# Bug: StatefulSet volumeClaimTemplates storageClassName immutable field causes ArgoCD sync failure

**Date:** 2026-05-31
**Severity:** High — data-layer Application stuck in sync loop
**Affects:** postgresql-orders, postgresql-payment, postgresql-products, redis-cart, redis-orders-cache, minio

## Symptom

ArgoCD `data-layer` Application fails sync repeatedly with:

```
error when patching "/dev/shm/<random>": StatefulSet.apps "postgresql-orders" is invalid:
spec: Forbidden: updates to statefulset spec for fields other than 'replicas', 'ordinals',
'template', 'updateStrategy', 'revisionHistoryLimit', 'persistentVolumeClaimRetentionPolicy'
and 'minReadySeconds' are forbidden
```

Same error for: `postgresql-payment`, `postgresql-products`, `redis-cart`, `redis-orders-cache`, `minio`.

With `selfHeal: true` the Application retries every sync interval, logging the error each time.

## Root Cause

PR #79 added `storageClassName: local-path` to `volumeClaimTemplates.spec` in all 6 StatefulSet
definitions to fix a persistent ArgoCD OutOfSync diff. However, `volumeClaimTemplates` is an
**immutable field** in Kubernetes — any attempt to patch it (even to add a matching value) is
rejected by the API server.

The existing StatefulSets were created without an explicit `storageClassName` in `volumeClaimTemplates`.
Kubernetes stored the original spec (no `storageClassName` / empty string). When git now specifies
`local-path`, ArgoCD detects a diff and tries to patch → Kubernetes rejects.

Note: The PVCs themselves correctly use `local-path` (injected by k3s default StorageClass). The
StatefulSet object simply retains the original spec it was created with.

## Fix

Add `ignoreDifferences` to `argocd/applications/data-layer.yaml` for `storageClassName` and
`volumeMode` in `volumeClaimTemplates`. These fields are auto-populated by Kubernetes on the
live objects but are not set in the original StatefulSet specs.

**File:** `argocd/applications/data-layer.yaml`

### Before

```yaml
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
```

### After

```yaml
  ignoreDifferences:
    - group: apps
      kind: StatefulSet
      jqPathExpressions:
        - .spec.volumeClaimTemplates[].spec.storageClassName
        - .spec.volumeClaimTemplates[].spec.volumeMode

  syncPolicy:
    automated:
      prune: false
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
```

## Why This Works

`ignoreDifferences` tells ArgoCD to skip these fields when comparing desired (git) vs live
(cluster) state. ArgoCD stops seeing a diff → stops trying to patch → sync succeeds.

On a fresh cluster (`make up`), StatefulSets will be created with `storageClassName: local-path`
from the start (from the git definition), so the diff never appears on new deployments.

## Definition of Done

- [ ] `ignoreDifferences` block added to `argocd/applications/data-layer.yaml`
- [ ] Committed on branch `docs/next-improvements` with message:
  `fix(argocd): ignore volumeClaimTemplates storageClassName diff to unblock data-layer sync`
- [ ] Pushed to origin
- [ ] memory-bank NOT updated (Codex prohibited from editing k3d-manager memory-bank)

## What NOT To Do

- Do NOT delete the StatefulSets — PVCs and pods are healthy, no disruption needed
- Do NOT revert the `storageClassName: local-path` additions from PR #79 — they are correct
- Do NOT create a PR — user will handle that
- Do NOT commit to `main` — work on `docs/next-improvements`
- Do NOT skip pre-commit hooks (`--no-verify`)
