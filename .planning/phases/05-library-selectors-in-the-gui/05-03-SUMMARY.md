---
phase: 05-library-selectors-in-the-gui
plan: 03
subsystem: ui
tags: [tkinter, optionmenu, postcommand, library-selectors, keyboard-focus]

requires:
  - phase: 05-library-selectors-in-the-gui
    provides: "Dropdown column and idempotent _refresh_library_menu (05-01); final scan_library rule (05-02)"
provides:
  - "Each dropdown rebuilds its list from a fresh folder scan every time it opens (menu postcommand)"
  - "Tests for rescan, vanished selected file, missing folder, and GUI-07 keyboard focus"
  - "Library README section 'Pick a variation from the app'"
affects: [phase-05-verification]

actuals:
  tokens: 5500
  tasks: 2
  commits: 2
plan_head_before: cea8ec4801d54251774dffeaa743d41766afcf2c
plan_head_after: 94501d461165864e6509c63ff808871045e49760
commits: 2

tech-stack:
  added: []
  patterns:
    - "Tk menu postcommand with default-argument capture (s=selector, v=var, m=menu) rebuilds each menu from its own selector"
    - "Tests run the real registered post command via root.tk.eval(menu.cget('postcommand')); picks use menu.invoke, never synthetic clicks"

key-files:
  created: []
  modified:
    - python_app/view.py
    - python_app/tests/test_view_tk.py
    - supercollider/library/README.md

key-decisions:
  - "The rebuild never sets the StringVar, so a selected name whose file was deleted stays shown on the closed dropdown"
  - "No watcher, timer or thread: the rescan happens only when the rider opens the dropdown (D-08)"

requirements-completed: [GUI-05, GUI-06, GUI-07]

coverage:
  - id: D1
    description: "A file added while the app runs appears the next time its dropdown is opened; a removed file disappears; repeated opens never duplicate names"
    requirement: GUI-05
    verification:
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_new_file_appears_on_next_open"
        status: pass
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_rebuild_is_idempotent"
        status: pass
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_every_dropdown_rebuilds_on_open"
        status: pass
    human_judgment: true
    rationale: "The native macOS menu cannot be opened by a test; synthetic clicks never reach tk::MbPost, so the real click is the rider's end-of-phase check"
  - id: D2
    description: "A deleted selected file keeps its label and another pick still sends; a vanished library folder shows Auto only on next open; nothing raises"
    requirement: GUI-06
    verification:
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_deleted_selected_file_keeps_its_label_and_another_pick_still_sends"
        status: pass
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_missing_folder_shows_auto_only_after_reopen"
        status: pass
    human_judgment: false
  - id: D3
    description: "Dropdowns take no focus and add no key bindings; Up/Down/Shift-Up/Shift-Down still nudge BPM by 1/1/5/5 after using each dropdown"
    requirement: GUI-07
    verification:
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_dropdowns_take_no_focus_and_add_no_key_bindings"
        status: pass
      - kind: automated_ui
        ref: "python_app/tests/test_view_tk.py#test_arrow_keys_still_nudge_bpm_after_using_each_dropdown"
        status: pass
    human_judgment: true
    rationale: "Keyboard focus after a real native menu click is only partly reachable from tests (menu.invoke plus focus_force); the real click is the rider's check"
  - id: D4
    description: "Engine still refuses unknown and invalid names while playing; library guard passes; no engine or variation file changed in this phase"
    requirement: GUI-06
    verification:
      - kind: integration
        ref: "./scripts/check.sh --library-only (CHECK OK: unknown name, invalid names ignored, python one-liner, library guard)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Library README explains picking from the app, rescan on open, and that re-picking the selected name does nothing"
    requirement: GUI-05
    verification: []
    human_judgment: true
    rationale: "Plain-language documentation quality is a judgment call for the rider"

duration: 20min
completed: 2026-10-12
status: complete
---

# Phase 5 Plan 03: A new file shows up when I open the dropdown, and the BPM keys keep working Summary

**Each Palette, Progression and Melody menu rebuilds from a fresh folder scan in its Tk `postcommand` (no watcher, timer or thread), survives deleted files and folders, and is proven to leave the BPM arrow shortcuts untouched.**

## Performance

- **Duration:** about 20 min
- **Tasks:** 2
- **Files modified:** 3 (no new files)
- **Suite:** 181 -> 188 tests, all passing

## Accomplishments
- `menu.configure(postcommand=lambda s=selector, v=var, m=menu: ...)` in `_build_library_column`; the existing delete-then-add `_refresh_library_menu` makes the twice-per-open post idempotent and never touches the StringVar, so a vanished selection stays shown.
- Five rescan tests (every menu has a postcommand, idempotent double post, new file appears and disappears, deleted selected file keeps its label while another pick still sends, missing folder shows Auto only) driven through the real registered post command.
- Two GUI-07 tests: `takefocus` 0 and no key bindings on any dropdown or menu; after a pick in each dropdown, focus is not on a library widget and Up/Down/Shift-Up/Shift-Down give BPM 121, 120, 125, 120 with `sent == [121.0, 120.0, 125.0, 120.0]`.
- README section "Pick a variation from the app" in plain words; the "from Phase 5 on" phrase replaced.
- Engine gates, run on this Mac: pytest `188 passed`; `./scripts/check.sh --library-only` printed `CHECK OK: library guard`, `CHECK OK: library file count (8 files)`, `CHECK PASS (library only)`; the library log has `CHECK OK: unknown name`, `CHECK OK: invalid names ignored`, `CHECK OK: python one-liner`.
- No commit of this phase touches `supercollider/main.scd`, `supercollider/core` or a variation folder, and `git status` shows nothing there.

## Task Commits

1. **Task 1: rescan on open** - `ce969d2` (feat)
2. **Task 2: GUI-07 tests and README section** - `94501d4` (test)

**Plan metadata:** committed separately (docs: complete plan)

## Files Created/Modified
- `python_app/view.py` - postcommand wiring and extended docstrings
- `python_app/tests/test_view_tk.py` - `_post`, `_labels`, `_seed_library`, `_seed_two_each` helpers and seven new tests
- `supercollider/library/README.md` - new "Pick a variation from the app" section

## Decisions Made
- Followed the plan as specified. `_refresh_library_menu` needed no change beyond its docstring; the GUI-07 tests passed without any `view.py` fix.

## Deviations from Plan

None - plan executed exactly as written. Setup step only: `./run.sh --setup` built the gitignored `.venv` in the worktree.

## Issues Encountered
- The first `./scripts/check.sh --library-only` run ended with `CHECK FAILED: library check` after `CHECK OK: select melody by name`, with no `LIBRARY FAIL` line in the log (the log simply stopped; likely the 230 s timeout or contention for the audio server and OSC port, since the rider's SuperCollider IDE was running on this Mac and the engine warned that port 57121 was used instead of 57120). An immediate re-run with nothing changed passed in 67 s with every expected line. No code was changed between the two runs. Worth knowing if the check ever fails once with a truncated log.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None.

## Threat Flags

None. The GUI still only lists folder entries; no write path to the library was added (T-05-07, T-05-08 and T-05-09 mitigations are tested).

## Pending human checks

These belong to the rider and are collected into the end-of-phase UAT. They are NOT done; the phase stays human_needed until the rider answers.

**Selector check (GUI-05, GUI-06, GUI-07)** - status: pending

1. Open SuperCollider, open supercollider/main.scd, select everything and evaluate it, as always. In a terminal in the PedalPulse folder, run ./run.sh to open the app.
2. The window now has a column on the right with Palette, Progression and Melody, each showing Auto. The SuperCollider post window shows three lines like "PedalPulse: /pp/palette auto -> auto (resolves to classic)", one each for palette, progression and melody.
3. Open the Melody dropdown with a normal click. It lists Auto, classic, classic_lead and classic_lead_loud (plus any newer melody files). Pick classic_lead_loud: from the next bar you hear the louder lead, and the post window shows a line with "/pp/melody classic_lead_loud -> selected". Open the dropdown again and pick classic_lead_loud again: no new line appears in the post window.
4. Right after using a dropdown, press Up, Down, Shift-Up and Shift-Down: the BPM number changes by 1, 1, 5 and 5, exactly as before.
5. In the terminal, run: cp supercollider/library/melodies/_template.scd supercollider/library/melodies/zz_try.scd. Open the Melody dropdown again without restarting the app: zz_try is now at the bottom of the list (you do not need to pick it). Then delete it with: rm supercollider/library/melodies/zz_try.scd. Open the dropdown once more: zz_try is gone.
6. Paste this line in the terminal and press Enter: .venv/bin/python -c "from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/melody', 'no_such_melody')". The post window shows "PedalPulse ERROR: library file ... does not exist" and "... refused -- still playing ...", and the music keeps playing without a gap.
7. Pick Auto in the Melody dropdown. Quit SuperCollider, then pick a few items in each dropdown: the app keeps working, with no freeze and no error window.

If anything looks or sounds wrong, describe it in your own words; Claude will fix the app or add a new library file, and existing library files are never edited.

## Next Phase Readiness
- All three plans of phase 5 are implemented; the phase awaits verification and the rider's UAT above.

## Self-Check: PASSED

- FOUND: python_app/view.py, python_app/tests/test_view_tk.py, supercollider/library/README.md
- FOUND commits: ce969d2, 94501d4 (ancestors of HEAD)
- Full suite: 188 passed; library-only engine check passes

---
*Phase: 05-library-selectors-in-the-gui*
*Completed: 2026-10-12*
