# Changelog

## [Unreleased]

## [0.2.0] - 2026-04-05

### Added
- `argocd/applications/data-layer.yaml` — ArgoCD Application for data-layer (PostgreSQL, RabbitMQ, Redis); previously required manual `kubectl apply`

### Fixed
- `data-layer/secrets/*.yaml`: switch `storeRef.kind` from `SecretStore` to `ClusterSecretStore` — only a ClusterSecretStore exists on the remote k3s cluster; namespace-scoped SecretStore was never provisioned, causing all ExternalSecrets to fail with SecretSyncedError
- `data-layer/secrets/postgres-*.yaml`: replace Vault dynamic DB engine paths (`database/creds/<role>`) with static KV paths (`secret/data/postgres/<db>`) — Vault DB engine is not configured on ACG sandbox; static KV credentials seeded by `bin/acg-up`
- `data-layer/secrets/postgres-*.yaml`: update `refreshInterval` from `1h` to `24h` and align comments to reflect static KV (not rotating) credentials
- `data-layer/secrets/*.yaml`: update `apiVersion` from `external-secrets.io/v1beta1` to `external-secrets.io/v1` — ESO 1.0.0 dropped v1beta1 serving; GA API required
- RabbitMQ `configmap.yaml`: add `loopback_users.guest = false` — guest user was restricted to localhost by default, causing "Connection refused" from cross-namespace pods
- RabbitMQ `statefulset.yaml`: reduce resource requests 500m/1Gi → 200m/512Mi to fit t3.medium with co-located services; keep limits at 1000m/1Gi
- Scale RabbitMQ from 3 replicas to 1 to reduce memory pressure on t3.medium (3×1Gi requests exhausted available RAM)

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
