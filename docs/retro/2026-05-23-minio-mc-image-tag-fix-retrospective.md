# Retrospective — minio/mc Image Tag Fix

**Date:** 2026-05-23
**PR:** #63 — merged to main
**Participants:** Claude

## What Went Well
- Bug spec written before fix (spec-before-implement rule followed)
- Correct branch + PR flow used after initial attempt to push directly to main
- CI green, Copilot clean

## What Went Wrong
- Initial fix was committed directly to main (caught by user before push succeeded)
- Wasted context time diagnosing the wrong cluster (local k3d instead of ubuntu-k3s)

## Process Rules Applied
- spec-before-implement: bug spec written to `docs/bugs/` before any code edit
- No direct push to main in shopping-cart repos: branch + PR required

## Decisions Made
- minio/mc pinned to `RELEASE.2024-11-05T11-29-45Z` (nearest valid tag to the nonexistent `RELEASE.2024-11-07T00-52-20Z`)

## Theme
Fixed a nonexistent minio/mc image tag that was blocking the bucket-init and image-upload ArgoCD PostSync jobs. The fix was straightforward but revealed a workflow gap: always verify cluster context (ubuntu-k3s for shopping-cart apps) before diagnosing pod failures.
