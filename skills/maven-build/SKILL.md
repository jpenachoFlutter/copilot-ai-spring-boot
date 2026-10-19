---
name: maven-build
description: Maven setup for GST Spring Boot 4 / Java 25 projects — wrapper, spring-boot-starter-parent, compiler release 25, Lombok annotation processing, Forge Store (JFrog) resolution, JaCoCo for Sonar, release-please, dependabot. Use when the project has pom.xml/mvnw, or when the user chose Maven for a new project.
---

# Maven Build (GST)

Use only when the project **already uses Maven** or the user **explicitly chose Maven** for a new project
(see `gst-conventions` → "Build tool — detect, never assume").

## Version baseline (verified 2026-10; re-check before pinning)

| Component | Version | Re-check (Maven Central) |
|-----------|---------|--------------------------|
| Maven (wrapper distribution) | latest 3.9.x (3.9.16) — Forge Flow input `maven-version` should match | `org/apache/maven/maven-core` |
| Maven Wrapper | 3.3.4 | `org/apache/maven/wrapper/maven-wrapper` |
| spring-boot-starter-parent | 4.1.1 | `org/springframework/boot/spring-boot` |
| jacoco-maven-plugin | 0.8.15 (≥ 0.8.14 for Java 25) | `org/jacoco/jacoco-maven-plugin` |

```bash
./mvnw -N wrapper:wrapper -Dmaven=3.9.16    # create/upgrade the wrapper
```

## pom.xml (service)

```xml
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>4.1.1</version>
    <relativePath/>
  </parent>

  <groupId>com.flutter.gst</groupId>
  <artifactId>pricing-service</artifactId>
  <version>0.1.0</version> <!-- x-release-please-version -->

  <properties>
    <java.version>25</java.version>          <!-- the Boot parent maps this to maven.compiler.release -->
    <jacoco.version>0.8.15</jacoco.version>
  </properties>

  <dependencies>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-webmvc</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-validation</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-actuator</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-jpa</artifactId></dependency>
    <dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><scope>runtime</scope></dependency>
    <dependency><groupId>io.micrometer</groupId><artifactId>micrometer-registry-prometheus</artifactId><scope>runtime</scope></dependency>
    <dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId><optional>true</optional></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-configuration-processor</artifactId><optional>true</optional></dependency>

    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-webmvc-test</artifactId><scope>test</scope></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-jpa-test</artifactId><scope>test</scope></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-testcontainers</artifactId><scope>test</scope></dependency>
    <dependency><groupId>org.testcontainers</groupId><artifactId>testcontainers-junit-jupiter</artifactId><scope>test</scope></dependency>
    <dependency><groupId>org.testcontainers</groupId><artifactId>testcontainers-postgresql</artifactId><scope>test</scope></dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-compiler-plugin</artifactId>
        <configuration>
          <parameters>true</parameters>
          <!-- JDK 23+ no longer runs classpath annotation processors implicitly: declare them -->
          <annotationProcessorPaths>
            <path><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId></path>
            <path><groupId>org.springframework.boot</groupId><artifactId>spring-boot-configuration-processor</artifactId></path>
          </annotationProcessorPaths>
        </configuration>
      </plugin>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
        <configuration>
          <excludes><exclude><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId></exclude></excludes>
        </configuration>
      </plugin>
      <plugin>
        <groupId>org.jacoco</groupId>
        <artifactId>jacoco-maven-plugin</artifactId>
        <version>${jacoco.version}</version>
        <executions>
          <execution><goals><goal>prepare-agent</goal></goals></execution>
          <execution><id>report</id><phase>verify</phase><goals><goal>report</goal></goals></execution>
        </executions>
      </plugin>
    </plugins>
  </build>
</project>
```

JaCoCo XML: `target/site/jacoco/jacoco.xml` → in Forge Flow set `coverage-report-path: '**/target/site/jacoco/jacoco.xml'`.

> Annotation processor paths without `<version>` rely on Boot's dependency management (maven-compiler-plugin ≥ 3.12).
> If the build fails with "version missing", add `<version>${lombok.version}</version>`.

## Libraries (published jars)

Drop `spring-boot-maven-plugin`. If the library must not inherit Boot's plugin config, import the BOM instead of
using the parent:

```xml
<dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId><artifactId>spring-boot-dependencies</artifactId>
      <version>4.1.1</version><type>pom</type><scope>import</scope>
    </dependency>
  </dependencies>
</dependencyManagement>
```

Publishing is done by Forge Flow (`artifact-publish: true`, `artifact-publish-cmd: './mvnw deploy -DskipTests'`);
`jf mvn-config` redirects deploy to `grt-maven-local`. **No `<distributionManagement>` URLs or credentials in the POM.**

## Local resolution through Forge Store (optional)

`jf c add` (SSO) once, then `jf mvn-config --repo-resolve-releases=grt-maven --repo-resolve-snapshots=grt-maven`
and `jf mvn clean verify`. Never commit a `settings.xml` with tokens.

## release-please & dependabot

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "release-type": "simple",
  "packages": { ".": { "extra-files": [ { "type": "xml", "path": "pom.xml", "xpath": "//project/version" } ] } }
}
```

For multi-module builds list every module `pom.xml` (or use `release-type: maven`).

Dependabot: same `maven-forge` registry block as in `gradle-build`, with `package-ecosystem: maven`.

## Verify loop

```bash
./mvnw -v                         # Maven 3.9.x running on Java 25
./mvnw -B clean verify            # must be green
ls target/site/jacoco/jacoco.xml
```
