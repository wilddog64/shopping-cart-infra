# Keycloak LDAP username attribute should resolve from `uid`

## What was tested

- Re-reviewed the live Keycloak login failure after the LDAP bind DN fix.
- Checked the current shopping-cart realm export and LDAP bootstrap data.
- Reviewed the Copilot diagnosis on the Keycloak pod.

## Actual output

```text
User returned from LDAP has null username!
Mapped username LDAP attribute: mail
attributes from LDAP: {}
```

```text
Key (name)=(shopping-cart) already exists.
```

## Root cause

The realm export and Keycloak LDAP ConfigMap were still resolving usernames from `mail`.
That path is not stable for the live directory data that exists in the bootstrap LDIF, while every user entry already has a deterministic `uid`.

## Fix

- Change `LDAP_USERNAME_ATTRIBUTE` in `identity/keycloak/configmap.yaml` to `uid`.
- Change `usernameLDAPAttribute` in `identity/keycloak/realm-shopping-cart.json` to `uid`.

## Follow-up

- Re-sync Keycloak after the branch merges so the live realm import and LDAP federation use the same identifier source as the bootstrap LDIF.
