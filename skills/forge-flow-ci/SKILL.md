---
name: forge-flow-ci
description: GitHub Actions CI/CD for GST Java/Spring Boot repos on Forge Flow (Flutter-Global/forge-flow-workflows + gst-risk-workflow-templates) — PR/feature build, release-please release, image + Helm publish to Forge Store (flutter.jfrog.io), infra-repo notification, PR-title lint, dependabot. Every action/workflow pinned to a full commit SHA. Use when creating or changing anything under .github/.
---

# Forge Flow CI (GST)

## Non-negotiables

1. **Every `uses:` is pinned to a 40-char commit SHA** with a trailing `# vX.Y.Z` comment. This covers actions,
   reusable workflows and composite actions. Never use `@main`, `@v2` or `@latest`. Local `./.github/...` refs are exempt.
2. Runner: `grt` (GST Forge runner group). Do not use `ubuntu-latest` for jobs that touch Forge Store.
3. Java `'25'`. Gradle builds pass `gradle-version` equal to the wrapper version (≥ 9.1).
   **The template defaults (`17`, `8.12`) break Java 25 builds.**
4. Least privilege: declare `permissions:` at the workflow level and widen it only per job.
5. No secrets in YAML. Use org secrets: `ORG_SONAR_TOKEN`, `ORG_SONAR_PROVISION_TOKEN`, `CATALYST_GITHUB_USERNAME`,
   `CATALYST_GITHUB_TOKEN`, `ORG_GS_GROUP_OLYMPUS_INFRA_SECRET`.
6. PR titles are Conventional Commits, because release-please derives versions from them.
7. If the repo is **not yet onboarded to Forge** (no `grt` runner group, no Forge Store OIDC mapping), stop. Point the user to the
   Flutter `forge-onboarding` / `forge-flow-build-migration` skills (sparta-ai-agents repo) instead of improvising.

## Pinned references (resolved 2026-10-19 — re-resolve before use, see below)

| Reference | Pin |
|-----------|-----|
| flutter-global/forge-flow-workflows (reusable workflows) | `19573adc434fe6ba8429febf495530e12675b3b8` # v2.13.0 |
| flutter-global/gst-risk-workflow-templates (no releases; `main`) | `71d6a89f7498df907afbed4c4ae6c4772ebc8a51` # main 2026-10-19 |
| actions/checkout | `3d3c42e5aac5ba805825da76410c181273ba90b1` # v7.0.1 |
| actions/setup-java | `b843ebf9b913146b38da2eaa7aeddf76074ae1ad` # v6.1.0 |
| gradle/actions/setup-gradle | `3f5f9adaf7d9fecd50b5935e54106014257a94e6` # v6.4.0 |
| actions/upload-artifact | `cf430e030ddbb5b0abf93d22962f4752f3646cd9` # v7.0.2 |
| actions/download-artifact | `9000827ccba6bdab643e8b6fd33ac0654aef8333` # v8.0.2 |
| actions/cache | `55cc8345863c7cc4c66a329aec7e433d2d1c52a9` # v6.1.0 |
| actions/create-github-app-token | `64ab729a6294000f5aa4a4bc0b73d1f32bc45510` # v3.3.0 |
| jfrog/setup-jfrog-cli | `ad1052fd1b866ba57235228e8cc8997cf968fc4b` # v4.12.0 |
| docker/login-action | `dbcb813823bdd20940b903addbd779551569679f` # v4.6.0 |
| docker/setup-buildx-action | `f87e5991a6d7451dcb8d9637bfbc97413f497069` # v4.4.1 |
| docker/metadata-action | `dc802804100637a589fabce1cb79ff13a1411302` # v6.2.0 |
| docker/build-push-action | `c3c9e263c25d99ce0380d002d59b67737d91b0dc` # v7.4.0 |
| googleapis/release-please-action | `45996ed1f6d02564a971a2fa1b5860e934307cf7` # v5.0.0 |
| amannn/action-semantic-pull-request | `48f256284bd46cdaab1048c3721360e808335d50` # v6.1.1 |
| madrapps/jacoco-report | `e51ce1f46f7f8b5331593f935e59cbaf44b84920` # v1.8.0 |

> Note: gst-risk-workflow-templates internally calls forge-flow-workflows by **tag** (`@v2.12.1`). Pinning the template
> by SHA freezes that code path, but the nested tag is outside our control. For maximum supply-chain control (or for
> Maven), call forge-flow-workflows directly (Option B).

> ⚠️ **Known defect at the pinned gst SHA (`71d6a89`):** `develop-build.yml` job conditions are malformed:
> - `build-and-push` (line ~109) uses `if: ${{ … > 0 }} && (…)`. Only part of it is inside `${{ }}`, so the whole condition is a non-empty string and **always true**. The job therefore publishes images without the `RUN_PR_WORKFLOW` label.
> - `just-build` (line ~136) uses `!x > 0` (a precedence bug).
>
> `actionlint` flags both. Until upstream fixes them, use **Option B for push/PR builds**. The gst `release.yml`,
> `helm-package-publish.yml` and `notify-infrastructure-repo.yml` are unaffected. Re-check after re-resolving the SHA
> (`actionlint` on the template), and raise it with the template owners.

### Re-resolving a pin (do this when creating or updating workflows)

```bash
repo=actions/checkout
tag=$(gh api repos/$repo/releases/latest --jq .tag_name)
ref=$(gh api repos/$repo/git/ref/tags/$tag --jq '.object.type + " " + .object.sha')
set -- $ref
[ "$1" = tag ] && sha=$(gh api repos/$repo/git/tags/$2 --jq .object.sha) || sha=$2   # dereference annotated tags
echo "uses: $repo@$sha # $tag"
# repos without releases (gst-risk-workflow-templates): gh api repos/<r>/commits/main --jq .sha
```

Verify: `grep -rnE 'uses: [^.][^@]*@[^ ]+' .github | grep -vE '@[0-9a-f]{40}( |$)'` must print nothing.

---

## Option A — Gradle **service** via GST templates (release flow OK; see the develop-build defect above)

`.github/workflows/on-push-to-feature-branch.yml`

```yaml
name: Feature branch build
on:
  push:
    branches-ignore: [main]
permissions:
  contents: read
  id-token: write
  packages: write
  pull-requests: write
jobs:
  build:
    uses: flutter-global/gst-risk-workflow-templates/.github/workflows/develop-build.yml@71d6a89f7498df907afbed4c4ae6c4772ebc8a51 # main 2026-10-19
    with:
      container-image-name: pricing-service
      java-version: '25'
      gradle-version: '9.8.1'
      build-tasks: build test jacocoTestReport
      deploy-env: qa              # first Olympus env for PR deploys (label RUN_PR_WORKFLOW)
    secrets: inherit
```

`.github/workflows/on-push-to-main.yml`

```yaml
name: Release
on:
  push:
    branches: [main]
permissions:
  contents: write
  id-token: write
  packages: write
  pull-requests: write
jobs:
  release:
    uses: flutter-global/gst-risk-workflow-templates/.github/workflows/release.yml@71d6a89f7498df907afbed4c4ae6c4772ebc8a51 # main 2026-10-19
    with:
      container-image-name: pricing-service
      java-version: '25'
      gradle-version: '9.8.1'
      deploy-env: qa
    secrets: inherit
```

What happens:
- **feature branch**: version `x.y.z-beta…`, build/test/Sonar. If the push belongs to a PR labelled `RUN_PR_WORKFLOW` (or
  `GAM_RUN_PR_WORKFLOW`), the image is pushed to `grt-container-local`, the chart in `./resources/<repo>` is published to
  `grt-helmoci-local`, and `<repo>-infra` is asked to update `deploy-env`.
- **main**: release-please opens/updates the release PR. When it is merged, the workflow builds and publishes the image + chart
  with the release version and notifies the infra repo (see `olympus-deploy`).

Libraries (Gradle): `library-develop-build.yml` / `library-release.yml` (inputs `gradle-version`, `build-tasks`,
`java-version`) — same pinning rules.

## Option B — direct forge-flow-workflows (default for push/PR builds; required for Maven)

`.github/workflows/build.yml` (PRs + feature branches)

```yaml
name: Build
on:
  pull_request:
  push:
    branches-ignore: [main]
permissions:
  contents: read
  id-token: write
  packages: write
  pull-requests: write
jobs:
  build:
    uses: flutter-global/forge-flow-workflows/.github/workflows/java-build-scan-publish.yml@19573adc434fe6ba8429febf495530e12675b3b8 # v2.13.0
    with:
      runner: grt
      java-version: '25'
      # --- Maven ---
      java-build-tool: maven
      maven-version: '3.9.16'
      java-build-cmd: ./mvnw -B verify
      coverage-report-path: '**/target/site/jacoco/jacoco.xml'
      # --- Gradle (instead of the Maven block) ---
      # java-build-tool: gradle
      # gradle-version: '9.8.1'
      # java-build-cmd: ./gradlew build test jacocoTestReport
      # coverage-report-path: '**/reports/**/jacoco/**/jacocoTestReport.xml'
      repo-resolve: grt-maven
      repo-deploy: grt-maven-local
      sonar-run: true
      container-publish: false
    secrets:
      GH_PKG_XREPO_USER: ${{ secrets.CATALYST_GITHUB_USERNAME }}
      GH_PKG_XREPO_TOKEN: ${{ secrets.CATALYST_GITHUB_TOKEN }}
      ORG_SONAR_TOKEN: ${{ secrets.ORG_SONAR_TOKEN }}
      ORG_SONAR_PROVISION_TOKEN: ${{ secrets.ORG_SONAR_PROVISION_TOKEN }}
```

`.github/workflows/release.yml` (main)

```yaml
name: Release
on:
  push:
    branches: [main]
permissions:
  contents: write
  id-token: write
  packages: write
  pull-requests: write
jobs:
  release-please:
    uses: flutter-global/forge-flow-workflows/.github/workflows/cc-release.yml@19573adc434fe6ba8429febf495530e12675b3b8 # v2.13.0
    with:
      runner: grt
      config-file: release-please-config.json
      manifest-file: .release-please-manifest.json

  build:
    needs: release-please
    if: needs.release-please.outputs.release_created == 'true'
    uses: flutter-global/forge-flow-workflows/.github/workflows/java-build-scan-publish.yml@19573adc434fe6ba8429febf495530e12675b3b8 # v2.13.0
    with:
      runner: grt
      java-version: '25'
      java-build-tool: maven
      maven-version: '3.9.16'
      java-build-cmd: ./mvnw -B verify
      coverage-report-path: '**/target/site/jacoco/jacoco.xml'
      repo-resolve: grt-maven
      repo-deploy: grt-maven-local
      sonar-run: true
      release-tag: ${{ needs.release-please.outputs.tag_name }}
      container-publish: true
      container-registry: grt-container-local
      container-image-name: pricing-service
      container-image-version: ${{ needs.release-please.outputs.release_version }}
      # library instead of image:
      # artifact-publish: true
      # artifact-publish-cmd: ./mvnw -B deploy -DskipTests      (Gradle: ./gradlew publish)
    secrets:
      GH_PKG_XREPO_USER: ${{ secrets.CATALYST_GITHUB_USERNAME }}
      GH_PKG_XREPO_TOKEN: ${{ secrets.CATALYST_GITHUB_TOKEN }}
      ORG_SONAR_TOKEN: ${{ secrets.ORG_SONAR_TOKEN }}
      ORG_SONAR_PROVISION_TOKEN: ${{ secrets.ORG_SONAR_PROVISION_TOKEN }}

  helm:
    needs: [release-please, build]
    uses: flutter-global/gst-risk-workflow-templates/.github/workflows/helm-package-publish.yml@71d6a89f7498df907afbed4c4ae6c4772ebc8a51 # main 2026-10-19
    with:
      chart-publish: true
      chart-version: ${{ needs.release-please.outputs.release_version }}
      chart-path: ./resources/${{ github.event.repository.name }}
      release-tag: ${{ needs.release-please.outputs.tag_name }}
      helm-values-repo: ${{ github.repository }}-infra
      helm-values-file-path: variants/nxt/values/values.yaml
    secrets:
      GH_PKG_XREPO_TOKEN: ${{ secrets.CATALYST_GITHUB_TOKEN }}

  notify-infra:
    needs: [release-please, helm]
    uses: flutter-global/gst-risk-workflow-templates/.github/workflows/notify-infrastructure-repo.yml@71d6a89f7498df907afbed4c4ae6c4772ebc8a51 # main 2026-10-19
    with:
      helm-chart-version: ${{ needs.release-please.outputs.release_version }}
      container-image-name: pricing-service
      deploy-env: qa
    secrets:
      ORG_GS_GROUP_OLYMPUS_INFRA_SECRET: ${{ secrets.ORG_GS_GROUP_OLYMPUS_INFRA_SECRET }}
```

`java-build-scan-publish.yml` v2.13.0 inputs (for reference): `runner`*, `java-build-cmd`*, `repo-resolve`*,
`repo-deploy`*, `java-build-tool`, `java-version` (17), `java-distribution` (temurin), `gradle-version` (current),
`maven-version` (3.9.9), `container-publish`, `container-registry`, `container-registry-host` (flutter.jfrog.io),
`container-image-name`, `container-image-version`, `containerfile-location` (Dockerfile), `container-multi-arch`,
`java-container-build-source` (dockerfile), `sonar-run`, `sonar-extra-args`, `coverage-report-path`, `release-tag`,
`artifact-publish`, `artifact-publish-cmd`, `artifact-version`, `trufflehog-block`. Check the live schema at the pinned SHA
before using any other input: `gh api 'repos/flutter-global/forge-flow-workflows/contents/.github/workflows/java-build-scan-publish.yml?ref=<sha>' --jq .content | base64 -d`.

## Shared files

`.github/workflows/pr-title.yml`

```yaml
name: PR title
on:
  pull_request:
    types: [opened, edited, synchronize, reopened]
permissions:
  pull-requests: read
jobs:
  lint:
    uses: flutter-global/forge-flow-workflows/.github/workflows/cc-lint-pr-title.yml@19573adc434fe6ba8429febf495530e12675b3b8 # v2.13.0
    with:
      runner: grt
```

`release-please-config.json` + `.release-please-manifest.json` (`{ ".": "0.1.0" }`). See `gradle-build` / `maven-build`
for the `extra-files` entry that bumps `gradle.properties` / `pom.xml`.

`.github/dependabot.yml`

```yaml
version: 2
registries:
  maven-forge:
    type: maven-repository
    url: https://flutter.jfrog.io/artifactory/grt-maven
    jfrog-oidc-provider-name: flutter-global
    audience: forge
updates:
  - package-ecosystem: gradle            # or: maven
    directory: "/"
    registries: [maven-forge]
    schedule: { interval: weekly }
    ignore:
      - dependency-name: "*"
        update-types: ["version-update:semver-major"]
  - package-ecosystem: github-actions    # keeps the SHA pins fresh (Dependabot updates SHA + comment)
    directory: "/"
    schedule: { interval: weekly }
    commit-message: { prefix: chore }
  - package-ecosystem: docker            # keeps the Dockerfile base-image digest fresh
    directory: "/"
    schedule: { interval: weekly }
    commit-message: { prefix: chore }
```

## Dockerfile expected by Forge Flow (`containerfile-location: Dockerfile`)

Forge Flow runs the build first, so the Dockerfile only copies the built jar (no in-image Maven/Gradle build):

```dockerfile
# Base image pulled through Forge Store, pinned by digest (dependabot docker updates it)
FROM flutter.jfrog.io/container/eclipse-temurin:25-jre@sha256:dbb43d81099eec91e0800226ed2296d03146ee7857165b95112372ad0d67e87f AS extract
WORKDIR /build
# Gradle: build/libs/*.jar   Maven: target/*.jar   (ensure exactly one boot jar — disable the plain jar)
COPY build/libs/*.jar app.jar
RUN java -Djarmode=tools -jar app.jar extract --layers --launcher --destination extracted

FROM flutter.jfrog.io/container/eclipse-temurin:25-jre@sha256:dbb43d81099eec91e0800226ed2296d03146ee7857165b95112372ad0d67e87f
WORKDIR /app
COPY --from=extract /build/extracted/dependencies/ ./
COPY --from=extract /build/extracted/spring-boot-loader/ ./
COPY --from=extract /build/extracted/snapshot-dependencies/ ./
COPY --from=extract /build/extracted/application/ ./
# Numeric UID so Kubernetes runAsNonRoot can verify it
USER 10001:10001
EXPOSE 8080 8081
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError -Djavax.net.ssl.trustStore=/etc/ssl/certs/keystore.p12 -Djavax.net.ssl.trustStorePassword=changeit"
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
```

- The `flutter.jfrog.io/container/...` remote is used by forge-flow-test. A value-stream remote (e.g. `grt-container`) may
  exist. Check existing GST Dockerfiles and match them.
- Get the digest for a new tag:
  `docker buildx imagetools inspect flutter.jfrog.io/container/eclipse-temurin:25-jre --format '{{json .Manifest.Digest}}'`.
- The truststore flags apply only on Olympus (the platform mounts `/etc/ssl/certs/keystore.p12`). Omit them for local `docker run`.

## Verify loop

1. `actionlint` (if installed) or `gh workflow view` after push. YAML must parse.
2. Pin check (command above) prints nothing.
3. Push the branch and watch: `gh run watch --exit-status`. On failure: `gh run view --log-failed`, fix, push. Retry at most 5 times
   per distinct error, then escalate with logs.
4. Confirm artifacts with the `artifact-verifier` skill (image/chart present in `flutter.jfrog.io`).

## Confluence references

[Forge 101](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293289574688) ·
[Forge Flow](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293299372049) ·
[Forge Build](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293299765251) ·
[Forge Store](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4293431918677) ·
[Forge onboarding and migration skills](https://fluttergroup.atlassian.net/wiki/spaces/GPDP/pages/4295212532095).
