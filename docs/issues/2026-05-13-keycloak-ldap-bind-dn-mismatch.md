# Keycloak LDAP bind DN mismatch

## Problem
The live Keycloak login path is reaching LDAP, but the bind account configured in Keycloak does not match the live LDAP admin identity.

## Evidence
The current Keycloak config still pointed at:

- `LDAP_BIND_DN: cn=admin,dc=shopping-cart,dc=local`

The running LDAP admin secret exposed a different account name:

- `ldap-admin`

Keycloak login failures were surfacing as LDAP user resolution problems:

- `User returned from LDAP has null username!`
- `Mapped username LDAP attribute: mail`
- `attributes from LDAP: {}`

## Fix
Update Keycloak's LDAP bind DN to the live admin account name:

- `cn=ldap-admin,dc=shopping-cart,dc=local`

Keep the realm export aligned with the same value so future imports do not drift.

## Superseded
This diagnosis was superseded by the later realm startup import flow that re-applies the JSON source of truth on Keycloak pod start. The current branch restores the canonical OpenLDAP root DN `admin`, so the live realm should be refreshed from `identity/config/realm-shopping-cart.json` instead of relying on a one-off live drift.

## Follow-up
After this change is merged, reapply the identity stack and retry the Argo CD SSO login.
