---
phase: 05-library-selectors-in-the-gui
verified: 2026-10-12T16:00:00Z
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
covered_digest: "v3:sha256:9f23562d09d8dc67dbdb3656ef95a41d1ed5fe179c953bb3d8b02a2d0e268daa"
behavior_unverified: 0
overrides_applied: 0
re_verification: null
coincidental_reliance_items:
  - truth: "After using any selector, Up/Down and the other BPM shortcuts still change BPM exactly as before (GUI-07)"
    reason: fixture-only
    harden: "The automated proof picks entries with menu.invoke plus focus_force on root. menu.invoke never moves focus, so the test setup establishes the focus state; a real native aqua click is not exercised. UAT test 3 is the real check."
human_verification:
  - test: "UAT 1: start the engine (evaluate supercollider/main.scd), run ./run.sh. Look at the window and the SuperCollider post window"
    expected: "A column on the right shows Palette, Progression and Melody, each on Auto. The post window shows one 'auto -> auto (resolves to classic)' line each for /pp/palette, /pp/progression and /pp/melody."
    why_human: "Needs the real engine and its post window; the app is send-only, so only the engine's post window can confirm what it received (ROADMAP SC2)."
  - test: "UAT 2: open the Melody dropdown with a normal mouse click, pick classic_lead_loud, then open it and pick classic_lead_loud again"
    expected: "The list shows Auto, classic, classic_lead, classic_lead_loud. From the next bar the louder lead is audible and the post window shows '/pp/melody classic_lead_loud -> selected'. The repeated pick prints no new line."
    why_human: "The native macOS (aqua) menu cannot be opened by a test. The audible change needs the engine and the rider's ears."
  - test: "UAT 3: right after using a dropdown, press Up, Down, Shift-Up, Shift-Down"
    expected: "The BPM number changes by 1, 1, 5 and 5, exactly as before."
    why_human: "Keyboard focus after a real native menu click is only approximated by menu.invoke + focus_force in the automated tests."
  - test: "UAT 4: cp supercollider/library/melodies/_template.scd supercollider/library/melodies/zz_try.scd, open the Melody dropdown without restarting; then rm the file and open it again"
    expected: "zz_try appears at the bottom after it is created and is gone after it is deleted, with no restart. (Remove zz_try afterwards: a stray .scd file fails the library file-count check.)"
    why_human: "The postcommand rebuild is proven by running the registered Tcl command; that a real aqua click fires it is only checkable by hand."
  - test: "UAT 5: .venv/bin/python -c \"from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/melody', 'no_such_melody')\""
    expected: "Post window shows 'PedalPulse ERROR: library file ... does not exist' and '... refused -- still playing ...'; the music continues without a gap."
    why_human: "Audible continuity with the live engine; the engine half is covered offline by scripts/check.sh --library-only."
  - test: "UAT 6: pick Auto in the Melody dropdown; quit SuperCollider; pick items in each dropdown"
    expected: "The app keeps working, with no freeze and no error window."
    why_human: "Real-window behavior with the engine stopped; automated tests only prove send_selection returns False/True without raising."
---

# Phase 5: Library Selectors in the GUI Verification Report

**Phase Goal:** As a rider, I want Palette, Progression and Melody selectors in the PedalPulse window, so that I can pick Auto or any named variation using the same names I use when giving feedback.
**Verified:** 2026-10-12
**Status:** human_needed
**Re-verification:** No gaps existed in the earlier report, so this is a fresh full pass. It supersedes the earlier 05-VERIFICATION.md, which predated the review fixes (commits 5521675, d6e8c32, 669da1a) and described them as open.
**Mode:** mvp (goal is a valid user story)

## User Flow Coverage

| Step | Expected | Evidence | Status |
|------|----------|----------|--------|
| Open the app | Right-hand column with Palette, Progression, Melody, each on Auto | `view.py:_build_library_column` (lines 182-221); `main.py:55-62` builds one `LibrarySelector` per `config.LIBRARY_CATEGORIES`; layout tests pass | VERIFIED (code and Tk tests); native look in UAT 1 |
| Open a dropdown | Auto, then `classic`, then every stem in that folder | `library_logic.scan_library` + `LibrarySelector.options()`; `_refresh_library_menu` adds radiobuttons labelled with the raw stem, no name map; `test_real_library_folders` scans the real folders | VERIFIED |
| Pick a name | Exact stem (or `auto`) sent to /pp/palette, /pp/progression or /pp/melody once, only on change | `osc_client.send_selection` -> `send_message(address, str(name))`; `main.py` binds the address per category with `functools.partial`; `test_melody_dropdown_pick_reaches_engine_over_udp` reads the real datagram | VERIFIED |
| "Same names I use when giving feedback" | Labels are the library file stems the engine and Phase 4 use | `view.py`/`library_logic.py` do no prettifying; engine `OSCdef(\pp_palette/\pp_progression/\pp_melody)` at `supercollider/main.scd:392-394` take the same stem | VERIFIED |
| Hear it | Engine switches at the next bar and posts a confirmation | Engine side is Phase 4 (`~ppSelect`); offline engine check passes. Audible result needs the live engine | Human (UAT 1, 2) |

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | SC1: window shows Palette, Progression, Melody; each lists Auto first, then variation files from its folder (hidden and `_template` skipped); empty or missing folder shows Auto only; relaunch picks up new files | VERIFIED | `scan_library` uses `_STEM_RE.fullmatch`, `is_file()`, OSError -> `[]`; `options()` rescans every call; `test_scan_filters_and_orders`, `test_scan_missing_empty_or_file_path_lists_nothing`, `test_real_library_folders` pass |
| 2  | SC2: a pick sends its name over OSC only when the choice changes; app stays send-only and keeps working with the engine not running | VERIFIED (GUI half) | `LibrarySelector.select` returns early on non-str, empty, or unchanged-and-last-send-ok; `send_selection` catches `(OSError, OverflowError, BuildError)`; no receive path (`recvfrom`, `osc_server`, `OSCUDPServer` not found in `python_app/*.py`); change/same-pick/failed-send tests pass. Engine post-window confirmation is a human item |
| 3  | SC3: a name the engine does not know is ignored with a warning, music keeps playing, GUI never crashes | VERIFIED | `select()` does not check the label against disk; `test_name_not_on_disk_is_still_sent`, `test_deleted_selected_file_keeps_its_label_and_another_pick_still_sends`; `check.sh --library-only` passed on re-run with `CHECK OK: unknown name`, `invalid names ignored`, `python one-liner`, `library file count (8 files)` |
| 4  | SC4: after using any selector, Up/Down and the other BPM shortcuts change BPM exactly as before; selectors never take keyboard focus | VERIFIED (automated proxy) | `takefocus=0` on every OptionMenu button; no `bind`/`focus` calls in the library column; root bindings at `view.py:175-178` unchanged; `test_dropdowns_take_no_focus_and_add_no_key_bindings`, `test_arrow_keys_still_nudge_bpm_after_using_each_dropdown` pass. Real native click is UAT 3 (coincidental-reliance item) |
| 5  | Column sits right of the unchanged controls; window grows wider, not taller; `test_window_layout_order` unmodified | VERIFIED | `container.pack(side="left", anchor="n")`, `library_column.pack(side="left")`; layout tests pass |
| 6  | Launch sends `auto` once each to /pp/palette, /pp/progression, /pp/melody after the unchanged /pp/bpm, /pp/play, /pp/epic, /pp/volume sends; nothing remembered between launches | VERIFIED | `main.py:63-68`; `test_launch_sends_initial_values_then_auto_to_each_library_address` passes (re-run alone: 1 passed); `main.py --port 9 --exit-after 300 --hidden` exits 0 |
| 7  | Fixed dropdown width: changing selection never changes window width | VERIFIED | `config.LIBRARY_DROPDOWN_WIDTH = 20` applied via `button.configure(width=...)`; `test_dropdown_width_is_fixed` |
| 8  | Dropdowns never offer a name the engine would refuse (1-64 chars `[a-z0-9][a-z0-9_]*`, not `auto`, regular `.scd` files), order independent of OS listing | VERIFIED | `_STEM_RE` and `fullmatch`; `sorted(stems)`; `test_scan_length_limit`, `test_scan_order_does_not_depend_on_listing_order` |
| 9  | `send_selection` delivers exactly one OSC string per address and never raises | VERIFIED | `osc_client.py:send_selection`; real-socket and unused-port tests pass |
| 10 | Opening a dropdown rebuilds its list from a fresh scan, idempotently, with no watcher, timer or thread | VERIFIED (postcommand level) | `menu.configure(postcommand=lambda s=selector, v=var, m=menu: ...)`; `menu.delete(0, "end")` then add; no `after(`/`Thread` in `view.py` or `library_logic.py`; `test_every_dropdown_rebuilds_on_open`, `test_rebuild_is_idempotent`, `test_new_file_appears_on_next_open`. A real aqua click is UAT 4 |
| 11 | A deleted selected file keeps its label on the button; a removed folder shows Auto only after reopen; nothing raises | VERIFIED | `_refresh_library_menu` never sets `var`; `scan_library` returns `[]` on OSError; named tests pass |
| 12 | Engine and variation files untouched by this phase | VERIFIED | `git status --porcelain -- supercollider python_app` clean; `git diff 8fe0d46 HEAD --stat -- supercollider` shows only `library/README.md` |
| 13 | Library README documents "Pick a variation from the app" and no longer says "from Phase 5 on" | VERIFIED | Section present in `supercollider/library/README.md`; phrase absent |
| 14 | The rider confirms the end-to-end behavior in the end-of-phase UAT (native menu with fresh list, engine post-window confirmations, no re-send on repeated pick, BPM keys after a real click, no crash with the engine stopped) | UNCERTAIN | By design only the rider can close this (05-03 judgment-tier prohibition). `05-UAT.md` has status `testing`, all 6 results `[pending]`. Neither SUMMARY claims it passed |

**Score:** 13/14 truths verified (0 behavior-unverified; 1 uncertain pending the rider)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `python_app/library_logic.py` | `scan_library`, `to_wire`, `LibrarySelector`; no tkinter/OSC import | VERIFIED | Substantive, wired from `view.py` and `main.py`. Includes review fixes: retry after a failed send (`_last_send_ok`) and send-in-`finally` when a listener raises |
| `python_app/config.py` | Address constants, `LIBRARY_ROOT`, `LIBRARY_CATEGORIES`, `AUTO_*`, `LIBRARY_FIRST_STEM`, `LIBRARY_DROPDOWN_WIDTH` | VERIFIED | All present; `LIBRARY_ROOT` derived from `__file__` |
| `python_app/osc_client.py` | `OscClient.send_selection` | VERIFIED | Error-swallowing, returns bool |
| `python_app/view.py` | Library column, `postcommand` rebuild, `selector_controllers` | VERIFIED | No OSC import |
| `python_app/main.py` | Selectors built from `LIBRARY_CATEGORIES`; `send_initial()` after volume; `--hidden` flag | VERIFIED | Lines 45-68, 85-91 |
| `python_app/tests/*` | Selector, layout, GUI-07 and launch tests | VERIFIED | Full suite 191 passed |
| `supercollider/library/README.md` | Pick-from-app section | VERIFIED | Present |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `view._refresh_library_menu` | `LibrarySelector.select` | radiobutton `command=lambda n=name: selector.select(n)` | WIRED | Default-argument capture |
| `view._build_library_column` | `options()` -> `scan_library` | `menu.configure(postcommand=...)` plus one startup call | WIRED | |
| `main.py` | `OscClient.send_selection` | `functools.partial(client.send_selection, address)` | WIRED | One per category |
| `LibrarySelector` | `config.AUTO_NAME` | `to_wire`, `send_initial` | WIRED | |
| `send_selection` | `supercollider/main.scd` `OSCdef(\pp_palette/\pp_progression/\pp_melody)` | UDP 127.0.0.1:57120, one OSC string | WIRED | Addresses match `main.scd:392-394` |
| `scan_library` | `core/loader.scd ~ppStemValid` | same rule in Python | WIRED | Engine file-count check passes |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| Dropdown menus | entry labels | `Path.iterdir()` on `LIBRARY_ROOT/<folder>` on every open and at startup | Yes | FLOWING |
| OSC sends | name string | picked label -> `to_wire` -> `send_selection` -> UDP; captured as real datagrams on a loopback socket in tests | Yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full Python suite | `.venv/bin/pytest python_app/tests -q` | 191 passed | PASS |
| Real entry point launches cleanly | `.venv/bin/python python_app/main.py --port 9 --exit-after 300 --hidden` | exit 0 | PASS |
| Engine library check | `./scripts/check.sh --library-only` | First run: `CHECK FAILED: library check` right after `CHECK OK: select melody by name`. Second run: exit 0, `CHECK PASS (library only)`, all checks OK | PASS on re-run (see flakiness note) |
| No receive path in app | grep `recvfrom|osc_server|OSCUDPServer` in `python_app/*.py` | No matches | PASS |
| Python and engine files untouched in working tree | `git status --porcelain -- supercollider python_app` | Empty | PASS |

**Flakiness note (WARNING, not a gap):** The first `--library-only` run failed and the immediate re-run passed with no code change. A live user `sclang` (pid 85038) and `scsynth` were running on this machine during verification, and the failing log shows the library-check engine on OSC port 57121 with the "quit other sclang instances" warning. The most likely cause is contention with that live engine. Phase 5 changed no engine file, so this is not attributable to this phase, but the library check is not fully reliable while another engine is running.

### Probe Execution

Step 7c: SKIPPED. No `scripts/*/tests/probe-*.sh` exists and no plan declares a probe. The runnable equivalent, `scripts/check.sh --library-only`, was run above.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| GUI-05 | 05-01, 05-02, 05-03 | Palette, progression and melody selectors, each offering Auto plus every item in the library folder on disk | SATISFIED (code and tests); native-click confirmation in UAT | Truths 1, 5, 7, 8, 10, 11 |
| GUI-06 | 05-01, 05-02, 05-03 | Selection reaches the engine over send-only OSC by name; unknown names ignored by the engine with a warning; GUI never crashes | SATISFIED (GUI and offline engine check); live post-window confirmation in UAT | Truths 2, 3, 9, 11 |
| GUI-07 | 05-03 | Selectors don't interfere with the BPM keyboard shortcuts | SATISFIED in automated tests; real click in UAT 3 | Truth 4 |

All three IDs appear in PLAN frontmatter and in REQUIREMENTS.md mapped to Phase 5. No orphaned requirements: REQUIREMENTS.md maps only GUI-05, GUI-06, GUI-07 to Phase 5.

Bookkeeping, not a gap: `REQUIREMENTS.md` still shows GUI-05/06/07 as `Pending` with unchecked boxes, and `ROADMAP.md` still shows Phase 5 as `[ ]`. Update these once the rider closes the UAT.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (all phase files) | - | `TBD`/`FIXME`/`XXX`/`TODO`/`HACK` | None found | No debt markers |
| `supercollider/library/README.md` | 15-17 | Lists library contents without `melodies/classic_lead_loud` (REVIEW WR-01, open) | Warning | Documentation only; the dropdown shows a name the README never mentions |
| `python_app/main.py` | 85-91 | `--hidden` without `--exit-after` yields an invisible app that cannot be closed (REVIEW WR-02, open) | Warning | Test-only flag; no effect on a normal launch |
| `python_app/library_logic.py` | 25-50 | Symlinks pointing outside the library are listed, the engine refuses them (REVIEW IN-01) | Info | Harmless, the engine validates |
| `python_app/library_logic.py` | 40 | Redundant `startswith(".")` (IN-02) | Info | Dead logic |
| `python_app/tests/test_main_launch.py` | 21-43 | Hard-coded defaults, probe without `TimeoutExpired` handling (IN-04) | Info | Test fragility |

The earlier WR-01/WR-02/WR-03 about failed-send retry, listener exceptions and the visible launch-test window are fixed in code and covered by `test_listener_exception_does_not_skip_the_send` and the retry tests. None of the open review items contradicts a must-have truth, so none is a BLOCKER.

### Human Verification Required

Six items, mirrored in `05-UAT.md` (all pending). See the frontmatter `human_verification` list. Summary: (1) launch with the live engine and check the three `auto` confirmation lines; (2) real click, pick `classic_lead_loud`, hear it, re-pick sends nothing; (3) BPM keys after a real click; (4) new file appears on next open; (5) unknown name refused while music continues; (6) no crash with the engine stopped.

### Gaps Summary

No gaps. Every ROADMAP success criterion and PLAN must-have is backed by code I read and tests I ran. The phase is `human_needed` only because the plans require the rider's own end-of-phase check on the real native menu and live engine, which no agent may perform or approve. Two open review warnings (README list, `--hidden` guard) are non-blocking and worth a small follow-up. The library check flaked once under a concurrently running live engine.

---

_Verified: 2026-10-12_
_Verifier: Claude (gsd-verifier)_
