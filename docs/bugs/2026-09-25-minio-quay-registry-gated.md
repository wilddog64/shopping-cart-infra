# Bug: quay.io/minio is no longer anonymously pullable — repoint the data layer

**Date:** 2026-09-25
**File:** `data-layer/minio/`
**Severity:** blocks `make up CLUSTER_PROVIDER=k3s-aws` at Step 10b on every fresh cluster

## Symptom

`minio-0` never starts; the `<cluster>-data-layer` ArgoCD Application remains `OutOfSync` /
`Progressing` with `operationState.phase: Running`, waiting for healthy state of `apps/StatefulSet/minio`.
The image pull fails with:

```text
Failed to pull image "quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z":
failed to resolve reference: unexpected status from HEAD request to
https://quay.io/v2/minio/minio/manifests/RELEASE.2024-11-07T00-52-20Z: 401 UNAUTHORIZED
```

## Root cause evidence

`quay.io/minio/minio` and `quay.io/minio/mc` require authentication for every tag. This is a
repository-level gate, not a missing tag, network problem, or node-credential problem.

| Probe | Result |
|---|---|
| `quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z` (anonymous pull token) | 401 |
| `quay.io/minio/minio:latest` | 401 |
| `quay.io/minio/minio:RELEASE.2022-01-08T03-11-54Z` | 401 |
| `quay.io/minio/mc:latest` | 401 |
| `quay.io/prometheus/busybox:latest` (control) | 200 |
| `ghcr.io/minio/minio:latest` | 403 |
| `docker.io/minio/minio` | does not exist |

## Replacement

Both Bitnami legacy images are public and carry the same upstream releases:

| Replacement | Current pin | Same upstream release |
|---|---|---|
| `docker.io/bitnamilegacy/minio:2024.11.7-debian-12-r1` | `quay.io/minio/minio:RELEASE.2024-11-07T00-52-20Z` | MinIO 2024-11-07 |
| `docker.io/bitnamilegacy/minio-client:2024.11.5-debian-12-r1` | `quay.io/minio/mc:RELEASE.2024-11-05T11-29-45Z` | mc 2024-11-05 |

A GHCR mirror is impossible from the gated source: mirroring requires pulling the source image
first, and no credentials for `quay.io/minio` are available. The public Bitnami legacy images are
therefore used for this fix.

## Layout deltas

This is a port, not a tag swap. The Bitnami image changes the runtime layout:

| | quay.io/minio | bitnamilegacy/minio |
|---|---|---|
| User | 1000 | 1001 |
| Entrypoint | none | `/opt/bitnami/scripts/minio/entrypoint.sh` |
| Cmd | none | `/opt/bitnami/scripts/minio/run.sh` |
| Data directory | `/data` (via args) | `/bitnami/minio/data` |
| `mc` binary | `/usr/bin/mc` | `/opt/bitnami/minio-client/bin/mc` (also on `PATH`) |

The StatefulSet therefore removes the old `server /data --console-address :9001` args, changes
`runAsUser` and `fsGroup` to `1001`, and mounts the PVC at `/bitnami/minio/data`. The image-upload
init container copies `mc` from the Bitnami path. API and console ports, health probes, credentials,
`MC_CONFIG_DIR=/tmp/.mc`, and `readOnlyRootFilesystem: false` remain unchanged.
