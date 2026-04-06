# Active Context: shopping-cart-infra

## Current Status (2026-04-06)

**v0.3.1 spec written:** `docs/plans/v0.3.1-fix-order-service-spring-rabbitmq-config.md` — fix order-service CrashLoopBackOff caused by Spring AMQP `CachingConnectionFactory` defaulting to `localhost:5672`. Two files: `shopping-cart-order/k8s/base/configmap.yaml` (add `SPRING_RABBITMQ_HOST/PORT/VIRTUAL_HOST`) + `shopping-cart-infra/data-layer/secrets/postgres-orders-apps-externalsecret.yaml` (add `SPRING_RABBITMQ_USERNAME/PASSWORD` to ESO template — Vault-managed, no hardcoded values). Issue: `docs/issues/2026-04-06-order-service-rabbitmq-health-503.md`. Branch: `fix/order-service-spring-amqp-config`. Ready to hand off to Codex.

**v0.3.0 COMPLETE:** `a37d8e1` — CI manifest cross-check + post-sync smoke test shipped. Codex verified: shellcheck clean, only 3 spec files touched, commit message exact.



**Round 2 CrashLoopBackOff fixes — ALL MERGED:**
- wilddog64/shopping-cart-payment#18 (`fix/networkpolicy-dns`) — MERGED `0fb7aa0` — DNS block fixed (namespaceSelector for kube-system), RabbitMQ env vars wired
- wilddog64/shopping-cart-product-catalog#17 (`fix/configmap-db-keys`) — MERGED `3a119fe` — DB_NAME fixed to `products`, ConfigMap keys aligned with pydantic aliases
- wilddog64/shopping-cart-frontend#14 (`fix/nginx-run-dir`) — MERGED `74d994f` — nginx-run emptyDir for /run PID file

**enforce_admins restored** on all three repos after merge.

**Next branches:** `docs/next-improvements` exists on payment, product-catalog, frontend.

**Password rotation spec** written: `k3d-manager/docs/plans/v1.0.4-bugfix-acg-up-random-passwords.md` — not yet handed to Codex.

**Previous round (2026-04-05):**
- wilddog64/shopping-cart-infra#28 (`fix/app-credentials`) — MERGED `e95b31a` — ExternalSecret key fixes for product-catalog + payment
- wilddog64/shopping-cart-payment#17 (`fix/network-policy-labels`) — superseded by #18
- wilddog64/shopping-cart-frontend#13 (`fix/frontend-manifest-port-probe`) — MERGED (nginx-cache emptyDir)

**admin override on shopping-cart-infra** — re-enable: `gh api repos/wilddog64/shopping-cart-infra/branches/main/protection/enforce_admins -X POST -f enabled=true`

## Current Status (2026-04-03)

**BLOCKED — do not investigate until k3d-manager cold-run gate passes.** Gate: `make down` → `make up` from zero completes with ClusterSecretStore Ready + 3 nodes Ready on a fresh sandbox.
**App pods Degraded/OutOfSync after k3d-manager v1.0.2 `make up`** — 3-node k3s cluster is up, ClusterSecretStore Ready, ESO running. ArgoCD sync shows: basket-service Degraded, frontend Degraded, order-service Degraded, payment-service Degraded, product-catalog OutOfSync/Degraded, data-layer OutOfSync/Missing. Root cause not yet diagnosed — needs investigation when next sandbox is live. Known prior issues: RabbitMQ (order-service), memory limits (payment-service), resource exhaustion (frontend).
**RabbitMQ Vault credentials fix** — COMPLETE (`d356490`). Branch `fix/app-namespace-secrets` adds `rabbitmq-externalsecret`, wires RabbitMQ StatefulSet to that secret, and updates app-namespace ExternalSecrets to pull RabbitMQ creds from Vault so pods no longer hardcode guest/guest. Spec: `docs/plans/v0.2.1-bugfix-rabbitmq-vault-creds.md`.

## Current Status (2026-03-25)

**PR #22 MERGED** — `7904c8a` 2026-03-25 — RabbitMQ connection fix: `loopback_users.guest = false`, data-layer ArgoCD app with `directory.recurse: true`, resource requests reduced. Copilot 3 findings fixed. `enforce_admins` restored.
**Active branch:** `docs/next-improvements`
**Issue shopping-cart-order#16:** CLOSED — fixed in PR #22.

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
