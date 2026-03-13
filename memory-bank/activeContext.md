# Active Context: shopping-cart-infra

## Current Branch: `fix/ci-stabilization` (as of 2026-03-13)

**Focus: CI Stabilization — get all 5 service repos green before branch protection + linters**

---

## CI Status

| Repo | PR | Status | Notes |
|---|---|---|---|
| shopping-cart-product-catalog | #1 | ✅ green | Ready to merge |
| rabbitmq-client-java | #1 | ✅ publish passing | Package in GitHub Packages |
| shopping-cart-frontend | #1 | ❌ lint fail | `react-refresh/only-export-components` warnings in Badge.tsx, Button.tsx, test-utils.tsx |
| shopping-cart-payment | #1 | ❌ build fail | rabbitmq version mismatch (1.0.0 vs SNAPSHOT) + missing `packages: read` permission — Round 3 spec |
| shopping-cart-order | #1 | ❌ build fail | `packages: read` permission missing on build job — Round 3 spec |

---

## Open Items

- [ ] frontend PR #1 — fix `react-refresh/only-export-components` in Badge.tsx, Button.tsx, test-utils.tsx
- [ ] payment PR #1 — Round 3: change rabbitmq-client.version to 1.0.0-SNAPSHOT + add GitHub Packages repo + maven-settings.xml + `packages: read` permission
- [ ] order PR #1 — Round 3: add `packages: read` to build job in ci.yml
- [ ] After all CI green — merge all PRs to main
- [ ] After merge — P4 linters: golangci-lint (basket), ruff+mypy (product-catalog), Checkstyle+OWASP (order), Checkstyle+SpotBugs (payment)
- [ ] After linters — branch protection on all 5 repos via `gh api`
- [ ] After branch protection — cut v0.1.0 release branches on all 6 repos

---

## Specs

- Round 1+2: `docs/plans/ci-stabilization.md` (commit ccd61d91)
- Round 3: `docs/plans/ci-stabilization-round3.md` (commit c5797539)

---

## Infrastructure State (as of 2026-03-13)

Two-cluster architecture active:
- Infra cluster: k3d on OrbStack on M2 Air — Vault, ESO, Istio, Jenkins, ArgoCD, Keycloak
- App cluster: Ubuntu k3s — shopping-cart-data running ✅, shopping-cart-apps ImagePullBackOff (blocked on CI green)

ArgoCD syncs app cluster from this repo. Images blocked until CI pushes to ghcr.io.
