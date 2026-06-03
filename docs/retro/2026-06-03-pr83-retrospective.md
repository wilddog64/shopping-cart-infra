# Retrospective — PR #83 fix/product-images-keycloak-login

**Date:** 2026-06-03
**PR:** #83 — merged to main (`28a58358347be5a229fdaa1b579f6696830ef4b8`)
**Branch:** fix/product-images-keycloak-login
**Participants:** Claude, Codex, Copilot

## What Went Well
- Codex implemented both file changes (minio image tag + LDAP hashes) exactly per spec with no interpretation errors
- Copilot caught the plaintext credential exposure in the bootstrap.yaml comment and CHANGELOG — caught before merge
- All Copilot threads replied to and resolved cleanly
- CI passed on first run (Validate Manifests)

## What Went Wrong
- Plaintext dev credentials (`admin/Shopping1!` etc.) were initially committed in the bootstrap.yaml comment and CHANGELOG entry — Copilot caught it; fixed in follow-up commit 9aba540
- Credential hygiene rule not in the spec template — the spec should have warned against embedding plaintext in comments

## Process Rules Added
None added to CLAUDE.md this PR. Implicit rule: never put plaintext dev credentials in YAML comments or CHANGELOG entries — reference the spec doc instead.

## Decisions Made
- SSHA hashes of known-password dev credentials are acceptable in GitOps bootstrap manifests for dev/sandbox clusters
- Plaintext must only appear in private spec docs (k3d-manager docs/bugs/), not in the repo being deployed
- Per-cluster credential generation (Vault init-job) deferred to a future hardening milestone

## Theme
Two-line fix: swap the Python base image to get Pillow working, replace unknown-hash LDAP passwords with known-hash equivalents so dev users can actually log in. Clean execution by Codex; Copilot caught a credential hygiene slip in the comment/changelog that the spec hadn't guarded against.
