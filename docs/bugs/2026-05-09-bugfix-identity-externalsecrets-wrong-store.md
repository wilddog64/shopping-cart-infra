# Bugfix: Identity ExternalSecrets reference non-existent ClusterSecretStore vault-backend

**Branch:** `docs/next-improvements`
**Files:** `identity/keycloak/keycloak-secrets-externalsecret.yaml`,
           `identity/keycloak/keycloak-client-secrets-externalsecret.yaml`,
           `identity/ldap/ldap-secrets-externalsecret.yaml`

---

## Problem

Three ExternalSecrets in the `identity` namespace fail with `SecretSyncedError` because
they reference `ClusterSecretStore vault-backend`, which does not exist on the hub cluster.
The hub cluster has only `SecretStore vault-kv-store` (namespace-scoped, `identity`).
Keycloak and LDAP pods cannot start without the secrets these ExternalSecrets provision.

**Root cause:** ExternalSecrets were written targeting the remote k3s cluster (which has
`ClusterSecretStore vault-backend`) but the identity stack deploys on the hub cluster.

---

## Reproduction

```bash
kubectl get externalsecret -n identity --context k3d-k3d-cluster
# Actual: keycloak-secrets, keycloak-client-secrets, ldap-secrets all show SecretSyncedError
kubectl get clustersecretstore --context k3d-k3d-cluster
# Actual: No resources found — vault-backend does not exist
kubectl get secretstore -n identity --context k3d-k3d-cluster
# Actual: vault-kv-store  Valid  True
```

---

## Fix

Change `secretStoreRef` in all three files from `ClusterSecretStore vault-backend` to
`SecretStore vault-kv-store`. The change is identical in each file.

### Change 1 — `identity/keycloak/keycloak-secrets-externalsecret.yaml` lines 20–22

**Old:**
```yaml
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
```
**New:**
```yaml
  secretStoreRef:
    name: vault-kv-store
    kind: SecretStore
```

### Change 2 — `identity/keycloak/keycloak-client-secrets-externalsecret.yaml` lines 19–21

**Old:**
```yaml
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
```
**New:**
```yaml
  secretStoreRef:
    name: vault-kv-store
    kind: SecretStore
```

### Change 3 — `identity/ldap/ldap-secrets-externalsecret.yaml` lines 20–22

**Old:**
```yaml
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
```
**New:**
```yaml
  secretStoreRef:
    name: vault-kv-store
    kind: SecretStore
```

---

## Files Changed

| File | Change |
|------|--------|
| `identity/keycloak/keycloak-secrets-externalsecret.yaml` | `ClusterSecretStore vault-backend` → `SecretStore vault-kv-store` |
| `identity/keycloak/keycloak-client-secrets-externalsecret.yaml` | `ClusterSecretStore vault-backend` → `SecretStore vault-kv-store` |
| `identity/ldap/ldap-secrets-externalsecret.yaml` | `ClusterSecretStore vault-backend` → `SecretStore vault-kv-store` |

---

## Definition of Done

- [ ] All three files updated
- [ ] `kubectl get externalsecret -n identity` shows all three as `SecretSynced / True`
- [ ] Keycloak pod reaches `Running`
- [ ] Committed and pushed to `docs/next-improvements`

**Commit message (exact):**
```
fix(identity): change ExternalSecrets from ClusterSecretStore vault-backend to SecretStore vault-kv-store
```
