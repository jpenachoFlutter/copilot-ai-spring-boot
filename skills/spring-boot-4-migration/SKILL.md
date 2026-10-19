---
name: spring-boot-4-migration
description: Step-by-step migration of GST services/libraries from Spring Boot 2.x/3.x and Java 17/21 to Spring Boot 4.x and Java 25, for Gradle or Maven builds. Use when a project is below Boot 4 or Java 25, or when build/test failures mention removed Boot 3 APIs (MockBean, javax, Jackson 2, starter names, Undertow).
---

# Spring Boot 4 + Java 25 Migration (GST)

Goal: the project builds and passes all tests on **Java 25 + latest Spring Boot 4.x**, deploys through the
existing Forge Flow / Olympus pipeline, with behaviour unchanged.

## Rules of engagement

- One concern per step; **build + test after every step** (`./gradlew build` / `./mvnw verify`). Commit per step
  (Conventional Commits, e.g. `chore(build): upgrade to Spring Boot 4.1`).
- Do not mix migration with feature work or refactors.
- Never delete or `@Disabled` a failing test to get green — fix the cause or stop and report.
- Keep the build tool. Use `gradle-build` or `maven-build` for target build snippets.
- Use OpenRewrite where possible, then fix the remainder by hand.

## Step 0 — Baseline

```bash
git switch -c chore/boot4-java25
./gradlew build    # or ./mvnw -B verify   → record current pass/fail and test count
```

Record: Boot version, Java version, build tool and version, Spring Cloud version, notable libraries
(Lombok, MapStruct, springdoc, Testcontainers, Resilience4j, Kafka, Flyway/Liquibase).

**If the project is on Boot 2.x**, first migrate to the latest 3.5.x (javax → jakarta, Security 6 DSL, and so on), get green,
then continue. Do not jump 2 → 4 in one step.

## Step 1 — Get to latest Boot 3.5.x on the current Java

Bump to the newest 3.5.x and fix **all deprecation warnings**. APIs deprecated in 3.x are removed in 4.0.
Compile with `-Xlint:deprecation` (Gradle `options.compilerArgs`, Maven `<compilerArgs>`).

## Step 2 — Java 25 toolchain

| Build | Change |
|-------|--------|
| Gradle | Wrapper ≥ **9.1** (use latest 9.x) **before** switching the toolchain; `java { toolchain { languageVersion = JavaLanguageVersion.of(25) } }`; remove `sourceCompatibility`/`targetCompatibility`. |
| Maven | `<java.version>25</java.version>` (Boot parent) or `<maven.compiler.release>25</maven.compiler.release>`; declare `annotationProcessorPaths` (Lombok, config processor, MapStruct). **JDK 23+ no longer runs classpath processors implicitly.** |
| Both | JaCoCo ≥ 0.8.14, Lombok ≥ 1.18.40, Mockito ≥ 5.x with byte-buddy that supports Java 25 (Boot BOM manages these). Add `-XX:+EnableDynamicAgentLoading` or a Mockito javaagent only if tests warn about self-attach. |
| CI | Forge Flow `java-version: '25'` and `gradle-version: '<wrapper version>'` (the GST template defaults are 17 and 8.12). |
| Docker | `eclipse-temurin:25-jre` base (see `spring-docker-expert` agent / `forge-flow-ci`). |

Build and test on Java 25 while still on Boot 3.5 (Boot 3.5 supports Java 25). Fix failures.

## Step 3 — OpenRewrite to Boot 4

Gradle (init script, no build change committed):

```bash
cat > /tmp/rewrite.gradle <<'EOF'
initscript {
  repositories { maven { url "https://plugins.gradle.org/m2" } }
  dependencies { classpath("org.openrewrite:plugin:latest.release") }
}
rootProject {
  plugins.apply(org.openrewrite.gradle.RewritePlugin)
  dependencies { rewrite("org.openrewrite.recipe:rewrite-spring:latest.release") }
  rewrite { activeRecipe("org.openrewrite.java.spring.boot4.UpgradeSpringBoot_4_0") }
  afterEvaluate { if (repositories.isEmpty()) { repositories { mavenCentral() } } }
}
EOF
./gradlew --init-script /tmp/rewrite.gradle rewriteRun
```

Maven:

```bash
./mvnw -U org.openrewrite.maven:rewrite-maven-plugin:run \
  -Drewrite.recipeArtifactCoordinates=org.openrewrite.recipe:rewrite-spring:RELEASE \
  -Drewrite.activeRecipes=org.openrewrite.java.spring.boot4.UpgradeSpringBoot_4_0
```

The recipe targets 4.0 (verified in rewrite-spring 6.37); afterwards bump the Boot version to the latest 4.x by hand.
List recipes with `rewriteDiscover` / `rewrite:discover` if a newer `UpgradeSpringBoot_4_x` recipe exists. Review the diff and
then apply the manual checklist below for anything the recipe missed.

## Step 4 — Manual checklist (Boot 3 → 4)

### Build / starters
- [ ] Starters are modular: `spring-boot-starter-web` → **`spring-boot-starter-webmvc`** (old name still works, but deprecated).
- [ ] Each tech has its own **test starter**, which is needed for slice tests: `spring-boot-starter-webmvc-test`, `-data-jpa-test`, `-security-test`, `-restclient-test`, and so on.
- [ ] `RestClient`/`WebClient` auto-config needs `spring-boot-starter-restclient` / `-webclient` if not otherwise pulled in.
- [ ] `spring-boot-starter-aop` → **`spring-boot-starter-aspectj`**.
- [ ] Undertow is not supported → use Tomcat (default) or Jetty.
- [ ] Spring Cloud: use the release train compatible with your Boot minor (check the compatibility table at spring.io/projects/spring-cloud).
- [ ] Remove explicit versions that the Boot BOM manages (Jackson, Hibernate, Mockito, Testcontainers, …).
- [ ] Testcontainers 2: artifacts renamed `testcontainers-<module>` (e.g. `testcontainers-postgresql`, `testcontainers-junit-jupiter`); container classes moved to module packages (`org.testcontainers.postgresql.PostgreSQLContainer`) and are **not generic** (`new PostgreSQLContainer("postgres:17")`).
- [ ] Classic uber-jar loader and `launchScript` removed; layered jars are default.

### Packages / APIs
- [ ] **Jackson 3**: `com.fasterxml.jackson.databind` → `tools.jackson.databind`, `ObjectMapper` → prefer the injected `JsonMapper`; `Jackson2ObjectMapperBuilderCustomizer` → `JsonMapperBuilderCustomizer`; `@JsonComponent` → `@JacksonComponent`. Annotations (`com.fasterxml.jackson.annotation.*`) are unchanged. Temporary escape hatch: `spring-boot-jackson2` module.
- [ ] Jackson 3 defaults differ (for example, dates are written as ISO strings rather than timestamps, and properties are sorted alphabetically). **Add/keep JSON contract tests** and set `spring.jackson.*` to preserve wire formats.
- [ ] `@MockBean`/`@SpyBean` → **`@MockitoBean`/`@MockitoSpyBean`** (`org.springframework.test.context.bean.override.mockito`); they work on test-class fields only. For shared mocks, use `@MockitoBean(types = …)` on the class or a `@TestConfiguration`.
- [ ] Test annotations moved to per-module packages, e.g. `org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest`, `org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest`. Fix imports.
- [ ] `TestRestTemplate` → **`RestTestClient`** with `@AutoConfigureRestTestClient`.
- [ ] `RestTemplate` → `RestClient` (GST rule). `ClientHttpRequestFactories` → `ClientHttpRequestFactoryBuilder`; SSL via `RestClientSsl.fromBundle(...)`.
- [ ] HTTP interface clients: prefer `@ImportHttpServices` + `spring.http.serviceclient.<group>.base-url`.
- [ ] Hibernate 7 / JPA 3.2: check deprecated `@Where`/`@Loader`, the `org.hibernate.annotations` changes, and that the `hibernate.dialect` property is no longer needed (remove it).
- [ ] Observability: `micrometer-tracing-bridge-otel` + `opentelemetry-exporter-otlp` → `spring-boot-starter-opentelemetry`; `management.otlp.tracing.endpoint` → `management.opentelemetry.tracing.export.otlp.endpoint`. Run `spring-boot-properties-migrator` (runtime-only, remove after) to log every renamed property.
- [ ] **Spring Security 7**: `and()` chaining is removed (use the lambda DSL); `AntPathRequestMatcher`/`MvcRequestMatcher` → `PathPatternRequestMatcher`; check `authorizeHttpRequests` ordering.
- [ ] JUnit Jupiter 6: remove the JUnit 4 vintage engine; `junit-platform-launcher` on the test runtime classpath for Gradle.
- [ ] Nullability: Spring APIs use JSpecify. Kotlin callers may see new nullability errors.
- [ ] Properties: run with `spring-boot-properties-migrator` (runtime scope) once to log renamed keys, then remove it.

### Optional new features (only if requested)
- API versioning (`spring.mvc.apiversion.*`, `@GetMapping(version = "1.1")`).
- Core resilience: `@EnableResilientMethods`, `@Retryable`, `@ConcurrencyLimit`.
- `@NullMarked` packages.

## Step 5 — Java 25 code clean-up (optional, separate commits)

- Remove `synchronized` → `ReentrantLock` rewrites that were only made for virtual-thread pinning (fixed in JDK 24, JEP 491).
- Enable `spring.threads.virtual.enabled: true` if it is not already enabled.
- Consider `ScopedValue` instead of `ThreadLocal` for request context in new code.
- Do **not** mass-rewrite code into new syntax. Keep the diff reviewable.

## Step 6 — Container, CI and runtime

- [ ] Dockerfile base → `flutter.jfrog.io/container/eclipse-temurin:25-jre@sha256:<digest>`.
- [ ] JVM flags: drop `-XX:+UseContainerSupport` (default) and obsolete GC flags. Keep `-XX:MaxRAMPercentage=75`. Consider `-XX:+UseCompactObjectHeaders` (product flag in 25) after load testing.
- [ ] Olympus truststore: `-Djavax.net.ssl.trustStore=/etc/ssl/certs/keystore.p12 -Djavax.net.ssl.trustStorePassword=changeit` if the service calls internal TLS endpoints.
- [ ] Forge Flow callers: `java-version: '25'`, `gradle-version` = wrapper version, and all `uses:` SHA-pinned (see `forge-flow-ci`).
- [ ] Actuator probes still at `/actuator/health/liveness` and `/readiness`. Prometheus endpoint still exposed.

## Step 7 — Verify and report

```bash
./gradlew clean build jacocoTestReport      # or ./mvnw -B clean verify
grep -rn --include=*.java -E 'javax\.(persistence|validation|servlet)|@MockBean|@SpyBean|com\.fasterxml\.jackson\.databind|RestTemplate|TestRestTemplate' src || echo "clean"
```

Report:
- versions before and after
- test count before and after (must not decrease)
- the list of manual changes
- any behaviour/wire-format risks (especially Jackson 3 defaults)
- follow-ups

Open the PR via the `git-workflow` skill with the title `chore: migrate to Spring Boot 4 and Java 25`.
