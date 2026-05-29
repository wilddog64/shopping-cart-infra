# Copilot PR #71 Review Findings

**PR:** #71 feat(keycloak): role-based TOTP MFA for platform-admin and platform-developer
**Fix commit:** d7b82e3

---

## Finding 1 — browserFlow only set inside `else` branch (partial-failure gap)

**File:** `identity/keycloak/keycloak-reconcile-hook-job.yaml` line 103

**What Copilot flagged:** The idempotency guard skips everything (including `browserFlow` update) when the flow already exists. A partial failure on a prior run (flow created, `browserFlow` update failed, or external change) leaves the realm on the wrong flow permanently.

**Fix:** Moved `kcadm.sh update realms/${KC_REALM} -s browserFlow=browser-with-conditional-otp` outside the `if/else` block so it runs unconditionally — flow creation is still guarded, but realm binding is always enforced.

**Before:**
```bash
if flow_exists; then
  echo "skipping"
else
  # create flow ...
  kcadm.sh update realms/${KC_REALM} -s browserFlow=browser-with-conditional-otp
fi
```

**After:**
```bash
if flow_exists; then
  echo "skipping creation"
else
  # create flow ...
fi
kcadm.sh update realms/${KC_REALM} -s browserFlow=browser-with-conditional-otp
```

---

## Finding 2 — `_otp_subflow_exec_id` unguarded extraction (line 121)

**File:** `identity/keycloak/keycloak-reconcile-hook-job.yaml` line 121

**What Copilot flagged:** ID extraction via `grep | cut | tr` inside command substitution with no guard. Under `set -euo pipefail`, no-match produces an empty string passed silently to the next `kcadm.sh update` call (wrong endpoint, cryptic failure).

**Fix:** Added guard immediately after extraction:
```bash
if [[ -z "${_otp_subflow_exec_id}" ]]; then
  echo "ERROR: could not resolve otp-conditional-subflow execution ID" >&2; exit 1
fi
```

---

## Finding 3 — `_role_cond_id` unguarded extraction (line 135)

**File:** `identity/keycloak/keycloak-reconcile-hook-job.yaml` line 135

**What Copilot flagged:** Same pattern as Finding 2 for `_role_cond_id`.

**Fix:**
```bash
if [[ -z "${_role_cond_id}" ]]; then
  echo "ERROR: could not resolve conditional-user-role execution ID" >&2; exit 1
fi
```

---

## Finding 4 — `_otp_form_id` unguarded extraction (line 154)

**File:** `identity/keycloak/keycloak-reconcile-hook-job.yaml` line 154

**What Copilot flagged:** Same pattern as Findings 2–3 for `_otp_form_id`.

**Fix:**
```bash
if [[ -z "${_otp_form_id}" ]]; then
  echo "ERROR: could not resolve auth-otp-form execution ID" >&2; exit 1
fi
```

---

## Root cause

All four issues stem from the same spec gap: the original spec provided the exact kcadm.sh commands but did not require explicit ID validation guards or specify that `browserFlow` enforcement must survive a partial-failure re-run.

## Process note

Add to spec template (`## Rules` section): "Every command-substitution ID extraction must include an empty-check guard with an explicit error message. Any idempotency guard that skips a block must not skip unconditional state enforcement (e.g. realm binding) that should survive partial failures."
