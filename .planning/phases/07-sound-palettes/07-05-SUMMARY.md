---
phase: 07-sound-palettes
plan: 05
subsystem: audio-engine
tags: [supercollider, sound-palettes, pluck, warm, air, cpu-check, loudness-meter]

requires:
  - phase: 07-sound-palettes
    plan: 01
    provides: "the palette meter and palette_level.sh, the shipped palettes table, the voice contract"
  - phase: 07-sound-palettes
    plan: 03
    provides: "bassStyle (eighths, sixteenths, octave) and the palette bass styles table"
  - phase: 07-sound-palettes
    plan: 04
    provides: "palette Auto, which rotates through every valid palette on disk"
provides:
  - "pluck, warm and air palettes: six named palettes plus classic ship (PAL-01)"
  - "scripts/palette_cpu.sh and the cpu mode of the palette meter: the rider's one-minute CPU check next to Zwift (D-14, D-15)"
affects: [07-06 exit gate, README and listening UAT]

actuals:
  tokens: 21000
  tasks: 3
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A new palette is tuned with scripts/palette_level.sh <name> before its first commit; per-voice gain constants are the only level control"
    - "The meter has a second mode (PP_METER=cpu) sharing the boot, setup and sampling code of the level mode"

key-files:
  created:
    - supercollider/library/palettes/pluck.scd
    - supercollider/library/palettes/warm.scd
    - supercollider/library/palettes/air.scd
    - scripts/palette_cpu.sh
  modified:
    - supercollider/library_test.scd
    - supercollider/palette_meter.scd

key-decisions:
  - "The CPU command finds the heaviest palette itself with a 2-bars-settle, 2-bars-sampled pass over every palette at VO2, then locks it for 60 s; a name argument measures that palette only (RESEARCH Open Question 3)"
  - "The 'bass is A1 roots and C2 last' check under the classic progression now also allows the octave style's second note (A2, 45); the exact notes were already compared with the style function"
  - "Every palette's own voices are checked disjoint across the shipped palettes table, and the table must list at least 6 rows"

requirements-completed: [PAL-01, PAL-04]

coverage:
  - id: D1
    description: "pluck, warm and air are selectable palettes with their own pp_<name>_ voices (pluck also its own hat and bassStyle octave), each level-matched to classic within 0.75 dB before its first commit, within VO2 headroom, CPU, synth-count and extreme-note limits"
    requirement: PAL-04
    verification:
      - kind: integration
        ref: "scripts/check.sh --library-only #CHECK OK: palette level|headroom|cpu|extreme notes pluck, warm, air; CHECK OK: palette levels"
        status: pass
      - kind: unit
        ref: "scripts/check.sh --library-only #CHECK OK: shipped palettes; LIBCHECK OK: palettes/pluck, warm, air; CHECK OK: voices pluck, warm, air"
        status: pass
    human_judgment: true
    rationale: "That each sounds clearly different from classic, supersaw, acid and dark in the full mix on the rider's real setup is judged by ear; the meter proves level, not character (Plan 06 listening check)"
  - id: D2
    description: "The bass style of each new palette is heard under every progression: pluck pops octaves (root, root + 12, root, last), warm and air play offbeat eighths, all on the bar's chord, under anthem and under the classic progression"
    requirement: PAL-01
    verification:
      - kind: integration
        ref: "scripts/check.sh --library-only #CHECK OK: palette bass styles under anthem, #CHECK OK: palette bass styles under classic"
        status: pass
    human_judgment: false
  - id: D3
    description: "The app's Palette dropdown lists classic, acid, air, dark, pluck, supersaw, warm with no Python change"
    requirement: PAL-01
    verification:
      - kind: unit
        ref: ".venv/bin/python -c scan_library(config.LIBRARY_ROOT / 'palettes') == ['classic', 'acid', 'air', 'dark', 'pluck', 'supersaw', 'warm']; git diff e2dc47e -- python_app is empty"
        status: pass
    human_judgment: false
  - id: D4
    description: "bash scripts/palette_cpu.sh measures every palette briefly at VO2, locks the heaviest one at EPIC 100 and volume 100 for about a minute on its own isolated server and prints mean, max and peak of scsynth's CPU; it passes only when the mean is under 25 percent; one name measures one palette; bad arguments exit 2"
    requirement: PAL-04
    verification:
      - kind: integration
        ref: "bash scripts/palette_cpu.sh (CPU PASS, heaviest palette supersaw, cpu quick line for all 7 palettes); bash scripts/palette_cpu.sh supersaw; bash scripts/palette_cpu.sh a b exits 2; bash scripts/palette_cpu.sh Bad-Name exits 2; bash scripts/palette_cpu.sh nosuch prints PALETTE FAIL: stems"
        status: pass
    human_judgment: true
    rationale: "The headless numbers are the no-Zwift baseline; whether the engine fits next to Zwift on the riding Mac is only answered by the rider running the command with Zwift open (Plan 06 UAT)"

duration: 31min
completed: 2026-10-13
status: complete
commits: 3
plan_head_before: ae9a69ad5bc96d607dc0444c27595dac6fa0ad5e
plan_head_after: b26d1ae772d56fbc7e7025783867129e6f80fd03
---

# Phase 7 Plan 05: The last three sound worlds, and the one command for the CPU check next to Zwift Summary

**pluck (bright plucks, octave-popping bass, tick hat), warm (soft round triangle and sine) and air (glassy FM bells, pure sine bass) join the library, each level-matched to classic within 0.12 dB before its first commit, so six named palettes plus classic ship; `bash scripts/palette_cpu.sh` finds the heaviest palette, holds it at VO2 for a minute and prints scsynth's CPU against the 25 percent budget**

## Performance

- **Duration:** 31 min
- **Started:** 2026-10-13T17:43:49Z
- **Completed:** 2026-10-13T18:15:00Z
- **Tasks:** 3 (3 task commits)
- **Files modified:** 6 (4 created, 2 modified)

## Accomplishments

- **pluck, warm, air** are in the library, each committed exactly once after the meter passed with no `CHECK WARN` (gap at most 0.75 dB). The app's Palette dropdown now lists `Auto`, `classic`, `acid`, `air`, `dark`, `pluck`, `supersaw`, `warm` with no Python change (`python_app/` is identical to e2dc47e).
- **The CPU command.** `scripts/palette_cpu.sh` runs the new `cpu` mode of `supercollider/palette_meter.scd` on the isolated server (port 57142, never the live engine). Run headless here it measured all 7 palettes briefly, picked supersaw as the heaviest, held it for 60 s (86 samples every 0.7 s) and printed `CPU PASS`.
- **Tests.** "shipped palettes" gains the pluck, warm and air rows, must list at least 6 palettes and checks that the palettes' own voices are all different; "palette bass styles" gains the three rows (pluck octave, warm and air eighths) under anthem and under the classic progression, and for pluck every recorded hat row must use `pp_pluck_hat`.

## How the rider selects the new palettes

In the app, open the **Palette** dropdown and pick `pluck`, `warm` or `air` (the list is `Auto`, `classic`, then the other palettes from A to Z: `acid`, `air`, `dark`, `pluck`, `supersaw`, `warm`). The palette takes over at the next bar line without stopping the music and the post window prints its description. Pick `classic` to go back.

Without the app, with the engine running:

```
.venv/bin/python -c "from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/palette', 'pluck')"
.venv/bin/python -c "from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/palette', 'warm')"
.venv/bin/python -c "from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/palette', 'air')"
```

(`'classic'` goes back.)

**pluck, in plain words.** Bright and digital. The arp is a plucked-string sound: each note is a short, bright twang that dies away, nothing like classic's buzzy pulse. The bass is a snappy pulse that "pops" open on every note and jumps up an octave on the second hit of the bar (low, high, low, then the little step to the next chord), so it bounces instead of pulsing. The lead is an FM pluck, a glassy "ping" that loses its brightness fast. The pad is a shimmering buzzy pulse that slowly drifts. The hi-hat is a tiny, very short, very bright tick, much shorter than classic's. Kick and clap stay classic's. Set against classic, the most obvious changes are the bouncing octave bass and the short tick hats.

**warm, in plain words.** Soft, round and old-analog. The bass is a smooth, rounded hum with no buzz (triangle and sine, closed down), still on classic's offbeat pulses. The arp is a mellow, flute-like triangle with no edge; the lead is the same family and its vibrato blooms in after the note starts, like a singer. The pad is a gentle sine-and-triangle cloud with a slow wobble in the pitch. Drums stay classic's. Set against classic, the most obvious change is that everything loses its bite: rounder, quieter in the highs, wobblier on the pad.

**air, in plain words.** Glassy and light. The arp and the lead are FM bells: clean "tink" tones with a ringing, slightly out-of-tune overtone, the arp short and the lead longer and brighter. The pad is made of pure sine waves, each swelling and fading at its own slow rate, so it shimmers without any buzz. The bass is a pure sine: deep, clean and smooth, with no harmonics, played on classic's offbeat pulses. Drums stay classic's. Set against classic, the most obvious changes are the bell-like arp and the buzz-free sine bass.

## Meter numbers (final run of `scripts/check.sh --library-only`, 21 library files)

| Palette | RMS (dBFS, EPIC 50) | Gap to classic | Post-FX peak (EPIC 100, vol 100) | Output peak | CPU mean / peak | Max synths |
|---------|--------------------|----------------|----------------------------------|-------------|-----------------|------------|
| classic | -21.70 | 0.00 (reference) | 0.542 | 0.542 | 4.67 / 7.35 | 19 |
| pluck | -21.71 | -0.01 dB | 0.674 | 0.674 | 6.12 / 9.54 | 20 |
| warm | -21.60 | +0.10 dB | 0.508 | 0.508 | 5.47 / 8.23 | 21 |
| air | -21.63 | +0.07 dB | 0.537 | 0.537 | 5.30 / 8.26 | 26 |

- Earlier palettes in the same run: acid +0.22, dark -0.08, supersaw +0.26 dB.
- Gates met for all three: gap at most 1.5 dB (authoring target 0.75 met, no `CHECK WARN`), post-FX peak at most 0.80, output at most 0.892, CPU far under 25 percent, at most 40 synths, finite and bounded at MIDI -12 and 127. The check printed `CHECK PASS (library only)` with `CHECK OK: library file count (21 files)` and `CHECK OK: palette levels`.
- Trim history (what the meter said before the gains were set). pluck: the first gains (hat 1.3, bass 0.85, arp 2.5, pad 0.55, lead 0.5, set from the per-voice levels of a one-note probe against classic's voices) gave -0.02 dB at once. warm: the first gains (bass 0.3, arp 0.65, pad 0.27, lead 0.32) gave +0.15 dB at once (the untrimmed draft was about 3 to 4 times louder per voice than classic's). air: the first gains (bass 0.42, arp 0.5, pad 0.5, lead 0.55) gave +1.34 dB, a uniform 0.86 gave +0.41, a further 0.95 gave +0.12 (final +0.07 in the full check).
- pluck's post-FX peak at VO2 varied between 0.63 and 0.73 across seven measurements (the noise-burst arp and the bass pop are random in phase); the 0.80 ceiling held every time, with the smallest margin of the shipped palettes.

## CPU baseline, headless, no Zwift (for the rider's comparison)

`bash scripts/palette_cpu.sh` (this M1 Mac, muted, 180 BPM, anthem, EPIC 100, volume 100):

```
PedalPulse meter: cpu quick acid mean=5.7
PedalPulse meter: cpu quick air mean=5.13
PedalPulse meter: cpu quick classic mean=4.67
PedalPulse meter: cpu quick dark mean=6.02
PedalPulse meter: cpu quick pluck mean=6.2
PedalPulse meter: cpu quick supersaw mean=9.13
PedalPulse meter: cpu quick warm mean=5.25
PedalPulse meter: heaviest palette supersaw
PedalPulse meter: cpu supersaw mean=8.68 max=9.89 peak=14.07 samples=86
CPU PASS
```

`bash scripts/palette_cpu.sh supersaw`:

```
PedalPulse meter: cpu supersaw mean=8.62 max=10.29 peak=13.46 samples=86
CPU PASS
```

The heaviest palette is supersaw (mean about 8.6 percent, peak about 14 percent), roughly a third of the 25 percent budget. The rider's own run with Zwift open is Plan 06's UAT step: quit the engine, open Zwift, run `bash scripts/palette_cpu.sh`, report `mean` and `peak`.

## Task Commits

1. **Task 1: pluck.scd, warm.scd and the shipped-palettes and bass-styles rows** - `31ca288` (feat)
2. **Task 2: air.scd, the at-least-6-rows rule and the air rows** - `6a242d3` (feat)
3. **Task 3: the cpu mode of the palette meter and scripts/palette_cpu.sh** - `b26d1ae` (feat)

**Plan metadata:** the commit that adds this SUMMARY (docs: complete plan).

## Files Created/Modified

- `supercollider/library/palettes/pluck.scd` (new) - `pp_pluck_hat`, `pp_pluck_bass`, `pp_pluck_arp`, `pp_pluck_pad`, `pp_pluck_lead`; `bassStyle: \octave`
- `supercollider/library/palettes/warm.scd` (new) - `pp_warm_bass`, `pp_warm_arp`, `pp_warm_pad`, `pp_warm_lead`; no bassStyle key, no drum role
- `supercollider/library/palettes/air.scd` (new) - `pp_air_bass`, `pp_air_arp`, `pp_air_pad`, `pp_air_lead`; no bassStyle key, no drum role
- `supercollider/library_test.scd` - rows for pluck, warm and air in "shipped palettes" (at least 6 rows, own voices disjoint) and in "palette bass styles"; the classic-progression note check allows the octave pop; pluck's hat rows
- `supercollider/palette_meter.scd` - mode `cpu`, header documents both modes
- `scripts/palette_cpu.sh` (new) - the rider's CPU command

## Decisions Made

- Followed the plan's recorded decisions. Two small additions of mine, both inside the files the plan names: the shipped-palettes check also asserts the palettes' own voices are all different (the plan asked for it), and the classic-progression bass check lets the octave style's second note be A2 (45) next to the A1 roots and the C2 last, because the plan's pluck row would otherwise fail a check written when only the eighths and sixteenths styles existed.
- pluck's hat gain 1.3 and arp gain 2.5 are larger than 1 on purpose: a 40 ms tick and a quickly decaying pluck carry little energy next to classic's 120 ms hat and sustained pulse arp, so they need more gain to sit at the same loudness. Their peaks stay inside the headroom gate.

## Deviations from Plan

None - plan executed exactly as written.

Small within-scope notes, not deviations: the plan's "palette bass styles" description covered pluck's octave shape only through the style function comparison; the A1-roots check under classic needed the octave allowance described above. The `commits:` count is measured against the dispatch base `ae9a69a` because the per-plan ledger file could not be written into the worktree's git directory from this sandbox.

## Issues Encountered

- The worktree has no `.venv`; a temporary symlink to the main checkout's `.venv` was used for the runs and removed before the SUMMARY commit. Not part of any commit.
- The sandbox refused shell lines that mix git with other commands, and refused some `bash scripts/palette_cpu.sh` calls that redirected output; commands were issued one at a time and the cpu script was run without redirection. No effect on the repository.
- No orphan test `scsynth` was left; `pgrep -lf scsynth` was empty at the end. The audio device worked on every run (no `AudioDeviceStart` failure).

## Known Stubs

None.

## Threat Flags

None. The new voices pass the same meter gates as the earlier palettes (T-07-14); the CPU script uses the isolated port and checks its argument in the shell and again with `~ppStemValid` (T-07-13); the quick-pass-plus-minute run stays inside the 480 s watchdog (about 4 minutes headless).

## Not covered by a fixture (for the verifier)

- Character: that pluck, warm and air each sound clearly different from classic and from the other palettes at a comparable level is a by-ear judgment (Plan 06 listening check). pluck is the most likely to read as "different" (octave bass, tick hat), warm the most likely to read as "just quieter-sounding classic" and should be judged first.
- Contention with Zwift: the CPU numbers above are headless without Zwift.
- The pad releases of the new palettes (1.2 to 1.4 s) fade under the start of the next chord, as the earlier palettes' do; judged by ear.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 06 can run the exit gate (full `scripts/check.sh`) with 21 library files, write the README sections for the new palettes and the CPU command, and ask the rider for the listening check and the Zwift-side `bash scripts/palette_cpu.sh` run.
- `pluck.scd`, `warm.scd` and `air.scd` are final; a later fix is a new file. Palette Auto already picks them up from disk.

## Self-Check: PASSED

- Created files exist: `supercollider/library/palettes/pluck.scd`, `warm.scd`, `air.scd`, `scripts/palette_cpu.sh`.
- Commits `31ca288`, `6a242d3`, `b26d1ae` are ancestors of HEAD; `git rev-list --count` from `ae9a69a` is 3; pluck.scd, warm.scd and air.scd have exactly one commit each.
- Last `./scripts/check.sh --library-only` printed `CHECK PASS (library only)` with `CHECK OK: library file count (21 files)`, `CHECK OK: palette levels`, `CHECK OK: shipped palettes`, `CHECK OK: palette bass styles under anthem`, `CHECK OK: palette bass styles under classic`, and the four palette-meter lines plus `LIBCHECK OK` and `CHECK OK: voices` for pluck, warm and air.
- `bash scripts/palette_cpu.sh` printed `CPU PASS`; `scan_library` returns classic, acid, air, dark, pluck, supersaw, warm; `python_app/` is unchanged since e2dc47e.

---
*Phase: 07-sound-palettes*
*Completed: 2026-10-13*
