# Keycloak reconcile hook treats a transient flow 404 as a permanent failure

**Filed:** 2026-09-29

## Symptom

The `KubeJobFailed` alert repeatedly fired for the hub because the
`shopping-cart-identity` PostSync Job `identity/keycloak-reconcile` failed:

```text
Logging into http://keycloak.identity.svc.cluster.local as user admin of realm master
Realm shopping-cart exists; applying partial import
browser-with-conditional-otp flow already exists; reconciling it
Resource not found for url: http://keycloak.identity.svc.cluster.local/admin/realms/shopping-cart/authentication/flows/browser-with-conditional-otp/executions
```

The Job had `failed=2`, `succeeded=0`, and the alert started on
`2026-09-27T19:01:58Z`. Because the failed Job remained in the cluster,
`kube_job_failed > 0` stayed true and Alertmanager repeated notifications.

## Cause

The hook waited for the Keycloak service TCP port, but not for the Admin REST
API to become stable. A transient `404 Resource not found` from `kcadm.sh get`
was treated as fatal under `set -euo pipefail`. A later read-only query against
the same live flow succeeded and showed all expected executions, confirming the
failure was transient rather than a permanently missing flow.

## Fix

The hook now routes its reconciliation `kcadm.sh get` calls through
`kcadm_get_retry`. It retries recognized `Resource not found`/`HTTP 404`
responses twelve times with a five-second delay, while immediately preserving
non-404 failures and returning failure if the 404 persists.

The BATS render test guards the retry helper and its bounded behavior.

## Prevention

- Gate hooks on API readiness, not only an open service port.
- Treat eventual-consistency responses as retryable only for bounded, known
  transient errors; keep authentication and other API failures fatal.
- Keep the failed Job visible until investigation, then rerun the sync after
  the corrected hook is deployed; deleting the Job alone only silences the
  metric temporarily.
- Add post-merge verification that the PostSync Job completes and that the
  corresponding `KubeJobFailed` alert is absent.
