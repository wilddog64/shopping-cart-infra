# Active Context: shopping-cart-infra

## Current Status (2026-05-10)
**v0.3.0 Milestone: Identity Stack & GitOps Hardening**
The identity stack (Keycloak + OpenLDAP) is fully integrated with Vault-backed secrets and ArgoCD. SSO protocol mismatches and PVC deadlocks have been resolved.

## Recent Changes
- **v0.3.0 SHIPPED:** Comprehensive identity integration.
- **SSO Fix:** Aligned OIDC protocols by enforcing `KC_HOSTNAME_STRICT: true` and `KC_HOSTNAME_URL`.
- **Secret Migration:** All identity secrets moved to ExternalSecrets + Vault.
- **LDAP Stability:** Fixed LDIF bootstrap writability via initContainer.

## Next Steps
- Stage 4: Observability wiring (ServiceMonitors, Grafana dashboards).
- Cross-cluster ESO validation (App cluster pulling from Hub Vault).
