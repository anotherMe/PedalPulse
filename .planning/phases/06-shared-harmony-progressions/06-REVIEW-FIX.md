---
phase: 06-shared-harmony-progressions
fixed_at: 2026-10-13T08:40:00Z
review_path: .planning/phases/06-shared-harmony-progressions/06-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 6: Code Review Fix Report

**Fixed at:** 2026-10-13T08:40:00Z
**Source review:** .planning/phases/06-shared-harmony-progressions/06-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 4 (critical + warning; the 4 Info findings were out of scope)
- Fixed: 4
- Skipped: 0

## Fixed Issues

### WR-01: Registry Events treat the stems `parent` and `proto` as prototypes, not entries

**Files modified:** `supercollider/core/loader.scd`, `supercollider/library/README.md`
**Commit:** bff3168
**Applied fix:** `~ppStemValid` now refuses `parent` and `proto` (as well as `auto`), and the README name rule lists them. The reviewer's first suggestion was used (reserve the names), not the IdentityDictionary rewrite, to keep the change small. Note: `Array:includes` compares Strings by identity, so the check uses `includesEqual` (verified headless: `auto`, `parent`, `proto` false; `classic`, `desc`, `name`, `lift` true).

### WR-02: Every Start replays the identical Auto order

**Files modified:** `supercollider/core/harmony.scd`, `supercollider/library/README.md`
**Commit:** 1e6d677
**Applied fix:** The draw counter moved out of the per-run `~ppHarm[\auto]` state into `~ppAutoPicks` (`~x = ~x ? 0` idiom), so Stop then Start continues the sequence instead of restarting it. README now says picks differ between runs and that a replay needs the same seed on a freshly started SuperCollider. Logic change: requires human verification (the intended behavior is that two Starts in one SuperCollider session no longer start with the same Auto order).

### WR-03: `~ppAutoPrefetching` is reset on every load of loader.scd

**Files modified:** `supercollider/core/loader.scd`
**Commit:** 78210e0
**Applied fix:** `~ppAutoPrefetching = ~ppAutoPrefetching ? false;`. The teardown clearing suggested as optional was not added.

### WR-04: The library guard only compares the working tree with HEAD

**Files modified:** `scripts/check.sh`
**Commit:** ff08acc
**Applied fix:** `library_guard` takes an optional base ref. The base is `LIBRARY_GUARD_BASE` if set, else the merge-base of HEAD with `origin/main` when that ref exists, else HEAD. A missing HEAD prints `CHECK SKIP: library guard (no commits yet)`; an unresolvable explicit base fails; a failing `git diff` fails instead of being swallowed. The self-test gained three cases (committed edit against an older base, unresolvable base, repo with no commits). Logic change: requires human verification of the base choice (the merge-base with origin/main means unpushed commits are covered too).

## Verification

Gates ran in the isolated review-fix worktree (with `.venv` symlinked in from the main checkout), not the main checkout. The tree contents were then cherry-picked onto `main` and compared identical (`git diff` of `supercollider/` and `scripts/` between the temp branch and main was empty), so the result is reproducible from main.

- `scripts/check.sh` (full): CHECK PASS. Guard self-test OK, guard OK, LIBRARY PASS (15 files), library file count OK, SMOKE PASS (about 5.5 min total).
- Run after all four fixes (the library test alone was also run after WR-01 and WR-02: LIBRARY PASS).

## Process note

The fast-forward of `main` to the review-fix branch failed because `main` gained a commit (`1c0acda docs: rewrite README ...`) while the fixer ran. The four fix commits were cherry-picked onto `main` instead (identical trees verified), the worktree was removed, the temp branch deleted and the recovery sentinel removed. Cherry-picked hashes differ from the ones recorded during the run.

---

_Fixed: 2026-10-13T08:40:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
