# Order Service RabbitMQ Health fails before rabbitmq-client 1.0.1

## Summary
- `/actuator/health` invokes Spring Boot's default `RabbitMQHealthIndicator`, which calls
  `CachingConnectionFactory.getCacheProperties()` before any AMQP channel exists and throws
  `NullPointerException`
- `shopping-cart-order` still depends on `rabbitmq-client:1.0.0-SNAPSHOT`, so the crash loops 24 times and
  startup probes fail with HTTP 503
- Temporary mitigation replaces the indicator with our own `RabbitHealthConfig`, but we need to bump to the
  official `rabbitmq-client` release (`1.0.1`) and remove the override when that version is published

## Details
- Logs from `order-service-65dd57bdf7-nmgzh`:
  ```
  java.lang.NullPointerException: Cannot invoke "java.util.concurrent.atomic.AtomicInteger.get()" because the return value of "java.util.Map.get(Object)" is null
      at org.springframework.amqp.rabbit.connection.CachingConnectionFactory.getCacheProperties(CachingConnectionFactory.java:966)
      at com.shoppingcart.rabbitmq.connection.ConnectionManager.getStats(ConnectionManager.java:212)
  ```
- Startup probe repeatedly fails (`Get "http://10.42.0.9:8080/actuator/health": dial tcp ... connection refused`)
- Current deployment uses `ghcr.io/wilddog64/shopping-cart-order@sha256:9809515...` built before rabbitmq-client commit `36ed860`

## Acceptance Criteria
1. Publish `rabbitmq-client-java` version `1.0.1` containing commit `36ed860` (guard `getCacheProperties()`)
2. `shopping-cart-order` updates `pom.xml` to depend on `com.shoppingcart:rabbitmq-client:1.0.1`
3. Remove `RabbitHealthConfig` override once dependency is bumped and verify `/actuator/health` stays UP during startup
4. Redeploy `order-service` image and confirm startup probes pass (no CrashLoopBackOff)

## Links
- Fix branch: `fix/rabbitmq-client-1.0.1` in shopping-cart-order
- Issue filed in app repo: https://github.com/wilddog64/shopping-cart-order/issues/23
- Image deployed: `ghcr.io/wilddog64/shopping-cart-order:2026-04-11-rabbit-health`
