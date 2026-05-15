# Active Context: shopping-cart-infra

## Current Status (2026-05-13)
**v0.4.0 Milestone: Observability & Cross-Cluster Validation**
Following the successful shipping of the Identity Stack (v0.3.0), focus shifts to observability wiring and hardening cross-cluster secret management.

## Recent Changes
- **v0.3.0 SHIPPED:** Identity stack integrated (Keycloak/LDAP/SSO/Vault-ESO).
- **Identity Regression Fix:** Resolved Keycloak CrashLoopBackOff by removing conflicting \`KC_HOSTNAME\` vs \`KC_HOSTNAME_URL\` (PR #46). Fixed DB auth failure by aligning Postgres internal password with Vault-synced secret.
- **Branch Created:** shopping-cart-infra-v0.4.0 for the next milestone.
- **LDAP Bind Recovery:** Investigating a live Keycloak LDAP `Invalid Credentials` failure after the `ldap-admin` bind DN experiment. The conservative repo-side fix restores the canonical OpenLDAP root DN `admin` in both Keycloak and LDAP manifests and now re-imports the realm on Keycloak startup so existing realms pick up the bind identity from the ConfigMap/source JSON.
- **Copilot Review Follow-up:** Copilot flagged that the Keycloak ConfigMap values were not being applied to already-initialized realms. The current fix keeps `identity/keycloak/realm-shopping-cart.json` as the single startup import source of truth so the live realm refreshes from repo state without a second copy under `identity/config/`.
- **NEW FINDING:** The Keycloak realm import was still templating the LDAP bind DN, which let a bad render path surface as `javax.naming.InvalidNameException: invalid DN` during Argo CD SSO. The branch now hardcodes the canonical bind DN in the realm template and keeps only the bind credential templated from Secret data. The import path now uses `--db=postgres --override=true` and `KC_DB_USERNAME` is carried in the generated `keycloak-config` ConfigMap. Issue docs: `docs/issues/2026-05-13-keycloak-realm-import-invalid-dn-literal-binddn.md` and `docs/issues/2026-05-13-kustomize-cross-directory-realm-file-disallowed.md`.
- **COMPLETE:** Live JSON reconcile without rebuild is implemented. The Keycloak deployment no longer boot-imports the realm; the repo now uses an Argo CD `PostSync` hook Job (`identity/keycloak/keycloak-reconcile-hook-job.yaml`) to render the realm JSON and call Keycloak partial import live with `ifResourceExists=OVERWRITE`. The hook now substitutes `LDAP_BIND_CREDENTIAL`, uses a bounded timeout, and the deployment no longer carries an empty `volumes:` key. Issue doc: `docs/issues/2026-05-14-keycloak-live-json-reconcile-without-rebuild.md`.
- **REVIEW FOLLOW-UP:** Copilot asked for the release-note scope and live-reconcile docs to match the shipped behavior. The README release note now describes the PostSync hook plus manifest/test updates, and the issue doc now clarifies that the mounted realm input is the unrendered JSON at `/realm`.
- **IN PROGRESS:** `bug/keycloak-ldap-mappers-missing` now carries the Keycloak LDAP mapper reconcile fix plus Istio/ArgoCD networking manifests. Commit `d3d4597` pushed to `origin/bug/keycloak-ldap-mappers-missing`; PR `https://github.com/wilddog64/shopping-cart-infra/pull/55` opened and Copilot reviewer requested.

## Next Steps
- **Observability Stage 1:** Deploy ServiceMonitors for Keycloak, LDAP, and databases.
- **Grafana Dashboards:** Port/customize dashboards for core infra components.
- **Cross-cluster ESO:** Validate application cluster pods retrieving secrets from the Hub cluster's Vault instance.
