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
- App image tags are in each app repo's `k8s/<app>/base/kustomization.yaml` — updated by CI in the app repo, not here
- `identity/ldap/` and `identity/keycloak/` use Kustomize overlays managed in this repo

### GitOps Principle
- ArgoCD watches this repo for changes to `argocd/`, `data-layer/`, `identity/`, and `namespaces/` manifests
- Never apply manifests directly to the cluster — always go through ArgoCD
- Exception: `data-layer/secrets/` (vault-bridge, ClusterSecretStore) are applied by k3d-manager `bin/acg-up`, not ArgoCD

### Manifest CI (validate.yml)
- Every PR runs yamllint + kubeconform + kustomize-build
- kubeconform uses `--ignore-missing-schemas` for CRDs (ESO, ArgoCD Application)
- yamllint has `indentation: disable` — pre-existing debt; kubeconform handles structural correctness

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
