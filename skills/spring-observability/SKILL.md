---
name: spring-observability
description: Instrument GST Spring Boot 4.x / Java 25 services for Grafana Cloud on Olympus — Micrometer/Prometheus metrics on the management port, latency histograms and SLO buckets, custom metrics with low cardinality, @Observed, OpenTelemetry tracing, JSON logs with trace correlation for Loki, PodMonitor metric filtering (cost). Use when adding or fixing metrics, traces or logs in a Spring service, or when a Grafana panel has no data because the app does not emit it.
---

# Spring Observability (app side)

How the signals reach Grafana on Olympus:

| Signal | App emits | Collected by | Grafana datasource (uid) |
|--------|-----------|--------------|--------------------------|
| Metrics | `/actuator/prometheus` on port **8081** (`management`) | PodMonitor → cluster agent → Grafana Cloud Mimir | `grafanacloud-prom` |
| Logs | stdout (JSON) | cluster agent → Grafana Cloud Loki | `grafanacloud-logs` |
| Traces | OTLP | OpenTelemetry collector → Grafana Cloud Tempo | `grafanacloud-traces` |
| Profiles | (optional) Pyroscope agent | Grafana Cloud Pyroscope | `grafanacloud-profiles` |

Labels added by the platform to every series and stream: `cluster` (e.g. `gst-stg-euw1-app-1`, `gst-prd-euw1-app-1`),
`namespace` (`<app>-<env>`), `job`, `container`, `pod`, `environment`, `platform="olympus"`.
**Do not add these as Micrometer tags** — they would be duplicated. Query with `cluster` + `namespace` (+ `job`).

## 1. Metrics

### Dependencies (versions from the Spring Boot BOM)

```kotlin
// Gradle
implementation("org.springframework.boot:spring-boot-starter-actuator")
runtimeOnly("io.micrometer:micrometer-registry-prometheus")
```

```xml
<!-- Maven -->
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-actuator</artifactId></dependency>
<dependency><groupId>io.micrometer</groupId><artifactId>micrometer-registry-prometheus</artifactId><scope>runtime</scope></dependency>
```

### application.yml

```yaml
spring:
  application:
    name: gst-ri-tennis-mapper            # becomes the `application` tag
management:
  server:
    port: 8081                            # never exposed via Ingress
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  endpoint:
    health:
      probes:
        enabled: true
  metrics:
    tags:
      application: ${spring.application.name}
    distribution:
      # Required for p95/p99 panels and latency SLO alerts; without it only _count/_sum/_max exist
      percentiles-histogram:
        http.server.requests: true
      slo:
        http.server.requests: 100ms,250ms,500ms,1s   # exact buckets for SLO alerting
      minimum-expected-value:
        http.server.requests: 5ms
      maximum-expected-value:
        http.server.requests: 10s
```

Histograms multiply the series count (dozens of buckets per `uri` × `status` × `method`). Enable them only for timers
you chart or alert on, cap the range with `minimum/maximum-expected-value`, and drop what you don't use in the PodMonitor (§5).

### What you get for free

| Area | Metric (Prometheus name) |
|------|--------------------------|
| HTTP server | `http_server_requests_seconds_{count,sum,max,bucket}` — tags `uri`, `method`, `status`, `outcome`, `exception` |
| HTTP client (`RestClient` from the auto-configured builder) | `http_client_requests_seconds_*` — tags `client_name`, `uri` |
| JVM | `jvm_memory_used_bytes`, `jvm_memory_max_bytes`, `jvm_gc_pause_seconds_*`, `jvm_threads_live_threads`, `jvm_threads_states_threads` |
| Process | `process_cpu_usage`, `system_cpu_usage`, `process_uptime_seconds`, `application_ready_time_seconds` |
| DB pool | `hikaricp_connections_{active,idle,pending,max}`, `hikaricp_connections_acquire_seconds_*` |
| Logging | `logback_events_total{level}` |
| Kafka | `spring_kafka_listener_seconds_*`, `spring_kafka_template_seconds_*`, client metric `kafka_consumer_fetch_manager_records_lag_max` |
| Executors | `executor_active_threads`, `executor_queued_tasks` (for `ThreadPoolTaskExecutor` beans) |

Inject the auto-configured `RestClient.Builder` — `RestClient.create()` bypasses observation, so no client metrics or spans.

### Custom business metrics

```java
@Component
@RequiredArgsConstructor
public class MarketMetrics {

    private final MeterRegistry registry;

    public void marketSuspended(String sport) {          // sport: bounded set (tennis, golf, …)
        registry.counter("gst.market.suspended", "sport", sport).increment();
    }

    public <T> T timeMapping(String sport, Supplier<T> work) {
        return Timer.builder("gst.mapping.duration")
                .tag("sport", sport)
                .publishPercentileHistogram()           // only if you will chart p95/p99
                .register(registry)
                .record(work);
    }
}
```

Or declaratively — `@Observed` produces a timer **and** a span:

```java
@Observed(name = "gst.mapping", contextualName = "map-event", lowCardinalityKeyValues = {"sport", "tennis"})
public MappingRecord map(Event event) { … }
```

`@Observed` needs AspectJ on the classpath (`spring-boot-starter-aspectj` in Boot 4, formerly `spring-boot-starter-aop`).

Naming and cardinality rules:
- Dot-separated lowercase names with a `gst.` prefix; Prometheus renders `gst_market_suspended_total`.
- **Tag values must be bounded.** Never IDs (`canonicalId`, `userId`, `eventId`), timestamps, raw URLs or exception
  messages. One bad tag can create millions of series and a large Grafana Cloud bill.
- `Counter` for events, `Timer` for durations, `Gauge` for current state, `DistributionSummary` for sizes.
- Replace hand-rolled "execution time" logging aspects with a `Timer`/`@Observed` — logs are not metrics.

## 2. Tracing (OpenTelemetry)

```kotlin
implementation("org.springframework.boot:spring-boot-starter-opentelemetry")
```

```yaml
management:
  tracing:
    sampling:
      probability: ${TRACING_SAMPLING:0.1}   # 1.0 in dts, 0.05–0.1 in prd
  opentelemetry:
    tracing:
      export:
        otlp:
          endpoint: ${OTEL_EXPORTER_OTLP_TRACES_ENDPOINT}
```

- Spans are created automatically for HTTP server/client and `@Observed`. Kafka needs
  `spring.kafka.template.observation-enabled: true` and `spring.kafka.listener.observation-enabled: true`.
- The **OTLP collector endpoint on Olympus is platform-provided** — confirm it with the platform team
  (`#gp-plat-eng-intake`) and set it per env in `variants/<env>/values/values.yaml`. Until then keep
  `management.tracing.enabled: false` rather than pointing at a guessed endpoint.
- No PII in span attributes.

## 3. Logs (Loki)

Logs are shipped from **stdout**; there is no app-side Loki appender. Emit JSON so LogQL can use `| json`:

```yaml
logging:
  structured:
    format:
      console: ecs            # or logstash — one JSON object per line on stdout
```

- With tracing on, Boot adds `traceId`/`spanId` to every log event, so Grafana can jump log → trace and back.
- Plain text only for local runs (`human-logs` profile — see the `logging-patterns` skill).
- For error-rate panels and alerts prefer `logback_events_total{level="error"}` (a metric) over LogQL counting.
- No PII, tokens or full payloads at INFO.

## 4. Health

`/actuator/health/liveness` and `/readiness` on port 8081 back the probes. Add custom `HealthIndicator`s only for
dependencies whose failure should take the pod **out of traffic** (readiness group), never into liveness.

```yaml
management:
  endpoint:
    health:
      group:
        readiness:
          include: readinessState,db
```

## 5. PodMonitor and metric filtering (cost)

Scrape with a **PodMonitor** (template in `olympus-deploy`), not `prometheus.io/*` annotations. Once dashboards and
alerts exist, keep only the metric families they use:

```yaml
spec:
  podMetricsEndpoints:
    - port: management
      path: /actuator/prometheus
      interval: 30s
      metricRelabelings:
        - sourceLabels: [__name__]
          regex: "(http_server_requests_seconds_.*|http_client_requests_seconds_.*|jvm_memory_(used|max)_bytes|jvm_gc_pause_seconds_.*|jvm_threads_live_threads|process_cpu_usage|hikaricp_connections_.*|logback_events_total|spring_kafka_.*|kafka_consumer_fetch_manager_records_lag_max|gst_.*|up)"
          action: keep
```

Rate windows in Grafana must be ≥ 4 × scrape `interval` (`[2m]` for 30s).

## 6. Verify locally (before deploying)

```bash
./gradlew bootRun    # or ./mvnw spring-boot:run
curl -s localhost:8081/actuator/prometheus | grep -E '^(http_server_requests_seconds_bucket|gst_)' | head
curl -s localhost:8081/actuator/prometheus | grep -vc '^#'          # sample count; re-check after adding tags
curl -s localhost:8081/actuator/health/readiness
```

Unit-test custom meters with `SimpleMeterRegistry`:

```java
@Test
void countsSuspensions() {
    var registry = new SimpleMeterRegistry();
    new MarketMetrics(registry).marketSuspended("tennis");
    assertThat(registry.get("gst.market.suspended").tag("sport", "tennis").counter().count()).isEqualTo(1.0);
}
```

`@SpringBootTest` does not export metrics/tracing by default; opt in with `@AutoConfigureMetrics` /
`@AutoConfigureTracing` (Boot 4 replacements for `@AutoConfigureObservability`) when a test needs them.

After deployment, confirm in Grafana with the `grafana-observability` skill (series exist with the expected labels).
