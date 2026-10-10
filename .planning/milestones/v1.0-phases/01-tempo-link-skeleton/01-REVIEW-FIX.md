---
phase: 01-tempo-link-skeleton
fixed_at: 2026-10-09T07:01:21Z
review_path: .planning/phases/01-tempo-link-skeleton/01-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 01: Code Review Fix Report

**Fixed at:** 2026-10-09T07:01:21Z
**Source review:** .planning/phases/01-tempo-link-skeleton/01-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 3 (fix_scope: critical_warning -- CR-* and WR-* only; the two Info findings, IN-01 and IN-02, were out of scope and left untouched)
- Fixed: 3
- Skipped: 0

**Isolation:** All edits and commits were made inside a dedicated git worktree
(`.claude/worktrees/rf-01-85961-1791529095`, on temp branch `gsd-reviewfix/01-85961`),
then fast-forwarded onto `main` and torn down transactionally (worktree removed, temp
branch deleted, recovery sentinel cleared) after all three commits landed.

**Verification environment:** Tier 1 (re-read) and Tier 2 (syntax checks: `bash -n`,
`python3 -c "ast.parse(...)"`) ran inside the isolated worktree. The full pytest suite
(`.venv/bin/pytest python_app/tests -q`, 66 passed) was also run inside the worktree,
against the repo's existing `.venv` (shared via absolute path, not duplicated into the
worktree). `scripts/smoke_test.sh` itself could not be run end-to-end inside the worktree
because worktrees do not carry untracked files, including the project's own `.venv` the
script requires (`'.venv/bin/python is missing'`) -- this is a worktree-isolation
artifact, not a regression. The fixed `set -e` + `rc=$?` capture pattern was instead
verified with an equivalent minimal harness run directly in the main checkout (not the
worktree): a `false`-based failing command under `set -euo pipefail` correctly reached
and printed the "smoke test FAILED (log: ...)" diagnostic branch, confirming the fix
closes the silent-exit gap CR-01 described. After cleanup, these results are reproducible
by running `.venv/bin/pytest python_app/tests -q` and `bash scripts/smoke_test.sh` from
the main checkout at `/Users/marcogiordano/Documents/personali/lab/PedalPulse`, where both
`.venv` and `sclang` are present.

## Fixed Issues

### CR-01: `set -e` silently defeats the smoke-test script's failure diagnostics

**Files modified:** `scripts/smoke_test.sh`
**Commit:** `2264568`
**Applied fix:** Replaced the `cmd; rc=$?` anti-pattern (which under `set -euo pipefail`
terminates the script at the failing command, before `rc=$?` or the subsequent `cat "$LOG"` /
failure message ever run) with the "avoid the toggle" variant from the review's second
suggested fix: `rc=0` is set first, then the sclang invocation is run with `|| rc=$?` so a
non-zero exit is caught without triggering `errexit`, and execution always reaches `cat "$LOG"`
and the pass/fail branch. Verified with a standalone harness reproducing the exact
`set -euo pipefail` + capture structure: a failing command now correctly reaches the "smoke
test FAILED (log: ...)" diagnostic instead of exiting silently.

### WR-01: Enter-commit's `focus_set()` triggers an implicit, untested second commit via `<FocusOut>`

**Files modified:** `python_app/view.py`
**Commit:** `b66d68d`
**Applied fix:** Added a `self._committing` reentrancy guard (initialized `False` in
`__init__`, alongside the entry widget setup) and wrapped `commit_entry`'s body in a
`try/finally` that sets the flag before calling `controller.apply_entry()` and clears it on
exit. If `commit_entry` is re-entered while the flag is set (which happens synchronously when
`self.root.focus_set()` on the force=True path triggers the Entry's own `<FocusOut>` binding),
the reentrant call now short-circuits and returns `None` immediately without a second
`apply_entry()` call. This directly follows the review's first suggested fix shape (explicit
reentrancy guard) rather than the alternative restructuring (separate private helper for the
blur-commit logic), since the guard is a smaller, behavior-preserving change to the existing
binding layout. Full pytest suite (66 tests) still passes, confirming no regression to the
existing direct-call test paths in `test_view_tk.py`.

### WR-02: Forced-but-unchanged entry commit leaves the Entry text un-normalized

**Files modified:** `python_app/bpm_logic.py`
**Commit:** `ac63e06`
**Applied fix:** Applied the review's suggested fix verbatim: changed
`apply_entry`'s `if force or changed: send_now() else: notify()` to
`if force or changed: send_now()` followed by an unconditional `if not changed: notify()`.
This preserves prior behavior for the `changed=True` case (where `_set()` already notified
internally) and for the unforced/unchanged case (still a pure re-notify, no send), while adding
the previously-missing notify for the `force=True, changed=False` case -- so a forced commit of
an unchanged-but-differently-formatted value (e.g. "150.00" when already at 150) now normalizes
the Entry's displayed text, matching the method's own docstring. Full pytest suite (66 tests)
still passes.

## Skipped Issues

None -- all in-scope findings (CR-01, WR-01, WR-02) were fixed. IN-01 and IN-02 were out of
scope for this run (`fix_scope: critical_warning`) and were left untouched; they remain
documented in `01-REVIEW.md` for a future `--fix-scope all` pass or manual follow-up.

---

_Fixed: 2026-10-09T07:01:21Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
