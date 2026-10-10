---
phase: 01-tempo-link-skeleton
plan: 01
subsystem: engine
tags: [supercollider, tempoclock, osc, python-osc, limiter, tkinter-adjacent]

requires: []
provides:
  - "supercollider/main.scd: single sclang entry file, boot-gated, autostarts kick+hat+bass through a master limiter on a dedicated TempoClock"
  - "OSC contract /pp/bpm <float>, loopback-only, clamped 60-180, latest-wins next-beat apply"
  - "python_app/osc_client.py + config.py: send-only OscClient and raw-send CLI, the wire contract Plans 02/03 build on"
  - "scripts/smoke_test.sh: one-command headless regression harness for the whole engine safety contract"
affects: [01-02-gui-window, 01-03-gui-controls, phase-2-groove, phase-3-epic, phase-4-heartbeat]

actuals:
  tokens: 5701
  tasks: 2
  commits: 2
plan_head_before: a6bc33d7a7736d4fcd752d871e55e97ae7de657b
plan_head_after: d06bfa5d46ba2cc05f0645fd3c63c6a446449767

tech-stack:
  added: ["python-osc==1.10.2"]
  patterns:
    - "Boot-gated OSCdef registration via s.waitForBoot (ENG-04)"
    - "Instant-but-beat-quantized tempo apply: schedAbs(nextTimeOnGrid(1), ...) with a single latest-wins pending-apply flag"
    - "Master limiter bus: instruments write only to a private mix bus; \\ppMaster applies preGain then Limiter.ar(sig, 0.891251, 0.01) before Out.ar(0)"
    - "Idempotent main.scd re-evaluation: stop patterns/clock, wait out s.latency, then free+rebuild nodes"
    - "Loopback-only OSCdef via srcID: NetAddr(\"127.0.0.1\", nil)"
    - "Send-only Python OSC client (OscClient + raw-send CLI) wrapping pythonosc.SimpleUDPClient"

key-files:
  created:
    - python_app/config.py
    - python_app/osc_client.py
    - python_app/requirements.txt
    - supercollider/main.scd
    - supercollider/smoke_test.scd
    - scripts/smoke_test.sh
  modified: []

key-decisions:
  - "Idempotent re-evaluation waits 0.3s (> default s.latency) between stopping the old patterns/clock and freeing the old groups/bus, so an in-flight timestamped note-on OSC bundle cannot land on an already-freed group"
  - "smoke_test.scd's check failures throw an Error caught by one top-level try/catch, instead of printing+async-quitting inline, so a failed check halts the whole test immediately rather than falling through to later checks"
  - "B8's 're-evaluation' check verifies the new master synth is alive by measuring real audio through it (behavioral), not via Node:isPlaying, which reads its unset default for a freshly-created, unwatched node"

requirements-completed: [ENG-02, ENG-04, TEMPO-03, LINK-01]

coverage:
  - id: D1
    description: "main.scd boots, posts its OSC port, and autostarts the kick+hat+bass loop on a dedicated TempoClock through the master limiter"
    requirement: "ENG-04"
    verification:
      - kind: integration
        ref: "scripts/smoke_test.sh: CHECK OK: boot ready, CHECK OK: port posted, CHECK OK: initial tempo 120"
        status: pass
    human_judgment: false
  - id: D2
    description: "/pp/bpm from the Python OscClient changes ~clock's tempo on the next whole beat"
    requirement: "LINK-01"
    verification:
      - kind: integration
        ref: "scripts/smoke_test.sh: CHECK OK: python tempo 140, CHECK OK: whole-beat apply"
        status: pass
    human_judgment: false
  - id: D3
    description: "Engine clamps /pp/bpm to 60-180 independently of the GUI, including adjacency (59/60/180/181) and float values"
    requirement: "TEMPO-03"
    verification:
      - kind: integration
        ref: "scripts/smoke_test.sh: CHECK OK: clamp 300->180 / 10->60 / 59->60 / 181->180 / 60 / 180, CHECK OK: float 150.5"
        status: pass
    human_judgment: false
  - id: D4
    description: "Malformed /pp/bpm (no-arg, string, NaN) is ignored with a warning and the handler stays live; latest-wins coalesces same-beat bursts to one apply"
    requirement: "TEMPO-03"
    verification:
      - kind: integration
        ref: "scripts/smoke_test.sh: CHECK OK: malformed ignored, CHECK OK: latest wins"
        status: pass
    human_judgment: false
  - id: D5
    description: "OSCdef accepts only loopback senders; a LAN-address send is ignored"
    requirement: "LINK-01"
    verification:
      - kind: integration
        ref: "scripts/smoke_test.sh: CHECK OK: loopback-only"
        status: pass
    human_judgment: false
  - id: D6
    description: "No enveloped synth leaks nodes; synth count stays bounded during sustained playback"
    requirement: "ENG-02"
    verification:
      - kind: integration
        ref: "scripts/smoke_test.sh: CHECK OK: node bound"
        status: pass
    human_judgment: false
  - id: D7
    description: "Master limiter holds the ceiling at a hot preGain and passes silence with preGain 0 (no bypass)"
    requirement: "ENG-02"
    verification:
      - kind: integration
        ref: "scripts/smoke_test.sh: CHECK OK: limiter no bypass, CHECK OK: limiter ceiling"
        status: pass
    human_judgment: false
  - id: D8
    description: "Re-evaluating main.scd replaces the loop/clock/master instead of stacking, keeps the last-applied tempo, and does not wedge the pending-apply flag"
    requirement: "ENG-04"
    verification:
      - kind: integration
        ref: "scripts/smoke_test.sh: CHECK OK: re-evaluation"
        status: pass
    human_judgment: false
  - id: D9
    description: "The groove (kick + offbeat hat + A-minor offbeat rolling bass) sounds right musically, and the limiter ceiling holds audibly at a hot preGain with no crackle, judged by ear/meter in the SC IDE"
    requirement: "ENG-02"
    verification: []
    human_judgment: true
    rationale: "D-17 makes the limiter check a listening/meter judgment and the groove's musical feel (D-13) can only be judged by ear -- this is Task 2's <human-check>, deferred to end-of-phase UAT per workflow.human_verify_mode=end-of-phase."

duration: 40min
completed: 2026-10-08
status: complete
---

# Phase 1 Plan 01: Engine walking skeleton (tracer + loop + safety contract) Summary

**Python OscClient sends /pp/bpm over UDP to a boot-gated sclang OSCdef that clamps, coalesces, and applies tempo on the next beat to a kick+offbeat-hat+A-minor-bass loop running through a -1 dBFS master limiter, all proven headless by one `scripts/smoke_test.sh` command.**

## Performance

- **Duration:** ~40 min
- **Tasks:** 2 completed
- **Files created:** 6

## Accomplishments

- Built the single SuperCollider entry file (`supercollider/main.scd`): boot-gated via `s.waitForBoot`, posts its OSC language port, autostarts a kick+offbeat-hat+A-minor-rolling-bass loop on a dedicated `TempoClock`, and routes every instrument through a `-1 dBFS` `Limiter.ar` master bus with a debug `~preGain` hook
- Built the Python send-only OSC client (`python_app/osc_client.py` + `config.py`): `OscClient.send_bpm` wraps `pythonosc.SimpleUDPClient`, never raises, and the module doubles as the raw-send CLI used for engine-side clamp verification (D-08) and the smoke test
- `/pp/bpm` handling in `main.scd`: rejects non-numeric/NaN input with a warning, clamps valid floats to 60-180, accepts only loopback senders (`srcID: NetAddr("127.0.0.1", nil)`), and applies via a single latest-wins pending-apply flag scheduled on the next whole beat (`schedAbs(nextTimeOnGrid(1), ...)`)
- Made `main.scd` idempotent under re-evaluation: stops the three Pbindefs and the old clock, waits out `s.latency` before freeing the old bus/groups/master (so an in-flight timestamped note-on bundle can't target an already-freed node), then rebuilds everything fresh while keeping the last-applied `~bpm`
- Built `supercollider/smoke_test.scd`, a headless harness on an isolated server (port 57140, muted) that drives the real Python -> UDP -> sclang path and asserts 19 named checks: boot/port/tempo, the full clamp table, whole-beat quantization, latest-wins, malformed-input tolerance, loopback-only rejection, node-leak bound, limiter no-bypass + ceiling, and idempotent re-evaluation
- Wrapped it in `scripts/smoke_test.sh`, a one-command terminal runner (D-18) that checks prerequisites, unsets `QT_QPA_PLATFORM` (verified to abort sclang 3.14.1 on macOS), and exits 0 only on `SMOKE PASS`

## Task Commits

Each task was committed atomically:

1. **Task 1: Tracer (Python OscClient -> sclang OSCdef -> TempoClock)** - `13d00f5` (feat)
2. **Task 2: Complete skeleton loop + lock engine safety contract** - `d06bfa5` (feat)

_Note: both tasks were production-quality from the first commit per the plan's tracer/auto typing -- no throwaway/rewrite cycle._

## Files Created/Modified

- `python_app/config.py` - OSC host/port/address constants and BPM bounds (D-07, D-22)
- `python_app/osc_client.py` - send-only `OscClient` + raw-send CLI (D-24, D-08)
- `python_app/requirements.txt` - pinned `python-osc==1.10.2`
- `supercollider/main.scd` - boot-gated engine entry file: SynthDefs, master limiter, TempoClock loop, `OSCdef(\pp_bpm)`, idempotent re-eval
- `supercollider/smoke_test.scd` - headless integration harness, 19 named checks
- `scripts/smoke_test.sh` - one-command terminal runner for the smoke test

## Decisions Made

- Idempotent re-evaluation waits 0.3s between stopping old patterns/clock and freeing old nodes, to absorb `s.latency`-bundled in-flight note-on messages (see Deviations below)
- Test-failure handling in `smoke_test.scd` uses a thrown `Error` + one top-level `try`/catch, so a failed check halts immediately instead of letting the routine fall through to subsequent checks
- The B8 "new master synth is alive" assertion was changed from `Node:isPlaying` to a direct peak measurement (see Deviations below)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Idempotent re-eval freed groups before an in-flight latency-bundled note-on landed**
- **Found during:** Task 2, first smoke-test run of the `re-evaluation` check
- **Issue:** `Pbindef(...).stop` + an immediate `.free` on the old master/instrument groups raced against an already-sent, server-timestamped OSC note-on bundle (bundled ahead by `s.latency`, default ~0.2s). The bundle landed on the already-freed group, producing `FAILURE IN SERVER /s_new Group N not found` and failing the re-evaluation check.
- **Fix:** Added a `0.3.wait` (comfortably longer than the default `s.latency`) between stopping the Pbindefs/clock and freeing the old master synth/groups/bus.
- **Files modified:** `supercollider/main.scd`
- **Verification:** `scripts/smoke_test.sh` re-run clean, no `FAILURE IN SERVER` lines, `CHECK OK: re-evaluation`
- **Committed in:** `d06bfa5` (Task 2 commit)

**2. [Rule 1 - Bug] Smoke-test `fail()` did not halt the routine on failure**
- **Found during:** Task 2, diagnosing the re-evaluation failure above
- **Issue:** `fail` only printed `SMOKE FAIL: ...` and called the asynchronous `s.quit(onComplete: {1.exit})`; the calling code continued executing synchronously afterward (e.g. it kept sending further `/pp/bpm` values and running later checks) before the process actually exited, producing confusing cascaded output and masking the real failure point.
- **Fix:** `fail` now throws an `Error`; the entire check sequence is wrapped in one top-level `{ ... }.try({ |err| ... })`, whose handler prints `SMOKE FAIL: <message>` and does the real `s.quit` + `1.exit`.
- **Files modified:** `supercollider/smoke_test.scd`
- **Verification:** Re-running against the (then still-present) re-evaluation bug produced exactly one clean `SMOKE FAIL:` line with no further OSC sends afterward
- **Committed in:** `d06bfa5` (Task 2 commit)

**3. [Rule 1 - Bug] B8 asserted `Node:isPlaying` on a freshly-created, unwatched node**
- **Found during:** Task 2, after fixes 1 and 2, the re-evaluation check still failed on `~ppMasterSynth.isPlaying.not`
- **Issue:** A `Synth` object's `isPlaying`/`isRunning` flags only track real server state once the node is registered with `NodeWatcher` *before* its creation notification (`/n_go`) arrives. The new `~ppMasterSynth` created during reload was never watched in time, so `.isPlaying` read its unset default (`false`) even though the synth was genuinely alive and playing.
- **Fix:** Replaced the `isPlaying` assertion with a direct behavioral check: place a fresh `\ppPeakProbe` synth after `~ppMasterGroup`, measure for 1s, and assert the measured peak is non-zero -- proving audio actually flows through the new master synth.
- **Files modified:** `supercollider/smoke_test.scd`
- **Verification:** `scripts/smoke_test.sh` passes with `CHECK OK: re-evaluation` and `SMOKE PASS`
- **Committed in:** `d06bfa5` (Task 2 commit)

---

**Total deviations:** 3 auto-fixed (all Rule 1 - bugs found and fixed during the task's own verification loop)
**Impact on plan:** All three fixes were necessary for the plan's own stated `re-evaluation` check to actually pass; none changed scope or added functionality beyond what the plan specified. No scope creep.

## Issues Encountered

None beyond the three deviations documented above, which were resolved within the task's normal fix-attempt budget.

## User Setup Required

None - no external service configuration required. (`.venv` is created locally from `python3.13` as part of this plan's own verify step; no secrets or dashboards involved.)

## Next Phase Readiness

- The `/pp/bpm` OSC contract, `python_app/config.py` constants, and `OscClient`/`main()` CLI shape are locked and ready for Plan 02 (GUI window) and Plan 03 (GUI controls) to build on directly, per the plan's `<interfaces>` block.
- `supercollider/main.scd`'s SynthDefs (`\ppKick`, `\ppHat`, `\ppBass`) are reusable as Phase 2's groove starting point, per D-13.
- Task 2's `<human-check>` (listening to the loop, confirming the limiter ceiling by ear/meter in the SC IDE) is deferred to end-of-phase UAT per `workflow.human_verify_mode=end-of-phase` -- it is not a blocker for Plan 02/03 execution, but should be exercised before the phase is marked verified.
- No blockers for the next plan.

---
*Phase: 01-tempo-link-skeleton*
*Completed: 2026-10-08*

## Self-Check: PASSED

- All 6 created files verified present on disk (`python_app/config.py`, `python_app/osc_client.py`, `python_app/requirements.txt`, `supercollider/main.scd`, `supercollider/smoke_test.scd`, `scripts/smoke_test.sh`)
- Both task commits (`13d00f5`, `d06bfa5`) verified as ancestors of HEAD
- No stub patterns (`TODO`/`FIXME`/`placeholder`/"coming soon"/"not available") found in any created file
- All plan acceptance criteria re-verified against the live `bash scripts/smoke_test.sh` run (19 `CHECK OK:` lines, `SMOKE PASS`, exit 0)
