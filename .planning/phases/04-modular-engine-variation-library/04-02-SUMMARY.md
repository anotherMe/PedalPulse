---
phase: 04-modular-engine-variation-library
plan: 02
subsystem: audio-engine
tags: [supercollider, library-loader, per-bar-renderer, pbindef, prout, parity]

requires:
  - phase: 04-modular-engine-variation-library
    provides: golden recording, library_test.scd parity tiers and scripts/check.sh (plan 01)
provides:
  - supercollider/core/loader.scd (registry, ~ppLibLoad, ~ppLibEnsure, ~ppLog)
  - supercollider/core/render.scd (role maps, drum grid, ~ppRenderBar, ~ppBuildLayers)
  - classic entries in library/palettes, library/melodies and library/progressions
  - main.scd without musical content (~ppRoot, ~ppLoadCore, ~ppSel)
affects: [04-03, 04-04, 04-05, 04-06]

actuals:
  tokens: 4800
  tasks: 2
  commits: 2

plan_head_before: 70f7b29a282473c043020446bf3ec74e25a2f3f5
plan_head_after: 4495e9cf031d6119cd70af9d89f84bfc2efd5306

tech-stack:
  added: []
  patterns:
    - "One Event per library file; loader sets name, path, category and rev and ignores any name in the file"
    - "Every layer is one Pbindef with array keys fed by a Prout that renders one bar at each bar start"
    - "Renderer is called inside the captured environment (env.use) because the player thread's environment is not guaranteed to be the interpreter's"
    - "Core modules load at top level before s.waitForBoot; palettes add SynthDefs inside a Routine followed by s.sync"

key-files:
  created:
    - supercollider/core/loader.scd
    - supercollider/core/render.scd
    - supercollider/library/palettes/classic.scd
    - supercollider/library/melodies/classic.scd
    - supercollider/library/progressions/classic.scd
  modified:
    - supercollider/main.scd

key-decisions:
  - "Pbindef accepts an Array key (verified in a scratch sclang run), so the Pdef(name, Pbind(...)) fallback was not needed; Pbindef(name).clear keeps the Pdef registered, so play/stop/isPlaying/quant keep working"
  - "Drum rows drop the note column and carry [instrument, dur, amp, legato] with the grid's timingOffset; pitched rows are [instrument, note, dur, amp, legato] with timingOffset 0"
  - "A render error is caught per bar, logged through ~ppLog and replaced by one silent bar, so a bad library file can never kill a layer's Prout"
  - "Core modules are looked up through the global every bar (via env.use), so re-evaluating render.scd alone takes effect at the next bar"

patterns-established:
  - "Classic library files are final when first committed; each has exactly one commit"
  - "bash scripts/check.sh (or --library-only) is the gate after every engine change"

requirements-completed: [LIB-01, LIB-02]

coverage:
  - id: D1
    description: "Engine emits the shipped groove note for note from the library: 16-bar parity, 0 mismatches against the unchanged golden (496 rows)"
    requirement: LIB-01
    verification:
      - kind: other
        ref: "bash scripts/check.sh (CHECK OK: parity; PedalPulse libtest: parity rows=496 mismatches=0)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Each classic file is registered under its category and file stem; the loader sets name, path, category and rev"
    requirement: LIB-02
    verification:
      - kind: other
        ref: "bash scripts/check.sh (library log shows loading of progressions, melodies and palettes classic.scd; engine ready)"
        status: pass
    human_judgment: false
  - id: D3
    description: "main.scd holds no per-note voice or layer pattern literal; infrastructure SynthDefs (master, epic smoother, fx) remain"
    requirement: LIB-01
    verification:
      - kind: other
        ref: "grep of non-comment lines in supercollider/main.scd: 0 voice SynthDefs, 3 infrastructure SynthDefs, 0 Pbindef(\\pp literals"
        status: pass
    human_judgment: false
  - id: D4
    description: "Existing smoke checks pass unchanged (BPM glide, Start/Stop, EPIC, volume, limiter, re-evaluation): 67 CHECK OK lines"
    requirement: LIB-01
    verification:
      - kind: other
        ref: "bash scripts/check.sh (CHECK PASS; smoke log 67 CHECK OK)"
        status: pass
    human_judgment: false
  - id: D5
    description: "The audible half of 'sounds the same' (timing of server bundles, anything the event recording cannot see)"
    requirement: LIB-01
    verification: []
    human_judgment: true
    rationale: "Event-level parity cannot see OSC bundle timing or the audible mix; Plan 06 end-of-phase listening check covers it"

duration: 40min
completed: 2026-10-11
status: complete
---

# Phase 4 Plan 02: The groove now comes from the library, proven note for note Summary

**Loader plus per-bar Prout renderer play all six shipped layers from classic library files (palette voices, melody arp, progression bass and pad, core drum grid), with 0 mismatches over 496 events against Plan 01's unchanged golden**

## Performance

- **Duration:** about 40 min
- **Tasks:** 2 (tracer + auto)
- **Files:** 5 created, 1 modified

## Accomplishments
- `core/loader.scd`: category list, bounded log (`~ppLog`, last 100 lines), registry `~ppLib`, `~ppLibLoad` (every failure logs one `PedalPulse ERROR: library file <path> ...` line and returns nil) and `~ppLibEnsure` (reloads from disk every call, runs palette `defs` then `s.sync`, bumps `\rev`, single registry put).
- `core/render.scd`: role maps, core-owned drum grid reproducing the shipped effective amps (kick/hat/bass keep the default 0.1), `~ppResolveStem` (classic on nil, `\auto` or unknown stem), `~ppRenderBar` with per-module state reset on `[stem, rev]` change and classic/rest fallbacks, `~ppBuildLayers`.
- `main.scd`: `~ppRoot` captured at top level, `~ppLoadCore`, `~ppSel` defaulting to classic, registry rebuild and classic ensure for every category before the first `s.sync`, one `~ppBuildLayers.()` call replacing all six pattern literals; the six per-note SynthDefs now live in the palette file.
- `bash scripts/check.sh`: guard self-test, guard, golden self-check, parity (rows=496 mismatches=0) and the 67-check smoke suite all pass; 150 Python tests still pass.

## Task Commits

1. **Task 1 (tracer): arp from the library through loader and renderer** - `f86ee0f` (feat)
2. **Task 2: bass, pad and drums from the library, main.scd without musical content** - `4495e9c` (feat)

**Plan metadata:** committed with this SUMMARY (docs)

## Files Created/Modified
- `supercollider/core/loader.scd` - library registry and loader
- `supercollider/core/render.scd` - per-bar renderer, role maps, drum grid, layer builder
- `supercollider/library/palettes/classic.scd` - six shipped voices plus role map (lead on the arp voice)
- `supercollider/library/melodies/classic.scd` - shipped arp, no lead
- `supercollider/library/progressions/classic.scd` - shipped bass and pad
- `supercollider/main.scd` - engine core only (clock, ramp stepper, buses, FX, master, transport, OSC)

## Decisions Made
See key-decisions. Golden, `library_test.scd`, `smoke_test.scd` and `scripts/` are untouched; the golden and each classic file have exactly one commit.

## Deviations from Plan

None - plan executed exactly as written. (Small robustness additions inside the planned design: a per-bar try around the renderer with a silent-bar fallback, and `env.use` around renderer calls, both within the planned `~ppBuildLayers`.)

## Issues Encountered
- One of six smoke runs failed `stop releases all: instrument group still has 1 children 2.6 s after stop` (the first full `check.sh` run of Task 2, immediately after a library-only run). Re-running the full `check.sh` and `smoke_test.sh` three more times passed each time with 67 checks. Treated as the known timing flake (like wave 1's `epic glide up` flake) rather than a regression, but it is in a different check than the one noted in plan 01, so a later plan seeing it again should look at whether stop-time notes can outlive the second gate broadcast.

## Known Stubs
None. The lead layer is intentionally absent under classic (D-05); Plan 03 adds it.

## Threat Flags
None. T-04-01 is mitigated: paths are built from the fixed category list and the stem `classic` at boot, loads run in `try`, every failure logs an ERROR naming the file, and a failing classic file stops the boot with an Error.

## Next Phase Readiness
Plan 03 can add OSC selection (`/pp/progression`, `/pp/melody`, `/pp/palette`) on top of `~ppSel`, `~ppLibEnsure` and the per-bar selection read, and the lead layer via `~ppLayerRole`/`~ppRoleCategory`.

## Self-Check: PASSED

---
*Phase: 04-modular-engine-variation-library*
*Completed: 2026-10-11*
