---
phase: 03-epic-zones-volume
plan: 03
subsystem: audio-dsp
tags: [supercollider, python-osc, lag, limiter, osc, control-bus]

# Dependency graph
requires:
  - phase: 03-epic-zones-volume
    provides: "Plan 01's /pp/epic end-to-end tracer (OSCdef pattern, Lag.kr smoother idiom, measurePeak/readCtl/traceCtl helpers, teardown discipline) and Plan 02's zone-button GUI wiring, which this plan's engine-side volume work extends"
provides:
  - "/pp/volume <float 0-100> end to end: Python OscClient.send_volume/--volume CLI -> UDP -> OSCdef(\\pp_volume) -> ~ppVolumeBus -> a 0.2s Lag.kr gain inside \\ppMaster, applied before Limiter.ar -- never after or around it"
  - "GUI-03 engine half complete: volume changes measurably scale the output peak following the squared taper (~ppVolumeAmp), volume 0 is silent, and the gain de-zippers instead of stepping"
  - "ROADMAP Phase 3 success criterion 4 proven headlessly: VO2 (EPIC 100) + volume 100 sent through the real Python CLI keeps the output peak <= 0.892 (limiter ceiling 0.891251 + tolerance) while real audio flows (peak > 0.1)"
  - "Engine-side input contract for /pp/volume: 0-100 clamp (one step either side, float precision preserved), malformed/NaN/missing-arg tolerance, loopback-only guard -- all independent of the GUI"
  - "Leak-free re-evaluation for the new volume bus: freed on teardown, last value preserved, new bus holds its taper immediately with no glide-from-0"
affects: ["03-04"]

# Actuals (#2632)
actuals:
  tokens: 7782
  tasks: 2
  commits: 2

# Commit ledger (#3968) -- measured via git rev-list, not narrated
commits: 2
plan_head_before: 0bbe263122205c9eafe1e84c45ac6298dc4b0743
plan_head_after: b9cb5f8bd72b21769176a4541d7afcaec2c8a5c4

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Volume as a gain stage inside the master synth, not a separate synth: \\ppMaster now reads an extra volumeBus control-rate argument, Lag.kr-smooths it over 0.2s (shorter than EPIC's 1.5s musical glide, since a slider release should de-zipper, not fade), and multiplies it into the signal next to preGain -- strictly before Limiter.ar, matching the project's existing 'never bypass the limiter' discipline from the EPIC FX chain."
    - "Squared taper for perceptual loudness: ~ppVolumeAmp = { |v| (v/100).squared } maps the GUI's 0-100 range to gain so equal slider moves feel like roughly equal loudness steps (100 -> 1.0 unity, 80 -> 0.64, 50 -> 0.25) -- a deliberate, reversible planner deviation from the plain-linear mapping RESEARCH proposed, documented as one line to revert."
    - "Isolated scratch-bus de-zipper check: the 'volume glides' smoke check builds its own \\ppDcSource -> \\ppMaster -> \\ppLevelProbe chain on throwaway buses/group, so the lag-smoothing behavior of \\ppMaster is proven directly (a constant 0.5 DC signal, a volume step from 1 to 0) without touching or depending on the real groove/FX chain's state."

key-files:
  created: []
  modified:
    - python_app/config.py
    - python_app/osc_client.py
    - python_app/tests/test_osc_client.py
    - supercollider/main.scd
    - supercollider/smoke_test.scd

key-decisions:
  - "Adopted the plan's squared-taper volume mapping (~ppVolumeAmp) as written -- no deviation needed; the plan's own planner-discretion note documents the rationale and reversibility."

requirements-completed: [GUI-03]

coverage:
  - id: D1
    description: "Python sends /pp/volume over OSC (config.OSC_VOLUME_ADDRESS, OscClient.send_volume, --volume CLI option, sent after --epic and before --play), catching (OSError, OverflowError, BuildError) like send_bpm/send_epic/send_play"
    requirement: "GUI-03"
    verification:
      - kind: unit
        ref: "python_app/tests/test_osc_client.py#test_send_volume_delivers_decodable_osc_message_over_real_socket"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_osc_client.py#test_send_volume_returns_false_on_overflow_error"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_osc_client.py#test_cli_main_sends_epic_then_volume_in_order"
        status: pass
    human_judgment: false
  - id: D2
    description: "Engine applies a lagged, squared-taper gain inside \\ppMaster before Limiter.ar; the output peak scales with the taper and volume 0 is silent"
    requirement: "GUI-03"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd: python volume / volume scales output / volume silent at 0"
        status: pass
      - kind: other
        ref: "grep: ~ppVolumeAmp = { |v| (v / 100).squared }, volumeBus = 0, * preGain * volume, Out.ar(out, Limiter.ar(sig, 0.891251, 0.01)) (volume applied before the limiter, confirmed by source order)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The engine clamps /pp/volume to 0-100 (one step either side), preserves float precision, ignores malformed/NaN/missing-argument input, and only accepts loopback senders -- independent of the GUI"
    requirement: "GUI-03"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd: volume clamp 150->100 / 101->100 / 100 / 0 / -1->0 / float 62.5"
        status: pass
      - kind: integration
        ref: "supercollider/smoke_test.scd: volume malformed ignored"
        status: pass
      - kind: integration
        ref: "supercollider/smoke_test.scd: loopback-only (extended to cover /pp/volume)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Volume changes are de-zippered: a volume step glides monotonically through intermediate values over the 0.2s lag instead of stepping instantly"
    requirement: "GUI-03"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd: volume glides (isolated \\ppMaster instance on scratch buses)"
        status: pass
    human_judgment: true
    rationale: "The smoke test proves the mechanism (monotone, bounded, convergent, passes >=3 genuine intermediate samples) headlessly; whether a real volume drag actually sounds free of zipper noise is a listening judgment deferred to Plan 04's manual check, per 03-RESEARCH.md's Validation Architecture (same split already used for EPIC's glide checks in Plan 01)."
  - id: D5
    description: "ROADMAP Phase 3 success criterion 4: with VO2 selected (EPIC 100) and volume at maximum (100), sent through the real Python CLI, the output peak never exceeds the limiter ceiling (0.891251) plus a small tolerance (<=0.892), while real audio still flows (>0.1)"
    requirement: "GUI-03"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd: max epic max volume no clip"
        status: pass
    human_judgment: false
  - id: D6
    description: "Re-evaluating main.scd frees the old volume bus (nil index), preserves the last ~volume value, and the new volume bus holds the correct taper immediately with no glide-from-0"
    requirement: "GUI-03"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd: volume re-evaluation"
        status: pass
    human_judgment: false

duration: 35min
completed: 2026-10-09
status: complete
---

# Phase 3 Plan 03: Master volume in the engine, and VO2 at full volume never clips Summary

**`/pp/volume` now drives a lagged, squared-taper gain stage inside `\ppMaster` (before `Limiter.ar`), proven headlessly via a 65-check smoke suite including VO2's EPIC at maximum volume staying under the -1 dBFS limiter ceiling.**

## Performance

- **Duration:** 35 min (approximate)
- **Started:** 2026-10-09T20:35:00Z (approximate)
- **Completed:** 2026-10-09T20:42:38Z
- **Tasks:** 2 completed
- **Files modified:** 5

## Accomplishments

- Wired the full `/pp/volume <float 0-100>` path: Python `OscClient.send_volume`/`--volume` CLI → UDP → `OSCdef(\pp_volume)` → `~ppVolumeBus` → a 0.2s `Lag.kr` gain read inside `\ppMaster` → multiplied with `preGain` into the signal → `Limiter.ar` (unchanged, never bypassed).
- Added `~ppVolumeAmp = { |v| (v/100).squared }` so equal slider moves produce roughly equal loudness steps (100 → unity, 80 → 0.64, 50 → 0.25), per the plan's documented, reversible planner deviation from a plain-linear mapping.
- Proved GUI-03 headlessly: raising volume from 50 to 100 scales the output peak within 0.1 of the expected taper ratio, volume 0 silences the output (`< 0.001` peak), and the gain glides through genuine intermediate samples instead of stepping (isolated `\ppDcSource`/`\ppLevelProbe` scratch-bus check).
- Proved the engine's input contract independently of the GUI: a 6-entry clamp/float table (150→100, 101→100, 100, 0, -1→0, 62.5 unrounded, each checked against the raw bus's taper), malformed/NaN/missing-argument tolerance, and loopback-only rejection (extended the existing B5 check to also exercise `/pp/volume`).
- Proved ROADMAP Phase 3 success criterion 4: `--epic 100 --volume 100` sent through the real Python CLI (VO2 + max volume) keeps the output peak at or below 0.892 while real audio still flows (0.507 measured) — the safety promise this phase exists to deliver.
- Proved leak-free re-evaluation: the volume bus is freed and rebuilt with no leak, and the last volume value (35, chosen non-default to be discriminating) survives a reload with the new bus holding the correct taper immediately.

## Task Commits

1. **Task 1: python osc_client.py --volume → /pp/volume → pre-limiter master gain: the output gets quieter and louder, and volume 0 is silent** - `7d19bca` (feat)
2. **Task 2: Volume clamps and validates, glides without zipper steps, survives re-evaluation, and VO2 at maximum volume never clips** - `b9cb5f8` (test)

_No separate plan-metadata commit yet (worktree mode): the orchestrator commits this SUMMARY.md after merge._

## Files Created/Modified

- `python_app/config.py` - `OSC_VOLUME_ADDRESS = "/pp/volume"`
- `python_app/osc_client.py` - `OscClient.send_volume`, `--volume` CLI option (sent after `--epic`, before `--play`), updated docstrings/error message
- `python_app/tests/test_osc_client.py` - wire-format/unclamped/error-path/CLI tests for `/pp/volume`, including send order with `--epic`
- `supercollider/main.scd` - `~ppVolumeAmp` squared taper, `~ppVolumeBus`, `\ppMaster` gains a `volumeBus` argument with a 0.2s `Lag.kr` read, `~volume`/`~ppVolumeCount` state, `OSCdef(\pp_volume)`, extended teardown and ready line
- `supercollider/smoke_test.scd` - hoisted `measurePeak` to a top-level helper, `sendVolume` helper, `\ppDcSource`/`\ppLevelProbe` test SynthDefs, and 10 new/extended checks: python volume, volume scales output, volume silent at 0, 6-entry volume clamp/float table, volume malformed ignored, volume glides, loopback-only (extended), max epic max volume no clip, volume re-evaluation

## Decisions Made

- Adopted the plan's squared-taper volume mapping exactly as specified -- no deviation from the plan was needed for this decision.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - the full `/pp/volume` path is wired end to end with no placeholder values; all SynthDef changes, the OSCdef and the Python send method are production code, not scaffolding.

## Threat Flags

None beyond what the plan's own `<threat_model>` already covers (T-03-10 through T-03-13, T-03-SC) — all dispositioned `mitigate`/`accept` in the plan and verified by the smoke checks listed in `coverage` above (malformed-input guard, loopback-only guard, pre-limiter gain placement proof via source grep, teardown leak check).

## Next Phase Readiness

- GUI-03 engine half is complete and proven headlessly, including the phase's core safety promise (max EPIC + max volume never clips). Plan 04 can now add the volume slider in the GUI window on top of this exact `send_volume`/`--volume` client, plus the manual listening check (smooth loudness change, no audible distortion at VO2 + max volume) that this plan's headless coverage explicitly defers.
- No blockers. The `\ppMaster` `volumeBus` argument and `~ppVolumeAmp` taper function are stable, documented extension points; reverting to a linear taper (if the Plan 04 listening check finds the slider uneven) means editing one line.

---
*Phase: 03-epic-zones-volume*
*Completed: 2026-10-09*

## Self-Check: PASSED

- FOUND: python_app/config.py
- FOUND: python_app/osc_client.py
- FOUND: python_app/tests/test_osc_client.py
- FOUND: supercollider/main.scd
- FOUND: supercollider/smoke_test.scd
- FOUND: commit 7d19bca (Task 1, ancestor of HEAD)
- FOUND: commit b9cb5f8 (Task 2, ancestor of HEAD)
- FOUND: .venv/bin/pytest python_app/tests -q exits 0 (122 passed)
- FOUND: bash scripts/smoke_test.sh exits 0, SMOKE PASS, 65 CHECK OK lines (>= 64 required)
