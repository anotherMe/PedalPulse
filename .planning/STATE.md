---
gsd_state_version: "1.0"
milestone: v2.0
milestone_name: Living Music
current_phase: 8
current_phase_name: Evolving Melodies
status: planning
stopped_at: Phase 07 complete, ready to plan Phase 8
last_updated: "2026-10-20T19:09:26.436Z"
last_activity: 2026-10-20
last_activity_desc: Phase 07 complete, transitioned to Phase 8
state_head: 7c432d56c2e3736ed5584e6bd5138bcb68895e75
progress:
  total_phases: 6
  completed_phases: 7
  total_plans: 20
  completed_plans: 20
  percent: 78
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-20)

**Core value:** Moving the BPM or EPIC control in the Python GUI audibly and smoothly changes the live, generated music in SuperCollider — the Python → OSC → SuperCollider chain works end to end.
**Current focus:** Phase 8 — Evolving Melodies

## Current Position

Phase: 8 — Evolving Melodies
Plan: Not started
Status: Ready to plan
Last activity: 2026-10-20 — Phase 07 complete, transitioned to Phase 8

Progress: [████████░░] 78% (v2.0)

## Performance Metrics

**Velocity:**
- Total plans completed: 31
- Average duration: -
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 3 | - | - |
| 02 | 4 | - | - |
| 03 | 4 | - | - |
| 04 | 6 | - | - |
| 05 | 3 | - | - |
| 06 | 5 | - | - |
| 07 | 6 | - | - |

**Recent Trend:**
- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 02 P01 | 18 min | 2 tasks | 5 files |
| Phase 02 P02 | 10 min | 2 tasks | 5 files |
| Phase 02 P03 | 19 min | 2 tasks | 3 files |
| Phase 02 P04 | 19 min | 2 tasks | 2 files |
| Phase 07 P01 | 31 min | 2 tasks | 7 files |
| Phase 07 P02 | 28 min | 2 tasks | 3 files |
| Phase 07 P03 | 26 min | 2 tasks | 6 files |
| Phase 07 P04 | 82 min | 2 tasks | 5 files |
| Phase 07 P05 | 33 min | 3 tasks | 6 files |
| Phase 07 P06 | 42 min | 2 tasks | 5 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v2.0 Roadmap]: Phases 4-9 follow the research build order (library core → harmony → palettes → melodies → structure/density). Every engine phase exits with the smoke suite and library check green, Stop silencing every new layer, and no stacked routines or leaked nodes (ENG-05 standing gate, introduced in Phase 4)
- [v2.0 Roadmap]: The GUI library selectors are one dedicated phase (5), right after the library core. GUI-05/06/07 each span all three selectors; the lists come from disk, so later content phases are auditioned in the GUI by name with no further GUI work
- [v2.0 Roadmap]: The ENG-03 real-ride soak is folded into the last phase (9) instead of a phase of its own. That ride doubles as the per-zone density listening test
- [Roadmap]: Vertical MVP structure. Every phase delivers an audible or visible GUI → OSC → SC capability; Phase 1 is the walking skeleton
- [Roadmap]: Master limiter, self-freeing synths (doneAction: 2), boot-gated OSCdefs and the posted OSC port all start in Phase 1; later phases inherit them
- [Roadmap]: Master volume is grouped with EPIC (Phase 3) so "max EPIC + max volume never clips" is verified where both first exist
- [Scope]: The Python app stays send-only, with no engine → GUI channel (LINK-02/LINK-03 moved to Out of Scope on 2026-10-10)
- [Scope]: The 60-minute soak (ENG-03) was a manual, non-blocking real-ride check in v1.0; in v2.0 it is Phase 9's closing criterion. Synth count and CPU are read from the SC IDE server status bar
- [Phase 1]: Project venv is python3.13 with Tk 9.0 via `./run.sh`; the Tk gate accepts 8.6 and 9.x (real Tk 9.0.3 widgets pass a widget smoke test)
- [Phase 1]: OSC contract is `/pp/bpm <float>` to sclang port 57120, loopback-only `srcID`, engine clamp 60–180, latest-wins apply on the next beat
- [Phase 1]: `scripts/smoke_test.sh` (headless sclang, isolated muted server on port 57140) is the engine regression harness; later phases extend it (36 checks after Phase 2, ~75 s)
- [Phase 2]: Transport is `/pp/play <int>` (loopback-only, idempotent); Stop = group `\gate, 0` broadcast + guarded second broadcast, never node free; `~ppLayers` is the single layer list new layers append to
- [Phase 2]: `~ppRampStepper` is the only writer of `~clock.tempo` (8-beat glide, beat-aligned engage, mid-glide retarget); Phase 3 EPIC changes must not write tempo
- [Phase 2]: New voices stay within ≤3 oscillators + 1 filter, write to `~ppMixBus` (through the limiter) and self-free with doneAction: 2
- [Phase 3]: EPIC is `/pp/epic <float 0–100>` → one raw bus → one `Lag.kr` smoother → one `\ppFx` synth → `~ppFxBus` → `\ppMaster`; zones are Recovery 10 / Endurance 30 / Tempo 50 / Threshold 75 / VO2 100
- [Phase 5]: GUI library dropdowns (palette, progression, melody) list Auto plus the stems of `supercollider/library/<category>/*.scd`, rescanned on every open (no watcher/timer); the engine is the name validator, a repeat pick sends nothing
- [Phase 3]: Volume is `/pp/volume <float 0–100>`, a 0.2 s lagged squared-taper gain inside `\ppMaster` before the limiter; GUI sends on slider release, launch sends 80

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 7, open code-review findings]: original review (07-REVIEW.md at commit 1081b38): WR-01 voice-namespace rule bypassable with a longer palette name (prefix collision), WR-02 fixed watchdogs do not scale with the library, IN-01 empty error handlers in the defs undo path, IN-02..IN-04 (still listed in 07-REVIEW-DISPOSITION.md). The 2026-10-20 re-review of quick task 261015-uez reused the ids WR-01/WR-02/IN-01 for its own findings (smoke boost range 2.0-3.0 rejects the README's 1.0, no runtime validation of ~ppMasterBoost, README wording), so the ledger replaced the original three rows; they are tracked here
- [Phase 6, open code-review info items]: IN-01 README/template doc drift (Auto hold is 32-64 bars), IN-02 `~ppAutoHistoryCap` not retunable, IN-03 voicing Array shared by reference, IN-04 test/gate timing. See 06-REVIEW-DISPOSITION.md
- [v2.0 research flags]: (Phase 4 flags resolved: quant 4 survives Stop/Start with doReset, plan bar equals played bar, per-bar seeding replays.) (Phase 6 flag resolved: harmony stays in step across Stop/Start and tempo glide, smoke + UAT.) (Phase 7 flag resolved: loudness gate 1.5 dB to classic, CPU budget 25% average, confirmed next to Zwift in UAT.) Phases 8-9: melody rules, the EPIC→density curve and section lengths need listening UAT
- [Phase 2, open code-review findings]: WR-02 `test_send_play_coerces_bool_to_int` cannot detect a missing int() coercion; IN-01 glide lands at ~7.75 beats (WR-01 BuildError catch fixed in Phase 3 plan 01). See 02-REVIEW-DISPOSITION.md
- [Phase 3, open code-review findings]: WR-01 `Debouncer.trigger()` token tracking breaks if `schedule()` fires synchronously; WR-02 `osc_client.py` CLI prints "sent" even when the send failed; IN-01 mutable default zone map; IN-02 `apply_entry()` sends before notifying. See 03-REVIEW-DISPOSITION.md; fix with `/gsd-code-review 03 --fix`
- [Phase 2, UI review]: spacing scale inconsistent (`transport_row` pady=4 vs `nudge_row` pady=8). The "no feedback when the engine is not running" finding is accepted by design (send-only app)
- [Milestone audit W2]: no resync after an engine restart. The GUI keeps its last values and the engine resets to defaults; restarting the app resyncs (accepted under the send-only design; LINK-04 deferred)
- [v1.0 close]: closed as override_closeout. The Phase 1–3 VERIFICATION.md digests went stale after the W1 fix, and ENG-03 is still open (see MILESTONES.md)
- [Phase 4, open code-review findings]: (WR-03 guard base fixed by Phase 6 WR-04) WR-04 template says `state` is shared (it is per role), WR-05 a classic load failure on re-evaluation leaves a half torn-down engine, WR-06 a refused newer selection cancels a valid older one, plus 6 info items. WR-01/WR-02 deferred by the rider (revisit before Phase 7). See 04-REVIEW-DISPOSITION.md
- [Phase 4, flaky smoke check]: `epic glide up: PulseCount did not advance` (pre-existing) failed about 1 run in 3 during Phase 4 gates and passed on rerun; it undermines the ENG-05 standing exit gate. Investigate with /gsd-debug
- [ENG-03, Phase 9]: CPU/timing coexistence with Zwift and macOS audio-device switching can only be known through the real-ride soak, now Phase 9's closing check

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 1 | Add classic_lead_loud melody (lead at arp level) for the Phase 4 listening check | 2026-10-12 | bd04c46 | — |
| 2 | Rewrite README.md with overview and Win/Linux/macOS setup | 2026-10-13 | 1c0acda | — |
| 3 | 2.5x master loudness boost before the limiter (`~ppMasterBoost`) | 2026-10-20 | f75fde8 | [261015-uez-increase-pedalpulse-master-output-volume](./quick/261015-uez-increase-pedalpulse-master-output-volume/) |

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-10-20
Stopped at: Phase 07 complete, ready to plan Phase 8
Resume file: None

## Operator Next Steps

- Discuss Phase 8 with /gsd-discuss-phase 8, then plan it with /gsd-plan-phase 8
