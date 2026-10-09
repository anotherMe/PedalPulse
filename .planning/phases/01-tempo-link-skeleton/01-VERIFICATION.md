---
phase: 01-tempo-link-skeleton
verified: 2026-10-09T08:15:00Z
status: human_needed
score: 26/27 truths verified (1 routed to human as insufficient_spec backstop)
covered_files: [".planning/phases/01-tempo-link-skeleton/01-01-PLAN.md", ".planning/phases/01-tempo-link-skeleton/01-01-SUMMARY.md", ".planning/phases/01-tempo-link-skeleton/01-02-PLAN.md", ".planning/phases/01-tempo-link-skeleton/01-02-SUMMARY.md", ".planning/phases/01-tempo-link-skeleton/01-03-PLAN.md", ".planning/phases/01-tempo-link-skeleton/01-03-SUMMARY.md", "python_app/bpm_logic.py", "python_app/config.py", "python_app/main.py", "python_app/osc_client.py", "python_app/requirements-dev.txt", "python_app/requirements.txt", "python_app/tests/conftest.py", "python_app/tests/test_bpm_logic.py", "python_app/tests/test_osc_client.py", "python_app/tests/test_tkcheck.py", "python_app/tests/test_view_tk.py", "python_app/tkcheck.py", "python_app/view.py", "run.sh", "scripts/smoke_test.sh", "supercollider/main.scd", "supercollider/smoke_test.scd"]
covered_digest: "v3:sha256:c051a4f4b93040cae81026f504cf87608d0f4e338473cdbbb5bf82f077d3bfc7"
behavior_unverified: 0
overrides_applied: 0
behavior_unverified_items: []
human_verification:
  - test: "Listen to the groove and the limiter ceiling in the SC IDE (Plan 01, D-17/D-13): evaluate supercollider/main.scd, send 300 and 10 via osc_client.py, set ~preGain = 8.0, re-evaluate, open s.meter, listen ~10s, restore ~preGain = 1.0, re-evaluate."
    expected: "Kick + offbeat hat + A-minor offbeat bass loop at 120 BPM, snapping audibly to 180 then 60 BPM on the next beat; with preGain 8 the meter holds at about -1 dBFS with no clip indicator and no crackle; re-evaluating never doubles the loop."
    why_human: "D-17 makes the limiter check a listening/meter judgment and the groove's musical feel (D-13) can only be judged by ear — not inferable from source or test output."
  - test: "Launch ./run.sh, drag the slider, click nudge buttons, toggle 'On top' while a full-screen app is frontmost (Plan 02)."
    expected: "Window is compact, shows 'Sending to 127.0.0.1:57120'; dragging updates the display live and the SC post window shows a single /pp/bpm line only after release; nudges show one net line; the window floats over the full-screen app only when 'On top' is ticked."
    why_human: "Visual window layout, real mouse-drag feel, and window-manager stacking over a full-screen app cannot be asserted by grep or unit test."
  - test: "End-to-end acceptance (Plan 03): evaluate main.scd, run ./run.sh, then (1) drag+release the slider, (2) type 140+Enter, (3) type abc+Enter, (4) type 300+click-away, (5) press Up x3 quickly, (6) hold Shift+Down ~1s, (7) click -5 then +1, (8) tick 'On top' over Zwift."
    expected: "After every gesture the slider, entry and audible tempo agree and the loop retempos on the next beat; the SC post window shows exactly one /pp/bpm line per gesture (never a stream during a drag or key hold); 'abc' reverts without sending; 300 snaps to 180; three quick Up presses produce one line with net +3; the held Shift+Down produces one line after release; the window floats over Zwift when 'On top' is ticked."
    why_human: "Physical keyboard focus, mouse drags, audible tempo and window stacking over a full-screen game cannot be asserted from a withdrawn/off-screen test window — this is the phase's full end-to-end acceptance listen."
  - test: "Confirm the OSC-port-mismatch WARNING actually appears when sclang's language port is not 57120 (e.g. run a second sclang instance holding 57120, then boot a third and evaluate main.scd)."
    expected: "The posted 'PedalPulse: listening for OSC on port <N>' line (N != 57120) is immediately followed by 'PedalPulse WARNING: OSC port is <N> but python_app/config.py sends to 57120 -- quit other sclang instances or pass --port <N>'."
    why_human: "Backstop truth (verification: backstop, PLAN 01-01). The warning branch (main.scd:135-137) is present in source and the logic is unconditional/unambiguous, but no automated check in this phase ever runs sclang on a non-default port, so the branch is never actually exercised by a test. Per the honest-verifier abstention protocol this must not be marked VERIFIED on presence alone."
---

# Phase 1: Tempo Link Skeleton Verification Report

**Phase Goal:** As a rider, I want to set BPM in the app and hear the engine loop change tempo, so that I know the control chain works.
**Verified:** 2026-10-09
**Status:** human_needed
**Re-verification:** No — initial verification
**Mode:** mvp (user-story goal confirmed valid via `user-story.validate`)

## User Flow Coverage

User story: «As a rider, I want to set BPM in the app and hear the engine loop change tempo, so that I know the control chain works.»

| Step | Expected | Evidence | Status |
|------|----------|----------|--------|
| Open the app | `./run.sh` builds `.venv` from python3.13 if missing and opens the PedalPulse window | `run.sh` (venv bootstrap, stamp-guarded installs, `exec .venv/bin/python python_app/main.py "$@"`); live run `timeout 30 ./run.sh --port 57199 --exit-after 800` exits 0 | ✓ launch proven; visual window appearance — human |
| Set BPM — slider | Drag updates the display live and sends nothing; release sends exactly one `/pp/bpm` | `python_app/bpm_logic.py` `BpmController.slider_moved`/`slider_released`; `python_app/view.py` `<ButtonRelease-1>` binding; `python_app/tests/test_view_tk.py::test_slider_live_update_then_release_sends` (pytest: pass) | ✓ logic+wiring proven; audible retempo — human |
| Set BPM — entry | Enter always commits once; focus-out only on change; invalid reverts; out-of-range snaps | `python_app/bpm_logic.py` `parse_bpm_entry`/`apply_entry`; `python_app/view.py` `commit_entry`; `test_bpm_logic.py`, `test_view_tk.py::test_entry_commit_revert_and_unchanged_focusout` (pytest: pass) | ✓ |
| Set BPM — nudge buttons / arrow keys | ±1/±5 debounced to one send 150 ms after the last change; boundaries no-op | `python_app/bpm_logic.py` `Debouncer`/`nudge`; `python_app/view.py` `handle_nudge_key`; `test_bpm_logic.py`, `test_view_tk.py::test_nudges_update_immediately_and_debounce_to_one_send` (pytest: pass) | ✓ |
| Hear the engine retempo | The engine's dedicated `TempoClock` retempos the kick/offbeat-hat/A-minor-bass loop on the next beat to match the sent BPM, clamped 60-180 | `supercollider/main.scd` `OSCdef(\pp_bpm)` → `schedAbs(nextTimeOnGrid(1), ...)`; `scripts/smoke_test.sh` live run: `SMOKE PASS`, 19/19 `CHECK OK:` (boot ready, port posted, python tempo 140, whole-beat apply, clamp table, latest wins, malformed ignored, loopback-only, node bound, limiter no bypass, limiter ceiling, re-evaluation) | ✓ numeric/headless proven; audible confirmation — human |
| Outcome — rider knows the control chain works | The GUI's own `OscClient` is the same client proven end-to-end by the headless smoke test; the live window launches, the unit+widget suite (66/66) and the headless engine suite (19/19 + SMOKE PASS) both pass in this session | All rows above, run live in this verification pass | ✓ programmatically; final audible/visual confirmation — human (see Human Verification) |

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | main.scd boot-gates everything in `s.waitForBoot`, posts the OSC port, autostarts the loop on a dedicated TempoClock (ENG-04) | ✓ VERIFIED | `supercollider/main.scd` contains `s.waitForBoot` (x2), `NetAddr.langPort`; live smoke run: `PedalPulse: listening for OSC on port 57120`, `CHECK OK: boot ready`, `CHECK OK: port posted`, `CHECK OK: initial tempo 120` |
| 2 | `/pp/bpm` from `OscClient` changes `~clock`'s tempo on the next whole beat, no glide (LINK-01) | ✓ VERIFIED | Live smoke run: `CHECK OK: python tempo 140`, `CHECK OK: whole-beat apply` |
| 3 | Engine clamps `/pp/bpm` to 60-180 independent of the GUI, incl. adjacency 59/60/180/181 and floats (TEMPO-03) | ✓ VERIFIED | Live smoke run: `CHECK OK: clamp 300->180/10->60/59->60/181->180/60/180`, `CHECK OK: float 150.5` |
| 4 | Malformed `/pp/bpm` (no-arg, string, NaN) ignored with a warning, handler stays live; latest-wins coalesces same-beat bursts (TEMPO-03, LINK-01 ordering) | ✓ VERIFIED | Live smoke run: `CHECK OK: malformed ignored`, `CHECK OK: latest wins`; log shows 3 `PedalPulse WARNING: ignoring /pp/bpm with invalid argument ...` lines, handler still applied 128 afterward |
| 5 | `OSCdef` accepts only loopback senders; a LAN-address send is ignored (LINK-01, T-01-02) | ✓ VERIFIED | Live smoke run: `CHECK OK: loopback-only` (ran as a real check, not SKIP — a LAN IPv4 existed on this machine) |
| 6 | No enveloped synth leaks nodes; synth count stays bounded under sustained playback (ENG-02) | ✓ VERIFIED | Live smoke run: `CHECK OK: node bound`; `grep -c "doneAction: 2"` = 3 |
| 7 | Master limiter holds the -1 dBFS ceiling at hot preGain, passes silence at preGain 0 (no bypass) (ENG-02) | ✓ VERIFIED | Live smoke run: `CHECK OK: limiter no bypass`, `CHECK OK: limiter ceiling`; `main.scd` contains `Limiter.ar(sig, 0.891251, 0.01)`; all `Out.ar` calls inside instrument SynthDefs write to the `out` arg (bound to `~ppMixBus`), never directly to bus 0 — only `\ppMaster` writes to hardware out |
| 8 | Re-evaluating `main.scd` replaces rather than stacks; keeps last-applied tempo; pending-apply flag not wedged (ENG-04) | ✓ VERIFIED | Live smoke run: `CHECK OK: re-evaluation` (port+ready re-posted, then 128 applied cleanly on the new instance) |
| 9 | Groove sounds musically right; limiter ceiling holds audibly with no crackle at hot preGain (ENG-02, D-13/D-17) | ⚠️ human_judgment (plan-declared) | SUMMARY 01-01 coverage D9: `human_judgment: true`, deferred `<human-check>` — see Human Verification |
| 10 | `./run.sh` bootstraps `.venv` from python3.13, installs requirements (+dev under `--setup`), launches `main.py`, touches nothing outside the project (GUI-04) | ✓ VERIFIED | `run.sh` greps: `python3.13`, `-m venv .venv`, `--setup`, `.pp-requirements.stamp`, `exec .venv/bin/python python_app/main.py "$@"`; 0 `sudo`/`brew`-as-command lines, 0 `--user`; live `timeout 30 ./run.sh --port 57199 --exit-after 800` exits 0 |
| 11 | An interpreter without `_tkinter` prints a clear fix message and exits 1 before any window or `python-osc` import (GUI-04) | ✓ VERIFIED | Live run: `python3.12 python_app/main.py` exits 1, stderr contains `Tkinter is not available`, `./run.sh`, `python3.13`; `main.py` calls `check_tk_compatible()` before importing `osc_client`/`view` (line order confirmed) |
| 12 | TkVersion 8.6 and 9.0 both pass the gate; 8.5 fails with exit 1 (GUI-04) | ✓ VERIFIED | `python_app/tests/test_tkcheck.py` (7 tests) — pytest: pass, no skips |
| 13 | Window opens compactly with slider at 120, `-5 -1 [value] +1 +5` row, status line, unchecked On-top toggle (GUI-01, D-06/D-22) | ⚠️ human_judgment (plan-declared) | SUMMARY 01-02 coverage D9: `human_judgment: true` — see Human Verification |
| 14 | On launch the app sends `/pp/bpm 120.0` exactly once (LINK-01) | ✓ VERIFIED | `test_bpm_logic.py::test_send_initial_sends_once` — pytest: pass |
| 15 | Slider drag updates display live, sends nothing; release sends exactly one final value (LINK-01, D-20) | ✓ VERIFIED | `test_bpm_logic.py`, `test_view_tk.py::test_slider_live_update_then_release_sends` — pytest: pass |
| 16 | Nudge buttons update immediately, debounce to one net send 150 ms after the last click (LINK-01, D-21) | ✓ VERIFIED | `test_bpm_logic.py::test_nudge_three_times_...`, `test_view_tk.py::test_nudges_update_immediately_and_debounce_to_one_send` — pytest: pass |
| 17 | Boundary adjacency: 178+5→180; at 180, +1/+5 no-op/no-send; at 60, -1/-5 no-op/no-send (GUI-01) | ✓ VERIFIED | `test_bpm_logic.py::test_nudge_at_upper_bound_adjacency`, `test_nudge_at_lower_bound_adjacency`; `test_view_tk.py::test_bounds_adjacency_at_upper_bound_sends_nothing` — pytest: pass |
| 18 | A pending debounced nudge is cancelled by a slider release (GUI-01 ordering, LINK-01 ordering) | ✓ VERIFIED | `test_bpm_logic.py::test_slider_release_before_debounce_window_cancels_pending_nudge_send` — pytest: pass |
| 19 | Every slider release sends exactly one message, even unchanged (LINK-01 adjacency) | ✓ VERIFIED | `test_bpm_logic.py::test_two_releases_with_no_change_send_two_messages` — pytest: pass |
| 20 | `OscClient.send_bpm` never raises when nothing listens; returns False on OSError (LINK-01 empty) | ✓ VERIFIED | `test_osc_client.py` (7 tests, real socket + mocked `sendto`) — pytest: pass |
| 21 | Audible retempo from slider/nudges matches the posted `/pp/bpm` line; On-top floats over a full-screen app (GUI-01, LINK-01, D-12) | ⚠️ human_judgment (plan-declared) | SUMMARY 01-02 coverage D10: `human_judgment: true` — see Human Verification |
| 22 | Entry field sits between nudge pairs, always shows the same BPM as the slider (GUI-01, D-06) | ✓ VERIFIED | `test_view_tk.py::test_build_shows_initial_state`, `::test_slider_live_update_then_release_sends` — pytest: pass |
| 23 | Enter always commits once (even unchanged); focus-out commits only on change — no double-send (GUI-01, D-10) | ✓ VERIFIED | `test_bpm_logic.py::test_apply_entry_force_true_same_value_sends_again`, `::test_apply_entry_force_false_unchanged_value_notifies_but_does_not_send`; `test_view_tk.py::test_entry_commit_revert_and_unchanged_focusout` — pytest: pass |
| 24 | Invalid entry text reverts the field, sends nothing (GUI-01 empty) | ✓ VERIFIED | `test_bpm_logic.py::test_parse_bpm_entry_invalid_returns_none`, `::test_apply_entry_invalid_text_reverts_without_send` — pytest: pass |
| 25 | Out-of-range entry snaps (300→180, 10/-5→60, 1e3→180); decimals round half up (GUI-01, D-09/D-10) | ✓ VERIFIED | `test_bpm_logic.py::test_parse_bpm_entry_valid` — pytest: pass |
| 26 | Up/Down ±1, Shift+Up/Down ±5 while window has focus, sharing the nudge debounce (GUI-01, D-11) | ✓ VERIFIED | `view.py` binds `<Up>`/`<Down>`/`<Shift-Up>`/`<Shift-Down>` on `root` → `handle_nudge_key` → `controller.nudge`; `test_view_tk.py::test_key_bindings_registered_and_handle_nudge_key_works` — pytest: pass. *(Real physical-keyboard focus routing across widgets is explicitly deferred to the human check per the plan — see Human Verification item 3.)* |
| 27 | Entry commit cancels a pending debounced nudge send (ordering, GUI-01/LINK-01) | ✓ VERIFIED | `test_bpm_logic.py::test_apply_entry_cancels_pending_nudge_debounce`; `test_view_tk.py::test_entry_commit_cancels_pending_nudge_send` — pytest: pass |
| 28 | Under real Tk 9.0.3, Scale/Entry/Button widgets drive the controller correctly (D-02 Tk 9 smoke test) | ✓ VERIFIED | `test_view_tk.py` — 8/8 tests pass, 0 skipped, real `root.after` scheduler |
| 29 | End-to-end audible/physical acceptance: all controls + physical keys agree with engine tempo; On-top floats over Zwift (GUI-01, LINK-01) | ⚠️ human_judgment (plan-declared) | SUMMARY 01-03 coverage D8: `human_judgment: true` — see Human Verification |
| 30 | If sclang's language port isn't 57120, the posted line + WARNING make the mismatch visible (backstop, ENG-04 concurrency) | ⚠️ insufficient_spec (backstop abstention) | Logic present and unconditional at `main.scd:135-137`, but no test in this phase ever boots sclang on a non-default port — the branch is never actually exercised. Per the backstop-abstention protocol this cannot be marked VERIFIED on presence alone — see Human Verification item 4 |

**Score:** 26/27 automatically-verifiable truths VERIFIED (29 total truths minus 1 backstop = 28 scorable; 4 are plan-declared `human_judgment: true` items excluded from the automated score, same as the backstop item). All automated checks that could run, ran and passed: 66/66 pytest, 19/19 headless smoke checks, `SMOKE PASS`, 2 live launch/gate checks.

### Deferred Items

None — all truths map to this phase; no later-phase deferrals apply.

### Advisory (New Scope, Unevidenced)

N/A — this is an initial verification (`is_re_verification = false`); the Step 7c convergence-evidence gate only applies to re-verification passes.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `supercollider/main.scd` | Boot-gated entry file: SynthDefs, limiter bus, TempoClock loop, OSCdef | ✓ VERIFIED | Exists, substantive (138 lines), all acceptance greps hit (`s.waitForBoot` x2, `Limiter.ar`, `0.891251`, `OSCdef(\pp_bpm`, `srcID: NetAddr("127.0.0.1", nil)`, `nextTimeOnGrid(1)`, `clip(60, 180)`, `isNaN`, `doneAction: 2` x3, `quant: 4` x3) |
| `supercollider/smoke_test.scd` | Headless engine+link test harness | ✓ VERIFIED | Exists, contains `SMOKE PASS`; live run produced it |
| `scripts/smoke_test.sh` | One-command terminal runner | ✓ VERIFIED (see Anti-Patterns for a non-blocking diagnostic-output bug on the failure path) | Exists, executable, live run exits 0 with `SMOKE PASS` |
| `python_app/config.py` | OSC constants | ✓ VERIFIED | Exists, contains `OSC_PORT = 57120` |
| `python_app/osc_client.py` | `OscClient` + raw-send CLI | ✓ VERIFIED | Exists, `class OscClient`, `def send_bpm`, `def main(`, `SimpleUDPClient`, `except OSError` all present |
| `python_app/requirements.txt` | Pinned dependency | ✓ VERIFIED | Contains `python-osc==1.10.2` |
| `run.sh` | venv bootstrap + launcher | ✓ VERIFIED | Executable, all acceptance greps hit, 0 sudo/brew/--user |
| `python_app/tkcheck.py` | Tk gate | ✓ VERIFIED | `MIN_TK_VERSION = 8.6`, `check_tk_compatible`, `sys.exit(1)`, `FIX_HINT`, no module-level tkinter import |
| `python_app/bpm_logic.py` | Pure BPM state/send policy | ✓ VERIFIED | `clamp_bpm`, `Debouncer`, `BpmController`, `parse_bpm_entry`, `apply_entry`; no tkinter import, no `eval(` |
| `python_app/view.py` | Tk widgets | ✓ VERIFIED | `class BpmWindow`, `tk.Entry`, `<Return>`/`<KP_Enter>`/`<FocusOut>`/`<Shift-Up>`/`<Shift-Down>`, `commit_entry`, `handle_nudge_key`; `value_label` fully removed (grep count 0) |
| `python_app/main.py` | Entry point | ✓ VERIFIED | `check_tk_compatible()` precedes `osc_client` import; `--port`/`--exit-after`/`send_initial()`/`send=client.send_bpm` all present |
| `python_app/requirements-dev.txt` | Dev dependency | ✓ VERIFIED | `pytest==8.4.2`, `-r requirements.txt` |
| `python_app/tests/conftest.py` | sys.path setup | ✓ VERIFIED | Exists, used successfully by the full pytest run |
| `python_app/tests/test_view_tk.py` | Tk 9 widget smoke test | ✓ VERIFIED | 8 `def test_` functions, uses real `root.after`, all pass, none skipped |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `python_app/osc_client.py` | `supercollider/main.scd` | UDP `/pp/bpm <float>` → `OSCdef(\pp_bpm)` | ✓ WIRED | `verify.key-links` tool: pattern found |
| `supercollider/main.scd OSCdef(\pp_bpm)` | `~clock` tempo | `schedAbs(nextTimeOnGrid(1), ...)` sets `~clock.tempo` | ✓ WIRED (manual) | Tool reported "source file not found" (symbolic `from:`, not a path — tooling limitation); manually confirmed via `grep -n "schedAbs\|nextTimeOnGrid\|clock.tempo" supercollider/main.scd` → lines 121-122 present; live smoke run proves it functions (`whole-beat apply`, `python tempo 140`) |
| `Pbindef(\ppKick/\ppHat/\ppBass)` | `\ppMaster` limiter | instruments → `~ppMixBus` → `\ppMaster` → `Limiter.ar` → `Out.ar(0)` | ✓ WIRED (manual) | Same tooling limitation; manually confirmed all three Pbindefs set `\out, ~ppMixBus` and only `\ppMaster` writes `Out.ar(out, Limiter.ar(...))`; live smoke run proves no bypass (`limiter no bypass`, `limiter ceiling`) |
| `supercollider/smoke_test.scd` | `python_app/osc_client.py` | spawns `.venv/bin/python osc_client.py ... --port <langPort>` | ✓ WIRED | `verify.key-links` tool: pattern found |
| `python_app/main.py` | `python_app/tkcheck.py` | `check_tk_compatible()` before other imports | ✓ WIRED | `verify.key-links` tool: pattern found |
| `python_app/view.py Scale` | `BpmController.slider_released` | `<ButtonRelease-1>` binding | ✓ WIRED (manual) | `view.py:51` `self.scale.bind("<ButtonRelease-1>", lambda _event: controller.slider_released())` |
| `python_app/bpm_logic.py BpmController` | `python_app/osc_client.py OscClient.send_bpm` | `send=client.send_bpm` injected in `main.py` | ✓ WIRED (manual) | `main.py:49` `BpmController(send=client.send_bpm, schedule=root.after, cancel=root.after_cancel)` |
| `python_app/view.py Entry <Return>/<KP_Enter>/<FocusOut>` | `BpmController.apply_entry` | `BpmWindow.commit_entry(force=...)` | ✓ WIRED (manual) | `view.py:79-81` bindings → `commit_entry` → `view.py:132` `self.controller.apply_entry(...)` |
| `python_app/view.py root <Up>/<Down>/<Shift-Up>/<Shift-Down>` | `BpmController.nudge` | `handle_nudge_key(delta)` | ✓ WIRED (manual) | `view.py:109-112` bindings → `handle_nudge_key` → `bpm_logic.py` `nudge(delta)` |

All nine key links hold. Four show `verified: false` from the `verify.key-links` automated tool purely because their `from:` field in PLAN frontmatter is a symbolic description ("supercollider/main.scd OSCdef(\pp_bpm)") rather than a bare relative path — a tooling limitation, not a wiring gap. Each was independently confirmed by reading the actual source and, for the two engine-side links, by the live headless smoke-test run exercising the exact behavior the link claims.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full Python test suite | `.venv/bin/pytest python_app/tests -q` | `66 passed in 2.38s` | ✓ PASS |
| Headless engine+link smoke test | `bash scripts/smoke_test.sh` | `SMOKE PASS`, exit 0, 19/19 `CHECK OK:`, 0 `CHECK SKIP:` | ✓ PASS |
| App launch under real Tk 9 | `timeout 30 ./run.sh --port 57199 --exit-after 800` | exit 0 | ✓ PASS |
| Tk-incompatible interpreter gate | `python3.12 python_app/main.py` | exit 1, `Tkinter is not available`, `./run.sh`, `python3.13` on stderr | ✓ PASS |
| Limiter/mix-bus routing (no bypass) | `grep -n "Out.ar" supercollider/main.scd` | only `\ppMaster`'s `Out.ar` targets bus 0; every instrument SynthDef's `Out.ar` targets its `out` arg (bound to `~ppMixBus`) | ✓ PASS |
| `set -e` failure-diagnostics repro | Minimal repro of `scripts/smoke_test.sh`'s `cmd; rc=$?` pattern under `set -euo pipefail` | Script exits silently with no `cat`/message reaching the terminal on a failing command | ✗ CONFIRMS CR-01 (see Anti-Patterns) |

### Probe Execution

N/A — no `scripts/*/tests/probe-*.sh` convention in this project; the project's own `scripts/smoke_test.sh` + `supercollider/smoke_test.scd` serve the equivalent role and are covered under Behavioral Spot-Checks above.

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|---|---|---|---|---|
| ENG-02 | 01-01 | Master limiter never clips | ✓ SATISFIED | `limiter no bypass` + `limiter ceiling` live `CHECK OK`; D9 musical/listening judgment deferred to human |
| ENG-04 | 01-01 | Single sclang entry file waits for boot, posts OSC port | ✓ SATISFIED | `boot ready`/`port posted`/`initial tempo 120`/`re-evaluation` live `CHECK OK` |
| TEMPO-03 | 01-01 | BPM clamped 60-180 by the engine | ✓ SATISFIED | Full clamp table + float 150.5 live `CHECK OK` |
| GUI-01 | 01-02, 01-03 | Slider, entry, nudge buttons stay in sync | ✓ SATISFIED | 66/66 pytest incl. 8/8 real-widget `test_view_tk.py`; D9/D10/D8 visual/audible judgments deferred to human |
| GUI-04 | 01-02 | App launches under Tk 8.6; clear warning on incompatible Tk | ✓ SATISFIED | `test_tkcheck.py` (7 tests) + live `python3.12` gate check |
| LINK-01 | 01-01, 01-02, 01-03 | Every control change reaches the engine over OSC, throttled/coalesced | ✓ SATISFIED | `python tempo 140`/`latest wins`/debounce tests all pass |

No orphaned requirements: REQUIREMENTS.md's Phase 1 row maps exactly ENG-02, ENG-04, TEMPO-03, GUI-01, GUI-04, LINK-01, and all six are declared across the three plans' `requirements:` frontmatter with no gaps either direction.

### Decision Coverage

`gsd_run query check.decision-coverage-verify` against `01-CONTEXT.md`: **24/24 trackable decisions honored** by shipped artifacts, commits, and SUMMARY.md content. `not_honored: []`. (Non-blocking gate; reported for completeness.)

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `scripts/smoke_test.sh` | 37-38 | `set -euo pipefail` (line 7) + bare `cmd; rc=$?` on a command that can exit non-zero — the classic errexit-defeats-diagnostics anti-pattern. Confirmed via an independent minimal repro in this verification pass: under `set -e`, the failing command terminates the script immediately, so `rc=$?`, the `cat "$LOG"` dump, and the `"smoke test FAILED (log: ...)"` message never execute. | ⚠️ Warning | Does **not** break the must-have "exits 0 only when SMOKE PASS" contract — bash still propagates the failing command's own non-zero exit code correctly, and the full log is still written to disk (just not echoed to the terminal). On a genuine engine failure, a developer loses the inline diagnostic dump and must manually `cat` the log path themselves. Already identified and tracked as **CR-01 (critical, disposition: open)** in `.planning/phases/01-tempo-link-skeleton/01-REVIEW-DISPOSITION.md` — carried forward here, not newly discovered. Not classified as a Blocker: it does not prevent the phase's observable truths (all independently verified live in this pass via the actual passing smoke run), and the current run's exit-code behavior is unaffected. Recommended fix (per 01-REVIEW.md): `set +e` around the sclang invocation, or `$TIMEOUT_CMD ... || rc=$?`. |
| `python_app/view.py` | 123-136, 81 | Enter-commit's `root.focus_set()` triggers an implicit, untested second `apply_entry()` call via the resulting `<FocusOut>` event (WR-01, open). Harmless today (the second call is a no-op re-notify) but untested and fragile to future side-effecting changes to `apply_entry`. | ⚠️ Warning | Carried forward from `01-REVIEW.md`/`01-REVIEW-DISPOSITION.md` (disposition: open). Does not affect any must-have truth; all entry-commit truths (22-25, 27) are independently proven by passing tests that call `apply_entry`/`commit_entry` directly. |
| `python_app/bpm_logic.py` | 138-162 | Forced-but-unchanged entry commit (`force=True`, value unchanged) skips `_notify()`, leaving the Entry text un-normalized (e.g. "150.00" stays shown instead of snapping to "150") — contradicts the method's own docstring (WR-02, open). | ⚠️ Warning | Carried forward from `01-REVIEW.md` (disposition: open). Cosmetic text-normalization gap only; no truth in this phase asserts text normalization on the forced-unchanged path specifically, so it is not a must-have regression. |
| `python_app/view.py` | 22-114 | `BpmWindow.__init__` is a single ~90-line method (IN-01, open) | ℹ️ Info | Maintainability note only, carried forward from `01-REVIEW.md`. |
| `run.sh` | 29-37 | `--setup` prints "venv ready" before the Tk compatibility check that can still fail (IN-02, open) | ℹ️ Info | Cosmetic message-ordering note only, carried forward from `01-REVIEW.md`. |

No debt markers (`TBD`/`FIXME`/`XXX`), no `TODO`/`HACK`/`PLACEHOLDER`, no "coming soon"/"not yet implemented" text, no empty-return stubs, and no hardcoded-empty-data patterns found in any of the 17 files this phase created or modified. The one textual hit on "not available" (`tkcheck.py:42`, `"Tkinter is not available in this Python..."`) is the intended GUI-04 error message, not a stub — confirmed by reading it in context.

### Human Verification Required

### 1. Listening/meter judgment: groove and limiter ceiling (Plan 01)

**Test:** Evaluate `supercollider/main.scd` in the SuperCollider IDE. Run `.venv/bin/python python_app/osc_client.py 300` then `.venv/bin/python python_app/osc_client.py 10`. Set `~preGain = 8.0;` at the top of `main.scd`, re-evaluate, open `s.meter`, listen ~10s, set `~preGain = 1.0;`, re-evaluate again.
**Expected:** Kick + offbeat hat + A-minor offbeat bass loop at 120 BPM; 300 snaps the loop to 180 BPM on the next beat, 10 drops it to 60; at `~preGain` 8 the loop is denser but the meter holds at about -1 dBFS with no clip indicator and no crackle; re-evaluating never doubles the loop.
**Why human:** D-17 makes the limiter check a listening/meter judgment and the groove's musical feel (D-13) can only be judged by ear.

### 2. GUI window layout and On-top stacking (Plan 02)

**Test:** Launch `./run.sh` from the repo root. Drag the slider slowly from 120 to about 150 and release; click +1 three times quickly; click -5; tick "On top" and bring Zwift (or any full-screen app) to the front; untick it.
**Expected:** The window is small and shows "Sending to 127.0.0.1:57120" (matching the posted "listening for OSC on port 57120"). The value updates live during the drag, but the SC post window shows a single "/pp/bpm" line only after release, and the loop retempos on the next beat. Three quick +1 clicks produce one post line with the net value. With "On top" ticked the window floats above the full-screen app; unticked, it does not.
**Why human:** Audible tempo change, real mouse-drag behavior and window-manager stacking over a full-screen app cannot be verified by grep or unit tests.

### 3. End-to-end phase acceptance (Plan 03)

**Test:** Evaluate `supercollider/main.scd`, then run `./run.sh`. (1) Drag the slider and release. (2) Type 140 in the entry and press Enter. (3) Type `abc` and press Enter. (4) Type 300 and click elsewhere (focus-out). (5) Press Up three times quickly. (6) Hold Shift+Down for about a second. (7) Click -5 and +1. (8) Tick "On top" while Zwift is full-screen.
**Expected:** After every gesture, the slider, the entry and the tempo you hear agree, and the loop retempos on the next beat. The SC post window shows exactly one "/pp/bpm" line per gesture, never a stream during a drag or a key hold. "abc" reverts the field without sending. 300 snaps to 180. Three quick Up presses produce one line with the net +3. The held Shift+Down produces one line after you let go. The window floats over Zwift when "On top" is ticked.
**Why human:** Physical keyboard focus, mouse drags, audible tempo and window stacking over a full-screen game cannot be asserted from a withdrawn/off-screen test window. This is the phase's full end-to-end acceptance listen.

### 4. OSC-port-mismatch warning (backstop truth)

**Test:** Start a second sclang instance already holding port 57120, then boot and evaluate `main.scd` in a third sclang instance (which will get a different language port).
**Expected:** The posted "PedalPulse: listening for OSC on port \<N\>" line (N != 57120) is immediately followed by "PedalPulse WARNING: OSC port is \<N\> but python_app/config.py sends to 57120 -- quit other sclang instances or pass --port \<N\>".
**Why human:** This truth is explicitly declared `verification: backstop` in the 01-01 PLAN. The branch exists and is unconditional in source (`main.scd:135-137`), but no automated check in this phase actually runs sclang on a non-default language port, so the warning path is never exercised by any test. Per the honest-verifier abstention protocol, presence-in-source is not sufficient to mark this VERIFIED.

### Gaps Summary

No gaps. Every must-have artifact exists, is substantive, and is wired; every key link holds (confirmed manually where the automated tool's path-matching fell short on symbolic `from:` descriptions); all 66 automated Python tests pass; the headless SuperCollider smoke test passes all 19 checks with `SMOKE PASS`; both live launch/gate checks (`./run.sh --port 57199 --exit-after 800`, `python3.12 python_app/main.py`) behave exactly as specified; all 6 phase requirements are satisfied with no orphans; all 24 CONTEXT.md decisions are honored; security (0 open threats) and validation (66/66, 19/19, nyquist_compliant: true) sign-offs are both green.

The phase routes to **human_needed**, not `passed`, strictly because:
1. Four truths are explicitly plan-declared `human_judgment: true` (the audible/visual acceptance checks every one of the three plans deliberately deferred to end-of-phase UAT per `workflow.human_verify_mode=end-of-phase`) — these are exactly the "hear the engine loop change tempo" and "window looks/behaves right" truths that are the literal core of this phase's user story and cannot be proven by source inspection or automated tests alone.
2. One backstop truth (OSC port mismatch warning) is present in source but not exercised by any test, so per the abstention protocol it cannot be marked VERIFIED on presence alone.

Separately, one already-tracked, confirmed-reproducible code-review finding (CR-01, `scripts/smoke_test.sh`'s `set -e` diagnostics bug) is carried forward as a non-blocking Warning: it does not affect the must-have exit-code contract and does not prevent any observable truth in this phase, but the developer should fix it before relying on the script's failure-path diagnostics.

---

_Verified: 2026-10-09_
_Verifier: Claude (gsd-verifier)_
