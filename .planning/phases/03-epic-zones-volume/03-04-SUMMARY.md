---
phase: 03-epic-zones-volume
plan: 04
subsystem: ui
tags: [tkinter, osc, volume, slider, gui-03]

# Dependency graph
requires:
  - phase: 03-epic-zones-volume
    provides: "Plan 02's EpicController/zone-row GUI pattern and Plan 03's engine-side OscClient.send_volume (/pp/volume, pre-limiter squared-taper gain), both extended here"
provides:
  - "GUI-03 complete: a Volume Scale in the window follows the drag live and sends the final value once on release (BpmController's slider-half pattern, mirrored exactly), launch sends 80.0 once"
  - "Phase 3 fully wired end to end: BPM, Start/Stop, EPIC zones and master volume all reachable from the one window, each following the same live-drag/send-on-release or send-on-click discipline"
affects: []

# Actuals (#2632)
actuals:
  tokens: 4377
  tasks: 2
  commits: 3

# Commit ledger (#3968) -- measured via git rev-list, not narrated
commits: 3
plan_head_before: d6266f77a2a9cb01778b77161d772448bdf8350c
plan_head_after: de941dc44cd3d8b6752d7533d7392a851eb88d19

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "VolumeController is a sibling of BpmController's slider half (not a generalisation of it): clamp_volume copies clamp_bpm's half-up-then-clamp contract verbatim, and VolumeController copies slider_moved/slider_released/send_initial's shape, with no nudge buttons or entry field since GUI-03 only asks for a slider."
    - "The Volume Scale is built the same way as the BPM Scale: takefocus=0 so Tk's own Scale arrow-key bindings cannot move the value without a release send, and so the root-level BPM arrow-key shortcuts are never shadowed by a focused Scale."

key-files:
  created:
    - python_app/tests/test_volume_logic.py
  modified:
    - python_app/config.py
    - python_app/bpm_logic.py
    - python_app/view.py
    - python_app/main.py
    - python_app/tests/test_view_tk.py

key-decisions:
  - "Followed the plan's TDD task structure for Task 1 exactly: wrote test_volume_logic.py first, confirmed RED via ImportError (VolumeController/clamp_volume do not exist yet), then implemented to GREEN. No REFACTOR commit was needed -- the implementation mirrors BpmController's existing shape with nothing to clean up."

requirements-completed: [GUI-03]

coverage:
  - id: D1
    description: "clamp_volume rounds half up then clamps to 0-100, raises ValueError on non-finite input; VolumeController tracks value, never sends on slider_moved, sends exactly once per slider_released (even several drag ticks followed by one release), send_initial sends unconditionally without notifying, and a falsy send return never rolls back the value"
    requirement: "GUI-03"
    verification:
      - kind: unit
        ref: "python_app/tests/test_volume_logic.py (24 tests, all pass)"
        status: pass
    human_judgment: false
  - id: D2
    description: "A Volume Scale (0-100, takefocus=0, label Volume) sits between the transport row and the status line, follows the drag live via slider_moved, sends once on ButtonRelease-1 via slider_released, and defaults to 80 at launch"
    requirement: "GUI-03"
    verification:
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_volume_scale_builds_at_default"
        status: pass
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_volume_drag_then_release_sends_once"
        status: pass
    human_judgment: false
  - id: D3
    description: "The Volume Scale takes no keyboard focus, so a drag-and-release leaves the root-level Up/Down/Shift-Up/Shift-Down BPM arrow-key shortcuts fully functional"
    requirement: "GUI-03"
    verification:
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_volume_slider_keeps_arrow_shortcuts_on_bpm"
        status: pass
    human_judgment: false
  - id: D4
    description: "The window's container packs its rows in the planned top-to-bottom order: BPM scale, nudge row, zone row, zone label, transport row, volume row, status line, On top checkbox"
    requirement: "GUI-03"
    verification:
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_window_layout_order"
        status: pass
    human_judgment: false
  - id: D5
    description: "main.py wires VolumeController(send=client.send_volume) into BpmWindow and calls volume.send_initial() last (after bpm/play/epic), so launching the app sends exactly one /pp/volume 80.0 after the other initial sends, never jumping the engine to full volume"
    requirement: "GUI-03"
    verification:
      - kind: other
        ref: "grep: main.py send_initial() calls, order confirmed controller -> play -> epic -> volume"
        status: pass
      - kind: e2e
        ref: "timeout 30 ./run.sh --port 57199 --exit-after 800 (exit 0)"
        status: pass
    human_judgment: false
  - id: D6
    description: "The whole Python test suite (150 tests: 122 pre-existing + 24 volume-logic + 4 Tk volume) stays green, with no skipped Tk tests, and the engine smoke suite (scripts/smoke_test.sh) still passes including the max-EPIC-max-volume no-clip check"
    requirement: "GUI-03"
    verification:
      - kind: unit
        ref: ".venv/bin/pytest python_app/tests -q -rs (150 passed, 0 skipped)"
        status: pass
      - kind: integration
        ref: "bash scripts/smoke_test.sh (SMOKE PASS, 65 CHECK OK lines, including 'max epic max volume no clip')"
        status: pass
    human_judgment: false
  - id: D7
    description: "End-of-phase listening acceptance: volume smoothness/evenness across the drag range, silence at 0, VO2 at full volume without audible distortion, and each EPIC zone sounding brighter/calmer and gliding cleanly"
    verification: []
    human_judgment: true
    rationale: "This project's workflow.human_verify_mode is end-of-phase (the project default) -- the plan's six-step human-check is a perceptual listening test (loudness evenness, zipper/click artifacts, distortion at full volume, musical brightness) that only a human with speakers/headphones and SuperCollider's IDE open can judge. Per the GSD checkpoints.md 'Default mode' contract, this executor ran every <automated> verification in the task's <verify> block (all passed, see D1-D6) and is leaving the <human-check> block for the end-of-phase UAT harvesting step rather than fabricating a listening judgment it cannot actually make. The six steps and their expected outcomes are reproduced verbatim in 'Next Phase Readiness' below for whoever performs the UAT pass."

duration: 25min (approximate)
completed: 2026-10-09
status: complete
---

# Phase 3 Plan 04: Volume slider in the app, and the phase acceptance listen Summary

**A Volume Scale (0-100, default 80) now sits in the PedalPulse window, following BpmController's exact live-drag/send-on-release pattern to drive `/pp/volume`, completing GUI-03 and wiring all four Phase 3 controls (BPM, Start/Stop, EPIC zones, volume) into one window.**

## Performance

- **Duration:** 25 min (approximate)
- **Started:** 2026-10-09T20:31:00Z (approximate)
- **Completed:** 2026-10-09T20:56:12Z
- **Tasks:** 2 completed
- **Files modified:** 6 (1 created, 5 modified)

## Accomplishments

- Added `clamp_volume` (half-up-then-clamp, raises on non-finite) and `VolumeController` (live drag never sends, release sends once, `send_initial` unconditional, no nudge/entry) to `python_app/bpm_logic.py`, test-first: 24 new tests in `python_app/tests/test_volume_logic.py`, confirmed RED (ImportError) before GREEN.
- Added `config.VOLUME_MIN`/`VOLUME_MAX`/`VOLUME_DEFAULT` (0/100/80), with the default strictly below the maximum so launching the app never jumps the engine to full volume.
- Added a 320px horizontal Volume `Scale` to `BpmWindow`, positioned between the transport row and the status line, wired to `VolumeController` exactly like the BPM Scale is wired to `BpmController` (`takefocus=0`, live `command=`, release-bound send).
- Wired `VolumeController(send=client.send_volume)` into `main.py`, with `volume.send_initial()` called last so the launch sequence sends BPM, play, EPIC, then volume -- one `/pp/volume 80.0` at startup.
- Extended `test_view_tk.py`'s `_build_all` fixture and added 4 new real-Tk-widget tests: default state, drag-then-release single send, arrow-key shortcuts staying on BPM after a volume drag, and the full window layout order.
- Ran the full automated verification surface for the plan: Python suite (150 passed, 0 skipped), `./run.sh --port 57199 --exit-after 800` (exit 0), and the SuperCollider headless smoke suite (`SMOKE PASS`, 65 `CHECK OK:` lines including `max epic max volume no clip`).

## Task Commits

1. **Task 1 RED: add failing tests for clamp_volume and VolumeController** - `623197b` (test)
2. **Task 1 GREEN: implement clamp_volume and VolumeController** - `17a06b7` (feat)
3. **Task 2: wire VolumeController to a Volume Scale in the window** - `de941dc` (feat)

_No separate plan-metadata commit yet (worktree mode): the orchestrator commits this SUMMARY.md after merge._

## Files Created/Modified

- `python_app/tests/test_volume_logic.py` - new: 24 pure-logic tests for `clamp_volume` and `VolumeController`
- `python_app/config.py` - `VOLUME_MIN = 0`, `VOLUME_MAX = 100`, `VOLUME_DEFAULT = 80`
- `python_app/bpm_logic.py` - `clamp_volume`, `class VolumeController` (mirrors `BpmController`'s slider half)
- `python_app/view.py` - `BpmWindow` gains `volume_controller` kwarg, `volume_row`/`volume_var`/`volume_scale` attributes, `_build_volume_row`/`_on_volume_changed` methods
- `python_app/main.py` - `VolumeController(send=client.send_volume)` wiring, `volume.send_initial()` last in the launch sequence
- `python_app/tests/test_view_tk.py` - `_build_all` returns `volume`/`volume_sent`; 4 new real-Tk tests

## Decisions Made

- Followed the plan's TDD structure for Task 1 exactly as specified: RED (test file first, confirmed failing via `ImportError` since the names did not exist), then GREEN (implementation). No REFACTOR commit -- the implementation is a direct mirror of `BpmController`'s existing, already-clean shape, with nothing to clean up.
- No other deviations: `clamp_volume` and `VolumeController` are copies of `clamp_bpm`/`BpmController`'s slider contract as the plan specified (sibling-over-refactor, per 03-RESEARCH.md Gray Areas and Phase 2 precedent), not a generalisation.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - the Volume slider is fully wired end to end (view -> VolumeController -> OscClient.send_volume -> `/pp/volume`), with no placeholder values or unwired data paths.

## Threat Flags

None beyond what the plan's own `<threat_model>` already covers (T-03-14 through T-03-16, T-03-SC) -- all dispositioned `mitigate`/`accept` in the plan and verified: T-03-14 (slider-flood DoS) by `test_slider_moved_sets_notifies_and_never_sends`/`test_several_drag_ticks_then_one_release_sends_exactly_once` plus the Tk `test_volume_drag_then_release_sends_once`; T-03-15 (non-finite/out-of-range tampering) by `test_clamp_volume_rejects_non_finite` and the bounded `Scale`; T-03-16 (launch-volume hearing safety) by `test_volume_config_constants` (`VOLUME_DEFAULT` strictly below `VOLUME_MAX`) and the engine-side limiter proven in Plan 03.

## Next Phase Readiness

- GUI-03 is complete. Phase 3 requirements EPIC-01, EPIC-02, EPIC-03 (Plans 01-02) and GUI-03 (Plans 03-04) are all delivered, and every automated verification this plan's `<verify>` block specifies has passed: the full Python suite (150 tests, 0 skipped), the app launching and exiting cleanly via `./run.sh`, and the SuperCollider smoke suite (65 `CHECK OK:` lines, `SMOKE PASS`, including the phase's core safety proof `max epic max volume no clip`).
- **End-of-phase human listening acceptance is outstanding and must be performed before Phase 3 is considered UAT-complete.** This project's `workflow.human_verify_mode` is `end-of-phase` (the GSD default), so this executor ran every automated check in the task's `<verify>` block and is deliberately leaving the plan's `<human-check>` block for the end-of-phase UAT pass rather than fabricating a listening judgment. Reproduced here verbatim for that pass:
  1. Set macOS output level low enough that volume 80 is comfortable (step 4 goes to 100). Evaluate `supercollider/main.scd` in the SuperCollider IDE, then run `./run.sh`.
  2. Check the window: Volume slider at 80, Recovery selected. Listen for 8 bars.
  3. Drag the Volume slider slowly from 80 down to 20 and release, then from 20 up to 100 and release. Then make several quick drags and releases.
  4. Set Volume to 0, then back to 80.
  5. Select VO2 and set Volume to 100. Listen for at least 8 bars.
  6. At Volume 80, click through Recovery, Endurance, Tempo, Threshold, VO2 and back down, then click three zones quickly in a row.
  7. Optional: ride a few minutes with Zwift running, changing zones and volume along the way, watching the IDE's CPU readout.
  Expected: loudness follows each release within a fraction of a second with no click/zipper/stepping and roughly equal perceived loudness per equal slider move; volume 0 is silent and 80 brings the groove back; VO2 at full volume is loud/bright/energetic with no harsh clipping or pumping; each zone up is brighter/more energetic and each zone down is darker/calmer, gliding cleanly with volume staying put; no audio dropouts and modest CPU. If the listener reports unevenness, a too-dark/harsh zone, or richness indistinguishable from brightness, record it as follow-up input rather than changing code to satisfy taste during this pass -- the taper is the single `~ppVolumeAmp` line and the EPIC constants are in `\ppFx`/`~ppEpicLagSecs`, both documented as one-line, reversible edits in Plan 03's SUMMARY.
- No blockers for Phase 4. `BpmController`/`PlayController`/`EpicController`/`VolumeController` now share one consistent live-drag/send-on-release-or-click/`send_initial` shape that Phase 4 (connection indicator, live BPM/EPIC display, 60-minute soak) can build on without new patterns.

---
*Phase: 03-epic-zones-volume*
*Completed: 2026-10-09*
