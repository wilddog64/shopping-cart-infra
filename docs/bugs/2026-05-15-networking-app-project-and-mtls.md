---
# Bugfix: networking ArgoCD app wrong project + Keycloak mTLS blocked from cicd namespace

**Branch:** `shopping-cart-infra-v0.5.2`
**Files:**
- `networking/istio/keycloak-destinationrule.yaml` (new)

---

## Before You Start

1. `git -C <shopping-cart-infra-path> pull origin shopping-cart-infra-v0.5.2`
2. Read this spec in full before touching any file
3. Read `argocd/applications/networking.yaml` — confirm line 15 still says `project: shopping-cart`
4. Confirm `networking/istio/keycloak-destinationrule.yaml` does NOT exist yet

**Branch (work repo):** `shopping-cart-infra-v0.5.2`

---

## Problem A — shopping-cart AppProject never applied to cluster

`argocd/applications/networking.yaml` correctly references `project: shopping-cart`.
The `shopping-cart` AppProject IS defined in the repo at `argocd/projects/shopping-cart.yaml`,
but it was never applied to the cluster. When the networking Application was created, ArgoCD
rejected it (`Unknown/Unknown`) because the project didn't exist in-cluster.

**Root cause:** `argocd/projects/shopping-cart.yaml` is in the repo but not managed by any
ArgoCD Application (the App of Apps only watches `argocd/applications/`, not `argocd/projects/`).
The AppProject must be applied manually or via a bootstrap Application.

### Fix A

Apply the existing AppProject definition to the cluster:
```bash
kubectl apply -f argocd/projects/shopping-cart.yaml
```

No change to `argocd/applications/networking.yaml` — `project: shopping-cart` is already correct.

Note: `argocd/projects/shopping-cart.yaml` is not tracked by any ArgoCD Application.
It must be applied as a cluster bootstrap step (`kubectl apply -f argocd/projects/shopping-cart.yaml`).

---

## Problem B — Keycloak not reachable from cicd namespace (Istio mTLS)

ArgoCD runs in the `cicd` namespace, which has `istio-injection=enabled`. Its pods have
an Istio sidecar. Keycloak runs in `identity`, which does NOT have Istio injection —
no sidecar on the Keycloak pod.

When ArgoCD's sidecar tries to connect to `keycloak.identity.svc.cluster.local` for
OIDC token exchange, Istio attempts mTLS. The Keycloak pod has no sidecar to complete
the mTLS handshake → connection refused. ArgoCD's OIDC setup silently fails.

**Symptoms:**
- `kubectl run -n cicd` curl to `keycloak.identity.svc.cluster.local` → connection refused
- Same curl from `identity` namespace → HTTP 200
- ArgoCD logs show `sso: false` until a DestinationRule with `DISABLE` is applied

### Fix B — Add DestinationRule disabling mTLS for Keycloak

Create `networking/istio/keycloak-destinationrule.yaml`:

```yaml
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: keycloak-disable-mtls
  namespace: istio-system
spec:
  host: keycloak.identity.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
```

This tells all Istio sidecars to use plaintext when connecting to Keycloak (which has
no sidecar and cannot complete mTLS handshake).

**Note:** Also add `argocd.identity.svc.cluster.local` if ArgoCD ever moves to the
identity namespace, but for now only Keycloak needs this.

---

## Verification (in-cluster state already fixed via kubectl apply)

The following were applied directly to unblock SSO:
1. `kubectl apply -f argocd/projects/shopping-cart.yaml` — creates the AppProject
2. `kubectl apply -f` the DestinationRule above

ArgoCD self-healed the networking Application once the project existed in-cluster.

---

## Files Changed

| File | Change |
|------|--------|
| `networking/istio/keycloak-destinationrule.yaml` | New file — DestinationRule disabling mTLS (`v1beta1`) |

---

## What NOT to Do

- Do NOT create a PR — this branch will get its own PR later
- Do NOT skip pre-commit hooks — use `PRE_COMMIT_ALLOW_NO_CONFIG=1 git commit` instead of `--no-verify`
- Do NOT commit to `main` — work only on `shopping-cart-infra-v0.5.2`
- Do NOT run kubectl or touch the cluster — the in-cluster state is already correct; only git needs updating

---

## Rules

- Commit on `shopping-cart-infra-v0.5.2`
- Use `PRE_COMMIT_ALLOW_NO_CONFIG=1 git commit`
- Push to `origin/shopping-cart-infra-v0.5.2`

**Commit message (exact):**
```
fix(networking): correct ArgoCD project name and add Keycloak DestinationRule for mTLS
```

---

## Definition of Done

- [ ] `argocd/applications/networking.yaml` has `project: platform`
- [ ] `networking/istio/keycloak-destinationrule.yaml` exists with `tls.mode: DISABLE`
- [ ] Committed and pushed to `origin/shopping-cart-infra-v0.5.2`
- [ ] Commit SHA verified on `origin/shopping-cart-infra-v0.5.2`
