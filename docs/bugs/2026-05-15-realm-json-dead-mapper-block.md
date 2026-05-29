# Bugfix: realm-shopping-cart.json — dead LDAP mapper block + kubectl apply -k doc error

**Branch:** `bug/keycloak-ldap-mappers-missing`
**Files:** `identity/keycloak/realm-shopping-cart.json`, `docs/bugs/2026-05-15-argocd-virtualservice-missing.md`

---

## Problem

`realm-shopping-cart.json` contains a `"components"` block nested inside the LDAP
`UserStorageProvider` entry (lines 421–551). This block is unreachable: Keycloak's
`partialImport` endpoint does not import `UserStorageProvider` components, and even if
it did, the nested `"components"` key is not a valid Keycloak realm-export field (the
correct field is top-level `components` with `parentId` references). The block was added
in commit `d3d4597` as part of Bug 1 but will be silently ignored on every cluster
rebuild. The reconcile-hook script (`create_mapper_if_missing`) is the correct and sole
mechanism for creating LDAP mappers.

Additionally, the ArgoCD routing bug doc (`2026-05-15-argocd-virtualservice-missing.md`)
uses `kubectl apply -k networking/istio/` in its testing section. `kustomization.yaml`
was removed from that path in commit `aa41928`, so `-k` will fail.

**Root cause (JSON):** `partialImport` does not process `UserStorageProvider` components;
nested `"components"` inside a provider entry is not a Keycloak-recognized field in any
import path.

**Root cause (doc):** The testing command was written before `kustomization.yaml` was
deleted and was not updated.

---

## Reproduction

JSON:
```bash
# Applies on every cluster rebuild — mappers will not be created by partialImport
kcadm.sh create partialImport -r shopping-cart -s ifResourceExists=OVERWRITE \
  -f realm-shopping-cart.json
# Verify: mappers are absent after fresh import (reconcile-hook script fixes them later)
```

Doc:
```bash
kubectl apply -k networking/istio/
# Error: unable to find one of 'kustomization.yaml', 'kustomization.yml' ...
```

---

## Fix

### Change 1 — `identity/keycloak/realm-shopping-cart.json`: remove dead `"components"` block

Remove lines 421–551. Line 421 currently closes the `config` object with a trailing
comma (`,`) because `"components"` follows it. After deletion, the comma must also go
— the `config` close brace becomes the last key in the provider object.

**Old (lines 421–551):**
```json
        },
        "components": {
          "org.keycloak.storage.ldap.mappers.LDAPStorageMapper": [
            {
              "name": "username",
              "providerId": "user-attribute-ldap-mapper",
              "config": {
                "ldap.attribute": ["uid"],
                "user.model.attribute": ["username"],
                "read.only": ["true"],
                "always.read.value.from.ldap": ["false"],
                "is.mandatory.in.ldap": ["true"]
              }
            },
            {
              "name": "email",
              "providerId": "user-attribute-ldap-mapper",
              "config": {
                "ldap.attribute": ["mail"],
                "user.model.attribute": ["email"],
                "read.only": ["true"],
                "always.read.value.from.ldap": ["false"],
                "is.mandatory.in.ldap": ["false"]
              }
            },
            {
              "name": "first name",
              "providerId": "user-attribute-ldap-mapper",
              "config": {
                "ldap.attribute": ["givenName"],
                "user.model.attribute": ["firstName"],
                "read.only": ["true"],
                "always.read.value.from.ldap": ["true"],
                "is.mandatory.in.ldap": ["true"]
              }
            },
            {
              "name": "last name",
              "providerId": "user-attribute-ldap-mapper",
              "config": {
                "ldap.attribute": ["sn"],
                "user.model.attribute": ["lastName"],
                "read.only": ["true"],
                "always.read.value.from.ldap": ["true"],
                "is.mandatory.in.ldap": ["true"]
              }
            },
            {
              "name": "creation date",
              "providerId": "user-attribute-ldap-mapper",
              "config": {
                "ldap.attribute": ["createTimestamp"],
                "user.model.attribute": ["createTimestamp"],
                "read.only": ["true"],
                "always.read.value.from.ldap": ["true"],
                "is.mandatory.in.ldap": ["false"]
              }
            },
            {
              "name": "modify date",
              "providerId": "user-attribute-ldap-mapper",
              "config": {
                "ldap.attribute": ["modifyTimestamp"],
                "user.model.attribute": ["modifyTimestamp"],
                "read.only": ["true"],
                "always.read.value.from.ldap": ["true"],
                "is.mandatory.in.ldap": ["false"]
              }
            }
          ]
        }
```

**New (line 421 only — the trailing comma is removed):**
```json
        }
```

The LDAP provider object then closes cleanly:
```
        }       ← config close, no comma (last key in provider object)
      }         ← LDAP provider object close
    ]           ← UserStorageProvider array close
  },            ← top-level components close
```

Verify the resulting JSON parses:
```bash
python3 -m json.tool identity/keycloak/realm-shopping-cart.json > /dev/null && echo OK
```

### Change 2 — `docs/bugs/2026-05-15-argocd-virtualservice-missing.md` line 224: fix apply command

**Old:**
```
1. `kubectl apply -k networking/istio/` (or ArgoCD sync)
```

**New:**
```
1. `kubectl apply -f networking/istio/` (or ArgoCD sync)
```

---

## Files Changed

| File | Change |
|------|--------|
| `identity/keycloak/realm-shopping-cart.json` | Remove lines 421–551 (dead `"components"` block) and trailing comma on line 421 |
| `docs/bugs/2026-05-15-argocd-virtualservice-missing.md` | Line 224: `-k` → `-f` |

---

## Rules

- JSON must parse after the edit: `python3 -m json.tool identity/keycloak/realm-shopping-cart.json > /dev/null`
- No other files touched

---

## Definition of Done

- [ ] `identity/keycloak/realm-shopping-cart.json` lines 421–551 removed; trailing comma on line 421 removed; JSON parses cleanly
- [ ] `docs/bugs/2026-05-15-argocd-virtualservice-missing.md` line 224 updated from `-k` to `-f`
- [ ] Committed and pushed to `bug/keycloak-ldap-mappers-missing`
- [ ] Commit SHA verified on `origin/bug/keycloak-ldap-mappers-missing` via `git log origin/bug/keycloak-ldap-mappers-missing --oneline -3`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(keycloak): remove dead realm JSON mapper block; fix apply-k doc error
```

---

## What NOT to Do

- Do NOT create a PR (PR #55 is already open)
- Do NOT skip pre-commit hooks — use `PRE_COMMIT_ALLOW_NO_CONFIG=1` if the hook fires with no config file
- Do NOT modify any file other than the two listed above
- Do NOT commit to `main` — work on `bug/keycloak-ldap-mappers-missing`
- Do NOT rewrite the reconcile hook — it is correct as-is
