---
name: gst-conventions
description: Mandatory GST (Flutter) conventions for Java / Spring Boot services and libraries — group id com.flutter.gst, Spring Boot 4.x, Java 25, Gradle-or-Maven detection, Forge Flow CI, Forge Store (JFrog) and Olympus deployment. Load FIRST whenever creating, changing or reviewing Java/Spring code in a GST repository.
---

# GST Spring Boot Conventions

These rules apply to **all** Java / Spring Boot code generated or reviewed for GST. Other skills
(`spring-boot`, `java-modern`, `testing-patterns`, …) give detail; when they conflict, **this skill wins**.

## Platform baseline

| Item | Rule |
|------|------|
| Java | **25** (LTS). Toolchain / `release` = 25. Never lower an existing version. |
| Spring Boot | **4.x** (latest GA patch). Spring Framework 7, Security 7, Jakarta EE 11, Hibernate 7, Jackson 3, JUnit Jupiter 6. |
| Group id | **`com.flutter.gst`**. Base package `com.flutter.gst.<service>` (service name in lowercase, no dashes). |
| Artifact id | Project (repository root directory) name, unless the existing build already defines one. |
| Versioning | SemVer, managed by **release-please** from Conventional Commit PR titles. Never bump versions by hand on `main`. |
| Lombok | **Allowed** (see rules below). |
| Migration | Code still on Boot 3 / Java < 25 → load the `spring-boot-4-migration` skill before changing anything else. |

## Build tool — detect, never assume

1. `build.gradle(.kts)` / `settings.gradle(.kts)` / `gradlew` present → **Gradle** → load `gradle-build` skill.
2. `pom.xml` / `mvnw` present → **Maven** → load `maven-build` skill.
3. **New project (neither present): ASK the user "Gradle or Maven?"** with the `ask_user` tool. Do not pick one.
4. Never convert an existing project from one build tool to the other unless explicitly asked.
5. Always use the wrapper (`./gradlew`, `./mvnw`); never a globally installed `gradle`/`mvn`.

## Mandatory code rules

- **Constructor injection** only — no `@Autowired` on fields. With Lombok, `@RequiredArgsConstructor` + `private final` fields is the preferred form.
- **Records for DTOs** (request/response/event payloads). Use Lombok only for classes records cannot model (JPA entities, mutable config holders, builders for large objects).
- Lombok rules:
  - OK: `@RequiredArgsConstructor`, `@Getter`, `@Setter` (non-entity), `@Builder`, `@Slf4j`, `@Value` (only when a record will not do).
  - **Never `@Data`, `@EqualsAndHashCode` or `@ToString` on JPA entities** (lazy-loading, identity and recursion bugs). Write `equals`/`hashCode` on the id explicitly.
  - Lombok ≥ 1.18.40 (first release supporting JDK 25); let the Spring Boot BOM manage the version. Add `lombok.config` with `lombok.addLombokGeneratedAnnotation = true` so JaCoCo ignores generated code.
- **RestClient** (or `@HttpExchange` interfaces registered with `@ImportHttpServices`) for blocking HTTP — never `RestTemplate`; `WebClient` only in reactive apps.
- **Jakarta** namespaces only (`jakarta.persistence`, `jakarta.validation`) — never `javax.*`.
- **Jackson 3** (`tools.jackson.*`). Do not add `com.fasterxml.jackson.core:jackson-databind` to new code; annotations stay in `com.fasterxml.jackson.annotation`.
- Prefer **JSpecify** nullability (`@NullMarked` in `package-info.java`, `@Nullable` where needed) in new packages.
- `@ConfigurationProperties` records for grouped config; no `@Value` sprawl.
- `@RestControllerAdvice` + Problem Details (`spring.mvc.problemdetails.enabled: true`).
- `@Valid` on every `@RequestBody`; return `ResponseEntity` with precise status codes.
- `@Transactional(readOnly = true)` on service classes, `@Transactional` on mutating methods.
- Virtual threads on (`spring.threads.virtual.enabled: true`) for servlet apps.
- Secrets never in source, `application*.yml`, Helm values or GitHub — use External Secrets Operator (see `olympus-deploy`).

## Testing rules

- JUnit Jupiter 6 + AssertJ + Mockito. `@MockitoBean` / `@MockitoSpyBean` (never `@MockBean`).
- Positive **and** negative cases for every public behaviour.
- Integration tests with **Testcontainers 2** + `@ServiceConnection` (no `@DynamicPropertySource` for supported services).
- Slice tests need the Boot 4 per-module test starters (e.g. `spring-boot-starter-webmvc-test`, `spring-boot-starter-data-jpa-test`).
- `RestTestClient` (`@AutoConfigureRestTestClient`) for HTTP integration tests.
- JaCoCo XML report always produced (Forge Flow uploads it to Sonar).

## Delivery rules

- **CI** = Forge Flow reusable workflows on Forge runners (`runner: grt`) → load `forge-flow-ci`.
  Every `uses:` pinned to a full commit SHA with a `# vX.Y.Z` comment. No floating tags.
- **Artifacts / images** → Forge Store (`flutter.jfrog.io`): resolve from `grt-maven`, deploy to `grt-maven-local`,
  images to `grt-container-local`, Helm charts to `grt-helmoci-local`.
- **Base images** pulled through Forge Store (`flutter.jfrog.io/container/...`) and pinned by digest.
- **Deploy** = Olympus (EKS + Argo CD) through the `<repo>-infra` repo → load `olympus-deploy`.
  Olympus hard requirements: ≥2 replicas + PDB in prod, readiness/liveness probes, graceful SIGTERM handling,
  CPU/memory requests, no persistent local disk, images only from JFrog/ECR.
- Ports: app `8080`, actuator/management `8081` (probes + `/actuator/prometheus` scraped by a PodMonitor on port name `management`).
- Observability: Micrometer/Prometheus metrics, JSON logs on stdout, OTel traces → Grafana Cloud (`spring-observability`, `grafana-observability`).
- PR titles follow Conventional Commits (linted by `cc-lint-pr-title`). Use the `git-workflow` skill for branches/commits.
- Update `README.md` when behaviour, configuration or endpoints change.

## Before you finish any change

- [ ] Build passes with the wrapper (`./gradlew build` or `./mvnw verify`) on Java 25.
- [ ] Tests added/updated (positive + negative); all green.
- [ ] No `javax.*`, `@MockBean`, `RestTemplate`, field `@Autowired`, or Lombok `@Data` on entities introduced.
- [ ] No secrets or unpinned actions/images introduced.
