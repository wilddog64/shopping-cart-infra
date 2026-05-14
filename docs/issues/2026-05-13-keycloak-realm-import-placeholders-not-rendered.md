# Keycloak realm import should render only client secrets

## What was tested

- Reviewed the live Keycloak pod logs after the repeated SSO failure.
- Confirmed the Keycloak init/startup path imports the realm JSON from `identity/keycloak/realm-shopping-cart.json`.
- Rechecked the rendered realm path and verified the LDAP bind DN is now a literal value while the bind credential remains templated from Secret data.

## Actual output

```text
2026-05-13 23:03:23,398 INFO  [org.keycloak.storage.ldap.LDAPIdentityStoreRegistry] (executor-thread-4) Creating new LDAP Store for the LDAP storage provider: 'ldap', LDAP Configuration: {pagination=[true], fullSyncPeriod=[604800], searchScope=[2], useTruststoreSpi=[ldapsOnly], connectionPooling=[true], usersDn=[ou=users,dc=shopping-cart,dc=local], cachePolicy=[DEFAULT], trustEmail=[true], priority=[0], userObjectClasses=[inetOrgPerson, organizationalPerson], enabled=[true], changedSyncPeriod=[86400], usernameLDAPAttribute=[uid], bindDn=[cn=admin,dc=shopping-cart,dc=local], rdnLDAPAttribute=[uid], vendor=[other], editMode=[READ_ONLY], uuidLDAPAttribute=[entryUUID], connectionUrl=[ldap://ldap.identity.svc.cluster.local:389], validatePasswordPolicy=[false], syncRegistrations=[false], authType=[simple], batchSizeForSync=[1000]}, binaryAttributes: []
```

## Root cause

The Keycloak startup import path was feeding the realm JSON into `kc.sh import` without rendering the bind credential first. The bind DN is safe to keep literal in the source template, so only the secret value needs substitution at import time.

## Fix

- Render the realm JSON inside the Keycloak initContainer before running `kc.sh import`.
- Expand the client secrets and LDAP bind credential from the environment populated by the ConfigMap and ExternalSecret.
- Keep `identity/keycloak/realm-shopping-cart.json` as the single source template and do not import a second copy.

## Follow-up

- Rebuild the identity stack after the branch merges.
- Verify the live Keycloak logs show a concrete LDAP bind DN and no import-time placeholder drift.
- Retry the Argo CD SSO login after the import path is rendered.
