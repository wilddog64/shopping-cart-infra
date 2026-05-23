# Copilot PR #62 Review Findings

**Date:** 2026-05-23
**PR:** #62 — feat(data-layer): add MinIO in-cluster object store with image pipeline
**Fix commit:** `c9dee05`

## Finding 1 — Go template hyphens in ESO ExternalSecret

**File:** `data-layer/minio/secret.yaml` line 29–30
**Flagged:** `{{ .root-user }}` and `{{ .root-password }}` use hyphenated identifiers in Go template syntax. Hyphens are not valid Go identifier characters; this silently produces an empty string instead of the secret value, so MinIO starts with no credentials.

**Fix:**
```yaml
# Before
data:
  MINIO_ROOT_USER: "{{ .root-user }}"
  MINIO_ROOT_PASSWORD: "{{ .root-password }}"

# After — index function accepts arbitrary string keys
data:
  MINIO_ROOT_USER: "{{ index . \"root-user\" }}"
  MINIO_ROOT_PASSWORD: "{{ index . \"root-password\" }}"
```

**Root cause:** ESO `target.template.data` uses Go template syntax where `.fieldname` only works for valid Go identifiers. Keys with hyphens must use `index . "key-name"` syntax.

**Process note:** When Vault secret keys contain hyphens, always use `{{ index . "key-name" }}` in ESO template blocks.

---

## Finding 2 — mc binary downloaded at runtime via curl (no checksum)

**File:** `data-layer/minio/image-upload-job.yaml` line 34–36
**Flagged:** initContainer uses `curl -sSL https://dl.min.io/client/mc/...` to download mc at runtime with no checksum verification — supply chain risk and network dependency.

**Fix:**
```yaml
# Before — alpine initContainer with curl
- name: install-mc
  image: alpine:3.19
  command:
    - sh
    - -c
    - |
      apk add --no-cache curl ca-certificates
      curl -sSL https://dl.min.io/client/mc/release/linux-amd64/mc \
        -o /shared/mc
      chmod +x /shared/mc

# After — pinned mc image, binary copied to shared volume
- name: copy-mc
  image: quay.io/minio/mc:RELEASE.2024-11-07T00-52-20Z
  command:
    - sh
    - -c
    - cp /usr/bin/mc /shared/mc
```

**Root cause:** Spec required `quay.io/minio/mc:RELEASE.2024-11-07T00-52-20Z`; implementation used curl instead.

**Process note:** Never curl-download binaries in Jobs — use pinned container images and copy the binary to a shared emptyDir.

---

## Finding 3 — No hook ordering between bucket-init and image-upload

**Files:** `data-layer/minio/bucket-init-job.yaml` line 13, `data-layer/minio/image-upload-job.yaml` line 13
**Flagged:** Both PostSync jobs have no `hook-weight`, so ArgoCD may run them in parallel. If image-upload starts before bucket-init, the `mc cp` to `product-images` bucket fails (bucket doesn't exist yet).

**Fix:**
```yaml
# bucket-init-job.yaml — runs first
annotations:
  argocd.argoproj.io/hook: PostSync
  argocd.argoproj.io/hook-delete-policy: HookSucceeded
  argocd.argoproj.io/hook-weight: "0"

# image-upload-job.yaml — runs after bucket is ready
annotations:
  argocd.argoproj.io/hook: PostSync
  argocd.argoproj.io/hook-delete-policy: HookSucceeded
  argocd.argoproj.io/hook-weight: "1"
```

**Root cause:** Spec did not include hook-weight annotations; ArgoCD PostSync hooks run in parallel without them.

**Process note:** Any pair of PostSync Jobs where one depends on the other's output must use `hook-weight` to establish ordering.

---

## Finding 4 — minio-image-pipeline.md references Picsum (stale)

**File:** `docs/minio-image-pipeline.md` line 143
**Flagged:** Bootstrap sequence said "downloads 20 Picsum images" but implementation generates images in-cluster with Pillow.

**Fix:** Updated to "generates 20 images in-cluster with Pillow, uploads to MinIO".

**Root cause:** Architecture doc was drafted before the Picsum→Pillow decision was made; doc was not updated when the implementation changed.

**Process note:** When switching image strategy during spec-writing, update the architecture doc in the same session.
