# Bug: ArgoCD Persistent OutOfSync — data-layer + shopping-cart-networking

**Date:** 2026-05-31
**Branch (work repo):** `bugfix/argocd-persistent-out-of-sync` (create from `docs/next-improvements`)
**Repos:** `shopping-cart-infra` only
**Symptom:** `data-layer` and `shopping-cart-networking` remain OutOfSync after every fresh cluster rebuild despite `selfHeal: true`.

---

## Root Causes

### 1. `data-layer` — missing `storageClassName` in StatefulSet volumeClaimTemplates

Kubernetes's admission controller injects the default StorageClass (`local-path` on k3s clusters) into every `spec.volumeClaimTemplates[].spec.storageClassName` that is unset at create time. The injected value is persisted in etcd. ArgoCD compares live state against git and sees `storageClassName: local-path` in the cluster but nothing in git → persistent OutOfSync.

**RabbitMQ** already has `storageClassName: local-path` set explicitly and does NOT show this drift.
All other StatefulSets are missing it.

### 2. `shopping-cart-networking` — mixed Istio API versions (`v1beta1` vs `v1`)

`networking.istio.io/v1` is the stable GA API since Istio 1.22. Some manifests use `v1beta1` while others use `v1`. Istiod's CRD storage version preference for `v1` can cause ArgoCD's manifest normalization to see drift on the `v1beta1` resources.

---

## Files to Change

### `data-layer` — add `storageClassName: local-path` to each volumeClaimTemplate spec

**`data-layer/postgresql/orders/statefulset.yaml`** (line 97–102):
```yaml
# BEFORE
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi
```
```yaml
# AFTER
      spec:
        storageClassName: local-path
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi
```

**`data-layer/postgresql/products/statefulset.yaml`** (line 97–102) — identical change:
```yaml
# BEFORE
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi
```
```yaml
# AFTER
      spec:
        storageClassName: local-path
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi
```

**`data-layer/postgresql/payment/statefulset.yaml`** (line 100–105) — identical change:
```yaml
# BEFORE
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi
```
```yaml
# AFTER
      spec:
        storageClassName: local-path
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 5Gi
```

**`data-layer/redis/orders-cache/statefulset.yaml`** (line 101–106):
```yaml
# BEFORE
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 2Gi
```
```yaml
# AFTER
      spec:
        storageClassName: local-path
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 2Gi
```

**`data-layer/redis/cart/statefulset.yaml`** (line 101–106) — identical change:
```yaml
# BEFORE
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 2Gi
```
```yaml
# AFTER
      spec:
        storageClassName: local-path
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 2Gi
```

**`data-layer/minio/statefulset.yaml`** (line 90–95):
```yaml
# BEFORE
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
```
```yaml
# AFTER
      spec:
        storageClassName: local-path
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
```

---

### `networking/istio` — upgrade VirtualService API version from `v1beta1` to `v1`

**`networking/istio/frontend-virtualservice.yaml`** (line 2):
```yaml
# BEFORE
apiVersion: networking.istio.io/v1beta1
```
```yaml
# AFTER
apiVersion: networking.istio.io/v1
```

**`networking/istio/argocd-virtualservice.yaml`** (line 2):
```yaml
# BEFORE
apiVersion: networking.istio.io/v1beta1
```
```yaml
# AFTER
apiVersion: networking.istio.io/v1
```

---

## Before You Start

1. `git pull origin docs/next-improvements` in `shopping-cart-infra`
2. `git checkout -b bugfix/argocd-persistent-out-of-sync`
3. Read all 8 target files listed above before editing

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the 8 target files listed above
- Do NOT commit to `main` or `docs/next-improvements` — work on `bugfix/argocd-persistent-out-of-sync`
- Do NOT change `storageClassName` on the RabbitMQ StatefulSet — it already has `local-path` set

## Rules

- YAML indentation must be preserved exactly — `storageClassName` line goes between the `spec:` key and the `accessModes:` key
- No other changes to any file — minimal patch only

## Definition of Done

- [ ] All 6 StatefulSet files have `storageClassName: local-path` added to `spec` inside `volumeClaimTemplates`
- [ ] Both VirtualService files have `apiVersion: networking.istio.io/v1`
- [ ] `git diff --stat` shows exactly 8 files changed, no other files
- [ ] Commit message: `fix(argocd): pin storageClassName + normalize Istio API versions to stop persistent OutOfSync`
- [ ] `git push origin bugfix/argocd-persistent-out-of-sync` succeeds
- [ ] Report back: commit SHA + paste push output
