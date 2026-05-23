# Bug: minio-bucket-init job fails — mc cannot write config to /root/.mc

**Date:** 2026-05-23
**File:** `data-layer/minio/bucket-init-job.yaml`
**Branch:** `main` (fix on `fix/minio-mc-config-dir`)

---

## Problem

`minio-bucket-init` job loops indefinitely with:

```
mc: <ERROR> Unable to save new mc config. mkdir /root/.mc: permission denied.
Waiting for MinIO...
```

**Root cause:** `quay.io/minio/mc` runs as a non-root user (UID 1000, home `/home/mc`). The `mc` CLI
defaults to `$HOME/.mc` for its config dir. With no `HOME` or `MC_CONFIG_DIR` env var set, it tries
to write to `/root/.mc`, which is not writable by UID 1000. The `mc alias set` command never
succeeds, so the loop never exits.

---

## Reproduction

Apply `data-layer/minio/bucket-init-job.yaml` and watch logs:
```
kubectl logs -l app.kubernetes.io/component=bucket-init -n shopping-cart-data
```
Expected: `mc alias set` succeeds and bucket is created.
Actual: `mkdir /root/.mc: permission denied` loops until backoffLimit.

---

## Fix

### Change 1 — `data-layer/minio/bucket-init-job.yaml`: add MC_CONFIG_DIR env var

**Exact old block (lines 41–43):**

```yaml
          envFrom:
            - secretRef:
                name: minio-credentials
```

**Exact new block:**

```yaml
          env:
            - name: MC_CONFIG_DIR
              value: /tmp/.mc
          envFrom:
            - secretRef:
                name: minio-credentials
```

---

## Files Changed

| File | Change |
|------|--------|
| `data-layer/minio/bucket-init-job.yaml` | Add `MC_CONFIG_DIR=/tmp/.mc` env var so mc writes config to writable path |

---

## Rules

- Code change limited to `data-layer/minio/bucket-init-job.yaml`
- No other files touched (CHANGELOG update may also be required)

---

## Definition of Done

- [ ] `data-layer/minio/bucket-init-job.yaml` updated with `MC_CONFIG_DIR` env var
- [ ] Job runs to completion on `ubuntu-k3s`: `kubectl get job minio-bucket-init -n shopping-cart-data` shows `Complete`
- [ ] `product-images` bucket exists: `mc ls local/` shows `product-images`
- [ ] Committed and pushed to `fix/minio-mc-config-dir`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(data-layer): set MC_CONFIG_DIR=/tmp/.mc so mc can write config as non-root user
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the listed targets
- Do NOT commit to `main` — work on `fix/minio-mc-config-dir`
