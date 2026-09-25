# Keycloak realm reconcile fails because `awk` is missing

**Filed:** 2026-09-25

## Evidence

The `keycloak-realm-reconcile` PostSync hook fails in `quay.io/keycloak/keycloak:24.0`. Its log ends with:

```text
Logging into http://keycloak.identity.svc.cluster.local as user admin of realm master
Realm shopping-cart exists; applying partial import
browser-with-conditional-otp flow already exists; reconciling it
environment: line 104: awk: command not found
```

The preceding `grep` succeeds, so reconciliation reaches the first CSV parsing call before the hook exits. The failed Job exhausts its `backoffLimit`, leaving `shopping-cart-identity` OutOfSync until the hook can complete.

## Cause

The hook runs in `quay.io/keycloak/keycloak:24.0`, based on `ubi9-micro`. That image provides the shell utilities used by the hook, but does not include `awk`. The embedded reconcile script used `awk` for CSV field extraction, row filtering, counting, and URL encoding.

The hook now performs those operations with pure Bash helpers and keeps the Keycloak image and all `kcadm.sh` calls unchanged. This avoids package installation or network access in the non-root hook container.
