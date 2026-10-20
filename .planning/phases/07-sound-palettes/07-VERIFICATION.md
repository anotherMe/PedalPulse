---
phase: 07-sound-palettes
verified: 2026-10-13T20:30:00Z
status: passed
score: 5/5 must-haves verified
covered_files:
  - .planning/phases/07-sound-palettes/07-01-PLAN.md
  - .planning/phases/07-sound-palettes/07-01-SUMMARY.md
  - .planning/phases/07-sound-palettes/07-02-PLAN.md
  - .planning/phases/07-sound-palettes/07-02-SUMMARY.md
  - .planning/phases/07-sound-palettes/07-03-PLAN.md
  - .planning/phases/07-sound-palettes/07-03-SUMMARY.md
  - .planning/phases/07-sound-palettes/07-04-PLAN.md
  - .planning/phases/07-sound-palettes/07-04-SUMMARY.md
  - .planning/phases/07-sound-palettes/07-05-PLAN.md
  - .planning/phases/07-sound-palettes/07-05-SUMMARY.md
  - .planning/phases/07-sound-palettes/07-06-PLAN.md
  - .planning/phases/07-sound-palettes/07-06-SUMMARY.md
  - scripts/check.sh
  - scripts/palette_cpu.sh
  - scripts/palette_level.sh
  - supercollider/core/harmony.scd
  - supercollider/core/loader.scd
  - supercollider/core/render.scd
  - supercollider/core/validate.scd
  - supercollider/library/README.md
  - supercollider/library/palettes/acid.scd
  - supercollider/library/palettes/air.scd
  - supercollider/library/palettes/dark.scd
  - supercollider/library/palettes/pluck.scd
  - supercollider/library/palettes/supersaw.scd
  - supercollider/library/palettes/warm.scd
  - supercollider/library_test.scd
  - supercollider/main.scd
  - supercollider/palette_meter.scd
  - supercollider/smoke_test.scd
covered_digest: "v3:sha256:e97ef01503f28415a792a7fe6c946e68e8da9cde27c421ba1ac72ca9f1983da1"
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Rider listening check (07-06 SUMMARY steps 1-8): pick each of the 7 palettes at low and high EPIC, then leave Palette and Progression on Auto for about 20 minutes at the usual BPM; pick a palette by name while Auto runs; press Stop then Start"
    expected: "Every palette is clearly different by ear; no palette jumps out in loudness when switching at low or high EPIC; Auto changes the palette on the same bar as a progression change, never an immediate repeat, about 5 minutes on average at 90-110 BPM; a named palette stays until Auto is picked again; Stop silences everything, Start resumes with a new palette on Auto"
    why_human: "Character, by-ear loudness, and pacing over many minutes are perceptual. The meter proves the numeric gap to classic is at most 0.29 dB, not that the rider hears no jump"
  - test: "VO2 at volume 100 on the loudest palette for about one minute (07-06 SUMMARY step 5)"
    expected: "Clean sound, no crackle, distortion or pumping"
    why_human: "Clipping is bounded numerically (post-FX peak at most 0.672, Limiter at 0.891), but audible cleanliness is a listening judgment"
  - test: "Zwift-side CPU check (07-06 SUMMARY step 9): quit the PedalPulse engine, open Zwift, run `bash scripts/palette_cpu.sh`"
    expected: "Prints CPU PASS with mean under 25 percent. Headless reference without Zwift: supersaw heaviest at mean about 9.7 percent, peak about 13.5 percent"
    why_human: "ROADMAP criterion 5 requires CPU measured on the riding Mac next to Zwift. Only the rider can run it with Zwift open"
---

# Phase 7: Sound Palettes Verification Report

**Phase Goal:** As a rider, I want the engine to change its whole sound set every few minutes, or keep one I like, so that a long ride never sounds the same and I can name what I want more or less of.
**Verified:** 2026-10-13T20:30:00Z
**Status:** passed (human checks confirmed by the rider on 2026-10-20, see 07-UAT.md)
**Re-verification:** No, initial verification

## Goal Achievement

All code-verifiable parts of the goal are present, wired and exercised by passing checks. The remaining items are perceptual and machine-specific (listening, Zwift CPU), which the plans declared as pending for the rider by design. No gaps found.

### Observable Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Palette selector lists at least 5 named palettes plus classic; each a coherent, recognisably different set of lead, bass, pad, arp and drum sounds | VERIFIED (distinctness by ear is a human item) | `scan_library('supercollider/library/palettes')` returns `['classic','acid','air','dark','pluck','supersaw','warm']`: six named plus classic, so the dropdown needs no Python change. Each of the 6 new files defines its own `pp_<name>_` bass/arp/pad/lead SynthDefs; dark adds its own kick, pluck its own hat; each has a distinct `desc` and `bassStyle` (acid/dark sixteenths, pluck octave, others eighths) |
| 2 | In Auto the palette changes on its own every few minutes, always at a phrase boundary, never mid-phrase | VERIFIED (pacing by ear is a human item) | `~ppPalAutoNext` in `core/harmony.scd` (lines 384-460): random first pick, hold `~ppPalHoldBars = [80,128]` bars, then lands only on `chapter` (progression change) or `phraseLine` (cycle start of at least 4 bars, or bar multiple of 8), excludes current and last two played; called once per (run, song bar) from `~ppHarmPaletteFor` inside the memoized harmony entry. Library test `auto palette rotates` passed in the orchestrator's `check.sh` run |
| 3 | Picking a named palette locks it until Auto is picked again | VERIFIED | `~ppHarmPaletteFor`: any non-auto selection returns the selected stem for every bar (progression changes irrelevant) and clears `palAuto[\current]`, so a later Auto engages fresh. `/pp/palette` OSCdef wired in `main.scd:408` to `~ppSelect`. Library test `named palette plays from the next bar` passed; smoke `palette stop and start` selects each palette by name and waits for `~ppPalPlaying` |
| 4 | Switching causes no noticeable volume jump; VO2 at volume 100 on the loudest palette never clips | VERIFIED (by-ear half is a human item) | Independently re-ran `bash scripts/palette_level.sh`: PALETTE PASS. RMS gap to classic at EPIC 50: acid +0.29, air +0.06, dark -0.07, pluck -0.12, supersaw +0.29, warm +0.13 dB (gate 1.5, authoring target 0.75). VO2 / volume 100 post-FX peak: classic 0.548, acid 0.556, air 0.539, dark 0.479, pluck 0.672, supersaw 0.545, warm 0.523 (gate 0.80; output equals fx peak, at or below the Limiter ceiling 0.891251 at `main.scd:119`). Extreme-note probe finite for all 6 |
| 5 | Exit gate holds for every palette (Stop silences, nothing bypasses limiter); CPU of the heaviest palette at VO2 measured on the riding Mac and within budget for Zwift | VERIFIED for Stop/limiter; PENDING HUMAN for Zwift CPU | Smoke checks `palette stop and start` (every palette on disk, master pre-gain 0 leaves bus 0 silent, Stop empties the group within 2.5 s) and `palette re-evaluation` (Auto, no stacking) exist in `smoke_test.scd` and passed in the orchestrator's `check.sh` run (CHECK PASS). Headless CPU (re-run now): heaviest is supersaw at mean 9.69 percent, peak 13.45, gate 25. `scripts/palette_cpu.sh` exists for the rider's Zwift measurement; not yet run next to Zwift |

**Score:** 5/5 truths verified in code; the 3 perceptual and machine-specific confirmations were reported done and passing by the rider on 2026-10-20 (07-UAT.md).

### Plan-level must-haves (spot-verified)

| Plan | Key truth | Status | Evidence |
|------|-----------|--------|----------|
| 07-01 | Palette decided once per (run, song bar) in the memoized entry and every layer, drums included, reads it; post-window line `PedalPulse: palette <name>: <desc>` | VERIFIED | `harmony.scd` ~590-610 sets `entry[\palette]` and logs the line; `render.scd:177-190` pulls the entry for every role and calls `~ppInstrumentFor.(role, palStem)` |
| 07-01 | Palette meter in library-only gate | VERIFIED | `palette_meter.scd` + `palette_level.sh` run end to end here: PALETTE PASS |
| 07-02 | Voice namespace `pp_<name>_` and defs guard that undoes a refused palette | VERIFIED with caveat | `~ppPaletteDefs` in `loader.scd`, `~ppClassicVoices` in `validate.scd`; library test `refused palette leaves no voices` present and passing. Caveat: WR-01 below |
| 07-03 | Bass styles eighths/sixteenths/octave chosen by palette | VERIFIED | `bassStyle` present in acid, dark (sixteenths), pluck (octave); library test `bass styles follow the chord` present |
| 07-04 | Palette Auto behaviour (random start, hold, no quick repeats, lock, bounded state) | VERIFIED | `~ppPalAutoNext` code read in full; history capped by `~ppAutoHistoryCap`, palLog by `~ppHarmLogCap`, entries by `~ppHarmKeepBars` |
| 07-05 | `scripts/palette_cpu.sh` one-minute CPU command | VERIFIED (exists, validated args); run next to Zwift pending | File read; `PP_METER=cpu` mode in the meter |
| 07-06 | Listening and Zwift checks listed as pending, never marked done; SUMMARY lists unconfirmed planner decisions | VERIFIED | `07-06-SUMMARY.md` has "Pending human checks" and "Planner decisions for the rider to review"; no claim of rider confirmation |

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `supercollider/core/harmony.scd` (836 lines) | VERIFIED | `~ppPalAutoNext`, `~ppHarmPaletteFor`, `~ppPalHoldBars`, palette stage in the memo |
| `supercollider/core/render.scd` | VERIFIED | `~ppInstrumentFor` with palette stem; renders every role from `entry[\palette]` |
| `supercollider/core/loader.scd`, `validate.scd` | VERIFIED | `~ppPaletteDefs` guard, `~ppBassStyleNames`, row bounds |
| `supercollider/palette_meter.scd` (482 lines) | VERIFIED | Ran: level, VO2, CPU and extreme-note tiers all report |
| `supercollider/library/palettes/{acid,air,dark,pluck,supersaw,warm}.scd` | VERIFIED | Substantive SynthDefs, not stubs; wired through the loader and the meter |
| `scripts/palette_level.sh`, `scripts/palette_cpu.sh`, `scripts/check.sh` | VERIFIED | `palette_level.sh` ran to PALETTE PASS; check.sh calls the meter on the library-only path |
| `supercollider/library/README.md`, `palettes/_template.scd` | VERIFIED | Sections and commands present (06 SUMMARY greps) |

### Key Link Verification

| From | To | Status |
|------|----|--------|
| `render.scd ~ppRenderBar` | `harmony.scd` memoized entry then `~ppInstrumentFor.(role, palStem)` | WIRED |
| `harmony.scd ~ppHarmonyFor` | `~ppHarmPaletteFor` then `~ppPalAutoNext` | WIRED |
| `main.scd` OSCdef `/pp/palette` | `~ppSelect(\palettes, ...)` | WIRED |
| `check.sh` | `palette_level.sh` then `palette_meter.scd` | WIRED |
| Python `scan_library` | `supercollider/library/palettes/*.scd` | WIRED, Python app unchanged (send-only; last `python_app` change predates Phase 7) |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|----------|------|--------|-----------|--------|
| Dropdown palette list | stems | filesystem scan of `library/palettes` | Yes (7 stems returned) | FLOWING |
| Bar's voices | `entry[\palette]` | selection or `~ppPalAutoNext` over loaded registry | Yes | FLOWING |

### Behavioral Spot-Checks (run by this verifier)

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Python side unchanged and green | `.venv/bin/python -m pytest -q python_app` | 191 passed | PASS |
| Every palette is level-matched, has VO2 headroom, bounded CPU, finite at extreme notes | `bash scripts/palette_level.sh` (about 3.5 min, real audio server) | PALETTE PASS (figures above) | PASS |
| One palette quick measure | `bash scripts/palette_level.sh pluck` | PALETTE PASS, vo2 fxpeak 0.647 | PASS |
| Library check, smoke suite, full gate | Not re-run (about 10 min, audio device); orchestrator evidence: `scripts/check.sh` on merged HEAD gave LIBRARY PASS, SMOKE PASS, CHECK PASS | Cited, not independently re-run | PASS (cited) |

Note: 07-06 SUMMARY records two intermittent smoke flakes (`stop releases all` missed its 2.5 s budget by 0.13 s; `epic glide down`) in earlier checks on classic, both passing on rerun. They are not in Phase 7 checks, but the gate is not fully deterministic.

### Probe Execution

No probes declared beyond `scripts/palette_level.sh` and `scripts/check.sh`, covered above.

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|--------------|-------------|--------|----------|
| PAL-01 | 07-01, 03, 05, 06 | At least 5 named palettes plus classic, each a coherent set of sounds | SATISFIED | 6 named + classic on disk, own voices each (see truth 1) |
| PAL-02 | 07-04, 06 | Auto rotates every few minutes only at section or phrase boundaries | SATISFIED in code and tests; pacing by ear pending | `~ppPalAutoNext`; hold 80-128 bars then progression change or phrase line |
| PAL-03 | 07-01, 04, 06 | Named palette locks until Auto is selected | SATISFIED | `~ppHarmPaletteFor` named branch; tests above |
| PAL-04 | 07-01, 02, 03, 05, 06 | Loudness-matched, no volume jump, never bypasses the limiter | SATISFIED numerically; by-ear check pending | Meter figures above; Limiter in `main.scd:119`; smoke no-bypass probe on every palette |

All four IDs appear in plan frontmatter and in REQUIREMENTS.md. No orphaned requirements for Phase 7. REQUIREMENTS.md still shows these four as `[ ]` / Pending; the orchestrator should flip them after the UAT closes (not a code gap).

### Anti-Patterns Found

No TBD/FIXME/XXX markers in the phase's files; no TODO/HACK in core or palette files. No stubs.

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `supercollider/core/loader.scd`, `validate.scd` | 187-193, 256-262 | WR-01: namespace check is a prefix test, so stems `a` and `a_b` can collide (an added name is accepted on prefix alone) | Warning | Needs a deliberately crafted palette name; does not affect any shipped palette or any success criterion. Recorded open in the review disposition |
| `palette_meter.scd:78`, `library_test.scd:55`, `smoke_test.scd:32` | | WR-02: fixed watchdogs against a library that grows by one file per variation (meter fails at about 18-20 palettes with an unexplained timeout). Currently 7 palettes at 3.5 min | Warning | Future maintenance risk; gate passes today |
| `loader.scd` | 218, 258 | IN-01 empty error handlers in the undo path | Info | Silent failure only in an already-refused path |
| `pluck.scd` | 19 | IN-02 comment misstates hat amplitude (frozen file) | Info | None |
| `main.scd` | 175-177 | IN-03 indentation | Info | None |
| `smoke_test.sh` | | IN-04 unanchored pass-line match | Info | Minor |

None is a blocker, and none contradicts a must-have truth. The WR-01 caveat softens the 07-02 truth ("two palettes never share a voice name") only for crafted prefix-colliding names.

### Human Verification Required

1. **Rider listening check** (palettes distinct, no volume jump by ear at low and high EPIC, Auto pacing at the rider's tempo, lock, Stop/Start). Expected: see frontmatter. Why human: perceptual.
2. **VO2 at volume 100 on the loudest palette for a minute**. Expected: clean, no crackle or pumping. Why human: audible quality.
3. **Zwift-side CPU check** with `bash scripts/palette_cpu.sh` while Zwift is open. Expected: CPU PASS, mean under 25 percent. Why human: needs the riding Mac with Zwift; ROADMAP criterion 5 explicitly requires this measurement.

Full script for these is in `07-06-SUMMARY.md` under "Pending human checks". No `07-UAT.md` exists yet.

### Gaps Summary

No gaps. Every must-have truth is implemented, wired and covered by checks that pass; the headline numbers (level gap at most 0.29 dB, VO2 peak at most 0.672, heaviest headless CPU 9.7 percent) were reproduced independently by this verifier. The phase cannot be marked fully passed until the rider completes the listening and Zwift CPU checks, which is why the status is `human_needed` rather than `passed`.

---

_Verified: 2026-10-13T20:30:00Z_
_Verifier: Claude (gsd-verifier)_
