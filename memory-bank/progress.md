# Progress: shopping-cart-infra

## Status
- **v0.4.0 IN PROGRESS** (2026-05-13) — Observability & Cross-Cluster validation.
- **v0.3.0 SHIPPED** (2026-05-10) — Identity SSO & Vault-ESO migration.
- **v0.2.0 SHIPPED** — Data Layer & Kitchen-Ansible testing.

## Milestone: v0.4.0 (Observability)
- [ ] Prometheus ServiceMonitors for Keycloak
- [ ] Prometheus ServiceMonitors for OpenLDAP
- [ ] Prometheus ServiceMonitors for Data Layer (Postgres, Redis, RabbitMQ)
- [ ] Grafana Dashboard: Identity Overview
- [ ] Grafana Dashboard: Database Health
- [ ] Cross-cluster ESO validation (App cluster)
- [ ] Keycloak LDAP bind DN recovery after `ldap-admin` experiment — realm import now re-applies the repo source of truth at Keycloak startup so existing realms pick up the canonical realm import in `identity/keycloak/realm-shopping-cart.json`.
- [x] Keycloak realm import no longer depends on templated LDAP bind DN — the canonical DN is now literal in the realm template and the initContainer only renders the bind credential from Secret data. `KC_DB_USERNAME` is generated with `keycloak-config`, and the import runs with `--db=postgres --override=true`. Issue docs: `docs/issues/2026-05-13-keycloak-realm-import-invalid-dn-literal-binddn.md` and `docs/issues/2026-05-13-kustomize-cross-directory-realm-file-disallowed.md`.
- [ ] Keycloak realm import should skip an existing `shopping-cart` realm — live startup still logs `Key (name)=(shopping-cart) already exists`, so the initContainer needs a DB-side existence check before calling `kc.sh import`. Issue doc: `docs/issues/2026-05-13-keycloak-realm-import-should-skip-existing-shopping-cart-realm.md`.
- [ ] Live JSON reconcile without rebuild — spec documented in `docs/issues/2026-05-14-keycloak-live-json-reconcile-without-rebuild.md`; next implementation should move realm updates to an idempotent live reconcile path instead of cluster rebuilds.

## Milestone: v0.3.0 (Identity & Hardening) — ARCHIVED
- [x] Keycloak + LDAP deployment manifests
- [x] Vault ESO integration for Identity
- [x] OIDC Issuer protocol mismatch resolution
- [x] LDAP bootstrap writable emptyDir fix
- [x] ArgoCD identity Application definition
