---
phase: 05-library-selectors-in-the-gui
verified: 2026-10-12T16:30:00Z
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
covered_digest: "v3:sha256:e2b965579e3d3416198d72c3f847e7ab4e15cbb398141bce528b686d68c29b9e"
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
**Re-verification:** No. The previous report had no `gaps:` section, so this is a fresh full pass. It supersedes the earlier 05-VERIFICATION.md, which predated the WR-01 (README) and WR-02 (`--hidden` guard) fixes (commits 1649257, 4312a47).
**Mode:** mvp (goal is a valid user story)

## User Flow Coverage

| Step | Expected | Evidence | Status |
|------|----------|----------|--------|
| Open the app | Right-hand column with Palette, Progression, Melody, each on Auto | `view.py:_build_library_column`; `main.py` builds one `LibrarySelector` per `config.LIBRARY_CATEGORIES`; layout tests pass | VERIFIED (code and Tk tests); native look in UAT 1 |
| Open a dropdown | Auto, then `classic`, then every stem in that folder | `library_logic.scan_library` + `LibrarySelector.options()`; `_refresh_library_menu` adds radiobuttons labelled with the raw stem; `test_real_library_folders` scans the real folders | VERIFIED |
| Pick a name | Exact stem (or `auto`) sent to /pp/palette, /pp/progression or /pp/melody once, only on change | `osc_client.send_selection` -> `send_message(address, str(name))`; `main.py` binds the address per category with `functools.partial`; `test_melody_dropdown_pick_reaches_engine_over_udp` reads the real datagram | VERIFIED |
| "Same names I use when giving feedback" | Labels are the library file stems the engine uses | No prettifying in `view.py`/`library_logic.py`; engine `OSCdef(\pp_palette/\pp_progression/\pp_melody)` at `supercollider/main.scd:392-394` take the same stem | VERIFIED |
| Hear it | Engine switches at the next bar and posts a confirmation | Engine side is Phase 4 (`~ppSelect`). Audible result needs the live engine | Human (UAT 1, 2) |

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | SC1: window shows Palette, Progression, Melody; each lists Auto first, then variation files from its folder (hidden and `_template` skipped); empty or missing folder shows Auto only; relaunch picks up new files | VERIFIED | `scan_library` (library_logic.py:24-50) uses `_STEM_RE.fullmatch`, `is_file()`, OSError -> `[]`; `options()` rescans on every call; real folders hold `_template.scd` files that are filtered; `test_real_library_folders`, `test_scan_*` pass |
| 2  | SC2: a pick sends its name over OSC only when the choice changes; app stays send-only and keeps working with the engine not running | VERIFIED (GUI half) | `LibrarySelector.select` returns early on non-str, empty, or unchanged-and-last-send-ok; `send_selection` catches `(OSError, OverflowError, BuildError)`; grep for `recvfrom`, `osc_server`, `OSCUDPServer` in `python_app/*.py` finds nothing. Engine post-window confirmation is a human item |
| 3  | SC3: a name the engine does not know is ignored with a warning, music keeps playing, GUI never crashes | VERIFIED (GUI half) | `select()` does not check the label against disk; `test_name_not_on_disk_is_still_sent`, `test_deleted_selected_file_keeps_its_label_and_another_pick_still_sends` pass. Engine-side refusal is Phase 4 `~ppSelect`; live check is UAT 5 |
| 4  | SC4: after using any selector, Up/Down and the other BPM shortcuts change BPM exactly as before; selectors never take keyboard focus | VERIFIED (automated proxy) | `takefocus=0` set on every OptionMenu button (view.py `_build_library_column`); no `bind`/`focus` calls in the library column; root `<Up>/<Down>/<Shift-*>` bindings unchanged; `test_dropdowns_take_no_focus_and_add_no_key_bindings` and `test_arrow_keys_still_nudge_bpm_after_using_each_dropdown` pass. Real native click is UAT 3 (coincidental-reliance item) |
| 5  | Column sits right of the unchanged controls; window grows wider, not taller; `test_window_layout_order` unmodified | VERIFIED | `library_column.pack(side="left", anchor="n")`; layout tests pass |
| 6  | Launch sends `auto` once each to /pp/palette, /pp/progression, /pp/melody after the unchanged /pp/bpm, /pp/play, /pp/epic, /pp/volume sends; nothing remembered between launches | VERIFIED | `main.py` send order (bpm, play, epic, volume, then selectors); `test_launch_sends_initial_values_then_auto_to_each_library_address` passes; `main.py --port 9 --exit-after 300 --hidden` exits 0 |
| 7  | Fixed dropdown width: changing selection never changes window width | VERIFIED | `config.LIBRARY_DROPDOWN_WIDTH = 20` applied via `button.configure(width=...)`; `test_dropdown_width_is_fixed` |
| 8  | Dropdowns never offer a name the engine would refuse (1-64 chars `[a-z0-9][a-z0-9_]*`, not `auto`, regular `.scd` files), order independent of OS listing | VERIFIED | `_STEM_RE`, `fullmatch`, `sorted(stems)`; `test_scan_length_limit`, `test_scan_order_does_not_depend_on_listing_order` |
| 9  | `send_selection` delivers exactly one OSC string per address and never raises | VERIFIED | `osc_client.py:109-122`; real-socket and unused-port tests pass |
| 10 | Opening a dropdown rebuilds its list from a fresh scan, idempotently, with no watcher, timer or thread | VERIFIED (postcommand level) | `menu.configure(postcommand=lambda s=selector, v=var, m=menu: ...)`; `menu.delete(0, "end")` then add; no `after(`/`Thread` in `view.py` or `library_logic.py`; `test_every_dropdown_rebuilds_on_open`, `test_rebuild_is_idempotent`, `test_new_file_appears_on_next_open`. A real aqua click is UAT 4 |
| 11 | A deleted selected file keeps its label on the button; a removed folder shows Auto only after reopen; nothing raises | VERIFIED | `_refresh_library_menu` never sets `var`; `scan_library` returns `[]` on OSError; named tests pass |
| 12 | Engine and variation files untouched by this phase | VERIFIED | `git status --porcelain -- supercollider python_app` is empty; only `supercollider/library/README.md` differs from the Phase 4 engine baseline |
| 13 | Library README documents "Pick a variation from the app" and lists `classic_lead_loud` | VERIFIED | Section at `supercollider/library/README.md:37`; `melodies/classic_lead_loud` named at line 17 and exists on disk |
| 14 | The rider confirms the end-to-end behavior in the end-of-phase UAT (native menu with fresh list, engine post-window confirmations, no re-send on repeated pick, BPM keys after a real click, no crash with the engine stopped) | UNCERTAIN | By design only the rider can close this (05-03 judgment-tier prohibition). `05-UAT.md` has status `testing`, all 6 results `[pending]`. Neither SUMMARY claims it passed |

**Score:** 13/14 truths verified (0 behavior-unverified; 1 uncertain pending the rider)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `python_app/library_logic.py` | `scan_library`, `to_wire`, `LibrarySelector`; no tkinter/OSC import | VERIFIED | 132 lines, substantive, wired from `view.py` and `main.py`. Includes retry after a failed send (`_last_send_ok`) and send-in-`finally` when a listener raises |
| `python_app/config.py` | Address constants, `LIBRARY_ROOT`, `LIBRARY_CATEGORIES`, `AUTO_*`, `LIBRARY_FIRST_STEM`, `LIBRARY_DROPDOWN_WIDTH` | VERIFIED | All present; `LIBRARY_ROOT` derived from `__file__` |
| `python_app/osc_client.py` | `OscClient.send_selection` | VERIFIED | Error-swallowing, returns bool |
| `python_app/view.py` | Library column, `postcommand` rebuild, `selector_controllers` | VERIFIED | No OSC import |
| `python_app/main.py` | Selectors built from `LIBRARY_CATEGORIES`; `send_initial()` after volume; `--hidden` guarded by `--exit-after > 0` | VERIFIED | `--hidden` alone exits 2 with a clear message |
| `python_app/tests/*` | Selector, layout, GUI-07 and launch tests | VERIFIED | Full suite 191 passed |
| `supercollider/library/README.md` | Pick-from-app section, accurate contents list | VERIFIED | Present |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `view._refresh_library_menu` | `LibrarySelector.select` | radiobutton `command=lambda n=name: selector.select(n)` | WIRED | Default-argument capture |
| `view._build_library_column` | `options()` -> `scan_library` | `menu.configure(postcommand=...)` plus one startup call | WIRED | |
| `main.py` | `OscClient.send_selection` | `functools.partial(client.send_selection, address)` | WIRED | One per category |
| `LibrarySelector` | `config.AUTO_NAME` | `to_wire`, `send_initial` | WIRED | |
| `send_selection` | `supercollider/main.scd` `OSCdef(\pp_palette/\pp_progression/\pp_melody)` | UDP 127.0.0.1:57120, one OSC string | WIRED | Addresses match `main.scd:392-394` |
| `scan_library` | `core/loader.scd ~ppStemValid` | same name rule in Python | WIRED | Rule mirrored; engine file-count check was reported passing on re-run in the prior pass |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| Dropdown menus | entry labels | `Path.iterdir()` on `LIBRARY_ROOT/<folder>` on every open and at startup | Yes | FLOWING |
| OSC sends | name string | picked label -> `to_wire` -> `send_selection` -> UDP; captured as real datagrams on a loopback socket in tests | Yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full Python suite | `.venv/bin/pytest python_app/tests -q` | 191 passed | PASS |
| Targeted tests (GUI-07, UDP pick, launch order) | `pytest -k "arrow_keys_still or take_no_focus or melody_dropdown_pick or launch_sends_initial"` | 4 passed | PASS |
| Real entry point launches cleanly | `.venv/bin/python python_app/main.py --port 9 --exit-after 300 --hidden` | exit 0 | PASS |
| `--hidden` guard | `.venv/bin/python python_app/main.py --hidden` | exit 2, "requires --exit-after > 0" | PASS |
| No receive path in app | grep `recvfrom|osc_server|OSCUDPServer` in `python_app/*.py` | No matches | PASS |
| Engine library check | `scripts/check.sh --library-only` | NOT re-run this pass. A live user `sclang` (pid 85038) and `scsynth` are running and booting a second engine would contend with it; the previous pass saw it flake for that reason. Phase 5 changed no engine file | SKIPPED |

### Probe Execution

Step 7c: SKIPPED. No `scripts/*/tests/probe-*.sh` exists and no plan declares a probe.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| GUI-05 | 05-01, 05-02, 05-03 | Palette, progression and melody selectors, each offering Auto plus every item in the library folder on disk | SATISFIED (code and tests); native-click confirmation in UAT | Truths 1, 5, 7, 8, 10, 11 |
| GUI-06 | 05-01, 05-02, 05-03 | Selection reaches the engine over send-only OSC by name; unknown names ignored by the engine with a warning; GUI never crashes | SATISFIED (GUI side; engine side is Phase 4); live post-window confirmation in UAT | Truths 2, 3, 9, 11 |
| GUI-07 | 05-03 | Selectors don't interfere with the BPM keyboard shortcuts | SATISFIED in automated tests; real click in UAT 3 | Truth 4 |

All three IDs appear in PLAN frontmatter (05-01: GUI-05, GUI-06; 05-02: GUI-05, GUI-06; 05-03: GUI-05, GUI-06, GUI-07) and in REQUIREMENTS.md mapped to Phase 5. No orphaned requirements.

Bookkeeping, not a gap: `REQUIREMENTS.md` still shows GUI-05/06/07 as `Pending` and `ROADMAP.md` shows Phase 5 as `[ ]`. Update once the rider closes the UAT.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (all phase files) | - | `TBD`/`FIXME`/`XXX`/`TODO`/`HACK` | None found | No debt markers |
| `supercollider/library/README.md` | 19 | Says `desc` is "at the top" of each file (REVIEW IN-01, open) | Info | Documentation wording only |
| `python_app/main.py` | 41-42, 90 | Negative `--exit-after` silently treated as 0 (REVIEW IN-02, open) | Info | Test-only flag |
| `supercollider/library/README.md` | 67, 74 | One-liners hard-code `.venv/bin/python` and port 57120 (IN-03, open) | Info | Docs only |
| `python_app/tests/test_main_launch.py` | 21-43 | Hard-coded defaults, fragile skip logic (IN-04, open) | Info | Test fragility |

REVIEW WR-01, WR-02, WR-03 are fixed in code. No open item contradicts a must-have truth, so no BLOCKER.

### Human Verification Required

Six items, mirrored in `05-UAT.md` (all pending). See the frontmatter `human_verification` list. Summary: (1) launch with the live engine and check the three `auto` confirmation lines; (2) real click, pick `classic_lead_loud`, hear it, re-pick sends nothing; (3) BPM keys after a real click; (4) new file appears on next open; (5) unknown name refused while music continues; (6) no crash with the engine stopped.

### Gaps Summary

No gaps. Every ROADMAP success criterion and PLAN must-have is backed by code I read and tests I ran. The phase is `human_needed` only because the plans require the rider's own end-of-phase check on the real native menu and live engine, which no agent may perform or approve. Four info-level review items remain open and are non-blocking.

---

_Verified: 2026-10-12_
_Verifier: Claude (gsd-verifier)_
