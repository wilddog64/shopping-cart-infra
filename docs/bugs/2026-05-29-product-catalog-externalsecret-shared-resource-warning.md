# Bug: ExternalSecret/product-catalog-secrets SharedResourceWarning

**Date:** 2026-05-29  
**Severity:** Low (warning only; does not block sync or pod startup)  
**Repo:** shopping-cart-infra  
**Branch to create:** `fix/product-catalog-externalsecret-shared-resource`

---

## Symptom

ArgoCD shows a SharedResourceWarning on the `data-layer` Application:

```
SharedResourceWarning: ExternalSecret/product-catalog-secrets is already owned
by application shopping-cart-product-catalog
```

The `data-layer` Application is `OutOfSync` due to this warning.

---

## Root Cause

Two ArgoCD Applications claim ownership of the same Kubernetes resource:

| Resource | Namespace | Owner 1 | Owner 2 |
|---|---|---|---|
| `ExternalSecret/product-catalog-secrets` | `shopping-cart-apps` | `data-layer` (this repo) | `shopping-cart-product-catalog` (services-git ApplicationSet) |

**Owner 1 — `data-layer`:**  
`data-layer/secrets/postgres-products-apps-externalsecret.yaml` in this repo creates an ExternalSecret named `product-catalog-secrets` in `shopping-cart-apps`.

**Owner 2 — `shopping-cart-product-catalog`:**  
The `services-git` ApplicationSet generates an Application from k3d-manager's `services/shopping-cart-product-catalog/kustomization.yaml`. That kustomization references `https://github.com/wilddog64/shopping-cart-product-catalog//k8s/base?ref=main`. That base includes `k8s/base/externalsecret.yaml` which also creates `product-catalog-secrets` in `shopping-cart-apps`.

**Why only product-catalog?**  
The other three `*-apps-externalsecret.yaml` files in `data-layer/secrets/` are not duplicated:
- `postgres-orders-apps-externalsecret.yaml` — order service k8s/base has no ExternalSecret
- `redis-cart-apps-externalsecret.yaml` — basket service k8s/base has no ExternalSecret
- `redis-orders-cache-apps-externalsecret.yaml` — no service-repo duplicate

Only `product-catalog` has an ExternalSecret in its service repo's k8s/base.

---

## Key Observation — Key Discrepancy

The data-layer version has 7 keys (including aliases); the service-repo version has 4:

| Key | data-layer version | service-repo version |
|---|---|---|
| `DATABASE_USER` | ✅ | ❌ |
| `DATABASE_PASSWORD` | ✅ | ❌ |
| `DB_USERNAME` | ✅ | ✅ |
| `DB_PASSWORD` | ✅ | ✅ |
| `RABBITMQ_USER` | ✅ | ❌ |
| `RABBITMQ_USERNAME` | ✅ | ✅ |
| `RABBITMQ_PASSWORD` | ✅ | ✅ |

The product-catalog Python service reads `DB_USERNAME`/`DB_PASSWORD` (confirmed in bug fix PR #28 — pydantic aliases). `DATABASE_USER`, `DATABASE_PASSWORD`, and `RABBITMQ_USER` are not used. The service-repo version already has all required keys.

---

## Fix

**File to delete:**  
`data-layer/secrets/postgres-products-apps-externalsecret.yaml`

Removing this file gives sole ownership of `product-catalog-secrets` to the `shopping-cart-product-catalog` Application (services-git). The service will continue to work because its own k8s/base deploys the ExternalSecret with all required keys.

Do NOT modify any other `*-apps-externalsecret.yaml` files — they have no service-repo duplicates.

---

## Steps for Codex

1. **Branch** — create `fix/product-catalog-externalsecret-shared-resource` from `main` (`8c6b0df`)

2. **Delete file:**
   ```
   data-layer/secrets/postgres-products-apps-externalsecret.yaml
   ```

3. **Commit:**
   ```
   fix(data-layer): remove duplicate product-catalog-secrets ExternalSecret
   
   The shopping-cart-product-catalog service repo's k8s/base already owns this
   ExternalSecret. Having it in data-layer/secrets/ causes an ArgoCD
   SharedResourceWarning. Sole ownership goes to the shopping-cart-product-catalog
   Application (services-git ApplicationSet).
   ```

4. **Push** the branch to origin before reporting done — verify SHA on `origin/fix/product-catalog-externalsecret-shared-resource`.

5. **Report** — SHA of the commit + confirmation that the deleted file is the only change.

---

## Definition of Done

- [ ] `data-layer/secrets/postgres-products-apps-externalsecret.yaml` deleted
- [ ] No other files modified
- [ ] Commit message matches above format
- [ ] Branch pushed to origin; SHA confirmed on remote
- [ ] No new YAML syntax errors introduced
