---
phase: 02-full-groove-smooth-tempo
plan: 04
subsystem: audio-engine
tags: [supercollider, tempoclock, jitlib, pbindef, synthdef, smoke-test]

# Dependency graph
requires:
  - phase: 02-full-groove-smooth-tempo (Plan 03)
    provides: beat-synchronous tempo glide stepper (~ppRampStepper) and the shared ~clock every layer now rides
  - phase: 02-full-groove-smooth-tempo (Plan 01)
    provides: ~ppStart/~ppStop transport, the \gate 0 group broadcast, the limiter and mix bus, and the Phase 1 kick/hat/bass loop
provides:
  - "Full six-layer groove (kick, hat, clap, bass, arpeggio, pad) in A minor, all on the one ~clock"
  - "Headless proof that every layer plays and every SynthDef name actually sounds on the server within 3 bars"
  - "Headless proof that the pre-limiter mix bus stays under the limiter ceiling at default gain (mix headroom)"
  - "Headless proof that Stop releases a held pad chord and in-flight notes within 2.0s against a ~3s natural tail"
affects: [phase-03-epic-fx, phase-04-soak-test]

actuals:
  tokens: 3130
  tasks: 2
  commits: 5

tech-stack:
  added: []
  patterns:
    - "Pbindef layers set an explicit \\amp key matching the SynthDef's own amp default, because a Pbindef with no \\amp key sends the pattern's default event amplitude (0.1), silently overriding the SynthDef's intended default"
    - "A generalised measurePeak(busIndex, durSec) helper plus a one-off Synth.after(~ppInstrGroup, ...) probe reads the pre-limiter mix bus sum, distinct from the post-limiter bus-0 probes placed after ~ppMasterGroup"
    - "instrDefNames() parses /g_queryTree.reply (flag 0) into a Set of SynthDef name Symbols -- defName is present at flag 0; only per-control values are gated by the flag"

key-files:
  created: []
  modified:
    - supercollider/main.scd
    - supercollider/smoke_test.scd

key-decisions:
  - "Clap/arp/pad Pbindef \\amp values were set to match each SynthDef's own amp default (0.25 / 0.1 / 0.06) rather than tuned ad hoc, keeping the mix balance the voice was designed at"
  - "The end-of-phase listening acceptance (groove style, glide feel, Stop tail, Start-on-bar, button label) was NOT performed live in this automated worktree run -- deferred to end-of-phase UAT consolidation per workflow.human_verify_mode: end-of-phase, consistent with the checkpoints.md #3309 default (no fabricated perceptual judgment)"

requirements-completed: [ENG-01]

coverage:
  - id: D1
    description: "Engine plays all six layers (kick, hat, clap, bass, arpeggio, pad) together on the one ~clock after boot"
    requirement: "ENG-01"
    verification:
      - kind: integration
        ref: "scripts/smoke_test.sh#CHECK OK: all layers playing"
        status: pass
      - kind: integration
        ref: "scripts/smoke_test.sh#CHECK OK: all layers sounding"
        status: pass
    human_judgment: false
  - id: D2
    description: "Mix stays under the limiter ceiling at default gain (limiter is a safety net, not a constant compressor)"
    requirement: "ENG-01"
    verification:
      - kind: integration
        ref: "scripts/smoke_test.sh#CHECK OK: mix headroom"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every new SynthDef self-frees; node count stays bounded with six layers"
    verification:
      - kind: integration
        ref: "scripts/smoke_test.sh#CHECK OK: node bound"
        status: pass
    human_judgment: false
  - id: D4
    description: "Stop releases a held pad chord within 2.0s against a ~3s natural tail, and no effect UGens were added"
    requirement: "ENG-01"
    verification:
      - kind: integration
        ref: "scripts/smoke_test.sh#CHECK OK: stop cuts held pad"
        status: pass
      - kind: integration
        ref: "scripts/smoke_test.sh#CHECK OK: stop catches in-flight notes"
        status: pass
    human_judgment: false
  - id: D5
    description: "Groove reads as melodic techno/progressive trance by ear; glide/retarget/Stop feel smooth and clean; Start brings the full groove back in time; button label and OSC logging are correct through the real app"
    human_judgment: true
    rationale: "Musical style, glide smoothness, click/tail quality and GUI feel are perceptual -- the smoke test proves the mechanisms (monotone, continuous, bar-aligned, voices released), not how they sound. No live listening session ran in this automated worktree execution; deferred to end-of-phase UAT per workflow.human_verify_mode: end-of-phase."

duration: 25min
completed: 2026-10-09
status: complete
commits: 5
plan_head_before: c7f403c9e2b1cf4c68aa882e8540dd6731b7abfb
plan_head_after: 32fcfef85ac7be661775dde5029e8416d2c5ba51
---

# Phase 2 Plan 04: Full groove (drums, bass, arpeggio, pad) and the phase acceptance listen Summary

**Added clap, 16th-note A-minor arpeggio and sustained Am pad layers to the shared `~clock`, extended `~ppLayers` to all six voices, and proved headlessly that Stop releases a held pad and in-flight notes within 2.0s of a ~3s natural tail.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-10-09
- **Tasks:** 2 completed
- **Files modified:** 2 (`supercollider/main.scd`, `supercollider/smoke_test.scd`)

## Accomplishments

- `supercollider/main.scd`: three new self-freeing SynthDefs (`\ppClap`, `\ppArp`, `\ppPad`, each with `doneAction: 2`, at most 3 oscillators + 1 filter, no effect UGens) and matching Pbindefs on `~ppMixBus`/`~ppInstrGroup`, each cycle length dividing a bar evenly for phase-locked restart. `~ppLayers` now reads `[\ppKick, \ppHat, \ppClap, \ppBass, \ppArp, \ppPad]`.
- `supercollider/smoke_test.scd`: new `instrDefNames` helper (parses `/g_queryTree.reply` into the instrument group's live SynthDef names), "all layers playing" and "all layers sounding" checks (ENG-01), a generalised `measurePeak` plus a new "mix headroom" check proving the pre-limiter mix bus peak stays <= 0.891 at default gain.
- Two new timing-sensitive Stop checks: "stop cuts held pad" (Stop sent 0.35s into a bar empties the instrument group within 2.0s against a ~3.0s natural tail) and "stop catches in-flight notes" (a `schedAbs`-scheduled Stop at the exact logical bar-line time still empties the group within 2.0s, regardless of event ordering).
- `scripts/smoke_test.sh`: 36 `CHECK OK:` lines, exit 0 (up from the Plan 03 baseline of 31).
- `.venv/bin/pytest python_app/tests -q`: 87 passed (no Python-side changes this plan; re-run as part of the plan's full verification).

## Task Commits

Each task was committed atomically:

1. **Task 1: The engine plays the full six-layer groove on one clock, every layer sounds, and the mix leaves headroom** - `ac82835` (feat)
2. **Task 2: Stop cuts a held pad chord and catches in-flight notes, then the rider accepts the whole phase by ear through the app** - `f1501f2` (test)

_No plan-metadata commit yet -- SUMMARY.md and REQUIREMENTS.md are committed separately per the worktree protocol (`git_commit_metadata` step), after this file is written._

## Files Created/Modified

- `supercollider/main.scd` - adds `\ppClap`/`\ppArp`/`\ppPad` SynthDefs and Pbindefs, extends `~ppLayers` to six names
- `supercollider/smoke_test.scd` - adds `instrDefNames` helper, "all layers playing"/"all layers sounding"/"mix headroom"/"stop cuts held pad"/"stop catches in-flight notes" checks, generalises `measurePeak`

## Decisions Made

- Set each new Pbindef's `\amp` key to match its SynthDef's own `amp` default (clap 0.25, arp 0.1, pad 0.06) rather than inventing new balance numbers -- a Pbindef with no `\amp` key sends the pattern's default event amplitude (0.1), which would have silently flattened all three new voices to the same level regardless of their intended design.
- Generalised the B7 `measurePeak` helper to take a bus-index parameter (keeping its fixed placement after `~ppMasterGroup` for the existing post-limiter checks) and added a separate, explicit `Synth.after(~ppInstrGroup, ...)` probe for the new pre-limiter "mix headroom" check, per the plan's exact instruction, rather than overloading one helper with two different placement semantics.
- Did not perform the end-of-phase live listening acceptance inside this automated worktree execution (see Issues Encountered).

## Deviations from Plan

None - plan executed exactly as written. The amp values (0.25 / 0.1 / 0.06) chosen for the new Pbindefs are literally the SynthDef argument defaults the plan itself specified in the action text, confirmed sufficient by the passing "mix headroom" check (pre-limiter peak measured at 0.21-0.27 across runs, well under the 0.891 ceiling) with no retuning needed.

## Issues Encountered

- One `bash scripts/smoke_test.sh` run (the first run after Task 1's changes) printed `SMOKE PASS` with every `CHECK OK:` line present, then crashed during server teardown with `libc++abi: terminating due to uncaught exception of type std::__1::system_error: mutex lock failed: Invalid argument`, causing a non-zero script exit despite a fully passing test body. This reproduced as a one-off: an immediate re-run (and all subsequent runs, including the final Task 2 run used for commit evidence) exited 0 cleanly with the same checks passing. Treated as a flaky sclang/CoreAudio shutdown race at process exit (a known class of issue, unrelated to this plan's code changes, and not reproducible on retry) rather than a regression; no code change was made in response. Flagging here in case it recurs during the phase's end-of-phase or CI runs.
- The end-of-phase human listening acceptance (Task 2's `<human-check>`: groove style, glide smoothness across retargets, Stop tail quality, Start-on-bar feel, button label correctness, optional Zwift-CPU observation) was **not performed** during this automated worktree execution -- there is no human present in this execution context to judge musical/perceptual quality. Per `.planning/config.json`'s `workflow.human_verify_mode: "end-of-phase"` (the project default, matching `checkpoints.md` #3309), this is the intended behavior: the planner embedded the check inside the task's `<verify><human-check>` rather than as a standalone `checkpoint:human-verify` task specifically so it would NOT halt execution, and the phase-level verifier is expected to harvest it into the phase's UAT consolidation for the user to perform once, in one batch, with the rest of the phase. Recorded in `coverage` above as `D5` with `human_judgment: true`. **This is the one open item blocking a complete "phase done" signal for Phase 2** -- a human still needs to run `./run.sh`, listen per Task 2's six verification steps, and confirm success criteria 2 and 3 (glide smoothness, Stop/Start feel) before the phase can be considered fully accepted.

## User Setup Required

None - no external service configuration required. The existing `.venv` setup from Phase 1/`./run.sh --setup` is unchanged; this worktree created its own local `.venv` (python3.13 + `python-osc`/`pytest`) purely to run the automated verification, same as prior plans in this phase.

## Next Phase Readiness

- ENG-01 is now structurally complete and automated-proof-complete: all six layers play on one clock, phase-locked through glides and restarts, with bounded node count and headroom under the limiter.
- Phase 2's remaining open item is the human listening pass (Task 2's six-step acceptance) -- recommend running it before `/gsd-verify-work` closes the phase, since success criteria 2 and 3 (glide smoothness, Stop/Start feel) are explicitly ear-judged, not automatable.
- Phase 3 (EPIC FX) can build on this groove directly: the six-layer `~ppLayers` list, the mix bus, and the limiter headroom margin (pre-limiter peak currently 0.21-0.27 against a 0.891 ceiling) all leave room for EPIC's planned filter/drive/reverb additions without restructuring this plan's work.

## Self-Check: PASSED

- FOUND: supercollider/main.scd
- FOUND: supercollider/smoke_test.scd
- FOUND: .planning/phases/02-full-groove-smooth-tempo/02-04-SUMMARY.md
- FOUND: ac82835 (Task 1 commit, ancestor of HEAD)
- FOUND: f1501f2 (Task 2 commit, ancestor of HEAD)

---
*Phase: 02-full-groove-smooth-tempo*
*Completed: 2026-10-09*
