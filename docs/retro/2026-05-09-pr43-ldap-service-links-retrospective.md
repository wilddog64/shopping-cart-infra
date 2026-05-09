# Retrospective — shopping-cart-infra PR #43

**Date:** 2026-05-09
**Milestone:** Bug 7 — LDAP CrashLoopBackOff (LDAP_PORT service link conflict)
**PR:** #43 — merged to main (`dcd18af7`)
**Participants:** Claude, Gemini, Copilot

## What Went Well
- Root cause identified quickly: Kubernetes service link injection corrupting osixia/openldap `LDAP_PORT` env var
- Fix was minimal and correct: single-line `enableServiceLinks: false` in pod spec
- CI passed on first try (YAML lint, kubeconform, kustomize build, GitGuardian — all green)
- Gemini's implementation matched the spec exactly; commit message matched verbatim

## What Went Wrong
- Copilot reviewer continues to generate only a summary overview comment with no inline findings on this repo — not a blocker but reduces code review signal

## Process Rules Added
None this milestone.

## Decisions Made
- `enableServiceLinks: false` is the correct fix for any osixia/openldap deployment where a Service named `ldap` exists in the same namespace — document this as a known footgun for future deployments

## Theme
A one-line fix for a subtle Kubernetes footgun: service link injection silently overrides a container's expected environment variable, causing a malformed URL that slapd rejects at startup. The osixia/openldap image reads `LDAP_PORT` directly from the environment rather than from its own config, making it vulnerable to this class of conflict whenever a Service of the same name coexists in the namespace. Fix: disable service link injection at the pod spec level.
