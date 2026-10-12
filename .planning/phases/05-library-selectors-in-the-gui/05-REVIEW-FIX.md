---
phase: 05-library-selectors-in-the-gui
fixed_at: 2026-10-12T00:00:00Z
review_path: .planning/phases/05-library-selectors-in-the-gui/05-REVIEW.md
iteration: 1
findings_in_scope: 2
fixed: 2
skipped: 0
status: all_fixed
---

# Phase 5: Code Review Fix Report

**Fixed at:** 2026-10-12
**Source review:** .planning/phases/05-library-selectors-in-the-gui/05-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 2
- Fixed: 2
- Skipped: 0

Scope was critical_warning, so the four Info findings (IN-01 to IN-04) were not attempted.

## Fixed Issues

### WR-01: README lists the library contents incorrectly

**Files modified:** `supercollider/library/README.md`
**Commit:** 1649257
**Applied fix:** Added `melodies/classic_lead_loud` (with a one-line description) to the list of shipped variations. Also added a sentence pointing readers to the `desc` line at the top of each file, so the list is less likely to go stale.

### WR-02: `--hidden` without `--exit-after` starts an app nobody can see or close

**Files modified:** `python_app/main.py`
**Commit:** 4312a47
**Applied fix:** After `parse_args`, `parser.error(...)` now rejects `--hidden` unless `--exit-after > 0`. A negative `--exit-after` combined with `--hidden` is rejected too. The only existing `--hidden` caller (`test_main_launch.py`) already passes `--exit-after 300`.

## Verification

Checks ran in the isolated worktree (it has no separate dependency install, so the main checkout's `.venv` was used). The worktree was fast-forwarded into `main` and removed afterwards.
- `python3 -c "import ast; ..."` syntax check on `main.py` passed.
- `main.py --hidden` and `main.py --hidden --exit-after -5` both exit with the new parser error.
- `pytest python_app/tests`: 191 passed.

WR-02 is a behaviour change, so it is worth a quick human look. The logic is simple and was checked by running the app.

---

_Fixed: 2026-10-12_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
