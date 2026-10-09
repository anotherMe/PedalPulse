---
phase: 02-full-groove-smooth-tempo
plan: 02
subsystem: ui
tags: [tkinter, python-osc, transport, tdd]

# Dependency graph
requires:
  - phase: 02-full-groove-smooth-tempo
    provides: "Plan 01's end-to-end /pp/play transport (OscClient.send_play, OSCdef(\\pp_play), ~ppStart/~ppStop)"
provides:
  - "python_app/bpm_logic.py: PlayController (playing state, add_listener, set_playing, toggle, send_initial)"
  - "python_app/view.py: Start/Stop button in BpmWindow (PLAY_LABELS, transport_row, play_button, _on_playing_changed)"
  - "python_app/main.py: PlayController wired to OscClient.send_play, initial play state sent on launch after BPM"
  - "python_app/tests/test_view_tk.py: _make_window_with_play helper and real Tk widget coverage for the button"
affects: [02-03-tempo-glide, 02-04-full-groove-and-epic-fx]

# Actuals (#2632)
actuals:
  tokens: 3443
  tasks: 2
  commits: 3
plan_head_before: 285ac58d39ea8f857db160e43d94fb1d88d43152
plan_head_after: d62ff8a163d549282a1170869ea7f75f88ec8655

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PlayController mirrors BpmController's track-value/notify-on-change/caller-decides-send-timing shape, but with no debounce -- every discrete click or set_playing call is exactly one send"
    - "Listeners are always notified before send on a state change (observable via an event-log test), matching the ordering contract the GUI relies on to repaint the button label before the network call"
    - "One toggle button whose label names the action a click will perform (not two separate buttons), consistent with Phase 1's compact-window decision (D-12)"

key-files:
  created:
    - python_app/tests/test_play_logic.py
  modified:
    - python_app/bpm_logic.py
    - python_app/view.py
    - python_app/main.py
    - python_app/tests/test_view_tk.py

key-decisions:
  - "PlayController.set_playing/toggle send int(1|0), never a bool -- test_send_value_is_always_a_real_int_never_a_bool asserts type(value) is int, matching OscClient.send_play's int-coercion contract from Plan 01"
  - "play_button uses takefocus=0 and adds no key binding, so it cannot interfere with Phase 1's Up/Down/Shift-Up/Shift-Down BPM shortcuts or with WR-01 (unrelated, still open, deferred per STATE.md)"
  - "main.py calls play.send_initial() immediately after controller.send_initial(), so the GUI announces BPM then play state once on every launch (GUI-as-source-of-truth, Phase 1 D-23 spirit)"

patterns-established:
  - "Pattern: a transport/state controller with no network import (PlayController) is unit-tested with a plain list as the send spy -- no mocking -- exactly like BpmController; only the Tk wiring itself needs the real-Tk widget layer"

requirements-completed: [GUI-02]

coverage:
  - id: D1
    description: "PlayController tracks play/stop intent and sends /pp/play as an int only on a real state change, with listeners notified before send and no rollback on a falsy send return"
    requirement: "GUI-02"
    verification:
      - kind: unit
        ref: "python_app/tests/test_play_logic.py (13 tests: construction defaults, toggle, set_playing idempotency/coercion, int-vs-bool send value, listener-before-send ordering, send_initial, fire-and-forget)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The window shows one Start/Stop toggle button whose label always names the action the next click will perform; each click is one discrete send (no debounce) and the last value sent matches the label shown"
    requirement: "GUI-02"
    verification:
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_play_button_toggles_with_one_send_per_click, test_play_button_follows_controller_state"
        status: pass
    human_judgment: false
  - id: D3
    description: "The Start/Stop button takes no keyboard focus and adds no key binding, so Phase 1's arrow-key BPM shortcuts behave exactly as before"
    requirement: "GUI-02"
    verification:
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_play_button_takes_no_focus"
        status: pass
    human_judgment: false
  - id: D4
    description: "main.py wires PlayController to OscClient.send_play and sends the initial play state once on launch, right after the initial BPM send; the app still never starts, watches or stops the engine process"
    requirement: "GUI-02"
    verification:
      - kind: other
        ref: "grep acceptance criteria: PlayController(send=client.send_play) and play.send_initial() present in main.py; ! grep -qE 'subprocess|Popen|os\\.system|os\\.kill' across main.py/view.py/bpm_logic.py/osc_client.py"
        status: pass
      - kind: integration
        ref: "timeout 30 ./run.sh --port 57199 --exit-after 800 (launch check, exits 0)"
        status: pass
    human_judgment: true
    rationale: "Wiring and the no-crash launch check are proven automatically, but the actual audible click -> engine stop/restart is this plan's own <verification> section defers to Plan 04's end-of-phase listening check against a running engine -- consistent with Plan 01's SUMMARY, which deferred the same for its half of the transport."
  - id: D5
    description: "All Phase 1 Python tests still pass and the real Tk 9 widget tests run with none skipped"
    verification:
      - kind: unit
        ref: ".venv/bin/pytest python_app/tests -q -rs (87 passed, 0 skipped)"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-10-09
status: complete
---

# Phase 2, Plan 02: Start/Stop button in the app Summary

**A `PlayController` (test-first, RED->GREEN) tracks play/stop intent with int-only sends, wired to a single Start/Stop toggle button in the Tkinter window that always names the next click's action, and to `OscClient.send_play` in `main.py` with the play state announced once on launch.**

## Performance

- **Duration:** 25 min (approx.)
- **Started:** 2026-10-09T10:58:00Z (approx.)
- **Completed:** 2026-10-09T11:23:33Z
- **Tasks:** 2
- **Files modified:** 4 modified, 1 created

## Accomplishments
- `PlayController` in `python_app/bpm_logic.py`: `playing` property, `add_listener`, `set_playing`, `toggle`, `send_initial` -- tracks value, notifies listeners before sending, sends an `int` (never a `bool`) only on an actual state change, no debounce
- 13 pure-logic tests in `python_app/tests/test_play_logic.py`, written first and confirmed failing (`ImportError: cannot import name 'PlayController'`) before any implementation existed
- `BpmWindow` gained a `transport_row` holding a single `play_button` (`takefocus=0`) whose text is `PLAY_LABELS[playing]` ("Stop" while playing, "Start" while stopped), kept in sync by `_on_playing_changed`
- `main.py` creates `PlayController(send=client.send_play)`, passes it to `BpmWindow`, and calls `play.send_initial()` right after `controller.send_initial()` -- the app announces BPM then play state once per launch
- 3 new real-Tk-9 widget tests in `test_view_tk.py` cover one-send-per-click toggling, following external `set_playing` calls, and that the button takes no focus and does not disturb the Phase 1 arrow-key BPM shortcuts
- Full suite: 87 passed, 0 skipped (71 Phase 1 + 13 new PlayController + 3 new widget tests); `timeout 30 ./run.sh --port 57199 --exit-after 800` exits 0

## Task Commits

Each task was committed atomically (TDD: test commit, then implementation commit for Task 1):

1. **Task 1 RED: add failing tests for PlayController** - `924838e` (test)
2. **Task 1 GREEN: implement PlayController play/stop state and send policy** - `0729f8f` (feat)
3. **Task 2: add Start/Stop button wired to PlayController** - `d62ff8a` (feat)

_No REFACTOR commit was needed -- the GREEN implementation was already minimal and matched the established `BpmController` shape with no obvious cleanup._

**Plan metadata:** committed alongside this SUMMARY (worktree mode; STATE.md/ROADMAP.md excluded, owned by the orchestrator).

## Files Created/Modified
- `python_app/bpm_logic.py` - added `class PlayController` after `BpmController`; updated module docstring to cover GUI-02
- `python_app/tests/test_play_logic.py` (new) - 13 pure-logic tests for `PlayController`
- `python_app/view.py` - `PLAY_LABELS` constant, `BpmWindow(..., *, play_controller)`, `transport_row`/`play_button`, `_on_playing_changed`
- `python_app/main.py` - imports `PlayController`, wires it to `client.send_play`, calls `play.send_initial()` after `controller.send_initial()`
- `python_app/tests/test_view_tk.py` - `_build_window`/`_make_window_with_play` helpers (existing `_make_window` unchanged in signature/return), 3 new widget tests

## Decisions Made
- Followed the plan's TDD instruction literally: wrote `test_play_logic.py` against a not-yet-existing `PlayController` and confirmed the resulting `ImportError` as the intended RED evidence, per the plan's own Task 1 action text ("Run it and confirm it fails because `PlayController` does not exist"). `workflow.tdd_mode` is not enabled in `.planning/config.json`, so the formal `gsd_run check tdd-red-evidence` report-based gate did not apply; the RED/GREEN/REFACTOR discipline itself was still followed and is documented here for traceability.
- `_make_window_with_play` returns `(window, play_controller, play_sent)` exactly as the plan's `<interfaces>` block specifies; a small private `_build_window` helper factors out the shared window-construction code so the existing `_make_window` keeps its original `(window, controller, sent)` return with no behavior change for the 8 pre-existing tests.

## Deviations from Plan

None - plan executed exactly as written. Both tasks' acceptance criteria and verification commands passed without needing a Rule 1-3 fix.

## Issues Encountered
This worktree had no `.venv` (worktrees do not share the main checkout's gitignored `.venv`, same as Plan 01's worktree). Created one fresh via `python3.13 -m venv .venv && .venv/bin/pip install -r python_app/requirements.txt -r python_app/requirements-dev.txt` before running any tests -- local test infrastructure, not a plan deliverable, and `.venv/` stays gitignored.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- GUI-02 is now complete end to end: the engine half (Plan 01, `/pp/play` -> `~ppStart`/`~ppStop`) and the app half (this plan, the Start/Stop button) both exist and are unit/widget-tested in isolation.
- The audible, human-judgment confirmation that pressing Stop/Start in the running app actually stops/restarts a live engine is explicitly deferred to Plan 04's end-of-phase listening check, consistent with this plan's own `<verification>` section and with Plan 01's SUMMARY, which deferred the engine-side half of the same check.
- No new blockers. STATE.md's open WR-01 finding (arrow keys nudging BPM while the entry has focus) remains untouched and unworsened -- the new button takes no focus and adds no key binding, as the plan required.

---
*Phase: 02-full-groove-smooth-tempo*
*Completed: 2026-10-09*

## Self-Check: PASSED

- FOUND: python_app/bpm_logic.py
- FOUND: python_app/tests/test_play_logic.py
- FOUND: python_app/view.py
- FOUND: python_app/main.py
- FOUND: python_app/tests/test_view_tk.py
- FOUND: 924838e (ancestor of HEAD)
- FOUND: 0729f8f (ancestor of HEAD)
- FOUND: d62ff8a (ancestor of HEAD)
- Acceptance criteria re-verified: all `grep` checks for both tasks pass; `.venv/bin/pytest python_app/tests -q -rs` exits 0 (87 passed, 0 skipped)
- Plan-level `<verification>` re-run: pytest green (87 passed, 0 skipped); `timeout 30 ./run.sh --port 57199 --exit-after 800` exits 0
