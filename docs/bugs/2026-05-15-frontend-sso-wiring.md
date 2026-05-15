# Bugfix: wire shopping-cart-frontend SSO end-to-end

**Branch (shopping-cart-infra):** `shopping-cart-infra-v0.5.3`
**Branch (shopping-cart-frontend):** `shopping-cart-frontend-v0.x.1` — create from `origin/main`

---

## Before You Start

### shopping-cart-infra
1. `git pull origin shopping-cart-infra-v0.5.3`
2. Read this spec in full before touching any file
3. Confirm `networking/istio/frontend-virtualservice.yaml` does NOT exist
4. Confirm `networking/istio/gateway.yaml` has only `keycloak.shopping-cart.local` and `argocd.shopping-cart.local` in hosts

### shopping-cart-frontend
1. Check current latest tag: `gh release list --repo wilddog64/shopping-cart-frontend --limit 1`
2. Create branch: `git checkout -b shopping-cart-frontend-v0.x.1 origin/main` (replace x with next minor)
3. Confirm `nginx.conf` has `http://keycloak.identity.svc.cluster.local:8080` in `connect-src`
4. Confirm `.github/workflows/ci.yml` does NOT pass `VITE_KEYCLOAK_URL` in "Build, Scan & Push" job

---

## Problem

The shopping-cart-frontend cannot be accessed via SSO because four things are missing:

1. **No Istio routing** — `frontend.shopping-cart.local` is not in the gateway or any VirtualService
2. **Keycloak redirect URI is HTTPS-only** — `frontend` client has no `http://` URI; ArgoCD uses HTTP
3. **`VITE_KEYCLOAK_URL` not passed at build time** — reusable workflow has no `build-args`; image was built with empty Keycloak URL; browser-side OIDC fails silently
4. **nginx CSP blocks Keycloak** — `connect-src` allows `http://keycloak.identity.svc.cluster.local:8080` (in-cluster, unreachable from browser) but not `http://keycloak.shopping-cart.local`

**Manual steps (not Codex's job):**
- Create `ghcr-pull-secret` in `shopping-cart-apps` namespace (cluster bootstrap)
- Add `192.168.97.2 frontend.shopping-cart.local` to `/etc/hosts` on the dev machine

---

## Fix 1 — shopping-cart-infra: add frontend host to Istio Gateway

In `networking/istio/gateway.yaml`, add `frontend.shopping-cart.local`:

**Old:**
```yaml
      hosts:
        - keycloak.shopping-cart.local
        - argocd.shopping-cart.local
```

**New:**
```yaml
      hosts:
        - keycloak.shopping-cart.local
        - argocd.shopping-cart.local
        - frontend.shopping-cart.local
```

---

## Fix 2 — shopping-cart-infra: create frontend VirtualService

Create `networking/istio/frontend-virtualservice.yaml`:

```yaml
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: frontend
  namespace: istio-system
  labels:
    app.kubernetes.io/part-of: shopping-cart
spec:
  hosts:
    - frontend.shopping-cart.local
  gateways:
    - istio-system/default-gateway
  http:
    - route:
        - destination:
            host: frontend.shopping-cart-apps.svc.cluster.local
            port:
              number: 80
```

---

## Fix 3 — shopping-cart-infra: add HTTP redirect URI to Keycloak frontend client

In `identity/keycloak/realm-shopping-cart.json`, find the `frontend` client entry.

**Old `redirectUris`:**
```json
"redirectUris": [
  "http://localhost:5173/*",
  "http://localhost:3000/*",
  "https://frontend.shopping-cart.local/*"
]
```

**New `redirectUris`:**
```json
"redirectUris": [
  "http://localhost:5173/*",
  "http://localhost:3000/*",
  "https://frontend.shopping-cart.local/*",
  "http://frontend.shopping-cart.local/*"
]
```

---

## Fix 4 — shopping-cart-infra: add build-args input to reusable workflow

In `.github/workflows/build-push-deploy.yml`, add an optional `build-args` input and
pass it to both build steps.

**Old `inputs:` block (top of file):**
```yaml
    inputs:
      service-name:
        required: true
        type: string
      image-name:
        required: true
        type: string
```

**New:**
```yaml
    inputs:
      service-name:
        required: true
        type: string
      image-name:
        required: true
        type: string
      build-args:
        required: false
        type: string
        default: ''
```

**Old "Build image" step (no build-args):**
```yaml
      - name: Build image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: false
          load: true
          tags: ${{ inputs.image-name }}:sha-${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          secrets: |
            GH_TOKEN=${{ secrets.PACKAGES_TOKEN }}
```

**New:**
```yaml
      - name: Build image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: false
          load: true
          tags: ${{ inputs.image-name }}:sha-${{ github.sha }}
          build-args: ${{ inputs.build-args }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          secrets: |
            GH_TOKEN=${{ secrets.PACKAGES_TOKEN }}
```

**Old "Push image" step (no build-args):**
```yaml
      - name: Push image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          platforms: linux/amd64,linux/arm64
          tags: |
            ${{ inputs.image-name }}:sha-${{ github.sha }}
            ${{ inputs.image-name }}:latest
          cache-from: type=gha
          secrets: |
            GH_TOKEN=${{ secrets.PACKAGES_TOKEN }}
```

**New:**
```yaml
      - name: Push image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          platforms: linux/amd64,linux/arm64
          tags: |
            ${{ inputs.image-name }}:sha-${{ github.sha }}
            ${{ inputs.image-name }}:latest
          build-args: ${{ inputs.build-args }}
          cache-from: type=gha
          secrets: |
            GH_TOKEN=${{ secrets.PACKAGES_TOKEN }}
```

---

## Fix 5 — shopping-cart-frontend: pass VITE_KEYCLOAK_URL in CI

In `.github/workflows/ci.yml`, find the "Build, Scan & Push" job that calls the
reusable workflow. Add the `build-args` input.

**Old:**
```yaml
    uses: wilddog64/shopping-cart-infra/.github/workflows/build-push-deploy.yml@3e3a7957cab3fb102946d6eaab10cd106ce7b1f2
    with:
      service-name: shopping-cart-frontend
      image-name: ghcr.io/wilddog64/shopping-cart-frontend
```

**New:**
```yaml
    uses: wilddog64/shopping-cart-infra/.github/workflows/build-push-deploy.yml@3e3a7957cab3fb102946d6eaab10cd106ce7b1f2
    with:
      service-name: shopping-cart-frontend
      image-name: ghcr.io/wilddog64/shopping-cart-frontend
      build-args: VITE_KEYCLOAK_URL=http://keycloak.shopping-cart.local
```

**Important:** After updating `ci.yml`, also update the SHA pinning the reusable
workflow to the SHA of the commit made in Fix 4 above (shopping-cart-infra). Get the SHA with:
```bash
gh api repos/wilddog64/shopping-cart-infra/commits/main --jq '.sha'
```

---

## Fix 6 — shopping-cart-frontend: fix nginx CSP for Keycloak

In `nginx.conf`, update the `Content-Security-Policy` header's `connect-src` to
allow the external Keycloak hostname.

**Old `connect-src` value (inside the CSP header):**
```
connect-src 'self' http://keycloak.identity.svc.cluster.local:8080 https://*.keycloak.local;
```

**New:**
```
connect-src 'self' http://keycloak.shopping-cart.local https://*.keycloak.local;
```

---

## Files Changed

### shopping-cart-infra (`shopping-cart-infra-v0.5.3`)
| File | Change |
|------|--------|
| `networking/istio/gateway.yaml` | Add `frontend.shopping-cart.local` to hosts |
| `networking/istio/frontend-virtualservice.yaml` | New VirtualService for frontend |
| `identity/keycloak/realm-shopping-cart.json` | Add `http://frontend.shopping-cart.local/*` to frontend client |
| `.github/workflows/build-push-deploy.yml` | Add optional `build-args` input, pass to both build steps |

### shopping-cart-frontend (new branch from `main`)
| File | Change |
|------|--------|
| `.github/workflows/ci.yml` | Add `build-args: VITE_KEYCLOAK_URL=http://keycloak.shopping-cart.local`; update SHA pin |
| `nginx.conf` | Fix `connect-src` to use `http://keycloak.shopping-cart.local` |

---

## What NOT to Do

- Do NOT create PRs — each branch will get its own PR later
- Do NOT skip pre-commit hooks — use `PRE_COMMIT_ALLOW_NO_CONFIG=1 git commit` for shopping-cart-infra; normal hooks for frontend
- Do NOT touch files outside those listed above
- Do NOT commit to `main` in either repo

---

## Rules

- shopping-cart-infra: `PRE_COMMIT_ALLOW_NO_CONFIG=1 git commit`
- shopping-cart-frontend: standard commit (has pre-commit config)
- Push both branches to `origin` before reporting done

**Commit messages (exact):**
- shopping-cart-infra: `feat(networking): add frontend Istio routing, HTTP redirect URI, and build-args support`
- shopping-cart-frontend: `fix(ci): pass VITE_KEYCLOAK_URL build arg; fix nginx CSP connect-src for Keycloak`

---

## Definition of Done

- [ ] `networking/istio/gateway.yaml` has `frontend.shopping-cart.local` in hosts
- [ ] `networking/istio/frontend-virtualservice.yaml` exists, routes to `frontend.shopping-cart-apps.svc.cluster.local:80`
- [ ] `realm-shopping-cart.json` frontend client has `http://frontend.shopping-cart.local/*` in redirectUris
- [ ] `build-push-deploy.yml` has `build-args` optional input wired to both build steps
- [ ] `shopping-cart-infra` committed and pushed to `origin/shopping-cart-infra-v0.5.3`
- [ ] `ci.yml` passes `build-args: VITE_KEYCLOAK_URL=http://keycloak.shopping-cart.local`
- [ ] `nginx.conf` uses `http://keycloak.shopping-cart.local` in `connect-src`
- [ ] `shopping-cart-frontend` committed and pushed to `origin/shopping-cart-frontend-v0.x.1`
- [ ] All SHAs verified on `origin/<branch>` for both repos
