# Shopping Cart Infrastructure Repository

**Repository Type:** Implementation
**Architecture Reference:** [shopping-cart blueprint repository](https://github.com/user/shopping-cart)

## Overview

This repository contains the **actual Kubernetes infrastructure implementation** for the Shopping Cart GitOps demo application. It is one of 5 repositories in the multi-repo architecture:

- **shopping-cart-frontend** - React application (separate repo)
- **shopping-cart-product-catalog** - Python service (separate repo)
- **shopping-cart-cart** - Go service (separate repo)
- **shopping-cart-order** - Java service (separate repo)
- **shopping-cart-infrastructure** - This repository (Kubernetes manifests, Helm charts)

## Purpose

This repository provides:

1. **Data Layer Infrastructure** - PostgreSQL and Redis StatefulSets
2. **Vault Integration** - Dynamic database credentials and secure secrets management
3. **Helm Charts** - Application service deployment templates
4. **Argo CD Applications** - GitOps deployment configuration
5. **External Secrets** - Vault integration for credential management
6. **Namespace Definitions** - Two-tier namespace model

**Planned:** RabbitMQ message queue for asynchronous order processing and event-driven architecture (see [Message Queue Implementation Plan](docs/plans/message-queue-implementation.md))

## Architecture Reference

For detailed architecture documentation, design decisions, and planning documents, see the **[shopping-cart blueprint repository](https://github.com/user/shopping-cart)**.

Key blueprint documents:
- `docs/plans/hybrid-architecture-plan.md` - Complete architecture specification
- `docs/implementation-priority.md` - Phase-by-phase implementation plan
- `docs/repository-setup-guide.md` - Multi-repo setup instructions
- `docs/cicd-guide.md` - CI/CD pipeline configuration

## Repository Structure

```
shopping-cart-infrastructure/
├── data-layer/                     # Infrastructure (shopping-cart-data namespace)
│   ├── postgresql/
│   │   ├── products/               # StatefulSet, Service, PVC, init-db.sql
│   │   └── orders/                 # StatefulSet, Service, PVC, init-db.sql
│   ├── redis/
│   │   ├── cart/                   # StatefulSet, Service, PVC
│   │   └── orders-cache/           # StatefulSet, Service, PVC
│   └── secrets/
│       ├── postgres-products-secret.yaml   # ExternalSecret (dynamic Vault creds)
│       ├── postgres-orders-secret.yaml     # ExternalSecret (dynamic Vault creds)
│       ├── redis-cart-secret.yaml          # ExternalSecret (static password)
│       └── redis-orders-secret.yaml        # ExternalSecret (static password)
├── namespaces/
│   └── namespaces.yaml             # shopping-cart-data + shopping-cart-apps
├── vault/
│   └── setup-database-secrets-engine.sh  # Configure Vault DB secrets engine
├── chart/                          # Helm chart for application services
│   ├── Chart.yaml
│   ├── values.yaml                 # Demo environment (8GB)
│   ├── values-prod.yaml            # Production overrides
│   └── templates/
│       ├── product-catalog/
│       ├── cart/
│       ├── order/
│       └── frontend/
└── argocd/
    ├── projects/
    │   └── shopping-cart.yaml
    └── applications/
        ├── shopping-cart-infrastructure.yaml  # Data layer
        ├── shopping-cart-dev.yaml             # Application services
        └── shopping-cart-prod.yaml            # Production deployment
```

## Two-Tier Namespace Model

### shopping-cart-data
- PostgreSQL StatefulSets (products, orders)
- Redis StatefulSets (cart, orders-cache)
- Infrastructure secrets (ExternalSecrets)
- Persistent storage

### shopping-cart-apps
- Application deployments (frontend, product-catalog, cart, order)
- Application ConfigMaps and Secrets
- Istio VirtualServices and DestinationRules

## Prerequisites

- k3d-manager cluster with required components:
  - Istio service mesh
  - HashiCorp Vault
  - External Secrets Operator (ESO)
  - Argo CD
- kubectl configured
- Vault initialized and unsealed

## Deployment

### 1. Deploy Data Layer Infrastructure

```bash
# Apply namespaces
kubectl apply -f namespaces/namespaces.yaml

# Configure Vault database secrets engine
./vault/setup-database-secrets-engine.sh

# Deploy PostgreSQL StatefulSets
kubectl apply -f data-layer/postgresql/products/
kubectl apply -f data-layer/postgresql/orders/

# Deploy Redis StatefulSets
kubectl apply -f data-layer/redis/cart/
kubectl apply -f data-layer/redis/orders-cache/

# Deploy ExternalSecrets (connects Vault → K8s secrets)
kubectl apply -f data-layer/secrets/
```

### 2. Deploy via Argo CD (GitOps)

```bash
# Apply AppProject
kubectl apply -f argocd/projects/shopping-cart.yaml

# Deploy infrastructure (PostgreSQL + Redis)
kubectl apply -f argocd/applications/shopping-cart-infrastructure.yaml

# Deploy application services
kubectl apply -f argocd/applications/shopping-cart-dev.yaml

# Verify sync status
argocd app list
argocd app get shopping-cart-dev
```

## Resource Requirements

### Demo Environment (8GB System)
- **PostgreSQL Products:** 256Mi request / 512Mi limit
- **PostgreSQL Orders:** 256Mi request / 512Mi limit
- **Redis Cart:** 128Mi request / 256Mi limit
- **Redis Orders Cache:** 128Mi request / 256Mi limit
- **Total Data Layer:** ~768Mi request / ~1.5Gi limit

### Production Environment
Override resources in `chart/values-prod.yaml`:
- PostgreSQL: 1Gi - 2Gi per instance
- Redis: 512Mi - 1Gi per instance
- Enable persistent storage with appropriate StorageClass

## Vault Integration

### Database Secrets Engine
PostgreSQL credentials are generated dynamically by Vault:

```bash
# Vault configuration (automated by setup script)
vault secrets enable database

vault write database/config/postgresql-products \
  plugin_name=postgresql-database-plugin \
  allowed_roles="products-readonly" \
  connection_url="postgresql://{{username}}:{{password}}@postgresql-products.shopping-cart-data.svc.cluster.local:5432/products" \
  username="postgres" \
  password="$POSTGRES_PASSWORD"

vault write database/roles/products-readonly \
  db_name=postgresql-products \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"
```

### Static Secrets (Redis)
Redis passwords stored in Vault KV:

```bash
vault kv put secret/redis/cart password="changeme"
vault kv put secret/redis/orders password="changeme"
```

### ExternalSecret Sync
ESO automatically syncs secrets from Vault to Kubernetes:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: postgres-products-secret
  namespace: shopping-cart-data
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: postgres-products-secret
  data:
    - secretKey: username
      remoteRef:
        key: database/creds/products-readonly
        property: username
    - secretKey: password
      remoteRef:
        key: database/creds/products-readonly
        property: password
```

## CI/CD Integration

### Overview
This repository integrates with GitHub Actions and Jenkins for automated container image builds and deployments.

**Workflow:**
1. Application repo triggers GitHub Actions on push
2. GitHub Actions builds and pushes image to GHCR
3. GitHub Actions triggers Jenkins webhook
4. Jenkins updates this repo's Helm values
5. Argo CD syncs and deploys to Kubernetes

### Documentation
- **[Container Image Workflow Guide](docs/container-image-workflow.md)** - Complete guide for building and pushing images to GHCR
- **[GitHub Actions & Jenkins Webhook Setup](docs/github-actions-webhook-setup.md)** - Step-by-step integration instructions
- **[Examples Directory](examples/README.md)** - Dockerfiles, GitHub Actions templates, and quick start guide

### Automation Scripts
Located in `bin/`:
- **`build-and-push.sh`** - Build and push container images locally for testing
- **`setup-service-repo.sh`** - Automate GitHub repository creation with Actions workflows
- **`deploy-infra.sh`** - Deploy complete infrastructure stack

### Example: Automated CI Pipeline
```bash
# Example: Product Catalog service CI pipeline
# 1. Build and push image: ghcr.io/user/product-catalog:abc123
# 2. Clone this repository
# 3. Update image tag in chart/values-dev.yaml
yq eval ".productCatalog.image.tag = 'abc123'" -i chart/values-dev.yaml
# 4. Commit and push
git commit -m "Update product-catalog to abc123"
git push origin main
# 5. Argo CD detects change and syncs
```

See the blueprint repository's `docs/cicd-guide.md` for additional CI/CD patterns.

## Monitoring and Health Checks

```bash
# Check data layer pods
kubectl get pods -n shopping-cart-data

# Check PostgreSQL connectivity
kubectl run -n shopping-cart-data test-pg --rm -it --image=postgres:15-alpine -- psql -h postgresql-products -U postgres -d products

# Check Redis connectivity
kubectl run -n shopping-cart-data test-redis --rm -it --image=redis:7-alpine -- redis-cli -h redis-cart ping

# Check ExternalSecret sync status
kubectl get externalsecrets -n shopping-cart-data
kubectl describe externalsecret postgres-products-secret -n shopping-cart-data

# Verify Argo CD sync
argocd app list
argocd app get shopping-cart-infrastructure
```

## Troubleshooting

### ExternalSecret Not Syncing
```bash
# Check SecretStore status
kubectl get secretstore -n shopping-cart-data
kubectl describe secretstore vault-backend -n shopping-cart-data

# Check ESO controller logs
kubectl logs -n external-secrets deployment/external-secrets

# Verify Vault connectivity from pod
kubectl run -n shopping-cart-data test-vault --rm -it --image=curlimages/curl -- curl -k https://vault.vault.svc.cluster.local:8200/v1/sys/health
```

### PostgreSQL Connection Issues
```bash
# Check StatefulSet status
kubectl describe statefulset postgresql-products -n shopping-cart-data

# Check PVC status
kubectl get pvc -n shopping-cart-data

# View logs
kubectl logs -n shopping-cart-data postgresql-products-0

# Test connection with generated credentials
kubectl get secret postgres-products-secret -n shopping-cart-data -o jsonpath='{.data.username}' | base64 -d
kubectl get secret postgres-products-secret -n shopping-cart-data -o jsonpath='{.data.password}' | base64 -d
```

### Redis Connection Issues
```bash
# Check StatefulSet status
kubectl describe statefulset redis-cart -n shopping-cart-data

# View logs
kubectl logs -n shopping-cart-data redis-cart-0

# Test authentication
kubectl run -n shopping-cart-data test-redis --rm -it --image=redis:7-alpine -- redis-cli -h redis-cart -a $(kubectl get secret redis-cart-secret -n shopping-cart-data -o jsonpath='{.data.password}' | base64 -d) ping
```

## Security Best Practices

1. **Never commit secrets** - All credentials managed by Vault and ESO
2. **Use network policies** - Restrict inter-service communication
3. **Enable TLS** - PostgreSQL and Redis should use TLS in production
4. **Rotate credentials** - Vault automatically rotates database credentials
5. **Audit access** - Monitor Vault audit logs for secret access
6. **Limit privileges** - Database roles should have minimal required permissions

## Development

### Local Testing
```bash
# Create k3d cluster with required components
./scripts/k3d-manager deploy_cluster
./scripts/k3d-manager deploy_vault
./scripts/k3d-manager deploy_eso

# Deploy infrastructure
kubectl apply -f namespaces/namespaces.yaml
./vault/setup-database-secrets-engine.sh
kubectl apply -f data-layer/
```

### Configuration Changes
1. Modify manifests in this repository
2. Commit and push changes
3. Argo CD automatically syncs (if auto-sync enabled)
4. Or manually sync: `argocd app sync shopping-cart-infrastructure`

## Planned Enhancements

### Message Queue Infrastructure (RabbitMQ)

**Status**: Planned (see [detailed implementation plan](docs/plans/message-queue-implementation.md))

**Objective**: Add RabbitMQ message queue to enable asynchronous order processing and event-driven architecture.

**Benefits**:
- Faster user response times (order creation < 100ms vs 500ms+ synchronous)
- Automatic retry on failures
- Independent service scaling
- Better fault isolation
- Event-driven microservices communication

**Implementation Stages**:
1. **Stage 1**: Infrastructure setup (RabbitMQ StatefulSet in `shopping-cart-data`)
2. **Stage 2**: Vault integration (dynamic credential management)
3. **Stage 3**: Application integration (publisher/consumer libraries)
4. **Stage 4**: Monitoring & production readiness

**Use Cases**:
- Order processing pipeline (payment, email, fulfillment)
- Inventory updates and cache invalidation
- Shopping cart abandonment notifications
- Cross-service event broadcasting

**Timeline**: 4 stages, ~15-20 hours total effort

For complete architecture, queue design, and implementation details, see [Message Queue Implementation Plan](docs/plans/message-queue-implementation.md).

---

### Vault Integration Enhancements

**Current**: Dynamic PostgreSQL credentials, static Redis passwords

**Documentation**:
- [Vault Usage Guide](docs/vault-usage-guide.md) - Complete integration guide
- [Vault Password Rotation](docs/vault-password-rotation.md) - Rotation testing and best practices
- [Integration Test](bin/test-vault-integration.sh) - Automated Vault functionality test
- [Rotation Test](bin/test-vault-rotation.sh) - Password lifecycle validation

## License

MIT

## Related Repositories

- **Blueprint/Architecture:** [shopping-cart](https://github.com/user/shopping-cart)
- **Application Services:**
  - [shopping-cart-frontend](https://github.com/user/shopping-cart-frontend)
  - [shopping-cart-product-catalog](https://github.com/user/shopping-cart-product-catalog)
  - [shopping-cart-cart](https://github.com/user/shopping-cart-cart)
  - [shopping-cart-order](https://github.com/user/shopping-cart-order)
