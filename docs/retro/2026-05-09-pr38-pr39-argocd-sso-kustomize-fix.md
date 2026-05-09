# Retrospective — PR #38 + PR #39: ArgoCD SSO Keycloak wiring + kustomize duplicate fix

**Date:** 2026-05-09
**Milestone:** ArgoCD SSO enablement — Keycloak ExternalSecrets + identity kustomization fix
**PRs:** #38 (feat: ArgoCD SSO via Keycloak) + #39 (fix: ldap duplicate ExternalSecret) — merged to main
**Participants:** Claude, Copilot

## What Went Well
- Copilot caught `argocd-secret` ExternalSecret missing `spec.target.template` — consistent label propagation now enforced across all ESO secrets
- Minimal fix PR (#39) cleanly isolated the one-line kustomize change; CI validated in a single pass
- All 6 Copilot threads addressed and resolved before merge
- enforce_admins workflow (disable → merge → restore) executed cleanly

## What Went Wrong
- Duplicate `ldap-secrets-externalsecret.yaml` entry was introduced in a prior PR and reached main undetected — kustomize build was not validated locally before commit
- Issue doc initially referenced k3d-manager internals (`services/shopping-cart-identity`) instead of `argocd/applications/identity.yaml` in this repo — caught by Copilot
- Bug spec contained a "Do NOT create a PR" instruction that contradicted the delivery mechanism — template artifact from the k3d-manager Codex workflow, not appropriate for in-repo doc

## Process Rules Added
- Run `kubectl kustomize <path>` locally before committing any change to `kustomization.yaml`
- Issue docs in this repo must reference `argocd/applications/` Application YAMLs, not consuming repos
- Spec "What NOT to Do" sections should not carry Codex-workflow instructions when the fix is delivered via a PR in-repo

## Decisions Made
- `argocd-secret` ExternalSecret uses `creationPolicy: Merge` to preserve static ArgoCD fields while ESO manages the OIDC client secret only
- All ESO-managed Secrets must include `spec.target.template` with `type: Opaque` and `app.kubernetes.io/*` labels for consistent label propagation

## Theme
Two PRs closed one chain: a duplicate kustomization entry blocked Keycloak from deploying, which blocked the OIDC flow, which blocked SSO. The fix was one line; the lesson is that kustomize validation belongs in the local workflow, not just CI. PR #38 delivered the broader SSO wiring; PR #39 delivered the surgical unblock.
