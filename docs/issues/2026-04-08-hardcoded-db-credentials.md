# Issue: Hardcoded Database and Infrastructure Credentials

## Status
**Identified** (Architectural Debt)

## Description
Multiple data-layer components (PostgreSQL, Redis) and identity components (Keycloak) are currently using hardcoded credentials in `Secret` manifests. This violates security best practices and deviates from the project established pattern of using Vault + External Secrets Operator (ESO) for secret management.

Affected files:
- `identity/keycloak/secret.yaml` (`KC_DB_PASSWORD`)
- `data-layer/postgresql/products/secret.yaml` (`password`)
- `data-layer/postgresql/payment/secret.yaml` (`password`)
- `data-layer/postgresql/orders/secret.yaml` (`password`)
- `data-layer/redis/orders-cache/secret.yaml` (`password`)
- `data-layer/redis/cart/secret.yaml` (`password`)

## Root Cause
These manifests were initially created as development placeholders and have not yet been migrated to the automated Vault-backed secret flow.

## Recommended Fix: Migration to Vault + ESO

To manage these credentials securely, follow these steps:

### 1. Seed Secrets in Vault
Add the credentials to the Vault KV store during the cluster provision step in `k3d-manager/bin/acg-up`.
Example:
```bash
_vault_kv_put "{\"password\":\"$(openssl rand -base64 16)\"}" postgres/products
```

### 2. Replace Static Secrets with ExternalSecrets
Delete the `secret.yaml` files or replace their contents with `ExternalSecret` resources.
Example (`data-layer/postgresql/products/externalsecret.yaml`):
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: postgres-products-admin
  namespace: shopping-cart-data
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: postgres-products-admin
    creationPolicy: Owner
  data:
  - secretKey: password
    remoteRef:
      key: postgres/products
      property: password
```

### 3. Update StatefulSets/Deployments
Ensure the components (e.g., PostgreSQL StatefulSet) source their environment variables from the Secret created by the `ExternalSecret`.

### 4. Update Vault Policies
Verify that the `vault-backend` ClusterSecretStore has access to the new paths in Vault.

## Definition of Done
- [ ] No hardcoded passwords in any `secret.yaml` or `configmap.yaml` file.
- [ ] All database/cache credentials are sourced from Vault via `ExternalSecret`.
- [ ] Sandbox `make up` successfully provisions the cluster with randomized secrets.
