# Changelog

## [Unreleased]

### Added
- `argocd/applications/data-layer.yaml` — ArgoCD Application for data-layer (PostgreSQL, RabbitMQ, Redis); previously required manual `kubectl apply`

### Fixed
- `data-layer/secrets/*.yaml`: update `apiVersion` from `external-secrets.io/v1beta1` to `external-secrets.io/v1` — ESO 0.9.20 on k3s serves `v1`; `v1beta1` was not available, causing ArgoCD sync failures for `data-layer` and `product-catalog`
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
