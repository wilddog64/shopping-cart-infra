# Kustomize disallows the realm import file outside `identity/keycloak`

## What happened

I attempted to point the `keycloak-realm-import` generator at `../config/realm-shopping-cart.json` so the realm JSON could live in one shared parent location.

## Actual output

```text
error: loading KV pairs: file sources: [realm-shopping-cart.json=../config/realm-shopping-cart.json]: security; file '/Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra/identity/config/realm-shopping-cart.json' is not in or below '/Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra/identity/keycloak'
```

## Root cause

The repo uses the default kustomize load restrictions, which prevent a Keycloak-local kustomization from reading a file outside its base directory.

## Fix

- Keep `identity/keycloak/realm-shopping-cart.json` as the import source for the Keycloak kustomization.
- Keep the rendered realm import self-contained under `identity/keycloak/`.
- Avoid cross-directory file references in this kustomization unless the repo explicitly opts into relaxed load restrictions.

## Follow-up

- Leave the single import source under `identity/keycloak/`.
- Re-run the rendered-manifest validation after any future Keycloak realm changes.
