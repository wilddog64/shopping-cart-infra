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
- [ ] Keycloak LDAP bind DN recovery after `ldap-admin` experiment

## Milestone: v0.3.0 (Identity & Hardening) — ARCHIVED
- [x] Keycloak + LDAP deployment manifests
- [x] Vault ESO integration for Identity
- [x] OIDC Issuer protocol mismatch resolution
- [x] LDAP bootstrap writable emptyDir fix
- [x] ArgoCD identity Application definition
