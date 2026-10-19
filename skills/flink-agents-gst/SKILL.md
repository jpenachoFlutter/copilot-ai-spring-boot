---
name: flink-agents-gst
description: GST layer for planning and building Apache Flink Agents (event-driven LLM agent) jobs — version selection, Java/Python project shape with Gradle or Maven, baked Flink image on Forge Store, FlinkDeployment on Olympus via the Flink Kubernetes Operator and Argo CD, action-state store, secrets, metrics and tests. Use together with the upstream `flink-agents-dev` skill whenever a GST project depends on `org.apache.flink:flink-agents-*` or the `flink-agents` Python package.
---

# Flink Agents — GST layer

Two skills work together:

| Skill | Owns | Source |
|-------|------|--------|
| `flink-agents-dev` | Framework APIs, the gated interview, provider contract triage, YAML/Python/Java patterns, local MiniCluster verification | Upstream `apache/flink-agents` `dev/agent-skills/flink-agents-dev`, linked by `install.sh` at a pinned SHA |
| `flink-agents-gst` (this) | GST specifics: versions we run, build tool, packaging, image, Olympus/FKO deployment, secrets, observability | This repo |

**Load both.** Follow `flink-agents-dev` for *how to write the agent*; this skill wins on *how it ships and runs at GST*.
If `flink-agents-dev` is missing (`~/.copilot/skills/flink-agents-dev`), tell the user to run `./install.sh` instead of
improvising framework APIs. Reviews use `flink-agents-review`.

## Scope exceptions to `gst-conventions`

Flink jobs are **not** Spring Boot services. From `gst-conventions` keep: group `com.flutter.gst`, base package
`com.flutter.gst.<app>`, Conventional Commits + release-please, SHA-pinned Forge Flow CI, Forge Store, no secrets in the
repo, Argo CD delivery. Override:

| GST default | Flink Agents job |
|-------------|------------------|
| Java 25 | **Java release ≤ the Flink image JDK** — official `flink` images stop at `-java21`, so compile with `release 21` (Agents baseline is JDK 11) |
| Spring Boot 4, starters, actuator | None. Plain Flink `main` + `AgentsExecutionEnvironment` |
| Fat runnable jar / layered Boot image | Shaded job jar baked into a `flink:<ver>-java21` image |
| Helm `Deployment` + probes on 8081 | `FlinkDeployment` CR reconciled by FKO; metrics on 9249 |
| `@ConfigurationProperties` | Job args / env vars / Agents config |

On JDK 21+ add `--add-exports=java.base/jdk.internal.vm=ALL-UNNAMED` to **`env.java.opts.all`** (continuation-based
async between actions; without it async actions degrade to synchronous). Java-native MCP needs JDK 17+.

## 1. Pick versions (gate — confirm with the user)

Resolve live, never from memory:

```bash
# Flink Agents releases (Java) and PyPI
curl -s https://repo1.maven.org/maven2/org/apache/flink/flink-agents-api/maven-metadata.xml | grep -oE '<version>[^<]+' | cut -d'>' -f2
curl -s https://pypi.org/pypi/flink-agents/json | jq -r '.releases | keys[]'
# Which Flink minors have a dist jar for the chosen Agents version
for m in 1.20 2.0 2.1 2.2 2.3; do curl -so /dev/null -w "$m %{http_code}\n" \
  "https://repo1.maven.org/maven2/org/apache/flink/flink-agents-dist-flink-$m/$AGENTS/flink-agents-dist-flink-$m-$AGENTS.jar"; done
# Flink versions accepted by the FKO installed on the target cluster
kubectl get crd flinkdeployments.flink.apache.org -o json \
  | jq -r '.spec.versions[].schema.openAPIV3Schema.properties.spec.properties.flinkVersion.enum'
# Base image digest (official image, pulled through Forge Store)
curl -s "https://hub.docker.com/v2/repositories/library/flink/tags/$FLINK-java21" | jq -r .digest
```

Snapshot (2026-10-19, re-verify): Agents **0.3.1** latest (dist for Flink 2.2 and 2.3); Flink 2.3.0 / 2.2.1 / 2.1.3;
FKO 1.16.1 accepts up to `v2_4`, FKO 1.13 stops at `v2_2`. **Safe default to propose: Agents 0.3.1 + Flink 2.2.1
(`flinkVersion: v2_2`)** unless the cluster's FKO CRD lists newer.

Rules:
- Agents version, Flink minor, dist jar and PyFlink version must all match. The YAML API exists from 0.3.0; 0.1.x/0.2.x have no YAML.
- `flink-agents-dev` picks YAML schemas from `assets/yaml-contracts.yaml`; a version not listed there (e.g. 0.3.1 at the pinned SHA) needs the schema from the `release-<ver>` tag before generating YAML.
- Upstream `main` docs may describe unreleased features (e.g. action-state key format changed for 0.4). Verify every feature against the **release docs** (`https://nightlies.apache.org/flink/flink-agents-docs-release-<major.minor>/`).
- Python: 3.10–3.12 (3.12 needs Flink 2.1+ and Agents 0.3+). Cross-language async needs Flink 1.20.5+/2.0.2+/2.1.3+/2.2.1+/2.3+.

## 2. Choose API and language

Ask through the `flink-agents-dev` gates: YAML, Python or Java. GST guidance to offer, not impose:
- **Java** fits GST tooling best (Gradle/Maven, Forge Flow `java-build-scan-publish`, Sonar, JaCoCo).
- **Python/YAML** needs a PyFlink image (Python + `flink-python` jar moved from `opt` to `lib`; FKO `entryClass: org.apache.flink.client.python.PythonDriver`); CI is custom. Use only if the team owns Python.
- LLM / embedding / vector-store / MCP providers are a **user decision**. Offer only integrations in the chosen release's `dist/pom.xml`. Note for the user: Bedrock can authenticate with the pod's IRSA role (no static key); other providers need an API key from Secrets Manager.

## 3. Project shape (Java)

```
<app>/
├── build.gradle.kts | pom.xml
├── Dockerfile
├── src/main/java/com/flutter/gst/<app>/
│   ├── <App>Job.java          # main: sources → AgentsExecutionEnvironment → sinks
│   ├── agent/                 # Agent classes, actions, custom events
│   ├── tools/                 # tool methods (bounded, idempotent where possible)
│   ├── model/                 # input/output types (serializable, stable keys)
│   └── config/                # JobConfig parsed from args/env (secrets only from env)
├── src/test/java/...          # unit + MiniCluster tests
└── chart/ (or infra repo)     # FlinkDeployment, PodMonitor, ExternalSecret, S3Bucket, ServiceAccount
```

**Build tool — detect, never assume** (`gradle-build` / `maven-build`). New project → ask "Gradle (Kotlin DSL) or Maven?".

Dependencies (upstream contract): `flink-agents-api`, `-plan`, `-runtime`, only the integrations actually selected,
`flink-streaming-java`, `flink-clients`, `flink-table-api-java-bridge` — all **`provided` (Maven) / `compileOnly` +
`testImplementation` (Gradle)**. Never use the dist artifact or `flink-agents-ide-support` as the compile contract.

GST packaging decision (state it in the plan):
- The **image** provides Flink + `flink-agents-dist-flink-<minor>-<ver>.jar` in `/opt/flink/lib` (the dist bundles api/plan/runtime and the built-in integrations of that release). Fetch it through Forge Store with the build tool, not `curl` in the Dockerfile.
- **Connectors** (`flink-connector-kafka:<x>-<flink-minor>`, Pulsar, …) are not in the image: shade them into the job jar **or** copy them into `/opt/flink/lib`. Pick one; never both (duplicate classes).
- Local runs: Maven `exec:exec` with `classpathScope=compile` (upstream); Gradle `JavaExec` over `compileClasspath + runtimeClasspath`. Never `exec:java`.

Templates: [`references/gst-flink-templates.md`](references/gst-flink-templates.md) (Gradle, Maven deltas, Dockerfile,
FlinkDeployment, PodMonitor, ExternalSecret, CI).

## 4. Correctness rules GST enforces

- **Remote-style env only:** `AgentsExecutionEnvironment.getExecutionEnvironment(env)` with a real `StreamExecutionEnvironment`; local list APIs are not for jobs or tests.
- **Never invent business logic.** Unknown prompts/tools/actions → scaffold with `UnsupportedOperationException` / `NotImplementedError` and `TODO_REQUIRED_*` placeholders, listed in the report.
- **Keys:** `keyBy` on a stable business key with a deterministic serializer. Key type and action names are part of state — renaming an action or changing the key type re-executes or orphans state (needs a savepoint migration plan).
- **Exactly-once:** sink output is exactly-once only with checkpointing + transactional sinks. **Action** effects (LLM calls, tool side effects) are exactly-once only with an **action state store** (`actionStateStoreBackend: kafka|fluss`), one dedicated topic/table per logical agent operator. Without it, every side effect must be idempotent (key = input key + action + sequence).
- **Timeouts/retries:** bound every model/tool/MCP call; retry only idempotent calls; failed input runs go to metrics and a DLQ/side output, never swallowed.
- **Prompt hygiene:** no PII or secrets in prompts or logs; treat model output as untrusted (validate before tool calls/sinks).
- **Cost:** cap max tokens per request; track `promptTokens` / `completionTokens`.

## 5. Olympus deployment (FKO + Argo CD)

Load `olympus-deploy` for Argo CD / app-of-apps and hand the chart to `spring-olympus-specialist`. Flink rules:

- **Application cluster**: one `FlinkDeployment` per job in the team namespace; FKO runs in `flink-operator-system`.
- **Baked image** `FROM flutter.jfrog.io/container/flink:<ver>-java21@sha256:<digest>`, published to Forge Store. Keep the base `docker-entrypoint.sh` (no `ENTRYPOINT`/`CMD` override, no Jib).
- **Job jar NOT in `/opt/flink/usrlib`** — FKO standalone mounts an empty dir there on the JobManager. Use `/opt/<tla>/<app>.jar` with `jarURI: local:///opt/<tla>/<app>.jar`.
- Checkpoints/savepoints on the team S3 bucket (Crossplane `S3Bucket`, IRSA, SSE-KMS); RocksDB incremental; `upgradeMode: savepoint`; HA `kubernetes` with `high-availability.storageDir` on S3.
- Flink 2.x keys: `execution.checkpointing.dir`, `execution.checkpointing.savepoint-dir`, `execution.checkpointing.incremental` (`state.checkpoints.dir`, `state.savepoints.dir`, `state.backend.incremental` no longer exist).
- Secrets: `ExternalSecret` from AWS Secrets Manager → `secretKeyRef` env vars in the pod template. Never in `flinkConfiguration`, job args or values files.
- JM↔TM RPC is plaintext by default — enable `security.ssl.internal.*` when the job handles sensitive data.
- `FlinkBlueGreenDeployment` is experimental (duplicates output, treats replica changes as upgrades) — don't use.
- Spot/Karpenter disruption restarts jobs: checkpoint interval and restart strategy must tolerate it.

Ops to share (link the runbook): `kubectl get flinkdeployments -n <ns>`; restart via `restartNonce`; force restart
`job.state: suspended → running`; redeploy from savepoint with `initialSavepointPath` + `savepointRedeployNonce`;
"Found 0 checkpoints in KubernetesStateHandleStore" = state-recovery failure.

## 6. CI (hand off to `spring-devops-engineer`, skill `forge-flow-ci`)

Forge Flow `java-build-scan-publish.yml` (Option B) with `java-version: '21'`, `java-build-tool: gradle|maven`,
`containerfile-location` pointing at the Flink Dockerfile, `container-publish: true`. Same SHA-pinning rules. The build
command must produce the shaded jar **and** stage the dist jar before the image build.

## 7. Observability (hand off to `spring-observability-engineer`)

- Reporter: `metrics.reporters: prom`, `metrics.reporter.prom.factory.class: org.apache.flink.metrics.prometheus.PrometheusReporterFactory`, port `9249`; `PodMonitor` on the `metrics` port; pod annotation `k8s.grafana.com/job: <app>`.
- Flink health (metric names verified in Grafana STG; labels `cluster`, `namespace`, `job_name`):
  ```promql
  sum by (namespace) (increase(flink_jobmanager_job_numRestarts{cluster="$cluster", namespace="$ns"}[1h]))
  max by (namespace) (flink_taskmanager_job_task_operator_KafkaSourceReader_KafkaConsumer_records_lag_max{namespace="$ns"})
  max by (job_name) (flink_jobmanager_job_lastCheckpointDuration{namespace="$ns"})
  sum by (job_name) (increase(flink_jobmanager_job_numberOfFailedCheckpoints{namespace="$ns"}[1h]))
  max by (task_name) (flink_taskmanager_job_task_backPressuredTimeMsPerSecond{namespace="$ns"})
  ```
- Agent metrics (operator scope; operator name = agent name): `numOfEventProcessed`, `numOfActionsExecuted`,
  `numOfInputRunsSucceeded/Failed`, `numOfPendingInputEvents`, `numOfActiveInputRuns`, `numOfLlmCallsFailed`,
  `numOfToolCallsFailed`, token counters under `action.chat_model_action.model.<model>`; custom ones via
  `getAgentMetricGroup()`. Their Prometheus names are **not yet observed** at GST — confirm with the `grafana` agent
  (metric names matching `flink_taskmanager_job_task_operator_.*numOf.*`) before building panels or alerts.
- Alerts: restarts > 0 over 15m, failed checkpoints, checkpoint age, input-run failure ratio, LLM call failure ratio, token burn rate.

## 8. Tests and evidence levels

| Level | What proves it | How |
|-------|----------------|-----|
| Unit | Actions, tools, prompt builders with fakes; positive + negative | `./gradlew test` / `./mvnw test` |
| Deployment | Job graph builds and runs on MiniCluster with a stub model | upstream `references/verification.md` |
| Behaviour | Expected outputs for representative inputs, incl. failures/timeouts | MiniCluster + Testcontainers (Kafka) |
| Integration | Real provider in a sandbox account — **only with user approval** (cost, data) | tagged/manual test |

Claim only the level actually run. A local run is never "deployed".

## 9. Plan template (architect output)

```markdown
## Flink Agents plan: <app>
**Versions:** Agents <x> · Flink <y> (FKO flinkVersion v<y>) · Java release 21 · Python <z|n/a> — evidence: <commands run>
**API / language:** YAML|Python|Java — why
**Build:** Gradle|Maven (detected|chosen) · connectors: shaded|image lib
**Flow:** source(s) → keyBy(<key>) → agent(s) [actions, tools, resources] → sink(s) + DLQ
**Resources:** chat model <provider/model> · embeddings · vector store · MCP — each confirmed by the user
**Consistency:** checkpoint interval · sink semantics · action state store <topic|table|none + idempotency plan>
**State & upgrades:** key type · frozen action names · savepoint/upgrade strategy
**Secrets:** <Secrets Manager names> → ExternalSecret → env
**Deployment:** image repo · JM/TM sizing, slots, parallelism · S3 bucket · service account/IRSA
**Observability:** dashboards and alerts
**Tests:** unit · MiniCluster · behaviour (· integration?)
**Open questions / TODO_REQUIRED_*:** …
**Tasks:** ordered, each with an acceptance check and owner agent
```

## References

- Upstream skill: `~/.copilot/skills/flink-agents-dev/`; docs https://nightlies.apache.org/flink/flink-agents-docs-release-0.3/ (match the release)
- Olympus FKO blueprint (GPDP): https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293415174158
- ADR-OLYMPUS-012 Flink on Olympus (GPDP): https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293371691121
- GBSD baked image / usrlib pitfall (GTT): https://fluttergroup.atlassian.net/wiki/spaces/GTT/pages/4294972145780
- FKO troubleshooting (GTT): https://fluttergroup.atlassian.net/wiki/spaces/GTT/pages/4293245567428
- FKO on-call (GTT): https://fluttergroup.atlassian.net/wiki/spaces/GTT/pages/4292424926504
- KEDA cron scaling runbook (GTT): https://fluttergroup.atlassian.net/wiki/spaces/GTT/pages/4295064191084
- Reference implementation `Flutter-Global/gbsd`: `decorator/Dockerfile`, `resources/gbsd-helm/templates/flinkDeployment.yaml`, `.github/workflows/publish-image-group-cloud.yml`
