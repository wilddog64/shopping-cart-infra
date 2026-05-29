# Bugfix: reconcile hook fails — python3 not found in Keycloak container

**Branch:** `shopping-cart-infra-v0.5.1`
**File:** `identity/keycloak/keycloak-reconcile-hook-job.yaml`

---

## Problem

The `keycloak-realm-reconcile` Job fails immediately after `partialImport` with:

```
/bin/bash: line 66: python3: command not found
```

`quay.io/keycloak/keycloak:24.0` is based on ubi9-minimal, which does not ship
Python. Two `python3 -c` one-liners were introduced in a prior fix to parse JSON
from `kcadm.sh` output. They fail at runtime, so `ldap_id` is never set and no
LDAP mappers are created.

**Root cause:** `python3` is not available in the Keycloak container image; both
JSON-parsing calls must be replaced with `kcadm.sh -q` server-side query
parameters + `grep`/`sed`, which are always present.

---

## Reproduction

```bash
kubectl logs -n identity -l job-name=keycloak-realm-reconcile --tail=10
# shows: /bin/bash: line 66: python3: command not found

kubectl exec -n identity deploy/keycloak -- \
  /opt/keycloak/bin/kcadm.sh get components \
  -r shopping-cart --fields name,providerId 2>/dev/null \
  | grep user-attribute-ldap-mapper
# shows nothing — no mappers exist
```

---

## Fix

Replace both `python3` blocks with pure `kcadm.sh`/`grep`/`sed`.

### Change 1 — lines 96–102: replace `ldap_id` fetch

**Old:**
```bash
          ldap_id="$(
            /opt/keycloak/bin/kcadm.sh get components \
              -r "${KC_REALM}" \
              --fields id,name,parentId,providerId \
              2>/dev/null \
            | python3 -c 'import json,sys; comps=json.load(sys.stdin); print(next((comp.get("id", "") for comp in comps if comp.get("providerId") == "ldap"), ""))'
          )"
```

**New:**
```bash
          ldap_id="$(
            /opt/keycloak/bin/kcadm.sh get components \
              -r "${KC_REALM}" \
              -q type=org.keycloak.storage.UserStorageProvider \
              --fields id \
              2>/dev/null \
            | grep '"id"' | head -1 \
            | sed 's/.*"id" : "\([^"]*\)".*/\1/'
          )"
```

The `-q type=` filter is a server-side query parameter on the Keycloak components
API — it returns only UserStorageProvider components (the LDAP provider), so no
client-side JSON parsing is needed.

### Change 2 — lines 113–125: replace `existing` check; remove `current_components_json`

**Old (lines 113–125):**
```bash
              local current_components_json existing mapper_file

              current_components_json="$(
                /opt/keycloak/bin/kcadm.sh get components \
                  -r "${KC_REALM}" \
                  --fields id,name,parentId,providerId \
                  2>/dev/null || true
              )"
              existing="$(
                printf '%s' "${current_components_json}" \
                  | python3 -c 'import json,sys; name=sys.argv[1]; parent_id=sys.argv[2]; comps=json.load(sys.stdin); print(sum(1 for comp in comps if comp.get("name") == name and comp.get("parentId") == parent_id and comp.get("providerId") == "user-attribute-ldap-mapper"))' \
                  "${name}" "${ldap_id}"
              )"
```

**New:**
```bash
              local existing mapper_file

              existing="$(
                /opt/keycloak/bin/kcadm.sh get components \
                  -r "${KC_REALM}" \
                  -q parent="${ldap_id}" \
                  -q type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
                  -q name="${name}" \
                  --fields id \
                  2>/dev/null \
                | grep -c '"id"' || echo 0
              )"
```

The three `-q` flags (`parent`, `type`, `name`) filter server-side, returning only
mappers matching all three criteria. `grep -c '"id"'` counts the results. No local
JSON parsing or intermediate variable needed.

---

## Files Changed

| File | Change |
|------|--------|
| `identity/keycloak/keycloak-reconcile-hook-job.yaml` | Replace both `python3` blocks with `kcadm.sh -q` + `grep`/`sed` |

---

## Rules

- No other files touched
- After editing, verify shellcheck passes:
  ```bash
  # Extract the script block and check it (no cluster required)
  grep -A200 'command: \["/bin/bash"' identity/keycloak/keycloak-reconcile-hook-job.yaml \
    | grep -B200 'envFrom:' | head -n -1 > /tmp/hook-script.sh
  shellcheck -S warning /tmp/hook-script.sh || true
  ```

---

## Definition of Done

- [ ] `python3` no longer appears in `keycloak-reconcile-hook-job.yaml`
- [ ] `ldap_id` fetch uses `-q type=org.keycloak.storage.UserStorageProvider`
- [ ] `existing` check uses `-q parent=`, `-q type=`, `-q name=` server-side filters
- [ ] `current_components_json` local variable removed
- [ ] Committed and pushed to `shopping-cart-infra-v0.5.1`
- [ ] Commit SHA verified on `origin/shopping-cart-infra-v0.5.1`

**Commit message (exact):**
```
fix(keycloak): replace python3 with kcadm.sh server-side queries in reconcile hook
```

---

## What NOT to Do

- Do NOT install python3 in the container — fix the script instead
- Do NOT create a PR — this branch will get its own PR later
- Do NOT skip pre-commit hooks — use `PRE_COMMIT_ALLOW_NO_CONFIG=1 git commit`
- Do NOT commit to `main` — work on `shopping-cart-infra-v0.5.1`

---

## Manual Verification (after push, on live cluster)

After Codex pushes, trigger the hook manually to confirm:

```bash
# Delete failed job and re-apply from the updated branch
kubectl delete job -n identity keycloak-realm-reconcile 2>/dev/null || true
# ArgoCD sync will re-apply the job; or apply directly:
kubectl apply -f identity/keycloak/keycloak-reconcile-hook-job.yaml

# Wait ~30s then check:
kubectl logs -n identity -l job-name=keycloak-realm-reconcile --tail=20
# Should show: "Created LDAP mapper: username", ... "Created LDAP mapper: modify date"

kubectl exec -n identity deploy/keycloak -- \
  /opt/keycloak/bin/kcadm.sh get components \
  -r shopping-cart --fields name,providerId 2>/dev/null \
  | grep user-attribute-ldap-mapper
# Should show 6 lines
```
