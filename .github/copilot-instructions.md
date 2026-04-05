# Copilot Instructions — Shopping Cart Infra

## Repository Overview

Shared infrastructure for the Shopping Cart platform:
- **`/.github/workflows/build-push-deploy.yml`** — reusable CI workflow called by all 5 app repos
- **`/.github/workflows/validate.yml`** — CI: yamllint + kubeconform + kustomize build on every PR
- **`/argocd/`** — ArgoCD Applications, AppProject, config
- **`/data-layer/`** — PostgreSQL, Redis, RabbitMQ StatefulSets + ESO ExternalSecrets
- **`/identity/`** — Keycloak + OpenLDAP (Kustomize overlays)
- **`/namespaces/`** — Namespace definitions
- **`/docs/`** — architecture, CI/CD, RabbitMQ, Vault, and issue documentation

---

## Architecture Guardrails

### Reusable Workflow — Handle With Care
- `build-push-deploy.yml` is called by all 5 app repos — a breaking change here breaks all of them
- Always pin action versions to a tag (`@v4`, `@v5`) — never `@main` or `@latest`
- The workflow accepts `PACKAGES_TOKEN` as an optional secret — never make it required without updating all 5 callers
- `continue-on-error: true` on Trivy scan and kustomization update steps is intentional — do not remove
- `GH_TOKEN=${{ secrets.PACKAGES_TOKEN }}` forwarded as Docker build secret — required for GitHub Packages auth

### Kustomization Updates
- `k8s/<app>/base/kustomization.yaml` `newTag` is updated by CI — the update step uses `git pull --rebase` before push
- If the update step fails (branch protection), it is non-blocking (`continue-on-error: true`) — the image is still pushed to ghcr.io
- Manual update may be needed when the CI step is blocked by branch protection

### GitOps Principle
- ArgoCD watches this repo for changes to `k8s/` manifests
- Never apply manifests directly to the cluster — always go through ArgoCD
- Never change image tags in `kustomization.yaml` to a floating tag (e.g., `latest`) in production paths

### ESO ExternalSecret Rules
- `storeRef.kind` must be `ClusterSecretStore` — no namespace-scoped SecretStore is deployed on the remote k3s cluster; using `kind: SecretStore` will cause `SecretSyncedError` on every ExternalSecret
- `remoteRef.key` paths must match what `bin/acg-up` seeds in Vault KV: `secret/data/redis/cart`, `secret/data/redis/orders-cache`, `secret/data/postgres/orders`, `secret/data/postgres/products`, `secret/data/postgres/payment`, `secret/data/payment/encryption`, `secret/data/payment/stripe`, `secret/data/payment/paypal`
- `refreshInterval` must be `24h` for static KV credentials — `1h` is for rotating dynamic creds only; the ACG sandbox does not run the Vault DB engine
- Do not use `database/creds/<role>` paths in `remoteRef.key` — the Vault DB engine is not configured on ACG sandbox; those paths do not exist

---

## Security Rules (treat violations as bugs)

### Supply Chain (OWASP A08)
- All GitHub Actions steps must pin to a version tag — never `@main` or `@latest`
- Docker image references in `k8s/` manifests must use pinned SHA or version tags, not `latest`
- Never add a new action without pinning its SHA or version tag

### Secrets (OWASP A02)
- Never hardcode tokens, passwords, or registry credentials in workflow files
- `PACKAGES_TOKEN` must always be passed as a secret input, never as a plain env var
- Vault secrets are managed by ESO — never add raw secrets to `k8s/` manifests

### Least Privilege (OWASP A01)
- Workflow `permissions` must be scoped to minimum required (`contents: write`, `packages: write` only where needed)
- New ServiceAccounts must not use `cluster-admin` — use namespace-scoped Role + RoleBinding

---

## Workflow Change Protocol

When modifying `build-push-deploy.yml`:
1. Test the change in isolation before merging
2. After merge, update the SHA reference in all 5 calling workflows:
   - `shopping-cart-order/.github/workflows/ci.yml`
   - `shopping-cart-payment/.github/workflows/ci.yaml`
   - `shopping-cart-product-catalog/.github/workflows/ci.yml`
   - `shopping-cart-frontend/.github/workflows/ci.yml`
   - `shopping-cart-basket/.github/workflows/go-ci.yml`
3. Each caller pins to a full 40-char SHA — never a branch name

---

## Completion Report Requirements

Before marking any task complete, the agent must provide:
- Confirmation no action version was unpinned
- Confirmation `continue-on-error` gates were not removed
- List of exact files modified
- If `build-push-deploy.yml` was changed: SHA and list of callers updated

---

## What NOT To Do

- Do not remove `continue-on-error: true` from Trivy scan or kustomization update steps
- Do not make `PACKAGES_TOKEN` a required secret — it must remain optional
- Do not add `latest` image tags to production `kustomization.yaml` files
- Do not apply k8s manifests directly — ArgoCD is the only deployment mechanism
- Do not add new workflows that duplicate the reusable workflow's function
