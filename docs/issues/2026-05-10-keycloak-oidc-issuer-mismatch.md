# Bug: Keycloak OIDC Issuer URL Mismatch (HTTP vs HTTPS)

**Date:** 2026-05-10
**Severity:** High — blocks ArgoCD SSO login
**Status:** Open
**Assignee:** Gemini CLI

## Symptom
ArgoCD SSO fails with the following error:
```
failed to query provider "http://keycloak.shopping-cart.local/realms/shopping-cart": 
oidc: issuer URL provided to client ("http://keycloak.shopping-cart.local/realms/shopping-cart") 
did not match the issuer URL returned by provider ("https://keycloak.shopping-cart.local/realms/shopping-cart")
```

## Root Cause
In the `keycloak-config` ConfigMap, `KC_PROXY` is set to `edge`. When Keycloak is in "edge" proxy mode, it assumes TLS termination is happening at a proxy and forcefully generates its OIDC metadata using `https://` URLs, even if the request reached it via `http://`.

Since ArgoCD is configured to use the internal `http://` address (via CoreDNS rewrite), the OIDC strict security check fails because `http` does not match `https`.

## Required Fix
Change `KC_PROXY` from `edge` to `none` in `identity/keycloak/configmap.yaml`. This will allow Keycloak to return `http://` URLs in its metadata, matching the internal cluster communication used in the sandbox environment.

## Security Note
Traffic remains secure via Istio mTLS encryption between namespaces, even though the application protocol is shifted to HTTP to satisfy the OIDC handshake.
