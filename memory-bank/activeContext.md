# Active Context: shopping-cart-infra

## Current State

Infrastructure stages 1–3 complete. The data layer (PostgreSQL, Redis, RabbitMQ) and identity stack (Keycloak + OpenLDAP) are deployed and functional. Argo CD GitOps is active. Stage 4 (monitoring integration) is in progress via the `observability-stack` sister repository.

## Implementation Progress

### Data Layer
- ✅ Stage 1: RabbitMQ StatefulSet deployed to `shopping-cart-data`
- ✅ Stage 2: Vault integration for RabbitMQ dynamic credentials (via ESO)
- ✅ PostgreSQL StatefulSets: products + orders
- ✅ Redis StatefulSets: cart + orders-cache
- ✅ Vault database secrets engine configured (products + orders roles)
- ✅ ExternalSecrets for all components

### Application Layer
- ✅ Helm chart for all 4 application services
- ✅ Argo CD AppProject + Applications (dev + prod)
- ✅ CI/CD pipeline: GitHub Actions → Jenkins → infra repo → Argo CD

### Identity
- ✅ Keycloak + OpenLDAP deployed in `identity` namespace
- ✅ Realm `shopping-cart` configured with `frontend` client

### Observability
- ⏳ Being handled by `observability-stack` repo (Stage 4)
- RabbitMQ Prometheus plugin enabled (port 15692 available for scraping)

## Known Issues / Docs

- `docs/issues/001-rabbitmq-nodeport.md` — RabbitMQ NodePort access issue
- `docs/issues/002-rabbitmq-prometheus-plugin.md` — Prometheus plugin configuration
- `docs/issues/deployment-troubleshooting.md` — Common deployment issues
- `docs/vault-password-rotation.md` — Rotation testing guide
- `docs/redis-password-rotation.md` — Redis password rotation

## Active Message Schemas

Documented in `docs/message-schemas.md`. Queues/exchanges:
- `cart.checkout` — Basket → Order (checkout event)
- `order.created` → Payment service
- `order.paid` → fulfillment/email

## CI/CD Flow (Current)

```
Application repo push
  → GitHub Actions builds + pushes GHCR image
  → Webhook triggers Jenkins
  → Jenkins updates chart/values-dev.yaml image tag
  → Git push to this repo
  → Argo CD auto-syncs shopping-cart-dev app
```

Docs: `docs/cicd-architecture.md`, `docs/container-image-workflow.md`, `docs/github-actions-webhook-setup.md`

## Pending Work

- [ ] Stage 4: Wire observability (ServiceMonitors, dashboards) — in `observability-stack` repo
- [ ] RabbitMQ load testing results integration — `docs/rabbitmq-load-testing.md` exists
- [ ] Production promotion workflow documentation
- [ ] Network policies for namespace isolation enforcement
