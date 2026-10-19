# GST Flink Agents templates

Versions below were resolved on 2026-10-19 — **re-resolve before use** (`flink-agents-gst` §1). Replace `<app>`, `<tla>`,
`<App>`, `<ns>` and keep only the integrations/connectors the plan selected.

## Gradle (Kotlin DSL)

```kotlin
plugins {
    java
    id("com.gradleup.shadow") version "9.6.1"
}

group = "com.flutter.gst"

java { toolchain { languageVersion = JavaLanguageVersion.of(21) } } // Flink image JDK, not GST's 25

val flinkVersion = "2.2.1"
val flinkMinor = "2.2"
val agentsVersion = "0.3.1"
val kafkaConnectorVersion = "5.0.0-2.2"

// Jars the image provides in /opt/flink/lib
val flinkLib by configurations.creating { isTransitive = false }

dependencies {
    listOf(
        "org.apache.flink:flink-agents-api:$agentsVersion",
        "org.apache.flink:flink-agents-plan:$agentsVersion",
        "org.apache.flink:flink-agents-runtime:$agentsVersion",
        // only the selected integrations, e.g.:
        // "org.apache.flink:flink-agents-integrations-chat-models-bedrock:$agentsVersion",
        "org.apache.flink:flink-streaming-java:$flinkVersion",
        "org.apache.flink:flink-clients:$flinkVersion",
        "org.apache.flink:flink-table-api-java-bridge:$flinkVersion",
    ).forEach { compileOnly(it); testImplementation(it) }

    implementation("org.apache.flink:flink-connector-kafka:$kafkaConnectorVersion") // shaded (or move to flinkLib)

    flinkLib("org.apache.flink:flink-agents-dist-flink-$flinkMinor:$agentsVersion")

    testImplementation("org.apache.flink:flink-test-utils:$flinkVersion")
    testImplementation(platform("org.junit:junit-bom:6.1.3"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    testImplementation(platform("org.testcontainers:testcontainers-bom:2.0.5"))
    testImplementation("org.testcontainers:testcontainers-kafka")
}

tasks.test {
    useJUnitPlatform()
    jvmArgs("--add-exports=java.base/jdk.internal.vm=ALL-UNNAMED")
}

tasks.shadowJar {
    archiveFileName = "${project.name}.jar"
    mergeServiceFiles()
}

val stageFlinkLib by tasks.registering(Sync::class) {
    from(flinkLib)
    into(layout.buildDirectory.dir("flink-lib"))
}

tasks.assemble { dependsOn(tasks.shadowJar, stageFlinkLib) }

// Local MiniCluster run: provided deps must be on the classpath
tasks.register<JavaExec>("runLocal") {
    mainClass = "com.flutter.gst.<app>.<App>Job"
    classpath = sourceSets.main.get().runtimeClasspath + sourceSets.main.get().compileClasspath
    jvmArgs("--add-exports=java.base/jdk.internal.vm=ALL-UNNAMED")
}
```

Build: `./gradlew build` → `build/libs/<app>.jar` + `build/flink-lib/flink-agents-dist-flink-2.2-0.3.1.jar`.

## Maven deltas (on top of the upstream `local-development.md` POM)

```xml
<groupId>com.flutter.gst</groupId>
<properties>
    <maven.compiler.release>21</maven.compiler.release>
</properties>

<!-- shaded job jar: provided deps are excluded automatically -->
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-shade-plugin</artifactId>
    <version>3.6.2</version>
    <executions>
        <execution>
            <phase>package</phase>
            <goals><goal>shade</goal></goals>
            <configuration>
                <finalName>${project.artifactId}</finalName>
                <createDependencyReducedPom>false</createDependencyReducedPom>
                <transformers>
                    <transformer implementation="org.apache.maven.plugins.shade.resource.ServicesResourceTransformer"/>
                </transformers>
                <filters>
                    <filter>
                        <artifact>*:*</artifact>
                        <excludes><exclude>META-INF/*.SF</exclude><exclude>META-INF/*.DSA</exclude><exclude>META-INF/*.RSA</exclude></excludes>
                    </filter>
                </filters>
            </configuration>
        </execution>
    </executions>
</plugin>

<!-- stage the jars the image provides -->
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-dependency-plugin</artifactId>
    <version>3.11.0</version>
    <executions>
        <execution>
            <id>stage-flink-lib</id>
            <phase>package</phase>
            <goals><goal>copy</goal></goals>
            <configuration>
                <outputDirectory>${project.build.directory}/flink-lib</outputDirectory>
                <artifactItems>
                    <artifactItem>
                        <groupId>org.apache.flink</groupId>
                        <artifactId>flink-agents-dist-flink-2.2</artifactId>
                        <version>${flink-agents.version}</version>
                    </artifactItem>
                </artifactItems>
            </configuration>
        </execution>
    </executions>
</plugin>
```

Add `--add-exports=java.base/jdk.internal.vm=ALL-UNNAMED` to the `exec-maven-plugin` arguments and Surefire `argLine` on JDK 21+.

## Dockerfile

```dockerfile
# Official Flink image via Forge Store; pin by digest (resolve: flink-agents-gst §1)
FROM flutter.jfrog.io/container/flink:2.2.1-java21@sha256:c2873d6e5e9d73a4eb1d77552feaedc49ca99e91412dc9f197730fc79f1660bf

# Flink Agents runtime (+ any connectors chosen to live in lib instead of the job jar)
COPY --chown=flink:flink build/flink-lib/*.jar /opt/flink/lib/

# Job jar: NOT /opt/flink/usrlib (FKO standalone mounts an empty dir there on the JobManager)
COPY --chown=flink:flink build/libs/<app>.jar /opt/<tla>/<app>.jar

# Python jobs only: RUN mv /opt/flink/opt/flink-python-*.jar /opt/flink/lib/ (+ install Python and requirements)
# ENTRYPOINT/CMD inherited: docker-entrypoint.sh drops privileges to user flink (uid 9999) — set pod fsGroup: 9999
```

Maven paths: `target/flink-lib/*.jar`, `target/<app>.jar`.

## FlinkDeployment (Helm template excerpt)

```yaml
apiVersion: flink.apache.org/v1beta1
kind: FlinkDeployment
metadata:
  name: <app>
  namespace: {{ .Values.namespace }}
  labels: { app: <app>, tla: <tla> }
spec:
  image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
  flinkVersion: v2_2
  mode: standalone
  serviceAccount: {{ .Values.serviceAccount.name }}          # IRSA: S3 + (optional) Bedrock
  flinkConfiguration:
    env.java.opts.all: "--add-exports=java.base/jdk.internal.vm=ALL-UNNAMED -Dlog4j2.formatMsgNoLookups=true"
    state.backend.type: rocksdb
    execution.checkpointing.incremental: "true"
    execution.checkpointing.interval: 60s
    execution.checkpointing.dir: s3://{{ .Values.s3BucketName }}/checkpoints
    execution.checkpointing.savepoint-dir: s3://{{ .Values.s3BucketName }}/savepoints
    execution.checkpointing.externalized-checkpoint-retention: RETAIN_ON_CANCELLATION
    high-availability.type: kubernetes
    high-availability.storageDir: s3://{{ .Values.s3BucketName }}/ha
    kubernetes.operator.periodic.savepoint.interval: 6h
    metrics.reporters: prom
    metrics.reporter.prom.factory.class: org.apache.flink.metrics.prometheus.PrometheusReporterFactory
    metrics.reporter.prom.port: "9249"
    taskmanager.numberOfTaskSlots: {{ .Values.taskManager.slots | quote }}
    # Flink Agents (keys per release docs) — action state store for exactly-once actions:
    # actionStateStoreBackend: kafka
    # kafkaBootstrapServers: {{ .Values.kafka.bootstrap }}
    # kafkaActionStateTopic: <app>-<agent>-action-state   # one topic per logical agent operator
  podTemplate:
    metadata:
      annotations: { k8s.grafana.com/job: <app> }
      labels: { app: <app> }
    spec:
      securityContext: { fsGroup: 9999 }
      containers:
        - name: flink-main-container
          env:
            - name: ENABLE_BUILT_IN_PLUGINS
              value: flink-s3-fs-hadoop-2.2.1.jar
            - name: OPENAI_API_KEY                         # example: only for key-based providers
              valueFrom: { secretKeyRef: { name: <app>-secrets, key: openai_api_key } }
          ports:
            - { name: metrics, containerPort: 9249, protocol: TCP }
  jobManager:
    replicas: 1
    resource: { cpu: {{ .Values.jobManager.cpu }}, memory: {{ .Values.jobManager.memory }} }
  taskManager:
    replicas: {{ .Values.taskManager.replicas }}
    resource: { cpu: {{ .Values.taskManager.cpu }}, memory: {{ .Values.taskManager.memory }} }
  job:
    jarURI: local:///opt/<tla>/<app>.jar
    entryClass: com.flutter.gst.<app>.<App>Job
    parallelism: {{ .Values.job.parallelism }}
    upgradeMode: savepoint
    state: {{ .Values.job.state | default "running" }}
  restartNonce: {{ .Values.job.restartNonce | default 1 }}
```

Also in the chart: Crossplane `S3Bucket` (lifecycle on `savepoints/`), `ServiceAccount` with the IRSA role,
`SecretStore` + `ExternalSecret` (AWS Secrets Manager → `<app>-secrets`), `PodMonitor` below. See
`Flutter-Global/gbsd` `resources/gbsd-helm/templates/` for a working set.

## PodMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: <app>-monitor
  namespace: {{ .Values.namespace }}
  labels: { app: <app> }
spec:
  selector:
    matchLabels: { app: <app>, type: flink-standalone-kubernetes }
  podMetricsEndpoints:
    - port: metrics
      path: /metrics
      interval: 30s
      honorLabels: true
```

## CI (Forge Flow, Option B — copy the full workflow from `forge-flow-ci`)

Only the `build` job of the release workflow differs from the Spring Boot example:

```yaml
  build:
    needs: release-please
    if: needs.release-please.outputs.release_created == 'true'
    uses: flutter-global/forge-flow-workflows/.github/workflows/java-build-scan-publish.yml@19573adc434fe6ba8429febf495530e12675b3b8 # v2.13.0
    with:
      runner: grt
      java-version: '21'                      # Flink image JDK
      java-build-tool: gradle
      gradle-version: '9.8.1'
      java-build-cmd: ./gradlew build         # produces build/libs/<app>.jar and build/flink-lib/
      # Maven: java-build-tool: maven / maven-version: '3.9.16' / java-build-cmd: ./mvnw -B verify
      repo-resolve: grt-maven
      repo-deploy: grt-maven-local
      sonar-run: true
      release-tag: ${{ needs.release-please.outputs.tag_name }}
      container-publish: true
      container-registry: grt-container-local
      containerfile-location: Dockerfile
      container-image-name: <app>
      container-image-version: ${{ needs.release-please.outputs.release_version }}
    secrets:
      GH_PKG_XREPO_USER: ${{ secrets.CATALYST_GITHUB_USERNAME }}
      GH_PKG_XREPO_TOKEN: ${{ secrets.CATALYST_GITHUB_TOKEN }}
      ORG_SONAR_TOKEN: ${{ secrets.ORG_SONAR_TOKEN }}
      ORG_SONAR_PROVISION_TOKEN: ${{ secrets.ORG_SONAR_PROVISION_TOKEN }}
```

Re-resolve pins as described in `forge-flow-ci`; run `actionlint` after editing.
