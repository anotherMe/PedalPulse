---
phase: 05-library-selectors-in-the-gui
plan: 01
subsystem: ui
tags: [tkinter, optionmenu, osc, python-osc, library-selectors]

requires:
  - phase: 04-library-selection-in-the-engine
    provides: "OSCdef(\\pp_palette|\\pp_progression|\\pp_melody) -> ~ppSelect; frozen interface"
provides:
  - "Palette, Progression and Melody dropdown column in the PedalPulse window"
  - "library_logic.py: scan_library, to_wire, LibrarySelector (no tkinter, no OSC)"
  - "OscClient.send_selection(address, name)"
  - "Launch sends auto once to each of the three library addresses"
affects: [05-02, 05-03]

actuals:
  tokens: 6300
  tasks: 2
  commits: 2
plan_head_before: 44f4fa3e9e7e6d2ac180599f99425b6ec8b867ab
plan_head_after: 71b3ab194c621eab4d603424bb57e7fa998919cf
commits: 2

tech-stack:
  added: []
  patterns:
    - "LibrarySelector shaped like EpicController: listeners notified, then one fire-and-forget send; never raises on unknown names (engine validates)"
    - "functools.partial binds each category's OSC address so view.py never imports OSC"
    - "Launch test runs the real main.py in a subprocess against a bound loopback socket"

key-files:
  created:
    - python_app/library_logic.py
    - python_app/tests/test_main_launch.py
  modified:
    - python_app/config.py
    - python_app/osc_client.py
    - python_app/view.py
    - python_app/main.py
    - python_app/tests/test_view_tk.py

key-decisions:
  - "Dropdown width fixed at 20 characters so the window never resizes; a longer stem is cut on the closed button, full in the open menu"
  - "select() does not check the label against the folder scan; the engine is the validator"

patterns-established:
  - "Tuple padding only in pack(), never in a widget constructor"
  - "Menu rebuild is idempotent (menu.delete(0, 'end') first), ready for Plan 05-03's rescan on open"

requirements-completed: [GUI-05, GUI-06]

coverage:
  - id: D1
    description: "Window shows Palette, Progression, Melody dropdowns in a column right of the unchanged controls; window grows wider, not taller"
    requirement: GUI-05
    verification:
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_library_column_sits_right_of_unchanged_column"
        status: pass
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_library_column_order_and_initial_state"
        status: pass
    human_judgment: true
    rationale: "Visual look of the column (spacing, alignment) is not asserted by any test"
  - id: D2
    description: "Each dropdown lists Auto, classic, then its own folder's stems A-Z, exact stems"
    requirement: GUI-05
    verification:
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_each_dropdown_lists_its_own_folder"
        status: pass
    human_judgment: false
  - id: D3
    description: "A pick sends the exact stem (or auto) as one OSC string to the category's own address, only when the choice changes"
    requirement: GUI-06
    verification:
      - kind: integration
        ref: "python_app/tests/test_view_tk.py#test_melody_dropdown_pick_reaches_engine_over_udp"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_view_tk.py#test_same_stem_goes_only_to_its_own_category"
        status: pass
    human_judgment: false
  - id: D4
    description: "Launch sends the four existing values, then auto to /pp/palette, /pp/progression, /pp/melody; identical on a second launch"
    requirement: GUI-06
    verification:
      - kind: e2e
        ref: "python_app/tests/test_main_launch.py#test_launch_sends_initial_values_then_auto_to_each_library_address"
        status: pass
    human_judgment: false
  - id: D5
    description: "Dropdown width never changes the window width"
    requirement: GUI-05
    verification:
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_dropdown_width_is_fixed"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-10-12
status: complete
---

# Phase 5 Plan 01: Pick any library variation from the window Summary

**Palette, Progression and Melody OptionMenu column in the Tk window; a pick sends the exact file stem (or `auto`) as an OSC string to `/pp/palette`, `/pp/progression` or `/pp/melody`, and launch sends `auto` to all three.**

## Performance

- **Duration:** about 25 min
- **Started:** 2026-10-12T11:40:00Z (approx.)
- **Completed:** 2026-10-12T12:03:00Z
- **Tasks:** 2
- **Files modified:** 7 (2 new)

## Accomplishments
- Tracer: Melody dropdown wired through every layer (folder scan, `LibrarySelector`, `OscClient.send_selection`, Tk view, startup send), proven by a test where a real menu pick arrives as a UDP datagram on a bound loopback socket.
- Expanded to the three categories from `config.LIBRARY_CATEGORIES`; the existing control column is unchanged (`test_window_layout_order` passes unmodified) and the window grows wider only.
- Real-entry-point launch test: seven datagrams in order, identical across two launches (nothing remembered).
- Suite: 150 -> 157 tests, all passing. App stays send-only; no settings file.

## Task Commits

1. **Task 1 (tracer): Melody dropdown reaches the engine over UDP** - `bb30d9e` (feat)
2. **Task 2: Palette, Progression and Melody column, auto sent at launch** - `71b3ab1` (feat)

The tracer gate ran in interactive `end-of-phase` mode with an automated-only verify: all verify commands were re-run end to end (tracer test, full suite, `main.py --port 9 --exit-after 300` with no traceback) and passed, so expansion continued without a checkpoint.

## Files Created/Modified
- `python_app/library_logic.py` - `scan_library`, `to_wire`, `LibrarySelector` (pure logic)
- `python_app/config.py` - library addresses, `LIBRARY_ROOT`, `LIBRARY_CATEGORIES`, Auto label/name, dropdown width
- `python_app/osc_client.py` - `send_selection(address, name)` with the existing error-swallowing contract
- `python_app/view.py` - `selector_controllers` keyword, `_build_library_column`, `_refresh_library_menu`, side-by-side pack
- `python_app/main.py` - selectors built from `LIBRARY_CATEGORIES`, `send_initial()` after volume
- `python_app/tests/test_view_tk.py` - `_build_all` selector support; six new tests
- `python_app/tests/test_main_launch.py` - subprocess launch test

## Decisions Made
- Followed the plan as specified (fixed 20-character dropdown width with the documented cut-off trade-off; the engine validates names, so `select()` does not check the scan).

## Deviations from Plan

None - plan executed exactly as written. The only setup step was `./run.sh --setup` to build the gitignored `.venv` in the worktree, as the plan's step 0 describes.

## Issues Encountered
- The plan's per-plan commit ledger was written after the first task commit rather than before it; the base is the known spawn HEAD `44f4fa3`, so the measured commit count (2) is unaffected.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None.

## Threat Flags

None. No new network surface: sends reuse the existing loopback `OscClient`; no receive path or settings file was added.

## Next Phase Readiness
- Plan 05-02 can tighten `scan_library` to the engine's exact name rule (name and signature kept) and add controller/send contract tests.
- Plan 05-03 can add rescan on open via the menu `postcommand`; `_refresh_library_menu` is already idempotent.

## Self-Check: PASSED

- FOUND: python_app/library_logic.py, python_app/tests/test_main_launch.py
- FOUND commits: bb30d9e, 71b3ab1 (ancestors of HEAD)
- Full suite: 157 passed; `main.py --port 9 --exit-after 300` exits 0 with no traceback

---
*Phase: 05-library-selectors-in-the-gui*
*Completed: 2026-10-12*
