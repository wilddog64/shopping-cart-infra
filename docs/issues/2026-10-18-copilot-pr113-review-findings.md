# Copilot review findings — PR #113 (MinIO uploader image)

**Date:** 2026-10-18
**PR:** #113, merged `1be75f5f` before the review arrived
**Fixed on:** `fix/minio-uploader-pin` (step 2 PR)

## Finding 1 — `:1.0.0` is hard-coded and gets overwritten

**Where:** `.github/workflows/minio-uploader-image.yml:52` (`tags:`)

Copilot (optional, maintainability): every later run of the workflow — any change under
`data-layer/minio/uploader/**` or a `workflow_dispatch` — re-pushes `:1.0.0` with new content, so two
digests end up sharing one version tag.

**Fix:**
- The version lives in `data-layer/minio/uploader/VERSION` (`1.0.0`) and must be `MAJOR.MINOR.PATCH`.
- The workflow reads it, and if `ghcr.io/wilddog64/minio-image-uploader:<version>` is already published
  it emits a `::warning::` and skips build, push and signing. A published version is never overwritten.
- A changed uploader therefore ships only with a `VERSION` bump.
- The BATS suite asserts the tag comes from the VERSION step, that build/cosign steps are gated on
  `publish == 'true'`, and that `VERSION` matches the tag the Job pins. The workflow assertion is red
  against the pre-fix workflow.

**Why skip rather than fail:** adding `VERSION` itself touches `uploader/**`, so the merge reruns the
workflow while `1.0.0` exists. A failure there would put a red run on `main` for a correct state.
The Job pins a digest, so a forgotten bump cannot reach the cluster; it shows up as the warning and
as a Job pin that still names the old version.

## Process note

A workflow that publishes a semver tag needs an explicit version source and an overwrite guard from the
first PR. Add both to future image-publishing specs.
