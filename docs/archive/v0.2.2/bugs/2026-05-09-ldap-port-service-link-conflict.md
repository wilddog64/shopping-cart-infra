# Bugfix: LDAP CrashLoopBackOff — Kubernetes LDAP_PORT service link conflicts with osixia/openldap

**Branch:** `bug/ldap-port-service-link-conflict`
**File:** `identity/ldap/deployment.yaml`

---

## Problem

The LDAP pod crashes immediately on startup with:

```
daemon: listen URL "ldap://ldap-5b67554584-r48gr:tcp://10.43.181.177:389" parse error=5
slapd stopped.
```

**Root cause:** Kubernetes auto-injects service environment variables when `enableServiceLinks`
is not disabled. Because a Service named `ldap` exists in the `identity` namespace, Kubernetes
injects `LDAP_PORT=tcp://10.43.181.177:389` into every pod in that namespace. The osixia/openldap
container reads `LDAP_PORT` as its port number and constructs a malformed listen URL:
`ldap://<hostname>:tcp://10.43.181.177:389`, which slapd rejects with parse error=5.

---

## Reproduction

```bash
kubectl logs -n identity -l app.kubernetes.io/name=ldap --previous
# Shows: daemon: listen URL "ldap://...:tcp://...:389" parse error=5

kubectl exec -n identity <ldap-pod> -- env | grep LDAP_PORT
# Shows: LDAP_PORT=tcp://10.43.181.177:389  (injected by Kubernetes)
```

---

## Fix

Add `enableServiceLinks: false` to the pod spec in `identity/ldap/deployment.yaml`.
This disables Kubernetes service environment variable injection, preventing the
`LDAP_PORT` conflict entirely.

### Change — `identity/ldap/deployment.yaml` (Deployment pod spec)

**Old** (lines 53–55):
```yaml
    spec:
      initContainers:
      - name: copy-ldif
```

**New:**
```yaml
    spec:
      enableServiceLinks: false
      initContainers:
      - name: copy-ldif
```

---

## Files Changed

| File | Change |
|------|--------|
| `identity/ldap/deployment.yaml` | Add `enableServiceLinks: false` under `spec.template.spec` |

---

## Definition of Done

- [ ] `enableServiceLinks: false` added to the Deployment pod spec
- [ ] Pod reaches `Running` state: `kubectl get pod -n identity -l app.kubernetes.io/name=ldap`
- [ ] No parse error in logs: `kubectl logs -n identity -l app.kubernetes.io/name=ldap`
- [ ] `ldapsearch` confirms LDAP is reachable
- [ ] Committed and pushed to `bug/ldap-port-service-link-conflict`
- [ ] Tag Copilot: `gh api repos/wilddog64/shopping-cart-infra/pulls/<n>/requested_reviewers -X POST -f 'reviewers[]=copilot-pull-request-reviewer[bot]'`

**Commit message (exact):**
```
fix(ldap): disable service links to prevent LDAP_PORT env var conflict with slapd listen URL
```
