---
phase: 02-full-groove-smooth-tempo
plan: 03
subsystem: audio-engine
tags: [supercollider, tempoclock, routine, oscdef, tempo-ramp]

# Dependency graph
requires:
  - phase: 02-full-groove-smooth-tempo
    provides: "Plan 01's ~ppLayers/~ppStart/~ppStop transport skeleton and headless smoke_test.scd harness (26 checks) that this plan extends"
provides:
  - "supercollider/main.scd: ~ppRampStepper -- a single long-lived Routine on ~clock that is the ONLY writer of ~clock.tempo, steering it toward a mutable ~ppRampTargetBpm at a rate recomputed from the clock's live tempo"
  - "/pp/bpm handler now only records ~ppRampPendingBpm (latest-wins); the stepper engages it from rest on a whole beat (TEMPO-01) or immediately mid-glide (TEMPO-02), never a cancel-and-replace"
  - "supercollider/smoke_test.scd: sendBpm/waitForTempo/traceGlide helpers; 31 CHECK OK lines covering glide start/land/direction/no-op/retarget, with every Phase 1/Plan 01 check adapted to glide semantics"
affects: [02-04-full-groove-and-epic-fx]

# Actuals (#2632)
actuals:
  tokens: 5345
  tasks: 2
  commits: 2
plan_head_before: 285ac58d39ea8f857db160e43d94fb1d88d43152
plan_head_after: cf9a180263bfa24b52c709e72567ac348144c16e

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single persistent ramp-stepper Routine as the sole writer of ~clock.tempo -- a mid-glide retarget is 'update ~ppRampTargetBpm/~ppRampRateBpm', never cancel-and-restart a Routine, which sidesteps the double-stepping/stall hazard a cancel-and-replace design would introduce"
    - "Latest-wins pending-target pattern generalized from Phase 1's one-shot ~ppPendingBpm/~ppApplyScheduled apply to a continuously-running stepper: the OSC handler only ever writes ~ppRampPendingBpm, the stepper is the only reader/clearer"
    - "Engage condition encodes both halves of the requirement in one guard: fromRest only on a whole beat (TEMPO-01 beat-synchronous start), mid-glide on any 16th-note tick (TEMPO-02 immediate retarget, no re-quantize)"

key-files:
  created: []
  modified:
    - supercollider/main.scd
    - supercollider/smoke_test.scd
    - scripts/smoke_test.sh

key-decisions:
  - "Engage-then-step as two ordered phases of one stepper tick (read beat, maybe engage pending target, maybe step toward target) rather than two separate scheduled callbacks -- keeps ~clock.tempo writes confined to one Routine, one tick, with no ordering ambiguity"
  - "8-beat (2 bars) linear-in-BPM glide, 0.25-beat (16th note) step granularity -- RESEARCH's provisional defaults, carried through unchanged per the plan; the curve shape remains isolated to one line (the step calculation) for the listening-test spike STATE.md already flags"
  - "Malformed /pp/bpm input is tested both at rest AND mid-glide ('malformed ignored' now sends the three bad messages again while a glide to 128 is in flight) to prove T-02-09's mitigation holds under the new continuously-running engage path, not just the one-shot path Phase 1 tested"

patterns-established:
  - "A clock-driving Routine's engage/step logic lives entirely inside its own loop tick, reading and clearing a pending-value variable the OSC handler writes -- this is the latest-wins idiom generalized beyond one-shot scheduling, reusable for any future continuously-steered clock parameter"

requirements-completed: [TEMPO-01, TEMPO-02]

coverage:
  - id: D1
    description: "A new BPM glides over 8 beats (2 bars) starting on a whole beat and landing exactly on the clamped target, with every layer still on the one ~clock"
    requirement: "TEMPO-01"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd#glide starts on beat, glide reaches target, glide upward, clamp table settle checks"
        status: pass
    human_judgment: false
  - id: D2
    description: "A /pp/bpm equal to the current tempo engages (apply count rises) but starts no glide: rate stays 0, tempo stays exact, start beat unchanged (TEMPO-01 adjacency edge)"
    requirement: "TEMPO-01"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd#same bpm no-op check"
        status: pass
    human_judgment: false
  - id: D3
    description: "Missing/string/NaN /pp/bpm input is ignored with a warning, both at rest and while a glide is in flight, without disturbing the apply count or the glide target"
    requirement: "TEMPO-01"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd#malformed ignored check"
        status: pass
    human_judgment: false
  - id: D4
    description: "Two /pp/bpm messages that arrive before a glide engages produce exactly one engage, to the later value (latest wins)"
    requirement: "TEMPO-01"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd#latest wins check"
        status: pass
    human_judgment: false
  - id: D5
    description: "A BPM sent mid-glide retargets from the current instantaneous tempo on the next 16th-note tick: no restart (start beat unchanged), no jump beyond two ramp steps, the abandoned target is never reached, and the new target lands 6-9 beats later"
    requirement: "TEMPO-02"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd#retarget mid-glide check"
        status: pass
    human_judgment: false
  - id: D6
    description: "Re-evaluating main.scd at rest stops the old stepper with the old clock, keeps the current tempo, and the next /pp/bpm still glides over 6-9 beats -- a stacked second stepper would halve that"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd#re-evaluation check"
        status: pass
    human_judgment: false
  - id: D7
    description: "The glide audibly sounds smooth (no jolt), including on rapid back-and-forth retargets -- the subjective half of TEMPO-01/02 that the smoke test's monotone/step-bound assertions prove the mechanism for, not the listening experience itself"
    verification: []
    human_judgment: true
    rationale: "This plan's own <verification> section explicitly defers the 'no audible jolt' listening check to Plan 04's end-of-phase human check, once the full groove exists to listen to alongside the glide. The automated proxy (monotone trajectory, two-ramp-step bound, exact landing) is covered by D1/D5."

duration: 50min
completed: 2026-10-09
status: complete
---

# Phase 2, Plan 03: Beat-synchronous tempo glide with mid-glide retarget Summary

**Phase 1's instant "snap at the next beat" BPM apply is replaced by a single long-lived `~ppRampStepper` Routine that glides the tempo over 8 beats (2 bars) starting on a whole beat, and retargets immediately -- no restart, no jump -- when a new BPM arrives mid-glide.**

## Performance

- **Duration:** 50 min
- **Started:** 2026-10-09T13:20:00Z (approx.)
- **Completed:** 2026-10-09T14:10:00Z (approx.)
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- `~ppRampStepper`, a Routine playing on `~clock` itself (never SystemClock/AppClock), is now the single writer of `~clock.tempo`; the `/pp/bpm` `OSCdef` only records the latest clamped value in `~ppRampPendingBpm`
- Each stepper tick (every 0.25 beat) first checks whether to *engage* a pending target -- from rest only on a whole beat (TEMPO-01), mid-glide on any tick (TEMPO-02) -- then *steps* the tempo toward the current target by at most one ramp step, landing exactly on it
- Teardown stops the previous stepper before the clock and resets ramp state, so re-evaluating `main.scd` can never stack a second stepper or leave a pending target wedged on a stopped clock
- Every Phase 1/Plan 01 smoke check was adapted to glide semantics (clamp table asserts the glide *target* instead of an instant tempo; "whole-beat apply" became "glide starts on beat"; malformed-input, latest-wins, node-bound, and re-evaluation checks now wait for the glide to land) and the watchdog/timeout budget was raised (120s to 240s, 150s to 270s) for the added glide time
- Four new checks prove the glide mechanism directly: "glide reaches target" and "glide upward" (monotone trajectory, two-ramp-step bound, exact landing, 6-9 beat duration in both directions), "same bpm no-op" (adjacency edge case), and "retarget mid-glide" (direction-reversing retarget with no restart, no jump, abandoned target never reached)
- `bash scripts/smoke_test.sh` now runs 31 checks, all green; `.venv/bin/pytest python_app/tests -q` stays green at 71 passed (Python side untouched by this plan)

## Task Commits

Each task was committed atomically:

1. **Task 1: A new BPM glides over 2 bars from a beat boundary, and every existing engine check is adapted to the glide** - `b061fc6` (feat)
2. **Task 2: Glide trajectory is proven smooth up and down, a same-BPM send is a no-op, and a mid-glide retarget bends without restarting or jumping** - `cf9a180` (test)

_Both tasks ran green on the first full-suite attempt after implementation; no retry commits were needed._

## Files Created/Modified
- `supercollider/main.scd` - `~ppRampBeats`/`~ppRampStepBeats` tuning constants, `~ppRampStepper` Routine (sole writer of `~clock.tempo`), ramp state vars (`~ppRampTargetBpm`/`~ppRampRateBpm`/`~ppRampPendingBpm`/`~ppRampStartBeat`/`~ppRampLandBeat`), rewritten `OSCdef(\pp_bpm)` that only stores the pending target, teardown stepper-stop-before-clock-stop
- `supercollider/smoke_test.scd` - `sendBpm`/`waitForTempo`/`traceGlide` helpers, `lastTrace` capture var, watchdog raised to 240s, "glide starts on beat"/"glide reaches target"/"glide upward"/"same bpm no-op"/"retarget mid-glide"/"clamp table settle" checks added, every existing tempo-related check adapted to glide semantics
- `scripts/smoke_test.sh` - timeout/gtimeout raised from 150s to 270s

## Decisions Made
- Engage and step are two ordered phases inside one stepper tick (not two separate scheduled callbacks), so every `~clock.tempo` write stays confined to one Routine with no ordering ambiguity between an engage and a step on the same tick.
- The 8-beat/0.25-beat-step/linear-in-BPM defaults from RESEARCH's Gray Areas were carried through unchanged, as the plan specified -- no new judgment calls were needed since the plan's `<action>` block fully specified the engage/step formulas.
- "malformed ignored" was extended to also fire mid-glide (not just at rest) to prove T-02-09's input-validation mitigation holds under the new continuously-running engage path, which the plan called for explicitly in its threat register.

## Deviations from Plan

None - plan executed exactly as written. The engage-condition formula, the step formula, the teardown ordering, and every adapted/added smoke check match the plan's `<action>` block verbatim.

## Issues Encountered
None. The worktree had no `.venv` (gitignored, not shared across worktrees); created one fresh via `python3.13 -m venv .venv && .venv/bin/pip install -r python_app/requirements-dev.txt` before running the smoke test and pytest, per the environment notes -- this is local test infrastructure, not a plan deliverable, and was not committed.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- TEMPO-01 and TEMPO-02 are now closed: the engine glides any BPM change over 2 bars from a beat boundary and retargets smoothly mid-glide, proven by 31 passing smoke checks.
- The "no audible jolt" listening half of TEMPO-01/02 (the subjective judgment this plan's mechanism cannot self-certify) is explicitly deferred to Plan 04's end-of-phase human check, alongside the full groove and Start/Stop listening checks -- not a gap introduced here, per this plan's own `<verification>` section.
- `~ppRampStepper`'s latest-wins engage/step pattern is available as a precedent for Plan 04 if EPIC-driven parameters ever need similar smoothed-change semantics.

---
*Phase: 02-full-groove-smooth-tempo*
*Completed: 2026-10-09*

## Self-Check: PASSED

- FOUND: supercollider/main.scd
- FOUND: supercollider/smoke_test.scd
- FOUND: scripts/smoke_test.sh
- FOUND: b061fc6 (ancestor of HEAD)
- FOUND: cf9a180 (ancestor of HEAD)
- Acceptance criteria re-verified: Task 1's grep-based criteria (main.scd contains `~ppRampStepper`, `~ppRampBeats = 8`, `~ppRampStepBeats = 0.25`, `~ppRampPendingBpm = bpm`, `play(~clock, quant: 1)`, `~ppRampStartBeat`; zero occurrences of `ppApplyScheduled`/`ppPendingBpm`; smoke_test.scd contains `SystemClock.sched(240`, `waitForTempo`, `traceGlide`, `glide starts on beat`; smoke_test.sh contains `timeout 270`/`gtimeout 270`) all passed; Task 2's criteria (smoke_test.scd contains all four new check names; `bash scripts/smoke_test.sh` exits 0 with >= 29 `CHECK OK:` lines; `.venv/bin/pytest python_app/tests -q` exits 0) all passed
- Plan-level `<verification>` re-run: `bash scripts/smoke_test.sh` printed `SMOKE PASS` with 31 `CHECK OK:` lines including all eight named glide/edge checks; `.venv/bin/pytest python_app/tests -q` passed 71/71
