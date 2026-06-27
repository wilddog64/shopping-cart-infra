# Changelog

## [Unreleased]

### Removed
- `data-layer/secrets/cluster-secret-store.yaml`: delete the stale ubuntu-k3s `vault-backend` ClusterSecretStore (token auth, `vault-bridge.secrets.svc.cluster.local:8201`). The app-cluster `vault-backend` CSS is now owned by k3d-manager's `eso-clustersecretstore` ApplicationSet (k8s-auth, external Vault). ExternalSecrets keep `secretStoreRef.name: vault-backend` unchanged. (ESO Phase 2)

### Fixed
- ESO ExternalSecrets: lower `refreshInterval` from `24h` to `15m` across all 19 manifests so a transient hub-Vault bridge flap self-heals within ~15m instead of staying broken up to 24h (ESO retry cadence == refreshInterval); inline cadence comments updated to match
- `data-layer/minio/image-upload-job.yaml`: replace `python:3.12-alpine` with `python:3.12-slim` — alpine uses musl-libc and cannot install Pillow manylinux wheels without a compiler, causing the image-upload job to fail silently (backoffLimit exhausted, no images uploaded)
- `identity/ldap/bootstrap.yaml`: replace SSHA hashes in `06-sample-users.ldif` with known-password hashes for dev test users; credentials documented in spec (not in repo)

### Added
- `.githooks/pre-push`: pre-push hook to block accidental direct pushes from feature branches to main; bypass with `ALLOW_MAIN_PUSH=1`
- MinIO StatefulSet with 10Gi PVC in `shopping-cart-data` namespace as S3-compatible in-cluster object store
- PostSync bucket-init Job (creates `product-images` bucket with anonymous read) and image-upload Job (generates 20 category images)
- ESO ExternalSecret for MinIO credentials from Vault `secret/data/minio/credentials`
- MinIO console accessible via NodePort 30900/30901; S3 API on ClusterIP
- Architecture documentation: `docs/minio-image-pipeline.md`

### Fixed
- Add `https://frontend.3ai-talk.org/*` to Keycloak `frontend` client `redirectUris`, add `frontend.3ai-talk.org` to Istio `default-gateway` hosts, and add `frontend.3ai-talk.org` to `frontend` VirtualService hosts — fixes `invalid_redirect_uri` SSO login failure on the public domain
- Pin `storageClassName: local-path` in all StatefulSet volumeClaimTemplates (postgresql/orders, postgresql/products, postgresql/payment, redis/cart, redis/orders-cache, minio) to prevent ArgoCD data-layer OutOfSync on every cluster rebuild
- `argocd/applications/data-layer.yaml`: add `ignoreDifferences` for StatefulSet `volumeClaimTemplates.storageClassName` and `volumeClaimTemplates.volumeMode` — prevents ArgoCD from patching immutable fields on existing StatefulSets, unblocking the data-layer Application sync loop
- `argocd/applications/data-layer.yaml`: add `RespectIgnoreDifferences=true` to syncOptions — prevents ArgoCD from including ignored immutable fields (`volumeClaimTemplates.storageClassName`, `volumeClaimTemplates.volumeMode`) in sync payloads, making the StatefulSet immutable-field protection permanent
- Normalize Istio VirtualService API version from `networking.istio.io/v1beta1` to `v1` in frontend and ArgoCD VirtualServices to prevent shopping-cart-networking OutOfSync
- `argocd/applications/`: remove legacy static Application definitions for basket-service, frontend, order-service, payment-service, product-catalog — superseded by services-git ApplicationSet; eliminated SharedResourceWarning and OutOfSync conflicts
- Add `group-ldap-mapper` to Keycloak LDAP federation reconcile job so LDAP group memberships sync to Keycloak and ArgoCD RBAC works correctly for SSO users
- `identity/keycloak/keycloak-reconcile-hook-job.yaml` — use `authentication/flows/{alias}/executions` PUT endpoint (not `authentication/executions/{id}`) for sub-flow requirement updates; Keycloak 24.0 returns HTTP 404 for the leaf-execution endpoint when the target is a sub-flow (`authenticationFlow: true`), causing the job to abort mid-way under `set -euo pipefail` and leaving `otp-conditional-subflow` DISABLED and empty — MFA never activates
- `identity/keycloak/keycloak-reconcile-hook-job.yaml` — capture `partialImport` exit code and log it explicitly; script continues to LDAP mapper setup and `triggerFullSync` regardless, fixing `user_not_found` on every re-deploy after the first ArgoCD sync
- `identity/keycloak/realm-shopping-cart.json` — restore `pkce.code.challenge.method: S256` on `frontend` client; an earlier commit had unintentionally removed it (PKCE is correct for SPA public clients)
- Add `LDAP_BIND_CREDENTIAL` env var to Keycloak realm reconcile hook job sourced from `ldap-secrets.LDAP_ADMIN_PASSWORD` — fixes LDAP federation bind failure on every PostSync run
- Correct `minio/mc` image tag to `RELEASE.2024-11-05T11-29-45Z` — the `2024-11-07` tag does not exist on quay.io, causing `minio-bucket-init` and `minio-image-upload` jobs to fail with ErrImagePull
- Set `MC_CONFIG_DIR=/tmp/.mc` in `minio-bucket-init` and `minio-image-upload` jobs — `minio/mc` image runs as non-root (UID 1000) and cannot write to `/root/.mc`, causing the bucket-init loop to never exit
- Remove placeholder `redis-cart-secret` and `redis-orders-cache-secret` Secret manifests from `data-layer/redis/cart/` and `data-layer/redis/orders-cache/` — ESO ExternalSecrets in `data-layer/secrets/` own these secrets and overwrite the placeholder data with real Vault values, causing perpetual ArgoCD `data-layer` OutOfSync. Deleting the placeholders lets ESO fully own the secrets without conflict.

## [0.5.0] - 2026-05-18

### Added
- `networking/istio/frontend-virtualservice.yaml` — new VirtualService routing `frontend.shopping-cart.local` to `frontend.shopping-cart-apps.svc.cluster.local:80`
- `networking/istio/gateway.yaml` — add `frontend.shopping-cart.local` to Istio gateway hosts
- `.github/workflows/build-push-deploy.yml` — add optional `build-args` input, wired to both "Build image" and "Push image" steps

### Fixed
- `data-layer/postgresql/products/init-db.sql`: removed SERIAL products table DDL that conflicted with SQLAlchemy UUID PK; SQLAlchemy's `create_all()` now owns the products table schema with UUID primary key, eliminating the need for manual table recreation on fresh clusters
- `argocd/config/argocd-cm.yaml`: change `url` field from `http://argocd.shopping-cart.local` to `https://argocd.shopping-cart.local` so OIDC callback after Keycloak auth lands on ArgoCD (port 443 socat HTTPS wrapper) instead of Keycloak (port 80 port-forward)
- `identity/keycloak/realm-shopping-cart.json` — add `http://frontend.shopping-cart.local/*` to frontend client `redirectUris` so HTTP (non-TLS) redirects work in local dev
- Apply `argocd/projects/shopping-cart.yaml` to cluster — the `shopping-cart` AppProject was defined in the repo but never applied, causing `shopping-cart-networking` to stay `Unknown`; `networking.yaml` already correctly references `project: shopping-cart`
- Add `networking/istio/keycloak-destinationrule.yaml` — disable mTLS for `keycloak.identity.svc.cluster.local` so ArgoCD (Istio-injected, `cicd` ns) can reach Keycloak (no sidecar, `identity` ns) for OIDC token exchange

### Added
- `argocd/applications/data-layer.yaml` — ArgoCD Application for data-layer (PostgreSQL, RabbitMQ, Redis); previously required manual `kubectl apply`
- `data-layer/secrets/redis-cart-apps-externalsecret.yaml` — sync redis-cart password into `shopping-cart-apps/redis-cart-secret` for basket-service
- `data-layer/secrets/redis-orders-cache-apps-externalsecret.yaml` — sync redis-orders-cache password into `shopping-cart-apps/redis-orders-cache-secret`
- `data-layer/secrets/postgres-orders-apps-externalsecret.yaml` — sync postgres/orders creds into `shopping-cart-apps/order-service-secrets` (all env keys)
- `data-layer/secrets/postgres-products-apps-externalsecret.yaml` — sync postgres/products creds into `shopping-cart-apps/product-catalog-secrets` (all env keys)

### Fixed
- `argocd/config/argocd-rbac-cm.yaml`: updated `catalog-admin` role to reference `shopping-cart/shopping-cart-product-catalog` app name (was `shopping-cart/product-catalog`) — the app name mismatch caused `permission denied` for `catalog-admins` LDAP group members attempting to sync the product catalog
- Update OIDC issuer URLs from internal cluster domain to external Keycloak domain (`keycloak.3ai-talk.org`) in ArgoCD config and Keycloak kustomization
- Disabled service link injection (`enableServiceLinks: false`) in LDAP Deployment to prevent Kubernetes-injected `LDAP_PORT` env var from corrupting the slapd listen URL (parse error=5)
- Remove duplicate `ldap-secrets-externalsecret.yaml` entry from `identity/ldap/kustomization.yaml` — fixes ArgoCD identity Application sync failure and unblocks Keycloak deployment
- `data-layer/postgresql/orders/configmap.yaml`: add 11 missing columns to `orders` table (lifecycle timestamps: `paid_at`, `shipped_at`, `completed_at`, `cancelled_at`; shipping address: `shipping_street/city/state/postal_code/country`; tracking: `tracking_number`, `carrier`) — resolves `order-service` CrashLoopBackOff caused by JPA schema-validation failure on expanded `Order` entity; applies to freshly initialised PostgreSQL data directories only — existing PVCs need recreation or an `ALTER TABLE` migration
- `data-layer/postgresql/orders/configmap.yaml`: align the orders init SQL with the UUID primary-key schema and add `cancellation_reason VARCHAR(255)` to the `orders` table — resolves the `order-service` schema-validation failure caused by the missing column
- `data-layer/secrets/postgres-orders-apps-externalsecret.yaml`: add `SPRING_RABBITMQ_USERNAME`/`SPRING_RABBITMQ_PASSWORD` to ESO template — supplies Vault-managed RabbitMQ credentials to Spring AMQP auto-config; host/port/vhost are set via the companion `shopping-cart-order` ConfigMap change (`SPRING_RABBITMQ_HOST/PORT/VIRTUAL_HOST`)
- `argocd/config/argocd-cm.yaml`: add ExternalSecret custom Lua health check so ArgoCD waits for `SecretSynced` before advancing past wave 0 — prevents StatefulSets from starting before secrets exist
- `data-layer/secrets/*.yaml` (12 files): add `argocd.argoproj.io/sync-wave: "0"` — ExternalSecrets deploy in wave 0 and must reach Healthy before wave 1 begins
- `data-layer/redis/*/statefulset.yaml`, `data-layer/rabbitmq/statefulset.yaml`, `data-layer/postgresql/*/statefulset.yaml` (6 files): add `argocd.argoproj.io/sync-wave: "1"` — StatefulSets deploy after ExternalSecrets are synced, eliminating the `CHANGE_ME` / `CreateContainerConfigError` race condition on fresh provision
- `argocd/applications/order-service.yaml`, `argocd/applications/product-catalog.yaml`: add `SPRING_JPA_HIBERNATE_DDL_AUTO=create` kustomize ConfigMap patch — Hibernate recreates the schema on each sandbox provision instead of failing `validate` on empty or stale tables
- `data-layer/secrets/*.yaml`: update `apiVersion` from `external-secrets.io/v1beta1` to `external-secrets.io/v1` — ESO 0.9.20 on k3s serves `v1`; `v1beta1` was not available, causing ArgoCD sync failures for `data-layer` and `product-catalog`
- RabbitMQ `configmap.yaml`: add `loopback_users.guest = false` — guest user was restricted to localhost by default, causing "Connection refused" from cross-namespace pods
- RabbitMQ `statefulset.yaml`: reduce resource requests 500m/1Gi → 200m/512Mi to fit t3.medium with co-located services; keep limits at 1000m/1Gi
- Scale RabbitMQ from 3 replicas to 1 to reduce memory pressure on t3.medium (3×1Gi requests exhausted available RAM)
- `data-layer/rabbitmq/service.yaml`: change `rabbitmq-management` from `LoadBalancer` to `ClusterIP` — LoadBalancer stays `Progressing` on k3s (no cloud LB), blocking ArgoCD wave 1 (StatefulSets) from deploying; ClusterIP resolves immediately as Healthy (`dfc949d` — PR #27)
- `argocd/applications/payment-service.yaml`: add `ignoreDifferences` for `payment-db-credentials` Secret `/data` — stops ArgoCD `selfHeal` from overwriting the ESO-managed Vault password back to the `CHANGE_ME` placeholder in `k8s/base/secret.yaml`, resolving `payment-service` CrashLoopBackOff caused by Flyway `FATAL: password authentication failed`
- `data-layer/secrets/*.yaml`: use single-line connection strings — remove backslash-newline continuations in double-quoted YAML scalars to avoid whitespace/backslash ambiguity across tooling (`ad0817d` — PR #26)

## [0.1.0] - 2026-03-14

### Added
- Data layer: RabbitMQ, PostgreSQL (products + orders), Redis (cart + orders-cache) as StatefulSets
- Vault integration: dynamic credentials for all data services via External Secrets Operator
- Identity stack: Keycloak + OpenLDAP in `identity` namespace
- Keycloak realm `shopping-cart` with `frontend` OIDC client
- Argo CD GitOps: AppProject + Applications (dev + prod environments)
- Helm charts for all 4 application services
- CI/CD pipeline: GitHub Actions → Jenkins → infra repo → Argo CD
- Reusable GitHub Actions workflow (`build-push-deploy.yml`) for all app repos
- CI stabilization across all 5 application repos (2026-03-14)
- P4 linter gates on all 4 backend/frontend repos (2026-03-14)
