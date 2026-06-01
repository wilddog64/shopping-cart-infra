# Bug: SSO login fails for frontend.3ai-talk.org — missing redirect URI and gateway routing

**Branch:** `docs/next-improvements`
**Files:**
- `identity/keycloak/realm-shopping-cart.json`
- `networking/istio/gateway.yaml`
- `networking/istio/frontend-virtualservice.yaml`
**Severity:** P1 — SSO login completely broken for the public-facing domain

---

## Symptom

Navigating to `https://frontend.3ai-talk.org` and attempting SSO login fails silently.
Keycloak logs show:

```
type="LOGIN_ERROR", clientId="frontend", error="invalid_redirect_uri",
redirect_uri="https://frontend.3ai-talk.org/callback"
```

---

## Root Cause

Three gaps in the networking and Keycloak config:

1. **Keycloak `frontend` client** — `redirectUris` only contains local dev URLs
   (`http://frontend.shopping-cart.local/*`, `http://localhost:*`).
   `https://frontend.3ai-talk.org/*` is absent, so Keycloak rejects the OAuth callback.

2. **`networking/istio/gateway.yaml`** — the `default-gateway` only lists
   `frontend.shopping-cart.local`; `frontend.3ai-talk.org` is not a gateway host,
   so Istio drops inbound traffic for that hostname.

3. **`networking/istio/frontend-virtualservice.yaml`** — the VirtualService `hosts` list
   only contains `frontend.shopping-cart.local`; requests arriving for
   `frontend.3ai-talk.org` have no routing rule.

---

## Fix

### Fix 1 — `identity/keycloak/realm-shopping-cart.json`

Find the `frontend` client block (search for `"clientId": "frontend"`).
Add `"https://frontend.3ai-talk.org/*"` to `redirectUris`:

**Before:**
```json
"redirectUris": [
  "http://localhost:5173/*",
  "http://localhost:3000/*",
  "https://frontend.shopping-cart.local/*",
  "http://frontend.shopping-cart.local/*"
],
```

**After:**
```json
"redirectUris": [
  "http://localhost:5173/*",
  "http://localhost:3000/*",
  "https://frontend.shopping-cart.local/*",
  "http://frontend.shopping-cart.local/*",
  "https://frontend.3ai-talk.org/*"
],
```

### Fix 2 — `networking/istio/gateway.yaml`

Add `frontend.3ai-talk.org` to the `default-gateway` hosts list (port 80 server block):

**Before:**
```yaml
    - hosts:
      - keycloak.shopping-cart.local
      - argocd.shopping-cart.local
      - frontend.shopping-cart.local
      port:
        name: http
        number: 80
        protocol: HTTP
```

**After:**
```yaml
    - hosts:
      - keycloak.shopping-cart.local
      - argocd.shopping-cart.local
      - frontend.shopping-cart.local
      - frontend.3ai-talk.org
      port:
        name: http
        number: 80
        protocol: HTTP
```

### Fix 3 — `networking/istio/frontend-virtualservice.yaml`

Add `frontend.3ai-talk.org` to the VirtualService `hosts` list:

**Before:**
```yaml
spec:
  hosts:
    - frontend.shopping-cart.local
```

**After:**
```yaml
spec:
  hosts:
    - frontend.shopping-cart.local
    - frontend.3ai-talk.org
```

---

## Behaviour After Fix

| Scenario | Before | After |
|----------|--------|-------|
| `https://frontend.3ai-talk.org` — SSO login | `invalid_redirect_uri` error | Redirects to Keycloak, login succeeds |
| `https://frontend.3ai-talk.org` — page load | May 404 (no gateway route) | Routed to frontend pod correctly |
| `https://frontend.shopping-cart.local` — SSO | Working | Unchanged |

---

## Before You Start

1. `git pull origin docs/next-improvements` in shopping-cart-infra
2. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`
3. Read the three target files in full before editing

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the three listed targets
- Do NOT commit to `main` — work on `docs/next-improvements`
- Do NOT change the existing `shopping-cart.local` entries — they are used for local dev

## Definition of Done

- [ ] `identity/keycloak/realm-shopping-cart.json`: `https://frontend.3ai-talk.org/*` added to `frontend` client `redirectUris`
- [ ] `networking/istio/gateway.yaml`: `frontend.3ai-talk.org` added to `default-gateway` hosts
- [ ] `networking/istio/frontend-virtualservice.yaml`: `frontend.3ai-talk.org` added to `hosts`
- [ ] Commit message: `fix(networking+keycloak): add frontend.3ai-talk.org redirect URI and gateway routing`
- [ ] `git push origin docs/next-improvements` succeeds — do NOT report done until push confirmed
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and COMPLETE status
- [ ] Report back: commit SHA + paste the memory-bank lines you updated
