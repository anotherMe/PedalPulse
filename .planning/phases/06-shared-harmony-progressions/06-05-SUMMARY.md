---
phase: 06-shared-harmony-progressions
plan: 05
subsystem: audio-engine
tags: [supercollider, smoke-test, chord-progression, readme, exit-gate]

requires:
  - phase: 06-shared-harmony-progressions
    provides: "harmony memo and ~ppHarmReset (06-01), chord-follow gates (06-02), eight progression files (06-03), Auto rotation and prefetch (06-04)"
provides:
  - "Smoke checks 'progression stop and start' and 'progression re-evaluation' on the real isolated engine"
  - "Smoke watchdog 360 s and scripts/smoke_test.sh timeout 390 s"
  - "Library README sections 'Progressions and Auto' and 'Write a new progression'; updated pick, auto and file-contract text"
  - "Melody template documents ownHarmony and the harmony plan keys"
affects: [phase-06-uat, phase-08-melodies]

actuals:
  tokens: 9500
  tasks: 2
  commits: 2
plan_head_before: e70a66532f0040252781e306be32d197242f0a6e
plan_head_after: 6062bb61510e75f2bda9c4aa1ea5cb23e3bfebec

tech-stack:
  added: []
  patterns:
    - "Smoke checks poll for the observable effect (cycle log, instrument group, registry) with a bounded wait instead of fixed sleeps"

key-files:
  created: []
  modified:
    - supercollider/smoke_test.scd
    - scripts/smoke_test.sh
    - supercollider/library/README.md
    - supercollider/library/melodies/_template.scd

key-decisions:
  - "No core change was needed: both new smoke checks passed against main.scd, harmony.scd and loader.scd as they stood after Plan 04"
  - "The new re-evaluation check compares engine counts taken on anthem against counts taken after a re-evaluation on auto, so the same baseline proves both"

requirements-completed: [HARM-01, HARM-02, HARM-03, HARM-04]

coverage:
  - id: D1
    description: "With anthem playing, Stop empties the instrument group within 2.5 s and no layer renders another bar; Start begins a new harmony run on anthem's first chord (Am, cycle bar 0)"
    requirement: HARM-01
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd#progression stop and start"
        status: pass
    human_judgment: false
  - id: D2
    description: "Re-evaluating main.scd twice on anthem and once on auto leaves 7 players, 1 routine and identical groups, SynthDefs and OSCdefs; the selection survives; on auto every progression file is loaded again and the auto seed line is posted"
    requirement: HARM-04
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd#progression re-evaluation"
        status: pass
    human_judgment: false
  - id: D3
    description: "The whole gate passes with all 15 library files, every progression included"
    requirement: HARM-02
    verification:
      - kind: integration
        ref: "bash scripts/check.sh (CHECK PASS, CHECK OK: library file count (15 files))"
        status: pass
      - kind: unit
        ref: ".venv/bin/python -m pytest -q python_app/tests (191 passed)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The README tells the rider how a progression switches, what Auto does, and how to write a progression; the melody template explains chord following and ownHarmony"
    requirement: HARM-03
    verification:
      - kind: other
        ref: "grep of README headings and phrases; LIBCHECK OK: melodies/_template"
        status: pass
    human_judgment: true
    rationale: "Whether the plain-language wording is clear to a rider who is not a SuperCollider musician is a reading judgement"
  - id: D5
    description: "Progressions sound distinct, change chord with no sour notes, the pad is smooth at the changes, switching waits for the cycle end, Auto paces well over minutes"
    requirement: HARM-01
    verification: []
    human_judgment: true
    rationale: "Only the rider's ear can judge distinct, clean and smooth; queued for the end-of-phase UAT and not performed by the executor"

duration: 35min
completed: 2026-10-12
status: complete
---

# Phase 6 Plan 05: Stop, Start and re-evaluation are safe with any progression, the README explains it, and the rider listens Summary

**Two real-engine smoke checks prove Stop silences a held anthem pad, Start begins on Am, and re-evaluating with anthem or Auto stacks nothing; the library README and melody template now explain progressions, Auto and chord following; the rider's listening check is queued for the end-of-phase UAT.**

## Performance

- **Duration:** about 35 min (most of it waiting on the 80 s library gate and the roughly 5 minute smoke suite, which ran three times)
- **Completed:** 2026-10-12
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- `progression stop and start`: selects anthem, waits until anthem is the playing cycle and the bass has rendered, then sends Stop. The instrument group empties within 2.5 s (a held pad is released too), no role renders another bar over 8 beats, every Pbindef is stopped. After Start the new run has a different harmony signature, its first cycle-log record is anthem, and that bar's entry is cycle bar 0 on chord "Am".
- `progression re-evaluation`: two re-evaluations on anthem leave 7 players, 1 routine and identical groups, SynthDefs, OSCdefs and Pdefs, keep the anthem selection and registry entry, and log no ERROR or "playing classic for this bar". A third re-evaluation on auto keeps the selection, loads all 8 progression files again within 3 s with the folder scan finished, posts `PedalPulse: progression auto seed <n>`, and leaves the engine counts equal to the anthem baseline with 1 routine.
- `scripts/smoke_test.sh` timeout raised 330 to 390 s, and the smoke watchdog 300 to 360 s, as planned.
- `supercollider/library/README.md`: new sections "Progressions and Auto" and "Write a new progression"; the eight progressions listed; the auto, pick-a-variation, try-it, and file-contract text corrected for progressions (cycle-end switching, `ownHarmony`, the harmony plan keys). The "Pick a variation from the app" heading and the "already selected" paragraph are kept.
- `supercollider/library/melodies/_template.scd`: comments only (chord following, `ownHarmony`, harmony plan keys); `LIBCHECK OK: melodies/_template` still prints.
- `bash scripts/check.sh` prints `CHECK PASS` with `CHECK OK: library file count (15 files)`, `CHECK OK: eng-05 no stacking`, `CHECK OK: eng-05 module re-evaluation`, `CHECK OK: stop silences every layer`, both new checks and `SMOKE PASS`. Python suite: 191 passed. `python_app/` is byte-identical to the pre-phase commit 3066535.

## Task Commits

1. **Task 1: progression stop/start and re-evaluation smoke checks, raised timeouts** - `4736a6b` (test)
2. **Task 2: README and melody template** - `6062bb6` (docs)

**Plan metadata:** committed separately (docs: complete plan)

## Files Created/Modified

- `supercollider/smoke_test.scd` - two new checks before SMOKE PASS, watchdog 360 s
- `scripts/smoke_test.sh` - timeout and gtimeout 390 s
- `supercollider/library/README.md` - progressions, Auto, writing a progression, chord following
- `supercollider/library/melodies/_template.scd` - comments on chord following and ownHarmony

## Decisions Made

None beyond following the plan. No core file needed a change: both checks passed on the code as left by Plan 04.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The first full `bash scripts/check.sh` run failed in the smoke suite with `SMOKE FAIL: ERROR: instrDefNames: no /g_queryTree.reply within 1s` followed by `Server 'ppSmoke' is currently unresponsive`, right after `CHECK OK: all layers playing` and before any of this plan's checks. It is a different failure from the known flaky `epic glide up` check. A direct rerun of the smoke suite passed, and the following full `bash scripts/check.sh` passed, so I treated it as a transient server stall and made no change. Worth knowing if it recurs: it would point at the isolated server (port 57140) not answering a `/g_queryTree`.
- The known flaky `epic glide up` check did not fail in the final run.
- A temporary untracked `.venv` symlink to the main checkout's virtualenv was created so `scripts/check.sh` and pytest could run; it was never staged and is removed before finishing.

## Known Stubs

None.

## Threat Flags

None. The two new checks are test-only and send OSC only to the smoke suite's own isolated engine. T-06-11 and T-06-12 are covered by the new checks, which pass.

## User Setup Required

None - no external service configuration required.

## Pending human checks

**Progression listening check (HARM-01, HARM-02, HARM-03, HARM-04)** - PENDING. Deferred to the end-of-phase UAT (`workflow.human_verify_mode` is end-of-phase). The executor did not perform, simulate or approve it; only the rider's own answer closes it. The phase stays human_needed until then. Steps, copied from the plan:

1. Open SuperCollider, open supercollider/main.scd, select everything and evaluate it. In a terminal in the PedalPulse folder run ./run.sh. The post window shows a line "PedalPulse: progression classic: Am" and a line "PedalPulse: progression auto seed" followed by a number.
2. Open the Progression dropdown: it lists Auto, classic, anthem, deep, drama, lift, melancholy, return and rocker. In the Melody dropdown pick classic_lead_loud so the lead is easy to hear.
3. Pick each named progression in turn and listen for at least two rounds of its chords. The post window prints "PedalPulse: progression <name>: <chords>" when it starts. Bass, pad, arp and lead change chord together, with no sour or clashing note at the changes. Write one plain sentence per progression about how it feels, and say if two of them sound too alike.
4. Pick deep, then anthem. The pad moves smoothly from chord to chord instead of jumping; on deep the first chord holds for four bars. Listen right at each chord change: the old pad chord should already be fading when the new one comes in (the engine lets it go one beat early). Say if you hear two pad chords smeared together into a sour wash at the change.
5. While anthem plays, pick drama at a random moment. The change comes when anthem is back at its first chord (Am), never in the middle of its four chords, and drama then keeps playing. On drama the last chord (E) sounds bright and leads back to Am.
6. Still on drama, press Up a few times and then Down a few times so the tempo glides, then press Stop and Start. The chords keep changing together during the glide, and after Start the music begins again on drama's first chord.
7. Pick classic in Progression and in Melody: you hear exactly the original groove.
8. Pick Auto in Progression (Melody can stay on classic_lead_loud) and leave it for about 6 minutes. It keeps classic first; then every 2-3 minutes a new "PedalPulse: progression <name>" line appears and the chords change at the start of a round, never in the middle; a name never comes back straight after itself.
9. Pick anthem and wait for its "PedalPulse: progression anthem" line, then pick Auto. Anthem keeps playing: it does not jump to another progression, or back to classic, at the end of its round (Auto moves on after about 1-2 minutes; you do not need to wait for that). Claude chose this so that the Auto the app sends at launch keeps the classic opening. Say whether this feels right, or whether you would rather have Auto go back to classic first, or change sooner.

If anything sounds wrong, describe it in your own words. Claude will change the core or add a new library file; existing library files are never edited.

**Other by-ear items carried from earlier waves** (all pending, for the same UAT):

- 06-01: the ownHarmony opt-out is a design choice the rider has not heard in use (no shipped file uses it); the 1-beat pad release gap, heard in step 4.
- 06-03: whether the new progressions (anthem, rocker, lift, return, deep, melancholy, drama) sound distinct from one another and from classic, heard in step 3.
- 06-04: whether a real 32-64 bar Auto hold at ride tempo (about 2-3 minutes) feels like a natural pace, heard in step 8; and the adopt-then-hold behaviour, heard in step 9.

## Planner decisions for the rider to review

These three were decided by Claude in yolo mode. The rider has not been asked and has not confirmed any of them; each can be changed.

1. **A melody file can opt out of chord following with `ownHarmony: true`** (RESEARCH Open Question 1). It lives in `supercollider/core/render.scd` (the chord-follow gate reads `mod[\ownHarmony]`) and is documented in the library README and `melodies/_template.scd`. No Phase 6 file uses it, so dropping it is a core-only change in render.scd.
2. **The pad lets go one beat before each chord change, while the frozen pad voice's slow fade still overlaps the start of the next chord** (RESEARCH Pitfall 4). It lives in `supercollider/core/harmony.scd` as `~ppPadGapBeats` (default 1; the legato of a pad chord is capped to leave that gap). Heard in step 4. The rider can ask for a larger or smaller gap by changing that one number, or for a new pad voice in a new palette file.
3. **Auto picked mid-ride keeps the playing progression for one full hold before rotating, while every Start begins on classic** (RESEARCH Open Question 4). It lives in `~ppHarmAutoNext` in `supercollider/core/harmony.scd` (engage: classic at a run start, otherwise adopt what is ending). Heard in step 9. The rider can ask for a plain shuffle from the end of the current cycle, or for Auto to go back to classic first.

## Next Phase Readiness

- All five plans of Phase 6 are done and the automated gate is green. The phase verifier collects the listening check above from the 06-05 PLAN file; the phase stays human_needed until the rider answers it.
- Nothing blocks Phase 7. Phase 8 melodies can set `ownHarmony: true` if they read `plan[\chord]` themselves.

## Self-Check: PASSED

- FOUND commits 4736a6b and 6062bb6 (ancestors of HEAD); `git rev-list --count e70a665..HEAD` was 2 before this SUMMARY
- FOUND supercollider/smoke_test.scd, scripts/smoke_test.sh, supercollider/library/README.md, supercollider/library/melodies/_template.scd
- `bash scripts/check.sh` printed `CHECK PASS`; smoke log has `CHECK OK: progression stop and start`, `CHECK OK: progression re-evaluation`, `CHECK OK: eng-05 no stacking`, `CHECK OK: eng-05 module re-evaluation`, `CHECK OK: stop silences every layer`, `SMOKE PASS`
- pytest 191 passed; `python_app/` identical to 3066535

---
*Phase: 06-shared-harmony-progressions*
*Completed: 2026-10-12*
