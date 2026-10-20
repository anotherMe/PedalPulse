---
phase: 07-sound-palettes
verified: 2026-10-20T21:00:00Z
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
covered_digest: "v3:sha256:6036015a1e064b193838e607d08fad3bdb6509f7db761a21dfa6e093157a0a31"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: passed
  previous_score: 5/5
  reason: "Previous report (2026-10-13) went stale: quick task 261015-uez (commit f75fde8) changed supercollider/main.scd and supercollider/smoke_test.scd (2.5x master boost before the limiter). Regenerated against current source."
  gaps_closed: []
  gaps_remaining: []
  regressions: []
---

# Phase 7: Sound Palettes Verification Report

**Phase Goal:** As a rider, I want the engine to change its whole sound set every few minutes, or keep one I like, so that a long ride never sounds the same and I can name what I want more or less of.
**Verified:** 2026-10-20T21:00:00Z
**Status:** passed
**Re-verification:** Yes, regeneration after the master-boost change (quick task 261015-uez, f75fde8). No code under `supercollider/`, `scripts/` or `python_app/` differs from HEAD (`git status` clean for those paths).

## Goal Achievement

All five roadmap truths still hold with the 2.5x master boost in place. The three human checks that were pending in the earlier report are complete: `07-UAT.md` (status: complete) records listening check, VO2 at volume 100 and Zwift-side CPU all as `pass` on 2026-10-20 (3 passed, 0 issues, 0 pending). No gaps.

### Observable Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | At least 5 named palettes plus classic; each a coherent, recognisably different set of lead, bass, pad, arp and drum sounds | VERIFIED | `scan_library(Path('supercollider/library/palettes'))` run today returns `['classic','acid','air','dark','pluck','supersaw','warm']` (six named plus classic, and `_template.scd` is excluded). Each of the six files defines its own SynthDefs (5-6 each by `grep -c SynthDef`; classic 7). Library log lists `LIBCHECK OK` for every one. By-ear distinctness: UAT test 1 pass |
| 2 | In Auto the palette changes on its own every few minutes, only at a phrase boundary | VERIFIED | `~ppPalAutoNext` (`core/harmony.scd:384-478`) read in full: random first pick on engage only on a `chapter` (progression change) or `phraseLine`; hold drawn from `~ppPalHoldBars`; rotation lands only when `chapter` or `phraseLine` (or, with progression Auto, on a chapter, with a documented single-candidate exception); pool excludes current and last two played; history capped by `~ppAutoHistoryCap`. Called once per (run, bar) from `~ppHarmPaletteFor` (line 493), itself called in the memoized entry at line 591, wrapped in `try` with a keep-playing fallback. Pacing by ear: UAT test 1 pass |
| 3 | Picking a named palette locks it until Auto is picked again | VERIFIED | `~ppHarmPaletteFor` non-auto branch returns the selected stem and ends the Auto state (read at `harmony.scd:485-499` and header comment); `/pp/palette` OSCdef wired at `main.scd:424` to `~ppSelect.(\palettes, ...)`. Library and smoke logs show the palette checks `CHECK OK` (`palette stop and start`, `palette re-evaluation`, `palette defs stay in their prefix`). Lock behaviour by ear: UAT test 1 pass |
| 4 | Switching causes no noticeable volume jump; VO2 at volume 100 on the loudest palette never clips | VERIFIED with the boost in place | `palette_meter` (library-only path, `pedalpulse-palette.log`): `PALETTE PASS`. Smoke log today: output peak at volume 100 = 0.619; VO2 + volume 100 pre-limiter peak 0.89127, output peak 0.89127, i.e. held at the Limiter ceiling 0.891251 (`main.scd:135`) with no overshoot. Level matching between palettes is a relative gap measured pre-boost and unaffected by a common gain stage. By-ear no jump and clean VO2: UAT tests 1 and 2 pass (2026-10-20, after the boost) |
| 5 | Exit gate holds for every palette (Stop silences, nothing bypasses the limiter); CPU of the heaviest palette at VO2 measured on the riding Mac and within budget for Zwift | VERIFIED | Smoke log: `CHECK OK` for `stop releases all`, `stop cuts held pad`, `stop catches in-flight notes`, `stop silences every layer`, `palette stop and start`, `palette re-evaluation`, `limiter no bypass`, `limiter ceiling`, `master boost`; full gate `SMOKE PASS`. Headless CPU today (`pedalpulse-cpu.log`): `CPU PASS`, heaviest supersaw mean 7.57 percent, peak 15.03 percent (gate mean 25). Next to Zwift: UAT test 3 pass (rider, 2026-10-20) |

**Score:** 5/5 truths verified. No truth is behavior-unverified; each transition and invariant (Auto landing, lock, Stop, limiter) has a named passing check.

### Master-boost regression check (the delta that made the old report stale)

| Concern | Evidence | Status |
|---------|----------|--------|
| Limiter still last in the master chain; boost cannot bypass it | `main.scd:126-136`: `sig = In.ar(in,2) * preGain * boost * volume; Out.ar(out, Limiter.ar(sig, 0.891251, 0.01))`. Boost is a gain stage strictly before the limiter; `boost` defaults to 1 so scratch masters stay unity; real `Synth(\ppMaster, ... \boost, ~ppMasterBoost ...)` at line 233 | VERIFIED |
| VO2 + volume 100 does not clip on the loudest palette | Output peak 0.8913 equals the limiter ceiling (smoke log); no value above 0.891251 | VERIFIED |
| New `master boost` smoke check passes and is substantive | `smoke_test.scd:1649-1726`: checks the number is in 2.0-3.0, reads the live `boost` from `~ppMasterSynth`, runs a gain probe (expects 0.4) and a ceiling probe (0.85-0.892), asserts at least 5 samples each. Log prints `CHECK OK: master boost` | VERIFIED |
| Palette level matching unaffected | Palette meter measures palettes against classic through the same chain; a common multiplier does not change the gap. `PALETTE PASS` today | VERIFIED |
| Headroom for the heaviest palettes | Palette meter peak gate and limiter probes pass; UAT test 2 (loudest palette, VO2, volume 100, one minute) clean after the boost | VERIFIED |

### Plan-level must-haves (spot-verified, unchanged from the prior report except where noted)

| Plan | Key truth | Status | Evidence |
|------|-----------|--------|----------|
| 07-01 | Palette decided once per (run, bar) in the memoized entry; every layer reads it | VERIFIED | `harmony.scd:591` inside the memoized entry; `render.scd` pulls `entry[\palette]` |
| 07-02 | Voice namespace and defs guard undoing a refused palette | VERIFIED (caveat WR-01 below) | `CHECK OK: palette defs stay in their prefix`; `LIBCHECK OK` for each file |
| 07-03 | Bass styles per palette | VERIFIED | `CHECK OK: palette bass styles under anthem` and `under classic` |
| 07-04 | Auto random start, hold, no quick repeat, lock, bounded state | VERIFIED | Code read above |
| 07-05 | One-minute CPU command | VERIFIED | `palette_cpu.sh` ran today: CPU PASS |
| 07-06 | Human checks listed pending then closed by rider | VERIFIED | Closed in `07-UAT.md` |

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `supercollider/core/harmony.scd` | VERIFIED | `~ppPalAutoNext`, `~ppHarmPaletteFor`, palette stage in the memo; wired |
| `supercollider/core/render.scd`, `loader.scd`, `validate.scd` | VERIFIED | Voice lookup by palette stem; defs guard; run by library log |
| `supercollider/library/palettes/{acid,air,dark,pluck,supersaw,warm}.scd` | VERIFIED | Substantive, `LIBCHECK OK` each |
| `supercollider/main.scd`, `smoke_test.scd` | VERIFIED | Boost delta read; wired; checks passing |
| `supercollider/palette_meter.scd`, `scripts/palette_level.sh`, `scripts/palette_cpu.sh`, `scripts/check.sh` | VERIFIED | Produced `PALETTE PASS`, `CPU PASS`, and `CHECK PASS` evidence today |

### Key Link Verification

| From | To | Status |
|------|----|--------|
| `render.scd` bar render | `harmony.scd` memoized entry, then per-role voice by palette stem | WIRED |
| `harmony.scd ~ppHarmonyFor` | `~ppHarmPaletteFor` then `~ppPalAutoNext` | WIRED (lines 591, 493) |
| `main.scd` OSCdef `/pp/palette` | `~ppSelect(\palettes, ...)` | WIRED (line 424) |
| `check.sh` | library check, `palette_level.sh`, smoke suite | WIRED (lines 221-271) |
| Python `scan_library` | `library/palettes/*.scd` | WIRED, 7 stems returned; Python side unchanged |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|----------|------|--------|-----------|--------|
| Dropdown palette list | stems | filesystem scan | Yes (7) | FLOWING |
| Bar's voices | `entry[\palette]` | selection or `~ppPalAutoNext` over the loaded registry | Yes | FLOWING |
| Master output | `In.ar * preGain * boost * volume` into `Limiter` | live fx bus | Yes (gain probe reads 0.4) | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Python side green | `.venv/bin/python -m pytest -q python_app/tests` (run by this verifier) | 191 passed | PASS |
| Palette list reaches the dropdown | `scan_library` on `library/palettes` (run by this verifier) | 7 stems | PASS |
| Full gate on current source | `bash scripts/check.sh`, logs inspected: library `LIBRARY PASS`, palette `PALETTE PASS`, smoke `SMOKE PASS` (75 `CHECK OK` in smoke, 89 in library), no `CHECK FAILED` in today's logs | Gathered by the orchestrator today (about 12 min); logs timestamped 2026-10-20 19:30-19:38 re-read here, not re-run | PASS (logs read) |
| Headless CPU | `bash scripts/palette_cpu.sh` log | CPU PASS, supersaw mean 7.57, peak 15.03 | PASS (log read) |

The only `CHECK FAILED` string under `$TMPDIR` is in `pedalpulse-check-mut.log` (13 Oct mutation run), not part of the current gate.

### Probe Execution

No probes beyond `scripts/palette_level.sh`, `scripts/palette_cpu.sh`, and `scripts/check.sh`, covered above.

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|--------------|-------------|--------|----------|
| PAL-01 | 07-01, 03, 05, 06 | At least 5 named palettes plus classic, each a coherent sound set | SATISFIED | Truth 1; UAT test 1 |
| PAL-02 | 07-04, 06 | Auto rotates every few minutes only at section or phrase boundaries | SATISFIED | Truth 2; UAT test 1 |
| PAL-03 | 07-01, 04, 06 | Named palette locks until Auto is selected | SATISFIED | Truth 3; UAT test 1 |
| PAL-04 | 07-01, 02, 03, 05, 06 | Loudness-matched, no volume jump, never bypasses the limiter | SATISFIED | Truths 4 and 5, boost regression table; UAT tests 1, 2 |

All four IDs appear in the plan frontmatter (`requirements:` of 07-01 to 07-06) and in REQUIREMENTS.md lines 36-39. No orphaned Phase 7 requirements. Follow-up for the orchestrator (bookkeeping, not a code gap): REQUIREMENTS.md still shows PAL-01..04 as `[ ]` and `Pending` (lines 36-39, 111-114); they can be flipped to complete now that UAT is closed.

### Anti-Patterns Found

Debt-marker scan (`TBD|FIXME|XXX`) over `supercollider/` and `scripts/` returns nothing. No stubs.

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `supercollider/core/loader.scd`, `validate.scd` | ~187-193, ~256-262 | WR-01 (prior review): prefix-based namespace test lets stems `a` and `a_b` collide | Warning | Needs a deliberately crafted palette name; no shipped palette or success criterion affected. Recorded in 07-REVIEW-DISPOSITION.md |
| `palette_meter.scd`, `library_test.scd`, `smoke_test.scd` | | WR-02 (prior review): fixed watchdogs against a library that grows by one file per variation | Warning | Future maintenance risk at roughly 18-20 palettes; gate passes at 7 |
| `smoke_test.scd:1659-1661` | | Boost review WR: the gate rejects boost values outside 2.0-3.0 that the README allows (07-REVIEW.md, 2 warnings, 1 info, 0 critical) | Warning | Affects only a rider who retunes `~ppMasterBoost`; shipped value 2.5 passes |
| smoke log | | `FAILURE IN SERVER /n_set Node N not found` lines in the smoke log | Info | Appear before `SMOKE PASS`; they are server messages for already-freed nodes during stop/restart checks, not a failed check |
| `07-VALIDATION.md` | line 7 | Frontmatter says `nyquist_compliant: false` while its sign-off line 102 and approval text say it was set to true | Warning (documentation inconsistency) | Does not affect any phase truth. The orchestrator's brief said true; the committed file (2d58217) says false. Fix the frontmatter value before milestone audit |

None is a blocker, and none contradicts a must-have truth.

### Human Verification Required

None outstanding. The three items from the prior report are complete and recorded as `pass` in `07-UAT.md` (rider, 2026-10-20): listening check across palettes, lock, Auto pacing and Stop/Start; VO2 at volume 100 on the loudest palette, clean; Zwift-side `palette_cpu.sh`, CPU PASS. These were done after the boost landed.

### Gaps Summary

No gaps. The master boost sits before the -1 dBFS limiter, the limiter remains the last stage, VO2 at volume 100 is held at the ceiling (0.8913), and the boost has its own passing smoke check. Phase 7 goal is achieved on the current source.

---

_Verified: 2026-10-20T21:00:00Z_
_Verifier: Claude (gsd-verifier)_
