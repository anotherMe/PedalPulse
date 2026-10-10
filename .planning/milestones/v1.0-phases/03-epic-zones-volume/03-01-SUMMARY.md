---
phase: 03-epic-zones-volume
plan: 01
subsystem: audio-dsp
tags: [supercollider, python-osc, lag, freeverb2, rlpf, softclip, osc, control-bus]

# Dependency graph
requires:
  - phase: 02-full-groove-smooth-tempo
    provides: TempoClock-driven six-layer groove, ~ppMixBus, re-evaluation teardown idiom, /pp/bpm and /pp/play OSCdef validation shape, OscClient send_bpm/send_play pattern
provides:
  - "/pp/epic <float 0-100> end to end: Python CLI/OscClient.send_epic -> UDP -> OSCdef(\\pp_epic) -> one raw control bus -> one Lag.kr smoother -> one smoothed bus -> one \\ppFx synth (drive/filter/richness/reverb) -> ~ppFxBus -> \\ppMaster (unchanged limiter)"
  - "EPIC-01 engine half complete: raising EPIC measurably brightens the post-FX output (>4kHz band at EPIC 100 is >=4x EPIC 0's level, proven headlessly)"
  - "EPIC-02 engine half complete: EPIC changes glide monotonically and convergently in both directions and through a mid-glide retarget, bounded by a step-bound derived from the tunable lag constant"
  - "Engine-side input contract for /pp/epic: 0-100 clamp (one step either side), float precision preserved end to end, malformed/NaN/missing-arg tolerance, loopback-only guard"
  - "Leak-free re-evaluation for all new FX objects (synths, group, three buses)"
affects: ["03-02", "03-03", "03-04"]

# Actuals (#2632)
actuals:
  tokens: 10567
  tasks: 2
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single-conductor-value + one smoother + one FX synth: exactly one Lag.kr smoother reads the raw EPIC control bus and writes a smoothed bus; exactly one \\ppFx synth reads that smoothed bus once and derives drive/cutoff/richness/reverb-wet from that single value, guaranteeing all four parameters move in lockstep by construction"
    - "Persistent (non-enveloped) SynthDef: \\ppEpicSmoother and \\ppFx have no envelope/doneAction, live for the whole session, and are freed explicitly by the teardown block -- a documented, deliberate exception to the project's doneAction:2 rule for per-note voices"
    - "addToTail required for FX-after-smoother ordering: Synth's default addAction is addToHead, so the smoother is created with \\addToHead and the FX synth with \\addToTail inside the same group, guaranteeing the smoother's write lands before the FX synth's read within one control block"

key-files:
  created: []
  modified:
    - python_app/config.py
    - python_app/osc_client.py
    - python_app/tests/test_osc_client.py
    - supercollider/main.scd
    - supercollider/smoke_test.scd
    - scripts/smoke_test.sh

key-decisions:
  - "Widened the glide-check monotonicity noise tolerance from the planned -1e-4 to -1e-3 (Rule 1 bug fix, see Deviations) -- the tighter value produced a reproducible false failure from residual settle-tail decay carried into each trace's pre-roll window."

requirements-completed: [EPIC-01, EPIC-02]

coverage:
  - id: D1
    description: "Python sends /pp/epic over OSC (config.OSC_EPIC_ADDRESS, OscClient.send_epic, --epic CLI option), with send_bpm/send_play/send_epic all catching (OSError, OverflowError, BuildError)"
    requirement: "EPIC-01"
    verification:
      - kind: unit
        ref: "python_app/tests/test_osc_client.py#test_send_epic_delivers_decodable_osc_message_over_real_socket"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_osc_client.py#test_send_bpm_and_send_epic_return_false_on_overflow_error"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_osc_client.py#test_send_play_returns_false_on_build_error"
        status: pass
    human_judgment: false
  - id: D2
    description: "Engine validates, clamps (0-100, one step either side), and preserves float precision end to end on /pp/epic; malformed/NaN/missing-arg input is ignored with a warning and state unchanged; non-loopback senders are ignored"
    requirement: "EPIC-01"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd: epic clamp 150->100 / 101->100 / 100 / 0 / -1->0 / -50->0 / epic float 37.5"
        status: pass
      - kind: integration
        ref: "supercollider/smoke_test.scd: epic malformed ignored"
        status: pass
      - kind: integration
        ref: "supercollider/smoke_test.scd: loopback-only (extended to cover /pp/epic)"
        status: pass
    human_judgment: false
  - id: D3
    description: "One Lag.kr smoother + one \\ppFx synth drive filter cutoff, drive/saturation, reverb amount and synth richness together from a single smoothed EPIC read; raising EPIC measurably brightens the post-FX output"
    requirement: "EPIC-01"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd: python epic / epic brightens output (>4kHz band >=4x and >0.001)"
        status: pass
      - kind: other
        ref: "grep -v comments: In.kr(epicBus)==1, Lag.kr==1, FreeVerb2==1, Synth(\\ppFx==1"
        status: pass
    human_judgment: true
    rationale: "The smoke test proves the mechanism is wired and measurably brighter; whether the combined drive/filter/richness/reverb blend actually *sounds* like 'brighter and more energetic' is a listening judgment deferred to Plan 02's manual check, per 03-RESEARCH.md's Validation Architecture."
  - id: D4
    description: "EPIC changes glide smoothly (no stepping/clicks): monotone, bounded, convergent in both directions and through a mid-glide retarget that never nearly reaches the abandoned target"
    requirement: "EPIC-02"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd: epic glide up / epic glide down / epic retarget mid-glide"
        status: pass
    human_judgment: true
    rationale: "The smoke test proves the mechanism (monotone, bounded, convergent, no near-jump on retarget) headlessly; whether the glide actually sounds free of zipper noise or clicks is a listening judgment deferred to Plan 02's manual check."
  - id: D5
    description: "Re-evaluating main.scd frees the previous FX synth, smoother, FX group and three new buses with no leak, and preserves the last EPIC value with no glide-from-0 or jump-to-default"
    requirement: "EPIC-01"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd: fx re-evaluation"
        status: pass
    human_judgment: false
  - id: D6
    description: "The always-on FX chain does not raise the per-note node bound beyond the two new persistent synths, and stays within the existing limiter headroom at the default EPIC"
    requirement: "EPIC-01"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd: node bound (<=22), fx headroom (<=0.891 at EPIC 10), limiter ceiling (now run at EPIC 100)"
        status: pass
    human_judgment: false

duration: 45min
completed: 2026-10-09
status: complete
---

# Phase 3 Plan 01: EPIC end to end in the engine (tracer) Summary

**`/pp/epic` now drives one shared `Lag.kr` smoother into a single `\ppFx` synth (softclip drive, `RLPF` cutoff, HF-exciter richness, `FreeVerb2` reverb) sitting between the groove and the limiter, proven headlessly via a 52-check smoke suite.**

## Performance

- **Duration:** 45 min (approximate)
- **Completed:** 2026-10-09T20:06:51Z
- **Tasks:** 2 completed
- **Files modified:** 6

## Accomplishments

- Wired the full `/pp/epic <float 0-100>` tracer slice: Python `OscClient.send_epic`/`--epic` CLI → UDP → `OSCdef(\pp_epic)` → `~ppEpicBus` → one `Lag.kr` smoother → `~ppEpicSmoothBus` → one `\ppFx` synth → `~ppFxBus` → the unchanged `\ppMaster` limiter.
- Proved EPIC-01 headlessly: raising EPIC from 0 to 100 raises the post-FX (>4kHz) band level by at least 4x and above the silence floor, measured on bus 0 after the master group (i.e. what the rider actually hears).
- Proved EPIC-02 headlessly: the smoothed EPIC value glides monotonically and convergently up, down, and through a mid-glide retarget (100→30 mid-flight never nearly reaches the abandoned 100), with every step bounded by a tolerance derived from the tunable `~ppEpicLagSecs` lag constant.
- Proved the engine's input contract independently of the GUI: a 7-entry clamp/float table (150→100, 101→100, 100, 0, -1→0, -50→0, 37.5 unrounded), malformed/NaN/missing-argument tolerance, and loopback-only rejection (extended the existing B5 check to also exercise `/pp/epic`).
- Proved leak-free re-evaluation: the new FX synth, smoother, FX group and three new buses are all freed and rebuilt with no leak, and the last EPIC value survives a reload with no glide-from-0 and no jump to the default.
- Carried forward Phase 2 review findings WR-01/WR-02: `send_bpm`/`send_play`/`send_epic` now all catch `(OSError, OverflowError, BuildError)`, and the bool-coercion test asserts the exact `int` type rather than `isinstance`.

## Task Commits

1. **Task 1: End-to-end tracer: python osc_client.py --epic → /pp/epic → one smoothed EPIC value → one FX synth → limiter** - `bd75f03` (feat)
2. **Task 2: EPIC glides smoothly up, down and through a mid-glide retarget, the engine clamps and validates /pp/epic, and re-evaluation leaks nothing** - `42765bf` (test)

_No separate plan-metadata commit yet (worktree mode): the orchestrator commits this SUMMARY.md after merge._

## Files Created/Modified

- `python_app/config.py` - `OSC_EPIC_ADDRESS = "/pp/epic"`
- `python_app/osc_client.py` - `OscClient.send_epic`, `--epic` CLI option, `(OSError, OverflowError, BuildError)` on all three send methods
- `python_app/tests/test_osc_client.py` - wire-format/error-path/CLI tests for `/pp/epic`; exact-`int`-type check for `/pp/play` bool coercion (WR-02)
- `supercollider/main.scd` - `~ppEpicLagSecs`, `\ppEpicSmoother`/`\ppFx` SynthDefs, `~ppFxGroup`/`~ppFxBus`/`~ppEpicBus`/`~ppEpicSmoothBus`, `OSCdef(\pp_epic)`, extended teardown, master now reads `~ppFxBus`
- `supercollider/smoke_test.scd` - `sendEpic`/`traceCtl`/`readCtl`/`waitEpicSettled`/`measureBand`/`groupChildDefs` helpers; `\ppCtlProbe`/`\ppBandProbe` test synths; 11 new/extended checks (tracer, brightness, chain order, 3 glide checks, 7-entry clamp table, malformed, fx headroom, fx re-evaluation, loopback-only extension); watchdog raised 240→300s; node bound raised 20→22
- `scripts/smoke_test.sh` - shell timeout raised 270→330s to match the new in-script watchdog

## Decisions Made

- Kept the FX chain order drive → filter → richness → reverb exactly as researched (standard analog signal-chain convention).
- Widened the glide-check monotonicity noise tolerance from -1e-4 to -1e-3 after a reproducible false failure (see Deviations) — still two orders of magnitude below the real step-bound used to catch genuine jumps.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Glide-check monotonicity tolerance was too tight, causing a reproducible false failure**
- **Found during:** Task 2, first run of "epic glide up"
- **Issue:** The planned `-1e-4` tolerance for the per-sample monotonicity check did not account for residual settle-tail decay: `waitEpicSettled`'s own 0.005 convergence tolerance means the bus can still be decaying toward its target by more than `1e-4` per 20ms sample when a new `traceCtl` trace's pre-roll window begins, immediately before the actual glide action fires. This produced a genuine (not flaky-in-the-bad-sense, but mathematically expected) failure: `value fell by -0.00019...` between the first two samples of "epic glide up".
- **Fix:** Widened the noise tolerance on both "epic glide up" (rise `< -1e-4`) and "epic glide down" (drop `< -1e-4`, i.e. unexpected rise) to `-1e-3`. This remains ~100x smaller than `stepBound` (the real jump-detection bound, ~0.13 at the default 1.5s lag), so it cannot mask a genuine stepping/jump defect while absorbing the expected settle-tail noise.
- **Files modified:** `supercollider/smoke_test.scd`
- **Verification:** Re-ran `bash scripts/smoke_test.sh` — all 3 glide checks ("epic glide up", "epic glide down", "epic retarget mid-glide") now pass consistently.
- **Committed in:** `42765bf` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix).
**Impact on plan:** Necessary correctness fix to an overly strict test tolerance; no scope creep, no change to the engine or Python production code, no loosening of the actual jump-detection bound.

## Issues Encountered

None beyond the deviation above.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - the full `/pp/epic` path is wired end to end with no placeholder values; all SynthDefs, OSCdefs and Python send methods are production code, not scaffolding.

## Threat Flags

None beyond what the plan's own `<threat_model>` already covers (T-03-01 through T-03-06, T-03-SC) — all dispositioned `mitigate`/`accept` in the plan and verified by the smoke checks listed in `coverage` above (malformed-input guard, loopback-only guard, teardown leak check, limiter-bypass-proof routing).

## Next Phase Readiness

- EPIC-01 and EPIC-02 engine halves are complete and proven headlessly. Plan 02 can now wire the five zone preset buttons (`EpicController`, `config.EPIC_ZONES`) onto this exact `send_epic`/`--epic` client, plus the manual listening checks (brightness/energy change across zones, glide smoothness including rapid back-to-back clicks) that this plan's headless coverage explicitly defers.
- No blockers. The `~ppFxGroup`/`~ppFxBus` ordering and the single-smoothed-value design are stable extension points for Plans 03/04's volume work (which will sit inside `\ppMaster`, pre-limiter, following the same "never bypass the limiter" discipline this plan established for the FX chain).

---
*Phase: 03-epic-zones-volume*
*Completed: 2026-10-09*

## Self-Check: PASSED

- FOUND: python_app/config.py
- FOUND: python_app/osc_client.py
- FOUND: python_app/tests/test_osc_client.py
- FOUND: supercollider/main.scd
- FOUND: supercollider/smoke_test.scd
- FOUND: scripts/smoke_test.sh
- FOUND: commit bd75f03 (Task 1, ancestor of HEAD)
- FOUND: commit 42765bf (Task 2, ancestor of HEAD)
