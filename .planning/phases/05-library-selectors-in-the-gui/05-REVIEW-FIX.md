---
phase: 05-library-selectors-in-the-gui
fixed_at: 2026-10-12T00:00:00Z
review_path: .planning/phases/05-library-selectors-in-the-gui/05-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 5: Code Review Fix Report

**Fixed at:** 2026-10-12
**Source review:** .planning/phases/05-library-selectors-in-the-gui/05-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 3 (critical_warning; IN-01..IN-04 out of scope)
- Fixed: 3
- Skipped: 0

**Verification environment:** edits and commits were made in an isolated git worktree; the suite was run from that worktree using the main checkout's `.venv` (`.venv/bin/pytest python_app/tests -q`): 191 passed (baseline 188, plus 3 new tests). Tk tests ran against the real display (windows off-screen/hidden).

## Fixed Issues

### WR-01: A lost send leaves the dropdown out of sync with the engine, and the same pick cannot be retried

**Files modified:** `python_app/library_logic.py`, `python_app/tests/test_library_logic.py`, `supercollider/library/README.md`
**Commit:** 5521675
**Applied fix:** `LibrarySelector` now remembers whether the last send succeeded (`_last_send_ok`, set from `send(...) is not False`, also updated by `send_initial`). Re-picking the already-selected name resends it only when the last send reported failure; listeners are not notified again on such a retry. After a successful send, picking the selected item still sends nothing, so D-05 holds. The recorded selection is still kept on a failed send, so `test_failed_send_keeps_the_selection` is unchanged and still passes. Added tests: retry after a failed send (then no resend after success), retry of `Auto` after a failed initial send. README line about re-picking now mentions the retry. Status: fixed, requires human verification (logic change).
**Scope notes:** No receive path, timer or thread was added. Engine-restart resync (the second scenario in the review) is intentionally not addressed: UDP to a missing listener returns success, and LINK-04 is deferred.

### WR-02: A listener exception skips the send and leaves state half-applied

**Files modified:** `python_app/library_logic.py`, `python_app/tests/test_library_logic.py`
**Commit:** d6e8c32
**Applied fix:** Listeners still run before the send (original order kept), but the send now sits in a `finally`, so a raising listener (e.g. a Tk `TclError`) no longer skips it; the exception still propagates afterwards. Added `test_listener_exception_does_not_skip_the_send`. Status: fixed, requires human verification (logic change).

### WR-03: `test_main_launch` opens a real, visible window and steals focus (twice per run)

**Files modified:** `python_app/main.py`, `python_app/tests/test_main_launch.py`
**Commit:** 669da1a
**Applied fix:** Added a `--hidden` flag to `main.py` that calls `root.withdraw()` after all startup sends and before the mainloop; the launch test passes it to the real entry point. All seven startup datagrams, the two launches and every assertion are unchanged (a withdrawn window does not affect `send_initial`, which does not go through the Scale command). Added a module-scoped autouse fixture that skips cleanly when a throwaway withdrawn Tk root cannot be created in a subprocess (independent of `main.py`, so a startup regression still fails).

## Skipped Issues

None. IN-01..IN-04 were outside `fix_scope` (critical_warning).

---

_Fixed: 2026-10-12_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
