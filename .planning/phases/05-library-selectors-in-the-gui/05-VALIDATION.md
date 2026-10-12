---
phase: "05"
slug: "library-selectors-in-the-gui"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: true) (#2117)
status: validated
nyquist_compliant: true
wave_0_complete: true
created: "2026-10-12"
---

# Phase 05 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from `05-RESEARCH.md` § Validation Architecture. Paths below are the research-proposed layout. If the plans settle on a different layout, the plans are authoritative and validate-phase reconciles this file.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 8.4.2 on the project `.venv` (Python 3.13.12): real Tk 9.0.3 (aqua) for view tests, mocked or real loopback sockets for OSC sends. The engine already covers unknown-name handling in `supercollider/library_test.scd`, and this phase does not change it |
| **Config file** | none. `python_app/tests/conftest.py` puts `python_app/` on `sys.path` |
| **Quick run command** | `.venv/bin/pytest python_app/tests/test_library_logic.py python_app/tests/test_osc_client.py python_app/tests/test_view_tk.py -q` |
| **Full suite command** | `.venv/bin/pytest python_app/tests -q` |
| **Estimated runtime** | ~5 s for the full suite (150 tests at baseline, measured during research) |

This phase is GUI and Python only. No engine change is needed: `~ppSelect` (`supercollider/core/loader.scd`) already posts a line for every outcome (selected, auto, invalid name, missing file). Do not use the engine smoke suite as this phase's gate. It is unaffected by this work, and it contains a known flaky check (`epic glide up`, STATE.md) unrelated to this phase.

---

## Sampling Rate

- **After every task commit:** Run the quick run command (or just the test files the task touched)
- **After every plan wave:** Run `.venv/bin/pytest python_app/tests -q`
- **Before `/gsd-verify-work`:** Full pytest suite green, then the manual UAT below
- **Max feedback latency:** ~5 s

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-01-T1 (tracer) | 05-01 | 1 | GUI-05, GUI-06 | — | Only the picked stem is sent, as one OSC string | Tk + UDP | `.venv/bin/pytest -q python_app/tests/test_view_tk.py::test_melody_dropdown_pick_reaches_engine_over_udp` | ✅ | ✅ green |
| 05-01-T2 | 05-01 | 1 | GUI-05, GUI-06 | — | No receive path; launch sends identical datagrams | Tk + subprocess | `.venv/bin/pytest -q python_app/tests/test_view_tk.py python_app/tests/test_main_launch.py` | ✅ | ✅ green |
| 05-02-T1 (tdd) | 05-02 | 2 | GUI-05 | — | Scan lists only names the engine accepts (`[a-z0-9][a-z0-9_]{0,63}`, not `auto`, regular files only) | unit | `.venv/bin/pytest -q python_app/tests/test_library_logic.py` | ✅ | ✅ green |
| 05-02-T2 | 05-02 | 2 | GUI-06 | — | `send_selection` returns False on send errors without raising | unit | `.venv/bin/pytest -q python_app/tests/test_library_logic.py python_app/tests/test_osc_client.py` | ✅ | ✅ green |
| 05-03-T1 | 05-03 | 3 | GUI-05 | — | Rebuild on open is idempotent; survives deleted files/folders | Tk | `.venv/bin/pytest -q python_app/tests/test_view_tk.py -k "rebuild or deleted or removed"` | ✅ | ✅ green |
| 05-03-T2 | 05-03 | 3 | GUI-07 | — | Dropdowns take no focus; BPM keys still nudge after each dropdown | Tk + engine check | `.venv/bin/pytest -q python_app/tests/test_view_tk.py` and `bash scripts/check.sh --library-only` | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

Requirement-level test map (from research, pending task assignment):

| Requirement | Behavior | Test Type | Automated Command | File Exists |
|-------------|----------|-----------|-------------------|-------------|
| GUI-05 | Scan: `.scd` only; skips hidden files, `_`-prefixed stems (`_template`), the reserved stem `auto`, invalid stems and directories; `classic` first, then A–Z; a missing, empty or not-a-folder path gives `[]` without raising | unit | `.venv/bin/pytest python_app/tests/test_library_logic.py -q` | ✅ exists |
| GUI-05 | `options()` is `Auto` + scan and re-scans on every call (add a file, call again, it appears) | unit | `.venv/bin/pytest python_app/tests/test_library_logic.py -q` | ✅ exists |
| GUI-05 | Window shows three labelled dropdowns in order Palette, Progression, Melody, each starting on `Auto`; menu entries equal `options()`; the `postcommand` rebuild is idempotent and picks up a new file | Tk | `.venv/bin/pytest python_app/tests/test_view_tk.py -q` | ✅ extended |
| GUI-05 | Real library folders list `classic` (plus `classic_lead`, `classic_lead_loud` for melodies) and never `_template` | unit | `.venv/bin/pytest python_app/tests/test_library_logic.py -q` | ✅ exists |
| GUI-06 | `send_selection` delivers the address plus an OSC string; returns False on `OSError` and on `BuildError`/`OverflowError` without raising | unit | `.venv/bin/pytest python_app/tests/test_osc_client.py -q` | ✅ extended |
| GUI-06 | Controller: a change sends once, in wire form (`Auto` → `auto`); picking the current item sends and notifies nothing; `send_initial` sends `auto` unconditionally; a failed send never rolls state back; an unknown or vanished name is still sent | unit | `.venv/bin/pytest python_app/tests/test_library_logic.py -q` | ✅ exists |
| GUI-06 | Engine ignores an unknown name with a warning and the music keeps playing | already covered engine-side | `bash scripts/check.sh --library-only` (existing `unknown name` check) | ✅ exists |
| GUI-07 | After invoking a menu entry on each dropdown, `focus_get()` is not a selector, each `takefocus` is `"0"`, and `<Up>` still nudges BPM by 1 (and `<Shift-Down>` by 5) | Tk | `.venv/bin/pytest python_app/tests/test_view_tk.py -q` | ✅ extended |
| GUI-07 | Existing layout test still passes (`window.scale.master.pack_slaves()` unchanged) | Tk | `.venv/bin/pytest python_app/tests/test_view_tk.py -q` | ✅ exists |

---

## Wave 0 Requirements

- [x] `python_app/tests/test_library_logic.py`: folder scan and selector controller tests (GUI-05, GUI-06)
- [x] `_build_all` in `python_app/tests/test_view_tk.py` updated to pass and return the selector controllers, in the same task that changes the `BpmWindow` signature
- [x] Framework install: none (pytest 8.4.2 and python-osc already in `.venv`; Tk 9.0.3 present)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Startup sends `auto` to all three addresses and the engine confirms | GUI-06 (D-04) | Needs the real engine post window | Launch via `./run.sh` with the engine running. The post window shows one `auto` confirmation line each for `/pp/palette`, `/pp/progression` and `/pp/melody` |
| A real click opens the native menu with freshly scanned entries | GUI-05 (D-08) | Synthetic events never reach `tk::MbPost`, so the native aqua popup cannot be driven headlessly (research assumptions A1/A3) | Open the Melody dropdown: `Auto, classic, classic_lead, classic_lead_loud`. In another terminal copy a melody file to a new name (for example `cp supercollider/library/melodies/_template.scd supercollider/library/melodies/zz_try.scd`, then delete it afterwards) and open the dropdown again without relaunching: the new name appears |
| Picking sends only on change, confirmed by the engine | GUI-06 (D-05) | Needs the real engine post window | Pick `classic_lead_loud`: the post window shows the selection line for `/pp/melody classic_lead_loud`. Pick it again: nothing new is posted |
| BPM shortcuts survive a real dropdown interaction | GUI-07 | Native menu focus handling on aqua is only partly reachable from tests | Right after using a dropdown, press Up, Down, Shift-Up and Shift-Down: BPM changes exactly as before |
| Engine down, or a vanished name: no crash, music keeps playing | GUI-06 | Needs the real engine started and stopped | Stop the engine and pick items: the app does not crash or freeze. Restart the engine, remove a file while it is selected, then send that name with the README one-liner: the post window shows the refusal lines and the music keeps playing |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 10s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** validated 2026-10-12 (validate-phase: 0 gaps, 188 tests green)

## Validation Audit 2026-10-12

| Metric | Count |
|---|---|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |
