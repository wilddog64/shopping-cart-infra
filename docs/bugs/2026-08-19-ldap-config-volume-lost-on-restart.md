# LDAP loses its configuration after pod restart

## Impact

`shopping-cart-identity`, and consequently its parent `shopping-cart-apps`, remained
in ArgoCD `Progressing` even though their sync operations succeeded. The managed
`identity/ldap` Deployment was `0/1` available and its pod repeatedly exited with:

```text
Error: the config directory (/etc/ldap/slapd.d) is empty but not the database directory (/var/lib/ldap)
```

## Root cause

The osixia OpenLDAP image requires its database directory and dynamic configuration
directory to persist together. The manifest persisted `/var/lib/ldap` on
`ldap-data-pvc`, but mounted `/etc/ldap/slapd.d` from `emptyDir`. The image also
defaults `LDAP_REMOVE_CONFIG_AFTER_SETUP` to true. After the pod restarted, the
database remained while the matching configuration was gone, so OpenLDAP correctly
refused to start.

## Fix

- Add `ldap-config-pvc` and mount it at `/etc/ldap/slapd.d`.
- Set `LDAP_REMOVE_CONFIG_AFTER_SETUP=false` so initialization retains the config.
- For the already affected environment, archive the existing database PVC before
  reinitializing it from the declarative bootstrap. The original configuration was
  ephemeral and cannot be reconstructed from the failed pod.

## Verification

```text
kubectl kustomize identity/ldap
kubectl apply --dry-run=client -k identity/ldap
kubectl -n identity rollout status deployment/ldap --timeout=180s
kubectl -n cicd get applications.argoproj.io shopping-cart-identity shopping-cart-apps
```
