# Retrospective — PR #79

**Date:** 2026-05-31
**Milestone:** ArgoCD persistent OutOfSync fix
**PR:** #79 — merged to main (`d5be9712cfb0dbe7d6a9667ba6ec8289dd16e5a9`)
**Participants:** Claude, Codex, Copilot

## What Went Well
- Root cause analysis completed without live cluster — identified storageClassName injection and Istio API version mismatch from static manifest inspection
- Codex implemented all 8 file changes correctly on first attempt — exact match to spec
- CI passed on both fix commit and monitoring corrections
- Copilot caught 3 real issues in monitoring files: wrong AppProject, unbootstrapped Application path, per-pod alert aggregation

## What Went Wrong
- PR #85 was accidentally created for k3d-manager instead of shopping-cart-infra — had to be closed and force-restored enforce_admins
- Monitoring files from docs/next-improvements rode into the diff unexpectedly, adding Copilot review overhead outside the stated scope
- ArgoCD session expired during initial investigation — needed make up to diagnose product-catalog OutOfSync (still unresolved)

## Process Rules Added
None added this cycle.

## Decisions Made
- `storageClassName: local-path` is now the explicit standard for all k3s StatefulSet volumeClaimTemplates — removes dependency on cluster default StorageClass admission injection
- All Istio CRD manifests should use `networking.istio.io/v1` (not v1beta1) — v1 is the GA API since Istio 1.22
- `shopping-cart-product-catalog` OutOfSync deferred — requires live `argocd app diff` to diagnose; tracked as follow-up

## Theme
A persistent-OutOfSync trifecta (data-layer, networking, product-catalog) diagnosed from static manifest analysis. Two root causes were structural: Kubernetes admission controller silently injecting storageClassName into StatefulSet volumeClaimTemplates, and inconsistent Istio API versions creating normalization drift. Both fixed with minimal targeted patches. The third (product-catalog) remains open pending live cluster access.
