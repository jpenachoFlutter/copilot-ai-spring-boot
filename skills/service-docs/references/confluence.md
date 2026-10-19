# Confluence references

Source-of-truth platform and practice docs. Link to them from service docs instead of copying their content.
Base URL: `https://fluttergroup.atlassian.net/wiki/spaces/<SPACE>/pages/<id>`. Re-check a page before quoting it — they change.

## Olympus platform (GPDP — GPPE User Docs)

| Topic | Page |
|-------|------|
| GPPE User Docs (root) | [GPDP/4292610657719](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4292610657719) |
| Olympus 101 | [GPDP/4292911497582](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4292911497582) |
| How to deploy applications via Olympus | [GPDP/4292680712236](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4292680712236) |
| Application requirements | [GPDP/4294790643970](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4294790643970) |
| Source code repository for Helm applications | [GPDP/4292685759170](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4292685759170) |
| Infrastructure and pipeline repository (`<repo>-infra`) | [GPDP/4292685431537](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4292685431537) |
| Argo CD Rollouts | [GPDP/4293435588678](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293435588678) |
| Probes for safe rolling updates | [GPDP/4293344133678](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293344133678) |
| Designing for pod disruption (HA, PDB) | [GPDP/4294790840484](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4294790840484) |
| DNS and ingresses | [GPDP/4292685496884](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4292685496884) |
| Secrets | [GPDP/4292685725728](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4292685725728) |
| Managing secrets with External Secrets Operator | [GPDP/4293479727124](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293479727124) |
| TLS/SSL root certificates | [GPDP/4292843667563](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4292843667563) |
| TLS/SSL certificates on Olympus | [GPDP/4294862536711](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4294862536711) |
| Stakater Reloader recommendations | [GPDP/4293346983945](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293346983945) |
| Ephemeral environments | [GPDP/4293160927311](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293160927311) |
| Self-learning resources | [GPDP/4293134942286](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293134942286) |

## Forge (build, CI, artifacts)

| Topic | Page |
|-------|------|
| Forge 101 | [GPDP/4293289574688](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293289574688) |
| Forge Flow | [GPDP/4293299372049](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293299372049) |
| Forge Build | [GPDP/4293299765251](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293299765251) |
| Forge Store | [GPDP/4293431918677](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293431918677) |
| FlutterTech ECR image repository | [GPDP/4292848255067](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4292848255067) |
| Forge onboarding and migration skills | [GPDP/4295212532095](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4295212532095) |

## Grafana and metrics on Olympus

| Topic | Page |
|-------|------|
| Grafana Cloud – EKS (UIs, ServiceMonitor example) | [GPDP/4292131749900](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4292131749900) |
| Metric scraping with Pod/Service Monitors (filtering) | [GPDP/4293662048312](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293662048312) |
| Grafana Global Services instance – HLD | [FGSC/4292509433857](https://fluttergroup.atlassian.net/wiki/spaces/FGSC/pages/4292509433857) |

## Observability and operations standard (FGSC)

| Topic | Page |
|-------|------|
| 3. Observability strategy: make services observable | [FGSC/4295220396075](https://fluttergroup.atlassian.net/wiki/spaces/FGSC/pages/4295220396075) |
| 3.1 Signals and when to use them | [FGSC/4295220363345](https://fluttergroup.atlassian.net/wiki/spaces/FGSC/pages/4295220363345) |
| 3.2 Telemetry standards (naming, labels, correlation, sampling) | [FGSC/4295217775027](https://fluttergroup.atlassian.net/wiki/spaces/FGSC/pages/4295217775027) |
| 3.3 Instrumenting with OpenTelemetry and Grafana Alloy | [FGSC/4295219445934](https://fluttergroup.atlassian.net/wiki/spaces/FGSC/pages/4295219445934) |
| 3.4 Dashboards and service health | [FGSC/4295219740807](https://fluttergroup.atlassian.net/wiki/spaces/FGSC/pages/4295219740807) |
| 3.5 Cost, privacy and cardinality guidelines | [FGSC/4295220199515](https://fluttergroup.atlassian.net/wiki/spaces/FGSC/pages/4295220199515) |
| 4.1 Alerting principles and alert design | [FGSC/4295220461592](https://fluttergroup.atlassian.net/wiki/spaces/FGSC/pages/4295220461592) |
| 4.2 SLO burn-rate alerting | [FGSC/4295217775048](https://fluttergroup.atlassian.net/wiki/spaces/FGSC/pages/4295217775048) |
| 4.3 Ownership, routing and on-call | [FGSC/4295220756503](https://fluttergroup.atlassian.net/wiki/spaces/FGSC/pages/4295220756503) |
| 4.4 Service runbook standard and template | [FGSC/4295220527188](https://fluttergroup.atlassian.net/wiki/spaces/FGSC/pages/4295220527188) |
| 4.5 Incident response and communication | [FGSC/4295218856206](https://fluttergroup.atlassian.net/wiki/spaces/FGSC/pages/4295218856206) |

## GST team examples (GTT)

| Topic | Page |
|-------|------|
| Dashboards and observability tools (tennis) | [GTT/4294461292662](https://fluttergroup.atlassian.net/wiki/spaces/GTT/pages/4294461292662) |
| User Catalogue Service – runbook (example) | [GTT/4295115768015](https://fluttergroup.atlassian.net/wiki/spaces/GTT/pages/4295115768015) |
| Incident playbook example: Grafana failed to export metrics | [GTT/4294864961799](https://fluttergroup.atlassian.net/wiki/spaces/GTT/pages/4294864961799) |

## Reading them from Copilot

Use the Confluence MCP tools: `getConfluencePage` (cloudId `6f23c509-f101-4087-ad2b-de50b55331f1`, `pageId`,
`contentFormat: markdown`) or `search` for new pages. Read-only — never edit Confluence from these agents.
