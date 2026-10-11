# Feature Research

**Domain:** Generative melodic techno / progressive trance engine for a 60+ minute interval-workout soundtrack (milestone v2.0 Living Music)
**Researched:** 2026-10-11
**Confidence:** MEDIUM. Genre conventions (progressions, 8/16/32-bar phrasing, layer-by-layer builds) agree across several production sources and common practice, but those sources are blogs and course outlines, not authoritative standards. The motif-mutation rules are backed by a published rule-based system (Computoser). The workout-specific recommendations (how EPIC should shape structure) are my own design judgement, not from any source. Treat all numbers as starting values to be tuned by ear.

Scope note: this covers only the NEW v2.0 features. The v1.0 six-layer loop, BPM glide, Start/Stop, EPIC brightness chain and master limiter already exist and are not re-researched.

## How long-form variety is actually achieved (the mechanism)

Generative dance music does not get variety from randomness. It gets it from layered timescales of slow change over a fixed groove:

| Timescale | Typical length | What changes | Why it works |
|-----------|----------------|--------------|--------------|
| Step / beat | 1/16 note | Ghost hats, arp accents, rests | Keeps the groove alive; no one notices it consciously |
| Bar | 1 bar | Chord (harmony) | Gives the "journey" feel; all pitched parts move together |
| Phrase | 4 bars | Arp pattern variant, melody repeat vs mutate | Small, predictable change |
| Phrase group | 8 bars | Hat pattern switch, layer toggle, small fill at bar 8 | The classic "something new every 8" cadence |
| Section chunk | 16 bars | New motif, new progression, new layer enters | Main perceived "new idea" cadence |
| Section | 32-64 bars | Breakdown / build / drop, palette rotation | The "song" arc. About 1 min at 124 BPM per 32 bars |

The drums stay almost fixed (four-on-the-floor kick, offbeat hat, clap on 2 and 4). The hypnotic quality of the genre depends on this, so variety lives in harmony, melody, timbre and layer density, not in the drum grid. Changes that happen on 8/16/32-bar boundaries feel intentional; changes at random moments feel like glitches.

At 124 BPM, 32 bars is about 62 s and 64 bars about 124 s. A 60-minute ride is therefore about 29 sections of 32 bars. With a 96-128 bar "song cycle" (3-4 min) the rider hears roughly 15-20 full arcs per hour. Tempo can change mid-ride (60-180 BPM), so all lengths must be counted in bars/beats on the TempoClock, never in seconds.

## Feature Landscape

### Table Stakes (the rider will say "still the same 5 notes" without these)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Shared chord progression driving bass, arp, pad (and lead) | This is the single biggest fix for the complaint: today bass/arp/pad are independent fixed loops. A genre-correct track moves its chords every 1-2 bars and everything follows. | MEDIUM | One "harmony clock" routine on `~clock`, updated on the bar line (quant 4). Layers read the current chord at event time (Pfunc/Pdefn) instead of owning note lists. Bass = chord root, arp = chord tones, pad = voiced chord. |
| Library of 6-8 progressions, 4-8 chords long, cycle changes every 16-32 bars | One progression repeated for an hour is still repetitive; progression is the main identity of a "song" | LOW per item, MEDIUM for the loader | See "Progressions common in the genre" below. Each progression file: name, chord list as scale degrees, bars per chord. Degrees (not hard-coded notes) so the same file works in any key. |
| Chord-following arp (chord tones, 16ths, with pattern variants) | The existing 16th arp is the most audible "5 notes". Arp over a moving chord is the classic trance sound. | MEDIUM | 3-4 patterns (up, up-down, skip/zigzag, octave-jump). Switch pattern every 4 or 8 bars. Accent and rest mask for groove. |
| Pad voice-leading (nearest inversion, not root-position jumping) | Pads that leap between chords sound amateur and clash with the bass | LOW-MEDIUM | Pick the inversion of the next chord closest to the previous voicing. Small function, big quality gain. |
| Evolving lead/melody: motif repeats, then mutates | Directly requested ("motifs follow the current chord, repeat, then mutate"). A motif that repeats unchanged is just another loop. | HIGH | See "Melody generation" below. Core is a motif data structure plus 4-5 mutation operations, gated by probability and a minimum gap. |
| Melody stays musical: chord tones on strong beats, scale-only pitches, limited leaps | Random notes in a scale sound wrong over changing chords; this is the difference between "generated" and "noise" | MEDIUM | Anchor downbeats and phrase endings to chord tones, mostly stepwise motion, range limited to about 1.5 octaves. |
| Phrase-aligned structure: 8/16/32-bar boundaries drive all changes | Genre convention; unaligned changes feel like bugs | MEDIUM | A single conductor routine counts bars and exposes section, bar-in-section and phrase index. Every other part asks the conductor; none keep their own timers. |
| Fill at the end of 8/16-bar phrases | The audible signpost that a phrase is ending (hat/clap roll, snare build, short break of one layer) | LOW-MEDIUM | 2-3 fill variants, fired on the last bar (or last beat) of a phrase. |
| Breakdown / build / drop cycle | Required by the milestone and by the genre. Without it the hour is one long loop with varying notes. | HIGH | Section state machine: groove, groove+, breakdown, build, drop. See "Section structure" below. |
| EPIC drives layer density (Recovery sparse, VO2 full-on) | Required (GEN-03). Brightness alone (v1) is not enough to feel Recovery vs VO2. | MEDIUM | See density matrix below. Treat EPIC as a continuous value inside the engine and give each layer a threshold. EPIC changes apply on the next bar line, brightness stays immediate via the existing lagged bus. |
| Palettes: named sets of SynthDefs and settings per role | Timbre change is the second most noticeable variety after harmony. Required by the milestone. | MEDIUM-HIGH | A palette maps role to SynthDef and parameters (bass, arp, pad, lead, plus optionally kick/hat/clap flavour and reverb character). 4-5 palettes at launch, each audibly different (e.g. warm/dark/glassy/driving). |
| Auto-rotating palettes with a lock | Required. Rotating at section boundaries masks the swap. | MEDIUM | Rotate on a breakdown or on a 32/64-bar boundary only. New notes use the new SynthDef; sounding notes finish on the old one. Never cut a ringing pad. |
| Per-palette loudness trim | Different SynthDefs have different levels; a loud palette hits the limiter and sounds crushed, a quiet one sounds like the music dropped out | LOW | One `amp` trim per role per palette, balanced by ear once. Limiter stays as the safety net. |
| Auto-or-named selectors in the GUI for palette, progression, melody style | Required. "Auto" = engine rotates; a name = locked. | MEDIUM | New send-only OSC addresses (e.g. `/pp/palette <name|auto>`). Python lists the library folder on disk. Engine ignores unknown names (tolerant, like existing handlers). |
| Library never overwritten, each item a named file | Required: the rider must be able to switch back to any earlier experiment | LOW (convention) | One file per item under `supercollider/library/<category>/`. Name = filename = the shared vocabulary for plain-language feedback. |
| Modular core and module loading without stopping the music | Required; also the precondition for the rider's "Claude writes a new file, I try it" loop | MEDIUM-HIGH | `main.scd` keeps clock, buses, EPIC FX, limiter, OSC, transport. Library files are loaded by a loader and register themselves in a dictionary. Must be safe to re-evaluate (v1 already preserves transport state). |
| Long-session stability (ENG-03) | A conductor plus several Routines running for 60+ min is where leaks appear | MEDIUM | No new Routine per section without stopping the old one; per-note voices use `doneAction: 2`; node and CPU count checked in the smoke test. |

### Differentiators (valuable, not strictly required)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Reactive transition on EPIC zone change | Interval workouts mean the rider presses a zone button right at the interval start. A short riser or fill at the next bar line when EPIC goes up (and a thinning when it goes down) makes the music feel like it is responding to the workout. | MEDIUM | Depends on the density matrix and the conductor. A small "lift" fill, one or two bars. Highest-value differentiator for this use case. |
| EPIC shapes the structure, not just the density | Breakdowns are shorter and shallower at high EPIC; Recovery rarely gets a drop. Keeps the arrangement from contradicting the effort being asked. | MEDIUM | A few parameters on the conductor: breakdown length, how many layers are removed, drop frequency, all functions of EPIC. |
| Seeded melody generation, with the seed logged | "Play that melody again" becomes possible; feedback like "the melody at about minute 20 was great" can become a new named melody file | MEDIUM | `thisThread.randSeed` per motif, printed to the sclang post window. Cheap to add if designed in from the start, painful to retrofit. |
| Optional key transposition every few sections (e.g. +2 or +5 semitones, or relative major) | Lifts the whole hour without new content; classic trance "key lift" | LOW-MEDIUM | Only safe if all parts use degrees plus a root note, which the harmony clock design gives for free. Keep bass range fixed by octave folding. |
| Call and response lead (A, A, A', B) | Makes motifs read as phrases rather than loops | MEDIUM | A phrase template over the motif generator. |
| Probabilistic density instead of hard layer on/off | Each layer plays a step with a probability that rises with EPIC, so the arp thins out gradually rather than switching | MEDIUM | Smoother feel on zone change; avoids audible "step" in arrangement. |
| Chord-substitution variants inside a progression (e.g. last bar swaps to V, sus, or a different bass note) | Small harmonic surprise every 16 bars | LOW-MEDIUM | Defer unless the progression library already feels too static. |
| Second lead voice or counter-line (octave or harmony) at high EPIC | Fills the VO2 "full-on" feeling | MEDIUM | After single-lead works. |
| Drum-pattern variants (8-bar hat switch, open-hat accents, extra shaker/ride at high EPIC) | Keeps drums alive without breaking the pulse | LOW-MEDIUM | Drum grid stays four-on-the-floor; only add layers and hat variants. |
| Melodic style presets (arp-led, sparse/long notes, pluck stabs) as library files | The GUI selector for melody style needs at least 3 items to be meaningful | MEDIUM | A melody style = rules (rhythm density, range, mutation probability, motif length). |
| Smoke-test checks for each library item | Catches a broken new file before a ride | LOW-MEDIUM | Extend the existing headless suite: every file in the library loads, registers a name, produces valid notes for N bars. |

### Anti-Features (commonly requested, often problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Fully random melodies (random note from scale each step) | "Generative" seems to mean random | Sounds like noise; clashes with chords; no memorable motif, which is exactly what makes a melody feel like a melody | Motif plus mutation with chord-tone anchoring |
| Markov chain or ML melody generation | Sounds sophisticated | Needs training data, hard to steer with "make it brighter", unreproducible; no gain over simple rules for this genre | Rule-based motif mutation with a seed |
| Random changes at random times | Easy to implement | Breaks the 8/16/32-bar expectation; feels like glitches | All changes quantised to phrase boundaries via the conductor |
| Randomising the drums | More variety | Destroys the steady pulse the rider is pedalling to | Fixed kick/clap, only hat variants and added layers |
| Long kick-less breakdowns at high EPIC | It is the genre's defining move | During a VO2 or Threshold interval the rider is working hardest; losing the pulse for 16+ bars works against the music's job | Scale breakdown depth and length down with EPIC (keep kick at high EPIC, remove only arp/lead; or a 2-4 bar mini-break) |
| Frequent key or progression changes every few bars | Maximum variety | Listener never settles; loses the hypnotic quality | Change progression every 16-32 bars; key lift only every few sections |
| Lead and arp in the same register | Easy default | Masking; both sound muddy | Lead sits at least an octave above the arp, or arp thins out when lead plays |
| Python deciding musical timing or sending per-note OSC | Python already has the GUI | Python is send-only by design, with UDP jitter; musical timing belongs on the sclang TempoClock | Python sends only selection and control messages; all scheduling in sclang |
| Engine-to-GUI "now playing" display (current palette/progression/section) | Useful to name feedback | Explicitly dropped on 2026-10-10 (app stays send-only) | Print to the sclang post window; the rider reads the name there when giving feedback |
| Live-coding or exposing musical parameters as GUI sliders | Feels powerful | The rider is not an SC or music-theory user; many sliders mean many ways to sound bad | Plain-language feedback, Claude writes a new named file |
| File watcher or hot-reload of the library | Convenient | Races with playing Routines; harder to debug | Manual re-evaluate of the loader in the SC IDE (already the established workflow) |
| A song ending or outro | Songs end | A workout soundtrack has no fixed end; an unexpected outro in a hard interval is jarring | Endless cycles; Stop is the only ending |
| Editing old library files to tweak them | Faster | Rider loses the ability to go back; breaks the shared vocabulary of names | Always add a new file (e.g. `Dark2`), leave old ones |
| Many genres or styles | More variety | Out of scope for v2.0 and dilutes the sound | Variety within melodic techno / progressive trance |
| Reverb/delay tails that cross palette swaps | Smooth transitions | Different palettes would share one wash; hard to remove | Keep the global reverb in the existing EPIC FX chain and swap only the source SynthDefs |
| Polyrhythmic or non-aligned loop lengths (Eno-style) | Endless non-repeating music | Clashes with a bar-aligned dance genre and with chord-synchronised parts | Aligned phrase lengths with varied content |

## Genre knowledge needed by the roadmap (concrete starting values)

### Progressions common in the genre (A minor, since v1 is in A minor)

Progressions are minor, use VI/VII/III heavily, and typically move one chord per bar (4-bar cycle) or one chord per two bars (8-bar cycle, "deeper" melodic techno feel). Store as scale degrees so any key works.

| Name idea | Degrees | In A minor | Feel | Bars per chord |
|-----------|---------|------------|------|----------------|
| Anthem | i - VI - III - VII | Am F C G | Uplifting trance staple | 1 or 2 |
| Rocker | i - VII - VI - VII | Am G F G | Driving, rocking | 1 |
| Lift | i - VI - VII - VII | Am F G G | Rising, good for builds | 1 |
| Return | i - III - VII - VI | Am C G F | Wistful, resolves home | 1 |
| Late arrival | VI - VII - i - i | F G Am Am | Starts away, lands on tonic | 1 or 2 |
| Deep | i - i - VI - VII | Am Am F G | Slow, hypnotic melodic techno | 2 |
| Melancholy | i - v - VI - iv | Am Em F Dm | Dark, sad | 1 or 2 |
| Drama | i - iv - VI - V | Am Dm F E | Classic trance tension; E major uses G# (harmonic minor), so the lead and arp scale must adapt on that chord. Use sparingly. | 1 |
| Dorian drone | i - IV | Am D | Hypnotic melodic techno; D major brings F#, so scale for lead/arp is Dorian | 2-4 |

Recommendation: ship the first 6 as launch content, plus Drama as an "advanced" test for per-chord scales. Dorian needs a mode-aware scale and is optional. Source support for i-VI-III-VII, i-VI-VII and i-III-VII-VI is the blog sources below; the remaining rows are common practice from my own knowledge, not individually verified.

### Melody generation and motif mutation

Recommended data model: motif = list of (scale degree offset or chord-relative step, start position in 16ths, duration), length 1-2 bars, 3-8 notes.

Generation rules (new motif):
- First note and last note are chord tones (root, third, fifth); downbeats and the last note of the phrase are chord tones.
- Mostly stepwise motion, an occasional leap of a third to a fifth, followed by a step back.
- Range of about 1.5 octaves; an octave or more above the arp.
- Rhythm drawn from a small set of templates (e.g. syncopated 8ths and 16ths, long-short, dotted), different per melody style.
- Rests are part of the motif; a gap prevents constant lead noise.

Mutation operations (apply exactly one per variation event):
1. Transpose by one or two scale steps (stay in scale)
2. Change the last 1-2 notes (the "ending") while keeping the rest
3. Notes-to-rests (drop a note or two)
4. Octave-lift one note or the whole phrase
5. Rhythm shift (move a note by a 16th)
6. Inversion or retrograde (rare, sounds more "different")

Schedule: play the motif unchanged 2 times, then a mutated version on repeat 3-4; after 16 bars (or at a section change) pick a brand new motif. A published rule-based composer (Computoser) triggers a variation for about 40% of motif occurrences, only after at least two bars, choosing one operation from a list including transposition, inversion, retrograde and notes-to-rests, with pitches kept in scale. Use these as starting values only. Between chords, a motif written in chord-relative terms follows the progression automatically, which is what "motifs follow the current chord" requires.

Keep variation seeded and logged (see differentiators), and limit unrestricted randomness: it gives incoherent music.

### Section structure (breakdown / build / drop)

Typical production structure (techno/trance arrangement guides): intro 16-32 bars, groove/build with layers added every 8 or 16 bars, breakdown 16-32 bars (kick and bass removed, pad/arp/atmosphere remain), build 8-16 bars (clap/snare rolls, filter sweep, riser, rising pitch or density), drop at full intensity for 32-64 bars, repeated. A common tip is switching hat patterns every 8 bars for movement.

Suggested engine cycle (single conductor state machine, lengths in bars, EPIC-scaled):

| Section | Length (mid EPIC) | Layers | Notes |
|---------|-------------------|--------|-------|
| Groove A | 16-32 | Drums + bass + arp + pad | Entry state; progression A |
| Groove B (lifted) | 16-32 | + lead, + extra percussion | New motif, maybe new progression |
| Breakdown | 8-16 (shorter at high EPIC) | Pad + arp or lead; drums reduced or removed at low EPIC; kick kept at high EPIC | Palette rotation happens here, masked by reduced layers |
| Build | 4-8 | Rising filter, clap/snare roll, density rising | Fill on the last bar |
| Drop | 16-32 | Everything the current EPIC allows | New motif or progression |

Since a rider sets EPIC by hand and may change it any time, the conductor must read EPIC at each bar line and be able to shorten or skip a section (e.g. an EPIC jump to VO2 during a breakdown should trigger the build early). That interaction is the main design risk and is flagged in the dependency notes.

### EPIC density matrix (starting point)

| Layer | Recovery (10) | Endurance (30) | Tempo (50) | Threshold (75) | VO2 (100) |
|-------|---------------|----------------|------------|----------------|-----------|
| Kick | Soft, steady pulse | Yes | Yes | Yes | Yes |
| Hat (offbeat) | Off or sparse | Yes | Yes | Yes + variants | Yes + open hat/shaker |
| Clap | Off | Beats 2/4 | Yes | Yes | Yes + roll fills |
| Bass | Long notes on chord roots | Offbeat 8ths | Offbeat 8ths | Offbeat + octave pops | Rolling with octave pops |
| Arp | Off or 8ths, soft | 8ths | 16ths | 16ths + accents | 16ths + accents + octave jumps |
| Pad | Full, long | Yes | Yes | Yes | Yes, brighter |
| Lead | Off or very sparse | Sparse | Regular | Regular | Continuous, plus second voice |
| Fills / transitions | Rare | Every 16 | Every 8-16 | Every 8 | Every 8, short breakdowns only |

Key decision: implement as a continuous density value 0-1 with per-layer thresholds (and ideally per-step probabilities), computed from the raw EPIC value inside sclang, rather than five hard-coded presets. This lets the engine pass through intermediate values during the lagged glide without a hard layer pop. Note that v1 EPIC currently lives only on a control bus; the sclang side needs to keep the raw value too (the OSC handler already has it).

## Feature Dependencies

```
Modular core + library loader (names -> registered items)
    ├──requires──> (existing) ~clock, ~ppInstrGroup, ~ppMixBus, teardown block, Pbindef layers
    └──enables──> Progression library / Palette library / Melody-style library

Shared harmony clock (current chord, per bar)
    ├──requires──> Modular core (needs a place to register progressions)
    ├──enables──> Chord-following bass
    ├──enables──> Chord-following arp
    ├──enables──> Pad voice-leading
    └──enables──> Rule-based melody (motifs are chord-relative)

Conductor (bar counter, section, phrase boundaries)
    ├──requires──> Shared harmony clock (progression changes align to phrases)
    ├──enables──> Fills
    ├──enables──> Motif change every 16 bars
    ├──enables──> Breakdown / build / drop
    └──enables──> Palette rotation at section boundaries

Palettes (role -> SynthDef + params)
    ├──requires──> Modular core
    └──enhanced by──> Conductor (rotation timing)

EPIC density (raw EPIC value in sclang)
    ├──requires──> Conductor (applies on bar lines)
    ├──requires──> Per-layer density thresholds
    └──enhances──> Breakdown depth/length, fills, reactive transitions

GUI selectors (Auto / named)
    ├──requires──> Library folder layout + name registry in the engine
    └──requires──> New OSC addresses and tolerant engine handlers

Long-session stability (ENG-03)
    └──cross-cuts──> everything above; verify after each phase

Aggressive breakdowns ──conflicts──> High-EPIC pulse (kick must stay at VO2)
```

### Dependency Notes

- **Harmony clock before melody and structure:** the lead, arp and bass all need "the current chord" as a single source of truth. Building structure first would mean rewriting it.
- **Modular core before any library item:** the loader and name registry define the file contract; every progression, palette and melody style file depends on it, so changing the contract later breaks the "never overwrite old files" promise.
- **Existing `Pbindef` layers:** v1 layers have hard-coded `\midinote` Pseqs. They need to become state-reading patterns (Pfunc/Pdefn). Remember the v1 note: Pbindef sets no `\amp`, so default event amp 0.1 overrides SynthDef amp unless set explicitly.
- **Existing Stop mechanism:** Stop broadcasts `\gate, 0` to `~ppInstrGroup`. New voices (lead, extra percussion, fills) must be created in that group and use a `gate` control, otherwise Stop will leave hanging notes. Fire-and-forget percussion with `doneAction: 2` is fine.
- **Conductor routines and Start/Stop:** the conductor must stop and start with transport (same `quant: 4`, `doReset` logic), or the bar counter will drift from the audible music after a Stop/Start.
- **BPM glide:** all scheduling is in beats on `~clock`, which is compatible with the glide; avoid `SystemClock` or seconds-based waits in the conductor.
- **EPIC density versus structure (conflict risk):** a breakdown, a drop and a hand-pressed EPIC change can disagree. Define one priority rule: manual EPIC changes win, applied at the next bar line, and may shorten the current section.
- **GUI selectors depend on the library:** Python reads folder names from disk, so file names must be clean identifiers (no spaces needed in OSC strings, but spaces would also work as OSC strings; prefer underscores for safety).

## MVP Definition

### Launch With (v2.0 core)

In build order:

- [ ] Modular core, loader, name registry, safe re-evaluation — everything else lives in it
- [ ] Harmony clock and 6 launch progressions; bass, arp, pad follow the chord; pad voice-leading — fixes the biggest part of the complaint immediately
- [ ] Library of 4-5 palettes, loudness-trimmed, rotating at section boundaries, lockable — second biggest audible change
- [ ] Evolving lead with 3 melody styles (motif generate, repeat, mutate, replace every 16 bars), seeded and logged
- [ ] Conductor: 8/16/32-bar boundaries, fills, breakdown/build/drop cycle with EPIC-scaled depth
- [ ] EPIC density matrix on top of the conductor
- [ ] GUI selectors (Auto or named) for palette, progression, melody style; send-only OSC; list read from disk
- [ ] Smoke-test additions (library load/registration, N bars of valid output) and a 60-minute stability run

### Add After Validation (v2.x)

- [ ] Reactive transition on EPIC zone change — add once the conductor and density are stable and the rider has ridden with them
- [ ] Key lift every few sections — trigger: the rider reports that the hour still feels flat
- [ ] Call-and-response lead, second voice at VO2 — trigger: the rider wants VO2 to feel bigger
- [ ] More palettes/progressions/melody styles from rider feedback — the ongoing "plain-language feedback becomes a new file" loop

### Future Consideration (later milestones)

- [ ] EPIC fine-tune slider (CTRL-01) and configurable ramp time (CTRL-02), already out of scope for v2.0
- [ ] Workout-file-driven EPIC (.zwo) and Zwift integration, already listed in Out of Scope
- [ ] Resync after engine restart (carried v1.0 tech debt W2)

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Modular core + library loader | HIGH (enables all) | MEDIUM-HIGH | P1 |
| Harmony clock + chord-following bass/arp/pad | HIGH | MEDIUM | P1 |
| Progression library (6) | HIGH | LOW | P1 |
| Pad voice-leading | MEDIUM | LOW | P1 |
| Palettes + rotation + lock + loudness trim | HIGH | MEDIUM-HIGH | P1 |
| Rule-based evolving lead | HIGH | HIGH | P1 |
| Conductor + fills | HIGH | MEDIUM | P1 |
| Breakdown/build/drop | HIGH | HIGH | P1 |
| EPIC density matrix | HIGH | MEDIUM | P1 |
| GUI selectors (3) | MEDIUM-HIGH | MEDIUM | P1 |
| Stability check (ENG-03) | HIGH | MEDIUM | P1 |
| Seeded melody + logging | MEDIUM | LOW | P2 |
| Reactive transition on zone change | HIGH | MEDIUM | P2 |
| EPIC-scaled breakdown depth | MEDIUM-HIGH | LOW (once conductor exists) | P2 (design in from the start) |
| Key lift | MEDIUM | LOW-MEDIUM | P2 |
| Probabilistic density | MEDIUM | MEDIUM | P2 |
| Call-and-response, second voice | MEDIUM | MEDIUM | P3 |
| Chord substitutions, Dorian mode | LOW-MEDIUM | MEDIUM | P3 |

**Priority key:** P1 must have for the milestone; P2 should have; P3 nice to have.

## Comparable Systems Analysis

Reference points from my own knowledge, not verified in this research session (LOW confidence).

| Feature | Endel-style adaptive generators | Algorithmic composers (e.g. Computoser) | Our Approach |
|---------|----------------------------------|------------------------------------------|--------------|
| Variety source | Slow parameter drift, no real song structure | Motif plus rule-based variation | Motif mutation plus genre-correct sections |
| Responds to user state | Inputs from sensors and context | None | Manual EPIC and BPM, mapped to density and brightness |
| User control | Little | Little | Auto-or-named selectors plus plain-language feedback becoming new library files |
| Genre fit | Ambient | General | Melodic techno / progressive trance conventions |

## Sources

- [The Most Popular Chord Progressions In EDM (Sample Focus)](https://blog.samplefocus.com/blog/the-most-popular-chord-progressions-in-edm) — progression families (MEDIUM)
- [Native Instruments: EDM chord progressions](https://blog.native-instruments.com/edm-chord-progressions/) — i-III-VII-VI explained (MEDIUM)
- [Futureproof Music School: EDM chord progressions](https://futureproofmusicschool.com/blog/unlocking-the-secrets-of-edm-chord-progressions) — i-VI-VII and i-III-VII-VI for builds and drops (MEDIUM)
- [Computoser: rule-based, probability-driven algorithmic music composition](https://arxiv.org/pdf/1412.3079) — rule-based motif variation operations and probabilities (MEDIUM)
- [Procedural Arrangement Techniques for Generative Music](https://geosurge.ai/corpus/gen-3018/generative-music/procedural-arrangement-techniques-for-generative-music.html) — seeded randomness for reproducible variation (LOW-MEDIUM)
- [WA Production: arrangement blueprints](https://blog.waproduction.com/arrangement-blueprints-10-proven-song-maps-that-just-work) — long-form techno map (32-bar intro, 16-bar breaks, layered grooves) and hat pattern switch every 8 bars (MEDIUM)
- [Elektronauts: simple tips in techno structure](https://elektronauts.com/t/simple-tips-in-techno-structure/151609?page=3) — common 16-bar intro / build / first drop layout (LOW-MEDIUM, forum)
- Existing code: `/Users/marcogiordano/Documents/personali/lab/PedalPulse/supercollider/main.scd` (layers, Pbindef, Stop mechanism, EPIC bus) and `.planning/PROJECT.md` (constraints, decisions)

---
*Feature research for: generative melodic techno / progressive trance workout soundtrack (PedalPulse v2.0)*
*Researched: 2026-10-11*
