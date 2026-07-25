# Bug: reconcile hook builds `browser-with-conditional-otp` with a TOP-LEVEL conditional OTP subflow → all logins fail

**Repo:** shopping-cart-infra
**File:** `identity/keycloak/keycloak-reconcile-hook-job.yaml`
**Branch:** `fix/keycloak-browser-flow-drop-custom-otp-subflow` (create from `origin/main`)
**Discovered live 2026-07-25** on the laptop k3d Keycloak (`keycloak.3ai-talk.org`, realm `shopping-cart`).
**Classification:** Bugfix in `docs/bugs/`.
**Owner decision (2026-07-25): OPTION B — drop the custom role-based OTP subflow entirely.**

---

## Problem

Every shopping-cart login returned **"Invalid username or password"** regardless of the
credential used. Keycloak server log on each attempt:

```
WARN  DefaultAuthenticationFlow  REQUIRED and ALTERNATIVE elements at same level!
      Those alternative executions will be ignored: [auth-cookie, identity-provider-redirector, null]
WARN  KC-SERVICES0013: Failed authentication: org.keycloak.authentication.AuthenticationFlowException
WARN  events  type="LOGIN_ERROR" ... error="invalid_user_credentials" userId="null"
```

Federation was healthy the whole time — the bind credential binds as rootdn (rc=0), and the
log shows `Sync all users finished: 3 imported users`. The failure was **purely the browser
flow structure**.

**Root cause.** The reconcile hook copies the built-in `browser` flow to
`browser-with-conditional-otp` (which already carries a correctly-nested
`Browser - Conditional OTP` inside its `... forms` subflow), and then **adds a second,
role-based OTP subflow (`otp-conditional-subflow`) at the TOP level of the flow** and marks it
`CONDITIONAL`. In Keycloak a `CONDITIONAL` (or `REQUIRED`) execution at the top level makes the
processor **ignore every `ALTERNATIVE` sibling at that level** — including the
`browser-with-conditional-otp forms` subflow that holds the **Username Password Form**. With the
password form skipped, authentication throws `AuthenticationFlowException` and returns
`invalid_user_credentials` for all users.

Live flow as built by the hook (the bug is the top-level `otp-conditional-subflow`):

```
lvl=0 ALTERNATIVE  Cookie
lvl=0 DISABLED     Kerberos
lvl=0 ALTERNATIVE  Identity Provider Redirector
lvl=0 ALTERNATIVE  browser-with-conditional-otp forms         <- holds Username Password Form
lvl=1   REQUIRED     Username Password Form
lvl=1   CONDITIONAL  Browser - Conditional OTP (built-in, user-configured)
lvl=0 CONDITIONAL  otp-conditional-subflow                    <- BUG: top-level, forces alternatives to be ignored
lvl=1   (role condition + OTP form)
```

**Live remediation already applied (not durable):** the top-level `otp-conditional-subflow`
was set `requirement=DISABLED` via kcadm; a real PKCE login for `admin` then returned an auth
code. This spec makes the fix survive a rebuild.

---

## Decision — Option B (drop the custom subflow)

Role-based MFA is **not needed yet**, so the hook should stop building the custom
`otp-conditional-subflow` altogether. The copied `browser` flow already provides the built-in
`Browser - Conditional OTP` (OTP prompted only when a user has OTP configured), correctly nested
inside the `... forms` subflow — that is sufficient and safe. Removing the custom top-level
subflow makes the whole "REQUIRED/ALTERNATIVE at same level" fault structurally impossible.

`browser-with-conditional-otp` remains a plain copy of `browser` (kept as the activated flow
name so the `browserFlow=browser-with-conditional-otp` activation and any other references stay
valid). If role-gated MFA is wanted later, reintroduce it **nested inside the `... forms`
subflow**, never at the top level.

---

## Reproduction

1. Rebuild the hub (or delete + re-run the `keycloak-realm-reconcile` PostSync hook) so the
   hook recreates `browser-with-conditional-otp`.
2. Browse to the shopping-cart login, submit any valid LDAP user.
3. **Actual (before fix):** "Invalid username or password"; server log shows the
   REQUIRED/ALTERNATIVE warning + `AuthenticationFlowException`.
4. **Expected (after fix):** the Username Password Form validates the credential; login succeeds;
   no top-level CONDITIONAL/REQUIRED execution exists in `browser-with-conditional-otp`.

---

## Fix

### Change 1 — delete the entire custom OTP-subflow creation block

Remove the whole `otp-conditional-subflow` construction (the subflow create, its top-level
`CONDITIONAL` requirement flip, the `conditional-user-role` execution + `platform-mfa-role-condition`
config, and the `auth-otp-form` execution + its `REQUIRED` flip). Keep the `browser/copy` that
creates `browser-with-conditional-otp` and the "flow created" echo.

**Exact old block (lines 107–169):**

```bash
            /opt/keycloak/bin/kcadm.sh create "authentication/flows/browser/copy" \
              -r "${KC_REALM}" -s newName=browser-with-conditional-otp

            /opt/keycloak/bin/kcadm.sh create \
              "authentication/flows/browser-with-conditional-otp/executions/flow" \
              -r "${KC_REALM}" \
              -s alias=otp-conditional-subflow \
              -s type=basic-flow

            _otp_subflow_exec_id=$(
              /opt/keycloak/bin/kcadm.sh get \
                "authentication/flows/browser-with-conditional-otp/executions" \
                -r "${KC_REALM}" --fields id,displayName --format csv 2>/dev/null \
              | grep "otp-conditional-subflow" | cut -d',' -f1 | tr -d '"'
            )
            if [[ -z "${_otp_subflow_exec_id}" ]]; then
              echo "ERROR: could not resolve otp-conditional-subflow execution ID" >&2; exit 1
            fi
            /opt/keycloak/bin/kcadm.sh update \
              "authentication/flows/browser-with-conditional-otp/executions" \
              -r "${KC_REALM}" \
              -b "{\"id\":\"${_otp_subflow_exec_id}\",\"requirement\":\"CONDITIONAL\",\"authenticationFlow\":true,\"displayName\":\"otp-conditional-subflow\"}"

            /opt/keycloak/bin/kcadm.sh create \
              "authentication/flows/otp-conditional-subflow/executions/execution" \
              -r "${KC_REALM}" -s provider=conditional-user-role

            _role_cond_id=$(
              /opt/keycloak/bin/kcadm.sh get \
                "authentication/flows/otp-conditional-subflow/executions" \
                -r "${KC_REALM}" --fields id,providerId --format csv 2>/dev/null \
              | grep "conditional-user-role" | cut -d',' -f1 | tr -d '"'
            )
            if [[ -z "${_role_cond_id}" ]]; then
              echo "ERROR: could not resolve conditional-user-role execution ID" >&2; exit 1
            fi
            /opt/keycloak/bin/kcadm.sh create \
              "authentication/executions/${_role_cond_id}/config" \
              -r "${KC_REALM}" \
              -s alias=platform-mfa-role-condition \
              -s 'config={"conditionRoleAlias":"platform-mfa","negate":"false"}'
            /opt/keycloak/bin/kcadm.sh update \
              "authentication/executions/${_role_cond_id}" \
              -r "${KC_REALM}" -s requirement=REQUIRED

            /opt/keycloak/bin/kcadm.sh create \
              "authentication/flows/otp-conditional-subflow/executions/execution" \
              -r "${KC_REALM}" -s provider=auth-otp-form

            _otp_form_id=$(
              /opt/keycloak/bin/kcadm.sh get \
                "authentication/flows/otp-conditional-subflow/executions" \
                -r "${KC_REALM}" --fields id,providerId --format csv 2>/dev/null \
              | grep "auth-otp-form" | cut -d',' -f1 | tr -d '"'
            )
            if [[ -z "${_otp_form_id}" ]]; then
              echo "ERROR: could not resolve auth-otp-form execution ID" >&2; exit 1
            fi
            /opt/keycloak/bin/kcadm.sh update \
              "authentication/executions/${_otp_form_id}" \
              -r "${KC_REALM}" -s requirement=REQUIRED

            echo "browser-with-conditional-otp flow created"
```

**Exact new block:**

```bash
            /opt/keycloak/bin/kcadm.sh create "authentication/flows/browser/copy" \
              -r "${KC_REALM}" -s newName=browser-with-conditional-otp

            echo "browser-with-conditional-otp flow created"
```

Everything above line 107 (the `if grep -q browser-with-conditional-otp … skipping creation`
guard, the `else`, the `echo "Creating…"`) and everything from line 170 onward (the `fi`, the
`browserFlow=browser-with-conditional-otp` activation, the LDAP `ldap_id` block) is **unchanged**.

---

## Files Changed

| File | Change |
|------|--------|
| `identity/keycloak/keycloak-reconcile-hook-job.yaml` | Delete the custom `otp-conditional-subflow` creation (role-based MFA); `browser-with-conditional-otp` stays a plain copy of `browser` with the built-in conditional OTP |

---

## Rules

- The embedded script is a YAML block scalar (heredoc-style). **Preserve indentation exactly** —
  every kept line keeps its current leading whitespace. Verify by extracting the script and
  running `bash -n` on it.
- No other file touched.
- No new top-level executions of any kind are added to `browser-with-conditional-otp`.

---

## Definition of Done

- [ ] The custom `otp-conditional-subflow` creation block is fully removed; the only kcadm calls
      left in the creation branch are the `browser/copy` and the `echo`
- [ ] `grep -c 'otp-conditional-subflow' identity/keycloak/keycloak-reconcile-hook-job.yaml` → **0**
- [ ] `grep -c 'platform-mfa-role-condition' identity/keycloak/keycloak-reconcile-hook-job.yaml` → **0**
- [ ] Extracted script passes `bash -n`
- [ ] A rebuilt realm yields a `browser-with-conditional-otp` flow with only `ALTERNATIVE` +
      `DISABLED` executions at level 0 (no top-level `CONDITIONAL`/`REQUIRED`) — **Claude verifies live**
- [ ] A real login (`admin`/`Shopping1!`) returns an auth code — **Claude verifies live**
- [ ] Committed and pushed; memory-bank updated with the commit SHA in a separate commit

**Commit message (exact):**
```
fix(keycloak): drop top-level role-based OTP subflow so browser login flow is valid
```

---

## What NOT to Do

- Do NOT re-add the custom OTP subflow at the top level — that is the bug.
- Do NOT add any top-level `CONDITIONAL`/`REQUIRED` execution to `browser-with-conditional-otp`.
- Do NOT remove the `browser/copy` or the `browserFlow=browser-with-conditional-otp` activation —
  the flow name must keep existing.
- Do NOT touch the LDAP `ldap_id` block or any other part of the hook.
- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than `identity/keycloak/keycloak-reconcile-hook-job.yaml`.
- Do NOT commit to `main` — use the feature branch.

---

## Claude-only (do NOT delegate)

Live verification is Claude's step: after the hook change, rebuild/re-run the reconcile hook,
dump the `browser-with-conditional-otp` executions, confirm level 0 has only ALTERNATIVE +
DISABLED (and no `otp-conditional-subflow`), and drive a real PKCE login to an auth code. The
live cluster currently carries the manual DISABLE remediation on the OLD top-level subflow; a
clean rebuild replaces the whole flow with the plain copy.

**Note:** Option B has NO pre-handoff live-verify blocker — the Option-A kcadm "space in the
`... forms` subflow path" concern does not apply here because nothing is nested.
