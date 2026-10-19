# Cloud Native - Spring Cloud

## Spring Cloud Config Server

```java
// Config Server
@SpringBootApplication
@EnableConfigServer
public class ConfigServerApplication {
    public static void main(String[] args) {
        SpringApplication.run(ConfigServerApplication.class, args);
    }
}

// application.yml
server:
  port: 8888

spring:
  cloud:
    config:
      server:
        git:
          uri: https://github.com/example/config-repo
          default-label: main
          search-paths: '{application}'
          # credentials: configure via environment variables
        native:
          search-locations: classpath:/config

// Config Client
@SpringBootApplication
public class ClientApplication {
    public static void main(String[] args) {
        SpringApplication.run(ClientApplication.class, args);
    }
}

// application.yml (Config Client)
spring:
  application:
    name: user-service
  config:
    import: "configserver:http://localhost:8888"
  cloud:
    config:
      # credentials: configure via environment variables
      fail-fast: true
      retry:
        max-attempts: 6
        initial-interval: 1000
```

## Dynamic Configuration Refresh

```java
@RestController
@RefreshScope
public class ConfigController {
    @Value("${app.feature.enabled:false}")
    private boolean featureEnabled;

    @Value("${app.max-connections:100}")
    private int maxConnections;

    @GetMapping("/config")
    public Map<String, Object> getConfig() {
        return Map.of(
            "featureEnabled", featureEnabled,
            "maxConnections", maxConnections
        );
    }
}

// Refresh configuration via Actuator endpoint:
// POST /actuator/refresh
```

## Service Discovery - Eureka

```java
// Eureka Server
@SpringBootApplication
@EnableEurekaServer
public class EurekaServerApplication {
    public static void main(String[] args) {
        SpringApplication.run(EurekaServerApplication.class, args);
    }
}

// application.yml (Eureka Server)
server:
  port: 8761

eureka:
  instance:
    hostname: localhost
  client:
    register-with-eureka: false
    fetch-registry: false
    service-url:
      defaultZone: http://${eureka.instance.hostname}:${server.port}/eureka/

// Eureka Client
@SpringBootApplication
@EnableDiscoveryClient
public class UserServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(UserServiceApplication.class, args);
    }
}

// application.yml (Eureka Client)
spring:
  application:
    name: user-service

eureka:
  client:
    service-url:
      defaultZone: http://localhost:8761/eureka/
    registry-fetch-interval-seconds: 5
  instance:
    prefer-ip-address: true
    lease-renewal-interval-in-seconds: 10
    lease-expiration-duration-in-seconds: 30
```

## Spring Cloud Gateway

```java
@SpringBootApplication
public class GatewayApplication {
    public static void main(String[] args) {
        SpringApplication.run(GatewayApplication.class, args);
    }

    @Bean
    public RouteLocator customRouteLocator(RouteLocatorBuilder builder) {
        return builder.routes()
            .route("user-service", r -> r
                .path("/api/users/**")
                .filters(f -> f
                    .rewritePath("/api/users/(?<segment>.*)", "/users/${segment}")
                    .addRequestHeader("X-Gateway", "Spring-Cloud-Gateway")
                    .circuitBreaker(config -> config
                        .setName("userServiceCircuitBreaker")
                        .setFallbackUri("forward:/fallback/users")
                    )
                    .retry(config -> config
                        .setRetries(3)
                        .setStatuses(HttpStatus.SERVICE_UNAVAILABLE)
                    )
                )
                .uri("lb://user-service")
            )
            .route("order-service", r -> r
                .path("/api/orders/**")
                .filters(f -> f
                    .rewritePath("/api/orders/(?<segment>.*)", "/orders/${segment}")
                    .requestRateLimiter(config -> config
                        .setRateLimiter(redisRateLimiter())
                        .setKeyResolver(userKeyResolver())
                    )
                )
                .uri("lb://order-service")
            )
            .build();
    }

    @Bean
    public RedisRateLimiter redisRateLimiter() {
        return new RedisRateLimiter(10, 20); // replenishRate, burstCapacity
    }

    @Bean
    public KeyResolver userKeyResolver() {
        return exchange -> Mono.justOrEmpty(
            exchange.getRequest().getHeaders().getFirst("X-User-Id")
        ).defaultIfEmpty("anonymous");
    }
}

// application.yml (Gateway)
spring:
  cloud:
    gateway:
      discovery:
        locator:
          enabled: true
          lower-case-service-id: true
      default-filters:
        - DedupeResponseHeader=Access-Control-Allow-Origin
      globalcors:
        cors-configurations:
          '[/**]':
            allowed-origins: "*"
            allowed-methods:
              - GET
              - POST
              - PUT
              - DELETE
            allowed-headers: "*"
```

## Circuit Breaker - Resilience4j

```java
@Service
public class ExternalApiService {
    private static final Logger log = LoggerFactory.getLogger(ExternalApiService.class);

    private final RestClient restClient;

    public ExternalApiService(RestClient.Builder builder) {
        this.restClient = builder
            .baseUrl("https://api.external.com")
            .build();
    }

    @CircuitBreaker(name = "externalApi", fallbackMethod = "getFallbackData")
    @Retry(name = "externalApi")
    @RateLimiter(name = "externalApi")
    public ExternalData getData(String id) {
        return restClient
            .get()
            .uri("/data/{id}", id)
            .retrieve()
            .body(ExternalData.class);
    }

    private ExternalData getFallbackData(String id, Exception e) {
        log.warn("Fallback triggered for id: {}, error: {}", id, e.getMessage());
        return new ExternalData(id, "Fallback data", LocalDateTime.now());
    }
}

// application.yml
resilience4j:
  circuitbreaker:
    instances:
      externalApi:
        register-health-indicator: true
        sliding-window-size: 10
        minimum-number-of-calls: 5
        permitted-number-of-calls-in-half-open-state: 3
        automatic-transition-from-open-to-half-open-enabled: true
        wait-duration-in-open-state: 5s
        failure-rate-threshold: 50
        event-consumer-buffer-size: 10

  retry:
    instances:
      externalApi:
        max-attempts: 3
        wait-duration: 1s
        enable-exponential-backoff: true
        exponential-backoff-multiplier: 2

  ratelimiter:
    instances:
      externalApi:
        limit-for-period: 10
        limit-refresh-period: 1s
        timeout-duration: 0s
```

## Distributed Tracing - Micrometer + OpenTelemetry

### OTLP Exporter (Preferred)

```yaml
# application.yml - OpenTelemetry Protocol (Boot 4 property names)
management:
  tracing:
    sampling:
      probability: 1.0          # lower (e.g. 0.1) in prd
  opentelemetry:
    tracing:
      export:
        otlp:
          endpoint: http://localhost:4318/v1/traces

logging:
  pattern:
    level: "%5p [${spring.application.name:},%X{traceId:-},%X{spanId:-}]"
```

```kotlin
// Boot 4: one starter brings Micrometer tracing bridge + OTLP exporters (metrics, traces, logs)
implementation("org.springframework.boot:spring-boot-starter-opentelemetry")
```

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-opentelemetry</artifactId>
</dependency>
```

> Boot 3 used `management.otlp.tracing.endpoint` plus separate `micrometer-tracing-bridge-otel` / `opentelemetry-exporter-otlp`
> dependencies. Migrate both when upgrading (see `spring-boot-4-migration`).

### Custom Spans with Observation API

```java
@Service
public class OrderService {
    private final ObservationRegistry observationRegistry;
    private final OrderRepository orderRepository;

    public OrderService(ObservationRegistry observationRegistry, OrderRepository orderRepository) {
        this.observationRegistry = observationRegistry;
        this.orderRepository = orderRepository;
    }

    public Order processOrder(OrderRequest request) {
        return Observation.createNotStarted("order.process", observationRegistry)
            .lowCardinalityKeyValue("order.type", request.type())
            .observe(() -> {
                Order order = createOrder(request);
                return order;
            });
    }
}
```

## Load Balancing with Spring Cloud LoadBalancer

```java
@Configuration
@LoadBalancerClient(name = "user-service", configuration = UserServiceLoadBalancerConfig.class)
public class LoadBalancerConfiguration {
}

@Configuration
public class UserServiceLoadBalancerConfig {

    @Bean
    public ReactorLoadBalancer<ServiceInstance> randomLoadBalancer(
            LoadBalancerClientFactory clientFactory,
            ObjectProvider<LoadBalancerProperties> properties) {
        return new RandomLoadBalancer(
            clientFactory.getLazyProvider("user-service", ServiceInstanceListSupplier.class),
            "user-service"
        );
    }
}

@Service
public class UserClientService {
    private final RestClient restClient;

    public UserClientService(RestClient.Builder builder) {
        this.restClient = builder
            .baseUrl("http://user-service")
            .build();
    }

    public User getUser(Long id) {
        return restClient
            .get()
            .uri("/users/{id}", id)
            .retrieve()
            .body(User.class);
    }
}
```

## Health Checks, Actuator & Prometheus

```xml
<!-- pom.xml - Prometheus metrics endpoint -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

```yaml
# application.yml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: when-authorized
      probes:
        enabled: true
  health:
    livenessState:
      enabled: true
    readinessState:
      enabled: true
  metrics:
    tags:
      application: ${spring.application.name}
```

```java
@Component
public class CustomHealthIndicator implements HealthIndicator {

    @Override
    public Health health() {
        boolean serviceUp = checkExternalService();

        if (serviceUp) {
            return Health.up()
                .withDetail("externalService", "Available")
                .withDetail("timestamp", LocalDateTime.now())
                .build();
        } else {
            return Health.down()
                .withDetail("externalService", "Unavailable")
                .withDetail("error", "Connection timeout")
                .build();
        }
    }

    private boolean checkExternalService() {
        // Check external dependency
        return true;
    }
}
```

## Kubernetes Deployment (Olympus)

GST services deploy to **Olympus** (EKS + Argo CD) via Helm charts and a `<repo>-infra` repository.
Do not hand-write generic Deployment/Ingress/cert-manager manifests here — load the **`olympus-deploy`**
skill for chart layout, probes, secrets (External Secrets Operator), TLS, metrics and ingress conventions.

Spring-side settings that Olympus relies on:

```yaml
management:
  server:
    port: 8081               # probes + /actuator/prometheus on the "management" port
  endpoint:
    health:
      probes:
        enabled: true          # /actuator/health/liveness + /readiness
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
server:
  shutdown: graceful
spring:
  lifecycle:
    timeout-per-shutdown-phase: 20s
  config:
    import: "optional:configtree:/run/secrets/"   # only if secrets are mounted as files
```

## Virtual Threads

```yaml
# application.yml - one line enables virtual threads for all request handling
spring:
  threads:
    virtual:
      enabled: true
```

Virtual threads eliminate the need for WebFlux in most cases. With `spring.threads.virtual.enabled=true`:
- Tomcat handles each request on a virtual thread
- Blocking I/O (JDBC, RestClient, file I/O) no longer wastes platform threads
- `@Async` tasks run on virtual threads automatically
- No code changes required - existing blocking code scales like reactive

**When to still use WebFlux:** streaming responses, SSE, WebSocket, or when you need backpressure.

## HTTP Interface Clients (Spring Framework 7 / Boot 4)

```java
// Declarative HTTP client - replaces OpenFeign
public interface UserClient {

    @GetExchange("/users/{id}")
    UserResponse getUser(@PathVariable Long id);

    @GetExchange("/users")
    List<UserResponse> getAllUsers();

    @PostExchange("/users")
    UserResponse createUser(@RequestBody UserCreateRequest request);
}

// Boot 4 preferred: register clients declaratively, configure via properties
// spring.http.serviceclient.users.base-url=http://user-service
@Configuration
@ImportHttpServices(group = "users", types = UserClient.class)
public class HttpClientsConfig {}

// Manual alternative
@Configuration
public class ClientConfig {

    @Bean
    public UserClient userClient(RestClient.Builder builder) {
        RestClient restClient = builder
            .baseUrl("http://user-service")
            .build();
        return HttpServiceProxyFactory
            .builderFor(RestClientAdapter.create(restClient))
            .build()
            .createClient(UserClient.class);
    }
}
```

## GraalVM Native Image

```xml
<!-- pom.xml (parent spring-boot-starter-parent 4.1.x) -->
<plugin>
    <groupId>org.graalvm.buildtools</groupId>
    <artifactId>native-maven-plugin</artifactId>
</plugin>
```

```kotlin
// build.gradle.kts
plugins { id("org.graalvm.buildtools.native") version "<latest>" }
```

```bash
./mvnw -Pnative native:compile        # Maven
./gradlew nativeCompile               # Gradle
```

Benefits: ~50ms startup, ~50MB RSS memory. Trade-offs: longer build time, reflection requires hints.
GST default is the JVM image (Java 25 + AOT cache). Use native only when the user explicitly asks; it needs a GraalVM build in CI.

## Graceful Shutdown

```yaml
# application.yml - required for zero-downtime K8s rolling updates
server:
  shutdown: graceful

spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s
```

```yaml
# Kubernetes - add preStop hook to allow deregistration
spec:
  containers:
  - name: app
    lifecycle:
      preStop:
        exec:
          command: ["sh", "-c", "sleep 10"]
```

## Container Images

Images are built and published by **Forge Flow** (`java-build-scan-publish.yml`) from a `Dockerfile`
to `flutter.jfrog.io/grt-container-local`. See the **`forge-flow-ci`** skill and the
`spring-docker-expert` agent for the Java 25 Dockerfile template.

## Quick Reference

| Component | Purpose |
|-----------|---------|
| **Config Server** | Centralized configuration management |
| **Eureka** | Service discovery and registration |
| **Gateway** | API gateway with routing, filtering, load balancing |
| **Circuit Breaker** | Fault tolerance and fallback patterns |
| **Load Balancer** | Client-side load balancing |
| **Tracing (OTLP)** | Distributed tracing with OpenTelemetry |
| **Actuator** | Production-ready monitoring and management |
| **Virtual Threads** | High-throughput blocking I/O without WebFlux |
| **HTTP Interfaces** | Declarative HTTP clients (replaces Feign) |
| **Native Image** | Fast startup, low memory with GraalVM |
| **Forge Flow** | Reusable CI: build, scan, publish image to Forge Store (JFrog) |
| **Config Tree** | Read secrets from mounted files instead of env vars |
| **SSL Bundles** | Unified SSL config with hot reload (see security reference) |
| **Olympus** | EKS + Argo CD platform; Helm chart + `<repo>-infra` repo (see `olympus-deploy`) |
