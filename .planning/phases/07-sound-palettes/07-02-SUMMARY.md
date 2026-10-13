---
phase: 07-sound-palettes
plan: 02
subsystem: audio-engine
tags: [supercollider, validation, hardening, synthdef, palettes]

requires:
  - phase: 04-variation-library
    provides: "~ppRowsValid, ~ppValidate, ~ppLibEnsure palette branch, library check (WR-01 and WR-02 came from its review)"
  - phase: 07-sound-palettes
    plan: 01
    provides: "per-bar palette state, the palette meter, supersaw (the first palette that owns pp_<name>_ voices)"
provides:
  - "row bounds in ~ppRowsValid: at most 64 rows, dur at least 1/32, legato at most 8, notes -12 to 127, chords of at most 8 notes"
  - "~ppClassicVoices and the pp_<name>_ namespace rule in ~ppValidate (optional stem argument)"
  - "~ppPaletteDefs: the only place palette defs run; snapshot diff of SynthDescLib, refusal reasons, undo that removes added voices and restores replaced ones"
affects: [07-04 palette Auto prefetch, 07-03 and 07-05 new palettes]

actuals:
  tokens: 12000
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns:
    - "Palette defs run only through ~ppPaletteDefs (engine loader, static tier, voice tier): one definition of valid"
    - "A refusal undoes before s.sync: added voices are SynthDef.removeAt'd, replaced voices are restored by re-running their owner's defs, proven by comparing compiled SynthDef bytes"

key-files:
  created: []
  modified:
    - supercollider/core/validate.scd
    - supercollider/core/loader.scd
    - supercollider/library_test.scd

key-decisions:
  - "Legato cap 8, not the reviewer's 4: the core default pad on an 8-bar chord has legato 7.2"
  - "A role may use one of classic's six voices without the prefix, so palettes/_template.scd and the bad_defs fixture stay statically valid"
  - "Replaced names are owned by the longest matching registered palette prefix, so stems a and a_b (both start pp_a_) cannot overwrite each other's voices"
  - "Restore happens at refusal time in the guard's undo; a replaced name that no library file owns is logged as an ERROR telling the rider to re-evaluate main.scd"

requirements-completed: [PAL-04]

coverage:
  - id: D1
    description: "A bar with more than 64 rows, a dur under 1/32 beat, a legato above 8, a note outside -12 to 127 or a chord of more than 8 notes is refused like any invalid bar; everything that ships (including the default pad on an 8-bar chord) stays valid"
    requirement: PAL-04
    verification:
      - kind: unit
        ref: "scripts/check.sh --library-only #CHECK OK: rows validation"
        status: pass
      - kind: unit
        ref: "scripts/check.sh --library-only #CHECK OK: shipped rows within bounds"
        status: pass
      - kind: integration
        ref: "scripts/check.sh --library-only #CHECK OK: parity, static check, chord follow deep"
        status: pass
    human_judgment: false
  - id: D2
    description: "A palette can only own voices under its own pp_<name>_ prefix (or use classic's six); a palette that adds or replaces a SynthDef outside its prefix is refused"
    requirement: PAL-04
    verification:
      - kind: unit
        ref: "scripts/check.sh --library-only #CHECK OK: static check catches bad files (foreign_role)"
        status: pass
      - kind: integration
        ref: "scripts/check.sh --library-only #CHECK OK: palette defs stay in their prefix"
        status: pass
    human_judgment: false
  - id: D3
    description: "A refused palette leaves nothing behind: added voices removed, replaced voices (classic's ppArp, or a loaded palette's last good voices) restored, palette selection unchanged"
    requirement: PAL-04
    verification:
      - kind: integration
        ref: "scripts/check.sh --library-only #CHECK OK: refused palette leaves no voices"
        status: pass
      - kind: integration
        ref: "scripts/check.sh --library-only #CHECK OK: refused reload restores the last good voices"
        status: pass
    human_judgment: false

duration: 27min
completed: 2026-10-13
status: complete
commits: 4
plan_head_before: 834c3b9135bf79febf40a36a1e0326c22b8552c4
plan_head_after: 41b94a247816a68e4a24136413e985a782e36429
---

# Phase 7 Plan 02: A broken or careless file can never damage the engine or another palette's sound Summary

**Row bounds (64 rows, dur at least 1/32, legato at most 8, notes -12 to 127, chords of 8) in the shared validator, plus a palette defs guard that enforces the pp_<name>_ voice namespace and, on any refusal, removes the voices a file added and restores the ones it replaced**

## Performance

- **Duration:** 27 min
- **Started:** 2026-10-13T13:04:00Z
- **Completed:** 2026-10-13T13:31:00Z
- **Tasks:** 2 (4 task commits: two RED, two GREEN)
- **Files modified:** 3 (no library file changed)

## Accomplishments

- **WR-01.** `~ppRowsValid` refuses a bar of more than 64 rows before it looks at a single row (so 400000 rows cost no loop), a dur under 1/32 beat, a legato above 8, a note outside -12 to 127 and a chord of more than 8 notes or with a note outside the range. All earlier reasons keep their wording. The core's default pad and bass, for chords of 1 to 8 bars, are proven valid by the new server-free check "shipped rows within bounds".
- **WR-02, the rule.** `~ppValidate` takes the file's stem; a palette other than classic whose role uses a voice that neither starts with `pp_<stem>_` nor is one of `~ppClassicVoices` (`ppKick ppHat ppClap ppBass ppArp ppPad`) is refused when it loads.
- **WR-02, the guard.** `~ppPaletteDefs` is now the only place palette defs run. It copies `SynthDescLib.global.synthDescs`, runs the defs under `try`, and lists every voice name that is new or whose SynthDesc object changed. A name outside the file's own prefix (or outside classic's six, for classic) refuses the file. The returned `undo` removes the added names with `SynthDef.removeAt` (which also frees them on the server) and re-runs the owner's defs for each replaced name.
- **The engine and the check share it.** `~ppLibEnsure` runs defs only through the guard and undoes before `s.sync`; the library check's static tier (classic preload and per-palette step) and voice tier call the same function.
- Plain words for the rider: nothing about the sound changes today. What changes is that a future palette file, yours or an AI-written one, can no longer replace classic's arp by accident or leave half-built voices around when it fails. If it tries, the post window says so and the music keeps playing the palette it was on.

## Task Commits

1. **Task 1 RED: failing bounds cases** - `036c343` (test)
2. **Task 1 GREEN: row bounds in ~ppRowsValid** - `3735a2f` (feat)
3. **Task 2 RED: foreign-role static fixture and the three fallback checks** - `9142c8a` (test)
4. **Task 2 GREEN: namespace rule, ~ppPaletteDefs guard, undo** - `41b94a2` (feat)

**Plan metadata:** the commit that adds this SUMMARY (docs: complete plan).

## Files Created/Modified

- `supercollider/core/validate.scd` - `~ppRowsValid` bounds and comment, `~ppClassicVoices`, `~ppValidate.(cat, module, stem)` namespace rule
- `supercollider/core/loader.scd` - `~ppPaletteDefs`, `~ppLibLoad` passes the stem, `~ppLibEnsure` palette branch through the guard
- `supercollider/library_test.scd` - bounds cases, "shipped rows within bounds", `foreign_role` static fixture, "palette defs stay in their prefix", "refused palette leaves no voices", "refused reload restores the last good voices", guard calls in the static and voice tiers

## Decisions Made

- Legato cap 8 as the plan decided (not the review's 4).
- Ownership of a replaced name uses the longest matching `pp_<x>_` prefix among registered palettes and the stem itself, so a palette `a` cannot overwrite the voices of a registered palette `a_b`. (Small extension of the plan's prefix rule, see Deviations.)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] Stems that share a prefix (a and a_b)**
- **Found during:** Task 2 (designing the guard)
- **Issue:** A plain `beginsWith("pp_a_")` test lets palette `a` define `pp_a_b_arp`, which is also the namespace of a palette `a_b`; the guard would call it allowed and the "two palettes never share a voice" truth would not hold.
- **Fix:** A replaced name is allowed only when the longest registered `pp_<x>_` prefix (or the stem itself) matching it is the stem; the undo uses the same owner lookup to choose whose defs to re-run.
- **Files modified:** supercollider/core/loader.scd
- **Verification:** the shipped checks stay green; the a and a_b case itself is not exercised by a fixture (documented below).
- **Committed in:** 41b94a2

---

**Total deviations:** 1 auto-fixed (1 missing critical). **Impact on plan:** a few lines in the guard; no scope creep, no change to any shipped file.

## TDD Gate Compliance

- **RED 1** `036c343`: `./scripts/check.sh --library-only` exit 1, `LIBRARY FAIL: ERROR: rows validation: 65 rows of 4/65 should fail but passed`. `gsd_run check tdd-red-evidence` has no adapter for SuperCollider's line protocol (and `workflow.tdd_mode` is off), so this is the semantic assessment: the target check ran and failed on the planned assertion (65 rows still accepted). The server-free "shipped rows within bounds" already passed (as expected, it must keep passing).
- **GREEN 1** `3735a2f`: same command exit 0, `CHECK OK: rows validation`, `CHECK OK: shipped rows within bounds`, `CHECK PASS (library only)`.
- **RED 2** `9142c8a`: exit 1, `LIBRARY FAIL: ERROR: static check catches bad files: no failure for a palette using another palette's voice (looked for "does not start with pp_foreign_role_")`. The three fallback checks come after that point in the run, so they were not exercised in the RED run; they were proven afterwards by a mutation run (below).
- **GREEN 2** `41b94a2`: exit 0, all new `CHECK OK` lines, `CHECK PASS (library only)`.
- **Mutation proof (not committed):** with the guard's `undo` replaced by a no-op, the run failed on `LIBRARY FAIL: ERROR: palette defs stay in their prefix: pp_clobber_arp was left behind by the refused palette`; reverted, the run passes.
- **REFACTOR:** none.

## Issues Encountered

- The worktree has no `.venv`; a temporary symlink to the main checkout's `.venv` was used for the runs and removed before the final commit. Not part of any commit.
- The sandbox refused compound shell lines that mix git with other commands; commands were issued one at a time. No effect on the repository.

## Known Stubs

None.

## Threat Flags

None. The guard narrows existing surface (palette defs into SynthDescLib and scsynth); it adds no endpoint, auth path or file access.

## Not covered by a fixture (for the verifier)

- Two registered palettes whose stems share a prefix (a and a_b) are handled in the guard but have no fixture; the shipped palettes (classic, supersaw) do not collide.
- A replaced voice owned by no library file (an engine voice from main.scd) is only logged as an ERROR; there is no automatic restore by design (the plan says to re-evaluate main.scd).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 04 (Auto) can load every palette file on disk through `~ppLibEnsure` without a file being able to damage classic or another palette.
- The prefix rule is already in the palette template's contract; no palette file needs to change.

## Self-Check: PASSED

- Modified files exist: `supercollider/core/validate.scd`, `supercollider/core/loader.scd`, `supercollider/library_test.scd`.
- Commits `036c343`, `3735a2f`, `9142c8a`, `41b94a2` are ancestors of HEAD; `git rev-list --count` from the plan start is 4.
- Last `./scripts/check.sh --library-only` printed `CHECK PASS (library only)` with every named `CHECK OK` line and `CHECK OK: palette levels`; the library guard found no changed committed library file.

---
*Phase: 07-sound-palettes*
*Completed: 2026-10-13*
