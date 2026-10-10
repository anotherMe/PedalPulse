# Milestones

## v1.0 Technical Proof (Shipped: 2026-10-10)

**Phases completed:** 3 phases, 11 plans, 23 tasks

**Key accomplishments:**
- Python OscClient sends /pp/bpm over UDP to a boot-gated sclang OSCdef that clamps, coalesces, and applies tempo on the next beat to a kick+offbeat-hat+A-minor-bass loop running through a -1 dBFS master limiter, all proven headless by one `scripts/smoke_test.sh` command.
- `./run.sh` provisions a python3.13 `.venv`, gates startup on a lazily-imported `tkinter.TkVersion` check, and wires a Tk-free, debounce-tested `BpmController` through a slider (release-only send) and `−5 −1 [value] +1 +5` nudge buttons to the Plan 01 `OscClient`.
- Entry-field parsing and commit rules (TDD RED/GREEN) added to `BpmController`, then a Tk `Entry` with Enter/focus-out/arrow-key bindings replaces the read-only value label in `BpmWindow`, proven against real Tk 9.0.3 widgets by a new smoke test that caught two genuine environment quirks.
- `/pp/play <int>` transport wired end to end -- real Python CLI to `OSCdef(\pp_play)` to `~ppStart`/`~ppStop` -- with a clean group-wide gate-release stop, bar-synced `doReset` restart, and an idempotent, validated, loopback-only handler, raising the headless smoke harness from 19 to 26 checks.
- A `PlayController` (test-first, RED->GREEN) tracks play/stop intent with int-only sends, wired to a single Start/Stop toggle button in the Tkinter window that always names the next click's action, and to `OscClient.send_play` in `main.py` with the play state announced once on launch.
- Phase 1's instant "snap at the next beat" BPM apply is replaced by a single long-lived `~ppRampStepper` Routine that glides the tempo over 8 beats (2 bars) starting on a whole beat, and retargets immediately -- no restart, no jump -- when a new BPM arrives mid-glide.
- Added clap, 16th-note A-minor arpeggio and sustained Am pad layers to the shared `~clock`, extended `~ppLayers` to all six voices, and proved headlessly that Stop releases a held pad and in-flight notes within 2.0s of a ~3s natural tail.
- `/pp/epic` now drives one shared `Lag.kr` smoother into a single `\ppFx` synth (softclip drive, `RLPF` cutoff, HF-exciter richness, `FreeVerb2` reverb) sitting between the groove and the limiter, proven headlessly via a 52-check smoke suite.
- Five EPIC zone preset buttons (Recovery/Endurance/Tempo/Threshold/VO2) now live in the Tkinter window, each sending its preset value once over `/pp/epic` through Plan 01's `OscClient.send_epic`, with a bold-font + sunken-relief + "Zone: <name>" caption highlight, and the Phase 1 arrow-key-clobbers-entry bug (WR-01) is fixed.
- `/pp/volume` now drives a lagged, squared-taper gain stage inside `\ppMaster` (before `Limiter.ar`), proven headlessly via a 65-check smoke suite including VO2's EPIC at maximum volume staying under the -1 dBFS limiter ceiling.
- A Volume Scale (0-100, default 80) now sits in the PedalPulse window, following BpmController's exact live-drag/send-on-release pattern to drive `/pp/volume`, completing GUI-03 and wiring all four Phase 3 controls (BPM, Start/Stop, EPIC zones, volume) into one window.
- Quick task 261010-hyl (audit W1): re-evaluating `main.scd` after Stop now keeps the engine stopped, matching the GUI; smoke suite at 67 checks.

**Stats:** 129 commits, 2026-10-08 → 2026-10-10 (3 days); ~2,800 lines Python (app + tests), ~2,350 lines SuperCollider (engine + smoke test).

**Closeout type:** override_closeout. Requirements 14/15 satisfied. Audit verdict: tech_debt (see milestones/v1.0-MILESTONE-AUDIT.md).

**Known verification overrides:** 0 newly acknowledged, 0 carried forward from a prior close (open-artifact audit was clear). Phases 1–3 VERIFICATION.md digests are stale: covered files (`supercollider/main.scd`, `supercollider/smoke_test.scd`, Phase 3's edit to `python_app/view.py`) changed after each verifier ran. All three reports were `passed` with completed UATs, and the post-change smoke run (67/67, SMOKE PASS) and pytest (150 passed) were green. The user accepted closing without re-running the verifiers.

### Known Gaps

- **ENG-03**: User can leave the engine playing for 60+ minutes without audio dropouts and without CPU or synth node count growth. Moved to a manual real-ride soak (no phase) on 2026-10-10; not yet performed.

---
