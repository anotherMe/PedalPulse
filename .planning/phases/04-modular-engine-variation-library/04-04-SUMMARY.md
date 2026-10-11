---
phase: 04-modular-engine-variation-library
plan: 04
subsystem: audio-engine
tags: [supercollider, validation, fault-containment, hot-reload, seeding]

requires:
  - phase: 04-modular-engine-variation-library
    provides: loader, per-bar renderer, select-by-name and the library test harness (plans 01-03)
provides:
  - "supercollider/core/validate.scd: ~ppDrumRoles, ~ppPitchedRoles, ~ppRowsValid, ~ppValidate, ~ppValidateVoices (pure, server-free)"
  - "Loader refuses invalid files and palette defs/voice failures with an ERROR line naming the file; last good copy stays"
  - "Renderer: ~ppSongSeed, ~ppSeedFor, ~ppRenderErrors, per-bar classic fallback, revert to classic after 3 failures"
  - "Fallback and containment tiers in library_test.scd (10 checks) using a temporary library root"
affects: [04-05, 04-06, 05-gui, 08-generative]

actuals:
  tokens: 8000
  tasks: 3
  commits: 3

plan_head_before: 32246fe36f195bd1d5ca1235a997c3372537274d
plan_head_after: 65ce92907e06f427a8e318cb172d7bab8865e7ef

tech-stack:
  added: []
  patterns:
    - "One set of pure validators (validate.scd) used by the loader, the renderer and the tests"
    - "Contract-freeze rule: unknown keys and role names are ignored, so later phases add optional fields without editing committed files"
    - "Per-bar containment: try around init and generator, rows checked, classic generator for that bar, count per (category, stem), revert at 3"
    - "Seed = ((songSeed * 1000003) + (songBar * 7919) + role.hash.abs) & 0x7FFFFFFF, set on thisThread immediately before every init and generator call"
    - "Fixtures only ever live in a temporary library root (Platform.defaultTempDir) that ~ppLibRoot is pointed at after boot"

key-files:
  created:
    - supercollider/core/validate.scd
  modified:
    - supercollider/core/loader.scd
    - supercollider/core/render.scd
    - supercollider/main.scd
    - supercollider/library_test.scd

key-decisions:
  - "A palette's defs function is now optional (a palette may only re-map existing voices); the voice check after s.sync is what refuses a palette naming a voice that does not exist"
  - "A module with no generator for a role (for example classic, which has no lead) uses classic's generator silently; only a throw or an invalid bar counts as a failure"
  - "Reverting to classic never applies to classic itself, so a failing classic file cannot log 'back to classic' every bar"
  - "A throwing init is stored as an init error for that module copy and treated as a failed bar on every bar until the module changes, instead of re-running init each bar"

patterns-established:
  - "Every refusal and fallback line from ~ppLog contains the file's absolute path; the tests assert it"
  - "A failing file logs at most 3 'playing classic for this bar' lines before the revert line"

requirements-completed: [LIB-04, LIB-05, LIB-06]

coverage:
  - id: D1
    description: "A broken or invalid library file never stops the music: syntax error, throw on load, empty, comment-only, not an Event, missing desc, wrong shape, symlink outside the library, palette defs that throw, palette naming a missing voice, a progression with a non-Function, and a missing name are each refused with an ERROR line naming the file; the selection is unchanged and all six sounding layers keep their per-bar counts for 40 bars"
    requirement: LIB-04
    verification:
      - kind: other
        ref: "bash scripts/check.sh --library-only (CHECK OK: broken files refused)"
        status: pass
    human_judgment: false
  - id: D2
    description: "A generator that throws, or returns a bar that fills 3.5 beats, keeps its layer playing the classic part; the third failure returns the category to classic with an ERROR line naming the file"
    requirement: LIB-04
    verification:
      - kind: other
        ref: "bash scripts/check.sh (CHECK OK: generator error falls back, short bar falls back)"
        status: pass
    human_judgment: false
  - id: D3
    description: "A valid file added while the engine runs is selectable by name; a changed file plays from a bar line with no bar mixing old and new rows; a broken edit keeps the last good copy playing; a broken selection racing a valid one never becomes the selection"
    requirement: LIB-05
    verification:
      - kind: other
        ref: "bash scripts/check.sh (CHECK OK: added file selectable, changed file reloads on whole bars, broken edit keeps last good, broken never wins a race)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Every library file is validated by the same pure functions the tests use: rows summing to 4.0 within 1e-6 pass, 3.5 and 4.5 fail, empty, a dur of 0, an amp of 1.5, a string note and a 3-item row fail; unknown keys are ignored"
    requirement: LIB-06
    verification:
      - kind: other
        ref: "bash scripts/check.sh (CHECK OK: rows validation); the committed classic files validate unchanged (parity still 496 rows, 0 mismatches)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Seeds replay bar for bar after a restart, and the plan's bar equals the played bar across a tempo change (research VERIFY flags)"
    requirement: LIB-06
    verification:
      - kind: other
        ref: "bash scripts/check.sh (CHECK OK: seeded generators replay, plan bar is the played bar)"
        status: pass
    human_judgment: false

duration: 50min
completed: 2026-10-11
status: complete
---

# Phase 4 Plan 04: A broken file never stops the music Summary

**Every library file is validated by pure server-free functions, refused with an ERROR naming its path while the last good copy plays on, and a generator that throws or returns a wrong-length bar degrades to the classic part for that bar and reverts to classic after 3 failures**

## Performance

- **Duration:** about 50 min
- **Completed:** 2026-10-11T19:35Z
- **Tasks:** 3
- **Files:** 1 created, 4 modified

## Accomplishments
- `core/validate.scd` (new): `~ppRowsValid` (non-empty Array of `[note, dur, amp, legato]`, finite values, dur and legato above 0, amp 0 to 1, durs summing to 4.0 within 1e-6), `~ppValidate.(cat, module)` (desc is a non-empty String; per-category function checks; palette roles map to Events with a Symbol instrument), `~ppValidateVoices` (each voice is a known SynthDef with `out` and `amp`, plus `freq` and `gate` for pitched roles). Unknown keys and role names are ignored.
- Loader: `~ppLibLoad` validates after the Event check and logs `library file <path> is invalid: <reasons>`; `~ppLibEnsure` runs palette defs inside try (`defs failed`), then validates voices after `s.sync`; any failure leaves `~ppLib` untouched, so the last good copy keeps playing. A successful load resets that file's `~ppRenderErrors` count.
- Renderer: every init and generator call is seeded from (song seed, song bar, role) and run under try; invalid rows or a throw are logged (`... playing classic for this bar`), counted per (category, stem), rendered from classic's generator for that bar, and the third failure returns the category to classic (`failed 3 times -- <cat> back to classic`). The existing Prout-level try stays as the last line of defence.
- Fallback tier (5 checks) and containment tier (5 checks) in `library_test.scd`, all in a temporary library root; `git status --porcelain -- supercollider/library` is empty after a run, and the temporary folders are removed (also on failure and by the watchdog).

## Task Commits

1. **Task 1: validate every file, contain a failing generator per bar** - `0f01eb5` (feat)
2. **Task 2: fallback tier (broken files, add, change, broken edit, race)** - `1c0490e` (test)
3. **Task 3: containment tier (rows, throwing and short generators, seeds, plan bar)** - `65ce929` (test)

**Plan metadata:** committed with this SUMMARY (docs)

## Files Created/Modified
- `supercollider/core/validate.scd` - the pure validators
- `supercollider/core/loader.scd` - validation on load, palette defs/voice checks, render error reset
- `supercollider/core/render.scd` - seeding, `~ppRunGenerator`, `~ppRenderFail`, contained `~ppRenderBar`
- `supercollider/main.scd` - loads `validate.scd` before `loader.scd`
- `supercollider/library_test.scd` - helpers (`expectClassicBars`, `leadDiffs`, `wr`, cleanup) and the ten new checks

## Decisions Made
See key-decisions. No Python file changed (150 Python tests still pass); the three committed classic library files and the golden are untouched.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] A palette without a defs function was refused**
- **Found during:** Task 1 (writing `~ppValidate`: the plan says `defs`, when present, is a Function)
- **Issue:** `~ppLibEnsure` from plan 02 logged `has no defs function` and refused any palette without defs, which would also refuse a palette that only re-maps existing voices and would hide the real reason for the ghost-voice fixture (a missing voice).
- **Fix:** defs is optional in the loader; the voice check after `s.sync` refuses a voice that does not exist.
- **Files modified:** supercollider/core/loader.scd
- **Verification:** "broken files refused" (ghost_voice logs `voice pp_ghost_arp for role arp is not a known SynthDef`), parity unchanged
- **Committed in:** 0f01eb5

**2. [Rule 2 - Missing critical] No revert for the classic file itself, init failures handled**
- **Found during:** Task 1 (render containment)
- **Issue:** the revert rule as written would log `back to classic` every bar if classic itself failed, and a throwing `init` would re-run every bar.
- **Fix:** the revert is skipped for classic; an init error is stored with the module copy and counted as a failed bar until the module changes.
- **Files modified:** supercollider/core/render.scd
- **Committed in:** 0f01eb5

**Total deviations:** 2 auto-fixed (1 bug, 1 missing critical). **Impact:** none on the planned behaviour.

## Issues Encountered
- None failed. Neither known smoke flake (`epic glide up`, `stop releases all`) appeared in the full runs.
- In "broken never wins a race" both Routines finished in order, so `fresh2` was selected and `broken_syntax` was refused (the superseded branch was not exercised). The assertion (never `broken_syntax`; `fresh2` or classic) holds, and the six sounding layers kept their classic counts.
- Not verified here: a generator that loops forever (T-04-09, accepted; Plan 05's static tier runs generators under the watchdog).

## Known Stubs
None.

## Threat Flags
None beyond the plan's register. T-04-08 (load/defs/init/generator containment, last good copy, per-bar fallback, revert after 3) is mitigated and proven by the new checks; T-04-10 (every ERROR line names the path) is asserted by the tests; T-04-11 (log capped at 100, one counter per file) holds.

## Next Phase Readiness
Plan 05 can build the library check's static tier on `~ppValidate`, `~ppValidateVoices` and `~ppRowsValid` as they are. REQUIREMENTS.md was not touched (the orchestrator owns shared files in this wave); LIB-04, LIB-05 and LIB-06 are ready to be marked once the remaining plans declaring them finish.

## Self-Check: PASSED
- Files exist: core/validate.scd, core/loader.scd, core/render.scd, main.scd, library_test.scd
- Commits `0f01eb5`, `1c0490e`, `65ce929` are ancestors of HEAD; `git rev-list --count 32246fe..HEAD` is 3
- `bash scripts/check.sh` prints CHECK PASS (parity 0 mismatches, ten new CHECK OK lines, 67 smoke CHECK OK); `pytest python_app/tests` 150 passed; `git status --porcelain -- supercollider/library` is empty

---
*Phase: 04-modular-engine-variation-library*
*Completed: 2026-10-11*
