# Retrospective — shopping-cart-infra PR #68

**Date:** 2026-05-25
**Milestone:** Keycloak reconcile job idempotency fix
**PR:** #68 — merged to main (`6f37459d`)
**Participants:** Claude, Codex, Copilot

## What Went Well
- Copilot caught two real issues: masked failure exit codes and CHANGELOG/PR description mismatch
- Fix was small and targeted — only the reconcile job script changed
- `_pi_rc=0 / || _pi_rc=$?` pattern correctly captures exit code without interfering with `set -euo pipefail`

## What Went Wrong
- Codex's original `ab328cc` commit edited the wrong client (frontend instead of argocd) and the wrong file — required a revert
- Bug spec was written against a file path (`identity/config/realm-shopping-cart.json`) that doesn't exist in the repo; root cause analysis had to be redone after Codex's work
- `enforce_admins` had already been disabled before post-merge ran (done inline in main conversation)

## Process Rules Added
None added to CLAUDE.md this milestone.

## Decisions Made
- `partialImport` failures are tolerated on re-runs because PostgreSQL duplicate-key is expected behavior; script must always continue to LDAP setup
- PKCE (`S256`) is intentionally kept on the `frontend` client — SPA public clients should use PKCE
- `identity/config/realm-shopping-cart.json` does not exist; `acg-up` was referencing the wrong path and needed its own fix in k3d-manager

## Theme
A deceptively simple idempotency bug — `set -euo pipefail` silently swallowing a duplicate-key PostgreSQL error on every ArgoCD re-sync — cascaded into `user_not_found` login failures. The fix was one `if !` block, but it took careful verification to catch that Codex had fixed the wrong client and the spec had named a non-existent file. Copilot then sharpened the fix by requiring the actual exit code be logged rather than assuming the cause.
