---
phase: 07-sound-palettes
plan: 01
subsystem: audio-engine
tags: [supercollider, sound-palettes, harmony-memo, loudness-meter, supersaw, osc]

# Dependency graph
requires:
  - phase: 04-variation-library
    provides: "palette category, ~ppSelect loader, voice contract, library guard, check.sh"
  - phase: 06-shared-harmony
    provides: "memoized per-bar harmony entry that the layers pull"
provides:
  - "per-bar palette state shared by all seven layers (entry[\\palette], ~ppHarmPaletteFor, ~ppHarmPaletteLog, ~ppPalPlaying)"
  - "post-window line 'PedalPulse: palette <name>: <desc>' on every palette change"
  - "headless palette meter (supercollider/palette_meter.scd, scripts/palette_level.sh) gating loudness, headroom, CPU, nodes and extreme notes"
  - "the supersaw palette (pp_supersaw_bass, _arp, _pad, _lead), level-matched before its first commit"
affects: [07-02 palette hardening, 07-03 bass styles and more palettes, 07-04 palette Auto, 07-05 CPU check and more palettes, 07-06 exit gate and README]

# Actuals (#2632)
actuals:
  tokens: 10000
  tasks: 2
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Palette is per-bar state in the memoized harmony entry; every layer, drums included, reads entry[\\palette]; the per-layer render-time lookup is only a fallback for entries without one"
    - "A palette is measured (RMS gap to classic, VO2 headroom, CPU, extreme notes) by an isolated-server meter before its first commit, because a committed library file is final"

key-files:
  created:
    - supercollider/palette_meter.scd
    - scripts/palette_level.sh
    - supercollider/library/palettes/supersaw.scd
  modified:
    - supercollider/core/harmony.scd
    - supercollider/core/render.scd
    - supercollider/library_test.scd
    - scripts/check.sh

key-decisions:
  - "Stem supersaw instead of D-01's working name anthem (anthem is already a progression)"
  - "Level metric: post-FX RMS over 4 bar-aligned bars after 2 settling bars, 180 BPM, progression anthem, melody classic_lead_loud, EPIC 50; gate 1.5 dB, authoring target 0.75 dB"
  - "The meter is its own isolated-server script (port 57142) run by check.sh --library-only, not a tier inside library_test.scd, so the library check's watchdog is untouched"
  - "A pad held across a next-bar switch keeps ringing to its own release; the new palette's pad enters at the next chord change (no core change, no gap, no double attack)"

patterns-established:
  - "Tune a new palette with scripts/palette_level.sh <name> (about a minute) and commit it only when the gap is at most 0.75 dB"
  - "Fixture palettes for core tests live in the temporary library root (palettes/probe_pal.scd), never in supercollider/library"

requirements-completed: [PAL-01, PAL-03, PAL-04]

coverage:
  - id: D1
    description: "A palette picked by name takes over all seven layers (drums included) on the same next bar and goes back the same way; the post window names each change once; the classic golden is untouched"
    requirement: PAL-03
    verification:
      - kind: integration
        ref: "scripts/check.sh --library-only (supercollider/library_test.scd) #named palette plays from the next bar"
        status: pass
      - kind: integration
        ref: "scripts/check.sh --library-only (supercollider/library_test.scd) #parity"
        status: pass
    human_judgment: false
  - id: D2
    description: "The library-only gate measures every palette against classic (level within 1.5 dB, post-FX peak and output ceiling at VO2, CPU, node count, NaN and peak at MIDI -12 and 127) and a single palette can be measured in about a minute"
    requirement: PAL-04
    verification:
      - kind: integration
        ref: "scripts/check.sh --library-only #CHECK OK: palette levels"
        status: pass
      - kind: integration
        ref: "scripts/palette_level.sh supersaw #PALETTE PASS"
        status: pass
    human_judgment: false
  - id: D3
    description: "supersaw is a selectable palette with its own bass, arp, pad and lead voices, level-matched to classic (gap 0.34 dB at EPIC 50) and within headroom and CPU limits"
    requirement: PAL-01
    verification:
      - kind: integration
        ref: "scripts/palette_level.sh supersaw #CHECK OK: palette level|headroom|cpu|extreme notes supersaw"
        status: pass
      - kind: unit
        ref: "supercollider/library_test.scd #shipped palettes, #voices supersaw, LIBCHECK OK: palettes/supersaw"
        status: pass
    human_judgment: true
    rationale: "Whether supersaw sounds clearly different from classic yet equally loud in the full mix on the rider's real setup is judged by ear; the meter proves level, not character (Plan 06 listening check)"

# Metrics
duration: 31min
completed: 2026-10-13
status: complete
commits: 3
plan_head_before: 4e6e823b8b5486fe4131c618a4d31b0b815e36c5
plan_head_after: b8450e5d576d53db96f1237012f852fd1ec10354
---

# Phase 7 Plan 01: Pick a palette and the whole band changes sound together; supersaw is the first one Summary

**One palette per bar, decided in the harmony memo so all seven layers (drums too) switch on the same bar line, announced in the post window, plus a headless palette meter in the library-only gate and the first new palette, supersaw, level-matched to classic within 0.34 dB before its first commit**

## Performance

- **Duration:** 31 min
- **Started:** 2026-10-13T12:28:00Z
- **Completed:** 2026-10-13T12:59:00Z
- **Tasks:** 2 (3 task commits: one RED, two GREEN)
- **Files modified:** 7 (3 created, 4 modified)

## Accomplishments

- **Palette is per-bar state.** `~ppHarmonyFor` now stamps `entry[\palette]` once per (run, song bar) via `~ppHarmPaletteFor`; `~ppRenderBar` pulls the entry for every role (the three drum layers used not to) and takes the voice from it. A fixture palette that replaces all seven voices switches on one bar line (bar 5 to 7 after a send at bar 4.5) and back (bar 11 to 13), the music never stops, and the parity check against the golden still finds 0 mismatches with classic everywhere.
- **The post window names every change** once: `PedalPulse: palette <name>: <desc>`. The app stays send-only.
- **The palette meter** (`supercollider/palette_meter.scd`, `scripts/palette_level.sh`) boots its own muted server on port 57142 and, per palette, checks level against classic, headroom at EPIC 100 and volume 100, CPU, node count, and finite output at MIDI -12 and 127. `scripts/check.sh --library-only` now runs it over every palette on disk (`CHECK OK: palette levels`). One palette plus the classic reference takes about 62 s.
- **supersaw** ships as a palette with its own bass (three detuned saws plus a sub-octave sine), arp (five saws, wide), pad (seven saws, slow opening, 3.2 kHz low-pass) and lead (five saws with a little vibrato; not the arp voice). Drums stay classic's.

## How the rider selects supersaw

In the app, open the **Palette** dropdown and pick `supersaw` (the dropdown lists `Auto`, `classic`, then every other palette file from A to Z by file name, so `supersaw` appears by itself). It takes over at the next bar line without stopping the music, and the post window prints `PedalPulse: palette supersaw: Supersaw: huge detuned-saw pad and lead, bright saw arp, saw bass with a sub, classic drums`. To go back, pick `classic`.

Without the app, with the engine running, the exact one-liner this project uses:

```
.venv/bin/python -c "from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/palette', 'supersaw')"
```

Use `'classic'` in place of `'supersaw'` to go back. Palette `Auto` still plays classic in this plan; the rotation arrives in Plan 04.

In plain words, supersaw is the "big trance" version of the same band: the pad is a wide, thick wall of detuned saws instead of classic's thin pad, the arp and the lead are brighter, fatter saw sounds (the lead now has its own voice with a slight wobble instead of reusing the arp), and the bass has an extra deep sub underneath. It is trimmed to sit at about the same loudness as classic.

## Meter numbers (final run of `scripts/check.sh --library-only`)

| Palette | RMS (dBFS, EPIC 50) | Gap to classic | Post-FX peak (EPIC 100, vol 100) | Output peak | CPU mean / peak | Max synths |
|---------|--------------------|----------------|----------------------------------|-------------|-----------------|------------|
| classic | -21.74 | 0.00 (reference) | 0.539 | 0.539 | 4.66 / 8.16 | 20 |
| supersaw | -21.40 | +0.34 dB | 0.577 | 0.577 | 8.64 / 12.73 | 21 |

- Gates met: gap at most 1.5 dB (authoring target 0.75 met, no `CHECK WARN`), post-FX peak at most 0.80, output at most 0.892 and above 0.1, CPU well under 25 (it stays below the 12 percent advice line on average), at most 40 synths, no NaN or inf and no peak of 4 or more at MIDI -12 and 127.
- Before the level trim (every voice gain 1.0) supersaw measured +1.15 dB; all four voices were then scaled by one constant (0.875, about -1.16 dB). Run-to-run noise of the meter is about 0.05 dB for classic and up to about 0.3 dB for supersaw.
- Extra spot checks (throwaway copies of the meter at another EPIC, not committed): gap -0.10 dB at EPIC 20 and +0.28 dB at EPIC 80, so the match holds across zones (RESEARCH Pitfall 2).

## Task Commits

1. **Task 1 (tracer), RED: failing check "named palette plays from the next bar"** - `fa6740d` (test)
2. **Task 1 (tracer), GREEN: palette decided once per bar, all seven layers read it, post-window line** - `7a5a3d0` (feat)
3. **Task 2: palette meter, palette_level.sh, check.sh wiring, "shipped palettes" check, supersaw.scd** - `b8450e5` (feat)

**Plan metadata:** the commit that adds this SUMMARY (docs: complete plan).

## Files Created/Modified

- `supercollider/core/harmony.scd` - palette stage: `~ppHarmPaletteFor`, `entry[\palette]`, run-state `lastPalette`/`palLog`, `~ppHarmPaletteLog`, `~ppPalPlaying`, the `PedalPulse: palette <name>: <desc>` line
- `supercollider/core/render.scd` - `~ppInstrumentFor` takes a palette stem; `~ppRenderBar` pulls the entry first for every role
- `supercollider/library_test.scd` - check "named palette plays from the next bar" (fixture `palettes/probe_pal.scd` in the temporary root) and the server-free "shipped palettes" check
- `supercollider/palette_meter.scd` (new) - isolated-server meter, port 57142, env `PP_METER` / `PP_METER_STEMS`
- `scripts/palette_level.sh` (new) - one command to measure all palettes or the ones named; log `${TMPDIR:-/tmp}/pedalpulse-palette.log`
- `scripts/check.sh` - runs the meter after the library file count; usage comment updated
- `supercollider/library/palettes/supersaw.scd` (new) - the supersaw palette, committed once

## Decisions Made

Followed the plan's recorded decisions (stem `supersaw`, level metric and gates, meter as its own script, held pad across a switch). Nothing new beyond them.

## Deviations from Plan

None - plan executed exactly as written.

Small within-scope additions, not deviations from any requirement: the meter stops the layers (`~ppStop`) and waits 0.6 s before quitting the server (otherwise the server logs `Group 1000 not found` noise after `PALETTE PASS`), and it also prints the CPU and headroom lines for classic as the reference (the plan's verify requires `palette headroom classic`).

**Total deviations:** 0 auto-fixed. **Impact on plan:** none.

## TDD Gate Compliance

- **RED** `fa6740d` (`test(07-01)`), before the implementation. Command: `./scripts/check.sh --library-only`, exit 1, the library log ended with `LIBRARY FAIL: ERROR: named palette plays from the next bar: ~ppHarmPaletteLog does not exist`. `gsd_run check tdd-red-evidence` has no adapter for SuperCollider's line protocol (and `workflow.tdd_mode` is off), so this is the semantic assessment: the target check ran (`CHECK OK: broken never wins a race` immediately before it), reached the new palette-log assertion and failed there for the intended reason (the per-bar palette stage did not exist). Honest note: the instrument-per-row assertions that come first in the check already passed against the old engine, because the old per-layer lookup happens to agree on the switch bar in a quiet run; the new guarantee (one decision per bar in the memo, the palette log, the named post-window line) is what the RED run failed on.
- **GREEN** `7a5a3d0` (`feat(07-01)`): the same command passed (`CHECK OK: named palette plays from the next bar`, `CHECK OK: parity`, `CHECK PASS (library only)`).
- **REFACTOR:** none needed.

## Issues Encountered

- The worktree has no `.venv` (gitignored) and `scripts/check.sh` requires `.venv/bin/python`; a temporary symlink to the main checkout's `.venv` was used for the runs and removed before returning. Not part of any commit.
- The sandbox refused to run `bash scripts/palette_level.sh` as a command prefix inside compound shell lines; scripts were run directly (`./scripts/palette_level.sh`). No effect on the repository.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 02 can add the palette `defs` guard and the WR-01 bounds on top of `~ppLibEnsure`; the meter picks up every palette file automatically.
- Plan 04 replaces only the `\auto` branch of `~ppHarmPaletteFor` and reads `~ppPalPlaying` / the `progChanged` argument already passed in.
- Plans 03 and 05 add rows to the "shipped palettes" table and new palette files; each is tuned with `scripts/palette_level.sh <name>` before its first commit.
- `supersaw.scd` is final; a later level or sound fix is a new file.

## Self-Check: PASSED

- Created files exist: `supercollider/palette_meter.scd`, `scripts/palette_level.sh`, `supercollider/library/palettes/supersaw.scd`.
- Commits `fa6740d`, `7a5a3d0`, `b8450e5` are ancestors of HEAD; `supersaw.scd` has exactly one commit.
- `./scripts/check.sh --library-only` printed `CHECK PASS (library only)` with `CHECK OK: palette levels` and `CHECK OK: library file count (16 files)`.

---
*Phase: 07-sound-palettes*
*Completed: 2026-10-13*
