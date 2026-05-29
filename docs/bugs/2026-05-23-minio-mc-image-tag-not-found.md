# Bug: minio/mc image tag RELEASE.2024-11-07T00-52-20Z does not exist on quay.io

**Date:** 2026-05-23
**Branch:** `main`
**Files:** `data-layer/minio/bucket-init-job.yaml`, `data-layer/minio/image-upload-job.yaml`

---

## Problem

`minio-bucket-init` and `minio-image-upload` pods fail with `ErrImagePull` immediately on
creation. The `product-images` bucket is never created and placeholder images are never
uploaded, so the frontend shows broken image URLs.

**Root cause:** Both jobs reference `quay.io/minio/mc:RELEASE.2024-11-07T00-52-20Z`. That
exact tag does not exist in the `quay.io/minio/mc` repository. The closest available tag is
`RELEASE.2024-11-05T11-29-45Z` (two days prior, same minor version as the minio server image
`RELEASE.2024-11-07T00-52-20Z` which does exist and pulls successfully).

---

## Fix

### Change 1 — `data-layer/minio/bucket-init-job.yaml`

**Old:**
```yaml
          image: quay.io/minio/mc:RELEASE.2024-11-07T00-52-20Z
```

**New:**
```yaml
          image: quay.io/minio/mc:RELEASE.2024-11-05T11-29-45Z
```

### Change 2 — `data-layer/minio/image-upload-job.yaml`

**Old:**
```yaml
            image: quay.io/minio/mc:RELEASE.2024-11-07T00-52-20Z
```

**New:**
```yaml
            image: quay.io/minio/mc:RELEASE.2024-11-05T11-29-45Z
```

---

## Files Changed

| File | Change |
|------|--------|
| `data-layer/minio/bucket-init-job.yaml` | Fix mc image tag |
| `data-layer/minio/image-upload-job.yaml` | Fix mc image tag (init container) |

---

## Rules

- Code change limited to the two listed files; CHANGELOG and memory-bank updates may also be required
- No other files touched

---

## Definition of Done

- [ ] Both files updated to `RELEASE.2024-11-05T11-29-45Z`
- [ ] Committed and pushed
- [ ] `minio-bucket-init` and `minio-image-upload` jobs complete successfully on ubuntu-k3s

**Commit message (exact):**
```
fix(data-layer): correct minio/mc image tag — RELEASE.2024-11-05T11-29-45Z exists, 2024-11-07 does not
```
