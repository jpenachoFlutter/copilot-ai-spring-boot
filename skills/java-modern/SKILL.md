---
name: java-modern
description: Java 25 (LTS) features for Spring Boot 4 - records, sealed classes, pattern matching, virtual threads, scoped values, stream gatherers, flexible constructor bodies, module imports, compact object headers. Use when user asks about modern Java, Java 25 features, or when modernizing existing code.
---

# Java Modern Skill

Java 25 (LTS) language features, the GST baseline, and how to use them in Spring Boot 4 applications.
Preview features (`--enable-preview`) are **not** allowed in GST production code. Everything below is final in Java 25 unless marked otherwise.

## When to Use
- Building new Spring Boot 4.x applications (default to modern features)
- Modernizing/refactoring existing Java code
- User asks about records, sealed classes, pattern matching, virtual threads

---

## Records (Java 16+)

### DTOs

```java
// ✅ Records for request/response DTOs
public record ProductRequest(
    @NotBlank String name,
    @DecimalMin("0.0") BigDecimal price
) {}

public record ProductResponse(
    Long id,
    String name,
    BigDecimal price,
    LocalDateTime createdAt
) {
    public static ProductResponse from(Product entity) {
        return new ProductResponse(
            entity.getId(),
            entity.getName(),
            entity.getPrice(),
            entity.getCreatedAt()
        );
    }
}
```

### Configuration Properties

```java
// ✅ Records for config properties (Spring Boot 4.x)
@ConfigurationProperties(prefix = "app.notification")
public record NotificationProperties(
    boolean enabled,
    String fromEmail,
    Duration timeout,
    Retry retry
) {
    public record Retry(int maxAttempts, Duration delay) {}
}
```

### When NOT to use records
- JPA entities (Hibernate needs mutable objects, no-arg constructor)
- Classes that need inheritance
- Objects with mutable state

---

## Sealed Classes (Java 17+)

### Domain Modeling

```java
// ✅ Restrict payment types at compile time
public sealed interface PaymentResult
    permits PaymentSuccess, PaymentFailure, PaymentPending {
}

public record PaymentSuccess(String transactionId, BigDecimal amount)
    implements PaymentResult {}

public record PaymentFailure(String errorCode, String message)
    implements PaymentResult {}

public record PaymentPending(String referenceId)
    implements PaymentResult {}

// Usage in service
public PaymentResult processPayment(PaymentRequest request) {
    try {
        String txId = gateway.charge(request);
        return new PaymentSuccess(txId, request.amount());
    } catch (InsufficientFundsException e) {
        return new PaymentFailure("INSUFFICIENT_FUNDS", e.getMessage());
    }
}
```

### Event Hierarchies

```java
public sealed interface OrderEvent
    permits OrderCreated, OrderShipped, OrderCancelled {

    Long orderId();
    LocalDateTime timestamp();
}

public record OrderCreated(Long orderId, LocalDateTime timestamp, Long customerId)
    implements OrderEvent {}

public record OrderShipped(Long orderId, LocalDateTime timestamp, String trackingNumber)
    implements OrderEvent {}

public record OrderCancelled(Long orderId, LocalDateTime timestamp, String reason)
    implements OrderEvent {}
```

---

## Pattern Matching

### instanceof (Java 16+)

```java
// ❌ Old style
if (obj instanceof String) {
    String s = (String) obj;
    return s.length();
}

// ✅ Pattern matching
if (obj instanceof String s) {
    return s.length();
}
```

### switch (Java 21+)

```java
// ✅ Exhaustive switch with sealed types - compiler enforces all cases
public String handlePayment(PaymentResult result) {
    return switch (result) {
        case PaymentSuccess s -> "Paid: " + s.transactionId();
        case PaymentFailure f -> "Failed: " + f.message();
        case PaymentPending p -> "Pending: " + p.referenceId();
    };
}

// ✅ Guarded patterns
public BigDecimal calculateDiscount(Order order) {
    return switch (order) {
        case Order o when o.getTotal().compareTo(new BigDecimal("100")) > 0 ->
            o.getTotal().multiply(new BigDecimal("0.10"));
        case Order o when o.isLoyaltyMember() ->
            o.getTotal().multiply(new BigDecimal("0.05"));
        default -> BigDecimal.ZERO;
    };
}
```

### In Service Logic

```java
// Replacing if-else chains with pattern matching
public String processNotification(Object event) {
    return switch (event) {
        case OrderCreated o when o.total().compareTo(BigDecimal.valueOf(1000)) > 0 ->
            sendPriorityNotification(o);
        case OrderCreated o -> sendStandardNotification(o);
        case OrderCancelled c -> sendCancellationNotification(c);
        case PaymentReceived p -> sendPaymentConfirmation(p);
        default -> throw new IllegalArgumentException("Unknown event: " + event);
    };
}

// Pattern matching with instanceof — no more casting
public BigDecimal calculateShipping(Address address) {
    if (address instanceof DomesticAddress d) {
        return d.isExpressZone() ? DOMESTIC_EXPRESS : DOMESTIC_STANDARD;
    } else if (address instanceof InternationalAddress i) {
        return BASE_INTERNATIONAL.multiply(i.distanceFactor());
    }
    throw new IllegalArgumentException("Unknown address type");
}
```

### In Exception Handlers

```java
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handle(Exception ex) {
        return switch (ex) {
            case EntityNotFoundException e ->
                ResponseEntity.status(404).body(new ErrorResponse(e.getMessage()));
            case DataIntegrityViolationException e ->
                ResponseEntity.status(409).body(new ErrorResponse("Duplicate entry"));
            case ConstraintViolationException e ->
                ResponseEntity.badRequest().body(new ErrorResponse(e.getMessage()));
            default ->
                ResponseEntity.internalServerError().body(new ErrorResponse("Unexpected error"));
        };
    }
}
```

---

## Virtual Threads (Java 25 + Spring Boot 4.x)

```yaml
# application.yml - enables virtual threads for all request handling
spring:
  threads:
    virtual:
      enabled: true
```

This single property:
- Runs each HTTP request on a virtual thread (Tomcat)
- Makes `@Async` methods use virtual threads
- Allows blocking I/O (JDBC, RestClient) to scale like reactive code

```java
// ✅ Blocking code scales with virtual threads - no code changes needed
@Service
@Transactional(readOnly = true)
public class ReportService {
    private final OrderRepository orderRepository;
    private final RestClient externalApi;

    public ReportService(OrderRepository orderRepository, RestClient externalApi) {
        this.orderRepository = orderRepository;
        this.externalApi = externalApi;
    }

    public Report generate(Long customerId) {
        // Both blocking calls - on virtual threads this scales to thousands of concurrent requests
        List<Order> orders = orderRepository.findByCustomerId(customerId);
        CustomerData data = externalApi.get()
            .uri("/customers/{id}", customerId)
            .retrieve()
            .body(CustomerData.class);
        return new Report(orders, data);
    }
}
```

**Notes for Java 25:**
- `synchronized` no longer pins carrier threads (JEP 491, Java 24), so the old "replace `synchronized` with `ReentrantLock`" advice is obsolete. Native/JNI calls can still pin.
- Do not pool virtual threads, and do not use `ThreadLocal` as a cache (millions of threads mean millions of copies). Use `ScopedValue` for request context.
- CPU-bound work still belongs on a bounded platform-thread pool.

---

## Text Blocks (Java 15+)

```java
// ✅ JPQL queries
@Query("""
    SELECT p FROM Product p
    WHERE p.active = true
      AND p.price BETWEEN :minPrice AND :maxPrice
    ORDER BY p.name
    """)
List<Product> findActiveInPriceRange(
    @Param("minPrice") BigDecimal min,
    @Param("maxPrice") BigDecimal max);

// ✅ JSON in tests
mockMvc.perform(post("/api/v1/products")
    .contentType(MediaType.APPLICATION_JSON)
    .content("""
        {
            "name": "Widget",
            "price": 10.00
        }
        """))
    .andExpect(status().isCreated());
```

---

## Sequenced Collections (Java 21)

`SequencedCollection` adds `getFirst()`, `getLast()`, and `reversed()` to ordered collections.

```java
// ❌ Before Java 21
String first = list.get(0);
String last = list.get(list.size() - 1);

// ✅ Java 21+
String first = list.getFirst();
String last = list.getLast();

// Reversed view (no copy)
for (var item : list.reversed()) {
    process(item);
}

// Works with all ordered collections: List, Deque, SortedSet, LinkedHashSet, LinkedHashMap
SortedSet<User> users = userRepository.findTopByOrderByCreatedAtDesc();
User newest = users.getFirst();
User oldest = users.getLast();
```

---

## Java 22–25 Features (final in 25)

### Unnamed variables `_` (Java 22)

```java
try { parse(s); } catch (NumberFormatException _) { return Optional.empty(); }
map.forEach((_, value) -> process(value));
if (event instanceof OrderPlaced(var id, _, _)) { audit(id); }
```

### Stream gatherers (Java 24)

```java
// Fixed-size batches for bulk inserts / Kafka sends
List<List<Order>> batches = orders.stream()
    .gather(Gatherers.windowFixed(500))
    .toList();

// Concurrent mapping with bounded parallelism (uses virtual threads)
List<Price> prices = ids.stream()
    .gather(Gatherers.mapConcurrent(16, pricingClient::fetch))
    .toList();
```

### Flexible constructor bodies (Java 25, JEP 513)

```java
public final class Money extends Amount {
    public Money(BigDecimal value, Currency currency) {
        Objects.requireNonNull(currency);            // validate BEFORE super(...)
        if (value.signum() < 0) throw new IllegalArgumentException("negative");
        super(value.setScale(currency.getDefaultFractionDigits(), RoundingMode.HALF_EVEN));
    }
}
```

### Scoped values (Java 25, JEP 506): replaces ThreadLocal for request context

```java
public final class RequestContext {
    public static final ScopedValue<String> CORRELATION_ID = ScopedValue.newInstance();
}

// In a filter
ScopedValue.where(RequestContext.CORRELATION_ID, correlationId)
    .run(() -> chain.doFilter(request, response));   // wrap checked exceptions as needed

// Anywhere downstream on the same (virtual) thread
String id = RequestContext.CORRELATION_ID.orElse("n/a");
```

Values are immutable, automatically unbound when the scope exits, and cheap with virtual threads.
Keep MDC for logging (Micrometer Tracing populates it).

### Module import declarations (Java 25, JEP 511)

`import module java.base;` is fine for scripts, tests and compact source files. In production code, prefer explicit imports
for readability and to avoid ambiguous names.

### Compact source files & instance main (Java 25, JEP 512)

Use these for throwaway tools and scripts only (`java Tool.java`), never in service code.

### Runtime (no code change)

- **Compact object headers** (JEP 519): `-XX:+UseCompactObjectHeaders` cuts heap usage by about 10–20%. Enable it after load testing.
- **AOT cache** (JEPs 483/514/515): `-XX:AOTCacheOutput=app.aot` during a training run, then `-XX:AOTCache=app.aot` for faster startup.
- **Generational Shenandoah** (JEP 521) is now a product option. G1 remains the default and is right for most services.

### Still preview in 25 — do not use

Structured concurrency (`StructuredTaskScope`), primitive types in patterns, stable values.

---

## Quick Decision Guide

| Feature | Use For | Avoid When |
|---------|---------|------------|
| **Records** | DTOs, config, value objects | JPA entities, mutable state |
| **Sealed classes** | Closed type hierarchies, domain events | Open extension needed |
| **Pattern matching switch** | Handling sealed types, replacing if-else chains | Simple equality checks |
| **Virtual threads** | High-concurrency blocking I/O | CPU-bound work |
| **Scoped values** | Request/tenant/correlation context | Mutable per-thread state |
| **Stream gatherers** | Batching, windowing, bounded concurrent mapping | Simple map/filter |
| **Flexible constructors** | Validating/deriving args before `super(...)` | — |
| **Text blocks** | JPQL queries, JSON test data, SQL | Single-line strings |
| **SequencedCollections** | First/last access on ordered collections | Unordered sets/maps |
