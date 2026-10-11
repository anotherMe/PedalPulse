---
phase: 04-modular-engine-variation-library
verified: 2026-10-11T20:55:00Z
status: human_needed
score: 5/5 roadmap success criteria verified (automated); 1 rider listening check pending
covered_files:
  - .planning/phases/04-modular-engine-variation-library/04-01-PLAN.md
  - .planning/phases/04-modular-engine-variation-library/04-01-SUMMARY.md
  - .planning/phases/04-modular-engine-variation-library/04-02-PLAN.md
  - .planning/phases/04-modular-engine-variation-library/04-02-SUMMARY.md
  - .planning/phases/04-modular-engine-variation-library/04-03-PLAN.md
  - .planning/phases/04-modular-engine-variation-library/04-03-SUMMARY.md
  - .planning/phases/04-modular-engine-variation-library/04-04-PLAN.md
  - .planning/phases/04-modular-engine-variation-library/04-04-SUMMARY.md
  - .planning/phases/04-modular-engine-variation-library/04-05-PLAN.md
  - .planning/phases/04-modular-engine-variation-library/04-05-SUMMARY.md
  - .planning/phases/04-modular-engine-variation-library/04-06-PLAN.md
  - .planning/phases/04-modular-engine-variation-library/04-06-SUMMARY.md
  - scripts/check.sh
  - supercollider/core/loader.scd
  - supercollider/core/render.scd
  - supercollider/core/validate.scd
  - supercollider/golden/shipped_groove.scd
  - supercollider/library/README.md
  - supercollider/library/melodies/classic.scd
  - supercollider/library/melodies/classic_lead.scd
  - supercollider/library/palettes/classic.scd
  - supercollider/library/progressions/classic.scd
  - supercollider/library_test.scd
  - supercollider/main.scd
  - supercollider/smoke_test.scd
covered_digest: "v3:sha256:9a403a9774c9b1d33da1a0cd25b1eda9f1afc95013c0501f769b96a50286ca80"
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Rider listening check (Plan 04-06 <human-check>, D-01 / D-06): evaluate supercollider/main.scd in the IDE as always, run ./run.sh, listen for a minute; move BPM, press Stop/Start, click effort zones, move volume; then send /pp/melody classic_lead with the documented python one-liner, hear a faint octave-up shimmer from the next bar; Stop (shimmer goes quiet too) and Start; send /pp/melody classic and hear the shimmer leave"
    expected: "Default startup sounds like the shipped v1.0 engine (same drums, bass, arp, pad, same loudness; BPM glide, Start/Stop, EPIC zones, volume unchanged). classic_lead only thickens the arp, it is not a new tune. /pp/melody classic removes it again"
    why_human: "Sound identity and 'faint shimmer' are perceptual. Event-level parity (496 rows, 0 mismatches) proves the same notes, amps, buses and timing, but not that it sounds the same through the real audio device; no executor performed or simulated this check"
  - test: "Decision on code-review warnings WR-01 and WR-02 (see Warnings section)"
    expected: "Rider/maintainer accepts them as hardening for a later phase, or asks for a gap-closure plan before Phase 5/6 add more library content"
    why_human: "They concern how hard a hostile or careless library file may push the engine; whether that is in scope for LIB-04 is a judgment call"
---

# Phase 4: Modular Engine & Variation Library Verification Report

**Phase Goal:** As a rider, I want the engine split into a core plus a library of named variation files, with no change to what I hear, so that new variations can be added as files and switched to without ever stopping the music.
**Verified:** 2026-10-11
**Status:** human_needed
**Re-verification:** No, initial verification

## Goal Achievement

Everything that can be checked from the code and by running it holds. I re-ran `bash scripts/check.sh` myself on the merged main (not relying on SUMMARY.md or the orchestrator's log): it printed `CHECK PASS` (library guard self-test OK, 7 `LIBCHECK OK` lines matching 7 files on disk, `parity rows=496 mismatches=0`, `LIBRARY PASS`, `SMOKE PASS`, 100 `CHECK OK:` lines in the tail I counted, 0 failures), pytest 150 passed, and no Python files changed in the phase. The one thing that cannot be proven by a machine, "no change to what I hear", is left as the rider's listening check, so the phase is `human_needed`, not `passed`.

### Observable Truths (ROADMAP Success Criteria, the contract)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Engine starts from `main.scd` exactly as before and plays the v1.0 groove unchanged; BPM glide, Start/Stop, EPIC, volume behave as v1.0 | VERIFIED for event-level behavior; sound identity routed to human | `main.scd` still the single entry (loads `core/*.scd` via `~ppLoadCore`, `~ppRoot` from `nowExecutingPath`). My run: `parity rows=496 mismatches=0` against `golden/shipped_groove.scd` (64 kick, 64 hat, 32 clap, 64 bass, 256 arp, 16 pad; every column incl. out bus and group). The golden was committed in `c4c518b` (20:34) before the first `main.scd` change `f86ee0f` (20:47) and has exactly one commit. The six SynthDefs in `palettes/classic.scd` are byte-for-byte the v1.0 ones (diffed against `d3dd072:main.scd`). BPM/EPIC/volume/transport handlers and the ramp stepper are untouched code in `main.scd`; the 67 pre-existing smoke checks still pass in my run. Sensitivity proven: I changed the classic arp amp 0.1 to 0.11, ran `library_test.scd`, got `LIBRARY FAIL: parity: 256 mismatches`, then restored the file (`git status` clean for `supercollider/`). The "same sound" half is Human item 1 |
| 2 | `library/` has `progressions/`, `melodies/`, `palettes/`, each with `classic.scd`; file name is identity; new variation = new file, earlier ones stay loadable | VERIFIED | Files exist (classic in all three, plus `classic_lead.scd` and three `_template.scd`). Loader sets `name`/`path`/`category`/`rev` from the stem and ignores any name inside the file (`~ppLibLoad`). `scripts/check.sh` guard (`git diff --name-status --no-renames HEAD`, non-`A` fails) with a self-test covering modify/delete/rename/new/byte-identical/golden/outside-git; self-test ran `CHECK OK` in my run. See WR-03 for the commit-bypass limitation |
| 3 | Added/changed file can be selected or reloaded by name over `/pp/progression`, `/pp/palette`, `/pp/melody` (`auto` or stem) with no restart and no playback gap; broken/invalid file refused with a post-window error naming it, music stays on classic | VERIFIED (with hardening warnings) | Three `OSCdef`s in `main.scd:392-394` delegate to `~ppSelect` (loader.scd:180-224): name validation by character loop before any path is built, realpath containment, Routine on SystemClock (no `s.sync` in the responder), latest-wins token, `~ppSel` set only after a successful load, renderer reads it at each bar start (`~ppResolveStem`). Refusal paths in `~ppLibLoad`/`~ppLibEnsure` each log `PedalPulse ERROR: library file <path> ...` and leave the registry untouched (last good copy kept). Per-bar containment in `~ppRenderBar` (try, `~ppRowsValid`, classic fallback for the bar, revert to classic after 3 failures). The library test exercises these (hot add, hot change, broken edit keeping last good copy, syntax error, empty file, wrong shape, missing file, symlink outside, bad defs, missing voice, throwing generator, 3.5/4.5-beat bars) and passed in my run. Gaps in what "invalid" covers: WR-01, WR-02, WR-06 below |
| 4 | One command runs the smoke suite plus a library check that validates every library file (loads, shape, voices go through limiter, obey Stop/gate) and reports pass/fail | VERIFIED | `bash scripts/check.sh` is the one command (`--library-only` fast loop). It ran guard + guard self-test, `library_test.scd`, `smoke_test.sh`, and printed `CHECK PASS`. Static tier prints one `LIBCHECK OK: <cat>/<stem>` per file (7), cross-checked against `find supercollider/library -name '*.scd'` count (`CHECK OK: library file count (7 files)`). Voice tier checks private-bus-only output, gate release, self-free, with three deliberately bad voices that must fail; static tier has six bad-file negative controls |
| 5 | Re-evaluating `main.scd` or a module several times leaves exactly one copy of every layer, no extra nodes/routines; Stop silences every layer and source | VERIFIED | Teardown stops all `~ppLayers` (now 7, lead included), stepper and clock, waits 0.3 s, frees groups/buses in dependency order, rebuilds the registry, then rebuilds layers. Smoke output in my run: `eng-05 counts players 7 routines 1 clocks 2 groups 6 synthDefs 121 oscdefs 10 pdefs [7 layers]`, `CHECK OK: eng-05 no stacking` (three back-to-back re-evaluations, selection survives), `eng-05 module re-evaluation` (validate/loader/render twice each), `stop silences every layer` (with classic_lead flowing), `re-evaluation stays stopped` |

**Score:** 5/5 roadmap truths verified by automated evidence; the perceptual half of truth 1 (and the 04-06 listening truth) is pending the rider.

### PLAN must-haves not in the roadmap

All PLAN truths I checked hold in the code or in the executed checks: golden recorded from the unmodified engine and repeatable (04-01), `main.scd` holds no musical content (04-02: voices in `palettes/classic.scd`, bass/pad in `progressions/classic.scd`, arp in `melodies/classic.scd`, drum grid in `render.scd`), 7th layer `ppLead` under classic renders only rests (0 lead events in parity), classic_lead lead = arp +12 semitones at amp 0.025, name rules (1-64 of a-z0-9_, not leading `_`, not `auto`), per-(song, bar, role) seeding formula, `thisThread.beats` bar number, quant 4 kept after Stop/Start, README with copy-paste one-liners for all three addresses. 04-06's truth "the rider confirms by ear..." is explicitly NOT closed (prohibition: judgment tier, resolved as 'executor must not perform it'; see Human Verification).

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `supercollider/core/loader.scd` (226 lines) | VERIFIED | Real logic: `~ppLibLoad`, `~ppLibEnsure`, `~ppSelect`, `~ppStemValid`, `~ppLibContained`; loaded by `main.scd:37`, called by OSCdefs and boot |
| `supercollider/core/render.scd` (237) | VERIFIED | `~ppRenderBar`, `~ppBuildLayers`, seeding, containment; `~ppBuildLayers.()` called at `main.scd:266`; layers feed `~ppMixBus` / `~ppInstrGroup` |
| `supercollider/core/validate.scd` (156) | VERIFIED | `~ppRowsValid`, `~ppValidate`, `~ppValidateVoices`; used by loader, renderer and `library_test.scd` (single source of truth) |
| `supercollider/library/{progressions,melodies,palettes}/classic.scd` | VERIFIED | Substantive; loaded at boot by `~ppLibEnsure` for each category |
| `supercollider/library/melodies/classic_lead.scd` | VERIFIED | Arp identical to classic plus lead 69/72/76/72 at amp 0.025 |
| `supercollider/library/*/_template.scd` (3) | VERIFIED | Validate in the static tier, never selectable. WR-04: template text about shared `state` is inaccurate |
| `supercollider/library/README.md` | VERIFIED | Plain-language guide with one-liners for `/pp/melody`, `/pp/progression`, `/pp/palette` |
| `supercollider/golden/shipped_groove.scd` | VERIFIED | Single commit, before engine changes; used by the parity tier |
| `supercollider/library_test.scd` (1572 lines) | VERIFIED | Own muted server on 57141, watchdog, all tiers ran |
| `scripts/check.sh` (203) | VERIFIED | Wired to guard, library test, smoke; fails if sclang or `.venv` missing |
| `supercollider/smoke_test.scd` | VERIFIED | ENG-05 block present and passing |

### Key Link Verification

| From | To | Status |
|------|----|--------|
| `main.scd` | `core/validate.scd`, `loader.scd`, `render.scd` via `~ppLoadCore` (lines 36-38, validate first) | WIRED |
| `main.scd` boot | `library/*/classic.scd` via `~ppLibEnsure` then `s.sync` before `~ppBuildLayers` (lines 147-168, 266) | WIRED |
| OSCdefs `pp_progression/palette/melody` | `~ppSelect` -> `~ppLibEnsure` -> `~ppSel` -> `~ppResolveStem` in `~ppRenderBar` | WIRED |
| `~ppRenderBar` | `~ppRowsValid` and classic fallback | WIRED |
| `library_test.scd` | golden, `main.scd`, temp library root, language port OSC | WIRED (ran) |
| `scripts/check.sh` | `library_test.scd`, `smoke_test.sh`, file-count cross-check | WIRED (ran) |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|----------|------|--------|-----------|--------|
| `Pbindef(ppArp ...)` | rows of `[inst, midinote, dur, amp, legato]` | `~ppRenderBar` -> `melodies/classic.scd` arp generator, per bar | Yes: 256 arp events in 16 bars, matching the golden | FLOWING |
| `Pbindef(ppLead)` | same | `classic_lead.lead` once selected; rests under classic | Yes: `~ppRoleNotes[\lead]` rises in the Stop check | FLOWING |
| Bass/pad | rows | `progressions/classic.scd` | Yes (64 bass, 16 pad) | FLOWING |
| Drums | rows | `~ppDrumGrid` in core (by design, a drum role has no category) | Yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Whole gate | `bash scripts/check.sh` (full, my own run, 3 m 56 s) | `CHECK PASS` | PASS |
| Parity is not vacuous | edit classic arp amp 0.1 -> 0.11, `sclang -D supercollider/library_test.scd` | `LIBRARY FAIL: parity: 256 mismatches`, file restored | PASS (control fails as it should) |
| Python side untouched | `git diff --stat d3dd072 HEAD -- python_app run.sh`; `pytest -q python_app` | empty diff; 150 passed | PASS |
| Debt markers | grep `TBD|FIXME|XXX` in phase code | none | PASS |

### Probe Execution

SKIPPED: no `probe-*.sh` conventions or declarations in this phase; the gate is `scripts/check.sh` (run above).

### Requirements Coverage

Every ID in the PLAN frontmatter exists in REQUIREMENTS.md and maps to Phase 4; no orphans (REQUIREMENTS.md maps exactly LIB-01..06 and ENG-05 to Phase 4, and all appear in plans).

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|--------------|-------------|--------|----------|
| LIB-01 | 04-01, 04-02, 04-06 | Start from `main.scd`, loads core plus library; classic sounds like v1.0 | SATISFIED (sound identity: human) | Parity 496/0, voices identical to v1.0 |
| LIB-02 | 04-02, 04-03, 04-05 | Each progression/melody/palette its own named file; file name is identity | SATISFIED | Loader derives name from stem; name rules enforced; round-trip per stem in static tier |
| LIB-03 | 04-01, 04-05 | New variations are new files; existing never overwritten | SATISFIED with limitation | Guard + self-test; bypassable by committing an edit (WR-03) |
| LIB-04 | 04-04 | Broken/invalid file never stops the music; logs error, keeps/falls back to classic | SATISFIED for the specified failure classes | Ten refusal classes plus per-bar containment tested; magnitude and palette-side-effect cases open (WR-01, WR-02) |
| LIB-05 | 04-03, 04-04 | File added/changed while running can be selected/reloaded without restart or interruption | SATISFIED | Hot add/change/broken-edit tests; bar-line switching. WR-06 race edge |
| LIB-06 | 04-01, 04-04, 04-05 | Automated check validates every library file and runs with the smoke suite | SATISFIED | `check.sh`, LIBCHECK per file with count cross-check, voice tier with negative controls |
| ENG-05 | 04-06 | Re-evaluation never stacks routines or leaks nodes; Stop silences every new layer and source | SATISFIED | eng-05 smoke block counts identical after 3 re-evals and module re-evals; Stop empties the group with the lead playing |

Note: `.planning/REQUIREMENTS.md` still shows all seven checkboxes unchecked and "Pending" in the traceability table. That is bookkeeping for the phase-complete step, not a code gap.

### Anti-Patterns Found

None blocking. No TBD/FIXME/XXX; no stub returns in shipped paths (the `silent` fallbacks in `~ppBuildLayers` are error containment, not stubs). IN-03 (drum fallback bar plays `\default` at amp 0) is minor.

## Warnings (not must-have failures; human decision requested)

These come from the code review (`04-REVIEW.md`, all dispositions `open`). I read the code and confirm each is real; none contradicts a stated PLAN truth or ROADMAP success criterion, and all the specified failure classes are tested and pass, so I did not classify them as BLOCKERs. They do weaken the strong reading of LIB-04 ("a bad file cannot take the engine down").

1. **WR-01, no upper bounds on rows (confirmed in `validate.scd:22-64`).** A bar with hundreds of thousands of rows whose durs sum to 4.0, legato 100, or midinote 500 all pass `~ppRowsValid`, so they are not refused and could flood or destabilise the engine (a NaN into the shared FX chain would silence it until re-evaluation). The code-review fix (row cap 64, note -12..127, legato <= 4, dur >= 1/32, plus negative tests) is small. Recommend a gap-closure plan or an explicit deferral before Phases 6-8 add many more library files.
2. **WR-02, a refused palette leaves its SynthDefs registered, and falling back to classic does not re-run classic's `defs` (confirmed in `loader.scd:126-154`).** Only bites if a palette reuses classic's SynthDef names (`ppArp` etc.); the `pp_<palette>_` prefix is documented but not enforced. Must be addressed before Phase 7 (sound palettes), which depends on palette switching and lock/auto.
3. **WR-06, a refused newer selection cancels a valid older in-flight one (confirmed: token bumped before load).** Music keeps playing on the old selection, so it is a UX edge, not an outage.
4. **WR-05, a failing `classic` load on re-evaluation leaves the engine half torn down.** Classic is a required file by design and the error is loud; low likelihood because classic files are guarded against edits.
5. **WR-03, guard compares to `HEAD`, so an edit that is committed passes, and a git error fails open (`|| true`).** The guard enforces the rule for the working tree only; fine as a guard rail, not a proof.
6. **WR-04, template text says `state` is shared between arp and lead; it is per role.** Templates are committed files that cannot be edited, so fix the doc in the README or accept; a wrong contract becomes permanent otherwise.

Also noted: the existing smoke check `epic glide up: PulseCount did not advance` is flaky (2 of 8 orchestrator gate runs, and once on the unmodified engine). It passed in my run. It predates this phase and is a risk to the "standing exit gate" being reliable.

## Human Verification Required

### 1. Rider listening check (D-01, D-06) from Plan 04-06

**Test:** Evaluate `supercollider/main.scd` in the SuperCollider IDE exactly as always, then run `./run.sh`. Listen for a minute; move the BPM slider, press Stop then Start, click a few effort zones, move volume. While playing, run `.venv/bin/python -c "from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/melody', 'classic_lead')"`, hear the shimmer from the next bar, press Stop (everything incl. shimmer goes quiet), Start, then send the same with `'classic'`.
**Expected:** Same groove and loudness as the shipped v1.0 engine; classic_lead only adds a soft octave-up thickening of the arp; `classic` removes it.
**Why human:** Perception. Event parity proves identical notes, amps and routing but not how it sounds on the real device. No executor performed it; it stays open until the rider answers in UAT.

### 2. Triage WR-01 / WR-02 (and optionally WR-03/04/06)

**Test:** Decide per warning: fix now via `/gsd-plan-phase 4 --gaps`, defer to a named later phase (WR-02 before Phase 7), or accept.
**Expected:** Dispositions recorded in `04-REVIEW-DISPOSITION.md` (currently all `open`).
**Why human:** Scope judgment about how strictly LIB-04 should be read.

## Gaps Summary

No must-have truth failed. No gap closure is required for the phase goal as specified. The phase is not `passed` because the rider's listening check is still open and because the review's hardening warnings are untriaged.

---

_Verified: 2026-10-11_
_Verifier: Claude (gsd-verifier)_
