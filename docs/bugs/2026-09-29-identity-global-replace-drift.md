# `shopping-cart-identity` retries forever when a bound PVC is globally replaced

**Filed:** 2026-09-29

## Symptom

After PR #101 merged at `00d0d8a`, `shopping-cart-identity` remained
`OutOfSync` and retried its sync. The operation failed while processing the
already-bound `postgres-keycloak-pvc`:

```text
Failed to replace resource: PersistentVolumeClaim "postgres-keycloak-pvc" is invalid: spec: Forbidden: is immutable after creation except resources.requests and volumeAttributesClassName for bound claims
```

The live Application still had the following app-level sync option, even
though `argocd/applications/identity.yaml` in Git did not:

```yaml
syncOptions:
- Replace=true
```

The live PVC had no resource-level `Replace` annotation, so the app-level
option selected replacement for the bound claim. The live Application was
running revision `00d0d8a731e6c99b5cda57d7f0b882512d34fd23` and reported
retry #4 with the same failure.

## Cause

`Replace=true` was an out-of-band, app-level setting on the live Argo CD
Application. The earlier fix added `Replace=false` to selected resources, but
that did not remove the stale application-level option from the live object.
Replacement is unsafe for persistent resources whose Kubernetes spec is
immutable after binding.

## Fix

`argocd/applications/identity.yaml` now declares `Replace=false` explicitly.
The existing PVC-level exemption remains in place. Applying this Application
manifest removes the stale live `Replace=true` entry, after which Argo CD can
reconcile the bound claim with ordinary apply semantics.

A BATS regression test rejects a global `Replace=true` and requires the
explicit `Replace=false` declaration.

## Prevention

- Keep sync options declarative in Git and forbid app-level `Replace=true` for
  the identity stack.
- Treat persistent resources as immutable: use ordinary apply for PVCs and
  StatefulSets, and make replacement an explicit, reviewed exception.
- Include a live-vs-Git Application spec check in post-merge verification so
  stale sync options are caught before the next retry loop.

## Related ESO drift

ESO-created resources can also receive server-defaulted fields that create
false drift under client-side comparison. ApplicationSets that manage ESO
resources should use Argo CD `ServerSideDiff=true` (with server-side apply)
consistently; this is a separate platform-level hardening item from the PVC
replacement failure fixed here.
