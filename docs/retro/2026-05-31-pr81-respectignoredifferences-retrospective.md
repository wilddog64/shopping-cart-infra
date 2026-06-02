# Retrospective — PR #81: RespectIgnoreDifferences

**Date:** 2026-05-31
**PR:** #81 — merged to main
**Change:** `fix(argocd): add RespectIgnoreDifferences to data-layer syncOptions`
**Participants:** Claude, Codex, Copilot
**Merge SHA:** 1eaf1e47f266f8fc5e1b6d34b8e6ec7234e6c61d

## What Went Well

- Root cause correctly identified: `ignoreDifferences` alone only suppresses diff display; `RespectIgnoreDifferences=true` is required to strip ignored fields from sync payloads
- Codex implemented the fix cleanly (one-line addition to syncOptions)
- CHANGELOG was updated with detailed explanation
- CI (Validate Manifests) passed cleanly
- Copilot review had no inline comments

## What Went Wrong

- Branch `docs/next-improvements` was dirty at PR creation due to squash-merge divergence (pre-squash commits from PR #80 still in branch history). Required `git reset --hard origin/main` + cherry-pick + force-push to resolve.
- Stale `operationState` in ArgoCD caused confusion — the last sync failure message persisted even after the app transitioned to Synced Healthy. The error was from before PR #80 landed.

## Root Cause of Original Bug

ArgoCD `ignoreDifferences` only affects diff detection (the UI / health check). When ArgoCD syncs for any reason (drift, manual trigger, app restart), it still includes `storageClassName` and `volumeMode` in the applied manifest, and Kubernetes rejects the patch because these are immutable fields on existing StatefulSets. `RespectIgnoreDifferences=true` strips those fields from the sync payload entirely.

## Decisions Made

- `RespectIgnoreDifferences=true` added to data-layer Application syncOptions alongside the existing `ignoreDifferences` block (from PR #80)
- No RBAC or ArgoCD app version changes needed — this option is supported in ArgoCD v3.x (cluster runs v3.4.2)

## Theme

A one-line syncOptions addition that permanently closes the immutable-field sync failure pattern for all six StatefulSets (postgresql-orders, postgresql-payment, postgresql-products, redis-cart, redis-orders-cache, minio). The fix is complementary to PR #80's `ignoreDifferences`: #80 fixed diff detection, #81 fixed sync payload inclusion.

## Lessons Learned

- Immutable field handling in Kubernetes StatefulSets requires both diff suppression (ArgoCD `ignoreDifferences`) AND payload filtering (ArgoCD `RespectIgnoreDifferences`). Neither alone is sufficient.
- Stale operationState in ArgoCD can mask actual sync success — clearing the condition required a manual ArgoCD sync or app restart to refresh the UI.
- Branch squash merges into `docs/next-improvements` should be rebase-merged instead to maintain linear history, reducing divergence on follow-up work.
