---
phase: 06-shared-harmony-progressions
plan: 03
subsystem: audio-engine
tags: [supercollider, chord-progression, library, chord-data, harmony]

requires:
  - phase: 06-shared-harmony-progressions
    provides: "chord-data core and anthem (Plan 01); strict static branch and chord-follow loop over every progression on disk (Plan 02)"
provides:
  - "six new chord-data progressions: rocker, lift, return, deep, melancholy, drama"
  - "shipped progressions table check pinning names, cycle length, spans, E major pitch classes and distinct descriptions"
  - "_template.scd rewritten as the chord-data recipe"
affects: [06-04, 06-05]

actuals:
  tokens: 6000
  tasks: 2
  commits: 2
plan_head_before: 6bfa3313a5938a0b01f5e4b74ea1b4e58dcec060
plan_head_after: 10f37d11392fd7a7c492a7c1960ddb41741fc46d

tech-stack:
  added: []
  patterns:
    - "A new progression is a few lines of chord data; the Plan 02 gates cover it the moment it exists on disk"
    - "A table check on the real files catches a wrong root number before the file is frozen by its commit"

key-files:
  created:
    - supercollider/library/progressions/rocker.scd
    - supercollider/library/progressions/lift.scd
    - supercollider/library/progressions/return.scd
    - supercollider/library/progressions/deep.scd
    - supercollider/library/progressions/melancholy.scd
    - supercollider/library/progressions/drama.scd
  modified:
    - supercollider/library/progressions/_template.scd
    - supercollider/library_test.scd

key-decisions:
  - "Drama's last chord is E major (root 7, maj): G sharp in the arp, pad voiced 44 47 52"
  - "Deep is two bars per chord with Am listed twice, giving an 8-bar cycle with Am held 4 bars; no shipped cycle is longer than 8 bars"
  - "No core change was needed: all six files passed the strict static branch and the chord-follow recording first time"

patterns-established:
  - "Each library file has exactly one commit; the table check ran green before the commit"

requirements-completed: [HARM-02, HARM-01]

coverage:
  - id: D1
    description: "The Progression dropdown source lists classic plus seven named progressions (anthem, deep, drama, lift, melancholy, return, rocker)"
    requirement: HARM-02
    verification:
      - kind: unit
        ref: ".venv/bin/python scan_library(LIBRARY_ROOT/progressions) == [classic, anthem, deep, drama, lift, melancholy, return, rocker]"
        status: pass
    human_judgment: false
  - id: D2
    description: "Each new file plays its own chords and pace: rocker Am G F G, lift Am F G G, return Am C G F, deep Am Am F G over 8 bars, melancholy Am Em F Dm, drama Am Dm F E"
    requirement: HARM-02
    verification:
      - kind: integration
        ref: "supercollider/library_test.scd#shipped progressions"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every new file keeps bass, arp, pad and lead inside its bar's chord, statically over two cycles and in a real recording"
    requirement: HARM-01
    verification:
      - kind: integration
        ref: "scripts/check.sh --library-only: LIBCHECK OK progressions/<stem>, CHECK OK: chord follow <stem>"
        status: pass
    human_judgment: false
  - id: D4
    description: "The seven progressions sound clearly different from each other and each description matches what the rider hears"
    requirement: HARM-02
    verification: []
    human_judgment: true
    rationale: "Distinctness of sound is a listening judgement, collected in the Plan 05 end-of-phase listening check"

duration: 12min
completed: 2026-10-12
status: complete
---

# Phase 6 Plan 03: Seven progressions to choose from, each with its own chords and pace Summary

**Six new chord-data progression files (rocker, lift, return, deep at two bars per chord, melancholy, drama with a major E) join anthem and classic, each pinned by a table check and passed through the strict static and recording gates.**

## Performance

- **Duration:** about 12 min
- **Completed:** 2026-10-12
- **Tasks:** 2
- **Files modified:** 8 (six created, two modified)

## Accomplishments

- Six progression files, each a header plus one Event of literal chord data. Drama's E major carries a comment that it is major on purpose; deep uses `barsPerChord: 2` for an 8-bar cycle.
- `shipped progressions` check in the static block of `library_test.scd`: loads each real file, requires names and cycle length, the lift (Am 1, F 1, G 2) and deep (Am 4, F 2, G 2) spans, drama's last chord pitch classes `[4, 8, 11]`, cycle at most 8 bars, first chord Am, and eight different descriptions across the seven files plus classic.
- `_template.scd` now teaches the chord-data recipe (roots relative to A, qualities or intervals, pace, optional bass/pad generators with the extra plan keys) and itself passes the strict check.
- The library gate shows `LIBCHECK OK` and `CHECK OK: chord follow <stem>` for all seven stems, `PedalPulse: progression drama: Am Dm F E` and `PedalPulse: progression deep: Am Am F G`, and `CHECK OK: library file count (15 files)`.
- Python suite unchanged: 191 passed; `scan_library` returns `[classic, anthem, deep, drama, lift, melancholy, return, rocker]`, so the dropdown shows the new names with no Python change.
- Full `scripts/check.sh` prints `CHECK PASS` (no flaky smoke failure on this run).

## Task Commits

1. **Task 1: six new progressions plus the shipped progressions table check** - `5ab49b9` (feat)
2. **Task 2: template as the chord-data recipe, full gate green** - `10f37d1` (docs)

## Files Created/Modified

- `supercollider/library/progressions/rocker.scd`, `lift.scd`, `return.scd`, `deep.scd`, `melancholy.scd`, `drama.scd` - the six new chord-data progressions
- `supercollider/library/progressions/_template.scd` - chord-data recipe
- `supercollider/library_test.scd` - `shipped progressions` check

## Decisions Made

- No core change: the strict gate from Plan 02 accepted all six files on the first run.
- Template commit typed `docs` since only comments and example data changed.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- A temporary untracked `.venv` symlink to the main checkout's virtualenv was created so `scripts/check.sh` and pytest could run; it was never staged and was removed before finishing.

## Known Stubs

None.

## Next Phase Readiness

- Ready for Plan 04 and the Plan 05 end-of-phase listening check, where "the progressions sound distinct" is judged by ear. A progression that sounds wrong must be replaced by a new file, never an edit.

## Self-Check: PASSED

- FOUND commits 5ab49b9 and 10f37d1 (ancestors of HEAD)
- The six progression files and `_template.scd` exist; drama contains `(root: 7, quality: \maj)`; deep contains `barsPerChord: 2`
- `./scripts/check.sh --library-only` and `./scripts/check.sh` both pass; `CHECK OK: shipped progressions` present

---
*Phase: 06-shared-harmony-progressions*
*Completed: 2026-10-12*
