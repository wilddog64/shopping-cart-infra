# Retrospective — MinIO MC_CONFIG_DIR Fix

**Date:** 2026-05-23
**PR:** #64 — merged to main
**Participants:** Claude, Copilot

## What Went Well
- Root cause identified quickly: minio/mc UID 1000 cannot write to /root/.mc
- Both affected jobs fixed in a single PR (bucket-init + image-upload)
- Copilot caught the incomplete Files Changed table and stale process instructions in the bug spec
- Fix verified live: minio-bucket-init job ran to Complete on ubuntu-k3s

## What Went Wrong
- Bug spec Files Changed table was incomplete on first commit (missing image-upload-job.yaml and CHANGELOG.md)
- Bug spec Rules section still said "No other files touched" after image-upload-job.yaml was also changed
- Bug spec included "Do NOT create a PR" instruction — contradicted by the PR itself

## Process Rules Applied
- spec-before-implement: bug spec written to docs/bugs/ before any code edit
- No direct push to main: branch + PR required

## Decisions Made
- MC_CONFIG_DIR=/tmp/.mc is the canonical fix pattern for any minio/mc job running as non-root

## Theme
Chasing a second MinIO job failure immediately after fixing the image tag in PR #63. The mc binary's assumption about /root being writable is a footgun for non-root container security — the fix (MC_CONFIG_DIR env var) is simple once the root cause is known. Copilot's doc review caught three spec inconsistencies that would have confused future readers.
