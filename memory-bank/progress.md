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
- [x] Keycloak LDAP mapper reconcile and networking routing fix — added idempotent mapper creation to `identity/keycloak/keycloak-reconcile-hook-job.yaml`, mirrored the 6 LDAP mapper definitions into `identity/keycloak/realm-shopping-cart.json`, switched ArgoCD to `http://argocd.shopping-cart.local`, and added the Istio Gateway/VirtualServices plus the `shopping-cart-networking` ArgoCD Application. Commit `d3d4597`; PR `https://github.com/wilddog64/shopping-cart-infra/pull/55`.
- [x] Copilot review follow-up for LDAP mapper reconcile and networking routing fix — removed `networking/istio/kustomization.yaml`, kept ArgoCD in `directory:` mode, dedented the reconcile-hook Python calls so they parse, and refreshed mapper idempotency checks per loop. Follow-up commit `aa41928` on PR `https://github.com/wilddog64/shopping-cart-infra/pull/55`.
- [x] Dead realm JSON mapper block removed — deleted the nested LDAP `components` block from `identity/keycloak/realm-shopping-cart.json`, corrected the ArgoCD routing doc command from `kubectl apply -k` to `kubectl apply -f`, and verified `python3 -m json.tool identity/keycloak/realm-shopping-cart.json > /dev/null`. Commit `e9733a1`; remote log: `e9733a1 fix(keycloak): remove dead realm JSON mapper block; fix apply-k doc error`.
- [x] Reconcile-hook python3 removal fix — on `shopping-cart-infra-v0.5.1`, replaced both `python3` JSON parsing calls in `identity/keycloak/keycloak-reconcile-hook-job.yaml` with `kcadm.sh` server-side queries, kept the `grep -c '"id"' || echo 0` fallback, verified shellcheck on the extracted hook script, and pushed commit `a2d4907` to `origin/shopping-cart-infra-v0.5.1`.
- [x] `frontend.3ai-talk.org` SSO redirect URI and gateway routing fix — `identity/keycloak/realm-shopping-cart.json` now includes `https://frontend.3ai-talk.org/*` in the `frontend` client redirect URIs, and `networking/istio/gateway.yaml` plus `networking/istio/frontend-virtualservice.yaml` now route `frontend.3ai-talk.org`; commit `da239d1`; validation used `python3 -m json.tool` and Ruby YAML parsing.
- [x] Keycloak browser-flow Option B — reconcile hook drops the custom top-level `otp-conditional-subflow`; `browser-with-conditional-otp` is now a plain copy of built-in `browser` (fixes REQUIRED/ALTERNATIVE-at-same-level → `invalid_user_credentials` for all logins). Codex commit `96c9850` on `fix/keycloak-browser-flow-drop-custom-otp-subflow`. Claude-verified static (grep→0, `bash -n` clean) + LIVE (rebuilt flow level 0 = ALTERNATIVE/DISABLED only; real `admin` PKCE login → auth code). Spec: `docs/bugs/2026-07-25-keycloak-browser-flow-toplevel-conditional-otp-breaks-login.md`. No PR yet.
- [ ] Keycloak LDAP bind DN recovery after `ldap-admin` experiment — realm import now re-applies the repo source of truth at Keycloak startup so existing realms pick up the canonical realm import in `identity/keycloak/realm-shopping-cart.json`.
- [x] Keycloak realm import no longer depends on templated LDAP bind DN — the canonical DN is now literal in the realm template and the initContainer only renders the bind credential from Secret data. `KC_DB_USERNAME` is generated with `keycloak-config`, and the import runs with `--db=postgres --override=true`. Issue docs: `docs/issues/2026-05-13-keycloak-realm-import-invalid-dn-literal-binddn.md` and `docs/issues/2026-05-13-kustomize-cross-directory-realm-file-disallowed.md`.
- [x] Keycloak realm import should skip an existing `shopping-cart` realm — superseded by live reconcile; the startup import path has been removed and realm changes now flow through the Argo CD `PostSync` hook Job instead of `kc.sh import` on boot. Issue doc: `docs/issues/2026-05-13-keycloak-realm-import-should-skip-existing-shopping-cart-realm.md`.
- [x] Live JSON reconcile without rebuild — implemented via an Argo CD `PostSync` hook Job in `identity/keycloak/keycloak-reconcile-hook-job.yaml`; the Keycloak deployment no longer boot-imports the realm. The hook renders the unescaped realm JSON from `/realm`, substitutes the client secrets and `LDAP_BIND_CREDENTIAL`, and uses a bounded timeout so syncs fail visibly instead of hanging. Issue doc: `docs/issues/2026-05-14-keycloak-live-json-reconcile-without-rebuild.md`.

## Milestone: v0.3.0 (Identity & Hardening) — ARCHIVED
- [x] Keycloak + LDAP deployment manifests
- [x] Vault ESO integration for Identity
- [x] OIDC Issuer protocol mismatch resolution
- [x] LDAP bootstrap writable emptyDir fix
- [x] ArgoCD identity Application definition
