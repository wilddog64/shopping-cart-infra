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

### Change 3 — deploy key as bypass actor (per consumer repo: order, payment, basket)

**Two dead ends, both probed 2026-08-09 on a personal (user-owned) repo — rulesets there reject
*any* integration as a bypass actor:**
- `github-actions[bot]` (actor_type Integration, id 15368) → HTTP 422 *"Actor GitHub Actions
  integration must be part of the ruleset source or owner organization."*
- A **user-owned GitHub App** (actor_type Integration) → same 422. App-as-bypass is org-only.

Confirmed accepted bypass actor types on the personal repo: **RepositoryRole** (admin) and
**DeployKey**. Chosen mechanism: a per-repo **deploy key** (no expiry → no rotation, keeps human
review, requires no user setup — provisioned entirely via API).

Per consumer repo (all done via `gh`/API):
1. `ssh-keygen -t ed25519` → add the **public** key as a **write** deploy key
   (`POST /repos/{o}/{r}/keys`, `read_only:false`); store the **private** key as repo secret
   `PROMOTER_SSH_KEY`.
2. Create a **ruleset** on `main` replicating the classic rules (pull_request
   `required_approving_review_count: 1`; required_status_checks strict with `Build & Test` +
   `Checkstyle`; plus `deletion` + `non_fast_forward`) and add the deploy key as a
   `bypass_actors` entry (`actor_type: DeployKey`, the key id; `bypass_mode: always`).
3. **Delete** the classic branch protection (classic + ruleset both apply — the classic PR rule
   would otherwise still block the deploy key). Human authors keep review + checks via the ruleset.

The reusable workflow writes `PROMOTER_SSH_KEY` to `~/.ssh`, sets `GIT_SSH_COMMAND` +
`git remote set-url origin git@github.com:<repo>`, and pushes the `[skip ci]` tag-bump commit
directly to the default branch over SSH. The push is attributed to the deploy key → bypasses.

**Superseded:** the earlier `github-actions[bot]` bypass plan and the GitHub App plan
(`APP_ID`/`APP_PRIVATE_KEY` + `actions/create-github-app-token`) both fail on personal repos.
Any Apps already created for this can be uninstalled.

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
