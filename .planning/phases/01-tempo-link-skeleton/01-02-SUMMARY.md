---
phase: 01-tempo-link-skeleton
plan: 02
subsystem: gui
tags: [tkinter, python-osc, pytest, tdd, debounce]

requires:
  - phase: 01-01
    provides: "python_app/config.py constants and python_app/osc_client.py OscClient/send_bpm contract this plan wires the GUI to"
provides:
  - "run.sh: venv bootstrap from python3.13, requirements install (stamped), --setup mode, launches python_app/main.py"
  - "python_app/tkcheck.py: GUI-04 compatibility gate (check_tk_compatible, MIN_TK_VERSION, FIX_HINT), lazily imports tkinter so it is safe to import on a broken interpreter"
  - "python_app/bpm_logic.py: Tk-free clamp_bpm/Debouncer/BpmController -- slider release-only send, nudge debounce coalescing, boundary no-send, initial send"
  - "python_app/view.py: BpmWindow Tk widgets (slider, −5 −1 [value] +1 +5 nudge row, status line, On top toggle) wired to BpmController, no OSC import"
  - "python_app/main.py: entry point running the Tk gate before importing osc_client, wiring OscClient -> BpmController -> BpmWindow"
affects: [01-03-gui-controls, phase-2-groove]

actuals:
  tokens: 6972
  tasks: 3
  commits: 4
plan_head_before: d320688a32320c22b4a35f901941bf4d18b03f2c
plan_head_after: 42a3e43f2a6fdb1a02e7c6ec6c4d967a4040d373

tech-stack:
  added: ["pytest==8.4.2 (dev-only, human-approved via Task 1 package-legitimacy checkpoint)"]
  patterns:
    - "Lazy in-function tkinter import (tkcheck.py has no module-level tkinter import) so the compatibility gate itself can be imported and run on a broken interpreter"
    - "Release-only slider send: Scale command= updates the live IntVar only; <ButtonRelease-1> is the sole OSC trigger"
    - "Cancel-and-reschedule Debouncer wrapping injected schedule/cancel callables (root.after/root.after_cancel in the app, a FakeScheduler in tests)"
    - "BpmController._set() short-circuits on an unchanged clamped value, so boundary nudges (178+5, 180+1, 60-1, etc.) never notify, schedule, or send"

key-files:
  created:
    - run.sh
    - python_app/requirements-dev.txt
    - python_app/tests/conftest.py
    - python_app/tkcheck.py
    - python_app/tests/test_tkcheck.py
    - python_app/bpm_logic.py
    - python_app/tests/test_bpm_logic.py
    - python_app/view.py
    - python_app/main.py
    - python_app/tests/test_osc_client.py
  modified: []

key-decisions:
  - "Task 1's blocking-human package-legitimacy checkpoint for pytest==8.4.2 was approved by the user (exact reply \"approved\") in a prior dispatch; this continuation started directly at Task 2 per the orchestrator's resume instructions"
  - "D-06's −5/−1/+1/+5 labels are built from a NUDGE_LABELS dict with the literal U+2212 minus sign characters in source, not an f-string-constructed MINUS_SIGN constant -- needed so the literal glyph is grep-able and the plan's acceptance check passes"
  - "test_osc_client.py adds regression coverage for the already-existing Plan 01 OscClient/CLI contract rather than driving new RED/GREEN -- the osc_client.py behavior was locked in Plan 01 and this task's BpmController sends through it unchanged"

requirements-completed: [GUI-04, GUI-01, LINK-01]

coverage:
  - id: D1
    description: "./run.sh bootstraps .venv from python3.13, installs requirements.txt (+ requirements-dev.txt with --setup), and never touches anything outside the project directory"
    requirement: "GUI-04"
    verification:
      - kind: integration
        ref: "./run.sh --setup && .venv/bin/pytest python_app/tests -q"
        status: pass
      - kind: unit
        ref: "run.sh content greps: python3.13, -m venv .venv, --setup, .pp-requirements.stamp, exec .venv/bin/python python_app/main.py, zero sudo/brew/--user lines"
        status: pass
    human_judgment: false
  - id: D2
    description: "An interpreter without _tkinter (python3.12) prints a clear fix-it message naming ./run.sh and python3.13, then exits 1 before any window is created or python-osc is imported"
    requirement: "GUI-04"
    verification:
      - kind: integration
        ref: "python3.12 python_app/main.py exits 1 with 'Tkinter is not available' + './run.sh' on stderr; check_tk_compatible() line precedes the osc_client import line in main.py"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_tkcheck.py#test_missing_tkinter_exits_1_with_clear_message, test_python312_without_tkinter_exits_1_with_fix_hint"
        status: pass
    human_judgment: false
  - id: D3
    description: "TkVersion 8.6 and 9.0 both pass the gate; 8.5 fails it with exit 1"
    requirement: "GUI-04"
    verification:
      - kind: unit
        ref: "python_app/tests/test_tkcheck.py#test_tk_version_8_6_and_9_0_both_pass, test_tk_version_8_5_exits_1_with_version_message"
        status: pass
    human_judgment: false
  - id: D4
    description: "On launch the app sends /pp/bpm 120.0 exactly once"
    requirement: "LINK-01"
    verification:
      - kind: unit
        ref: "python_app/tests/test_bpm_logic.py#test_send_initial_sends_once"
        status: pass
    human_judgment: false
  - id: D5
    description: "Dragging the slider updates the shown BPM live and sends nothing; releasing sends exactly one /pp/bpm with the final value"
    requirement: "LINK-01"
    verification:
      - kind: unit
        ref: "python_app/tests/test_bpm_logic.py#test_slider_moved_notifies_and_sends_nothing_then_release_sends_final, test_two_releases_with_no_change_send_two_messages"
        status: pass
    human_judgment: false
  - id: D6
    description: "Nudge buttons update immediately and send exactly one debounced net value 150ms after the last click; a slider release cancels a pending debounced nudge send"
    requirement: "LINK-01"
    verification:
      - kind: unit
        ref: "python_app/tests/test_bpm_logic.py#test_nudge_three_times_updates_immediately_and_sends_once_after_window, test_nudge_up_then_down_within_window_sends_one_net_value, test_slider_release_before_debounce_window_cancels_pending_nudge_send"
        status: pass
    human_judgment: false
  - id: D7
    description: "Boundary adjacency: at 178 +5 gives 180; at 180, +1/+5 leave 180 and send nothing; at 60, -1/-5 leave 60 and send nothing"
    requirement: "GUI-01"
    verification:
      - kind: unit
        ref: "python_app/tests/test_bpm_logic.py#test_nudge_at_upper_bound_adjacency, test_nudge_at_lower_bound_adjacency"
        status: pass
    human_judgment: false
  - id: D8
    description: "OscClient.send_bpm never raises when nothing listens, returns False on OSError, and the CLI/wire contract from Plan 01 still holds"
    requirement: "LINK-01"
    verification:
      - kind: integration
        ref: "python_app/tests/test_osc_client.py (7 tests: real-socket decode, mocked sendto destination, OSError handling, CLI stdout+wire)"
        status: pass
    human_judgment: false
  - id: D9
    description: "Under the project venv (Tk 9.0) the window opens compactly with the slider at 120, the −5 −1 [value] +1 +5 row, the status line, and an unchecked On top toggle that floats the window over Zwift when checked"
    verification: []
    human_judgment: true
    rationale: "Visual window layout, drag feel, and window-manager stacking over a full-screen app can only be judged by looking at and using the live window -- this is Task 3's <human-check>, deferred to end-of-phase UAT per workflow.human_verify_mode=end-of-phase."
  - id: D10
    description: "The audible retempo: dragging the slider and clicking nudge buttons changes the live SuperCollider loop's tempo on the next beat, matching the single /pp/bpm line posted per gesture"
    verification: []
    human_judgment: true
    rationale: "Requires running supercollider/main.scd and listening -- audible musical correctness is not something a unit test can assert; deferred to end-of-phase UAT per workflow.human_verify_mode=end-of-phase."

duration: 35min
completed: 2026-10-09
status: complete
---

# Phase 1 Plan 02: Launchable BPM window (Tk gate + slider + nudge buttons) Summary

**`./run.sh` provisions a python3.13 `.venv`, gates startup on a lazily-imported `tkinter.TkVersion` check, and wires a Tk-free, debounce-tested `BpmController` through a slider (release-only send) and `−5 −1 [value] +1 +5` nudge buttons to the Plan 01 `OscClient`.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-10-09 (continuation; Task 1's checkpoint was resolved in a prior dispatch)
- **Completed:** 2026-10-09
- **Tasks:** 3 (Task 1 checkpoint already resolved; Task 2 + Task 3 executed this dispatch)
- **Files created:** 10

## Accomplishments

- `run.sh`: creates `.venv` from `python3.13` (overridable via `PEDALPULSE_PYTHON`) only when missing, installs `python_app/requirements.txt` with a stamp file to skip redundant installs, adds `requirements-dev.txt` + a `tkcheck.py` report under `--setup`, and otherwise `exec`s `python_app/main.py`; never runs a package manager or touches anything outside the project directory
- `python_app/tkcheck.py`: the GUI-04 compatibility gate. `check_tk_compatible()` imports `tkinter` lazily (no module-level import, so the module itself loads safely on a broken interpreter), exits 1 with a clear fix hint on missing `_tkinter` or `TkVersion < 8.6`; both Tk 8.6 and 9.x pass (D-03); no GUI dialog on failure (D-04)
- `python_app/bpm_logic.py`: `clamp_bpm` (half-up rounding via `floor(value + 0.5)`, rejects non-finite input), `Debouncer` (cancel-and-reschedule through injected `schedule`/`cancel`), and `BpmController` (slider live-update-only, release sends now, nudge debounces and no-ops on an unchanged clamped boundary value, one unconditional initial send) -- pure Python, no tkinter import, fully unit-tested with a `FakeScheduler`
- `python_app/view.py`: `BpmWindow` builds the compact Tk window -- `Scale` bound live to `slider_moved` with the actual OSC trigger on `<ButtonRelease-1>`, the `−5 −1 [value] +1 +5` nudge row (literal U+2212 minus sign, `takefocus=0` throughout so arrow-key focus can't move a control without a release), a status line, and an unchecked "On top" `Checkbutton` toggling `-topmost`
- `python_app/main.py`: runs `check_tk_compatible()` before importing `osc_client`/`bpm_logic`/`view` (verified by line order), builds `Tk()` inside `try`/`except TclError`, wires `OscClient.send_bpm -> BpmController -> BpmWindow`, sends the initial BPM once, and supports `--port`/`--exit-after` for automated launch checks
- 35 tests pass across `test_tkcheck.py` (7), `test_bpm_logic.py` (21), and `test_osc_client.py` (7, regression coverage for the already-locked Plan 01 `OscClient`/CLI contract)

## Task Commits

Each task was committed atomically (TDD RED/GREEN pairs for Tasks 2 and 3):

1. **Task 1: Confirm pytest 8.4.2 legitimacy** - checkpoint, resolved "approved" in a prior dispatch (no commit; nothing was installed until approval)
2. **Task 2 RED: Tk gate tests** - `6b57567` (test)
3. **Task 2 GREEN: tkcheck.py + run.sh** - `c7e9230` (feat)
4. **Task 3 RED: BpmController/Debouncer/clamp_bpm + OscClient regression tests** - `45cc62f` (test)
5. **Task 3 GREEN: bpm_logic.py + view.py + main.py** - `42a3e43` (feat)

**Plan metadata:** committed separately after this SUMMARY.

_No REFACTOR commits were needed -- both GREEN implementations passed cleanly without further cleanup._

## Files Created/Modified

- `run.sh` - venv bootstrap, requirements install, `--setup` mode, app launch
- `python_app/requirements-dev.txt` - `-r requirements.txt` + `pytest==8.4.2` (human-approved)
- `python_app/tests/conftest.py` - puts `python_app/` on `sys.path` for tests
- `python_app/tkcheck.py` - GUI-04 compatibility gate
- `python_app/tests/test_tkcheck.py` - 7 tests for the gate, including a real `python3.12` subprocess check
- `python_app/bpm_logic.py` - `clamp_bpm`, `Debouncer`, `BpmController`
- `python_app/tests/test_bpm_logic.py` - 21 tests with a `FakeScheduler`
- `python_app/view.py` - `BpmWindow` Tk widgets
- `python_app/main.py` - entry point wiring the gate, client, controller, and window
- `python_app/tests/test_osc_client.py` - 7 regression tests for Plan 01's `OscClient`/CLI

## Decisions Made

- Approved pytest 8.4.2 install stands from the resolved Task 1 checkpoint; no further legitimacy concerns raised during Task 2/3 execution
- Built nudge-button labels from a `NUDGE_LABELS` dict containing the literal U+2212 glyphs rather than constructing them with an ASCII `MINUS_SIGN` + digit f-string, so the plan's acceptance grep for the literal `−5` text passes and the labels are easy to audit at a glance
- Kept `test_osc_client.py` as regression coverage for Plan 01's already-correct `OscClient`, rather than treating it as new RED/GREEN work, since the client's wire contract was locked in Plan 01 and this plan only adds a new caller (`BpmController`)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Own test assertion flagged the intentional lazy tkinter import**
- **Found during:** Task 2 GREEN verification
- **Issue:** `test_importing_tkcheck_does_not_import_tkinter` used a substring check (`line.strip().startswith(...)`) that also matched the indented, in-function `import tkinter` inside `check_tk_compatible()` -- exactly the lazy import the test exists to require, not forbid.
- **Fix:** Narrowed the check to column-0 (module-level) lines only (`line.startswith(...)` without `.strip()`), so the function-local import is correctly left unflagged while a real module-level import would still fail the test.
- **Files modified:** `python_app/tests/test_tkcheck.py`
- **Verification:** `.venv/bin/pytest python_app/tests/test_tkcheck.py -q` passes all 7 tests
- **Committed in:** `c7e9230` (Task 2 GREEN commit)

**2. [Rule 1 - Bug] NUDGE_LABELS literal character missing from initial view.py draft**
- **Found during:** Task 3 GREEN verification, acceptance-criteria grep for the literal `−5` text
- **Issue:** The first `view.py` draft derived nudge labels from `f"{MINUS_SIGN}{abs(delta)}"` where `MINUS_SIGN = "−"` was its own line -- correct at runtime, but the literal glyph `−5` never appeared as contiguous text in the source file, so the plan's `grep -c "−5" python_app/view.py` acceptance check (requiring the literal glyph+digit sequence) failed.
- **Fix:** Replaced the dynamic construction with a `NUDGE_LABELS = {-5: "−5", -1: "−1", 1: "+1", 5: "+5"}` dict containing the literal characters, and used `NUDGE_LABELS[delta]` directly when building each button.
- **Files modified:** `python_app/view.py`
- **Verification:** `grep -c "−5" python_app/view.py` returns 2; `.venv/bin/pytest python_app/tests -q` still passes all 35 tests
- **Committed in:** `42a3e43` (Task 3 GREEN commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 - bugs found during this plan's own verification loop, both in test/view code written this plan, not pre-existing issues)
**Impact on plan:** Both fixes were necessary for the plan's own stated acceptance criteria to pass; neither changed scope or added functionality beyond what the plan specified. No scope creep.

## Issues Encountered

None beyond the two deviations documented above, resolved within the normal fix-attempt budget.

## User Setup Required

None - no external service configuration required. `.venv` is created locally from `python3.13` by `./run.sh` itself; `pytest==8.4.2`'s install was gated on and received the required human approval (Task 1, resolved in a prior dispatch) before any install ran.

## Next Phase Readiness

- `python_app/bpm_logic.py`'s `BpmController`/`Debouncer` and `python_app/view.py`'s `BpmWindow` are built exactly to the `<interfaces>` contract this plan's frontmatter specified, so Plan 03 can extend `BpmWindow`'s middle cell with the entry field and add keyboard shortcuts without changing either class's existing public surface.
- Task 3's `<human-check>` (dragging the slider/nudging while `supercollider/main.scd` plays, confirming the audible retempo and the On-top float-over-Zwift behavior) is deferred to end-of-phase UAT per `workflow.human_verify_mode=end-of-phase` -- not a blocker for Plan 03, but should be exercised before the phase is marked verified.
- No blockers for the next plan.

---
*Phase: 01-tempo-link-skeleton*
*Completed: 2026-10-09*

## Self-Check: PASSED

- All 5 created core files verified present on disk (`run.sh`, `python_app/tkcheck.py`, `python_app/bpm_logic.py`, `python_app/view.py`, `python_app/main.py`)
- All 4 task commits (`6b57567`, `c7e9230`, `45cc62f`, `42a3e43`) verified as ancestors of HEAD
- All plan acceptance criteria re-verified: `./run.sh --setup && .venv/bin/pytest python_app/tests -q` (35 tests pass), `python3.12 python_app/main.py` exits 1 with the Tk fix hint, `timeout 30 ./run.sh --port 57199 --exit-after 800` exits 0
- No stub patterns (`TODO`/`FIXME`/`placeholder`/"coming soon"/"not available") found in any created file (one false-positive grep hit on the literal error-message text "is not available" in tkcheck.py, which is the intended GUI-04 message, not a stub)
- Requirements: GUI-04 marked complete (sole declarer, this plan); GUI-01 and LINK-01 held back per the shared-ID gate (also declared by Plan 03, not yet summarized)
