# Retrospective — PR #42: fix(ldap) LDAP_SEED_INTERNAL_LDIF_PATH

**Date:** 2026-05-09
**PR:** #42 — merged to main
**Participants:** Claude, Gemini, Copilot

## What Went Well
- Root cause correctly identified: any Kubernetes volume mount (ConfigMap OR emptyDir) creates a kernel mount point; osixia startup script's `rm -rf assets/config` hits EBUSY on descent into that mount point
- `LDAP_SEED_INTERNAL_LDIF_PATH` discovered in osixia 1.5.0 startup.sh source — clean solution requiring minimal YAML changes
- Gemini implemented the 3-change fix correctly on first attempt; all 3 changes verified by Claude

## What Went Wrong
- Bug 5 (PR #41) shipped an incorrect fix: switched ConfigMap to emptyDir at `ldif/custom`, which still makes `custom/` a mount point — same EBUSY error
- Root cause analysis was incomplete when Bug 5 spec was written; the mount-point constraint was not understood at spec time

## Process Rules Added
- When a startup script calls `rm -rf` on a directory: verify it is NOT a Kubernetes volume mount point. Any volume mounted at the target path (ConfigMap, emptyDir, secret, PVC) will cause EBUSY

## Decisions Made
- Use `LDAP_SEED_INTERNAL_LDIF_PATH` env var (supported natively by osixia 1.5.0) rather than command overrides or parent-directory mounts

## Theme
Bug 5 was a well-intentioned but insufficiently analyzed fix. Switching ConfigMap to emptyDir felt like it solved the write-permission problem but missed the kernel mount-point constraint entirely. Bug 6 required reading the osixia startup script source to find the correct hook point.
