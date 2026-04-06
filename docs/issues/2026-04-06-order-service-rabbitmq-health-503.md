---
date: 2026-04-06
service: order-service
symptom: CrashLoopBackOff (startup probe 503)
status: fix-ready (spec: docs/plans/v0.3.1-fix-order-service-spring-rabbitmq-config.md)
---

# Issue: order-service CrashLoopBackOff — RabbitMQ health check 503

## Symptom

`order-service` enters CrashLoopBackOff after every cold `make up`. The startup probe
(`/actuator/health`) returns 503, killing the pod before it passes.

```
Warning  Unhealthy  kubelet  Startup probe failed: HTTP probe failed with statuscode: 503
```

All other app pods come up cleanly. Data layer is healthy (rabbitmq-0, postgresql-orders-0 all 1/1).

## Root Cause

Spring Boot's AMQP auto-configuration creates a `CachingConnectionFactory` using
`spring.rabbitmq.*` properties. Because no `SPRING_RABBITMQ_*` env vars are set, it
defaults to `localhost:5672`.

The application also has a custom `ConnectionManager` that reads `RABBITMQ_HOST`/`RABBITMQ_PORT`
from the ConfigMap and connects correctly. But Spring's built-in `RabbitHealthIndicator`
uses the *auto-configured* `CachingConnectionFactory`, not the custom one. Every health
probe hits `localhost:5672`, gets `Connection refused`, and returns DOWN → 503.

```
INFO  CachingConnectionFactory : Attempting to connect to: [localhost:5672]
WARN  RabbitMQHealthIndicator  : Health check failed
WARN  RabbitHealthIndicator    : Rabbit health check failed
```

## Evidence

- `nc -zv rabbitmq.shopping-cart-data.svc.cluster.local 5672` → `open` (connectivity fine)
- Log shows `CachingConnectionFactory: Attempting to connect to: [localhost:5672]` (wrong host)
- Custom `ConnectionManager` log: `Successfully initialized RabbitMQ connection factory` (correct host)
- Two independent health indicators both fail on `localhost`

## Files Involved

| File | Issue |
|------|-------|
| `shopping-cart-order/k8s/base/configmap.yaml` | Missing `SPRING_RABBITMQ_HOST/PORT/VIRTUAL_HOST` |
| `shopping-cart-infra/data-layer/secrets/postgres-orders-apps-externalsecret.yaml` | Missing `SPRING_RABBITMQ_USERNAME/PASSWORD` in template |

## Fix

See `docs/plans/v0.3.1-fix-order-service-spring-rabbitmq-config.md`.

Add `SPRING_RABBITMQ_HOST`, `SPRING_RABBITMQ_PORT`, `SPRING_RABBITMQ_VIRTUAL_HOST` to the
ConfigMap. Add `SPRING_RABBITMQ_USERNAME`/`SPRING_RABBITMQ_PASSWORD` to the ExternalSecret
template (same Vault source as existing `RABBITMQ_USERNAME`/`RABBITMQ_PASSWORD` — credentials
remain Vault-managed, no hardcoded values).
