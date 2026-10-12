---
phase: 05-library-selectors-in-the-gui
verified: 2026-10-12T00:00:00Z
status: human_needed
score: 13/14 must-haves verified
covered_files:
  - .planning/phases/05-library-selectors-in-the-gui/05-01-PLAN.md
  - .planning/phases/05-library-selectors-in-the-gui/05-01-SUMMARY.md
  - .planning/phases/05-library-selectors-in-the-gui/05-02-PLAN.md
  - .planning/phases/05-library-selectors-in-the-gui/05-02-SUMMARY.md
  - .planning/phases/05-library-selectors-in-the-gui/05-03-PLAN.md
  - .planning/phases/05-library-selectors-in-the-gui/05-03-SUMMARY.md
  - python_app/config.py
  - python_app/library_logic.py
  - python_app/main.py
  - python_app/osc_client.py
  - python_app/tests/test_library_logic.py
  - python_app/tests/test_main_launch.py
  - python_app/tests/test_osc_client.py
  - python_app/tests/test_view_tk.py
  - python_app/view.py
  - supercollider/library/README.md
covered_digest: "v3:sha256:1bc097c153ed73b6b762e85e6f6fd1630c704362309a783722337210e5bd8f8f"
behavior_unverified: 0
overrides_applied: 0
re_verification: null
coincidental_reliance_items:
  - truth: "After using any selector, Up/Down and the other BPM shortcuts still change BPM exactly as before (GUI-07)"
    reason: fixture-only
    harden: "The automated proof picks entries with menu.invoke plus focus_force on root. menu.invoke never moves focus, so the test setup establishes the focus state; a real native aqua click is not exercised. The plan declares this as a flagged assumption; UAT step 4 is the real check."
human_verification:
  - test: "Selector check (GUI-05, GUI-06, GUI-07), step 1-2: start the engine (evaluate supercollider/main.scd), run ./run.sh. Look at the window and the SuperCollider post window"
    expected: "A column on the right shows Palette, Progression and Melody, each on Auto. The post window shows three lines like 'PedalPulse: /pp/palette auto -> auto (resolves to classic)', one each for palette, progression and melody."
    why_human: "Needs the real engine and its post window; the app is send-only so only the engine's post window can confirm what it received (ROADMAP SC 2)."
  - test: "Selector check, step 3: open the Melody dropdown with a normal mouse click, pick classic_lead_loud, then open it and pick classic_lead_loud again"
    expected: "The list shows Auto, classic, classic_lead, classic_lead_loud. From the next bar the louder lead is audible and the post window shows '/pp/melody classic_lead_loud -> selected'. The repeated pick prints no new line."
    why_human: "The native macOS (aqua) menu cannot be opened by a test; synthetic clicks never reach tk::MbPost. The audible change needs the engine and the rider's ears."
  - test: "Selector check, step 4: right after using a dropdown, press Up, Down, Shift-Up, Shift-Down"
    expected: "The BPM number changes by 1, 1, 5 and 5, exactly as before."
    why_human: "Keyboard focus after a real native menu click is only approximated by menu.invoke + focus_force in the automated tests (RESEARCH A1/A3)."
  - test: "Selector check, step 5: cp supercollider/library/melodies/_template.scd supercollider/library/melodies/zz_try.scd, open the Melody dropdown without restarting; then rm the file and open it again"
    expected: "zz_try appears at the bottom after it is created and is gone after it is deleted, with no restart."
    why_human: "The postcommand rebuild is proven by running the registered Tcl command; that a real aqua click actually fires it is checked only by hand. (Remove zz_try afterwards: a stray .scd file fails the library file-count check.)"
  - test: "Selector check, step 6: .venv/bin/python -c \"from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/melody', 'no_such_melody')\""
    expected: "Post window shows 'PedalPulse ERROR: library file ... does not exist' and '... refused -- still playing ...'; the music continues without a gap."
    why_human: "Audible continuity with the live engine; the engine half is covered offline by scripts/check.sh --library-only (CHECK OK: unknown name)."
  - test: "Selector check, step 7: pick Auto in the Melody dropdown; quit SuperCollider; pick items in each dropdown"
    expected: "The app keeps working, with no freeze and no error window."
    why_human: "Real-window behavior with the engine stopped; automated tests only prove send_selection returns False/True without raising."
---

# Phase 5: Library Selectors in the GUI Verification Report

**Phase Goal:** As a rider, I want Palette, Progression and Melody selectors in the PedalPulse window, so that I can pick Auto or any named variation using the same names I use when giving feedback.
**Verified:** 2026-10-12
**Status:** human_needed
**Re-verification:** No, initial verification
**Mode:** mvp (goal is a valid user story; `user-story.validate` returned `true`)

## User Flow Coverage

User story: "As a rider, I want to have Palette, Progression and Melody selectors in the PedalPulse window, so that I can pick Auto or any named variation using the same names I use when giving feedback."

| Step | Expected | Evidence | Status |
|------|----------|----------|--------|
| Open the app | Window shows a right-hand column with Palette, Progression, Melody, each on Auto | `python_app/view.py:174-211` `_build_library_column`; `python_app/main.py:55-62`; `test_library_column_order_and_initial_state`, `test_library_column_sits_right_of_unchanged_column` pass | VERIFIED (code and Tk tests); native look is in the human checklist |
| Open a dropdown | Auto, then classic, then every file stem in that folder A-Z, exact names | `library_logic.py:scan_library` + `LibrarySelector.options()`; `view.py:_refresh_library_menu` uses `add_radiobutton(label=name, ...)` with no name map; `test_each_dropdown_lists_its_own_folder`; real folders scanned in `test_real_library_folders` | VERIFIED |
| Pick a name | The exact stem (or `auto`) goes to /pp/palette, /pp/progression or /pp/melody once, only on change | `osc_client.py:send_selection` -> `send_message(address, str(name))`; `main.py` binds the address per category via `functools.partial`; `test_melody_dropdown_pick_reaches_engine_over_udp` receives the real datagram on a loopback socket; `test_same_stem_goes_only_to_its_own_category` | VERIFIED |
| Outcome: "same names I use when giving feedback" | Dropdown labels are the library file stems, i.e. the names the engine and Phase 4 use | No prettifying or name map in `view.py`/`library_logic.py` (`grep` for json/pickle/shelve/configparser: none); engine OSCdefs at `supercollider/main.scd:392-394` take the same stem | VERIFIED |
| Hear it | Engine switches at the next bar and posts a confirmation | Engine side from Phase 4 (`~ppSelect`); `scripts/check.sh --library-only` passes. Audible result and post-window line need the live engine | Human (UAT steps 2, 3) |

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | ROADMAP SC1: window shows Palette, Progression, Melody; each lists Auto first, then variation files from its folder (hidden and `_template` skipped); empty or missing folder shows Auto only; relaunch picks up new files | VERIFIED | `scan_library` uses `_STEM_RE.fullmatch`, `is_file()`, OSError -> `[]`; `LIBRARY_CATEGORIES` order Palette, Progression, Melody; `options()` rescans on each call. Tests: `test_scan_filters_and_orders`, `test_scan_missing_empty_or_file_path_lists_nothing`, `test_real_library_folders`; full suite 188 passed (run by me) |
| 2  | ROADMAP SC2: a pick sends its name over OSC only when the choice changes; app stays send-only and keeps working when the engine is not running | VERIFIED (GUI half) | `LibrarySelector.select` returns early on non-str, empty or unchanged (D-05); `send_selection` catches `(OSError, OverflowError, BuildError)`; `grep recvfrom|osc_server|OSCUDPServer python_app/*.py` finds nothing; `test_send_selection_returns_false_on_send_errors`, `test_change_sends_once_and_same_pick_sends_nothing`. The engine post-window confirmation is a human item |
| 3  | ROADMAP SC3: a name the engine does not know is ignored with a warning, music keeps playing, GUI never crashes | VERIFIED | `select()` does not check the label against disk (`test_name_not_on_disk_is_still_sent`); `test_deleted_selected_file_keeps_its_label_and_another_pick_still_sends`; I ran `./scripts/check.sh --library-only`: exit 0, `CHECK PASS (library only)`, `CHECK OK: unknown name`, `CHECK OK: invalid names ignored`, `CHECK OK: python one-liner`, `CHECK OK: library file count (8 files)` |
| 4  | ROADMAP SC4: after using any selector, Up/Down and the other BPM shortcuts change BPM exactly as before; selectors never take keyboard focus | VERIFIED (automated proxy) | `view.py:_build_library_column` sets `takefocus=0`, adds no `bind`/`focus` calls on the column; root bindings unchanged; `test_dropdowns_take_no_focus_and_add_no_key_bindings`, `test_arrow_keys_still_nudge_bpm_after_using_each_dropdown` (sent `[121.0, 120.0, 125.0, 120.0]`) pass. Real native click is UAT step 4 (see coincidental-reliance item) |
| 5  | Column sits to the right of the unchanged controls; window grows wider, not taller; `test_window_layout_order` unmodified | VERIFIED | `view.py:48-49` `container.pack(side="left", anchor="n")`; `library_column.pack(side="left", ...)`; tests above and `test_window_layout_order` pass |
| 6  | Launch sends `auto` once each to /pp/palette, /pp/progression, /pp/melody after the unchanged /pp/bpm 120.0, /pp/play 1, /pp/epic 10.0, /pp/volume 80.0, with nothing remembered between launches | VERIFIED | `main.py:63-68` send order; `test_launch_sends_initial_values_then_auto_to_each_library_address` runs the real `main.py` twice and compares seven datagrams; I also ran `python_app/main.py --port 9 --exit-after 300`: exit 0, empty stderr |
| 7  | Fixed dropdown width: changing selection never changes window width | VERIFIED | `config.LIBRARY_DROPDOWN_WIDTH = 20`, `button.configure(width=...)`; `test_dropdown_width_is_fixed` |
| 8  | Dropdowns never offer a name the engine would refuse (1-64 chars `[a-z0-9][a-z0-9_]*`, not `auto`, regular `.scd` files only), order independent of OS listing | VERIFIED | `library_logic.py:20,43-52`; `test_scan_length_limit`, `test_scan_order_does_not_depend_on_listing_order`; RED commit `f76d022 test(05-02)` precedes GREEN `4bd90ed feat(05-02)` |
| 9  | `send_selection` delivers exactly one OSC string for each of the three addresses and never raises | VERIFIED | `osc_client.py:send_selection`; `test_send_selection_delivers_osc_string_over_real_socket`, `test_send_selection_sends_auto`, `test_send_selection_to_unused_port_returns_true_without_raising` |
| 10 | Opening a dropdown rebuilds its list from a fresh scan, idempotently, with no watcher, timer or thread | VERIFIED (postcommand level) | `view.py:196-198` `menu.configure(postcommand=lambda s=selector, v=var, m=menu: ...)`; `_refresh_library_menu` does `menu.delete(0, "end")` then adds; `grep after( / Thread` in `view.py`/`library_logic.py` finds none; `test_every_dropdown_rebuilds_on_open`, `test_rebuild_is_idempotent`, `test_new_file_appears_on_next_open`. The tests run the registered Tcl command, not a real click; native path is UAT step 5 |
| 11 | A deleted selected file keeps its label on the button; a removed folder shows Auto only after reopen; nothing raises | VERIFIED | `_refresh_library_menu` never sets `var`; `scan_library` returns `[]` on OSError; `test_deleted_selected_file_keeps_its_label_and_another_pick_still_sends`, `test_missing_folder_shows_auto_only_after_reopen` |
| 12 | Engine and variation files untouched by this phase; library guard and library check pass | VERIFIED | `git status --porcelain -- supercollider` is clean; no commit labelled phase 05 touches `supercollider/main.scd`, `supercollider/core` or a variation folder (the only phase-05 commit touching `supercollider/` is `94501d4`, README.md only); `check.sh --library-only` passes (see truth 3). Note `04-05` commit `549e2cf` and `bd04c46 feat(library)` are not phase 5 |
| 13 | Library README has "## Pick a variation from the app", says a new file appears on next open and that re-picking the selected name does nothing, and no longer says "from Phase 5 on" | VERIFIED | `supercollider/library/README.md:35`; `grep "from Phase 5 on"` returns nothing; "already selected" present |
| 14 | The rider confirms the end-to-end behavior in the end-of-phase UAT (native menu with fresh list, engine post-window confirmations, no re-send on repeated pick, BPM keys after a real click, no crash with the engine stopped) | UNCERTAIN | By design only the rider can close this (05-03 prohibition, judgment tier). 05-03-SUMMARY.md lists "Selector check" as pending and nowhere claims it passed. See Human Verification Required |

**Score:** 13/14 truths verified (0 present, behavior-unverified; 1 uncertain pending the rider)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `python_app/library_logic.py` | `scan_library`, `to_wire`, `LibrarySelector`; no tkinter/OSC import | VERIFIED | Substantive and wired (imported by `view.py` and `main.py`); import grep returns 0 |
| `python_app/config.py` | Address constants, `LIBRARY_ROOT`, `LIBRARY_CATEGORIES`, `AUTO_*`, `LIBRARY_FIRST_STEM`, `LIBRARY_DROPDOWN_WIDTH` | VERIFIED | All present; `LIBRARY_ROOT` derived from `__file__` |
| `python_app/osc_client.py` | `OscClient.send_selection` | VERIFIED | `send_message(address, str(name))`, error-swallowing |
| `python_app/view.py` | `selector_controllers`, library column, `postcommand` rebuild | VERIFIED | `tk.OptionMenu(`, `takefocus=0`, `menu.delete(0, "end")`, `postcommand=lambda`; no OSC import |
| `python_app/main.py` | Selectors built from `config.LIBRARY_CATEGORIES`, `send_initial()` after volume | VERIFIED | Lines 45-68 |
| `python_app/tests/test_main_launch.py` | Subprocess launch test | VERIFIED | Collected and passing |
| `python_app/tests/test_library_logic.py` | Scan and selector contract tests | VERIFIED | All named tests collected and passing |
| `python_app/tests/test_view_tk.py` | Layout, width, rescan, GUI-07 tests | VERIFIED | All named tests collected and passing |
| `supercollider/library/README.md` | Pick-from-app section | VERIFIED | Line 35 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `view.py _refresh_library_menu` | `LibrarySelector.select` | radiobutton `command=lambda n=name: selector.select(n)` | WIRED | Default-argument capture present |
| `view.py _build_library_column` | `_refresh_library_menu` -> `options()` -> `scan_library` | `menu.configure(postcommand=lambda ...)` | WIRED | Plus one startup call |
| `main.py` | `OscClient.send_selection` | `functools.partial(client.send_selection, address)` | WIRED | One per `LIBRARY_CATEGORIES` entry |
| `LibrarySelector` | `config.AUTO_NAME` | `to_wire`, also in `send_initial` | WIRED | |
| `osc_client.send_selection` | `supercollider/main.scd` `OSCdef(\pp_palette / \pp_progression / \pp_melody)` | UDP 127.0.0.1:57120, one OSC string | WIRED | Addresses match `main.scd:392-394` |
| `scan_library` | `supercollider/core/loader.scd ~ppStemValid` | same rule in Python | WIRED | Engine check passes with the same set of files |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| Dropdown menus | entry labels | `LibrarySelector.options()` -> `Path.iterdir()` on `LIBRARY_ROOT/<folder>` | Yes, real directory listing on every open and at startup | FLOWING |
| OSC sends | name string | Picked label via `to_wire` -> `send_selection` -> UDP socket | Yes, captured as real datagrams on a bound loopback socket in tests | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full Python suite | `.venv/bin/pytest python_app/tests -q` | 188 passed | PASS |
| Real entry point launches with no traceback | `.venv/bin/python python_app/main.py --port 9 --exit-after 300` | exit 0, stderr empty | PASS |
| Engine library check | `./scripts/check.sh --library-only` | exit 0; `CHECK PASS (library only)`, unknown name, invalid names, python one-liner, file count (8 files) all OK | PASS |
| No receive path / settings file in app | `grep -lE 'recvfrom\|osc_server\|OSCUDPServer' python_app/*.py`; `grep -E 'json\|pickle\|shelve\|configparser'` on app modules | No matches | PASS |
| Library folders unmodified | `git status --porcelain -- supercollider` | Empty | PASS |

### Probe Execution

Step 7c: SKIPPED. No `scripts/*/tests/probe-*.sh` exists and no plan declares a probe. The equivalent engine-side runnable check, `scripts/check.sh --library-only`, was run above.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| GUI-05 | 05-01, 05-02, 05-03 | Palette, progression and melody selectors, each offering Auto plus every item in the library folder on disk | SATISFIED (code and tests); native-click confirmation in UAT | Truths 1, 5, 7, 8, 10, 11; `scan_library`, `_build_library_column` |
| GUI-06 | 05-01, 05-02, 05-03 | Selection reaches the engine over send-only OSC by name; unknown names ignored by the engine with a warning; GUI never crashes | SATISFIED (GUI and offline engine check); live post-window confirmation in UAT | Truths 2, 3, 9, 11 |
| GUI-07 | 05-03 | Selectors don't interfere with the BPM keyboard shortcuts | SATISFIED in automated tests; real click in UAT step 4 | Truth 4; two named GUI-07 tests |

All three IDs appear in PLAN frontmatter (05-01 and 05-02: GUI-05, GUI-06; 05-03: GUI-05, GUI-06, GUI-07) and in REQUIREMENTS.md mapped to Phase 5. No orphaned requirements: REQUIREMENTS.md maps only GUI-05, GUI-06, GUI-07 to Phase 5.

Bookkeeping, not a gap: `REQUIREMENTS.md` still shows GUI-05/06/07 as `Pending` with unchecked boxes, and `ROADMAP.md` still shows Phase 5 as `[ ]`. These should be updated by the orchestrator once the rider closes the UAT.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (all phase files) | - | `TBD`/`FIXME`/`XXX`/`TODO`/`HACK` | None found | No debt markers |
| `python_app/library_logic.py` | 107-112 | State recorded before the send; a failed send (or an engine restart) leaves the dropdown showing a choice the engine never received, and re-picking it is a no-op (REVIEW WR-01) | Warning | Matches the plan's stated design ("a failed send keeps the new selection", D-05); does not break a ROADMAP success criterion, but the dropdown can diverge from the engine after a restart. Recovery: pick another name and back |
| `python_app/library_logic.py` | 109-112 | A listener exception (`TclError` from `var.set`) would skip the send after `_selected` changed (REVIEW WR-02) | Warning | Narrow teardown-time edge |
| `python_app/tests/test_main_launch.py` | 33-38 | Subprocess opens a real on-screen window twice per run and has no display-less skip (REVIEW WR-03) | Warning | Flashes a window and can steal focus; fails with `TclError` on a headless box |
| `python_app/library_logic.py` | 40 | Redundant `startswith(".")` (REVIEW IN-01) | Info | Dead logic, harmless |
| `python_app/tests/test_view_tk.py` | 506, 659, 589 | Duplicate `_menu_labels`/`_labels`; layout equality assertion that is font-dependent (IN-02, IN-03) | Info | Test fragility |
| `supercollider/library/README.md` | 15-17, 53-55 | Stale file list; "pick another and back" advice vs. never-edit rule (IN-04) | Info | Documentation only |

I read 05-REVIEW.md: 0 critical, 3 warnings, 4 info, dispositions open. None of the warnings contradicts a must-have truth, so none is a BLOCKER.

### Human Verification Required

The plans embed a `<verify><human-check>` block ("Selector check", 05-03 Task 2) that the executor was forbidden to perform. It is harvested here, not marked passed. Items are in the frontmatter `human_verification` list; summarised:

1. **Start and post-window (steps 1-2).** Evaluate `main.scd`, run `./run.sh`. Expect three dropdowns on Auto and three `auto -> auto (resolves to classic)` lines in the post window. Why human: needs the live engine; the app is send-only.
2. **Real click, pick and repeat (step 3).** Click Melody, pick `classic_lead_loud`: louder lead from the next bar, `-> selected` line; pick it again: no new line. Why human: aqua menus cannot be opened by tests; audible change.
3. **BPM keys after a real click (step 4).** Up, Down, Shift-Up, Shift-Down change BPM by 1, 1, 5, 5. Why human: focus after a native click is only approximated by `menu.invoke` plus `focus_force`.
4. **Rescan on open (step 5).** Copy `_template.scd` to `zz_try.scd`, reopen Melody: it appears; delete it, reopen: it is gone. Remove the file afterwards. Why human: the postcommand is proven by running the Tcl command, not by a real click.
5. **Unknown name (step 6).** Send `no_such_melody` with the one-liner: error and `refused -- still playing` lines, music continues without a gap.
6. **Engine stopped (step 7).** Pick Auto, quit SuperCollider, pick items in each dropdown: no freeze or error window.

### Gaps Summary

No gaps. Every ROADMAP success criterion and PLAN must-have is backed by code I read and tests I ran (188 passed, launch check clean, engine library check passed, engine and variation files untouched). The phase is `human_needed` rather than `passed` only because the plans require the rider's own end-of-phase check on the real native menu and live engine, which no agent may perform or approve. Three open code-review warnings (WR-01 to WR-03) are recorded as non-blocking. WR-01 (dropdown can diverge from the engine after a dropped send or an engine restart) is the one most worth a follow-up decision.

---

_Verified: 2026-10-12_
_Verifier: Claude (gsd-verifier)_
