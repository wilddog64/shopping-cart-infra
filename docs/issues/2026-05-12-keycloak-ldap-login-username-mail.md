# Keycloak LDAP login is resolved using `uid` instead of the email-style login that Argo CD users enter

## What was tested

- Opened the Argo CD SSO login page from `make up`.
- Attempted to sign in with the current shopping-cart realm users.
- Verified Keycloak returned `Invalid username or password` for `admin@shopping-cart.local`.
- Verified the realm and LDAP bootstrap data still advertised email-style identities via `mail` while Keycloak was resolving LDAP users by `uid`.

## Actual output

```text
invalid_request: Missing parameter: code_challenge_method
```

```text
Invalid username or password.
```

```text
user_not_found
```

## Root cause

The shopping-cart realm had `loginWithEmailAllowed=true`, but the LDAP federation was still keyed on `uid`.
That made the login flow inconsistent with the browser-facing guidance that presents `username or email`.

## Follow-up

- Keep the LDAP federation username attribute aligned with the email-style login users actually enter.
- Re-sync Keycloak after the realm and ConfigMap change so the live client import matches the repo source of truth.
