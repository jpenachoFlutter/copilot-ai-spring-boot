---
name: flink-agents-review
description: Review checklist for GST Apache Flink Agents jobs — version/contract fidelity, packaging and classpath, keys and state, exactly-once and side effects, LLM/tool safety and cost, FKO/Olympus deployment, observability and test evidence. Use when reviewing a diff, branch or PR that touches Flink Agents code, build files, Dockerfile or FlinkDeployment chart.
---

# Flink Agents review (GST)

Use with `flink-agents-gst` (GST rules) and `flink-agents-dev` (framework contracts). Every finding needs evidence:
a `file:line`, a command output, or a rule from one of those skills or the **release** docs of the target version.

## 0. Establish the contract first

Before judging code, record:
- Agents version, Flink version (build file, Dockerfile `FROM`, `flinkVersion` in the CR) and whether they agree.
- API/language (YAML / Python / Java) and build tool.
- Selected Resources (chat model, embeddings, vector store, MCP) and the integrations declared.
- Consistency target: at-least-once vs exactly-once output; action state store or idempotency plan.

If these can't be determined, that is the first finding.

## 1. Version and contract fidelity — usually Critical
- APIs, annotations, config keys and YAML fields exist **in the target release** (check the `release-<ver>` tag / release docs, not `main`).
- YAML validates against the matching schema; unknown fields are not silently ignored.
- Agents version ↔ dist jar Flink minor ↔ Flink image ↔ `flinkVersion` ↔ PyFlink version all match.
- Flink version is accepted by the cluster's FKO CRD enum.
- No features documented only on `main` (e.g. 0.4 action-state key format) used against an older release.

## 2. Packaging and classpath
- `flink-agents-*` and Flink core artifacts are `provided` / `compileOnly` — never shaded into the job jar.
- Dist artifact / `flink-agents-ide-support` not used as the compile dependency.
- Only integrations actually used are declared; each one is present in the release's dist (or added to `/opt/flink/lib`).
- Connectors either shaded **or** in `/opt/flink/lib` — not both; no duplicate Kafka/Jackson/Netty on the classpath.
- Java `release` ≤ image JDK (21); `--add-exports=java.base/jdk.internal.vm=ALL-UNNAMED` in `env.java.opts.all` (and tests/local run) on JDK 21+.
- Python: Python 3.10–3.12, `flink-python` jar in `lib`, requirements pinned and available on TaskManagers.

## 3. Job wiring
- `AgentsExecutionEnvironment.getExecutionEnvironment(env)` with a real `StreamExecutionEnvironment`; no local list APIs in jobs or tests posing as integration tests.
- `keyBy` on a stable business key; deterministic key serializer; no `hashCode`-of-mutable-object keys.
- Output and errors routed: failed input runs to a DLQ/side output with the input key, not dropped.
- Watermarks/ordering assumptions documented when actions depend on ordering per key.

## 4. State, consistency and side effects — usually Critical/Important
- Checkpointing enabled with a sensible interval; sinks transactional when exactly-once output is claimed.
- Side-effecting actions/tools (writes, payments, notifications, external APIs) are either covered by an action state store (`actionStateStoreBackend`, one dedicated topic/table per logical agent operator) or are idempotent with an explicit idempotency key.
- Action state topic not shared between operators/jobs; Kafka store topic settings match the documented retention/compaction rules for the release.
- **Renamed actions, changed key types, changed event classes** → state compatibility: flag unless a savepoint migration plan / `allowNonRestoredState` decision is documented.
- State size bounded (TTL or pruning); no unbounded memory/chat history per key.

## 5. LLM, tools and MCP
- Every model/tool/MCP call has a timeout; retries only for idempotent operations; backoff bounded.
- Max tokens / temperature / model id configured explicitly, not left to provider defaults that change.
- Prompts contain no secrets or unnecessary PII; logs don't print prompts/responses with PII.
- Model output treated as untrusted: validated/parsed with schema before driving tools or sinks; tool arguments checked (prompt-injection → tool misuse).
- Tools are least-privilege (read-only where possible); MCP servers pinned and authenticated.
- No invented business logic: placeholders (`TODO_REQUIRED_*`, `UnsupportedOperationException`) are either resolved or explicitly listed.
- Cost: token counters observable; no per-event calls that could be batched or cached when the plan says so.

## 6. Secrets and security
- No API keys, passwords or tokens in code, `flinkConfiguration`, job args, values files or YAML agent definitions.
- Secrets via `ExternalSecret` → `secretKeyRef` env; Bedrock/S3 via IRSA service account.
- `security.ssl.internal.*` considered for sensitive data; images pinned by digest from Forge Store.

## 7. Deployment (Dockerfile / FlinkDeployment)
- `FROM flutter.jfrog.io/container/flink:<ver>-java21@sha256:…`; no `ENTRYPOINT`/`CMD` override; no Jib.
- Job jar **not** in `/opt/flink/usrlib`; `jarURI: local:///opt/<tla>/<app>.jar` matches the `COPY` path.
- Dist jar in `/opt/flink/lib` and matches the Agents/Flink versions.
- `upgradeMode: savepoint`; checkpoint/savepoint/HA dirs on the team S3 bucket; Flink 2.x key names (`execution.checkpointing.*`), not removed `state.checkpoints.dir` / `state.savepoints.dir`.
- RocksDB for non-trivial state; resources/slots/parallelism consistent; `fsGroup: 9999`.
- No `FlinkBlueGreenDeployment`; no session cluster for production jobs.

## 8. Observability
- Prometheus reporter on 9249, `PodMonitor` targeting the `metrics` port, `k8s.grafana.com/job` annotation.
- Dashboards/alerts cover restarts, checkpoint failures/age, back-pressure, source lag, event throughput, chat-model retries, tokens (input-run and LLM/tool failure ratios only on releases that ship them).
- Agent metric names match the `flink-agents-gst` §7 table for the chosen release (label-based `action`/`model`, `operator_name="action_execute_operator"`, no `_total`) or were confirmed in Grafana. Flag `main`-only metrics (`numOfInputRuns*`, `numOfLlmCallsFailed`, …) on 0.3.x as **Critical** (always-empty panels and alerts).

## 9. Tests and evidence
- Unit tests for actions/tools/prompt builders, positive and negative (timeouts, malformed model output, provider errors).
- MiniCluster deployment test with a stub model; behaviour tests for representative inputs.
- Real-provider integration tests are opt-in (tagged), never default in CI.
- The PR description claims only the evidence level actually run.

## Severity guide

| Severity | Examples |
|----------|----------|
| Critical | API/key not in target release; Flink core shaded into job jar; secret in repo/config; non-idempotent side effect claimed exactly-once without action state store; jar in `usrlib`; version mismatch dist ↔ Flink |
| Important | Missing timeouts/retries bounds; action rename without migration; no DLQ; missing `add-exports`; metrics/alerts missing; only local-list tests |
| Code Smell | Unused integration, prompt strings scattered, magic config values, weak test names |
