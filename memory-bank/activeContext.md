# Active Context: shopping-cart-infra

## Current Branch: `fix/ci-stabilization` (as of 2026-03-14)

**Focus: CI Stabilization — get all 5 service repos green before branch protection + linters**

---

## CI Status

| Repo | PR | Status | Notes |
|---|---|---|---|
| shopping-cart-product-catalog | #1 | ✅ green | Ready to merge |
| rabbitmq-client-java | #1 | ✅ green | Package published, ready to merge |
| shopping-cart-order | #1 | ✅ green | PACKAGES_TOKEN secret + maven-settings fixed |
| shopping-cart-frontend | #1 | ❌ lint fail | `react-refresh/only-export-components` warnings in Badge.tsx, Button.tsx, test-utils.tsx |
| shopping-cart-payment | #1 | ❌ compile fail | Pre-existing broken test code — `org.testcontainers.junit.jupiter` not found + `com.shoppingcart.payment.exception` missing. Spec: `docs/plans/ci-payment-test-fix.md` |

---

## Open Items

- [ ] payment PR #1 — fix broken test compilation (Round 4 spec: `docs/plans/ci-payment-test-fix.md`)
- [ ] frontend PR #1 — fix `react-refresh/only-export-components` in Badge.tsx, Button.tsx, test-utils.tsx
- [ ] After all CI green — merge all PRs to main
- [ ] After merge — P4 linters: golangci-lint (basket), ruff+mypy (product-catalog), Checkstyle+OWASP (order), Checkstyle+SpotBugs (payment)
- [ ] After linters — branch protection on all 5 repos via `gh api`
- [ ] After branch protection — cut v0.1.0 release branches on all 6 repos

---

## PAT Token Rotation — Decision (2026-03-14)

**Current:** `PACKAGES_TOKEN` secret in shopping-cart-order + shopping-cart-payment repos.
Used by maven-settings.xml to read `com.shoppingcart:rabbitmq-client` from GitHub Packages.

**Problem:** PAT expires and must be manually rotated across multiple repo secrets.

**Decision: Option 3 — Vault-managed rotation (deferred to post-CI-green)**

```
PAT stored in Vault KV (secret/github/packages-read-token)
→ rotation script updates Vault + re-runs gh secret set on all repos
→ single update point, all consumers get new token
```

A small sync script (or k3dm-mcp tool) reads from Vault and pushes to GitHub repo secrets via `gh secret set`. ESO cannot write to GitHub secrets directly — the bridge is a script or MCP tool.

**Near-term:** Use 1-year PAT (manual rotation with calendar reminder).
**Long-term:** Vault-managed via k3dm-mcp `rotate_github_token` tool (v0.2.0+).

Spec to write when k3dm-mcp v0.1.0 ships.

---

## Specs

- Round 1+2: `docs/plans/ci-stabilization.md` (commit ccd61d91)
- Round 3: `docs/plans/ci-stabilization-round3.md` (commit c5797539)
- Round 4 (payment test fix): `docs/plans/ci-payment-test-fix.md`

---

## Infrastructure State (as of 2026-03-13)

Two-cluster architecture active:
- Infra cluster: k3d on OrbStack on M2 Air — Vault, ESO, Istio, Jenkins, ArgoCD, Keycloak
- App cluster: Ubuntu k3s — shopping-cart-data running ✅, shopping-cart-apps ImagePullBackOff (blocked on CI green)

ArgoCD syncs app cluster from this repo. Images blocked until CI pushes to ghcr.io.
