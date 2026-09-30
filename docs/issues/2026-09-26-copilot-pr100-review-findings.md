# Copilot review findings — PR #100

**PR:** [#100](https://github.com/wilddog64/shopping-cart-infra/pull/100) — `fix(identity): remove the awk dependency the Keycloak image does not provide`
**Date:** 2026-09-26

## Finding 1 — `set -e` abort in the awk-free CSV helpers

**Flagged:** `identity/keycloak/keycloak-reconcile-hook-job.yaml:119`, also 131, 165, 171.

> With `bash -euo pipefail`, a helper used in command substitution must not return non-zero for
> the normal "no matches" case. If `csv_value` doesn't find a match it will return the `read` EOF
> status (1), which can abort the entire hook before the subsequent `[[ -z ... ]]` checks run.

### The specific claim is a false positive

`read`'s EOF status is the *loop condition*, not the loop's exit status. Bash sets a `while` loop's
status from the last command executed in the **body**. In `csv_value` that is an `if` compound, and
an `if` whose condition is false and which has no `else` returns 0. Verified under
`set -euo pipefail` across five no-match shapes — direct call, `local` assignment, plain assignment,
empty CSV, trailing blank line — all returned 0 and none aborted.

### The pattern is real, in a function Copilot did not flag

`level0_rows` ends its body with `[[ ... ]] && printf '%s\n' "${line}"`. When the condition is
false that compound returns 1, so the loop — and the function — return 1 whenever the **last** row
is not level 0.

The call site is a plain assignment, which propagates under `set -e`:

```bash
top_executions="$(level0_rows "${all_executions}")"
```

This was reachable in normal operation, not an edge case: `kcadm get authentication/flows/<alias>/executions`
returns a *flattened* listing of every nested execution, so the final row is routinely a level-1
entry such as `Username Password Form`. The hook would have aborted at essentially the same point
it previously died on `awk: command not found` — trading a named error for a silent one.

Reproduced before the fix:

```
--- last row IS level 0 ---                rc=0
--- last row is NOT level 0 (level 1) ---  rc=1
--- plain assignment under set -e ---      ABORTS
```

### Fix

An explicit `return 0` on the four helpers whose body's last command can return non-zero:
`csv_value`, `csv_all_values`, `level0_rows`, `csv_unexpected_top_names`. `csv_match_count`,
`csv_row_count` and `urlencode_path` already end in `printf` and were left alone.

This makes the contract explicit rather than resting on the subtle "an unmatched `if` returns 0"
semantics, which is what made the difference between the two cases hard to see in review.

Re-verified against the fixed file: the repro now returns rc=0 with the correct single level-0 row;
`bash -n` and `shellcheck -s bash` both clean.

## Root cause

Translating awk to bash moved the exit status from "the last `print`" to "whatever the loop body
last evaluated". awk programs have no equivalent of a body whose final expression leaks a falsy
status into `set -e`, so the hazard is created by the translation itself and has no counterpart in
the code being replaced.

## Process note

This file was already patched once for the same class of bug — the `|| true` guards on the five
`grep`-in-command-substitution pipelines. Any future rewrite of a hook script running under
`set -euo pipefail` should end every value-returning helper with an explicit `return 0` or a
`printf`, and should be checked by running the helper's no-match path under `set -e` rather than by
reading it.
