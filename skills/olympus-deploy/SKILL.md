---
name: olympus-deploy
description: Deploying GST Spring Boot services to Olympus (Flutter's EKS + Argo CD platform) — Helm chart in the app repo, <repo>-infra repo with Argo CD apps and env variants, promotion flow, platform requirements (probes, PDB, SIGTERM, resources), External Secrets, TLS truststore, ingress-nginx/ExternalDNS, PodMonitor metrics, Stakater Reloader, Argo Rollouts. Use for anything Kubernetes/Helm/deploy related.
---

# Olympus Deployment (GST)

Source: GPPE "Olympus User Docs" (Confluence space GPDP). If something here conflicts with the live docs, the docs win.
Platform support: Slack `#gp-plat-eng-intake`.

## Repositories and flow

```
<app>-app  (source)                                   <app>-infra  (pipeline / GitOps)
├─ src/ …                                             ├─ argocd-apps/        entry point for Argo CD Applications
├─ Dockerfile                                         ├─ build-me/           Argo CD Project + Application (kustomize)
├─ resources/<repo-name>/   ← Helm chart              ├─ environments/       env-agnostic patches (image tag, chart targetRevision)
│   ├─ Chart.yaml                                     └─ variants/<env>/     env-specific config (values.yaml, DNS, replicas) — NOT promoted
│   ├─ values.yaml                                         └─ values/values.yaml
│   └─ templates/…
└─ .github/workflows (Forge Flow — see forge-flow-ci)
```

1. CI builds the image → `flutter.jfrog.io/grt-container-local/<image>:<version>` and the chart → `grt-helmoci-local`.
2. `notify-infrastructure-repo` (GitHub App `gs-olympus-infra`, secret `ORG_GS_GROUP_OLYMPUS_INFRA_SECRET`) dispatches
   `update-chart-and-image.yml` in `<repo>-infra` with `deploy_env`, image name/version and chart `<repo>-app`/version.
3. That workflow opens a PR updating the **lowest env** (GST: `qa` or `nxt`). Merge → `create-deployment-on-push` → Argo CD syncs.
4. A successful deployment triggers `on-deployment-status-update`, which opens the **promotion PR** to the next env (… → `stg` → `prd`).
   Promotion copies `environments/` patches only. `variants/<env>/` is never copied.

Use the user's `argocd` agent to inspect sync/health, and the `aws-secrets` agent for Secrets Manager entries.
Never `kubectl apply` or `helm install` directly against Olympus clusters. Everything goes through the infra repo PR flow.

Repo prerequisites (one-off, via org-config / Codebase Governor): the `ORG_GS_GROUP_OLYMPUS_INFRA_SECRET` org secret,
`runner-groups` for Forge runners (`grt`), and the Forge Store OIDC mapping. If any are missing, hand off to the Flutter `forge-onboarding` skill.

## Platform requirements (mandatory)

| Requirement | Spring Boot / chart implementation |
|-------------|------------------------------------|
| Tolerate eviction (Karpenter rotates nodes continuously) | Stateless pods; no in-memory-only state; idempotent consumers |
| Handle SIGTERM | `server.shutdown: graceful`, `spring.lifecycle.timeout-per-shutdown-phase: 20s` (< `terminationGracePeriodSeconds`, default 30s); Kafka listeners stop/close on shutdown |
| ≥ 2 replicas in prod + PDB `minAvailable: 1` | `replicaCount: 2` in `variants/prd`; **never** a PDB on a single-replica deployment (it blocks node drains) |
| Readiness + liveness (+ startup) probes | Actuator probe groups (below) |
| No persistent data on local disk | DB / S3 / PVC only; `/tmp` is scratch |
| CPU + memory requests | Always set `resources.requests`; memory limit = request for JVMs |
| Images only from JFrog (Forge Store) or FlutterTech ECR | `flutter.jfrog.io/...`; Docker Hub/ghcr/quay are blocked from nodes |
| Single-active workloads | Leader election (Lease RBAC) or Kafka consumer groups. Single-replica prod is unsupported |

## Spring Boot settings for Olympus

```yaml
server:
  port: 8080
  shutdown: graceful
management:
  server:
    port: 8081                # GST PodMonitors scrape the "management" port
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  endpoint:
    health:
      probes:
        enabled: true
      group:
        readiness:
          include: readinessState,db
  observations:
    key-values:
      application: ${spring.application.name}
spring:
  lifecycle:
    timeout-per-shutdown-phase: 20s
  threads:
    virtual:
      enabled: true
```

JVM options (Dockerfile `JAVA_TOOL_OPTIONS` or chart env):
`-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError -Djavax.net.ssl.trustStore=/etc/ssl/certs/keystore.p12 -Djavax.net.ssl.trustStorePassword=changeit`.
Olympus auto-mounts `/etc/ssl/certs/{ca-certificates.crt,keystore.p12,keystore.jks}` (public CAs plus Flutter internal CAs:
Vault, Betfair, FlutterGlobal, …) into every pod, so internal TLS works only with this truststore. Do not add the
`ignore-olympus-certs` annotation.

## Helm chart templates (resources/<repo-name>/templates)

**_helpers.tpl** (the label set used by every selector below: keep `app` in it)

```yaml
{{- define "app.labels" -}}
app: {{ .Values.name }}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
environment: {{ .Values.environment }}
{{- end }}
```

**deployment.yaml (core)**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.name }}
  labels: {{- include "app.labels" . | nindent 4 }}
  annotations:
    # Reload only on the app's own config/secret — never reloader.stakater.com/auto: "true"
    configmap.reloader.stakater.com/reload: "{{ .Values.name }}-config"
    secret.reloader.stakater.com/reload: "{{ .Values.name }}-secrets"
spec:
  replicas: {{ .Values.replicaCount }}
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxSurge: 1, maxUnavailable: 0 }
  selector:
    matchLabels: { app: {{ .Values.name }} }
  template:
    metadata:
      labels: {{- include "app.labels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ .Values.name }}
      terminationGracePeriodSeconds: 30
      securityContext: { runAsNonRoot: true, seccompProfile: { type: RuntimeDefault } }
      containers:
        - name: app
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - { name: http, containerPort: 8080 }
            - { name: management, containerPort: 8081 }
          envFrom:
            - configMapRef: { name: {{ .Values.name }}-config }
            - secretRef:    { name: {{ .Values.name }}-secrets }
          startupProbe:
            httpGet: { path: /actuator/health/liveness, port: management }
            periodSeconds: 5
            failureThreshold: 36          # up to 3 min to start
          readinessProbe:
            httpGet: { path: /actuator/health/readiness, port: management }
            periodSeconds: 10
            failureThreshold: 3
          livenessProbe:
            httpGet: { path: /actuator/health/liveness, port: management }
            periodSeconds: 10
            failureThreshold: 3
          resources:
            requests: { cpu: {{ .Values.resources.cpu }}, memory: {{ .Values.resources.memory }} }
            limits:   { memory: {{ .Values.resources.memory }} }
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: { drop: [ALL] }
          volumeMounts:
            - { name: tmp, mountPath: /tmp }
      volumes:
        - { name: tmp, emptyDir: {} }
```

**pdb.yaml** (render only when replicas ≥ 2)

```yaml
{{- if ge (int .Values.replicaCount) 2 }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: {{ .Values.name }}-pdb }
spec:
  minAvailable: 1
  selector: { matchLabels: { app: {{ .Values.name }} } }
{{- end }}
```

**service.yaml / ingress.yaml**: `ingressClassName: nginx` is the **only** valid class. Hostname pattern
`<app>.<valuestream>.<dts|prod>.<euw1|use2|apse2>.int.fluttergroup.com`. ExternalDNS registers it automatically, and the NLB terminates
TLS with a platform wildcard cert. Add `nginx.ingress.kubernetes.io/force-ssl-redirect: "true"`. For custom domains use the
`AcmCertificate` Crossplane claim, and for internet-facing traffic the `ExternalALB` composition (see the GPPE TLS docs).

**podmonitor.yaml** (preferred over scrape annotations — filter unwanted metrics here)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: {{ .Values.name }}-monitor
  labels: { app: {{ .Values.name }}, environment: {{ .Values.environment }} }
spec:
  selector:
    matchLabels: { app: {{ .Values.name }} }
  namespaceSelector:
    matchNames: [ {{ .Release.Namespace }} ]
  podMetricsEndpoints:
    - port: management
      path: /actuator/prometheus
      interval: 30s
      honorLabels: true
      metricRelabelings:
        - { sourceLabels: [__name__], regex: 'jvm_buffer_.*|tomcat_sessions_.*', action: drop }
```

For a keep-list matching the dashboards/alerts, see the `spring-observability` skill (§5).

**secrets** (External Secrets Operator → AWS Secrets Manager. **Never put a `Secret` in the chart or any GitHub repo**)

```yaml
apiVersion: olympus.crossplane/v1
kind: RoleSA                       # creates an IAM role + linked ServiceAccount (IRSA)
metadata: { name: {{ .Values.name }} }
spec:
  clusterName: {{ .Values.cluster.name }}
  namespace: {{ .Release.Namespace }}
  roleName: {{ .Values.name }}
  accountId: '{{ .Values.aws.accountId }}'
  region: {{ .Values.aws.region }}
  serviceAccount: {{ .Values.name }}
  policy: |
    { "Version": "2012-10-17", "Statement": [ { "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue","secretsmanager:DescribeSecret"],
      "Resource": "arn:aws:secretsmanager:*:*:secret:{{ .Values.name }}*" } ] }
---
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata: { name: {{ .Values.name }}-secrets-store }
spec:
  provider:
    aws:
      service: SecretsManager
      region: {{ .Values.aws.region }}
      auth: { jwt: { serviceAccountRef: { name: {{ .Values.name }} } } }
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: { name: {{ .Values.name }}-secrets }
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: SecretStore, name: {{ .Values.name }}-secrets-store }
  target: { name: {{ .Values.name }}-secrets, creationPolicy: Owner, deletionPolicy: Retain }
  dataFrom:
    - extract: { key: {{ .Values.name }} }     # one AWS secret ↔ one K8s Secret (GPPE recommendation)
```

Expose secret keys as env vars in the `SPRING_DATASOURCE_PASSWORD` style, or mount them and read them with
`spring.config.import: optional:configtree:/run/secrets/`.

**values.yaml** keys used above: `name`, `environment`, `replicaCount` (1 in lower envs, ≥ 2 in prd),
`image.repository` (`flutter.jfrog.io/grt-container-local/<image>`), `image.tag`, `resources.cpu|memory`,
`domainname`, `cluster.name`, `aws.accountId`, `aws.region`. Env-specific values live in
`<repo>-infra/variants/<env>/values/values.yaml`.

## Progressive delivery (optional)

Argo Rollouts is supported as a replacement for `Deployment` (canary with `setWeight`/`pause`/`analysis`, or blue-green with
`activeService`/`previewService`/`autoPromotionEnabled: false`). Use it only when the user asks.

## Verify loop

1. `helm lint resources/<repo>` and `helm template resources/<repo> -f <infra>/variants/<env>/values/values.yaml | kubeconform -strict -ignore-missing-schemas`.
2. Checklist: probes on `management`, requests set, PDB only when replicas ≥ 2, no `Secret` kinds, `ingressClassName: nginx`,
   image registry `flutter.jfrog.io`, Reloader annotations named (not `auto`).
3. After merge: the `argocd` agent reports the app as `Synced` + `Healthy` in the target env, and `/actuator/health/readiness` is `UP`.
4. On failure: inspect Argo CD events/pod logs (argocd/grafana agents), fix in the app chart or infra variant, re-run. At most 5
   attempts per distinct symptom before escalating to `#gp-plat-eng-intake` with the evidence.
