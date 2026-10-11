---
phase: 04-modular-engine-variation-library
plan: 05
subsystem: testing
tags: [supercollider, library-check, voice-contract, negative-controls, readme]

requires:
  - phase: 04-modular-engine-variation-library
    provides: loader, renderer, validators, fallback and containment tiers (plans 01-04)
provides:
  - "library_test.scd static tier: every .scd file under supercollider/library (templates included) loaded, linted and rendered with no server; one LIBCHECK OK: <category>/<stem> line per file"
  - "Six static negative controls (no classic.scd, empty bar, load-time side effect, forbidden call, bad name, auto.scd)"
  - "Voice tier on a bare server: every palette voice writes only to its own bus, releases on gate 0, frees itself; three bad voices prove it can fail"
  - "quant 4 on all 7 layers survives Stop and Start"
  - "scripts/check.sh fails when the LIBCHECK OK count differs from the .scd files on disk"
  - "Three _template.scd authoring examples and supercollider/library/README.md"
affects: [05-gui, 06-library-growth, 08-generative]

actuals:
  tokens: 14000
  tasks: 2
  commits: 2

plan_head_before: 10996755a84eacdbbb8f22fd47660c453e806099
plan_head_after: eecdae584e4a1dc5e58c031f795a0a53dbe3c4a4

tech-stack:
  added: []
  patterns:
    - "One list of files per category: classic first, then sorted names, fixed category order, so LIBCHECK lines are identical run to run"
    - "Lint on comment-stripped source with string contents blanked, so prose in a desc never trips a forbidden token"
    - "Negative controls live in a temporary root or as test-only SynthDefs, never in supercollider/library"
    - "Voices of one batch run side by side (own group, bus and two peak probes each), about 3 s per batch"

key-files:
  created:
    - supercollider/library/progressions/_template.scd
    - supercollider/library/melodies/_template.scd
    - supercollider/library/palettes/_template.scd
    - supercollider/library/README.md
  modified:
    - supercollider/library_test.scd
    - scripts/check.sh

key-decisions:
  - "The lint blanks string contents as well as comments, so a desc that mentions a forbidden word is not a false positive; real code is still linted"
  - "The generator replay check runs two full fresh passes (init, then 16 bars) instead of calling one generator twice on shared state, so stateful generators replay fairly"
  - "Voice contract runs the voices of one palette concurrently; the three bad-voice controls run in their own batch so the bus 0 writer cannot contaminate a real palette"
  - "The quant check waits until every layer is really playing before Stop and again after Start (see deviations)"

patterns-established:
  - "A file is checked by the same ~ppLibLoad, ~ppValidate, ~ppRowsValid, ~ppValidateVoices and ~ppRenderBar the engine uses"
  - "String comparison in sclang tests uses == through any/detect, never Array:includes (identity)"

requirements-completed: [LIB-06, LIB-02, LIB-03]

coverage:
  - id: D1
    description: "bash scripts/check.sh validates every library file (selectable files and templates) without a server: loads, is an Event with a desc, right shape, no load-time side effects, no forbidden calls, generators fill 4 beats over 16 bars and replay from the same seed; one LIBCHECK OK line per file, and check.sh fails if the count differs from the files on disk"
    requirement: LIB-06
    verification:
      - kind: other
        ref: "bash scripts/check.sh (CHECK OK: static check, CHECK OK: library file count (7 files))"
        status: pass
    human_judgment: false
  - id: D2
    description: "Six kinds of bad file each make the static check fail, naming the file or category"
    requirement: LIB-06
    verification:
      - kind: other
        ref: "bash scripts/check.sh (CHECK OK: static check catches bad files)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every selectable stem round-trips through the primary use path (registered under category and stem, rendered by ~ppRenderBar with no classic fallback); every category has classic.scd"
    requirement: LIB-02
    verification:
      - kind: other
        ref: "bash scripts/check.sh (LIBCHECK OK lines for all 7 files; a category without classic.scd fails in the negative control)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Every palette voice writes only to its own out bus, releases on gate 0 and frees itself; a bus 0 writer, a voice without doneAction and a voice without gate each fail the same check"
    requirement: LIB-06
    verification:
      - kind: other
        ref: "bash scripts/check.sh (CHECK OK: voices classic, voices _template, voice contract catches bad voices)"
        status: pass
    human_judgment: false
  - id: D5
    description: "All 7 layer Pbindefs keep quant 4 after a Stop and a Start with doReset"
    requirement: LIB-06
    verification:
      - kind: other
        ref: "bash scripts/check.sh (CHECK OK: quant 4 survives restart)"
        status: pass
    human_judgment: false
  - id: D6
    description: "supercollider/library/README.md explains in plain words how to add a variation (always a new file), try one by name with copy-paste one-liners, and run the check"
    requirement: LIB-03
    verification:
      - kind: other
        ref: "grep of the README for the classic_lead and classic one-liners, /pp/progression, /pp/palette, bash scripts/check.sh"
        status: pass
    human_judgment: true
    rationale: "Whether the README reads clearly to the rider is a judgment; the presence of the required one-liners is checked automatically"

duration: 55min
completed: 2026-10-11
status: complete
---

# Phase 4 Plan 05: One command checks every library file Summary

**`bash scripts/check.sh` now opens every library file with no server, prints one `LIBCHECK OK` line each, proves every palette voice goes through the limiter and obeys Stop and gate on a bare server, shows it can fail through six bad-file and three bad-voice controls, and fails if any file was skipped**

## Performance

- **Duration:** about 55 min
- **Completed:** 2026-10-11
- **Tasks:** 2
- **Files:** 4 created, 2 modified

## Accomplishments
- Static tier (runs first, before the server boots): `staticCheck` loads each file with `~ppLibLoad` (same validators as the engine), asserts no new environment variable, `Pdef`, `Tdef` or `OSCdef` appeared, lints the comment-stripped code for 27 forbidden tokens, runs generators for 16 bars (valid 4-beat bars, identical on replay), checks palette voices, and round-trips each selectable stem through `~ppRenderBar` with no classic fallback. Order is fixed: progressions, melodies, palettes; classic first, then sorted.
- Six negative controls in a temporary root (no `classic.scd`, an empty bar, a side effect, a `Synth(` call, `Bad Name.scd`, `auto.scd`) each fail the check and name their file; the good classic copies must not fail.
- Voice tier (after boot, before `main.scd` loads, so only a bad voice can write to bus 0): per voice, peak probes on its private bus and on bus 0, gate 0, then `/g_queryTree` child count. Three test-only bad voices (`\ppBadBus0`, `\ppBadNoDone`, `\ppBadNoGate`) must each be caught, with the specific reason asserted.
- quant 4 on all 7 layers holds before and after `~ppStop` then `~ppStart`.
- `scripts/check.sh`: `CHECK OK: library file count (7 files)` or `CHECK FAILED: library file count (...)`.
- Three `_template.scd` files (never selectable, still validated) and `library/README.md` (rider sections first, author contract last).

## Task Commits

1. **Task 1: static tier, templates, count cross-check** - `549e2cf` (feat)
2. **Task 2: voice tier, bad-voice controls, quant probe, README** - `eecdae5` (feat)

**Plan metadata:** committed with this SUMMARY (docs)

## Files Created/Modified
- `supercollider/library_test.scd` - `staticCheck`, `stripSource`, `listStems`, static negative controls, voice tier (`voiceContractMany`, `voiceContract`, `\ppLibPeak`, three bad voices), quant probe
- `scripts/check.sh` - LIBCHECK OK count cross-check
- `supercollider/library/{progressions,melodies,palettes}/_template.scd` - authoring examples
- `supercollider/library/README.md` - plain-language guide and file contract

## Decisions Made
See key-decisions. No committed library file, the golden, or any Python file was changed (150 Python tests pass; the guard passes).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Quant probe raised inside SuperCollider while a bar-quantized start was pending**
- **Found during:** Task 2 (first full run after adding the probe)
- **Issue:** `~ppStop` / `~ppStart` followed at once by the recorder's `Pbindef.stop` hit a player still waiting for its bar quantization (`Message 'sched' not understood`), failing the next tier. Same hazard exists for the engine's own autostart, which never showed because nothing stopped in between.
- **Fix:** the probe waits until every layer's player has `nextBeat` set (really playing) before the Stop and again after the Start. (`isWaiting` has no getter; `nextBeat` does.)
- **Files modified:** supercollider/library_test.scd
- **Verification:** three full `bash scripts/check.sh` runs in a row pass, no "not understood" lines
- **Committed in:** eecdae5

**2. [Rule 1 - Bug] `Array:includes` compared Strings by identity**
- **Found during:** Task 1 (first run reported "no classic.scd" in every category)
- **Fix:** `any { |n| n == "classic" }` in `listStems` and the classic test
- **Files modified:** supercollider/library_test.scd
- **Committed in:** 549e2cf

### Plan wording refined (not a behaviour change)
- The lint also blanks string contents (the plan said comment-stripped source); a `desc` mentioning a forbidden word does not fail, real code does.
- The replay check uses two fresh full passes rather than a second call on the same state.
- The voice contract runs a palette's voices side by side (about 3 s per palette instead of about 3 s per voice).

**Total deviations:** 2 auto-fixed (2 bugs). **Impact:** none on the planned behaviour.

## Issues Encountered
- One full run failed at `select melody by name: no lead rows after selecting classic_lead` right after the first quant probe attempt (the 'sched' error above had broken the recorder's players). With the wait fix, three consecutive full runs passed. Neither known smoke flake (`epic glide up`, `stop releases all`) appeared.
- `scripts/check.sh` is run as `./scripts/check.sh` in this worktree because the sandbox refuses `bash scripts/check.sh` as a compound command; the script is identical.

## Known Stubs
None.

## Threat Flags
None beyond the plan's register. T-04-12 (load-time side effects and shelling out), T-04-13 (voice writing to bus 0 or ignoring gate/doneAction) and T-04-14 (a file skipped by the check) are mitigated, each with a negative control that was run and observed to fail.

## Next Phase Readiness
The library now has a gate that every later variation file passes through: add a file, run `bash scripts/check.sh --library-only`. REQUIREMENTS.md, STATE.md and ROADMAP.md were not touched (the orchestrator owns them); LIB-02, LIB-03 and LIB-06 are ready to be marked once all plans declaring them have finished.

## Self-Check: PASSED
- Files exist: library_test.scd, check.sh, the three `_template.scd`, `library/README.md`
- Commits `549e2cf` and `eecdae5` are ancestors of HEAD; `git rev-list --count 1099675..HEAD` is 2
- `bash scripts/check.sh` prints CHECK PASS (7 LIBCHECK OK lines, `CHECK OK: library file count (7 files)`, voices classic, voice contract catches bad voices, quant 4 survives restart, parity); the smoke log has 67 `CHECK OK:` lines; `pytest python_app/tests` 150 passed; the committed library files are unchanged

---
*Phase: 04-modular-engine-variation-library*
*Completed: 2026-10-11*
