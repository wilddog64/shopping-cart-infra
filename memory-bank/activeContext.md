# Active Context: shopping-cart-infra

## Current Status (2026-05-11)
**v0.4.0 Milestone: Observability & Cross-Cluster Validation**
Following the successful shipping of the Identity Stack (v0.3.0), focus shifts to observability wiring and hardening cross-cluster secret management.

## Recent Changes
- **v0.3.0 SHIPPED:** Identity stack integrated (Keycloak/LDAP/SSO/Vault-ESO).
- **Branch Created:** shopping-cart-infra-v0.4.0 for the next milestone.

## Next Steps
- **Observability Stage 1:** Deploy ServiceMonitors for Keycloak, LDAP, and databases.
- **Grafana Dashboards:** Port/customize dashboards for core infra components.
- **Cross-cluster ESO:** Validate application cluster pods retrieving secrets from the Hub cluster's Vault instance.
