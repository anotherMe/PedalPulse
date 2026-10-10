---
phase: 03-epic-zones-volume
plan: 02
subsystem: ui
tags: [tkinter, epic, zone-presets, osc, arrow-key-fix]

# Dependency graph
requires:
  - phase: 03-epic-zones-volume (plan 01)
    provides: "/pp/epic end to end in the engine, OscClient.send_epic(epic) -> bool"
provides:
  - "EpicController: pure zone/value/zone_names state + send policy, mirrors PlayController's shape"
  - "config.EPIC_ZONES / config.EPIC_DEFAULT_ZONE zone preset map"
  - "Five zone buttons in BpmWindow, selected-zone highlight (bold font + sunken relief + caption), wired to EpicController.select_zone"
  - "WR-01 fixed: BPM entry has its own break bindings for Up/Down/Shift-Up/Shift-Down, so arrow keys no longer nudge BPM or clobber typed text while the entry has focus"
affects: ["03-03", "03-04"]

# Actuals (#2632)
actuals:
  tokens: 5840
  tasks: 2
  commits: 3
  plan_head_before: c0d2d9be8ebef26e6e01327fd15ee342ae3cdb72
  plan_head_after: e83685ef11106a697bf56cb3ea7c5172fdb10611

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "EpicController mirrors PlayController exactly: discrete-click state tracked client-side, notify-then-send only on a real change, no debounce, send_initial() unconditional at launch without notifying"
    - "Selected-state highlight via a bold tkinter.font copy + relief + a plain-text caption, not relief alone -- this Mac's Tk 9.0.3 (aqua) buttons were already known (Phase 2 UI review) to render relief poorly, so the font/caption pairing is the actually-visible signal"
    - "Entry-scoped key bindings that return \"break\" take precedence over root-level bindings for the same sequence while that widget has focus -- the same idiom used for <Return>/<KP_Enter>/<FocusOut>, now extended to the four arrow sequences for WR-01"

key-files:
  created:
    - python_app/tests/test_epic_logic.py
  modified:
    - python_app/config.py
    - python_app/bpm_logic.py
    - python_app/view.py
    - python_app/main.py
    - python_app/tests/test_view_tk.py

key-decisions:
  - "Selected-zone highlight uses a bold font copy + caption (not relief alone), confirmed during planning that this Mac's Tk 9.0.3 aqua buttons render font-weight changes reliably where relief is often invisible -- same lesson as the Phase 2 UI review."
  - "WR-01 fixed with entry-scoped \"break\" bindings rather than touching the root-level handler -- Tk's focus-widget-first dispatch means the entry's own binding runs before root's, and it was the review's own suggested fix."

patterns-established:
  - "Sibling-controller pattern: a third pure state class (EpicController) added to bpm_logic.py alongside BpmController/PlayController with zero Tk coupling, zero new test-infrastructure cost."

requirements-completed: [EPIC-03]

coverage:
  - id: D1
    description: "config.EPIC_ZONES maps five named zones (Recovery 10, Endurance 30, Tempo 50, Threshold 75, VO2 100) to a preset EPIC value, strictly increasing, VO2 exactly 100, default zone Recovery"
    requirement: "EPIC-03"
    verification:
      - kind: unit
        ref: "python_app/tests/test_epic_logic.py#test_zone_map_has_expected_names_and_values"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_epic_logic.py#test_zone_values_strictly_increasing_within_0_100_vo2_is_100"
        status: pass
    human_judgment: false
  - id: D2
    description: "EpicController.select_zone sends the preset as a float only on a real zone change (no-op on repeat/same-zone), notifies listeners before sending, and raises ValueError before any state change for an unknown or empty zone name or a bad construction argument"
    requirement: "EPIC-03"
    verification:
      - kind: unit
        ref: "python_app/tests/test_epic_logic.py#test_select_zone_in_turn_sends_each_preset_as_float"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_epic_logic.py#test_select_zone_same_zone_is_a_noop"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_epic_logic.py#test_recovery_endurance_recovery_sends_exactly_two_values"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_epic_logic.py#test_listener_called_before_send_on_change"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_epic_logic.py#test_select_zone_unknown_name_raises_value_error_and_leaves_state_untouched"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_epic_logic.py#test_construction_with_empty_zone_map_raises_value_error"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_epic_logic.py#test_construction_with_initial_zone_missing_from_map_raises_value_error"
        status: pass
    human_judgment: false
  - id: D3
    description: "Five zone buttons appear in the window in EPIC_ZONES order, the selected zone is clearly highlighted (bold font + sunken relief) and captioned \"Zone: <name>\", clicking a button sends that zone's preset once over /pp/epic via OscClient.send_epic, and the default zone is sent once at launch"
    requirement: "EPIC-03"
    verification:
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_zone_row_builds_in_order_with_recovery_selected"
        status: pass
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_zone_click_highlights_and_sends_once"
        status: pass
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_each_zone_button_sends_its_preset"
        status: pass
    human_judgment: true
    rationale: "The automated Tk suite proves the mechanism end to end (preset values sent, highlight/caption state set, launch-time send). Whether raising/lowering EPIC zones actually sounds brighter/darker and glides smoothly by ear, and whether the highlight is visually clear on this Mac's Aqua theme, is the plan's <human-check> listening test -- deferred to end-of-phase UAT consolidation per workflow.human_verify_mode=end-of-phase (see Issues Encountered below)."
  - id: D4
    description: "WR-01 (Phase 1 review): Up/Down/Shift-Up/Shift-Down pressed while the BPM entry has keyboard focus neither nudge BPM nor overwrite the typed text; with focus elsewhere (including immediately after a zone click, since zone buttons take no focus) the shortcuts still nudge BPM"
    requirement: "EPIC-03"
    verification:
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_arrow_keys_do_not_nudge_while_entry_focused"
        status: pass
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_zone_click_keeps_arrow_shortcuts_on_bpm"
        status: pass
    human_judgment: false
  - id: D5
    description: "Every existing BPM and Start/Stop widget test still passes, and ./run.sh launches and exits cleanly with the new zone row"
    requirement: "EPIC-03"
    verification:
      - kind: unit
        ref: ".venv/bin/pytest python_app/tests -q -rs"
        status: pass
      - kind: integration
        ref: "timeout 30 ./run.sh --port 57199 --exit-after 800"
        status: pass
    human_judgment: false

duration: 15min
completed: 2026-10-09
status: complete
---

# Phase 3 Plan 02: Five zone buttons in the app Summary

**Five EPIC zone preset buttons (Recovery/Endurance/Tempo/Threshold/VO2) now live in the Tkinter window, each sending its preset value once over `/pp/epic` through Plan 01's `OscClient.send_epic`, with a bold-font + sunken-relief + "Zone: <name>" caption highlight, and the Phase 1 arrow-key-clobbers-entry bug (WR-01) is fixed.**

## Performance

- **Duration:** ~15 min (approximate)
- **Completed:** 2026-10-09T20:22:23Z
- **Tasks:** 2 completed
- **Files modified:** 6 (5 modified, 1 created)

## Accomplishments

- Added `config.EPIC_ZONES` (Recovery 10, Endurance 30, Tempo 50, Threshold 75, VO2 100) and `config.EPIC_DEFAULT_ZONE = "Recovery"`, matching the engine's boot default and Plan 01's `/pp/epic` contract.
- Added `bpm_logic.EpicController`, a sibling to `BpmController`/`PlayController`: tracks the current zone, notifies listeners then sends the preset as a `float` only on a real change, raises `ValueError` before any state change for an unknown/empty zone name or a bad construction argument, and `send_initial()` sends unconditionally without notifying.
- Wrote 16 pure-logic tests (`test_epic_logic.py`) test-first (RED: `EpicController`/`config.EPIC_ZONES` did not exist; GREEN: all pass) covering construction, real-change sends, same-zone no-op, double-select-once, listener-before-send ordering, unknown/empty-name and bad-construction `ValueError`s, `send_initial` semantics, fire-and-forget send, and an injected zone map.
- Built the five-button zone row in `view.py` (`_build_zone_row`, `_on_zone_changed`), packed left-to-right in `EPIC_ZONES` order between the nudge row and the transport row, each button `takefocus=0` and wired via `command=lambda z=name: epic_controller.select_zone(z)`. The selected zone gets a bold font copy + `relief="sunken"`; every other zone gets the normal-weight font + `relief="raised"`; a `zone_label` below the row reads `"Zone: <name>"`.
- Wired `EpicController(send=client.send_epic)` into `main.py`, passed `epic_controller=epic` to `BpmWindow`, and called `epic.send_initial()` after `play.send_initial()` so the default zone's value reaches the engine once at launch.
- Fixed Phase 1 review finding WR-01 before adding the new controls: the BPM entry now has its own `<Up>`/`<Down>`/`<Shift-Up>`/`<Shift-Down>` bindings returning `"break"`, so arrow keys typed into the entry no longer nudge BPM or overwrite the typed text. The root-level shortcuts still fire whenever focus is anywhere else, confirmed to keep working immediately after a zone-button click (zone buttons take no focus).
- Added 5 new Tk widget tests (`test_view_tk.py`) covering zone-row build order/highlight/caption, per-click sends, repeated-and-cumulative zone sends, the WR-01 entry-focus guard (with a positive control proving the same key nudges BPM once focus leaves the entry), and zone-click + arrow-shortcut independence.
- Added `_build_all(root, status_text)` returning a `types.SimpleNamespace(window, controller, sent, play, play_sent, epic, epic_sent)`; `_build_window` is now implemented on top of it, so all nine pre-existing Tk tests kept passing unchanged.

## Task Commits

1. **Task 1: EpicController maps each zone to its preset and sends it only on a real zone change** - `d62661d` (test, RED), `3bf1bcf` (feat, GREEN) — no REFACTOR commit; the implementation needed no cleanup after GREEN.
2. **Task 2: User clicks a zone button in the window, sees it selected and hears the music move to that zone, and arrow keys no longer clobber the BPM entry** - `e83685e` (feat)

_No separate plan-metadata commit yet (worktree mode): the orchestrator commits this SUMMARY.md after merge._

## Files Created/Modified

- `python_app/config.py` - `EPIC_ZONES`, `EPIC_DEFAULT_ZONE`
- `python_app/bpm_logic.py` - `class EpicController` (zone, value, zone_names, add_listener, select_zone, send_initial)
- `python_app/tests/test_epic_logic.py` - 16 pure-logic tests for the zone map and `EpicController` (new file)
- `python_app/view.py` - `_build_zone_row`, `_on_zone_changed`, `zone_row`/`zone_buttons`/`zone_label`/`zone_font`/`zone_font_selected`, WR-01 entry-scoped arrow-key "break" bindings, `transport_row` pady 4->8
- `python_app/main.py` - `EpicController(send=client.send_epic)` wiring, `epic.send_initial()` after `play.send_initial()`
- `python_app/tests/test_view_tk.py` - `_build_all` helper; 5 new zone/WR-01 tests; `_build_window` reimplemented on top of `_build_all`

## Decisions Made

- Selected-zone highlight uses a bold font copy + caption, not relief alone (Gray Areas default adopted from RESEARCH.md): this Mac's Tk 9.0.3 aqua buttons were already known from the Phase 2 UI review to render `relief` poorly, so the bold-font + "Zone: <name>" caption pairing is the signal that actually renders visibly; `relief` is still set as a secondary cue for other platforms/themes.
- WR-01 fixed with entry-scoped "break" bindings (the review's own suggested fix) rather than adding focus-tracking state to the root-level handler — Tk's focus-widget-first dispatch means the entry's own binding runs before root's for the same key sequence, so no extra guard logic was needed.

## Deviations from Plan

None - plan executed exactly as written. `EpicController` and the zone row match the plan's behavior/interface spec, both acceptance-criteria gates passed on the first implementation (no auto-fix cycles needed), and the WR-01 fix matched the review's own suggested approach.

## Issues Encountered

- **Task 2's `<verify><human-check>` (the six-step listening/visual check) was not performed by this executor.** This project's `.planning/config.json` sets `workflow.human_verify_mode: "end-of-phase"` (the default per #3309): the planner embeds `<human-check>` content inside an `auto` task's `<verify>` specifically so it is *not* run mid-flight by the executor, but harvested at end-of-phase by the verifier and consolidated into the phase's UAT.md for one batched human review. This plan's executor ran only the `<automated>` portion of Task 2's verify (`pytest` + `./run.sh --exit-after`, both green) per that mode's contract; the six listening/visual steps (zones brighten/darken by ear, glide smoothly including rapid back-to-back clicks, highlight visible on macOS, arrow keys respect the entry while typing) remain open for the Phase 3 end-of-phase UAT pass. This is coverage item D3's `human_judgment: true` entry above, not a defect in this plan's automated proof.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - `EpicController`, the zone map, and the zone row are fully wired production code: real `select_zone` calls real `OscClient.send_epic`, the button commands are not placeholders, and no hardcoded empty/mock data flows to the UI.

## Next Phase Readiness

- EPIC-03 is implemented end to end (GUI click -> `EpicController.select_zone` -> `OscClient.send_epic` -> Plan 01's engine chain) and covered by 116 automated tests (16 new logic + 5 new Tk + 95 pre-existing), all green, no skips.
- The Phase 1 WR-01 finding is closed before any further GUI controls are added, as STATE.md requested.
- Six listening/visual human-check steps for this plan are queued for the Phase 3 end-of-phase UAT consolidation (`human_verify_mode: end-of-phase`), alongside Plan 01's own deferred listening checks.
- No blockers for Plan 03 (volume control) or Plan 04: the zone row's layout (`nudge_row` -> `zone_row` (pady=8) -> `transport_row` (pady=8)) and the `_build_zone_row`/`_on_zone_changed` listener-driven highlight pattern are stable extension points for the next control row.

---
*Phase: 03-epic-zones-volume*
*Completed: 2026-10-09*

## Self-Check: PASSED

- FOUND: python_app/config.py
- FOUND: python_app/bpm_logic.py
- FOUND: python_app/tests/test_epic_logic.py
- FOUND: python_app/view.py
- FOUND: python_app/main.py
- FOUND: python_app/tests/test_view_tk.py
- FOUND: commit d62661d (Task 1 RED, ancestor of HEAD)
- FOUND: commit 3bf1bcf (Task 1 GREEN, ancestor of HEAD)
- FOUND: commit e83685e (Task 2, ancestor of HEAD)
- CONFIRMED: `.venv/bin/pytest python_app/tests -q -rs` exits 0, 116 passed, 0 skipped
- CONFIRMED: `timeout 30 ./run.sh --port 57199 --exit-after 800` exits 0
