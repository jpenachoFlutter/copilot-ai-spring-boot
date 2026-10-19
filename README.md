# Copilot CLI — Spring Boot toolkit for Flutter GST

GitHub Copilot CLI **agents**, **skills** and **instructions** for building, migrating, shipping and deploying
GST Spring Boot services and libraries:

| Baseline | |
|----------|---|
| Runtime | Spring Boot **4.x**, Java **25** (LTS), Jakarta EE 11, Jackson 3, Spring Security 7, Hibernate 7 |
| Group id | `com.flutter.gst` |
| Build | Gradle (Kotlin DSL) **or** Maven: detected per project; for new projects the agent asks |
| Tests | JUnit 6, Mockito, Testcontainers 2, `RestTestClient` |
| CI | Forge Flow reusable workflows; **every** `uses:` pinned to a commit SHA |
| Artifacts | Forge Store (`flutter.jfrog.io`) |
| Deploy | Olympus (EKS + Argo CD) via Helm chart + `<repo>-infra` repo |

Derived from [piomin/claude-ai-spring-boot](https://github.com/piomin/claude-ai-spring-boot) (Apache-2.0).

## Install

```bash
./install.sh            # symlink agents/, skills/, instructions/ into ~/.copilot (or $COPILOT_HOME)
./install.sh --copy     # copy instead of symlink (re-run after every git pull)
./install.sh --dry-run  # show what would happen
./install.sh --uninstall
```

Existing files with the same name are moved to `*.bak.<timestamp>`. Restart Copilot CLI and check `/agent`, `/skills`
and `/instructions`. If the agents or skills do not show up with symlinks, re-install with `--copy`.

## Agents (`agents/`)

| Agent | Use for |
|-------|---------|
| `spring-boot-engineer` | Implement features, scaffold services, run the Boot 4 / Java 25 migration |
| `spring-code-reviewer` | Read-only review of diffs/PRs (Boot 4 leftovers, Lombok misuse, delivery readiness) |
| `spring-security-engineer` | Spring Security 7, JWT/OAuth2, validation, secrets, TLS truststores |
| `spring-devops-engineer` | Forge Flow CI/CD workflows, SHA pinning, release-please, Dependabot |
| `spring-docker-expert` | Digest-pinned Temurin 25 images from Forge Store, layered jars, non-root |
| `spring-olympus-specialist` | Helm chart, infra repo, promotion, Olympus requirements |
| `spring-observability-engineer` | Metrics, traces, logs, dashboards, alerts and investigation in Grafana Cloud |
| `spring-documentation-engineer` | README + docs/: Argo CD apps, dependencies, Grafana dashboards/alerts, runbook (Flutter 4.4) |

Every agent runs an observe → act → verify loop with an attempt ledger, a 5-iteration budget per symptom and explicit
exit criteria/escalation. They integrate with the user-level `git-workflow`, `jira-reader` and `artifact-verifier` skills
and the `argocd`, `grafana` and `aws-secrets` agents when those are installed.

## Skills (`skills/`)

| Skill | Content |
|-------|---------|
| `gst-conventions` | **Load first.** Platform baseline, build-tool detection, Lombok rules, delivery rules, finish checklist |
| `gradle-build` / `maven-build` | Reference `build.gradle.kts` / `pom.xml`, wrappers, Forge Store config, release-please |
| `spring-boot-4-migration` | Boot 2/3 + Java 17/21 → Boot 4 + Java 25 (OpenRewrite + manual checklist) |
| `forge-flow-ci` | Pinned SHA table, GST templates vs direct Forge Flow, Dockerfile template |
| `olympus-deploy` | Infra repo flow, mandatory requirements, Helm templates, External Secrets, PodMonitor |
| `spring-observability` | Micrometer metrics, histograms, custom meters, OpenTelemetry, JSON logs, PodMonitor cost filtering |
| `service-docs` | Docs layout, discovery commands, templates (runbook per Flutter 4.4), Confluence reference index |
| `grafana-observability` | Grafana Cloud stacks and datasources, GST labels, verified PromQL/LogQL, alerts, SLOs, dashboard template |
| `spring-boot` | Web, data, security, cloud and testing references |
| `java-modern` | Java 25 features (records, patterns, virtual threads, scoped values, gatherers…) |
| `jpa-patterns`, `testing-patterns`, `logging-patterns`, `code-quality`, `design-patterns` | Focused guidance |

## Instructions (`instructions/`)

`gst-spring.instructions.md` is a modular user-level instruction (applied to Java/build/CI/chart files) that points
Copilot at `gst-conventions` and the agents above.

## Maintenance

- **Pinned SHAs:** `skills/forge-flow-ci/SKILL.md` contains the SHA table and a script to re-resolve it. Refresh it when Forge Flow or
  the GST templates release.
- **Versions:** the version tables in `gradle-build` / `maven-build` (Boot, Gradle, Maven, Lombok, JaCoCo, Testcontainers).
- **Base image digest:** in `forge-flow-ci` (Dockerfile template).
- **Olympus docs** (GPPE User Docs, Confluence GPDP) are the source of truth for `olympus-deploy`.
- **Confluence index:** `skills/service-docs/references/confluence.md` (Olympus, Forge, observability 3.x, alerting/on-call/runbook 4.x).
