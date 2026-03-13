# Progress: shopping-cart-infra

## Infrastructure Stages

| Stage | Description | Status |
|---|---|---|
| 1 | RabbitMQ StatefulSet deployment | ✅ Complete |
| 2 | Vault integration for RabbitMQ dynamic credentials | ✅ Complete |
| 3 | Python client library | ✅ Complete (rabbitmq-client-python repo) |
| 3 | Go client library | ✅ Complete (rabbitmq-client-go repo) |
| 3 | Java client library | ✅ Complete (rabbitmq-client-java repo) |
| 4 | Monitoring & production readiness | ⏳ In Progress (observability-stack repo) |

## Built

### Data Layer
- [x] Namespace definitions (`shopping-cart-data`, `shopping-cart-apps`)
- [x] PostgreSQL StatefulSet: products (with init SQL schema)
- [x] PostgreSQL StatefulSet: orders (with init SQL schema)
- [x] Redis StatefulSet: cart session storage
- [x] Redis StatefulSet: orders-cache
- [x] RabbitMQ StatefulSet with management UI + Prometheus plugin
- [x] ExternalSecrets for all components (Vault → K8s Secrets)
- [x] Vault database secrets engine configuration script

### Application Services (Helm Chart)
- [x] Helm chart structure (`chart/`)
- [x] product-catalog templates (Python/FastAPI)
- [x] cart/basket templates (Go/Gin)
- [x] order templates (Java/Spring Boot)
- [x] frontend templates (React/nginx)
- [x] Demo values (`values.yaml`, 8GB constraints)
- [x] Production values (`values-prod.yaml`)
- [x] Dev values (`values-dev.yaml`, updated by CI)

### Argo CD GitOps
- [x] AppProject (`shopping-cart`)
- [x] Application: shopping-cart-infrastructure (data layer)
- [x] Application: shopping-cart-dev (app layer, auto-sync)
- [x] Application: shopping-cart-prod (app layer, manual sync)

### Identity Stack
- [x] Keycloak deployment in `identity` namespace
- [x] OpenLDAP deployment
- [x] Realm `shopping-cart` with `frontend` client

### CI/CD
- [x] `bin/build-and-push.sh` — Build/push images to GHCR
- [x] `bin/setup-service-repo.sh` — Automate new service repo creation
- [x] `bin/deploy-infra.sh` — Deploy full infrastructure stack
- [x] `examples/dockerfiles/` — Dockerfile templates for all service types
- [x] `examples/github-actions/` — GitHub Actions workflow templates

### Documentation
- [x] `docs/cicd-architecture.md`
- [x] `docs/container-image-workflow.md`
- [x] `docs/github-actions-webhook-setup.md`
- [x] `docs/message-schemas.md`
- [x] `docs/rabbitmq-client-library-design.md`
- [x] `docs/rabbitmq-operations.md`
- [x] `docs/rabbitmq-load-testing.md`
- [x] `docs/vault-usage-guide.md`
- [x] `docs/vault-password-rotation.md`
- [x] `docs/redis-password-rotation.md`
- [x] `docs/plans/message-queue-implementation.md`
- [x] Issue docs: 001 (RabbitMQ NodePort), 002 (Prometheus plugin)

### CI Stabilization (fix/ci-stabilization branch)
- [x] `shopping-cart-frontend`: TypeScript cleanup + `tsconfig` types (`5b69bd0`)
- [x] `shopping-cart-product-catalog`: Dockerfile apt upgrades (`c745bd3`)
- [x] `shopping-cart-payment`: GitHub Actions `./mvnw … -Dmaven.multiModuleProjectDirectory=.` (`7642f06` — local Maven wrapper download timed out)
- [x] `rabbitmq-client-java`: GitHub Packages publish workflow + distributionManagement (`0f1c9b1`)
- [x] `shopping-cart-order`: GitHub Packages repository + Maven settings/workflow update (`75c07bb` — local Maven unavailable)

## Pending

- [ ] Stage 4: Observability integration (being done in `observability-stack` repo)
- [ ] Network policies for strict namespace isolation
- [ ] Production promotion runbook
- [ ] RabbitMQ cluster (multi-node) configuration for HA
- [ ] PostgreSQL HA (read replicas)
- [ ] Backup/restore procedures for PostgreSQL and Redis

## Known Issues

| ID | Description | Status |
|---|---|---|
| 001 | RabbitMQ NodePort accessibility in k3d | Documented |
| 002 | RabbitMQ Prometheus plugin configuration | Documented |
