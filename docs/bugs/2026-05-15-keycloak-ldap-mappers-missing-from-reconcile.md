# Bug: LDAP attribute mappers missing after realm reconcile

**Status:** Live-patched 2026-05-15; permanent fix pending  
**Branch:** `bug/keycloak-ldap-mappers-missing`  
**Affects:** `identity/keycloak/keycloak-reconcile-hook-job.yaml`, `identity/keycloak/realm-shopping-cart.json`

---

## Symptom

```
LOGIN_ERROR … error="user_not_found", username="admin@shopping-cart.local"

User returned from LDAP has null username! Mapped username LDAP attribute: uid,
user DN: uid=developer,ou=users,dc=shopping-cart,dc=local, attributes from LDAP: {}
Sync all users finished: 0 imported users, 0 updated users, 3 users failed sync!
```

SSO page loads but every login fails with `user_not_found`.

---

## Root cause

`keycloak-reconcile-hook-job.yaml` runs `kcadm.sh create partialImport` from
`realm-shopping-cart.json`. The `partialImport` API creates the top-level LDAP
`UserStorageProvider` component, but **does not create nested mapper
sub-components**. Without mappers:

- Keycloak has no definition of which LDAP attribute maps to `username`, `email`,
  `firstName`, `lastName`.
- The LDAP sync finds users by DN but returns `attributes from LDAP: {}`.
- Every login attempt results in `user_not_found`.

The LDAP bind credential and LDAP service are both correct — the bug is purely
in missing Keycloak-side mapper configuration.

**Also found:** `kcadm.sh create components … -s 'config.prop=["val"]'` fails
with `[unknown_error]` inside a `kubectl exec` heredoc due to quoting.
Use `-f <json-file>` instead.

---

## Live patch applied 2026-05-15

6 mapper components created via `kcadm.sh create components -f mapper.json` in
the running Keycloak pod. LDAP sync immediately imported 3 users:

```
Sync all users finished: 3 imported users, 0 updated users
```

Mappers created:
| name          | providerId                 | ldap.attribute  | user.model.attribute |
|---------------|----------------------------|-----------------|----------------------|
| username      | user-attribute-ldap-mapper | uid             | username             |
| email         | user-attribute-ldap-mapper | mail            | email                |
| first name    | user-attribute-ldap-mapper | givenName       | firstName            |
| last name     | user-attribute-ldap-mapper | sn              | lastName             |
| creation date | user-attribute-ldap-mapper | createTimestamp | createTimestamp      |
| modify date   | user-attribute-ldap-mapper | modifyTimestamp | modifyTimestamp      |

---

## Permanent fix required

### File 1: `identity/keycloak/keycloak-reconcile-hook-job.yaml`

After the existing `kcadm.sh create partialImport` call (line ~92), add a
mapper-creation step. Use `-f <json-file>` pattern (not `-s config.prop=[...]`).
The step must be idempotent — check if each mapper already exists before creating.

Pseudocode to add after the `partialImport` block:

```bash
# Get LDAP component ID
LDAP_ID=$(/opt/keycloak/bin/kcadm.sh get components -r "${KC_REALM}" \
  --fields id,providerId 2>/dev/null \
  | python3 -c "
import sys,json
comps=json.load(sys.stdin)
match=[c['id'] for c in comps if c.get('providerId')=='ldap']
print(match[0] if match else '')
")

if [ -z "${LDAP_ID}" ]; then
  echo "No LDAP component found; skipping mapper setup"
else
  PT="org.keycloak.storage.ldap.mappers.LDAPStorageMapper"

  create_mapper_if_missing() {
    local name="$1" json="$2"
    existing=$(/opt/keycloak/bin/kcadm.sh get components -r "${KC_REALM}" \
      --fields name 2>/dev/null | grep -c "\"name\" : \"${name}\"" || true)
    [ "${existing}" -gt 0 ] && return 0
    local f; f=$(mktemp /tmp/mapper-XXXXXX.json)
    printf '%s' "${json}" > "${f}"
    /opt/keycloak/bin/kcadm.sh create components -r "${KC_REALM}" -f "${f}"
    rm -f "${f}"
    echo "Created LDAP mapper: ${name}"
  }

  create_mapper_if_missing "username" \
    "{\"parentId\":\"${LDAP_ID}\",\"providerType\":\"${PT}\",\"providerId\":\"user-attribute-ldap-mapper\",\"name\":\"username\",\"config\":{\"ldap.attribute\":[\"uid\"],\"user.model.attribute\":[\"username\"],\"read.only\":[\"true\"],\"always.read.value.from.ldap\":[\"false\"],\"is.mandatory.in.ldap\":[\"true\"]}}"

  create_mapper_if_missing "email" \
    "{\"parentId\":\"${LDAP_ID}\",\"providerType\":\"${PT}\",\"providerId\":\"user-attribute-ldap-mapper\",\"name\":\"email\",\"config\":{\"ldap.attribute\":[\"mail\"],\"user.model.attribute\":[\"email\"],\"read.only\":[\"true\"],\"always.read.value.from.ldap\":[\"false\"],\"is.mandatory.in.ldap\":[\"false\"]}}"

  create_mapper_if_missing "first name" \
    "{\"parentId\":\"${LDAP_ID}\",\"providerType\":\"${PT}\",\"providerId\":\"user-attribute-ldap-mapper\",\"name\":\"first name\",\"config\":{\"ldap.attribute\":[\"givenName\"],\"user.model.attribute\":[\"firstName\"],\"read.only\":[\"true\"],\"always.read.value.from.ldap\":[\"true\"],\"is.mandatory.in.ldap\":[\"true\"]}}"

  create_mapper_if_missing "last name" \
    "{\"parentId\":\"${LDAP_ID}\",\"providerType\":\"${PT}\",\"providerId\":\"user-attribute-ldap-mapper\",\"name\":\"last name\",\"config\":{\"ldap.attribute\":[\"sn\"],\"user.model.attribute\":[\"lastName\"],\"read.only\":[\"true\"],\"always.read.value.from.ldap\":[\"true\"],\"is.mandatory.in.ldap\":[\"true\"]}}"

  create_mapper_if_missing "creation date" \
    "{\"parentId\":\"${LDAP_ID}\",\"providerType\":\"${PT}\",\"providerId\":\"user-attribute-ldap-mapper\",\"name\":\"creation date\",\"config\":{\"ldap.attribute\":[\"createTimestamp\"],\"user.model.attribute\":[\"createTimestamp\"],\"read.only\":[\"true\"],\"always.read.value.from.ldap\":[\"true\"],\"is.mandatory.in.ldap\":[\"false\"]}}"

  create_mapper_if_missing "modify date" \
    "{\"parentId\":\"${LDAP_ID}\",\"providerType\":\"${PT}\",\"providerId\":\"user-attribute-ldap-mapper\",\"name\":\"modify date\",\"config\":{\"ldap.attribute\":[\"modifyTimestamp\"],\"user.model.attribute\":[\"modifyTimestamp\"],\"read.only\":[\"true\"],\"always.read.value.from.ldap\":[\"true\"],\"is.mandatory.in.ldap\":[\"false\"]}}"

  # Trigger sync after mapper setup
  /opt/keycloak/bin/kcadm.sh create \
    "user-storage/${LDAP_ID}/sync?action=triggerFullSync" \
    -r "${KC_REALM}"
fi
```

The hook already has python3 available (via the Keycloak image). If not,
replace the python3 call with a `jq` approach or a simple grep/awk.

### File 2: `identity/keycloak/realm-shopping-cart.json`

Add nested `components` inside the LDAP UserStorageProvider entry so that
any future version of Keycloak that supports nested partialImport also gets
the mappers:

```json
"components": {
  "org.keycloak.storage.UserStorageProvider": [
    {
      "name": "ldap",
      "providerId": "ldap",
      "config": { ... existing config unchanged ... },
      "components": {
        "org.keycloak.storage.ldap.mappers.LDAPStorageMapper": [
          {"name":"username","providerId":"user-attribute-ldap-mapper","config":{"ldap.attribute":["uid"],"user.model.attribute":["username"],"read.only":["true"],"always.read.value.from.ldap":["false"],"is.mandatory.in.ldap":["true"]}},
          {"name":"email","providerId":"user-attribute-ldap-mapper","config":{"ldap.attribute":["mail"],"user.model.attribute":["email"],"read.only":["true"],"always.read.value.from.ldap":["false"],"is.mandatory.in.ldap":["false"]}},
          {"name":"first name","providerId":"user-attribute-ldap-mapper","config":{"ldap.attribute":["givenName"],"user.model.attribute":["firstName"],"read.only":["true"],"always.read.value.from.ldap":["true"],"is.mandatory.in.ldap":["true"]}},
          {"name":"last name","providerId":"user-attribute-ldap-mapper","config":{"ldap.attribute":["sn"],"user.model.attribute":["lastName"],"read.only":["true"],"always.read.value.from.ldap":["true"],"is.mandatory.in.ldap":["true"]}},
          {"name":"creation date","providerId":"user-attribute-ldap-mapper","config":{"ldap.attribute":["createTimestamp"],"user.model.attribute":["createTimestamp"],"read.only":["true"],"always.read.value.from.ldap":["true"],"is.mandatory.in.ldap":["false"]}},
          {"name":"modify date","providerId":"user-attribute-ldap-mapper","config":{"ldap.attribute":["modifyTimestamp"],"user.model.attribute":["modifyTimestamp"],"read.only":["true"],"always.read.value.from.ldap":["true"],"is.mandatory.in.ldap":["false"]}}
        ]
      }
    }
  ]
}
```

---

## Testing

After applying:
1. Run `make up` (or ArgoCD sync) — hook job must complete without error
2. Confirm `Sync all users finished: 3 imported users` in Keycloak logs
3. Log in as `admin` / `developer` / `operator` via the SSO page
4. Confirm no `user_not_found` in Keycloak logs

---

## Definition of Done

- [ ] `keycloak-reconcile-hook-job.yaml` creates all 6 mappers idempotently
- [ ] `realm-shopping-cart.json` includes nested mapper components
- [ ] LDAP sync succeeds on a fresh cluster without manual intervention
- [ ] PR created on branch `bug/keycloak-ldap-mappers-missing`
- [ ] Copilot reviewer tagged after PR creation
- [ ] Branch pushed before reporting done
