# Active Context: shopping-cart-infra

## Current Status (2026-05-13)
**v0.4.0 Milestone: Observability & Cross-Cluster Validation**
Following the successful shipping of the Identity Stack (v0.3.0), focus shifts to observability wiring and hardening cross-cluster secret management.

## Recent Changes
- **v0.3.0 SHIPPED:** Identity stack integrated (Keycloak/LDAP/SSO/Vault-ESO).
- **Identity Regression Fix:** Resolved Keycloak CrashLoopBackOff by removing conflicting \`KC_HOSTNAME\` vs \`KC_HOSTNAME_URL\` (PR #46). Fixed DB auth failure by aligning Postgres internal password with Vault-synced secret.
- **Branch Created:** shopping-cart-infra-v0.4.0 for the next milestone.
- **LDAP Bind Recovery:** Investigating a live Keycloak LDAP `Invalid Credentials` failure after the `ldap-admin` bind DN experiment. The conservative repo-side fix restores the canonical OpenLDAP root DN `admin` in both Keycloak and LDAP manifests so the deployment and realm import agree on the bind identity.

## Next Steps
- **Observability Stage 1:** Deploy ServiceMonitors for Keycloak, LDAP, and databases.
- **Grafana Dashboards:** Port/customize dashboards for core infra components.
- **Cross-cluster ESO:** Validate application cluster pods retrieving secrets from the Hub cluster's Vault instance.
