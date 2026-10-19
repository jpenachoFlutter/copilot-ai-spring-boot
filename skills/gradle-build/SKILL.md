---
name: gradle-build
description: Gradle setup for GST Spring Boot 4 / Java 25 projects — wrapper, toolchains, Boot plugin, Forge Store (JFrog) resolution, JaCoCo for Sonar, release-please version file, dependabot. Use when the project has build.gradle(.kts)/gradlew, or when the user chose Gradle for a new project.
---

# Gradle Build (GST)

Use only when the project **already uses Gradle** or the user **explicitly chose Gradle** for a new project
(see `gst-conventions` → "Build tool — detect, never assume"). Match the existing DSL (Kotlin `.kts` or Groovy);
for new projects use the Kotlin DSL.

## Version baseline (verified 2026-10; re-check before pinning)

| Component | Version | How to re-check |
|-----------|---------|-----------------|
| Gradle wrapper | 9.8.1 (≥ 9.1 required to *run* on Java 25) | `curl -s https://services.gradle.org/versions/current` |
| Spring Boot plugin | 4.1.1 | Maven Central `org/springframework/boot/spring-boot/maven-metadata.xml` |
| foojay toolchain resolver | 1.0.0 | Gradle plugin portal |
| JaCoCo | 0.8.15 (≥ 0.8.14 for Java 25 class files) | Maven Central `org/jacoco` |

Upgrade the wrapper with the wrapper itself, never by editing the properties file by hand:

```bash
./gradlew wrapper --gradle-version 9.8.1 --distribution-type bin
./gradlew wrapper   # second run refreshes the wrapper jar/scripts using the new version
```

In CI pass the same version to Forge Flow (`gradle-version: '9.8.1'`). The GST template default is `8.12`,
which **cannot run on Java 25**.

## settings.gradle.kts

```kotlin
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}
rootProject.name = "pricing-service"   // = repository name
```

## build.gradle.kts (service)

```kotlin
plugins {
    java
    jacoco
    id("org.springframework.boot") version "4.1.1"
}

group = "com.flutter.gst"
version = project.property("version") as String   // from gradle.properties, bumped by release-please

java {
    toolchain { languageVersion = JavaLanguageVersion.of(25) }
}

repositories {
    mavenCentral()   // in CI, `jf gradle-config` redirects resolution to Forge Store (grt-maven)
}

dependencies {
    implementation(platform(org.springframework.boot.gradle.plugin.SpringBootPlugin.BOM_COORDINATES))
    annotationProcessor(platform(org.springframework.boot.gradle.plugin.SpringBootPlugin.BOM_COORDINATES))
    testAnnotationProcessor(platform(org.springframework.boot.gradle.plugin.SpringBootPlugin.BOM_COORDINATES))   // not inherited from annotationProcessor

    implementation("org.springframework.boot:spring-boot-starter-webmvc")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    runtimeOnly("org.postgresql:postgresql")
    runtimeOnly("io.micrometer:micrometer-registry-prometheus")

    compileOnly("org.projectlombok:lombok")
    annotationProcessor("org.projectlombok:lombok")
    annotationProcessor("org.springframework.boot:spring-boot-configuration-processor")

    testImplementation("org.springframework.boot:spring-boot-starter-webmvc-test")
    testImplementation("org.springframework.boot:spring-boot-starter-data-jpa-test")
    testImplementation("org.springframework.boot:spring-boot-testcontainers")
    testImplementation("org.testcontainers:testcontainers-junit-jupiter")
    testImplementation("org.testcontainers:testcontainers-postgresql")
    testCompileOnly("org.projectlombok:lombok")
    testAnnotationProcessor("org.projectlombok:lombok")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.addAll(listOf("-parameters", "-Xlint:all,-processing"))
}

tasks.test {
    useJUnitPlatform()
    finalizedBy(tasks.jacocoTestReport)
}

jacoco { toolVersion = "0.8.15" }

tasks.jacocoTestReport {
    dependsOn(tasks.test)
    reports { xml.required = true; html.required = true }
}

tasks.jar { enabled = false }   // only the boot jar → Dockerfile can COPY build/libs/*.jar
```

`gradle.properties`:

```properties
version=0.1.0
org.gradle.caching=true
org.gradle.parallel=true
org.gradle.configuration-cache=true
```

The JaCoCo XML lands at `build/reports/jacoco/test/jacocoTestReport.xml`, matching the GST default
`coverage-report-path: '**/reports/**/jacoco/**/jacocoTestReport.xml'`.

## Libraries (published jars)

Replace the Boot plugin with `java-library` + `maven-publish`, keep the BOM via `platform(...)`, add
`withSourcesJar()` / `withJavadocJar()`. Publishing is done by Forge Flow (`artifact-publish: true`,
`artifact-publish-cmd: './gradlew publish'`) — `jf gradle-config` points deploy at `grt-maven-local`.
Do not hard-code repository URLs or credentials in the build.

## Multi-module

- Put shared config in a convention plugin (`buildSrc/` or an included `build-logic` build), not `allprojects {}`.
- Use a version catalog `gradle/libs.versions.toml` for non-BOM dependencies.

## Local resolution through Forge Store (optional)

Developers who must resolve internal `com.flutter.gst` artifacts locally configure JFrog CLI once
(`jf c add`, SSO) and run `jf gradle-config --repo-resolve=grt-maven --use-wrapper=true`, then
`jf gradle build`. Never commit tokens to `gradle.properties`.

## release-please & dependabot

`release-please-config.json` (as in `gst-risk-workflow-templates/examples`):

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "release-type": "simple",
  "packages": { ".": { "extra-files": ["gradle.properties"] } }
}
```

Add `# x-release-please-version` at the end of the `version=` line if release-please does not pick it up.

`.github/dependabot.yml` ecosystem entry:

```yaml
registries:
  maven-forge:
    type: maven-repository
    url: https://flutter.jfrog.io/artifactory/grt-maven
    jfrog-oidc-provider-name: flutter-global
    audience: forge
updates:
  - package-ecosystem: gradle
    directory: "/"
    registries: [maven-forge]
    schedule: { interval: weekly }
    ignore:
      - dependency-name: "*"
        update-types: ["version-update:semver-major"]
```

## Verify loop

```bash
./gradlew --version                         # Gradle ≥ 9.1
./gradlew javaToolchains                    # JDK 25 detected/provisioned
./gradlew clean build jacocoTestReport      # must be green
ls build/reports/jacoco/test/jacocoTestReport.xml
```
