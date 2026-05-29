# Copilot PR #74 Review Findings

**PR:** #74 — fix(keycloak): add group-ldap-mapper so LDAP groups sync for ArgoCD RBAC
**Date:** 2026-05-29
**File:** `identity/keycloak/keycloak-reconcile-hook-job.yaml`

---

## Finding

**File:** `identity/keycloak/keycloak-reconcile-hook-job.yaml`, heredoc block (~line 241)

Copilot flagged that the heredoc content and terminator were at column 0 inside a YAML
block scalar. Lines at column 0 terminate the YAML `|` block scalar prematurely, so the
raw JSON and `GMEOF` string would appear at the YAML top level — breaking manifest
validation and preventing the Job from running.

---

## First Fix Attempt (wrong)

The Phase 1 agent changed `<<EOF` to `<<-GMEOF` and indented the JSON and terminator
with spaces:

```yaml
              cat > "${_gm_file}" <<-GMEOF
              {"parentId": ...}
              GMEOF
```

**Why this was wrong:** `<<-` strips leading *tabs*, not spaces. After YAML strips its
10-space block prefix, bash sees the content and terminator with 4 leading spaces.
The heredoc never closes (terminator not recognized) and the JSON written to disk has
4 leading spaces — invalid JSON, `kcadm.sh` rejects it.

---

## Correct Fix (commit `a00a636`)

Match the existing `create_mapper_if_missing` pattern already in the file:
use `<<EOF` (no dash) with JSON and terminator at the YAML block indentation level
(10 spaces). YAML strips those 10 spaces before bash executes the script, so the
terminator lands at column 0 as expected.

**Before:**
```yaml
              cat > "${_gm_file}" <<-GMEOF
              {"parentId":"${ldap_id}",...}
              GMEOF
```

**After:**
```yaml
              cat > "${_gm_file}" <<EOF
          {"parentId":"${ldap_id}",...}
          EOF
```

---

## Root Cause

The original spec code block was written with the heredoc at column 0 (valid for a
standalone shell script). When embedded in a YAML block scalar, the content must stay
within the block indentation — but the terminator must also end up at column 0 *after
YAML strips its indentation prefix*. The existing file establishes the correct pattern;
the spec should have referenced it.

---

## Process Note

**Spec template rule to add:** When writing shell heredocs inside YAML block scalars,
always check the existing heredoc pattern in the same file for the correct indentation
level. The terminator must sit at the YAML block indentation level so that after YAML
strips the prefix, bash sees it at column 0. Do not use `<<-` with space-indented files.
