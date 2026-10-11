# Project Research Summary

**Project:** PedalPulse
**Milestone:** v2.0 Living Music (additions on top of the shipped v1.0 engine)
**Domain:** Generative melodic techno / progressive trance engine in SuperCollider, with a send-only Tkinter control app
**Researched:** 2026-10-11
**Confidence:** MEDIUM-HIGH

## Executive Summary

v2.0 turns the fixed six-layer A-minor loop into a generative engine that changes harmony, melody, sound and arrangement over a 60+ minute ride. Genre practice: the drum grid stays fixed; variety comes from slow changes on 8/16/32-bar boundaries. Chords move every 1-2 bars and all pitched parts follow; melodies are short motifs that repeat then mutate; sections (groove, breakdown, build, drop) give the "new idea" cadence. No random generation at any level.

Approach: (1) zero new dependencies, all stock SuperCollider 3.14.1 plus Python stdlib and the existing python-osc 1.10.2. (2) Modular engine: `main.scd` keeps the core (clock, buses, EPIC FX, limiter, OSC, transport); musical content lives in library files under `supercollider/library/<category>/`, each evaluating to one side-effect-free Event. A memoized per-bar plan, keyed by absolute bar index, is what every layer pulls from, so harmony is a pure function of musical time with no mutable "current chord". (3) Send-only Python app lists the library folder from disk and sends `auto` or a file stem over OSC.

Main risks are in the SC integration: `nowExecutingPath` is nil inside `waitForBoot` routines; library files that bypass `out`/`group`/`gate`/`amp` break limiter, Stop and levels; Pbindef swaps and merges drift out of phase; routines not stopped in teardown stack on re-evaluation. Each has a known prevention. The build order puts the contract and validation harness first. Because the rider is not an SC user, Claude authors all library files, so lint (`library_test.scd`) is the safety net.

## Key Findings

### Recommended Stack

v2.0 adds zero dependencies. Verified on SC 3.14.1 headless: `String:load` returns the file's last expression and the loaded file sees its own `nowExecutingPath`; `Pbindef` key swaps apply at the next event, and `Pbindef(name).quant = 4` moves them to the bar line; `\degree`/`\scale`/`\root`/`\octave` on the default `\note` event give chord-driven MIDI; `Array.wchoose`, `Pwalk`, `Pwrand`, `Pxrand` cover weighted and motif choices; `thisThread.randSeed` gives determinism; OSC string args arrive as `Symbol` (use `msg[1].notNil` then `asSymbol`; never `isSymbol`/`isString`).

Not stock, do not plan around: `MarkovSet`, `Pmarkov`, `Pdegrees`, `Pchoose`. Use a transition Dictionary with `wchoose`.

- SC 3.14.1 stock classes (`String:load`, `Pbindef`, `Pdefn`, `Pfunc`, `Pwalk`, `Pwrand`, `Routine`, `TempoClock`): all mechanisms, no quarks.
- `pathlib` and `tkinter` `OptionMenu`: scan and selectors.
- python-osc 1.10.2 `SimpleUDPClient`: unchanged; strings pack as OSC `s`.

Operational: keep `unset QT_QPA_PLATFORM` in smoke tests (offscreen aborts sclang 3.14.1 on macOS, exit 134). Every new Routine (harmony, structure, rotation, motif mutator) needs stop-and-nil in the teardown block.

### Expected Features

Must have (table stakes):
- Shared progression driving bass, arp, pad and lead, changing every 1-2 bars.
- 6 launch progressions (4-8 chords, stored as degrees), cycling every 16-32 bars.
- Chord-following arp with 3-4 patterns switched every 4-8 bars; pad voice-leading (nearest inversion).
- Evolving lead: motif from chord tones, repeat, then mutate; replaced about every 16 bars; chord tones on strong beats, stepwise, about 1.5-octave range.
- Phrase-aligned structure: 8/16/32-bar boundaries drive changes; fills on phrase ends.
- Breakdown/build/drop cycle.
- 4-5 named palettes, each loudness-trimmed, rotating at section boundaries, lockable by name.
- EPIC drives density (Recovery sparse, VO2 full), thresholds applied only on bar lines.
- Library files never overwritten; name = filename = GUI label = OSC string.
- 60+ minute stability (ENG-03) with node, CPU and plan-count checks.

Should have (differentiators): reactive riser/fill on EPIC zone change (add after density is stable); EPIC shapes structure (shorter breakdowns at high EPIC, rare drops at Recovery); seeded melodies with seed printed to post window; probabilistic density; key lift, call-and-response, VO2 second voice, melody presets (defer until the rider asks).

Defer (v2.x+): chord substitutions and Dorian/mode scales; .zwo-driven EPIC; Zwift integration; EPIC fine-tune slider (CTRL-01); configurable ramp (CTRL-02); restart resync (W2).

Anti-features (do not build): random scale notes; Markov/ML melody; random change timing; randomised drums; long kick-less breakdowns at high EPIC; live-coding or musical sliders; engine-to-GUI "now playing" (dropped 2026-10-10); file watcher or hot-reload; editing old library files; a song ending.

### Architecture Approach

Core owns clock (sole tempo writer stays `~ppRampStepper`), buses, EPIC FX, master, limiter, transport, all OSCdefs, and the conductor. The conductor is one persistent Event plus one Routine on `~clock`; once per bar it builds `plan(bar+1)`: read-only Event with chord, scale, phrase position, section, density, `layersOn`, and resolved palette/progression/melody modules. Each layer is a permanent Pbindef with content `Pn(Plazy { render bar from ~ppPlanFor.(bar) })`. Seven fixed layer names in `~ppLayers`: `kick hat clap bass arp pad` plus new `ppLead`. Layers pull the plan at their own event beat. Selections are requests: OSC handlers validate and write `~ppSel`; the change applies at plan time, 1-2 bars later.

Library contract: a file evaluates to one Event. Progressions: `desc`, `mode`, `chords` as degrees with `bars`. Melody styles: `init` and generators `{ |plan, state| -> [[note, dur, amp, legato], ...] }`, durations summing to 4 beats; engine seeds per (song seed, bar, role). Palettes: `desc`, optional `defs` run on prepare (not load), `roles` mapping to `pp_<palette>_<role>` SynthDefs. Core forces `out` and `group`, injects `amp` trims. Loader registers each file under its stem, never an in-file name.

New files: `core/loader.scd`, `core/validate.scd`, `core/conductor.scd`, `core/arrange.scd`, `core/render.scd`, `library/{palettes,progressions,melodies}/` (each with `classic.scd` and `_template.scd`), `library_test.scd`. Python: `library_scan.py`, `library_logic.py`.

Components:
1. Core `main.scd` (clock, buses, FX, master, transport, OSCdefs; captures `~ppRoot` on lines 1-5)
2. `core/loader.scd` (registry `~ppLib[category][stem]`, safe load, validation, lazy ensure, reload)
3. `core/conductor.scd` (selections, rotation, section machine, memoized plan)
4. `core/render.scd` (per-layer renderers, fit-to-bar, try-wrapped, falls back to `classic`)
5. Library modules (pure data plus generators)
6. Python scan and controller mirroring `PlayController`

### Critical Pitfalls

1. **`nowExecutingPath` nil inside `waitForBoot` and callbacks.** Capture `~ppRoot` once at top of `main.scd`; absolute paths only; no `loadRelative` in routines.
2. **Library files bypass invariants** (`Out.ar(0,…)`, no `gate`, no `doneAction: 2`, missing `\amp` so default 0.1 overrides SynthDef). Core injects `out`, `group`, `amp` after file keys; validate controls `out freq amp gate` after `s.sync`; Stop must leave zero children in `~ppInstrGroup`.
3. **Layers reading a mutable chord at different times.** Harmony is a pure function of absolute bar index; layers pull `plan(bar)` at their own beat; no shared `~chord`.
4. **Pbindef swaps/merges drift out of phase.** One permanent Pbindef per layer; scene changes on bar-aligned boundaries; `quant = 4`; never rely on merge (missing keys persist); fills are overlays, not restores.
5. **Routines escape Stop and stack on re-evaluation.** One registry iterated by Start, Stop and teardown; conductor on `~clock` only; check live Routine/Tdef count after 3 re-evaluations.
6. **Loudness jumps and CPU growth.** Per-palette trim with RMS audit (within ±1.5 dB at EPIC 30 and 75); FX stays in `\ppFx`; palettes set parameters, never persistent synths; CPU budget checked at VO2 with densest palette.
7. **Name drift Python vs SC.** Stem is the identity, regex `^[a-z0-9_]+$`, `auto` reserved; engine validates, ignores unknown with a warning, keeps paths inside the library root.
8. **Smoke runtime blow-up.** Tiers: lint (every run), canary audio (fixed subset), full audit (on demand). Separate files, not the 1,920-line block; watchdog derived from work; keep the 67 existing checks.

## Implications for Roadmap

7 phases (build order from ARCHITECTURE, FEATURES mapped on). Each ends with the full smoke suite green.

### Phase 1: Core split, loader and contract (behaviour-preserving)
**Rationale:** everything depends on the file contract and plan schema; must not change the music.
**Delivers:** `core/` split; `~ppRoot` capture; loader registry; validators; `classic` palette/progression/melody reproducing v1 exactly; per-bar Plazy rendering; plan with static chord and stubbed section/density; `\ppLead` as silent or classic-arp-doubled; `_template.scd` per category; `library_test.scd` layer 1; headless VERIFY probes.
**Addresses:** modular core; never-overwrite convention; file-stem naming.
**Avoids:** P1, P2, P4, P5, P8, P12, P16, P18.
**Research flag:** short spike (mostly verified): `thisThread.beats` inside Plazy equals bar-start time; `randSeed` reproducibility in Routines.

### Phase 2: Conductor and shared harmony (GEN-01)
**Rationale:** melody, structure and density all read "the current chord".
**Delivers:** progression expansion; plan.chord, plan.scale, plan.nextChord; bass, pad, arp follow chord; pad voice-leading; `/pp/progression` with lazy ensure and bar-quantized apply. Start with 2-3 progressions, reach the six launch progressions before exit; bass register window MIDI 33-45.
**Addresses:** shared progression; progression library; chord-following arp; voice-leading.
**Avoids:** P3, P17.
**Research flag:** small spike on stateless bar lookup vs plan-ahead, across Stop/Start and tempo glide.

### Phase 3: Palettes, hot-swap and auto rotation with lock
**Rationale:** largest audible variety after harmony; needs loader and plan; load on demand.
**Delivers:** `defs` on prepare then `s.sync`; `pp_<palette>_<role>` naming; voice contract in tests; 2-3 palettes first, grow to 4-5; per-palette trim; `/pp/palette` (`auto` or name); auto rotation at section/phrase boundaries (phrase fallback while sections are stubbed); song-bar timer; shuffle-bag; named = locked; fallback to `classic`, revert after repeated errors.
**Addresses:** palettes; rotation with lock; loudness trim.
**Avoids:** P2, P6, P7, P10, P13, P15.
**Research flag:** measure palette CPU alongside Zwift on the target Mac; RMS audit method; `defs` timing on first selection.

### Phase 4: Python selectors
**Rationale:** depends only on OSC addresses and folder layout; can overlap 2-3.
**Delivers:** `library_scan.py` (pure, sorted, `auto` first, skips dot and underscore files, empty folder gives Auto only); `library_logic.py` (send on real change only; `send_initial`); three `tk.OptionMenu` rows with `takefocus=0`; `osc_client.send_library`; pytest for scan, controller, send path.
**Addresses:** GUI selectors for palette, progression, melody.
**Avoids:** P8, P19, root Up/Down clash.
**Research flag:** skip; mirrors `view.py` and `PlayController`.

### Phase 5: Rule-based melodies and lead
**Rationale:** needs chord/scale plan (Phase 2) and state/seed plumbing (Phase 1).
**Delivers:** motif generator (chord-tone downbeats, stepwise, one leap then step back, ~1.5-octave range, rests part of motif); mutation schedule (A A A' A, one mutation per repeat, return to original, new motif ~every 16 bars); three melody styles; `/pp/melody`; seeds logged; language-only metrics (range, chord-tone ratio, repeat ratio 20-80%, distinct motifs).
**Addresses:** evolving lead; seeded melody; melody style library.
**Avoids:** P9; lead/arp masking (lead an octave above arp or thin arp when lead plays).
**Research flag:** rule parameters need listening UAT; FEATURES numbers are starting values.

### Phase 6: Song structure and EPIC density (GEN-02, GEN-03)
**Rationale:** reads everything else; replaces stubs without changing earlier contracts.
**Delivers:** section machine (groove, breakdown, build, drop; 8-32 bars, EPIC-scaled); fills on phrase ends and build bars; density 0-1 = EPIC x section, per-layer thresholds with hysteresis (leave below X minus 10), evaluated only on bar lines; amp ramps over a beat; precedence rule (manual EPIC wins at next bar line, may shorten section); pulse floor (kick and bass always present); palette rotation lands on real section boundaries.
**Addresses:** breakdown/build/drop; fills; EPIC density; EPIC shapes structure.
**Avoids:** P5, P11, P14.
**Research flag:** design decisions (EPIC-to-density curve, section lengths, precedence rule); listening UAT per zone.

### Phase 7: Soak and authoring polish (ENG-03)
**Delivers:** accelerated soak (180 BPM, 4-bar rotation, forced fills, 2-3 min) checking node, group, SynthDef, plan counts; 60-second health log (CPU, nodes); documented `CmdPeriod` recovery; on-demand `scripts/library_audit.sh` stop-cleanliness per file; README "how to add a library file"; real 60-minute ride as final ENG-03 check.
**Avoids:** P6, P12, P20.
**Research flag:** partly; real ride needs the user; CPU budget (proposed average under 25%) needs calibration with Zwift running.

### Phase Ordering Rationale

- Contract and loader first; a later contract change breaks never-overwrite.
- Harmony before melody and structure: one source of "current chord".
- Palettes before melodies: loader-only dependency, highest payoff per line, proves fallback/revert on simple content.
- Structure and density last: read everything, replace stubs.
- Python selectors overlap 2-3; no engine state.

### Research Flags

Needs deeper work: Phase 2 (same-beat ordering); Phase 3 (CPU and loudness on the Mac; `defs` timing); Phase 5 (melody parameters; listening UAT); Phase 6 (EPIC-to-density curve, section lengths, precedence); Phase 7 (real-ride soak, CPU calibration).

Standard patterns: Phase 1 (verified SC behaviour; only cheap VERIFY probes); Phase 4 (mirrors v1 code).

## Resolved Disagreements Between Research Files

| Topic | Disagreement | Resolution |
|-------|--------------|------------|
| GUI selector | STACK: `ttk.Combobox(state="readonly")`. ARCHITECTURE/PITFALLS: `tk.OptionMenu`, `takefocus=0`, since Combobox clashes with root Up/Down BPM keys. | Use `tk.OptionMenu`, `takefocus=0`. Combobox only as fallback. |
| Harmony as function of time | STACK: stateless `chordAt(beats.div(4))` or `next` slot. ARCHITECTURE: memoized `plan(bar)`. PITFALLS: pure function of time. | All agree on the principle: pure function of absolute bar index, no shared mutable chord. ARCHITECTURE's plan implements it; STACK's stateless lookup fits inside. Mechanism settled by Phase 2 spike. |
| Layer names | STACK: keep fixed names. ARCHITECTURE/FEATURES: add `\ppLead`. | Keep six v1 names, add `\ppLead` as seventh in `~ppLayers`. No per-section Pdefs. Update smoke expected sets. |
| Folder names | PROJECT: `<category>/`. ARCHITECTURE: `palettes/ progressions/ melodies/`. PITFALLS: `palette/`. | Plural per ARCHITECTURE. |
| Auto keyword | STACK: "Auto". ARCHITECTURE/PITFALLS: lowercase `auto`, reserved. | Wire `auto` (reserved); GUI label `Auto`. |
| Name rules | STACK: spaces allowed ("Dark Pad"). ARCHITECTURE/PITFALLS: `[a-z0-9_]+`. | Strict `[a-z0-9_]+` stems; GUI may prettify labels only. |
| Lock | STACK: `/pp/palette_lock`. ARCHITECTURE: no lock message. | No lock message. `auto` = rotate; named = locked. |
| SynthDef loading | STACK: `.add` at boot. ARCHITECTURE: `defs` on prepare. | Prepare on demand. Boot-time adds don't scale; a broken file could stop boot. |
| Smoke placement | STACK: extend `smoke_test.sh`. ARCHITECTURE/PITFALLS: separate files. | Separate `library_test.scd` and suites run in sequence; do not extend the 1,920-line block. |
| Counts | FEATURES: 4-5 palettes, 6 progressions at launch. ARCHITECTURE: 2-4 palettes, 2-3 progressions early. | Incremental: 2-3 first, FEATURES counts before milestone exit. |
| Rotation timing | FEATURES: at breakdown or 32/64-bar boundary. ARCHITECTURE: 128-256 song-bar timer, section boundary within 16 bars, else phrase. | Use ARCHITECTURE's policy; tune by ear. |

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Empirically verified on installed SC 3.14.1 and project venv; 0 quarks. |
| Features | MEDIUM | Genre conventions from blogs and course outlines, not standards; numbers are starting values; EPIC-to-structure is judgement. |
| Architecture | MEDIUM-HIGH | From reading shipped code; several VERIFY items later confirmed by STACK (load return value, nowExecutingPath, Symbol args, randSeed, quant). |
| Pitfalls | MEDIUM | Integration pitfalls high confidence; some SC details are known behaviour marked verify. |

**Overall confidence:** MEDIUM-HIGH. SC mechanics largely verified; remaining uncertainty is musical quality and CPU on the rider's Mac.

### Gaps to Address

- Same-beat ordering between harmony and layers across Stop/Start and tempo glide: Phase 2 spike.
- `Pbindef(name).quant = 4` surviving `doReset: true` on Start: check in Phase 1.
- Per-(song, bar, role) seeding inside Plazy and Routines: confirm in Phase 1.
- `thisThread.beats` inside Plazy equals bar-start time: smoke check, 32 events per layer.
- CPU and node budget on the Zwift Mac: record `s.avgCPU`, `s.numSynths`, `s.numGroups` in the ENG-03 run; 25% is a proposal.
- Loudness ±1.5 dB is a proposal; choose reference palette and EPIC levels in Phase 3.
- EPIC vs section precedence: confirm with the user before Phase 6 planning.
- Melody and progression quality: listening UAT per phase.
- Restart resync (W2): out of scope unless reported; "resend on Start" is a cheap mitigation.
- Remaining VERIFY: `SynthDef.add` visibility after `s.sync`; multi-key Pbindef with `Pseq` of arrays and `\rest` in column one; running synth behaviour after same-name re-add.

## Sources

### Primary (HIGH confidence)
- Local SC 3.14.1 headless verification 2026-10-11 (STACK.md)
- Project venv verification (Python 3.13, Tk 9.0.3, python-osc 1.10.2)
- Shipped code: `supercollider/main.scd`, `smoke_test.scd`, `scripts/smoke_test.sh`, `python_app/*`; `.planning/PROJECT.md`

### Secondary (MEDIUM confidence)
- SC docs: Pbindef, Pdef/EventPatternProxy, Quant, Process, SynthDef, Environment
- Genre references: Sample Focus, Native Instruments, Futureproof Music School, WA Production
- Computoser; arXiv 1412.3079

### Tertiary (LOW confidence)
- Elektronauts forum; 2007-2009 sc-users threads on `nowExecutingPath`; geosurge.ai article; Endel/Computoser comparison (own knowledge)

---
*Research completed: 2026-10-11*
*Ready for roadmap: yes*
