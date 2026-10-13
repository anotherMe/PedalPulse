---
phase: 07-sound-palettes
plan: 03
subsystem: audio-engine
tags: [supercollider, sound-palettes, bass-styles, acid, dark, loudness-meter]

requires:
  - phase: 07-sound-palettes
    plan: 01
    provides: "per-bar palette state, the palette meter and palette_level.sh, supersaw, the shipped palettes table"
  - phase: 07-sound-palettes
    plan: 02
    provides: "row bounds and the pp_<name>_ voice-namespace guard every new palette must pass"
  - phase: 06-shared-harmony
    provides: "the chord rules for the bass (chord tones, root first, pickup or third last)"
provides:
  - "the optional palette key bassStyle (eighths, sixteenths, octave) with validator, core style table and renderer hook"
  - "the bar's palette decides the bass rhythm under every progression, the classic progression included; the classic palette keeps v1"
  - "the acid palette (squelchy 303-style bass rolling in sixteenths) and the dark palette (deep long kick, gritty rolling bass)"
affects: [07-04 palette Auto, 07-05 CPU check and more palettes (pluck uses octave), 07-06 exit gate and README]

actuals:
  tokens: 14000
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns:
    - "A palette sets its bass rhythm with a data key (bassStyle); the rhythm functions live in the core (~ppBassStyles) so the chord and pickup rules exist once (~ppBassLast)"
    - "The renderer lets the bar's palette override the progression's bass generator; only the classic palette plays a progression's own bass"

key-files:
  created:
    - supercollider/library/palettes/acid.scd
    - supercollider/library/palettes/dark.scd
  modified:
    - supercollider/core/validate.scd
    - supercollider/core/harmony.scd
    - supercollider/core/render.scd
    - supercollider/library_test.scd

key-decisions:
  - "Bass style is a core table chosen by a palette key, so library files stay data-only (D-02)"
  - "A non-classic palette plays its bassStyle under every progression, the classic progression included (RESEARCH Open Question 4, resolved after plan check); the classic palette keeps the progression's own bass, so the golden is untouched"
  - "sixteenths plays the root on all 12 notes and the pickup or third on the last; octave alternates root and root plus 12 on the offbeat eighths"
  - "dark's gain trim is uneven by design (kick 0.47, bass 0.58, arp/pad/lead 0.70): the long deep kick and the gritty bass carried most of the +3.8 dB, so they were cut harder; the match is on the full mix"

requirements-completed: [PAL-01, PAL-04]

coverage:
  - id: D1
    description: "A palette file can set bassStyle to eighths, sixteenths or octave; a missing key means eighths; a typo or a String refuses the file with the list of valid styles"
    requirement: PAL-01
    verification:
      - kind: unit
        ref: "scripts/check.sh --library-only #CHECK OK: static check catches bad files (bad_style.scd, string_style.scd)"
        status: pass
      - kind: unit
        ref: "scripts/check.sh --library-only #CHECK OK: bass styles follow the chord"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every bass style stays on the bar's chord: root first, pickup toward the next chord (or the third) last; eighths is the core default and equals v1's rows on classic's A minor"
    requirement: PAL-01
    verification:
      - kind: unit
        ref: "scripts/check.sh --library-only #CHECK OK: bass styles follow the chord, #CHECK OK: harmony units"
        status: pass
    human_judgment: false
  - id: D3
    description: "The bar's palette decides the bass rhythm under every progression: classic palette keeps v1 (golden untouched), every other palette plays its style, also under the classic progression"
    requirement: PAL-01
    verification:
      - kind: integration
        ref: "scripts/check.sh --library-only #CHECK OK: parity, #LIBCHECK OK: palettes/* (round trip under the classic progression)"
        status: pass
      - kind: integration
        ref: "scripts/check.sh --library-only #CHECK OK: palette bass styles under anthem, #CHECK OK: palette bass styles under classic"
        status: pass
    human_judgment: false
  - id: D4
    description: "acid and dark are selectable palettes with their own voices (dark also its own kick), each level-matched to classic (gap 0.75 dB or less), within VO2 headroom, CPU and extreme-note limits, committed once"
    requirement: PAL-04
    verification:
      - kind: integration
        ref: "scripts/check.sh --library-only #CHECK OK: palette level|headroom|cpu|extreme notes acid and dark, #CHECK OK: palette levels"
        status: pass
      - kind: unit
        ref: "scripts/check.sh --library-only #CHECK OK: shipped palettes, #LIBCHECK OK: palettes/acid, palettes/dark, #CHECK OK: voices acid, voices dark"
        status: pass
    human_judgment: true
    rationale: "That acid and dark sound clearly different from classic and supersaw in the full mix on the rider's real setup is judged by ear; the meter proves level, not character (Plan 06 listening check)"

duration: 25min
completed: 2026-10-13
status: complete
commits: 3
plan_head_before: c090b9a096942cabb1d8c7bb2bd1ad06b645e235
plan_head_after: 85c55e90c949c4a62c0b1106f71a9d48ff1086cf
---

# Phase 7 Plan 03: A palette also sets how the bass moves, and acid and dark join the library Summary

**The optional palette key bassStyle (eighths, sixteenths, octave) is validated, implemented once in the core on the chord and pickup rules and played by the bar's palette under every progression, and the two palettes that need it ship: acid (squelchy 303-style rolling bass) and dark (deep long kick, gritty rolling bass), both level-matched to classic within 0.21 dB before their first commit**

## Performance

- **Duration:** 25 min
- **Started:** 2026-10-13T13:33:00Z
- **Completed:** 2026-10-13T13:58:00Z
- **Tasks:** 2 (3 task commits: one RED, two GREEN)
- **Files modified:** 6 (2 created, 4 modified)

## Accomplishments

- **bassStyle.** A palette file may name its bass rhythm. `~ppBassStyleNames` (validate.scd) lists the three styles; a typo or a String such as `"sixteenths"` refuses the file with `bassStyle is not one of: eighths, octave, sixteenths`. `~ppBassStyles` (harmony.scd) holds one function per style, all ending on the shared `~ppBassLast` rule (the pickup toward the next chord when it changes, the chord's third otherwise), so they cannot drift apart. `eighths` is `~ppDefaultBass` itself.
- **The palette decides the bass.** `~ppRenderBar` plays `~ppBassStyleFor.(palStem)` for the bass whenever the bar's palette is not classic, under every progression. That includes the classic progression every Start opens on: acid and dark roll sixteenths from the first bar, and supersaw keeps v1's offbeat eighths because eighths on classic's A minor is exactly v1's rows. The classic palette keeps the old path (the progression's own bass), so classic in every category still matches the golden (parity: 0 mismatches).
- **acid and dark.** Both pass the meter (see below), the voice tier and the namespace guard, and each was committed exactly once.
- **Tests.** Server-free "bass styles follow the chord" (every style x the 17-row pickup table x every chord with no change, plus the exact row shapes), two static negative fixtures, a palette round trip under the classic progression for every selectable palette, "shipped palettes" rows, and the real-time "palette bass styles" check under anthem and under classic (own bass voice, 4 or 12 notes a bar, notes, onsets, durs, legatos and amps equal the style function for each bar's entry).

## How the rider selects the new palettes

In the app, open the **Palette** dropdown and pick `acid` or `dark` (the dropdown lists `Auto`, `classic`, then the other palettes from A to Z: `acid`, `dark`, `supersaw`). The palette takes over at the next bar line without stopping the music and the post window prints its description. Pick `classic` to go back.

Without the app, with the engine running:

```
.venv/bin/python -c "from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/palette', 'acid')"
.venv/bin/python -c "from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/palette', 'dark')"
```

(`'classic'` goes back.) Note that `/pp/palette` with `auto` still plays classic until Plan 04.

**acid, in plain words.** The bass is the squelchy, snarling "303" sound: every note snaps open and closes again, and it rolls in fast sixteenth notes (three per beat, a tiny gap before each beat) instead of classic's slow offbeat pulses. It stays on the chord and ends each bar with the little step toward the next chord. The arp is brighter and more nasal, with a resonant "wow" on each note; the lead is a sharp, biting acid sweep; the pad is thin and reedy, without the thick low end. Drums stay classic's. Set against classic, the most obvious change is the rolling, squelching bass.

**dark, in plain words.** The kick is deeper and longer, with a short click on the hit, so the beat feels heavier and slower. The bass is gritty and muffled (distorted, then closed down), also rolling in sixteenths. The arp is narrow and nasal like a small speaker, the pad is murky and dull, and the lead is a hollow, buzzy folded tone. Hats and clap stay classic's. Set against classic, the most obvious changes are the big boomy kick and the dark, rolling bass.

## Meter numbers (final run of `scripts/check.sh --library-only`)

| Palette | RMS (dBFS, EPIC 50) | Gap to classic | Post-FX peak (EPIC 100, vol 100) | Output peak | CPU mean / peak | Max synths |
|---------|--------------------|----------------|----------------------------------|-------------|-----------------|------------|
| classic | -21.71 | 0.00 (reference) | 0.554 | 0.554 | 5.14 / 8.23 | 19 |
| supersaw | -21.44 | +0.26 dB | 0.557 | 0.557 | 9.05 / 13.27 | 22 |
| acid | -21.50 | +0.21 dB | 0.586 | 0.586 | 5.93 / 9.11 | 20 |
| dark | -21.79 | -0.09 dB | 0.501 | 0.501 | 5.77 / 9.00 | 21 |

- Gates met for both: gap at most 1.5 dB (authoring target 0.75 met, no `CHECK WARN`), post-FX peak at most 0.80, output at most 0.892, CPU far under 25 percent, at most 40 synths, finite and bounded at MIDI -12 and 127.
- Trim history (what the meter said before the gains were set). acid: all four voices at gain 1.0 measured +1.07 dB, then one gain of 0.88 on all voices gave +0.20. dark: all gains 1.0 measured +3.78 dB; kick 0.6, bass 0.75, others 0.9 gave +2.07; the final gains kick 0.47, bass 0.58, arp, pad and lead 0.70 gave -0.06 (final run -0.09). The sixteenth roll is what makes both palettes hotter than the draft numbers in RESEARCH (which were measured with eighths).
- Library check (without the meter) takes 2:49 against the 300 s watchdog, so about 130 s of margin remain for Plans 04 and 05.

## Task Commits

1. **Task 1 RED: failing checks for bass styles, the two bad-style fixtures and the classic round trip** - `ad48dae` (test)
2. **Task 1 GREEN: bassStyle validator, style table and renderer hook** - `677f316` (feat)
3. **Task 2: acid.scd, dark.scd, shipped-palettes rows and the "palette bass styles" check** - `85c55e9` (feat)

**Plan metadata:** the commit that adds this SUMMARY (docs: complete plan).

## Files Created/Modified

- `supercollider/core/validate.scd` - `~ppBassStyleNames`, the `bassStyle` value check in the palette branch, header note
- `supercollider/core/harmony.scd` - `~ppBassLast`, `~ppBassStyles`, `~ppBassStyleFor`; `~ppDefaultBass` now takes its last note from `~ppBassLast`; header comments say who plays the bass
- `supercollider/core/render.scd` - the bar's palette picks the bass generator for a non-classic palette under every progression; header comment updated
- `supercollider/library_test.scd` - "bass styles follow the chord", `bad_style.scd` and `string_style.scd` fixtures, the classic-progression bass round trip, "shipped palettes" rows, "palette bass styles under anthem" and "under classic"
- `supercollider/library/palettes/acid.scd` (new) - `pp_acid_bass`, `pp_acid_arp`, `pp_acid_pad`, `pp_acid_lead`; `bassStyle: \sixteenths`; no drum role
- `supercollider/library/palettes/dark.scd` (new) - `pp_dark_kick`, `pp_dark_bass`, `pp_dark_arp`, `pp_dark_pad`, `pp_dark_lead`; `bassStyle: \sixteenths`

## Decisions Made

- Followed the plan's recorded decisions (core style table, palette-gated renderer, style per palette). One tuning decision of mine: dark's level trim is uneven across its voices (kick 0.47, bass 0.58, the rest 0.70) because the deep long kick and the gritty bass added most of the excess energy. The match is on the full mix, and dark's post-FX peak (0.50) is lower than classic's (0.55).
- sixteenths uses the root on every note except the last; no octave jumps, so the roll stays a plain driving pulse and the chord rules hold trivially.

## Deviations from Plan

None - plan executed exactly as written.

Small within-scope notes, not deviations: the static round trip computes the expected bass with a nil-safe lookup (`~ppBassStyles` may not exist yet) so the RED run reached the validator fixtures; and the plan's "RED fails on bass styles follow the chord" became "RED fails on static check catches bad files" because that check runs earlier in the file (see TDD Gate Compliance).

## TDD Gate Compliance

- **RED** `ad48dae` (`test(07-03)`), before the implementation. Command `./scripts/check.sh --library-only`, exit 1, last library line `LIBRARY FAIL: ERROR: static check catches bad files: no failure for palettes/bad_style (looked for "bassStyle is not one of: eighths, octave, sixteenths")`. `gsd_run check tdd-red-evidence` has no adapter for SuperCollider's line protocol (and `workflow.tdd_mode` is off), so this is the semantic assessment: the target check ran and failed on the planned assertion (the validator did not yet refuse an unknown or String bassStyle). Honest note: "bass styles follow the chord" (which fails first on `~ppBassStyles does not exist`) runs after "static check catches bad files" in the file, so it was not reached in the RED run; it first ran, and passed, in the GREEN run.
- **GREEN** `677f316` (`feat(07-03)`): same command passed (`CHECK OK: bass styles follow the chord`, `CHECK OK: static check catches bad files`, `CHECK OK: parity`, `CHECK OK: harmony units`, `CHECK PASS (library only)`).
- **REFACTOR:** none needed.
- Task 2 is a plain `auto` task (palette files tuned against the meter, then the real-time check); the new tests and files were committed together once green.

## Issues Encountered

- The worktree has no `.venv`; a temporary symlink to the main checkout's `.venv` was used for the runs and removed before the final commit. Not part of any commit.
- The sandbox refused compound shell lines that mix git with other commands; commands were issued one at a time. No effect on the repository.
- `FAILURE IN SERVER /s_new Group 1000 not found` lines appeared once at the end of a failed (gap too large) palette_level run; known shutdown noise of the meter, not present in passing runs.

## Known Stubs

None.

## Threat Flags

None. `bassStyle` narrows nothing new: it is a Symbol checked against a fixed list at load (T-07-07), and the new voices pass the same meter gates as supersaw (T-07-08).

## Not covered by a fixture (for the verifier)

- A palette whose own role voices are absent for the bass (bassStyle set, no bass voice) falls back to classic's bass voice playing the style's rows; the shipped palettes always give a bass voice, so no fixture exercises it.
- The meter measures at EPIC 50 only; a by-ear pass at Recovery and at VO2 settings is the check for the stronger bass roll (dark and acid have more low-mid energy than classic).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 05 can add `pluck` with `bassStyle: \octave` (the style exists and is pinned) and add its row to the `palette bass styles` table and the "shipped palettes" table.
- Plan 04's Auto can rotate through acid and dark: both are valid, namespaced and level-matched. `acid.scd` and `dark.scd` are final; a later fix is a new file.
- README (Plan 06) should say that a progression's own bass generator is heard only under the classic palette.

## Self-Check: PASSED

- Created files exist: `supercollider/library/palettes/acid.scd`, `supercollider/library/palettes/dark.scd`.
- Commits `ad48dae`, `677f316`, `85c55e9` are ancestors of HEAD; `git rev-list --count` from the plan start is 3; acid.scd and dark.scd have exactly one commit.
- Last `./scripts/check.sh --library-only` printed `CHECK PASS (library only)` with `CHECK OK: library file count (18 files)`, `CHECK OK: palette levels`, `CHECK OK: bass styles follow the chord`, `CHECK OK: palette bass styles under anthem`, `CHECK OK: palette bass styles under classic`, `CHECK OK: shipped palettes`, and the four palette-meter lines plus `LIBCHECK OK` and `CHECK OK: voices` for acid and dark.

---
*Phase: 07-sound-palettes*
*Completed: 2026-10-13*
