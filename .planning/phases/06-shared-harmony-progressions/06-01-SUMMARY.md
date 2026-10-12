---
phase: 06-shared-harmony-progressions
plan: 01
subsystem: audio-engine
tags: [supercollider, harmony, chord-progression, sclang, pbindef, library]

requires:
  - phase: 04-variation-library-core
    provides: "library loader/validator/renderer seam, classic files and golden, library_test and smoke gates"
provides:
  - "core/harmony.scd: one memoized harmony entry per (run, song bar) that bass, arp, pad and lead pull"
  - "Chord-data progression files (chords, barsPerChord) validated at load"
  - "anthem progression: Am F C G, one chord per bar"
  - "Cycle-boundary progression switching with a post-window line"
affects: [06-02, 06-03, 06-04, 06-05, phase-07-palettes, phase-08-melodies]

actuals:
  tokens: 10000
  tasks: 2
  commits: 2
plan_head_before: ced202d52625570c797f08f593dcd1d72773dd4f
plan_head_after: 61a92061bc58a70ef38e4fcf91706ea8201185ee

tech-stack:
  added: []
  patterns:
    - "Memoized per-bar entry pulled by layers (no mutable current-chord variable)"
    - "Run keyed by (thisThread.clock, bar - songBar); cycle decided on the previous cycle's last bar"
    - "Chord following by Am chord-tone ladder re-read off the current chord"

key-files:
  created:
    - supercollider/core/harmony.scd
    - supercollider/library/progressions/anthem.scd
  modified:
    - supercollider/core/validate.scd
    - supercollider/core/render.scd
    - supercollider/core/loader.scd
    - supercollider/main.scd
    - supercollider/library_test.scd
    - supercollider/smoke_test.scd

key-decisions:
  - "Bass and pad are core default generators reading the plan chord; a progression file is chord data and may still override with its own bass/pad"
  - "classic is an implicit Am chord with extraPcs [5] for its frozen passing F; classic.scd is untouched and arp/lead rows under classic are not mapped"
  - "Pad gate closes at least one beat before each chord change (legato min(0.9 x chordBars, chordBars - 0.25)); the frozen voice's 1.2 s release tail is left for the by-ear check"
  - "A melody module may declare ownHarmony: true to opt out of core chord mapping (planner decision, not confirmed by the rider; no shipped file uses it)"

patterns-established:
  - "Progression picks are read at cycle decisions only; palettes and melodies still switch at the next bar"
  - "Library chord-follow invariant tested by harmonyCheck on real recordings"

requirements-completed: [HARM-01, HARM-03, HARM-04]

coverage:
  - id: D1
    description: "Picking anthem plays Am F C G with bass, arp, pad and lead on the same chord every bar, through a tempo change and a restart"
    requirement: HARM-01
    verification:
      - kind: integration
        ref: "supercollider/library_test.scd#chord follow anthem"
        status: pass
    human_judgment: false
  - id: D2
    description: "Pad plays each chord once in the nearest close voicing inside MIDI 40-64 and holds it, gate closing a beat before the next chord"
    requirement: HARM-03
    verification:
      - kind: integration
        ref: "supercollider/library_test.scd#chord follow anthem"
        status: pass
    human_judgment: true
    rationale: "Voicing and sustain are asserted, but whether the outgoing chord's release tail clashes under the next chord is judged by ear (Plan 05 listening check)"
  - id: D3
    description: "A progression picked mid-cycle starts at the next cycle boundary, stays until another pick, and the post window says so"
    requirement: HARM-04
    verification:
      - kind: integration
        ref: "supercollider/library_test.scd#named progression switches at the cycle end"
        status: pass
    human_judgment: false
  - id: D4
    description: "Classic stays the golden note for note; auto still plays classic; Stop and ENG-05 module re-evaluation stay green with harmony.scd loaded"
    verification:
      - kind: integration
        ref: "bash scripts/check.sh (CHECK OK: parity, auto plays classic, eng-05 module re-evaluation, stop silences every layer)"
        status: pass
    human_judgment: false

duration: 14min
completed: 2026-10-12
status: complete
---

# Phase 6 Plan 01: Pick anthem and the whole band moves through Am F C G together Summary

**A memoized per-bar harmony entry (core/harmony.scd) that bass, arp, pad and lead all pull, so picking `anthem` plays Am F C G with every pitched note inside its own bar's chord, switching only at cycle boundaries, while classic stays the golden note for note.**

## Performance

- **Duration:** 14 min
- **Started:** 2026-10-12T18:41:32Z
- **Completed:** 2026-10-12T18:55:42Z
- **Tasks:** 2
- **Files modified:** 8 (2 created, 6 modified)

## Accomplishments

- New `core/harmony.scd`: one stored entry per (run, song bar), built strictly in order, at most 64 song bars kept, no Routine or clock (ENG-05), re-evaluable mid-ride because it never assigns `~ppHarm`. Cycle decision happens on the previous cycle's last bar so the bass pickup knows the next chord, and a pick arriving later waits one more cycle.
- Chord data for progressions: `~ppChordTypes` and `~ppChordDataReasons` in the validator (counts capped before iteration, types checked, cycle capped at 16 bars); `anthem.scd` is the first chord-data file.
- Renderer: bass and pad come from the cycle's captured module or the core defaults; arp and lead are mapped onto the chord by the Am chord-tone ladder (53 57 60 57 under F, 60 64 67 64 under C, 55 59 62 59 under G; lead stays exactly +12). Classic is left byte-identical.
- Bass: offbeat eighths on the chord root; last eighth is a chord-tone pickup toward the next root (anthem: 40, 36, 43, 35) or the third. Pad: nearest close voicing (45 48 52, 45 48 53, 43 48 52, 43 47 50), sustain 3 beats.
- Proof by real recordings: `chord follow anthem` (tempo change at bar 5 and 9, then a restart replaying the same rows) and `named progression switches at the cycle end` (pick at bar 5 lands at bar 8 or 12, return pick lands at 14 to 16 and stays). Full gate `bash scripts/check.sh` prints `CHECK PASS`.

## Task Commits

1. **Task 1 (tracer): anthem plays Am F C G with all four layers on one chord, classic stays the golden** - `a6909b0` (feat)
2. **Task 2: mid-cycle pick waits for the cycle boundary, post window says so, full gate passes** - `61a9206` (feat)

**Plan metadata:** committed separately (docs: complete plan)

## Files Created/Modified

- `supercollider/core/harmony.scd` - chord expansion, cycles, entries, run-keyed memo, nearest voicing, chord-follow mapping, bass root and pickup, default bass and pad
- `supercollider/library/progressions/anthem.scd` - Am F C G, one chord per bar (FINAL)
- `supercollider/core/validate.scd` - `~ppChordTypes`, `~ppChordDataReasons`, progressions branch accepts `chords`
- `supercollider/core/render.scd` - `~ppPlanFor` optional entry, `~ppRenderBar` pulls the entry and maps arp/lead
- `supercollider/core/loader.scd` - progression pick wording: switches at the end of the current progression cycle
- `supercollider/main.scd` - loads harmony.scd, `~ppHarmReset` on teardown and every Start, OSC comment
- `supercollider/library_test.scd` - `harmonyCheck`, two new recording checks, per-file memo reset in the static round trip
- `supercollider/smoke_test.scd` - harmony.scd in the ENG-05 module re-evaluation list

## Decisions Made

- Followed the plan's recorded decisions (core default bass/pad, implicit classic Am with extraPcs [5], ladder-based arp/lead mapping, pad release one beat before the change, `ownHarmony` opt-out). `ownHarmony` and the pad release gap are planner decisions made in yolo mode that the rider has not heard or confirmed; both are listed for Plan 05's review. No Phase 6 library file uses `ownHarmony`.
- Run identity is `[thisThread.clock, bar - songBar]`: a fresh recording clock, a Start (explicit reset) or a changed base always begins a new run at the selected progression's first chord, and a tempo change cannot affect it because bars are beat-based.

## Deviations from Plan

None - plan executed exactly as written.

**Total deviations:** 0
**Impact on plan:** None.

## Issues Encountered

- The sandbox refused compound shell commands (heredocs piped to interpreters, `cd` plus a pipeline), so helper edits were done with Edit/Write and one-line commands. No effect on the result.
- A `.venv` symlink to the main checkout's virtualenv was created in the worktree so `scripts/check.sh` could run; it is untracked and was never staged.

## Known Stubs

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Ready for Plan 02 (the remaining progression files): the chord-data shape, validator, memo, default bass/pad, chord-follow mapping and `harmonyCheck` are in place; Plan 02 only adds files plus its on-disk invariant loop.
- Plan 04 (Auto rotation) plugs into `~ppHarmDecide`, which currently resolves `auto` to classic.
- Open by-ear items for Plan 05: pad release tail under the next chord (frozen 1.2 s voice release), `ownHarmony` opt-out wording, and audibility of the chord moves.

## Self-Check: PASSED

- FOUND: supercollider/core/harmony.scd, supercollider/library/progressions/anthem.scd
- FOUND commits: a6909b0, 61a9206 (ancestors of HEAD)
- `bash scripts/check.sh` printed `CHECK PASS`; library log holds `CHECK OK: parity`, `CHECK OK: auto plays classic`, `CHECK OK: chord follow anthem`, `CHECK OK: named progression switches at the cycle end`, `LIBCHECK OK: progressions/anthem`; smoke log holds `CHECK OK: eng-05 module re-evaluation` and `CHECK OK: stop silences every layer`
- Frozen library files and the golden still have exactly one commit each; anthem.scd has one

---
*Phase: 06-shared-harmony-progressions*
*Completed: 2026-10-12*
