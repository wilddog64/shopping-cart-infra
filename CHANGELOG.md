# Changelog

## [Unreleased]

### Fixed
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
