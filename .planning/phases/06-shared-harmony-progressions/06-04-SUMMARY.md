---
phase: 06-shared-harmony-progressions
plan: 04
subsystem: audio-engine
tags: [supercollider, chord-progression, auto-rotation, seeded-shuffle, harmony, library]

requires:
  - phase: 06-shared-harmony-progressions
    provides: "memoized harmony decision point ~ppHarmDecide (Plan 01); eight progression files and the chord-follow gates (Plans 02-03)"
provides:
  - "Auto rotation for progressions: classic first, whole-cycle holds of about 32-64 bars, seeded shuffle with no quick repeats, changes only at cycle ends"
  - "~ppAutoPrefetch: background scan of the progressions folder so a file added while the engine runs joins the rotation"
  - "Auto seed posted at boot; progression auto line says Auto rotates at cycle ends"
  - "Six Auto checks in the library gate (rotation, adoption, new file, bounded, failing progression, broken file once)"
affects: [06-05, phase-08-melodies]

actuals:
  tokens: 14000
  tasks: 2
  commits: 3
plan_head_before: 93b8d6dcfc0d43964e9b9e4b61323234a27480bb
plan_head_after: 623447bc5c50f9a5e912ddedd03128a5e57245e3

tech-stack:
  added: []
  patterns:
    - "Auto state lives inside the run memo (~ppHarm[\\auto]) so a Start begins a new rotation on classic"
    - "Thread seed set right before each draw (thisThread.randSeed from engine seed and pick number); no Stream class"
    - "A background scan on SystemClock registers new files; the layer that decides a cycle never waits for disk"
    - "Failed-file memory keyed by path and modification time: report a broken file once per change"

key-files:
  created: []
  modified:
    - supercollider/core/harmony.scd
    - supercollider/core/loader.scd
    - supercollider/main.scd
    - supercollider/library_test.scd

key-decisions:
  - "Auto selected mid-ride adopts the progression that is playing and holds it for a fresh hold, then shuffles; at every run start (Start, Stop then Start, re-evaluation) Auto begins on classic (D-09). Planner decision made in yolo mode, resolving RESEARCH Open Question 4; the rider has not reviewed it. It departs from the literal D-09 wording and from the Open Question 4 recommendation only when Auto is chosen mid-run, because the app sends auto at launch while the autostarted engine already plays classic, and a plain shuffle would replace classic one or two bars later."
  - "A named pick clears Auto's current progression, so a later Auto adopts whatever plays then rather than resuming an old hold"
  - "Auto seed is chosen once per interpreter (~ppAutoSeed ? ...), kept across re-evaluation, posted at every evaluation of main.scd; every draw seeds the thread from (seed, pick number), so a heard order replays within a run"
  - "Candidates are sorted by name before the seeded choice; a stem is excluded when its file is gone from the current library root or its render-error count is 3 or more"

patterns-established:
  - "Memo decisions may now have side effects, so no `?` with a decision call on the right (eager argument)"

requirements-completed: [HARM-04, HARM-02]

coverage:
  - id: D1
    description: "With Progression on Auto the engine starts on classic, then changes progression by itself; each progression plays whole cycles of 4-8 bars (shrunk hold) and every change lands at a cycle end"
    requirement: HARM-04
    verification:
      - kind: integration
        ref: "supercollider/library_test.scd#auto rotates progressions"
        status: pass
    human_judgment: false
  - id: D2
    description: "Auto never repeats the progression playing or either of the last two, chooses from every progression on disk, and the order comes from a seed posted once at engine start"
    requirement: HARM-02
    verification:
      - kind: integration
        ref: "supercollider/library_test.scd#auto rotates progressions"
        status: pass
    human_judgment: false
  - id: D3
    description: "Auto picked mid-ride keeps the playing progression for a full hold before rotating; a fresh run begins on classic"
    requirement: HARM-04
    verification:
      - kind: integration
        ref: "supercollider/library_test.scd#auto keeps the playing progression first, auto plays classic"
        status: pass
    human_judgment: true
    rationale: "Adopt-then-hold is a planner decision made in yolo mode that the rider has not heard or confirmed; Plan 05 lists it for review"
  - id: D4
    description: "A progression file added while the engine runs joins the Auto rotation with no restart"
    requirement: HARM-02
    verification:
      - kind: integration
        ref: "supercollider/library_test.scd#auto adds a new progression file"
        status: pass
    human_judgment: false
  - id: D5
    description: "Auto state stays bounded over 1200 bars; a progression that fails 3 bars leaves the rotation while the music keeps playing; a broken file is reported once per change"
    requirement: HARM-04
    verification:
      - kind: integration
        ref: "supercollider/library_test.scd#auto stays bounded, auto skips a failing progression, auto reports a broken file once"
        status: pass
    human_judgment: false
  - id: D6
    description: "A 2-3 minute hold at real ride tempo feels like a natural pace and the chosen name shows in the post window"
    requirement: HARM-04
    verification: []
    human_judgment: true
    rationale: "The automated checks shrink the hold; whether the real 32-64 bar hold sounds right is a listening judgement for the Plan 05 end-of-phase check"

duration: 40min
completed: 2026-10-12
status: complete
---

# Phase 6 Plan 04: On Auto the engine moves through the progressions by itself Summary

**Auto now plays classic first, then rotates through every progression file on disk (new ones included) by a seeded shuffle with no quick repeats, always at the end of a cycle, with a background folder scan and bounded state proven over 1200 bars.**

## Performance

- **Duration:** about 40 min
- **Completed:** 2026-10-12
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- `~ppHarmAutoNext` plugs into `~ppHarmDecide`: engage (classic at a run start, otherwise adopt what is ending), hold for H = max(1, round(rrand(lo, hi) / cycleLen)) whole cycles (default 32-64 bars), then a seeded pick that excludes the current progression and the last two played, with fallbacks when nothing is left.
- `~ppAutoPrefetch` scans `progressions/*.scd` on SystemClock at every Auto pick (one scan at a time, 256 files at most). Names pass `~ppStemValid`, loading goes only through `~ppLibEnsure`, and a failed path is remembered with its modification time so a broken file is reported once per change.
- `main.scd` posts `PedalPulse: progression auto seed <n>` and prefetches when a stored progression selection is auto. Selecting auto now logs `rotates progressions at cycle ends; a Start begins on classic` for progressions only (palettes and melodies keep `resolves to classic`).
- Six new library checks pass: `auto rotates progressions`, `auto keeps the playing progression first`, `auto adds a new progression file`, `auto stays bounded`, `auto skips a failing progression`, `auto reports a broken file once`. The existing `auto plays classic` golden check still matches. `bash scripts/check.sh` prints `CHECK PASS`; Python suite 191 passed, `python_app/` unchanged from the pre-phase commit.
- No engine-to-app message was added (prohibition honoured): the post window is the only place the rider sees Auto's choice.

## Task Commits

1. **Task 1 RED: failing Auto tests** - `0b05333` (test)
2. **Task 1 GREEN: Auto rotation, prefetch, seed, wording** - `873342e` (feat)
3. **Task 2: bounded, failing-progression and broken-file checks, full gate** - `623447b` (test)

**Plan metadata:** committed separately (docs: complete plan)

## TDD Gate Compliance

- **RED:** `./scripts/check.sh --library-only` failed with `LIBRARY FAIL: ERROR: auto rotates progressions: fewer than 3 different progressions played in 48 bars: List[('start': 0, 'stem': classic, 'len': 51)]` - the target check ran and failed on the planned assertion because Auto still resolved to classic (semantic assessment: valid RED, not a load or syntax fault).
- **GREEN:** the three Task 1 checks plus the whole library gate pass after `873342e`.
- **REFACTOR:** none needed.

## Files Created/Modified

- `supercollider/core/harmony.scd` - `~ppAutoHoldBars`, `~ppAutoSeed`, `~ppAutoHistoryCap`, `~ppAutoCandidates`, `~ppHarmAutoNext`, Auto branch in `~ppHarmDecide`, `auto` state in the run memo, eager-`?` fix
- `supercollider/core/loader.scd` - `~ppAutoPrefetch`, `~ppAutoFailed`, `~ppAutoPrefetching`, progression auto wording
- `supercollider/main.scd` - auto seed line and boot prefetch
- `supercollider/library_test.scd` - six Auto checks (`fresh_prog.scd` and `gen_fail.scd` fixtures in the temporary root only)

## Decisions Made

See `key-decisions`. The adopt-then-hold rule is a deliberate planner decision made in yolo mode and not reviewed by the rider; it is listed for the Plan 05 "Planner decisions for the rider to review" section (the rider can ask for a pure shuffle from the end of the current cycle instead).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Cycle boundary evaluated ~ppHarmDecide eagerly**
- **Found during:** Task 1 (first GREEN run: runs lasted 12 bars with a 4-8 bar hold)
- **Issue:** `h[\cycle] = h[\pending] ? ~ppHarmDecide.(b)` in `~ppHarmonyFor` evaluates the right-hand call even when a pending cycle exists (SuperCollider evaluates arguments eagerly). Harmless while a decision was pure, but Auto's decision advances its hold counter, history and pick number, so every cycle was decided twice and the hold ran long.
- **Fix:** an explicit `if (h[\pending].notNil) { h[\pending] } { ~ppHarmDecide.(b) }`.
- **Files modified:** supercollider/core/harmony.scd
- **Verification:** `auto rotates progressions` passes (every run 4-8 bars, no repeats within two changes)
- **Committed in:** 873342e

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** The fix was necessary for Auto to hold for the specified length; no scope change.

## Issues Encountered

- The sandbox refused compound shell commands (heredocs, `cd` plus pipelines), so helper scripts were written with the Write tool and commands kept to single plain calls.
- A temporary untracked `.venv` symlink to the main checkout's virtualenv was created so `scripts/check.sh` and pytest could run; it was never staged and was removed before finishing.

## Known Stubs

None.

## Threat Flags

None. The new folder scan is the surface listed as T-06-07/T-06-08 in the plan's threat model and carries its mitigations (name rule before any path, load only through `~ppLibEnsure`, 256-file cap, failed-file memory, one scan at a time).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Ready for Plan 05 (README and the end-of-phase listening check). By-ear items to carry: the real 32-64 bar hold at ride tempo, whether the post window line is enough to see Auto's choice, and the adopt-then-hold planner decision.
- Auto relies on `~ppRenderErrors` counts from the renderer; Phase 8 melodies are unaffected.

## Self-Check: PASSED

- FOUND commits 0b05333, 873342e, 623447b (ancestors of HEAD); a `test(06-04)` commit precedes the `feat(06-04)` commit
- `bash scripts/check.sh` printed `CHECK PASS`; library log holds `CHECK OK` for all six Auto checks, `auto plays classic` and `invalid names ignored`, and `PedalPulse: progression auto seed <n>`
- `python_app/` identical to 3066535; pytest 191 passed

---
*Phase: 06-shared-harmony-progressions*
*Completed: 2026-10-12*
