# Keycloak LDAP bind should use the canonical `admin` root DN

## What was tested

- Reviewed the live Keycloak pod diagnosis from Copilot.
- Rechecked the current shopping-cart identity manifests after the `ldap-admin` bind DN experiment.
- Confirmed the Keycloak and LDAP manifests still source the bind password from the shared Vault-backed `ldap/admin` path.

## Actual output

```text
**Root cause:** Keycloak is healthy; the failure is **LDAP authentication**. The log shows `javax.naming.AuthenticationException: [LDAP: error code 49 - Invalid Credentials]`, so Keycloak is binding to LDAP with a bad username/password (or a rotated secret that Keycloak hasn’t picked up).
```

## Root cause

The identity stack still rejects LDAP binds at runtime after the bind DN was changed to `cn=ldap-admin,dc=shopping-cart,dc=local`.
The safest repo-side fix is to restore the canonical OpenLDAP root account DN, `cn=admin,dc=shopping-cart,dc=local`, in both Keycloak and the LDAP deployment so the live directory and the manifests agree on the bind identity.

## Fix

- Change `LDAP_ADMIN_USERNAME` in `identity/ldap/deployment.yaml` back to `admin`.
- Change `LDAP_BIND_DN` in `identity/keycloak/configmap.yaml` back to `cn=admin,dc=shopping-cart,dc=local`.
- Change the realm import `bindDn` in `identity/config/realm-shopping-cart.json` back to `cn=admin,dc=shopping-cart,dc=local`.

## Follow-up

- Re-sync the identity stack after the branch merges and confirm the live `keycloak-secrets` ExternalSecret still sources `LDAP_BIND_CREDENTIAL` from `secret/data/ldap/admin`.
- Retry Argo CD SSO with the canonical shopping-cart login after the deployment refreshes.
