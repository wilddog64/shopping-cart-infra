# Bug: argocd-cm url uses http — OIDC callback resolves to Keycloak instead of ArgoCD

**Date:** 2026-05-15
**File:** `argocd/config/argocd-cm.yaml`
**Symptom:** ArgoCD SSO login always fails after Keycloak authentication completes.
The browser is redirected to `http://argocd.shopping-cart.local/auth/callback`, which
resolves to `127.0.0.1:80` — the Keycloak port-forward — returning:
```
{"error":"Unable to find matching target resource method","error_description":"..."}
```
ArgoCD never receives the OIDC callback code and the login loop repeats.

---

## Root Cause

`argocd-cm` has `url: http://argocd.shopping-cart.local` (line 13).

ArgoCD uses this `url` field to construct the OIDC `redirect_uri` sent to Keycloak:
```
http://argocd.shopping-cart.local/auth/callback
```

After successful Keycloak authentication the browser follows that redirect.
On the local dev setup:
- `argocd.shopping-cart.local` → `127.0.0.1` (via `/etc/hosts`)
- `127.0.0.1:80` → Keycloak kubectl port-forward
- `127.0.0.1:443` → socat HTTPS wrapper → ArgoCD

The callback therefore lands on Keycloak (port 80) instead of ArgoCD (port 443).
Keycloak has no `/auth/callback` handler and returns an error, breaking the OIDC flow.

The fix is one token: `http` → `https`.

---

## Fix

**File:** `argocd/config/argocd-cm.yaml`

**Old (line 13):**
```yaml
  url: http://argocd.shopping-cart.local
```

**New:**
```yaml
  url: https://argocd.shopping-cart.local
```

Only this one line changes. No other lines in the file are modified.

---

## Definition of Done

- [ ] `argocd/config/argocd-cm.yaml` line 13 reads `url: https://argocd.shopping-cart.local`
- [ ] No other lines in the file are modified
- [ ] Commit message: `fix(argocd): use https url so OIDC callback resolves to ArgoCD not Keycloak`
- [ ] Push: `git push origin shopping-cart-infra-v0.5.3`
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager with commit SHA and task status

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside `argocd/config/argocd-cm.yaml`
- Do NOT commit to `main`
- Work on branch: `shopping-cart-infra-v0.5.3`

## Before You Start

- Branch (all work repos): `shopping-cart-infra-v0.5.3`
- `git pull origin shopping-cart-infra-v0.5.3` in `shopping-cart-infra`
- Read this spec in full
- Read `argocd/config/argocd-cm.yaml` line 13 to confirm the exact string before editing
