---
phase: 04-modular-engine-variation-library
plan: 06
subsystem: testing
tags: [supercollider, smoke-test, re-evaluation, idempotence, stop, exit-gate]

requires:
  - phase: 04-modular-engine-variation-library
    provides: loader, renderer, lead layer, library check (plans 01-05)
provides:
  - "eng-05 no stacking: three back-to-back main.scd re-evaluations with classic_lead playing leave identical Pdef, clock, EventStreamPlayer, Routine, group, SynthDef and OSCdef counts (7 players, 1 routine)"
  - "eng-05 module re-evaluation: validate.scd, loader.scd and render.scd each re-evaluated twice while playing change no counts, every one of the seven roles keeps rendering, the registry survives"
  - "stop silences every layer: with classic_lead flowing, /pp/play 0 empties the instrument group within 2.5 s and no role renders another bar"
  - "Smoke helpers sendSel, waitSel, engineCounts, compareCounts, layersStarted, reloadMain, waitLeadFlowing, roleSnapshot"
affects: [05-gui, 06-library-growth, 08-generative]

requirements-completed: [ENG-05, LIB-01]

actuals:
  tokens: 4500
  tasks: 2
  commits: 2

plan_head_before: a2de807a473897cccb600f1b7458c0eaa0b2e95d
plan_head_after: 1fd10c59aa5b828be20b3c092ae82e5bf010a36e

tech-stack:
  added: []
  patterns:
    - "Count what must not multiply (Pdef names, TempoClock.all, EventStreamPlayers and Routines in ~clock.queue, groups, SynthDefs, OSCdefs) before and after, and compare every key"
    - "Wait until every layer's player has nextBeat before another Stop or re-evaluation, so a pending bar-quantized start is never interrupted"
    - "Non-vacuous Stop check: the lead is proven flowing (role note count rising) before Stop"

key-files:
  created: []
  modified:
    - supercollider/smoke_test.scd

key-decisions:
  - "supercollider/main.scd needed no change: every ENG-05 check passed against it as left by plans 02-05"
  - "reloadMain waits for the autostarted layers to be really playing (nextBeat set) before returning, the same precaution as the wave-5 quant probe"
  - "The eng-05 counts line is one line so the plan's grep for players 7 and routines 1 can read it"

patterns-established:
  - "A check is shown to be able to fail: a temporary leaked Group per evaluation in main.scd made eng-05 no stacking fail with groups before 9 after 12 (reverted, not committed)"

coverage:
  - id: D1
    description: "Re-evaluating main.scd three times while playing leaves exactly one copy of everything: 7 Pdefs, 7 EventStreamPlayers and 1 Routine on the live clock, and identical clock, group, SynthDef and OSCdef counts"
    requirement: ENG-05
    verification:
      - kind: other
        ref: "supercollider/smoke_test.scd (CHECK OK: eng-05 no stacking; PedalPulse smoke: eng-05 counts players 7 routines 1 clocks 2 groups 6 synthDefs 121 oscdefs 10)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Re-evaluating validate.scd, loader.scd and render.scd twice each while playing changes no counts, every role keeps rendering notes, and the registry keeps classic and classic_lead"
    requirement: ENG-05
    verification:
      - kind: other
        ref: "supercollider/smoke_test.scd (CHECK OK: eng-05 module re-evaluation)"
        status: pass
    human_judgment: false
  - id: D3
    description: "A selection survives re-evaluation: classic_lead is still selected and the lead still plays after three re-evaluations; no ERROR or 'playing classic for this bar' line appears"
    requirement: ENG-05
    verification:
      - kind: other
        ref: "supercollider/smoke_test.scd (CHECK OK: eng-05 no stacking)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Stop silences every layer with the classic_lead lead playing: empty instrument group within 2.5 s, no role renders another bar, no Pbindef plays"
    requirement: ENG-05
    verification:
      - kind: other
        ref: "supercollider/smoke_test.scd (CHECK OK: stop silences every layer)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The whole phase passes the one-command gate and the Python suite"
    requirement: ENG-05
    verification:
      - kind: other
        ref: "./scripts/check.sh (CHECK PASS); .venv/bin/python -m pytest -q python_app/tests (150 passed)"
        status: pass
    human_judgment: false
  - id: D6
    description: "The default startup sounds like the shipped engine, and classic_lead adds only a faint shimmer that /pp/melody classic removes (D-01, D-06)"
    requirement: LIB-01
    verification: []
    human_judgment: true
    rationale: "Whether the split sounds identical and whether the shimmer is faint enough can only be judged by ear; the rider answers in the end-of-phase UAT"

duration: 40min
completed: 2026-10-11
status: complete
---

# Phase 4 Plan 06: Re-evaluating never stacks, Stop silences everything Summary

**The smoke suite now proves that three re-evaluations of main.scd and two of each core module leave exactly 7 players, 1 routine and unchanged clock, group, SynthDef and OSCdef counts with classic_lead still selected and playing, and that Stop empties the instrument group with the lead playing; `check.sh` prints CHECK PASS**

## Performance

- **Duration:** about 40 min
- **Completed:** 2026-10-11
- **Tasks:** 2
- **Files:** 1 modified (`supercollider/smoke_test.scd`); `supercollider/main.scd` unchanged

## Accomplishments
- `eng-05 no stacking`: selects `classic_lead`, proves the lead is rendering notes, counts, re-evaluates `main.scd` three times, counts again. Every key must match, players must equal the seven layers, routines must be 1, the Pdef names must be exactly the seven layers, the selection and registry entry must survive, the lead must still flow, and no `ERROR` or `playing classic for this bar` line may appear in `~ppLogLines`.
- `eng-05 module re-evaluation`: `validate.scd`, `loader.scd`, `render.scd`, each loaded twice with `.load` while playing, then the same count comparison, all seven roles must have rendered more notes, `~ppLib` must still hold `classic` in all three categories and `classic_lead`.
- `stop silences every layer`: lead proven flowing and instrument nodes proven present, then `/pp/play 0`; the instrument group must be empty within 2.5 s, no role may render for 8 beats, no Pbindef may report playing.
- Posted counts line: `PedalPulse smoke: eng-05 counts players 7 routines 1 clocks 2 groups 6 synthDefs 121 oscdefs 10 pdefs [ppArp, ppBass, ppClap, ppHat, ppKick, ppLead, ppPad]`.

## Task Commits

1. **Task 1: eng-05 no stacking and module re-evaluation** - `61dfb6f` (test)
2. **Task 2: stop silences every layer** - `1fd10c5` (test)

**Plan metadata:** committed with this SUMMARY (docs)

## Gate results (Task 2 step 2)

| Measure | Result |
|---|---|
| `LIBCHECK OK` lines | 7 (`CHECK OK: library file count (7 files)`) |
| Parity | `parity rows=496 mismatches=0`, `CHECK OK: parity`, `LIBRARY PASS` |
| Smoke `CHECK OK:` lines | 70 (67 before this plan, plus 3) |
| eng-05 counts line | `players 7 routines 1 clocks 2 groups 6 synthDefs 121 oscdefs 10` |
| `check.sh` wall time | about 237 s (single run, includes library tier and smoke) |
| `check.sh` result | `CHECK PASS` |
| Python suite | 150 passed |

`TempoClock.all.size` is 2 in steady state (the default system clock plus `~clock`); the point is that it is identical before and after.

## Deviations from Plan

None - plan executed exactly as written. `supercollider/main.scd` was left unchanged because no check exposed a defect.

Two harness choices worth recording, neither a behaviour change:
- `reloadMain` waits until every layer's player has `nextBeat` set after each re-evaluation. The wave-5 finding was that stopping a layer whose bar-quantized start is still pending raises `'sched' not understood`, and back-to-back re-evaluations do exactly that (teardown stops each Pbindef). I did not run the suite without this wait, so I cannot say whether the engine itself would raise when a rider re-evaluates twice inside one bar; that remains an open question for a later plan if it matters.
- The counts line is posted as one line (named fields) rather than printing the Event, so the plan's grep for players and routines can read it.

## Non-vacuity probe

To show the check can fail, a temporary line leaking one `Group` per evaluation was added to `main.scd`. `eng-05 no stacking` then failed with `counts changed across re-evaluation: groups before 9 after 12`. The line was removed again with `git checkout`; it is not in any commit.

## Issues Encountered
- None. Smoke ran four times in total (two for Task 1, the mutation probe, and the full `check.sh`); neither known flake (`epic glide up`, `stop releases all`) appeared, and the new Stop check passed on its first run.
- In this worktree the scripts are run as `./scripts/smoke_test.sh` and `./scripts/check.sh` because the sandbox refuses `bash scripts/...` as a compound command; the scripts are identical. The plan's own `<automated>` greps read the logs under `$TMPDIR`, which `check.sh` and `smoke_test.sh` write.

## Pending human checks

**Listening check (D-01, D-06): status pending.** Deferred to the end-of-phase UAT (workflow.human_verify_mode is end-of-phase). The executor has not performed, simulated or approved it, and the phase stays human_needed until the rider answers. Steps, copied from the plan:

1. Open SuperCollider, open supercollider/main.scd, select everything and evaluate it, exactly as you always have. In a terminal in the PedalPulse folder, run ./run.sh to open the app.
2. Listen for a minute. It should be the same groove as before: same drums, bass, arpeggio and pad, same loudness.
3. Move the BPM slider, press Stop and then Start, click a few effort zones, and move the volume. Everything should behave as it did before.
4. While the music plays, paste this line into the terminal and press Enter:
   `.venv/bin/python -c "from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/melody', 'classic_lead')"`
   From the next bar, a soft, higher copy of the arpeggio should add shimmer. It should thicken the arpeggio, not sound like a new tune.
5. Press Stop while the shimmer is playing: everything goes quiet, the shimmer too. Press Start again.
6. Paste the same line with 'classic' in place of 'classic_lead'. At the next bar the shimmer stops and the original sound is back.

Expected: steps 2 and 3 sound and behave exactly like before the split; step 4 adds a faint shimmer one octave above the arpeggio; step 5 silences everything, shimmer included; step 6 brings back the original sound. If the shimmer is too loud, too quiet, or a different sound is wanted, that becomes a new library file (for example `classic_lead_soft.scd`); `classic_lead.scd` is never edited.

## Known Stubs
None.

## Threat Flags
None beyond the plan's register. T-04-15 (re-evaluation stacking) and T-04-16 (Stop failing to silence the lead) are mitigated by the two eng-05 checks and the Stop check, each with a precondition that makes it non-vacuous.

## Next Phase Readiness
The standing exit gate for Phases 6-9 exists: `./scripts/check.sh` runs the library guard, the library check and the smoke suite with the ENG-05 checks. Only the rider's listening check remains open for Phase 4. STATE.md, ROADMAP.md and REQUIREMENTS.md were not touched (the orchestrator owns them).

## Self-Check: PASSED
- `supercollider/smoke_test.scd` contains `eng-05 no stacking`, `eng-05 module re-evaluation`, `stop silences every layer`, `engineCounts`, `compareCounts`, `reloadMain`, `waitLeadFlowing`
- Commits `61dfb6f` and `1fd10c5` are ancestors of HEAD; `git rev-list --count a2de807..HEAD` is 2
- `./scripts/check.sh` prints CHECK PASS; smoke log has 70 `CHECK OK:` lines; `pytest python_app/tests` 150 passed; `supercollider/main.scd` and all library files are unchanged

---
*Phase: 04-modular-engine-variation-library*
*Completed: 2026-10-11*
