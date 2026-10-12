---
phase: 06-shared-harmony-progressions
plan: 02
subsystem: audio-engine
tags: [supercollider, harmony, library-check, static-tier, negative-controls, chord-progression]

requires:
  - phase: 06-shared-harmony-progressions
    provides: "core/harmony.scd entries and cycles, chord-data validator, anthem, harmonyCheck (Plan 01)"
provides:
  - "harmony units check: the arp, lead, bass-root, third, pickup and pad-voicing rules pinned by exact values"
  - "strict chord-data branch in staticCheck: two full cycles of every chord-data progression file rendered and checked with no allowance"
  - "eight chord-data negative controls (seven malformed files with exact reasons, one bass outside its chord)"
  - "chord-follow recording loop over every non-classic progression on disk"
affects: [06-03, 06-04, 06-05]

actuals:
  tokens: 10000
  tasks: 2
  commits: 2
plan_head_before: 96be1a1523bff948c71aa90f9a4a0234b8022a03
plan_head_after: 32163e82a1ffa95c4b1eb0c6a31a6b00c91953b5

tech-stack:
  added: []
  patterns:
    - "Independent voicing oracle (enumVoicings) in the test, separate from the core's inversion search"
    - "Static strict check uses explicit pure entries, never the live memo"
    - "Recording tier loops over listStems of the real folder so a new file is covered automatically"

key-files:
  created: []
  modified:
    - supercollider/library_test.scd
    - scripts/check.sh

key-decisions:
  - "No core defect found: every table value of the plan matched the Plan 01 core on the first run, so no change under supercollider/core"
  - "A chord-follow stem whose module has no chords is skipped with a CHECK SKIP line (generator-only files are covered by the static tier); every chord-data stem is checked"
  - "Added a ninth negative control (strict_bass: chord data with its own bass playing 34 under Am) to prove the strict branch actually refuses a bad file, beyond the seven malformed-data fixtures the plan listed"

patterns-established:
  - "Committed library files stay untouched; every new progression is gated by the same loops before commit"

requirements-completed: [HARM-01, HARM-03]

coverage:
  - id: D1
    description: "Arp, lead, bass root, third, pickups and pad voicing paths of seven planned progressions hold exact values; classic rows equal the frozen generators"
    requirement: HARM-03
    verification:
      - kind: integration
        ref: "supercollider/library_test.scd#harmony units"
        status: pass
    human_judgment: false
  - id: D2
    description: "HARM-03 boundary and precision edges: voicings inside 40-64 at both window edges; G to F tie resolves to 45 48 53"
    requirement: HARM-03
    verification:
      - kind: integration
        ref: "supercollider/library_test.scd#harmony units"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every chord-data progression on disk is checked strictly for two cycles statically and in a real recording with a tempo change and a restart"
    requirement: HARM-01
    verification:
      - kind: integration
        ref: "supercollider/library_test.scd#static check / chord follow <stem>"
        status: pass
    human_judgment: false
  - id: D4
    description: "Malformed chord data is refused with the exact reason (T-06-01, T-06-04)"
    requirement: HARM-01
    verification:
      - kind: integration
        ref: "supercollider/library_test.scd#static check catches bad files"
        status: pass
    human_judgment: false

duration: 20min
completed: 2026-10-12
status: complete
---

# Phase 6 Plan 02: The strict harmony gate, in place before any more progressions are committed Summary

**The harmony rules are pinned by exact values and every chord-data progression, now and later, is checked strictly (two cycles statically, a recording with a tempo change and a restart live), with seven malformed chord files refused by their exact reasons.**

## Performance

- **Duration:** about 20 min
- **Started:** 2026-10-12T18:50Z
- **Completed:** 2026-10-12T19:09Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- `harmony units` (static tier, no server): chord names and pitch classes for seven chords, the four-note chord `A(0,3,7,10)`, intervals over quality, E major scale; arp and lead tables and four non-chord-tone cases; bass roots, thirds and all 17 pickups; pad path of seven progressions over two cycles against an independent candidate enumerator (every change is the minimum movement and at most 6 semitones); the G to F tie (`45 48 53`); previous voicings at and beyond both window edges; cycle and entry records; default bass and pad through `~ppRenderBar` (legato 3.6, 1.75, 0.75); classic rows byte-identical to the frozen generators; `ownHarmony`; the memo shared, capped at 64 entries and 256 cycle records, and picks waiting for the cycle end (late pick waits one more cycle).
- Strict branch (c2) in `staticCheck`: for every chord-data progression file it walks two cycles with explicit entries and renders bass, pad and arp, failing on any note outside the bar's chord (no allowance), bass not four offbeats, arp not the mapped classic figure, pad not once per chord with legato `min(0.9 x bars, bars - 0.25)` and a gate closing at least a beat early, a non-nearest or out-of-window voicing, or a classic fallback log line. A cycle above 8 bars prints `CHECK WARN` and does not fail.
- Eight negative controls in the temporary root: bad root, unknown quality, bad intervals, empty chords, 17 chords, 0 bars, 24-bar cycle (each matched by its exact reason) and a chord file whose own bass plays a non-chord note (proves the strict branch bites).
- The anthem-only recording became a loop over every non-classic progression stem (chord data, tempo change at bars 5 and 9, `2 x len + 4` bars, then a restart replay over `len` bars). Anthem's literal pickups 40 36 43 35 are still asserted.
- Library check timeout raised to 330 s, watchdog to 300 s. Full library gate takes about 80 s today.

## Task Commits

1. **Task 1: harmony rules pinned by exact values** - `4b2561b` (test)
2. **Task 2: strict gate for every chord-data progression, negative controls, chord-follow loop, timeouts** - `32163e8` (test)

## Files Created/Modified

- `supercollider/library_test.scd` - `enumVoicings`, `voicingCost`, `strictChordCheck`, `harmony units`, (c2) branch, chord-data fixtures, chord-follow loop, 300 s watchdog
- `scripts/check.sh` - library check timeout 330 s

## Decisions Made

- No core change was needed: every expected value of the plan matched `core/harmony.scd` and `core/render.scd` from Plan 01 on the first run.
- Mutation spot checks (pickup value, pad sustain) were run once to confirm the new checks fail when a value is wrong, then reverted.

## Deviations from Plan

### Additions

**1. [Rule 2 - Missing critical] Ninth negative control `strict_bass`**
- **Found during:** Task 2
- **Issue:** The seven listed fixtures prove malformed data is refused, but nothing proved the strict in-chord rule itself refuses a file that loads fine.
- **Fix:** Added a chord-data fixture with its own bass playing 34 under Am and an `expectFailure` on `progressions/strict_bass bass bar 0: note 34 is not in chord Am`.
- **Files modified:** supercollider/library_test.scd
- **Commit:** 32163e8

**2. Chord-follow loop skips modules without chords**
- A non-classic stem with no `chords` prints `CHECK SKIP: chord follow <stem> (no chord data)` instead of being held to chord-follow assertions; the static tier still checks it. All files planned for this phase are chord data.

**Total deviations:** 1 auto-added control, 1 documented scoping choice. **Impact:** none on scope; stricter coverage.

## Issues Encountered

- A temporary untracked `.venv` symlink to the main checkout's virtualenv was created so `scripts/check.sh` could run; it was never staged and is removed before finishing.

## Known Stubs

None.

## Next Phase Readiness

- Ready for Plan 03: the six remaining progression files (rocker, lift, return, deep, melancholy, drama) are gated automatically by the static strict branch and the chord-follow loop the moment they exist on disk, and a 24-bar or malformed file is refused.
- `scripts/check.sh --library-only` currently prints `CHECK OK: library file count (9 files)`; Plan 03 raises it to match the new files.

## Self-Check: PASSED

- FOUND commits 4b2561b, 32163e8 (ancestors of HEAD)
- `./scripts/check.sh --library-only` prints `CHECK PASS (library only)` with `CHECK OK: harmony units`, `CHECK OK: static check catches bad files`, `CHECK OK: chord follow anthem`, `CHECK OK: named progression switches at the cycle end`, `LIBCHECK OK: progressions/anthem`, `CHECK OK: library file count (9 files)`
- `git status --porcelain -- supercollider scripts` is empty after the commits; no file under `supercollider/library` changed

---
*Phase: 06-shared-harmony-progressions*
*Completed: 2026-10-12*
