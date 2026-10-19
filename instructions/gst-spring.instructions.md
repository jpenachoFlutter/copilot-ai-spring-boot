---
applyTo: "**/*.java,**/*.kt,**/pom.xml,**/build.gradle,**/build.gradle.kts,**/settings.gradle*,**/gradle.properties,**/application*.yml,**/application*.properties,**/Dockerfile,**/.github/workflows/*.yml,**/resources/**/templates/*.yaml"
---

# GST Spring Boot work

When working on Java / Spring Boot code, builds, Dockerfiles, CI workflows or Helm charts in a Flutter GST repository:

- Load the `gst-conventions` skill first. It defines the baseline: Spring Boot 4.x, Java 25, group `com.flutter.gst`,
  Gradle **or** Maven (detect it; for a new project ask the user which one), Lombok allowed with entity restrictions,
  Forge Flow CI pinned to commit SHAs, Forge Store (`flutter.jfrog.io`) and Olympus deployment.
- Then load the matching skill: `gradle-build` / `maven-build`, `spring-boot-4-migration`, `forge-flow-ci`, `olympus-deploy`,
  `spring-boot`, `java-modern`, `jpa-patterns`, `testing-patterns`, `logging-patterns`, `code-quality`, `design-patterns`.
- Specialist agents: `spring-boot-engineer`, `spring-code-reviewer`, `spring-security-engineer`, `spring-devops-engineer`,
  `spring-docker-expert`, `spring-olympus-specialist`.
