---
phase: 01-tempo-link-skeleton
plan: 03
subsystem: gui
tags: [tkinter, bpm-entry, keyboard-shortcuts, tdd, tk9]

requires:
  - phase: 01-02
    provides: "python_app/bpm_logic.py BpmController/Debouncer/clamp_bpm and python_app/view.py BpmWindow this plan extends"
provides:
  - "python_app/bpm_logic.py: parse_bpm_entry() and BpmController.apply_entry(text, *, force) -- entry commit rules (D-10), sharing clamp_bpm's half-up rounding and 60..180 snapping with the slider"
  - "python_app/view.py: BpmWindow.entry/entry_var (replaces value_label), commit_entry(force), handle_nudge_key(delta), and the Up/Down/Shift-Up/Shift-Down root bindings (D-11)"
  - "python_app/tests/test_view_tk.py: the D-02 Tk 9 widget smoke test with real Scale/Entry/Button widgets and the real root.after scheduler"
affects: [phase-2-groove]

actuals:
  tokens: 4168
  tasks: 2
  commits: 3
plan_head_before: c12d195134a400da0b8ab0a7410228170c1a385f
plan_head_after: 32b50d0a5d00c52e5edcc6a5c658626513646db0

tech-stack:
  added: []
  patterns:
    - "parse_bpm_entry shares clamp_bpm with the slider path so entry and slider snap/round identically (D-09, D-10)"
    - "BpmController._notify() helper: notifies listeners without requiring a value change, used both for the revert-on-invalid-entry path and for an unforced-unchanged commit's text normalisation"
    - "Entry commit always routes through _send_now(), which already cancels any pending debounced nudge send -- the single mechanism both D-10 and D-21's ordering guarantee rely on"
    - "Tk 9 test fixture positions the window off-screen (geometry, not withdraw()) to keep it mapped -- withdrawing it was found to suppress the Scale widget's -command callback under this build"

key-files:
  created:
    - python_app/tests/test_view_tk.py
  modified:
    - python_app/bpm_logic.py
    - python_app/view.py
    - python_app/tests/test_bpm_logic.py

key-decisions:
  - "parse_bpm_entry evaluates no text -- strip, float(), isfinite check, then clamp_bpm -- so entry parsing can never execute arbitrary code (T-01-10)"
  - "Enter always force-commits (even at an unchanged value); focus-out only commits a changed value -- this is the exact mechanism that prevents Enter followed by a focus-out from double-sending"
  - "Tk 9 smoke test fixture keeps the window mapped off-screen (root.geometry('+2000+2000')) instead of calling withdraw() -- empirically, a withdrawn root suppressed the Scale widget's -command callback on a programmatic .set() under this project's Tk 9.0.3 build, which would have made every slider-driven test assert against a stale controller value"
  - "Tk 9 smoke test fixture calls root.update() immediately before root.destroy() in teardown -- without it, the second (and every later) Tk() instance created in the same pytest process hung inside root.update() the first time it packed a widget"

requirements-completed: [GUI-01, LINK-01]

coverage:
  - id: D1
    description: "The entry field sits between the nudge pairs (-5 -1 [entry] +1 +5) and always shows the same BPM as the slider after any change from any control"
    requirement: "GUI-01"
    verification:
      - kind: unit
        ref: "python_app/tests/test_view_tk.py#test_build_shows_initial_state"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_view_tk.py#test_slider_live_update_then_release_sends"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_view_tk.py#test_nudges_update_immediately_and_debounce_to_one_send"
        status: pass
    human_judgment: false
  - id: D2
    description: "Enter (Return/KP_Enter) always commits once; focus-out commits only a changed value, so Enter followed by focus-out never double-sends"
    requirement: "GUI-01"
    verification:
      - kind: unit
        ref: "python_app/tests/test_bpm_logic.py#test_apply_entry_force_true_same_value_sends_again, test_apply_entry_force_false_unchanged_value_notifies_but_does_not_send"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_view_tk.py#test_entry_commit_revert_and_unchanged_focusout"
        status: pass
    human_judgment: false
  - id: D3
    description: "Invalid entry text ('abc', '', 'nan', 'inf') reverts the field to the current BPM and sends nothing"
    requirement: "GUI-01"
    verification:
      - kind: unit
        ref: "python_app/tests/test_bpm_logic.py#test_parse_bpm_entry_invalid_returns_none, test_apply_entry_invalid_text_reverts_without_send"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_view_tk.py#test_entry_commit_revert_and_unchanged_focusout"
        status: pass
    human_judgment: false
  - id: D4
    description: "Out-of-range entry text snaps (300 -> 180, 10 -> 60, -5 -> 60, 1e3 -> 180); decimals round half up (130.5 -> 131, 130.4 -> 130); surrounding spaces are ignored"
    requirement: "GUI-01"
    verification:
      - kind: unit
        ref: "python_app/tests/test_bpm_logic.py#test_parse_bpm_entry_valid"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_view_tk.py#test_bounds_adjacency_at_upper_bound_sends_nothing"
        status: pass
    human_judgment: false
  - id: D5
    description: "Up/Down change BPM by +-1 and Shift+Up/Shift+Down by +-5 while the window has focus, sharing the same debounced send as the nudge buttons"
    requirement: "LINK-01"
    verification:
      - kind: unit
        ref: "python_app/tests/test_view_tk.py#test_key_bindings_registered_and_handle_nudge_key_works"
        status: pass
    human_judgment: false
  - id: D6
    description: "An entry commit cancels any pending debounced nudge send, so the last /pp/bpm sent is always the last value the user committed"
    requirement: "LINK-01"
    verification:
      - kind: unit
        ref: "python_app/tests/test_bpm_logic.py#test_apply_entry_cancels_pending_nudge_debounce"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_view_tk.py#test_entry_commit_cancels_pending_nudge_send"
        status: pass
    human_judgment: false
  - id: D7
    description: "Under the project's real Tk 9.0.3, the real Scale, Entry and Button widgets drive the controller correctly with a fake sender (the D-02 Tk 9 smoke test)"
    requirement: "GUI-01"
    verification:
      - kind: integration
        ref: "python_app/tests/test_view_tk.py (8 tests, real widgets, real root.after scheduler)"
        status: pass
    human_judgment: false
  - id: D8
    description: "End-to-end audible/physical acceptance: slider, entry, nudges and physical arrow keys agree with the engine's tempo, the SC post window shows exactly one /pp/bpm line per gesture, and the window floats over Zwift when On top is ticked"
    verification: []
    human_judgment: true
    rationale: "Physical keyboard focus, mouse drags, audible tempo and window stacking over a full-screen game cannot be asserted from an automated test; this is Task 2's <human-check>, deferred to end-of-phase UAT per workflow.human_verify_mode=end-of-phase."

duration: 55min
completed: 2026-10-09
status: complete
---

# Phase 1 Plan 03: Entry field + keyboard shortcuts, all controls in sync Summary

**Entry-field parsing and commit rules (TDD RED/GREEN) added to `BpmController`, then a Tk `Entry` with Enter/focus-out/arrow-key bindings replaces the read-only value label in `BpmWindow`, proven against real Tk 9.0.3 widgets by a new smoke test that caught two genuine environment quirks.**

## Performance

- **Duration:** ~55 min
- **Started:** 2026-10-09
- **Completed:** 2026-10-09
- **Tasks:** 2
- **Files modified:** 4 (1 created, 3 modified)

## Accomplishments

- `python_app/bpm_logic.py`: `parse_bpm_entry()` parses typed text through `strip()` -> `float()` -> `math.isfinite` -> `clamp_bpm()`, sharing the slider's half-up rounding and 60..180 snapping; `BpmController.apply_entry(text, *, force)` implements D-10's full commit contract (revert on invalid, force-always-sends, unforced-unchanged-just-normalises) via a new `_notify()` helper, and always routes a send through `_send_now()` so an entry commit cancels any pending debounced nudge send (D-21 ordering)
- `python_app/view.py`: the read-only `value_label` is replaced by `BpmWindow.entry`/`entry_var`, bound to `<Return>`/`<KP_Enter>` (force=True) and `<FocusOut>` (force=False) via `commit_entry(force)`; `<Up>`/`<Down>`/`<Shift-Up>`/`<Shift-Down>` are bound on `root` via `handle_nudge_key(delta)` (D-11); the controller listener now updates both `bpm_var` (slider) and `entry_var` (text) so all three controls always agree
- `python_app/tests/test_view_tk.py`: the D-02 Tk 9 widget smoke test -- 8 tests against real `Scale`/`Entry`/`Button` widgets and the real `root.after`/`root.after_cancel` scheduler, with only the OSC send faked
- 66 tests pass total: 35 Plan 02 tests (unchanged) + 23 new `test_bpm_logic.py` tests (Task 1) + 8 new `test_view_tk.py` tests (Task 2); `timeout 30 ./run.sh --port 57199 --exit-after 800` exits 0; `bash scripts/smoke_test.sh` still prints `SMOKE PASS` (no engine change in this plan)

## Task Commits

Each task was committed atomically (Task 1 followed full TDD RED/GREEN; Task 2 is a standard `type="auto"` task):

1. **Task 1 RED: failing tests for parse_bpm_entry/apply_entry** - `6bc1e67` (test)
2. **Task 1 GREEN: implement parse_bpm_entry/apply_entry** - `a1da652` (feat)
3. **Task 2: entry field + keyboard shortcuts in view.py + test_view_tk.py** - `32b50d0` (feat)

**Plan metadata:** committed separately after this SUMMARY.

_No REFACTOR commit was needed for Task 1 -- the GREEN implementation passed cleanly without further cleanup._

## Files Created/Modified

- `python_app/bpm_logic.py` - `parse_bpm_entry()`, `BpmController._notify()`, `BpmController.apply_entry(text, *, force)`
- `python_app/tests/test_bpm_logic.py` - 23 new tests for `parse_bpm_entry` and `apply_entry` (44 total after this plan, up from 21 after Plan 02)
- `python_app/view.py` - `BpmWindow.entry`/`entry_var` (replaces `value_label`), `commit_entry(force)`, `handle_nudge_key(delta)`, root key bindings
- `python_app/tests/test_view_tk.py` - new file: fixture `tk_root`, helper `pump(root, ms)`, 8 tests

## Decisions Made

- `parse_bpm_entry` never evaluates text (no `eval`); it only parses with `float()` and clamps, matching the plan's T-01-10 mitigation
- Enter always force-commits even at an unchanged value (`force=True`); focus-out only commits on an actual change (`force=False`) -- the exact split that makes "type a value, press Enter, click elsewhere" send exactly once
- Kept the Tk 9 test fixture's window mapped (positioned off-screen with `geometry`) rather than following the plan's literal `withdraw()` instruction, after confirming empirically that a withdrawn root suppresses the Scale widget's `-command` callback on a programmatic `.set()` under this project's real Tk 9.0.3 build -- this is precisely the class of Tk 9 quirk D-02 asks this smoke test to surface
- Added a `root.update()` call immediately before `root.destroy()` in the fixture's teardown after finding that, without it, the second (and every later) `Tk()` instance created later in the same pytest process hung inside `root.update()` the first time it packed a widget

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] RED phase needed minimal stub bodies, not a bare import, to produce valid RED evidence**
- **Found during:** Task 1 RED phase
- **Issue:** Writing the new tests first against a `bpm_logic.py` with no `parse_bpm_entry`/`apply_entry` at all caused an `ImportError` during test collection -- a collection-level failure (INVALID_RED per the TDD gate: "syntax errors, zero-test discovery... are INVALID_RED"), not a genuine assertion failure, and it also blocked every pre-existing Plan 02 test in the same file from running.
- **Fix:** Added minimal stub bodies (`parse_bpm_entry` returning `None`; `apply_entry` returning `False`) so the module imported cleanly and the new tests failed on real `AssertionError`s while all 27 untouched tests kept passing -- genuine RED evidence, not a collection error.
- **Files modified:** `python_app/bpm_logic.py`
- **Verification:** `.venv/bin/pytest python_app/tests/test_bpm_logic.py -q` showed 17 failed (all target behavior assertions) / 27 passed (all pre-existing + the already-correct invalid-text cases), with zero collection errors
- **Committed in:** `6bc1e67` (RED commit)

**2. [Rule 1 - Bug] `root.withdraw()` suppressed the Scale widget's -command callback under this Tk 9.0.3 build**
- **Found during:** Task 2, building `test_view_tk.py`'s first slider test
- **Issue:** The plan's fixture spec calls for `tkinter.Tk()` + `withdraw()`. Empirically, under this project's real Homebrew python3.13 / Tk 9.0.3 build, a withdrawn (unmapped) root's `Scale` widget never invoked its `-command` callback on a programmatic `.set()` call -- confirmed by isolating the exact same `.set()` call against an unmapped vs. an off-screen-but-mapped root. Left as written, every slider-driven test (2, 3, 4, 6) would have asserted against a stale `controller.value` that the GUI's live display (D-20) depends on.
- **Fix:** Changed the fixture to `root.geometry("+2000+2000")` instead of `withdraw()`, keeping the window mapped (so Tk's native widget-command firing behaves exactly as in the real running app) while positioning it off-screen so it stays invisible during an automated run.
- **Files modified:** `python_app/tests/test_view_tk.py`
- **Verification:** All 8 `test_view_tk.py` tests pass with the real `Scale`/`Entry`/`Button` widgets; the slider tests now correctly observe `controller.value` updating on `.set()`
- **Committed in:** `32b50d0` (Task 2 commit)

**3. [Rule 3 - Blocking] A second `Tk()` instance in the same pytest process hung on first widget pack**
- **Found during:** Task 2, running the full 8-test `test_view_tk.py` suite (each test creates and destroys its own root per the plan's function-scoped fixture spec)
- **Issue:** The second test to run (and every test after it) hung indefinitely inside `root.update()` the first time it packed a `Scale` widget on its freshly created `Tk()` instance -- reproduced in isolation down to a 3-line minimal repro with no `BpmWindow` involved, so this is a property of this machine's Tk 9.0.3/macOS Aqua build re-using the process for a second `Tk()` instance, not a bug in this plan's code.
- **Fix:** Added `root.update()` immediately before `root.destroy()` in the fixture's teardown (flushing any pending Tk event before the interpreter tears down) -- empirically this made every subsequent `Tk()` instantiation in the same process behave normally, verified across the full 8-test run with no hang.
- **Files modified:** `python_app/tests/test_view_tk.py`
- **Verification:** `timeout 30 .venv/bin/pytest python_app/tests/test_view_tk.py -v` completes all 8 tests in ~2s with no hang
- **Committed in:** `32b50d0` (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (1 Rule 1 TDD-process fix, 1 Rule 1 real Tk-9-build bug the smoke test was designed to catch, 1 Rule 3 blocking test-infrastructure fix). All three were necessary to get a genuinely green, non-hanging test suite that actually exercises the real widget wiring this plan's `<behavior>`/`<verify>` sections require; none changed the plan's functional scope.
**Impact on plan:** No scope creep. Deviations 2 and 3 are themselves exactly what D-02's "Tk 9 widget smoke test" was commissioned to find -- genuine, environment-specific Tk 9 behavior differences from the Tk 8.6 assumptions baked into common Tkinter test-writing habits.

## Issues Encountered

None beyond the three documented deviations above, all resolved within the normal fix-attempt budget.

## User Setup Required

None - no external service configuration required. The existing project `.venv` (created by `./run.sh --setup` in an earlier wave) was reused; no new dependency was installed by this plan.

## Next Phase Readiness

- `BpmController` and `BpmWindow` now fully implement GUI-01 and LINK-01 as scoped for Phase 1: slider, entry, nudge buttons and keyboard shortcuts all stay in sync and share one send-debounce/cancel mechanism.
- This plan's `<human-check>` (end-to-end acceptance: drag the slider, type values, press arrow keys, hold Shift+Down, toggle On top, all while `supercollider/main.scd` plays) is the phase's end-to-end acceptance listen, deferred to end-of-phase UAT per `workflow.human_verify_mode=end-of-phase` -- it is the final verification gate for Phase 1 and should be exercised before the phase is marked verified.
- Two Tk 9 environment findings (documented above) are now encoded directly in `test_view_tk.py`'s fixture; any future Tk-widget test file in this project should reuse the same `geometry()`-not-`withdraw()` and pre-destroy-`update()` pattern rather than rediscovering them.
- No blockers for Phase 2.

---
*Phase: 01-tempo-link-skeleton*
*Completed: 2026-10-09*

## Self-Check: PASSED

- All 4 touched files verified present on disk: `python_app/bpm_logic.py`, `python_app/view.py`, `python_app/tests/test_bpm_logic.py`, `python_app/tests/test_view_tk.py`
- All 3 task commits (`6bc1e67` RED, `a1da652` GREEN, `32b50d0` Task 2) verified as ancestors of HEAD
- All plan acceptance criteria re-verified: `.venv/bin/pytest python_app/tests -q` passes 66/66 with no skipped tests; `timeout 30 ./run.sh --port 57199 --exit-after 800` exits 0; `bash scripts/smoke_test.sh` prints `SMOKE PASS`; acceptance-criteria greps for `tk.Entry`, `StringVar`, `<Return>`, `<KP_Enter>`, `<FocusOut>`, `<Shift-Up>`, `<Shift-Down>`, `def commit_entry`, `def handle_nudge_key` all hit; `value_label` count is 0; `test_view_tk.py` has 8 test functions and uses `root.after`; `grep -cE '(^|[^.])\beval\(' python_app/bpm_logic.py` is 0
- No stub patterns (`TODO`/`FIXME`/`placeholder`/"coming soon"/"not available") found in any created or modified file
- Requirements: GUI-01 and LINK-01 marked complete (this was the last plan declaring both per the shared-ID gate; `requirements.ready-ids` confirmed 2/2 ready before marking)
