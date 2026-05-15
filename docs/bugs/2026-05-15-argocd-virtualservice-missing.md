# Bug: ArgoCD not reachable via hostname — Istio Gateway and VirtualService missing

**Status:** Open  
**Branch:** `bug/keycloak-ldap-mappers-missing` (add to same branch — related networking fix)  
**Affects:** `networking/istio/` (new directory), `argocd/applications/networking.yaml` (new file),
`argocd/config/argocd-cm.yaml`, `identity/keycloak/realm-shopping-cart.json`

---

## Symptom

`http://argocd.shopping-cart.local` routes to Keycloak instead of ArgoCD.
All traffic on port 80 is served by Keycloak regardless of the `Host` header, because no Istio
Gateway or VirtualService exists to do host-based routing. The Keycloak VirtualService that is
present in the live cluster references `istio-system/default-gateway`, which does not exist as a
CRD resource and is not persisted to the repo.

---

## Root Cause

Two resources are missing:

1. **No Istio `Gateway` CRD** — without it, the Istio IngressGateway has no host-based routing
   rules and passes all port-80 traffic to a single backend (Keycloak via OrbStack transparent
   proxy routing).
2. **No Istio `VirtualService` for ArgoCD** — even after the Gateway is created, `argocd.shopping-cart.local` has no routing rule.

Additionally:
- The Keycloak VirtualService exists only as a live patch; it is not in the repo and will be lost
  on the next cluster build.
- `argocd-cm.yaml` sets `url: https://argocd.shopping-cart.local` but ArgoCD runs `--insecure`
  (HTTP only). The OIDC redirect callback will use the URL scheme, so HTTPS would break the
  callback against an HTTP-only server.
- The Keycloak `argocd` client's `redirectUris` does not include
  `http://argocd.shopping-cart.local/*`, so OIDC SSO will fail after the URL is corrected to HTTP.

---

## Fix

### File 1 (new): `networking/istio/gateway.yaml`

```yaml
---
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: default-gateway
  namespace: istio-system
  labels:
    app.kubernetes.io/part-of: shopping-cart
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "keycloak.shopping-cart.local"
    - "argocd.shopping-cart.local"
```

### File 2 (new): `networking/istio/keycloak-virtualservice.yaml`

Persists the live-patched VirtualService to the repo.

```yaml
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: keycloak
  namespace: identity
  labels:
    app.kubernetes.io/part-of: shopping-cart
spec:
  gateways:
  - istio-system/default-gateway
  hosts:
  - keycloak.shopping-cart.local
  http:
  - route:
    - destination:
        host: keycloak.identity.svc.cluster.local
        port:
          number: 80
```

### File 3 (new): `networking/istio/argocd-virtualservice.yaml`

```yaml
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: argocd
  namespace: cicd
  labels:
    app.kubernetes.io/part-of: shopping-cart
spec:
  gateways:
  - istio-system/default-gateway
  hosts:
  - argocd.shopping-cart.local
  http:
  - route:
    - destination:
        host: argocd-server.cicd.svc.cluster.local
        port:
          number: 80
```

### File 4 (new): `networking/istio/kustomization.yaml`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

metadata:
  name: istio-networking

resources:
- gateway.yaml
- keycloak-virtualservice.yaml
- argocd-virtualservice.yaml
```

### File 5 (new): `argocd/applications/networking.yaml`

Adds a new ArgoCD Application so the networking resources are GitOps-managed.
Use `directory:` (not kustomize) so each resource's explicit namespace is respected —
kustomize's `namespace` field would override all namespaces to the destination namespace.

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: shopping-cart-networking
  namespace: cicd
  labels:
    app.kubernetes.io/name: shopping-cart-networking
    app.kubernetes.io/part-of: shopping-cart
  annotations:
    argocd.argoproj.io/sync-wave: "-2"
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: shopping-cart

  source:
    repoURL: https://github.com/wilddog64/shopping-cart-infra.git
    targetRevision: HEAD
    path: networking/istio
    directory:
      recurse: false

  destination:
    server: https://kubernetes.default.svc
    namespace: istio-system

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=false
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 1m

  info:
  - name: Description
    value: Istio Gateway and VirtualServices for host-based HTTP routing
```

**Note on namespace:** ArgoCD's `destination.namespace` is the default only when using plain
`directory:` type without kustomize namespace override. Resources with explicit `namespace:` in
their manifests (VirtualServices in `identity` and `cicd`) will be applied to those namespaces.
The Gateway with `namespace: istio-system` matches the destination and also works correctly.

### File 6 (update): `argocd/config/argocd-cm.yaml`

Change line:
```yaml
  url: https://argocd.shopping-cart.local
```
to:
```yaml
  url: http://argocd.shopping-cart.local
```

ArgoCD runs with `--insecure` (confirmed from pod args). The HTTPS URL causes the OIDC redirect
callback to target `https://argocd.shopping-cart.local/auth/callback`, which the HTTP-only server
cannot serve.

### File 7 (update): `identity/keycloak/realm-shopping-cart.json`

In the `argocd` client's `redirectUris` array, add the HTTP hostname:

```json
"redirectUris": [
  "https://argocd.shopping-cart.local/*",
  "http://argocd.shopping-cart.local/*",
  "http://localhost:8080/*"
]
```

The existing HTTPS entry can stay for forward-compatibility; the new HTTP entry is required
for the OIDC callback to work after the URL change.

---

## Testing

After applying:
1. `kubectl apply -k networking/istio/` (or ArgoCD sync)
2. Confirm both VirtualServices are accepted by Istio:
   ```
   kubectl get virtualservice -A
   ```
3. `curl -v http://argocd.shopping-cart.local/` — must NOT redirect to `/admin/`; must redirect to ArgoCD login or the OIDC flow
4. Open `http://argocd.shopping-cart.local` in a browser — click "Log in via Keycloak"
5. Log in as `admin` / `Admin1234!` — confirm ArgoCD loads with admin role
6. `curl -v http://keycloak.shopping-cart.local/` — must still return Keycloak's own 302

---

## Definition of Done

- [ ] `networking/istio/gateway.yaml` created
- [ ] `networking/istio/keycloak-virtualservice.yaml` created
- [ ] `networking/istio/argocd-virtualservice.yaml` created
- [ ] `networking/istio/kustomization.yaml` created
- [ ] `argocd/applications/networking.yaml` created
- [ ] `argocd/config/argocd-cm.yaml` URL changed to `http://`
- [ ] `identity/keycloak/realm-shopping-cart.json` ArgoCD client redirectUris updated
- [ ] Branch pushed before reporting done
- [ ] Copilot reviewer tagged after PR creation
