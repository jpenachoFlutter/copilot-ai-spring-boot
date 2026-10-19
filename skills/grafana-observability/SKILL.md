---
name: grafana-observability
description: Query, dashboard and alert on GST Spring Boot services in Grafana Cloud (stacks ppbtradingtribe for STG/NXT and ppbtradingtribeprd for PRD) — datasource UIDs, GST label model, verified PromQL/LogQL recipes (RED, JVM, pod resources, Hikari, Kafka, logs), SLO burn-rate alerts, Argo Rollouts canary analysis, dashboards-as-code, and how to verify via the Grafana MCP tools. Use when investigating a service in Grafana, building a dashboard or alert, or checking that a service's telemetry arrived.
---

# Grafana Observability (Grafana side)

App instrumentation lives in `spring-observability`. Publishing/promoting dashboards via the API is the `grafana`
agent's job — this skill gives it correct queries.

## Stacks and datasources

| Env | Grafana stack | Clusters (`cluster` label) | `environment` label |
|-----|---------------|----------------------------|---------------------|
| STG / NXT | `ppbtradingtribe` | `gst-stg-euw1-app-1`, `grt-stg-euw1-app-1` | `dts` (some series `nxt`) |
| PRD | `ppbtradingtribeprd` | `gst-prd-euw1-app-1`, `grt-prd-euw1-app-1` | `prod` |

Same datasource UIDs in both stacks — dashboards are portable:

| UID | Type | Use |
|-----|------|-----|
| `grafanacloud-prom` | Prometheus (Mimir) | metrics (default) |
| `grafanacloud-logs` | Loki | logs |
| `grafanacloud-traces` | Tempo | traces |
| `grafanacloud-profiles` | Pyroscope | profiles |
| `grafanacloud-ngalertmanager` | Alertmanager | alert routing |

## Label model

| Label | Example | Notes |
|-------|---------|-------|
| `cluster` | `gst-stg-euw1-app-1` | always filter on it — namespaces repeat across clusters |
| `namespace` | `gst-ri-tennis-mapper-stg` | `<app>-<env>`; may host more than one app |
| `job` | `gst-ri-tennis-mapper` | app name on app metrics (from the PodMonitor) |
| `container`, `pod` | | cAdvisor / kube-state-metrics and Loki |
| `environment` | `dts` | env name |
| `uri`, `method`, `status`, `outcome`, `exception` | | Micrometer HTTP tags |

Loki streams have `cluster`, `namespace`, `container`, `job` (`namespace/container`), `service_name`,
`environment`, `stream`; structured metadata `detected_level`, `pod`.

## Known gaps in current GST telemetry (check before building panels)

Verified on STG — fix in the app/PodMonitor first, or the panel shows "No data":

| Missing | Effect | Fix |
|---------|--------|-----|
| `http_server_requests_seconds_bucket` | no p95/p99, no latency SLO | `percentiles-histogram` (`spring-observability` §1) |
| `jvm_memory_max_bytes`, `jvm_gc_pause_seconds_*` | no heap %, no GC pause | add to the PodMonitor keep-list; meanwhile use container memory vs limit and `jvm_gc_overhead` |
| Tempo traces / span metrics | no trace view, no service graph | OTel export (`spring-observability` §2) |
| JSON logs | can't `\| json`; no `traceId` | structured logging (`spring-observability` §3) |

Discover what actually exists before writing a query:

```
list_prometheus_metric_names   regex: "http_server_.*|jvm_.*|hikaricp_.*|gst_.*"
query_prometheus  count by (__name__) ({__name__=~"jvm_.*", cluster="<c>", namespace="<ns>"})
list_loki_label_values  label: namespace
```

## PromQL recipes (verified)

Use `$cluster`, `$namespace`, `$job` dashboard variables; `[2m]` minimum window for a 30s scrape, `$__rate_interval` in dashboards.

**Traffic (RPS)**
```promql
sum by (uri) (rate(http_server_requests_seconds_count{cluster="$cluster", namespace="$namespace", uri!~"/actuator.*"}[$__rate_interval]))
```

**Error ratio (5xx)** — `or vector(0)`, otherwise the ratio vanishes when no 5xx series exist:
```promql
(sum(rate(http_server_requests_seconds_count{cluster="$cluster", namespace="$namespace", uri!~"/actuator.*", status=~"5.."}[$__rate_interval])) or vector(0))
/
sum(rate(http_server_requests_seconds_count{cluster="$cluster", namespace="$namespace", uri!~"/actuator.*"}[$__rate_interval]))
```

**Latency — mean (works today)**
```promql
sum by (uri) (rate(http_server_requests_seconds_sum{cluster="$cluster", namespace="$namespace", uri!~"/actuator.*"}[$__rate_interval]))
/
sum by (uri) (rate(http_server_requests_seconds_count{cluster="$cluster", namespace="$namespace", uri!~"/actuator.*"}[$__rate_interval]))
```

**Latency — p95 (needs histogram)**
```promql
histogram_quantile(0.95, sum by (le, uri) (rate(http_server_requests_seconds_bucket{cluster="$cluster", namespace="$namespace", uri!~"/actuator.*"}[$__rate_interval])))
```

**Max latency (worst single request in the window)**
```promql
max by (uri) (http_server_requests_seconds_max{cluster="$cluster", namespace="$namespace", uri!~"/actuator.*"})
```

**Error log rate (metric, cheap)**
```promql
sum by (level) (rate(logback_events_total{cluster="$cluster", namespace="$namespace", level=~"error|warn"}[$__rate_interval]))
```

**Pod memory vs limit**
```promql
sum by (pod) (container_memory_working_set_bytes{cluster="$cluster", namespace="$namespace", container!="", container!="POD"})
/
sum by (pod) (kube_pod_container_resource_limits{cluster="$cluster", namespace="$namespace", resource="memory"})
```

**CPU throttling ratio**
```promql
sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{cluster="$cluster", namespace="$namespace", container!=""}[$__rate_interval]))
/
sum by (pod) (rate(container_cpu_cfs_periods_total{cluster="$cluster", namespace="$namespace", container!=""}[$__rate_interval]))
```

**JVM**
```promql
sum by (pod) (jvm_memory_used_bytes{cluster="$cluster", namespace="$namespace", area="heap"})
avg by (pod) (jvm_gc_overhead{cluster="$cluster", namespace="$namespace"})
sum by (pod) (jvm_threads_live_threads{cluster="$cluster", namespace="$namespace"})
avg by (pod) (process_cpu_usage{cluster="$cluster", namespace="$namespace"})
```

**Restarts / availability**
```promql
increase(kube_pod_container_status_restarts_total{cluster="$cluster", namespace="$namespace"}[1h])
kube_deployment_status_replicas_available{cluster="$cluster", namespace="$namespace"}
up{cluster="$cluster", namespace="$namespace"}
```

**Hikari**
```promql
max by (pod, pool) (hikaricp_connections_active{cluster="$cluster", namespace="$namespace"})
max by (pod, pool) (hikaricp_connections_pending{cluster="$cluster", namespace="$namespace"})
sum(rate(hikaricp_connections_timeout_total{cluster="$cluster", namespace="$namespace"}[$__rate_interval]))
```

**Kafka**
```promql
sum by (name, result) (rate(spring_kafka_template_seconds_count{cluster="$cluster", namespace="$namespace"}[$__rate_interval]))
max by (client_id, topic) (kafka_consumer_fetch_manager_records_lag_max{cluster="$cluster", namespace="$namespace"})
```

## LogQL recipes (verified)

```logql
# Volume by level (works on today's plain-text logs)
sum by (detected_level) (count_over_time({cluster="$cluster", namespace="$namespace"} [$__auto]))

# Errors and warnings
{cluster="$cluster", namespace="$namespace"} | detected_level=~"error|warn"

# Free-text search
{cluster="$cluster", namespace="$namespace", container="$container"} |= "Exception" != "HealthIndicator"

# With JSON logs (after structured logging is enabled)
{cluster="$cluster", namespace="$namespace"} | json | level="ERROR" | line_format "{{.message}} trace={{.traceId}}"
```

Always include `cluster` + `namespace` in the stream selector — label-less or regex-only selectors scan the whole tenant.

## TraceQL (once traces are exported)

```traceql
{ resource.service.name = "gst-ri-tennis-mapper" && status = error }
{ resource.service.name = "gst-ri-tennis-mapper" && duration > 500ms }
```

## Alerts

Grafana-managed alert rules, one folder per team, labels `team="gst"`, `severity`, `service`; annotations
`summary`, `description`, `runbook_url`, `dashboard_url`. Rule baseline per service:

| Alert | Expression (condition) | For | Severity |
|-------|------------------------|-----|----------|
| Service down | `sum(up{cluster, namespace, job}) == 0` | 2m | critical |
| High 5xx ratio | error-ratio recipe `> 0.05` | 5m | critical |
| Slow requests | mean latency recipe `> 0.5` (p95 once histograms exist) | 10m | warning |
| Pod restarting | `increase(kube_pod_container_status_restarts_total[15m]) > 2` | 0m | warning |
| Memory near limit | memory-vs-limit recipe `> 0.9` | 10m | warning |
| Hikari starvation | `hikaricp_connections_pending > 0` | 5m | warning |
| Consumer lag | `kafka_consumer_fetch_manager_records_lag_max > <N>` | 10m | warning |

**SLO burn rate** (availability SLO 99.9% ⇒ error budget 0.001). Fast burn pages, slow burn tickets:

```promql
# fast: 14.4× budget over 1h AND 5m
(
  (sum(rate(http_server_requests_seconds_count{cluster="$cluster", namespace="$namespace", status=~"5.."}[1h])) or vector(0))
  / sum(rate(http_server_requests_seconds_count{cluster="$cluster", namespace="$namespace"}[1h]))
) > (14.4 * 0.001)
and
(
  (sum(rate(http_server_requests_seconds_count{cluster="$cluster", namespace="$namespace", status=~"5.."}[5m])) or vector(0))
  / sum(rate(http_server_requests_seconds_count{cluster="$cluster", namespace="$namespace"}[5m]))
) > (14.4 * 0.001)
```

Slow burn: same shape with `[6h]`/`[30m]` and `6 * 0.001`. Latency SLO: ratio of `_bucket{le="0.25"}` to `_count`
(needs the `slo` bucket from `spring-observability`).

Create alerts in **STG first**, confirm they evaluate (state `Normal`, not `Error`/`NoData`), then promote to PRD with
the PRD cluster/namespace — via the `grafana` agent or the `alerting_manage_rules` MCP tool.

## Argo Rollouts canary analysis

Rollouts query Mimir through the in-cluster proxy `http://prometheus-proxy.monitoring`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: http-success-rate
spec:
  args:
    - name: namespace
  metrics:
    - name: success-rate
      interval: 1m
      count: 5
      failureLimit: 1
      successCondition: result[0] >= 0.99
      provider:
        prometheus:
          address: http://prometheus-proxy.monitoring
          query: |
            (sum(rate(http_server_requests_seconds_count{namespace="{{args.namespace}}", uri!~"/actuator.*", status!~"5.."}[2m])) or vector(0))
            /
            sum(rate(http_server_requests_seconds_count{namespace="{{args.namespace}}", uri!~"/actuator.*"}[2m]))
```

Guard the case of zero traffic (division yields no result → `inconclusive`); set `inconclusiveLimit` or add synthetic traffic.

## Dashboards as code

- Keep dashboard JSON in the service repo (`observability/dashboards/<service>.json`) — the Grafana UI is not the source of truth.
- Start from `references/spring-boot-service-dashboard.json`: variables `datasource`, `loki`, `cluster`, `namespace`;
  rows Golden signals → JVM/pod → Dependencies → Logs.
- Datasources by **variable**, never hardcoded numeric IDs; set `uid` and `title`, `"id": null`.
- Publish STG first, render-check every panel, then promote — hand this to the `grafana` agent.

## Verify loop (MCP tools)

The Grafana MCP servers expose read tools per stack (`…ppbtradingtribe…` for STG, `…ppbtradingtribeprd…` for PRD):
`query_prometheus` (`datasourceUid`, `expr`, `queryType: instant`, `startTime`/`endTime: now`), `query_loki_logs`
(`datasourceUid`, `logql`), `list_prometheus_metric_names`, `list_prometheus_label_values`, `list_loki_label_values`,
`search_dashboards`, `get_dashboard_summary`, `get_dashboard_panel_queries`, `alerting_manage_rules`, `list_incidents`.

For every panel/alert expression:
1. Run it as an instant query against the right stack with real label values.
2. Data → check the magnitude makes sense (ratios 0–1, seconds not ms).
3. No data → strip matchers one at a time; check the metric exists (`count by (__name__)`); fix the query or the app.
4. Only then add it to the dashboard / rule.
