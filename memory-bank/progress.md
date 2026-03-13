# Progress: shopping-cart-infra

## CI Stabilization (v0.9.0 — active)

### PR Status

| Repo | PR | CI | Notes |
|---|---|---|---|
| shopping-cart-product-catalog | #1 | ✅ green | Ready to merge |
| rabbitmq-client-java | #1 | ✅ publish green | Package published to GitHub Packages |
| shopping-cart-frontend | #1 | ❌ lint | react-refresh warnings — Round 3 pending |
| shopping-cart-payment | #1 | ❌ build | rabbitmq SNAPSHOT + packages:read — Round 3 pending |
| shopping-cart-order | #1 | ❌ build | packages:read permission missing — Round 3 pending |

### Round 3 Fixes Pending (spec: docs/plans/ci-stabilization-round3.md @ c5797539)

- [ ] payment: `rabbitmq-client.version` 1.0.0 → 1.0.0-SNAPSHOT; add GitHub Packages repo + maven-settings.xml; add `packages: read` to build job
- [ ] order: add `packages: read` to build job in ci.yml
- [ ] frontend: fix `react-refresh/only-export-components` in Badge.tsx, Button.tsx, test-utils.tsx

### After CI Green

- [ ] Merge all 5 PRs to main
- [ ] P4 linters — basket: golangci-lint + go vet; order: Checkstyle + OWASP; product-catalog: ruff + mypy + black; payment: Checkstyle + SpotBugs
- [ ] Branch protection — all 5 repos via `gh api` (require PR, required checks, no force push, dismiss stale reviews)
- [ ] Cut v0.1.0 release branches on all 6 repos (including shopping-cart-infra)

---

## Infrastructure Stages

| Stage | Description | Status |
|---|---|---|
| 1 | RabbitMQ StatefulSet deployment | ✅ Complete |
| 2 | Vault integration for RabbitMQ dynamic credentials | ✅ Complete |
| 3 | Java client library (rabbitmq-client-java) | ✅ Complete |
| 4 | CI Stabilization | ⏳ In Progress |
| 5 | Linters + Branch Protection | Pending |
| 6 | Monitoring & production readiness | Pending |

## Built

### Data Layer
- [x] Namespace definitions (`shopping-cart-data`, `shopping-cart-apps`)
- [x] PostgreSQL StatefulSets: products + orders
- [x] Redis StatefulSets: cart + orders-cache
- [x] RabbitMQ StatefulSet with management UI + Prometheus plugin
- [x] ExternalSecrets for all components (Vault → K8s Secrets)

### Application Services
- [x] Helm chart structure (`chart/`)
- [x] All 4 service templates (product-catalog, basket, order, frontend)
- [x] Argo CD AppProject + Applications

### CI/CD
- [x] Reusable GitHub Actions workflow (build + Trivy + ghcr.io push + kustomize update)
- [x] All 5 service repos have `fix/ci-stabilization` PRs open

## Known Issues

| ID | Description | Status |
|---|---|---|
| CI-01 | Frontend ESLint react-refresh warnings | Round 3 pending |
| CI-02 | Payment rabbitmq version mismatch + packages:read | Round 3 pending |
| CI-03 | Order packages:read permission missing | Round 3 pending |
