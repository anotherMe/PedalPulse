---
phase: 05-library-selectors-in-the-gui
plan: 02
subsystem: ui
tags: [library-selectors, scan-rule, osc, tests, tdd]

requires:
  - phase: 05-library-selectors-in-the-gui
    provides: "scan_library, LibrarySelector, to_wire, OscClient.send_selection (plan 05-01)"
provides:
  - "scan_library applying the engine's exact name rule (_STEM_RE.fullmatch, auto reserved, regular files only)"
  - "Contract tests for scan rule, LibrarySelector and send_selection"
affects: [05-03]

actuals:
  tokens: 6000
  tasks: 2
  commits: 3
plan_head_before: 77e5bb312522a1ecf1dbb38fb09f8a9141f73717
plan_head_after: f1e87c16463295dacb2ad48e11f3ad8be593cd6a
commits: 3

tech-stack:
  added: []
  patterns:
    - "Python mirror of ~ppStemValid: re.fullmatch (never $) so a trailing newline cannot pass"
    - "All scan tests use tmp_path; nothing writes into supercollider/library"

key-files:
  created:
    - python_app/tests/test_library_logic.py
  modified:
    - python_app/library_logic.py
    - python_app/tests/test_osc_client.py

key-decisions:
  - "osc_client.py needed no change: every send_selection test passed against Plan 05-01's code"

requirements-completed: [GUI-05, GUI-06]

coverage:
  - id: D1
    description: "Dropdowns list only names the engine accepts, classic first, then code-point order; hidden, _template, auto, odd names, over-64 and directories are skipped"
    requirement: GUI-05
    verification:
      - kind: unit
        ref: "python_app/tests/test_library_logic.py#test_scan_filters_and_orders"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_library_logic.py#test_scan_length_limit"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_library_logic.py#test_scan_order_does_not_depend_on_listing_order"
        status: pass
    human_judgment: false
  - id: D2
    description: "Empty, missing, unreadable or not-a-folder path gives Auto only and never raises; real library folders list classic first without _template"
    requirement: GUI-05
    verification:
      - kind: unit
        ref: "python_app/tests/test_library_logic.py#test_scan_missing_empty_or_file_path_lists_nothing"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_library_logic.py#test_scan_unreadable_folder_lists_nothing"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_library_logic.py#test_real_library_folders"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_library_logic.py#test_library_root_is_independent_of_cwd"
        status: pass
    human_judgment: false
  - id: D3
    description: "A pick is sent as the exact name once per real change (Auto as auto), keeps state on failed send, still sends names not on disk, ignores empty/non-string"
    requirement: GUI-06
    verification:
      - kind: unit
        ref: "python_app/tests/test_library_logic.py#test_change_sends_once_and_same_pick_sends_nothing"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_library_logic.py#test_name_not_on_disk_is_still_sent"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_library_logic.py#test_empty_or_non_string_pick_is_ignored"
        status: pass
    human_judgment: false
  - id: D4
    description: "send_selection delivers exactly one OSC string per address, returns True with no listener, returns False with one stderr line on OSError/OverflowError/BuildError"
    requirement: GUI-06
    verification:
      - kind: integration
        ref: "python_app/tests/test_osc_client.py#test_send_selection_delivers_osc_string_over_real_socket"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_osc_client.py#test_send_selection_returns_false_on_send_errors"
        status: pass
    human_judgment: false

duration: 10min
completed: 2026-10-12
status: complete
---

# Phase 5 Plan 02: The dropdowns only offer names the engine accepts Summary

**scan_library now applies the engine's exact stem rule (`[a-z0-9][a-z0-9_]{0,63}` via `fullmatch`, `auto` reserved, regular files only), and the LibrarySelector and send_selection contracts are pinned by 24 new tests (157 -> 181 passing).**

## Accomplishments
- RED then GREEN for the scan rule: hostile names (uppercase, space, non-ASCII, dots, trailing newline, `auto`, `_template`, `._` files, a directory named `dir.scd`) and a 65-character stem are no longer listed; a 64-character stem is.
- Empty, missing, file-path and permission-000 folders each give Auto only without raising; order independent of OS listing order; `LIBRARY_ROOT` independent of cwd.
- Selector contract: send only on change, Auto as `auto`, listeners before send, failed send keeps the selection, vanished names still sent, empty/non-string ignored.
- `send_selection` contract over a real loopback socket and for all three error classes.

## Task Commits
1. **Task 1 RED:** `f76d022` (test) - two target tests fail on the planned assertions (hostile names and 65-char stem still listed)
2. **Task 1 GREEN:** `4bd90ed` (feat) - `_STEM_RE.fullmatch`, `auto` reserved, `is_file()`
3. **Task 2:** `f1e87c1` (test) - selector and send_selection contract tests

## TDD Gate Compliance
RED: `test_scan_filters_and_orders` and `test_scan_length_limit` failed (2 failed, 6 passed) with assertion errors for the planned behavior (`'Upper'` listed where `'alpha'` expected; the 65-character stem listed). Semantic assessment: the target tests ran and failed on the intended rule, not on import or fixture faults. The `workflow.tdd_mode` gate was off, so the classifier was not run. GREEN: full suite 165 passed after the change. No REFACTOR needed.

## Files Created/Modified
- `python_app/library_logic.py` - `_STEM_RE`, tightened `scan_library`
- `python_app/tests/test_library_logic.py` - new, 18 tests
- `python_app/tests/test_osc_client.py` - 4 new send_selection tests (6 cases with parametrize)

## Deviations from Plan

None - plan executed exactly as written. `osc_client.py` required no fix. The only setup step was `./run.sh --setup` for the gitignored `.venv`.

## Issues Encountered
None.

## Known Stubs
None.

## Threat Flags
None. T-05-04 and T-05-05 mitigations are implemented and tested; no new surface.

## Next Phase Readiness
Plan 05-03 (rescan on open) can rely on the final `scan_library` rule and the idempotent menu rebuild.

## Self-Check: PASSED
- FOUND: python_app/tests/test_library_logic.py, python_app/library_logic.py
- FOUND commits: f76d022, 4bd90ed, f1e87c1 (RED before GREEN)
- Full suite: 181 passed; `git status` clean for the three variation folders

---
*Phase: 05-library-selectors-in-the-gui*
*Completed: 2026-10-12*
