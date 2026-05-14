# Issue: Keycloak realm import was still templating the LDAP bind DN

## What happened
Copilot triage of the live `keycloak` pod reported an LDAP lookup failure with:

```text
javax.naming.InvalidNameException: [LDAP: error code 34 - invalid DN]
```

The log path showed Keycloak trying to authenticate the `argocd` client while resolving LDAP users for `admin@shopping-cart.local`.

## Actual output

```text
2026-05-13 23:03:23,476 ERROR [org.keycloak.storage.ldap.idm.store.ldap.LDAPOperationManager] (executor-thread-4) Could not query server using DN [ou=users,dc=shopping-cart,dc=local] and filter [(&(email=admin@shopping-cart.local)(objectclass=inetOrgPerson)(objectclass=organizationalPerson))]: javax.naming.InvalidNameException: [LDAP: error code 34 - invalid DN]
...
2026-05-13 23:03:23,481 WARN  [org.keycloak.events] (executor-thread-4) type="LOGIN_ERROR", realmId="cbd5207c-ed78-4186-afef-271d0995f582", clientId="argocd", userId="null", ipAddress="127.0.0.1", error="invalid_user_credentials", auth_method="openid-connect", auth_type="code", redirect_uri="https://argocd.shopping-cart.local/auth/callback", code_id="0f097024-3eaa-402a-93ec-6e502b8d05b2", username="admin@shopping-cart.local"
```

## Root cause
The realm import continued to rely on `${LDAP_BIND_DN}` templating for the LDAP federation bind DN. That made the live realm sensitive to whether the startup render path ran correctly. A literal DN is not secret, so there is no reason to keep that field templated at import time.

## Fix
- Hardcode the canonical bind DN in the realm template:
  - `cn=admin,dc=shopping-cart,dc=local`
- Keep the bind credential templated from the Secret.
- Remove the bind-DN substitution from the Keycloak initContainer render step so the import path no longer depends on it.

## Follow-up
- Rebuild the identity stack after the branch merges.
- Verify the live Keycloak logs no longer show the LDAP bind DN placeholder or an invalid DN error.
