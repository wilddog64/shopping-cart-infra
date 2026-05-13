# Keycloak realm import did not render LDAP placeholders

## What was tested

- Reviewed the live Keycloak pod logs after the repeated SSO failure.
- Confirmed the Keycloak init/startup path imports `identity/config/realm-shopping-cart.json` directly from the shopping-cart-infra repo.
- Rechecked the raw realm JSON and found the LDAP federation section still contains placeholder values for the bind DN and bind credential.

## Actual output

```text
2026-05-13 23:03:23,398 INFO  [org.keycloak.storage.ldap.LDAPIdentityStoreRegistry] (executor-thread-4) Creating new LDAP Store for the LDAP storage provider: 'ldap', LDAP Configuration: {pagination=[true], fullSyncPeriod=[604800], searchScope=[2], useTruststoreSpi=[ldapsOnly], connectionPooling=[true], usersDn=[ou=users,dc=shopping-cart,dc=local], cachePolicy=[DEFAULT], trustEmail=[true], priority=[0], userObjectClasses=[inetOrgPerson, organizationalPerson], enabled=[true], changedSyncPeriod=[86400], usernameLDAPAttribute=[uid], bindDn=[${LDAP_BIND_DN}], rdnLDAPAttribute=[uid], vendor=[other], editMode=[READ_ONLY], uuidLDAPAttribute=[entryUUID], connectionUrl=[ldap://ldap.identity.svc.cluster.local:389], validatePasswordPolicy=[false], syncRegistrations=[false], authType=[simple], batchSizeForSync=[1000]}, binaryAttributes: []
```

## Root cause

The Keycloak startup import path was feeding `identity/config/realm-shopping-cart.json` to `kc.sh import` without rendering the `${...}` placeholders first. As a result, the LDAP provider was imported with literal placeholder text instead of the live bind DN and bind credential values.

## Fix

- Render the realm JSON inside the Keycloak initContainer before running `kc.sh import`.
- Expand the client secrets, LDAP bind DN, and LDAP bind credential from the environment populated by the ConfigMap and ExternalSecret.
- Keep `identity/config/realm-shopping-cart.json` as the source template, but do not import it raw.

## Follow-up

- Rebuild the identity stack after the branch merges.
- Verify the live Keycloak logs show a concrete LDAP bind DN instead of `${LDAP_BIND_DN}`.
- Retry the Argo CD SSO login after the import path is rendered.
