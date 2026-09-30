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

## Recurrence-safe ownership decision

The chosen port keeps Bitnami's UID 1001 and performs an ownership migration before MinIO starts.
We did not keep UID 1000: Bitnami's MinIO documentation identifies the image as non-root and says
that mounted files and directories must be writable by UID 1001; it also documents
`/bitnami/minio/data` as the persistent data path. The existing Hostinger PVC uses local-path
storage, which does not apply Kubernetes `fsGroup` ownership changes, so merely changing the pod
security context would not make the existing UID-1000 files readable by MinIO.

The `fix-data-ownership` init container runs as root with the pinned `busybox:1.36` image. It scans
the entire mounted data tree with `find ... ! -user 1001`, so a top-level directory already owned by
1001 cannot hide nested UID-1000 files. If any mismatch is found, it recursively changes ownership
to `1001:1001`; otherwise it does nothing. It keeps `drop: [ALL]` and adds only `CHOWN` and
`DAC_READ_SEARCH`, allowing the scan and recursive ownership update through directories that deny
access to other users. MinIO then starts as UID 1001 against the same PVC and data path.
