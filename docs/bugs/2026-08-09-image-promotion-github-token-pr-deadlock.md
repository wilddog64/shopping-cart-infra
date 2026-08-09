# Bugfix: image-promotion gate deadlocks under GITHUB_TOKEN + no loop guard

**Repo:** shopping-cart-infra (reusable workflow) + consumers order/payment/basket
**Branch (infra):** `fix/promotion-direct-push-skip-ci`
**File:** `.github/workflows/build-push-deploy.yml`

---

## Problem

`build-push-deploy.yml` (reusable "Build, Scan, Push, Deploy") promotes a freshly built
image by bumping `k8s/base/kustomization.yaml`'s `newTag`, opening a `ci/deploy-*` PR, and
`gh pr merge --auto`-ing it. On every push to a consumer's `main`, the `build-push` job's
`promote` step **fails at the gate**, turning `main` CI red (first seen: shopping-cart-order
run `31142951387`, after PR #67 merged; payment/basket would hit the same on their next push).

**Two compounding root causes:**

1. **GITHUB_TOKEN can't produce a mergeable promotion PR.**
   - The promote step authenticates `gh` with `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`.
   - With the repo policy `can_approve_pull_request_reviews: false`, `gh pr create` fails
     outright: `GitHub Actions is not permitted to create or approve pull requests`.
   - Even after enabling that policy (done 2026-08-09 on all three repos), the bot-created PR
     **still cannot merge**: GitHub deliberately does **not** trigger workflows for events
     raised by the default `GITHUB_TOKEN` (anti-recursion). So the PR's *required* strict
     checks (`Build & Test`, `Checkstyle`) **never run**, and `main` requires 1 review — the
     PR is `mergeStateStatus: BLOCKED` / `REVIEW_REQUIRED` forever, then the 30×10s poll times
     out → `exit 1`.
   - Historical contrast: earlier promotion PRs (#65/#66) merged because they were created by
     a **PAT** (`wilddog64`), whose PR events *do* trigger CI, and the review count was 0 at
     the time (later restored to 1).

2. **No convergence / loop guard.**
   - `on: push: branches: [main]` has no `paths-ignore`, and the promotion commit carries no
     `[skip ci]`. Each promotion commit is itself a push to `main` → triggers `build-push`
     again → new `sha-<commit>` → another promotion. The flow never converges; every merge to
     `main` leaves a failing push-run (visible across the run history).

---

## Fix (chosen approach: bypass actor + direct push)

Replace the PR-create/auto-merge dance with a **direct push to the default branch**, guarded
by `[skip ci]` so the promotion commit does not re-trigger the workflow. `github-actions[bot]`
is added as a **bypass actor** on each consumer repo's `main` ruleset so the direct push is
allowed while human PRs keep review + required checks.

### Change 1 — `.github/workflows/build-push-deploy.yml`: drop unused PR permission

**Old:**
```yaml
    permissions:
      contents: write
      pull-requests: write
      packages: write
```
**New:**
```yaml
    permissions:
      contents: write
      packages: write
```

### Change 2 — `.github/workflows/build-push-deploy.yml`: direct push + `[skip ci]`

**Old (the `git commit` line through the `env:` block of the `promote` step):**
```yaml
          git commit -m "ci: update ${{ inputs.service-name }} to sha-${{ github.sha }}"
          branch="ci/deploy-${{ inputs.service-name }}-${{ github.sha }}"
          git push origin "HEAD:${branch}"
          pr_url=$(gh pr create --base main --head "${branch}" \
            --title "ci: deploy ${{ inputs.service-name }} sha-${{ github.sha }}" \
            --body "Automated image promotion for ${{ inputs.service-name }}.")
          pr_number="${pr_url##*/}"
          gh pr merge --auto --squash "${pr_number}"
          for _attempt in $(seq 1 30); do
            state=$(gh pr view "${pr_number}" --json state --jq .state)
            [ "${state}" = "MERGED" ] && exit 0
            [ "${state}" = "CLOSED" ] && exit 1
            sleep 10
          done
          echo "Timed out waiting for promotion PR ${pr_url} to merge" >&2
          exit 1
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```
**New:**
```yaml
          git commit -m "ci: update ${{ inputs.service-name }} to sha-${{ github.sha }} [skip ci]"
          if ! git push origin "HEAD:${{ github.ref_name }}"; then
            git pull --rebase origin "${{ github.ref_name }}"
            git push origin "HEAD:${{ github.ref_name }}"
          fi
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

The `git diff --cached --quiet` early-exit ("Image tag already matches") is retained above the
changed block — it is the idempotency guard for reruns.

### Change 3 — ruleset bypass actor (per consumer repo: order, payment, basket)

Each repo's `main` is protected by **classic branch protection** (required PR + strict checks
+ `enforce_admins`), which has **no per-actor bypass**. Add a repository **ruleset** targeting
`main` with `github-actions[bot]` (the Actions integration) as a **bypass actor** so the
direct push is allowed. Keep the pull-request + required-status-check rules for human authors.
(Alternatively: keep classic protection for humans and rely solely on the ruleset bypass for
the bot — verify direct push succeeds end-to-end before repinning all three.)

### Change 4 — repin consumers to the new infra ref

`.github/workflows/ci.yml` (order, payment) and `.github/workflows/go-ci.yml` (basket, if it
calls the reusable workflow) pin `wilddog64/shopping-cart-infra/.github/workflows/build-push-deploy.yml@<ref>`.
Bump each to the merge SHA of this fix. Also drop the callers' `pull-requests: write` grant on
the build-push job (no longer required).

---

## Files Changed

| Repo | File | Change |
|------|------|--------|
| shopping-cart-infra | `.github/workflows/build-push-deploy.yml` | direct push + `[skip ci]`; drop `pull-requests: write` |
| order/payment/basket | `main` ruleset | add `github-actions[bot]` bypass actor |
| order/payment/basket | `ci.yml` / `go-ci.yml` | repin reusable-workflow ref; drop caller `pull-requests: write` |

---

## Definition of Done

- [ ] Reusable workflow pushes the tag bump directly to the default branch with `[skip ci]`
- [ ] `github-actions[bot]` bypass actor added to `main` on order/payment/basket
- [ ] Consumers repinned; one real push to `main` promotes green with **no** re-triggered run
- [ ] Stale `ci/deploy-*` branches pruned; open promotion PR (#69 on order) closed
- [ ] `enforce_admins` state confirmed restored where temporarily disabled
- [ ] memory-bank updated with commit SHAs and task status (separate commit)

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT commit to `main` — work on the feature branch and open a PR
- Do NOT bundle the pre-existing uncommitted `identity/` working-tree edits into this commit
- Do NOT weaken required reviews/checks for **human** PRs — the bypass is bot-only
