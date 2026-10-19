---
name: service-docs
description: Documentation standard for GST Spring Boot services on Olympus — README.md + docs/ layout, templates for overview, Argo CD applications per env, dependency services (DBs, Kafka topics, HTTP APIs, secrets), Grafana dashboards and alerts, runbook, configuration and ADRs, plus the commands to discover each fact from the code, the <repo>-infra repo, Argo CD and Grafana. Use when writing or refreshing service documentation.
---

# Service Documentation

Docs live **in the app repo** and are updated in the same PR as the change they describe.
Every fact must come from a source (code, infra repo, Argo CD, Grafana) — never from memory or guesswork.
Unknowns are written as `TODO(owner): …`, not invented.

## Layout

```
README.md                    short: what, quick start, links into docs/  (≤ ~150 lines)
docs/
├── architecture.md          context diagram (Mermaid), components, data flow
├── dependencies.md          upstream/downstream services, DBs, Kafka topics, external APIs, secrets (names only)
├── deployment.md            Argo CD applications per env, infra repo, promotion, rollback
├── observability.md         Grafana dashboards, alerts, key queries, logs, traces
├── configuration.md         properties / env vars per env (no values for secrets)
├── runbook.md               symptoms → checks → actions; on-call and escalation
└── adr/NNNN-title.md        architecture decisions (Context / Decision / Consequences)
```

Templates: `references/templates.md`. Platform/practice docs to link: `references/confluence.md`.
Keep each file current or delete it — stale docs are worse than none.

## Discovery: where each fact comes from

### Service identity and build
| Fact | Source |
|------|--------|
| Name, group, version | `settings.gradle(.kts)` / `build.gradle(.kts)` or `pom.xml`; `.release-please-manifest.json` |
| Java / Boot versions | toolchain + Boot plugin/parent version |
| CI pipelines | `.github/workflows/*.yml` (names, triggers, reusable workflow + pinned SHA) |
| Artifacts | Forge Store: `grt-maven-local`, `grt-container-local`, `grt-helmoci-local` (verify with the `artifact-verifier` skill) |
| Owners | `CODEOWNERS`, catalog file if present |

### Argo CD applications
| Fact | Source |
|------|--------|
| Applications per env | `<repo>-infra/argocd-apps/**` (Application/ApplicationSet manifests: name, project, destination cluster/namespace, source path) |
| Env-specific values (replicas, resources, ingress host) | `<repo>-infra/variants/<env>/values/values.yaml` |
| Deployed version | `<repo>-infra/environments/<env>/` patches (chart + image version) |
| Live state (read-only) | `argocd app get <app> --grpc-web -o json \| jq '{sync:.status.sync.status, health:.status.health.status, rev:.status.sync.revision, images:.status.summary.images}'` |
| Argo CD UIs | DTS `https://argocd.grt.dts.euw1.int.fluttergroup.com`, PRD `https://argocd.grt.prd.euw1.int.fluttergroup.com` — link as `<ui>/applications/<app>` |

Never sync, rollback or change anything to "check" — documentation work is read-only. Live operations → `argocd` agent.

### Dependency services
| Dependency | Where to look |
|------------|---------------|
| Databases | `spring.datasource.*`, `spring.data.*`, Flyway/Liquibase dirs, driver deps |
| Kafka | `spring.kafka.*`; `@KafkaListener(topics=…, groupId=…)`; `KafkaTemplate.send("topic"…)`; topic constants/properties |
| HTTP (outbound) | `@HttpExchange` interfaces, `RestClient` beans + base-url properties, OpenFeign clients |
| HTTP (inbound) | `@RestController` mappings, OpenAPI spec, Ingress hosts in the chart/variants |
| gRPC / Pulsar / Redis / S3 | starters in the build file + matching properties |
| Secrets | `ExternalSecret`/`SecretStore` in the chart: **AWS secret names and keys only, never values** |
| Certificates / truststore | chart truststore volume, `spring.ssl.bundle.*` |

Record for each: name, type, direction (in/out), env-specific endpoint property, owning team, failure impact, and the
metric/dashboard that shows its health.

```bash
grep -rnE '@KafkaListener|KafkaTemplate|@HttpExchange|RestClient|FeignClient|@GrpcClient' src/main/java
grep -rnE 'bootstrap-servers|url:|base-url|uri:|datasource' src/main/resources
grep -rn 'kind: ExternalSecret' -A30 resources/ | grep -E 'key:|property:|name:'
```

### Grafana dashboards and alerts
| Fact | Source |
|------|--------|
| Dashboards in code | `observability/dashboards/*.json` (title, uid) |
| Dashboards in Grafana | MCP `search_dashboards` (query = service name) on STG `ppbtradingtribe` and PRD `ppbtradingtribeprd`; `get_dashboard_summary` for panels |
| Links | `https://ppbtradingtribe.grafana.net/d/<uid>` (STG), `https://ppbtradingtribeprd.grafana.net/d/<uid>` (PRD) with `?var-namespace=<ns>&var-cluster=<cluster>` |
| Alerts | MCP `alerting_manage_rules` (list, filter by service/namespace): name, severity, condition, contact point |
| Key queries | `grafana-observability` skill — copy verified queries, not new ones |
| Telemetry gaps | "Known gaps" table in `grafana-observability` |

Verify every link resolves (dashboard exists in that stack) before writing it.

## Best practices

- **Audience first:** README for a newcomer (5 minutes to run it), docs/ for operators and maintainers.
- **Facts with provenance:** add `<!-- source: <file|command> -->` comments for generated tables so the next refresh is mechanical.
- **Tables over prose** for inventories (apps, dependencies, dashboards, alerts, config).
- **Diagrams as code:** Mermaid in markdown; no binary images that rot.
- **Per-env columns** (dts / nxt / prd) instead of separate pages.
- **No secrets, tokens, internal IPs or PII.** Secret *names* and AWS secret paths are fine.
- **Runbook entries are actionable:** symptom → dashboard/query → likely causes → action → escalate to whom.
- **Link, don't copy** platform docs — use the Confluence pages in `references/confluence.md` (Olympus GPPE, Forge,
  observability standard 3.x, alerting/on-call/runbook/incident 4.x); copy only the service-specific bit.
- **Runbook follows Flutter standard 4.4** (sections, stable anchors, review checklist) so Grafana alert
  `runbook_url` annotations can deep-link to a section.
- **Docs change with code:** a PR that adds a dependency, topic, endpoint, property, alert or env updates the docs in the same PR.
- **Markdown hygiene:** one H1 per file, relative links between docs, code blocks with language tags, lines readable in diffs.
- **Date stamp** volatile sections: `_Last verified: YYYY-MM-DD_`.

## Verify

```bash
# links between docs resolve
grep -rnoE '\]\((\./)?[^)#:]+\.md' README.md docs | sed -E 's/.*\]\((\.\/)?//' | sort -u
# no secrets slipped in
grep -rniE 'password|secret|token|apikey' README.md docs | grep -viE 'secret name|ExternalSecret|secretKey|TODO'
# markdown lint if available
npx --yes markdownlint-cli2 "README.md" "docs/**/*.md"
```
