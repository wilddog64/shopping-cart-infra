# Progress: shopping-cart-infra

## Status
- **v0.3.0 SHIPPED** (2026-05-10) — Identity SSO & Vault-ESO migration.
- **v0.2.0 SHIPPED** — Data Layer & Kitchen-Ansible testing.

## Milestone: v0.3.0 (Identity & Hardening)
- [x] Keycloak + LDAP deployment manifests
- [x] Vault ESO integration for Identity
- [x] OIDC Issuer protocol mismatch resolution
- [x] LDAP bootstrap writable emptyDir fix
- [x] ArgoCD identity Application definition

## Next: v0.4.0 (Observability)
- [ ] Prometheus ServiceMonitors for all components
- [ ] Grafana dashboards (Postgres, Redis, Keycloak)
- [ ] Unified logging strategy
