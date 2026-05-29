# Issue: Keycloak/LDAP ExternalSecrets reference non-existent ClusterSecretStore vault-backend

**Date:** 2026-05-09
**Severity:** High — blocks Keycloak and LDAP secret sync, prevents identity stack from starting
**Repo:** shopping-cart-infra
**Branch affected:** main

---

## Symptom

After the `shopping-cart-identity` ArgoCD Application syncs, three ExternalSecrets remain in
`SecretSyncedError` state and Keycloak/postgres pods fail with `CreateContainerConfigError`:

```
NAME                     STATUS              READY
keycloak-secrets         SecretSyncedError   False
keycloak-client-secrets  SecretSyncedError   False
ldap-secrets             SecretSyncedError   False
```

Error from ESO controller: `could not get secret data from provider`

---

## Root Cause

All three ExternalSecrets reference `ClusterSecretStore vault-backend`:

```yaml
secretStoreRef:
  name: vault-backend
  kind: ClusterSecretStore
```

No `ClusterSecretStore` named `vault-backend` exists on the hub cluster. The hub cluster
only has a namespace-scoped `SecretStore` named `vault-kv-store` in the `identity` namespace,
which is already used (successfully) by the OpenLDAP ExternalSecrets.

`vault-backend` is the ClusterSecretStore name applied to the **remote** k3s worker cluster
by `acg-up` Step 9. The identity ExternalSecrets were authored with the remote cluster in
mind but the identity stack was subsequently moved to deploy on the hub cluster.

---

## Impact

- `keycloak-secrets` Secret: never created → Keycloak pod `CreateContainerConfigError`
- `keycloak-client-secrets` Secret: never created → OIDC client secrets unavailable
- `ldap-secrets` Secret: never created → LDAP pod missing credentials
- Keycloak: never reaches `Running` → ArgoCD SSO unavailable

---

## Files

| File | Wrong store |
|------|------------|
| `identity/keycloak/keycloak-secrets-externalsecret.yaml` | `ClusterSecretStore vault-backend` |
| `identity/keycloak/keycloak-client-secrets-externalsecret.yaml` | `ClusterSecretStore vault-backend` |
| `identity/ldap/ldap-secrets-externalsecret.yaml` | `ClusterSecretStore vault-backend` |

## Fix

Change `kind: ClusterSecretStore` → `kind: SecretStore` and `name: vault-backend` →
`name: vault-kv-store` in all three files.
See `docs/bugs/2026-05-09-bugfix-identity-externalsecrets-wrong-store.md`.
