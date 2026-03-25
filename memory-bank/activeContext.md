# Active Context: shopping-cart-infra

## Current Status (2026-03-25)

**PR #22 MERGED** — `7904c8a` 2026-03-25 — RabbitMQ connection fix: `loopback_users.guest = false`, data-layer ArgoCD app with `directory.recurse: true`, resource requests reduced. Copilot 3 findings fixed. `enforce_admins` restored.
**Active branch:** `docs/next-improvements`
**Issue shopping-cart-order#16:** CLOSED — fixed in this PR.

## Current Status (2026-03-14)

Infrastructure stages 1–3 complete. CI stabilization complete across all 5 app repos. P4 linters merged to main on all 4 linted repos.

## What's Implemented

### Data Layer
- RabbitMQ StatefulSet + Vault dynamic credentials (ESO)
- PostgreSQL StatefulSets: products + orders
- Redis StatefulSets: cart + orders-cache
- Vault database secrets engine (products + orders roles)
- ExternalSecrets for all components

### Application Layer
- Helm chart for all 4 application services
- Argo CD AppProject + Applications (dev + prod)
- CI/CD pipeline: GitHub Actions → Jenkins → infra repo → Argo CD

### Identity
- Keycloak + OpenLDAP deployed in `identity` namespace
- Realm `shopping-cart` configured with `frontend` client

### CI Stabilization (2026-03-14) — ALL MERGED
| Repo | Status |
|---|---|
| `rabbitmq-client-java` | ✅ MERGED |
| `shopping-cart-order` | ✅ MERGED |
| `shopping-cart-product-catalog` | ✅ MERGED |
| `shopping-cart-payment` | ✅ MERGED |
| `shopping-cart-frontend` | ✅ MERGED |

### P4 Linters (2026-03-14) — ALL MERGED
| Repo | Linter | Status |
|---|---|---|
| `shopping-cart-basket` | golangci-lint | ✅ MERGED |
| `shopping-cart-product-catalog` | ruff + mypy | ✅ MERGED |
| `shopping-cart-order` | Checkstyle + OWASP | ✅ MERGED |
| `shopping-cart-payment` | Checkstyle + SpotBugs | ✅ MERGED |

## Active Task

- **v0.1.0 release branches** — cut on all 6 repos, add CHANGELOGs, tag after merge.

## Known Issues / Docs

- `docs/issues/001-rabbitmq-nodeport.md` — RabbitMQ NodePort access
- `docs/issues/002-rabbitmq-prometheus-plugin.md` — Prometheus plugin config
- `docs/issues/003-ci-stabilization-followups.md` — CI follow-ups
- `docs/issues/2026-03-14-owasp-nvd-api-key.md` — NVD API key needed for order repo

## Pending Work

- [ ] v0.1.0 release branches on all 6 repos
- [ ] Stage 4: Wire observability (ServiceMonitors, dashboards)
- [ ] Namespace redesign (function-centric)
- [ ] Two-cluster split (infra on OrbStack, app on k3s/Parallels)
- [ ] Auth re-architecture (centralise through Keycloak OIDC)
- [ ] ESO cross-cluster (app cluster pulling from Vault on infra cluster)
