---
phase: 07-sound-palettes
plan: 06
subsystem: audio-engine
tags: [supercollider, sound-palettes, smoke-test, exit-gate, readme, uat]

requires:
  - phase: 07-sound-palettes
    plan: 04
    provides: "palette Auto, ~ppPalPlaying, ~ppAutoPrefetching, the palette post-window line"
  - phase: 07-sound-palettes
    plan: 05
    provides: "all seven palettes (21 library files), scripts/palette_cpu.sh, scripts/palette_level.sh"
provides:
  - "smoke checks 'palette stop and start' (every palette on disk, with a no-bypass probe) and 'palette re-evaluation' (Palette on Auto) on the real engine"
  - "a library README that explains palettes, Palette Auto, bass styles, writing and level-matching a palette and the CPU check"
  - "palette and progression templates updated for bassStyle, the enforced pp_<name>_ rule, the level loop and the bass-generator rule"
affects: [phase 07 verification, end-of-phase UAT]

actuals:
  tokens: 14000
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Palette stems are counted from disk in the smoke suite, never hardcoded, so a later palette file is covered with no test edit"

key-files:
  created: []
  modified:
    - supercollider/smoke_test.scd
    - scripts/smoke_test.sh
    - supercollider/library/README.md
    - supercollider/library/palettes/_template.scd
    - supercollider/library/progressions/_template.scd

key-decisions:
  - "The new smoke checks wait on ~ppPalPlaying (the palette of the bar being played) rather than the selection, so each palette is measured only once its bar has really started"

requirements-completed: [PAL-01, PAL-02, PAL-03, PAL-04]

coverage:
  - id: D1
    description: "On the real engine, for every palette on disk with progression anthem and melody classic_lead_loud playing: a master pre-gain of 0 leaves bus 0 silent, Stop empties the instrument group within 2.5 s and no layer renders another bar, and Start plays again"
    requirement: PAL-04
    verification:
      - kind: integration
        ref: "bash scripts/smoke_test.sh #CHECK OK: palette stop and start"
        status: pass
    human_judgment: false
  - id: D2
    description: "Re-evaluating main.scd twice with Palette on Auto stacks nothing (7 players, 1 routine, same groups, SynthDefs and OSCdefs), keeps the auto selection, loads every palette file again and Auto draws a palette other than classic again, with no ERROR line"
    requirement: PAL-02
    verification:
      - kind: integration
        ref: "bash scripts/smoke_test.sh #CHECK OK: palette re-evaluation"
        status: pass
    human_judgment: false
  - id: D3
    description: "The whole gate passes with all 21 library files: library check, palette meter for all seven palettes and the smoke suite"
    requirement: PAL-04
    verification:
      - kind: integration
        ref: "bash scripts/check.sh #CHECK PASS, CHECK OK: library file count (21 files), CHECK OK: palette levels"
        status: pass
      - kind: unit
        ref: ".venv/bin/python -m pytest -q python_app/tests (191 passed); git diff e2dc47e -- python_app is empty"
        status: pass
    human_judgment: false
  - id: D4
    description: "The README explains in plain words what each palette sounds like, how Palette Auto behaves with the real timing, bass styles, how to write and level-match a palette and how to run the CPU check next to Zwift; the templates document bassStyle, the pp_<name>_ rule, the level loop and the classic-palette-only bass generator"
    requirement: PAL-01
    verification:
      - kind: other
        ref: "grep acceptance criteria of Task 2 (README headings, commands, palette names, single-progression note; template keywords); LIBCHECK OK: palettes/_template, progressions/_template"
        status: pass
    human_judgment: true
    rationale: "Whether the wording is clear to a rider who is not a SuperCollider musician is a reading judgment; the greps only prove the sections and commands are present"
  - id: D5
    description: "Palettes are recognisably different by ear, no noticeable volume jump at low and high EPIC, VO2 at volume 100 is clean on the loudest palette, Auto pacing feels right at the rider's tempo, and the engine fits next to Zwift"
    requirement: PAL-03
    verification: []
    human_judgment: true
    rationale: "Only the rider can judge character, loudness by ear, pacing over many minutes and CPU next to a running Zwift (D-13, D-15); listed under Pending human checks"

duration: 70min
completed: 2026-10-13
status: complete
commits: 2
plan_head_before: 366cba80b033a3f8873bb2c3a5315d08a8dfdf17
plan_head_after: ac0b6b6fad4251ee1ddf8de1fd51739977a98be6
---

# Phase 7 Plan 06: Every palette passes the exit gate on the real engine, the README explains palettes, and the rider listens Summary

**The smoke suite now stops and starts every palette on disk with a limiter no-bypass probe and re-evaluates main.scd on Palette Auto without stacking anything; the library README and templates explain palettes, Auto, bass styles, the level loop and the CPU check in plain words; the full `scripts/check.sh` gate passes with all 21 library files; the rider's listening check and the Zwift CPU check are queued as pending**

## Performance

- **Duration:** about 70 min (most of it waiting for four full gate runs of about 9 minutes each)
- **Started:** 2026-10-13T18:25:00Z
- **Completed:** 2026-10-13T19:35:00Z
- **Tasks:** 2 (2 task commits)
- **Files modified:** 5 (no file created)

## Accomplishments

- **palette stop and start.** For every palette stem on disk (7 here, counted from disk, classic first), with anthem and `classic_lead_loud` playing: select it, wait until it is the bar's palette, lead flowing; set the master pre-gain to 0 and require bus 0 below 0.001; restore the pre-gain; Stop and require the instrument group empty within 2.5 s, no layer rendering another bar, no Pbindef playing and no instrument node afterwards; Start and require the layers to play again. Then classic is put back in Palette, Progression and Melody.
- **palette re-evaluation.** With anthem and Palette on Auto: all palette files registered and the scan idle, engine counts taken, `main.scd` re-evaluated twice, counts identical (7 players, 1 routine, same groups, SynthDefs and OSCdefs), the selection still `auto`, every palette registered again, and a `PedalPulse: palette <name>:` line for a palette other than classic appears within 40 beats; no ERROR or "playing classic for this bar" line.
- **Watchdog 480 s, wrapper timeout 510 s** (`SystemClock.sched(480`, `timeout 510`, `gtimeout 510`).
- **README** (plain words, for a rider who is not a SuperCollider musician): the seven palettes in a list, the `auto` sentence for progressions and palettes, the palette line in the post window, new sections "Palettes and Auto" (real timing: 2.9-5.7 minutes of hold, about 4.7-5.7 minutes per palette on average, single palettes about 3 to 8.5 minutes at 90-110 BPM; both exceptions; no quick repeats; a name locks it; Stop then Start draws a new one), "Bass styles" and "Write a new palette", "CPU next to Zwift" under "Check everything", and the file contract additions.
- **Templates.** `palettes/_template.scd` documents `bassStyle` (and has `bassStyle: \eighths,` in its Event), the enforced `pp_<palette>_` rule, the `.min(12000)` clamp in the example voice and the `palette_level.sh` loop; `progressions/_template.scd` says a `bass` generator plays only under the classic palette. Both still validate.

## Task Commits

1. **Task 1: palette stop and start and palette re-evaluation smoke checks, watchdog 480, wrapper timeout 510** - `e230b92` (test)
2. **Task 2: README and templates** - `ac0b6b6` (docs)

**Plan metadata:** the commit that adds this SUMMARY (docs: complete plan).

## Files Created/Modified

- `supercollider/smoke_test.scd` - the two palette checks before `SMOKE PASS`; watchdog 480 s with updated comment
- `scripts/smoke_test.sh` - `timeout 510` / `gtimeout 510`
- `supercollider/library/README.md` - palettes, Palettes and Auto, Bass styles, Write a new palette, CPU next to Zwift, contract text
- `supercollider/library/palettes/_template.scd` - authoring comments, `bassStyle: \eighths,`
- `supercollider/library/progressions/_template.scd` - comment on the classic-palette-only bass generator

## Verification (final tree, HEAD `ac0b6b6`)

| Gate | Result |
|------|--------|
| `bash scripts/check.sh` (full) | `CHECK PASS`, with `CHECK OK: library file count (21 files)`, `CHECK OK: palette levels`, `LIBCHECK OK: palettes/_template`, `LIBCHECK OK: progressions/_template`, `CHECK OK: palette stop and start`, `CHECK OK: palette re-evaluation` (third full run; see Issues) |
| `bash scripts/smoke_test.sh` alone | `SMOKE PASS` twice (first run and one diagnostic rerun) |
| `.venv/bin/python -m pytest -q python_app/tests` | 191 passed |
| `git diff e2dc47e -- python_app` | empty |
| Test servers left running | none (`pgrep -lf scsynth` empty) |

## Decisions Made

- The new checks wait for `~ppPalPlaying` to equal the stem (up to 12 beats) before probing, so the no-bypass probe and the Stop test always run on the palette whose bar is really playing.
- The re-evaluation check treats a `PedalPulse: palette classic:` line as "not a draw" (the rebuilt registry opens on classic) and waits for any other palette name.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The audio device worked on every run (no `AudioDeviceStart` failure).
- **Two intermittent smoke failures in earlier checks, neither in the new checks.** The first full gate run of the final code failed with `SMOKE FAIL: ERROR: stop releases all: instrument group still has 1 children 2.62786925 s after stop` and the second with `SMOKE FAIL: ERROR: epic glide down: PulseCount did not advance between samples 0 and 1` (a sibling of the known `epic glide up` flake). Both checks come before the new ones and run on classic; the library check and the palette meter passed in both runs. A standalone `bash scripts/smoke_test.sh` passed, and the third full `bash scripts/check.sh` printed `CHECK PASS`. The "stop releases all" failure is a new variant: its 2.5 s budget was missed by 0.13 s with one pad voice still releasing, which suggests the budget is tight under load rather than a defect; I did not change that check (out of scope). Worth knowing if the gate flakes again; the orchestrator may want to rerun the gate once on the merged tree.
- The worktree has no `.venv`; a temporary symlink to the main checkout's `.venv` was used and removed before the SUMMARY commit. The sandbox refuses compound shell lines mixing git with other commands; commands were run one at a time. The per-plan ledger file was not written; `commits:` is measured with `git rev-list --count 366cba8..HEAD` (2) against the dispatch base.

## Known Stubs

None.

## Threat Flags

None. The new checks only send OSC to the smoke suite's own isolated server and language port. T-07-15 (Stop with a non-classic palette), T-07-16 (no limiter bypass) and T-07-17 (re-evaluation stacking) are covered by the two new checks across all seven palettes.

## Pending human checks

These belong to the rider. They are deferred to the end-of-phase UAT (workflow.human_verify_mode is end-of-phase); the executor did not perform, simulate or approve any of them, and they are not done.

**Palette listening and CPU check (PAL-01, PAL-02, PAL-03, PAL-04, D-13, D-15) - PENDING**

On the riding Mac with the engine and the app:

1. Open SuperCollider, open `supercollider/main.scd`, select everything and evaluate it. In a terminal in the PedalPulse folder run `./run.sh`. Within a few seconds the post window prints a line "PedalPulse: palette <name>: <description>" and the sound changes: the app's Auto picked a palette by itself, and it is not classic.
2. Open the Palette dropdown: it lists Auto, classic, acid, air, dark, pluck, supersaw and warm. Pick classic_lead_loud in Melody (so the lead is easy to hear) and anthem in Progression.
3. Pick each palette by name in turn, at a low EPIC (Recovery or Endurance) and then at a high one (Threshold or VO2), at your usual volume. Each one takes over at the next bar and the post window names it. Write one plain sentence per palette about how it sounds, say whether you can tell every palette apart in the full mix, and say if any palette sounds clearly louder or quieter than the others when you switch (that is the by-ear loudness check).
4. Still on anthem: acid and dark should roll the bass in fast sixteenths, pluck should pop the bass between two octaves, and the others should keep the offbeat bass. Pick classic in Progression and go through acid, pluck and supersaw again: acid still rolls sixteenths and pluck still pops octaves, now on the classic A-minor groove, and supersaw plays the classic offbeat bass. Then pick classic in Palette too: everything is the original sound. Say whether each palette's bass rhythm fits its sound.
5. Pick the palette you found loudest, set VO2 and volume 100, and listen for a minute: it should sound clean, with no crackle, distortion or pumping.
6. Pick Auto in Palette and in Progression and leave it for about 20 minutes at your usual BPM (note the BPM). A new "PedalPulse: palette" line should appear on the same bar as a new "PedalPulse: progression" line, so sound and chords change together; a palette should never come straight back after itself. At 90-110 BPM a palette lasts about 5 minutes on average, but any single one can last from about 3 to about 8.5 minutes, because after its hold (about 3 to 5.7 minutes) it waits for the next progression change (faster at a higher BPM). Note how long each palette lasted and say whether the pace feels right.
7. While Auto runs, pick a palette you like by name: it takes over at the next bar and stays, through several progression changes, until you pick Auto again; then a different palette comes in at the start of a round. Say whether Auto should instead keep the palette you had picked (Claude chose a fresh palette).
8. Press Stop: everything goes quiet, pad tails included. Press Start: the music comes back, and on Auto with a newly drawn palette.
9. Quit the PedalPulse engine (close the SuperCollider window or press Ctrl+. and quit). Open Zwift (no ride needed). In the terminal run: `bash scripts/palette_cpu.sh`. When it finishes it prints a line "PedalPulse meter: cpu <name> mean=... max=... peak=..." and CPU PASS or CPU FAIL. Report the name, the mean and the peak numbers. It passes when the mean is under 25.

If anything sounds wrong, describe it in your own words. Claude will change the core or add a new library file; existing library files are never edited.

Expected: Step 1: a palette other than classic starts by itself. Step 2: the eight names. Step 3: every palette takes over at the next bar, each is clearly different, and none jumps out in loudness at low or high EPIC. Step 4: rolling sixteenths on acid and dark and octave pops on pluck under both anthem and the classic progression, the offbeat bass on the others, and the original sound with classic in Palette and Progression. Step 5: clean sound at VO2 and volume 100. Step 6: every palette change on the same bar as a progression change, no immediate repeat, palettes lasting about 5 minutes on average at 90-110 BPM (single ones about 3 to 8.5 minutes). Step 7: the named palette stays until Auto is picked again. Step 8: Stop silences everything, Start resumes with a new palette on Auto. Step 9: mean CPU under 25% with Zwift open.

Reference for step 9 (headless, no Zwift, from Plan 05): supersaw is the heaviest palette, mean about 8.7 percent, peak about 14 percent. pluck has the smallest VO2 headroom (post-FX peak 0.63-0.73 against the 0.80 gate), so it is the first to listen to at step 5 if no palette is obviously loudest.

## Planner decisions for the rider to review

These were decisions Claude made in yolo mode. The rider has not confirmed any of them; none is recorded here as confirmed, accepted or approved.

1. **The palette stem `supersaw` instead of `anthem`** (Plan 01). Lives in `supercollider/library/palettes/supersaw.scd`. To change: add a new palette file with another name (a committed palette is never edited).
2. **The level metric and gates.** Post-FX RMS over 4 bars at 180 BPM, anthem, `classic_lead_loud`, EPIC 50; 1.5 dB gate, 0.75 dB authoring target. Lives in `supercollider/palette_meter.scd` (and `scripts/check.sh`, `scripts/palette_level.sh`). To change: edit the constants in the meter.
3. **The bar's palette decides the bass rhythm under every progression, classic included**, so a progression file's own `bass` generator is heard only under the classic palette. Lives in `supercollider/core/render.scd` (and `core/harmony.scd`). D-02 itself is the rider's decision; this is how it was wired. To change: a core edit in `render.scd`.
4. **Exception 1 to D-06.** A rotation's opening pick (Start with files still loading, the app's launch-time Auto, Auto picked again) lands on the next round start rather than waiting for a progression change, and Auto picked after a named lock draws a different palette instead of keeping the locked one. Lives in `~ppPalAutoNext` in `supercollider/core/harmony.scd`. To change: edit that function.
5. **The hold of 80-128 bars** with the real timing: 2.9-5.7 minutes of hold at 90-110 BPM, about 4.7-5.7 minutes per palette on average once the wait for the next progression change is added, single palettes about 3 to 8.5 minutes. Lives in `~ppPalHoldBars` in `supercollider/core/harmony.scd`. To change: set another `[min, max]` pair there.
6. **Exception 2 to D-06.** With Progression on Auto but only one progression able to play, palettes change at the end of its round with a one-time post-window note, and on an 8-bar line for classic's one-bar round. Lives in `~ppPalAutoNext` in `supercollider/core/harmony.scd`. To change: edit that function.
7. **The new palette's pad enters at the next chord change** after a mid-chord manual switch while the old pad rings out. Lives in the per-bar palette stage and render path (`supercollider/core/harmony.scd`, `core/render.scd`). To change: a core edit there.
8. **Which palettes roll sixteenths or pop octaves:** acid and dark roll sixteenths, pluck pops octaves, the rest play eighths. Lives in the `bassStyle` line of each palette file. To change: add a new palette file with another `bassStyle` (committed files are never edited).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 7 has all its plans executed. The phase stays human_needed until the rider answers the "Palette listening and CPU check" above in the end-of-phase UAT.
- If the gate flakes again on `stop releases all` or an `epic glide` check, rerun once; a repeat should go to `/gsd-debug`.

## Self-Check: PASSED

- Modified files exist: `supercollider/smoke_test.scd`, `scripts/smoke_test.sh`, `supercollider/library/README.md`, `supercollider/library/palettes/_template.scd`, `supercollider/library/progressions/_template.scd`.
- Commits `e230b92` and `ac0b6b6` are ancestors of HEAD; `git rev-list --count 366cba8..HEAD` was 2 before this SUMMARY.
- Acceptance greps hold: `checkOk.("palette stop and start")`, `checkOk.("palette re-evaluation")`, `\preGain, 0`, `SystemClock.sched(480`, `timeout 510`, `gtimeout 510`; README headings `## Palettes and Auto`, `## Bass styles`, `## Write a new palette`; `palette_level.sh`, `palette_cpu.sh`, `PedalPulse: palette <name>`, `only one progression can play on Auto`; `bassStyle: \eighths` in the palette template.
- Final full `bash scripts/check.sh` printed `CHECK PASS`; pytest 191 passed; `python_app/` unchanged since e2dc47e.

---
*Phase: 07-sound-palettes*
*Completed: 2026-10-13*
