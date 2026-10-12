# Phase 6: Shared Harmony & Progressions - Research

**Researched:** 2026-10-12
**Domain:** Generative harmony inside the existing SuperCollider per-bar engine (sclang 3.14.1): a shared chord schedule that bass, arp, pad and lead pull, a chord-follow mapping for frozen melody files, pad voice-leading, cycle-end progression switching and Auto rotation
**Confidence:** HIGH for the engine integration (every seam read this session and the riskiest mechanics probed in real sclang); MEDIUM for the musical parameters (registers, voicing window, pickup rule), which are listening-UAT items

## Summary

Phase 6 needs no new packages and no new Python code. It is a core-engine change plus new library content. The engine already renders one bar per layer with a per-layer `Prout` that knows `songBar` and `bar`, and `~ppPlanFor` is the documented seam for adding optional plan keys. The recommended design is the research "memoized per-bar plan, layers pull" pattern: one memoized harmony schedule, keyed by the run, answers "which progression, which chord, which voicing" for any `songBar`. Every pitched layer pulls the same entry, so no mutable "current chord" exists and the same-beat ordering race (STATE.md spike) cannot occur by construction. The spike was run in real sclang: all seven layers pull the same `(run, songBar)` key, `thisThread.beats` at bar start is exactly a multiple of 4 even through a tempo glide, and the run signature `bar - songBar` is constant within a run and changes after Stop/Start.

Cycle-end switching (HARM-04) falls out of the same design: the schedule reads `~ppSel[\progressions]` only when it plans the *next cycle* (one bar before that cycle starts, because the bass pickup needs the next chord), so a pick can never land mid-cycle. Auto (HARM-02/D-08..D-10) is the same decision point reading `\auto`: start on `classic`, hold each progression 32-64 bars of whole cycles, then shuffle with no quick repeats among every progression loaded from disk. The arp and lead (D-01/D-02) are mapped onto the current chord by the core after the frozen generator returns its rows, using a chord-tone "ladder" so that under the implicit `classic` chord (Am) the mapping is the identity and the v1 rows are untouched. Bass and pad become core default generators that read `plan[\chord]`, so a new progression file is just chord data; `classic.scd` stays frozen and keeps its own generators.

**Primary recommendation:** Add `supercollider/core/harmony.scd` (chord expansion, run-keyed memoized schedule, Auto rotation, nearest-voicing, chord-follow mapping, default bass/pad), extend `~ppPlanFor` with optional chord keys, make `~ppRenderBar` take bass/pad from the cycle's captured module and map arp/lead rows onto the plan chord, extend the validator for chord data, add seven chord-data files plus a chord-follow check, and never use `RandStream` (it hangs headless sclang 3.14.1 here; use `thisThread.randSeed` like the rest of the engine).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Arp and lead under new chords
- **D-01:** When a non-classic progression plays and Melody is `classic` (or any existing melody file written for A minor), **the arp follows the chords**. The engine maps the melody's notes onto the current chord: the classic A3–C4–E4–C4 shape becomes root–third–fifth–third of whatever chord is playing. Under the `classic` progression the result must be note-for-note identical to v1.0. The frozen melody files are **not edited**; the core does the mapping. — **Reversibility:** costly — every later melody file (Phase 8) and the chord-follow smoke check will rely on how chord-relative mapping works.
- **D-02:** The **same rule applies to the lead** (`classic_lead`, `classic_lead_loud`): its notes follow the current chord exactly like the arp's, so nothing pitched ever clashes with the progression.
- **D-03:** Phase 6 changes **only the notes**, not the rhythm or pattern. The arp keeps its 16th-note shape. New arp patterns stay in Phase 8 (MEL-02).

#### Progression content
- **D-04:** The first progressions are a **broad trance mix**: mostly uplifting and driving (the research list's Anthem i–VI–III–VII, Rocker i–VII–VI–VII, Lift i–VI–VII–VII, Return i–III–VII–VI), plus at least one deep/hypnotic one (e.g. Deep i–i–VI–VII) and one dark/melancholy one (e.g. Melancholy i–v–VI–iv). At least 6 named files plus `classic`. Each must sound clearly distinct (the "variations must be audible" rule).
- **D-05:** **Drama (i–iv–VI–V, Am Dm F E) ships too**, with the E **major** chord (G#). The chord data must therefore carry each chord's actual notes, not just "a degree of A minor". The arp and pad play the G# on that chord. Phase 8's lead will need per-chord scales because of this; the plan should expose enough chord information (actual pitch classes per chord) for that.
- **D-06:** **Chord pace is set per file**: driving progressions change chord every bar (4-bar cycle), deeper ones every 2 bars (8-bar cycle). Pace is part of what makes files sound different.
- **D-07:** **Everything plays in the key of A**, as in v1. Progression files are written relative to the key (key-independent), and the engine supplies the key root A. Switching progressions never jumps key. Key lifts stay deferred (HARM-05).

#### Auto behaviour
- **D-08:** On Auto, one progression plays for **about 2–3 minutes** (a few complete cycles, roughly 32–64 bars at ride tempos), and the change always lands **at the end of a cycle**, never mid-cycle.
- **D-09:** **Start on `classic`, then rotate.** On Auto the first progression is `classic` (familiar opening; all-classic still sounds exactly like v1.0), then Auto moves on to the others. `classic` stays part of the rotation.
- **D-10:** Auto picks the next progression by **shuffle with no quick repeats**: random, but never the current one or the last couple played. Any new progression file in the library joins the rotation automatically, with no list to maintain.
- **D-11:** Each progression change (Auto or manual) **prints a post-window line naming the progression and its chords** (e.g. `progression anthem: Am F C G`), so the rider can name what they heard when giving feedback. The app stays send-only.

#### Bass and pad
- **D-12:** The bass keeps the **v1 rolling offbeat-eighths rhythm**, now on each chord's **root**. Bass variety (rolling 16ths, octave pops) belongs to palettes and density (Phases 7 and 9), not to progression files.
- **D-13:** Like v1's C on the last eighth of the bar, the bass plays a **pickup note on the last eighth before a chord change that steps toward the next chord**. When the chord doesn't change, it plays whatever the planner judges to fit v1's feel. Under `classic` the bass must stay exactly v1 (A1 ×3, C2 at the bar end).
- **D-14:** The pad **holds each chord for as long as the chord lasts** (2 bars on a 2-bar chord), using the voicing nearest the previous chord (HARM-03). It re-attacks only when the chord changes. Under `classic` the pad must stay exactly v1 (Am / Am with passing F, one per bar).

### Claude's Discretion
- **Data shape of a progression file:** follow `.planning/research/ARCHITECTURE.md` "Progression" (chords as key-relative roots plus quality or explicit intervals, bars per chord), adjusted so out-of-key chords like Drama's E major are representable (D-05). Planning decides whether bass/pad stay per-file generators reading `plan[\chord]` or become core defaults that progression files can still override. Either way the existing generator contract (`{ |plan, state| }` → rows) and the validator must keep accepting the frozen `classic.scd`, which has no chord data.
- **`classic` progression's chord:** `progressions/classic.scd` is frozen and has only bass/pad generators. The core must treat it as "Am every bar" (implicit chord data supplied by the core, or an equivalent) so arp/lead mapping (D-01) is the identity under classic.
- **How notes are mapped onto chords (D-01/D-02):** e.g. interpret notes relative to Am (the key chord) as chord-tone positions and re-voice them on the current chord in the same register. Notes that are not Am chord tones (passing tones) need a sensible rule. Planning picks the rule; the bar is "no clashes, and identical to v1 under classic".
- **Same-beat ordering:** STATE.md flags a spike on harmony-vs-layer ordering at the same beat across Stop/Start and tempo glide. Follow the research "memoized per-bar plan, layers pull" pattern (no mutable current-chord variable), and include that spike.
- **Cycle-end switching:** a named pick waits for the current cycle's end (HARM-04). The longest cycle should stay short enough for auditioning (about 8 bars, ≈15 s at 128 BPM; flag it if a file is longer). How `auto` interacts with the Phase 4 `~ppSelect` code (which today posts "resolves to classic") is the planner's call.
- **Progression file names:** lowercase stems in the research spirit (`anthem`, `rocker`, `lift`, `return`, `deep`, `melancholy`, `drama`). Final names are up to the planner, within the stem rule `^[a-z0-9_]+$`.
- **Exact Auto timing:** "a few cycles ≈ 2–3 minutes", counted in song bars so Stop pauses it. Jitter is optional.

### Deferred Ideas (OUT OF SCOPE)
- Files choosing their own key: rejected for now. Everything stays in A; key lifts remain HARM-05.
- Per-progression arp shapes or bass rhythms: rejected for this phase. Arp patterns are Phase 8 (MEL-02); bass variety goes with palettes and density (Phases 7 and 9).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HARM-01 | Music follows a chord progression. Bass, arp, pad and lead always play over the same current chord, with no clashes at chord changes (GEN-01) | Run-keyed memoized harmony schedule that every pitched layer pulls (spike-verified, see "Spike results"); chord-follow mapping for arp/lead (verified prototype, identity under Am); default bass/pad read `plan[\chord]`; chord-follow check in library_test |
| HARM-02 | At least 6 named progressions plus `classic` ship in the library | Seven chord-data files (anthem, rocker, lift, return, deep, melancholy, drama) with verified chord math; data-only file shape; validator + static check + template; Auto rotation picks up every loaded file |
| HARM-03 | Pad chords move smoothly between chords (voice-leading) instead of jumping | `nearestVoicing` (verified prototype outputs for all seven progressions), computed inside the in-order schedule so it is deterministic across Stop/Start; pad holds a chord across its whole length |
| HARM-04 | User can select a progression (Auto or a named one). Changes take effect at the end of the current progression cycle | The schedule reads `~ppSel[\progressions]` only when planning the next cycle (simulated: pick at bar 70 landed at the cycle boundary at bar 74); `~ppSelect` wording changes; Auto uses the same decision point |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

Extracted from `/Users/marcogiordano/Documents/personali/lab/PedalPulse/.claude/CLAUDE.md` and the memory index:

- Platform macOS, same machine as Zwift: the engine must stay light. Schedule work is once per bar, not per note; prune the memo.
- Audio engine is SuperCollider with **stock JITLib/Pattern classes only; no quarks**.
- Python app stays minimal and **send-only**; no engine-to-GUI channel. Phase 6 needs **no Python changes** (new files appear in the Progression dropdown automatically, Phase 5).
- Protocol is OSC over UDP to sclang port 57120; `/pp/progression <string>` is a frozen address and argument shape.
- SuperCollider patch lifecycle is the user's; the Python app only connects.
- Testing approach: headless `sclang -D` scripts (no `QT_QPA_PLATFORM=offscreen`; it aborts sclang 3.14.1 with exit 134 per the repo's own notes), driven by `scripts/check.sh`.
- GSD workflow: file edits happen through a GSD command (this research writes only the RESEARCH.md).
- Memory preferences: keep the app simple (minimal scope); the user is not an SC musician and judges by ear in plain words, every variation is a new library file; variations must be clearly audible (a faint variation counts as a failure).
- Committed library files and the golden are never edited; `scripts/check.sh` guards against `HEAD`.

## Architectural Responsibility Map

This is an audio engine, not a web app, so the generic tiers are mapped to this project's real tiers.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Progression choice UI (Auto or a name) | Python GUI (Phase 5, unchanged) | - | Dropdowns already list `supercollider/library/progressions/*.scd` stems and send `/pp/progression`; no change |
| Name validation and path safety | sclang core (`loader.scd`) | - | `~ppStemValid`, `~ppLibContained`, `~ppLibLoad`; Auto's folder scan must reuse them |
| Chord schedule, cycle-end switching, Auto rotation, voicing | sclang core (new `core/harmony.scd`) | - | Must be core state: only the core sees all layers, the selection and the bar grid |
| Chord data (what the chords are) | Library files (`library/progressions/*.scd`) | core expands and validates | Content grows by adding files; files are data plus pure functions |
| Bass and pad note choice | Core default generators | Library file generator override | D-12/D-14 behaviour is identical for every chord-data file, so it belongs in the core; `classic.scd` keeps its own |
| Arp and lead chord-follow mapping | sclang core (`render.scd`) | Melody file opt-out | Frozen melody files cannot change (D-01); the core re-voices rows after the generator returns |
| Rendering, timing, Stop/Start | sclang core (`render.scd`, `main.scd`) | - | Unchanged: per-bar `Prout` on `~clock`, `quant 4` |
| Regression gate | Headless test scripts (`library_test.scd`, `smoke_test.scd`) | `scripts/check.sh` | Chord-follow, cycle-end, Auto, Stop/Start checks live here |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SuperCollider (sclang/scsynth) | 3.14.1 [VERIFIED: `sclang -v` this session printed `sclang 3.14.1 (Built from tag 'Version-3.14.1' [426edf6])`] | The engine; everything in this phase is sclang code | Project constraint; already installed at `/Applications/SuperCollider.app` |
| Stock sclang classes: `Pbindef`, `Prout`, `TempoClock`, `Event`, `Dictionary`, `thisThread.randSeed` | 3.14.1 | Per-bar rendering, run-keyed memo, deterministic randomness | Already the engine's mechanism (Phase 4); no quarks per CLAUDE.md |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| pytest (existing venv) | already installed | Confirm the Python side is untouched (`test_library_logic.py` scans the real folder) | Run once at the phase gate; no new Python tests expected |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Core default bass/pad generators reading `plan[\chord]` | Each progression file ships its own bass/pad generators | Seven files would each duplicate the same rhythm and pickup logic; any v1 bass-feel fix would need seven new files. Keep generators as an optional per-file override (it is what `classic.scd` already is) |
| `thisThread.randSeed` for Auto | `RandStream` | `RandStream(\xoroshiro128plus, 1234)` never returned in headless sclang 3.14.1 here (see Pitfall 6); `thisThread.randSeed` is already the engine's pattern |
| Run signature inferred from `(clock, bar - songBar)` | Explicit reset in `~ppStart` only | The test recorder (`recordBars`) restarts layers on fresh private clocks without calling `~ppStart`; the inferred signature makes the memo self-correcting. Do both (explicit reset in `~ppStart` and teardown, signature as the safety net) |

**Installation:** none. No packages are added to Python or SuperCollider.

**Version verification:** `sclang -v` confirmed 3.14.1. No registry packages are involved.

## Package Legitimacy Audit

No external packages are installed or recommended in this phase (stock SuperCollider classes only, per CLAUDE.md "no quarks"; no Python changes). The audit table is not applicable.

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
 GUI dropdown / OSC /pp/progression <auto|stem>
            |
            v
  ~ppSelect  (validate stem, load file in a background Routine, THEN set ~ppSel[\progressions];
              'auto' sets \auto and kicks the Auto prefetch scan)
            |  (nothing is applied here; ~ppSel is only read at cycle planning)
            v
  ~ppSel[\progressions]  --------------------------------------+
                                                                | read ONLY when a new cycle is planned
 layer Prouts (bass, arp, pad, lead pull; drums do not)         v
   each bar start: bar = floor(thisThread.beats/4)     ~ppHarmonyFor(bar, songBar)
                   run signature = [thisThread.clock, bar - songBar]
                         |                                  |
                         |   new signature? -> new run: clear memo, Auto restarts at classic
                         |   cycle for songBar+1 not planned yet? -> decide stem
                         |       sel named -> that stem (if loaded)
                         |       sel auto  -> hold current N cycles, else shuffle (no quick repeats)
                         |   expand chords (cached per module rev), merge adjacent identical chords
                         |   compute voicing in order (previous voicing -> nearest voicing)
                         |   log "progression <stem>: Am F C G" when a cycle of a NEW stem starts
                         v
                  harmony entry for songBar  (memoized; all layers get the SAME entry)
     (stem, mod, chord, nextChord, chordBar, chordBars, cycleBar, cycleLen, voicing, bassRoot, ...)
                         |
        +----------------+--------------------+--------------------+
        v                v                    v                    v
   bass: mod[\bass]   pad: mod[\pad]     arp rows (melody gen)  lead rows (melody gen)
   or core default    or core default    -> ~ppFollowChord      -> ~ppFollowChord
   (root, pickup)     (voicing, hold)    (identity under Am)    (identity under Am)
        \________________\___________________/_____________________/
                                 |
                       ~ppRowsValid check, try/fallback to classic (unchanged)
                                 |
                  Pbindef -> Synth(\out ~ppMixBus, \group ~ppInstrGroup) -> limiter
```

### Recommended Project Structure
```
supercollider/
├── main.scd                 # MODIFIED: load core/harmony.scd; reset harmony on teardown and in ~ppStart
├── core/
│   ├── validate.scd         # MODIFIED: progression chord-data validation (still accepts classic.scd)
│   ├── loader.scd           # MODIFIED: ~ppSelect wording for progressions + Auto prefetch hook
│   ├── harmony.scd          # NEW: chord expansion, schedule memo, Auto, voicing, follow mapping, default bass/pad
│   └── render.scd           # MODIFIED: ~ppPlanFor optional harmony keys; ~ppRenderBar uses the entry
├── library/progressions/
│   ├── classic.scd          # FROZEN
│   ├── _template.scd        # content change allowed (not selectable, outside the guard)
│   └── anthem rocker lift return deep melancholy drama .scd   # NEW, chord data only
├── library_test.scd         # MODIFIED: core load list, static chord checks, chord-follow tier
├── smoke_test.scd           # MODIFIED: core load list in the module re-evaluation check, engine-level checks
└── library/README.md        # MODIFIED: progressions and Auto
```

Three places list the core modules and must gain `harmony.scd` (load it after `validate.scd`/`loader.scd` and before `render.scd`):
- `supercollider/main.scd:36-38` [VERIFIED: read this session] quote: `~ppLoadCore.("validate.scd");` `~ppLoadCore.("loader.scd");` `~ppLoadCore.("render.scd");`
- `supercollider/library_test.scd:543` [VERIFIED: read this session] quote: `["validate.scd", "loader.scd", "render.scd"].do { |name|`
- `supercollider/smoke_test.scd:2083` [VERIFIED: read this session] quote: `["validate.scd", "loader.scd", "render.scd"].do { |name|`

### Pattern 1: Run-keyed memoized harmony schedule (layers pull)
**What:** `~ppHarmonyFor.(bar, songBar)` returns the entry for that song bar. State lives in one Event `~ppHarm`: `(sig:, entries: Dictionary, cycles: List, auto:, history:, voicing:, ...)`. The first layer to ask for a bar builds it (and any missing earlier bars strictly in order); the other layers hit the cache. There is no mutable "current chord" anywhere.
**When to use:** always; it is the only design that is race-free by construction (research ARCHITECTURE Pattern 1 / Anti-Pattern 2, PITFALLS Pitfall 3).
**Key facts (spike-verified, see below):**
- Within a run, `bar - songBar` is identical for all seven layers, and it differs after Stop/Start. Together with `thisThread.clock === <clock>` it is a self-validating run signature. The memo is cleared when the signature changes, and also by an explicit `~ppHarmReset` in `~ppStart` and in the main teardown.
- Cycle decisions are made one bar early. To give the bass a pickup toward `nextChord`, the entry for the last bar of a cycle needs the first chord of the next cycle, so the next cycle's progression is decided when the last bar of the current cycle is first planned. A pick that arrives after that point waits one more cycle. This is still "never mid-cycle".
- The pad's voice-leading chain is computed in the same strict order, so it is deterministic and survives no state loss: if a layer's `state` is reset by a module reload, the voicing still comes from the schedule.
- Keep the memo bounded: delete entries older than about 8 song bars each time a new bar is built (ENG-03 / "no growth").

**Example (design sketch; the chord math and mapping pieces below were run in real sclang, the memo/Auto simulation was run too, the integration into `~ppRenderBar` is new code):**
```supercollider
// core/harmony.scd (sketch)
~ppKeyRoot = 9;   // A (D-07); the only place the key lives
~ppChordTypes = (maj: [0, 4, 7], min: [0, 3, 7]);
~ppHarmReset = { ~ppHarm = nil };

~ppHarmonyFor = { |bar, songBar|
	var sig = [thisThread.clock, bar - songBar];
	if (~ppHarm.isNil or: { ~ppHarm[\sig][0] !== sig[0] } or: { ~ppHarm[\sig][1] != sig[1] }) {
		~ppHarmNewRun.(sig);          // clears entries/cycles/auto/history/voicing
	};
	~ppHarm[\entries][songBar] ?? { ~ppHarmBuildUpTo.(songBar) }
};
```

### Pattern 2: Cycle-end switching and Auto share one decision point
**What:** `~ppHarmDecide.(cycleStart)` is called once per cycle, in order, when the cycle before it reaches its last bar. If `~ppSel[\progressions]` is a loaded stem, that stem plays the next cycle. If it is `\auto`, the Auto state decides: hold the current progression for its chosen number of cycles, then shuffle.
**Auto rules (D-08..D-10):**
- First Auto progression of a run is `classic` (D-09).
- Hold = `max(1, round(rrand(32, 64) / cycleLen))` whole cycles (32-64 bars, about 2-3 minutes at 85-100 BPM).
- Next = random choice among every loaded progression stem except the current one and the last two played; if that set is empty, relax to "not the current one"; if only one stem exists, stay.
- All randomness through `thisThread.randSeed = (autoSeed * 1000003) + (decisionIndex * 7919)` set immediately before the pick. Every generator call re-seeds its own thread (`~ppRunGenerator` does `thisThread.randSeed = ~ppSeedFor.(...)`), so seeding in the shared path never leaks.
- Counting is in song bars, so Stop pauses it. A Stop/Start begins a new run (songBar restarts at 0), so the Auto state restarts at `classic`; this matches the ARCHITECTURE state table ("song position and rotation timers: reset on Start, frozen on Stop").
**Simulation result (real sclang, this session):** with three simulated layers pulling every song bar, Auto played `classic` bars 0-53, then `drama`; a named pick of `deep` at song bar 70 started at bar 74 (the next cycle boundary of the 4-bar `drama` cycle, decided one bar earlier); picking `auto` at bar 130 took effect at the cycle boundary at bar 138; a pick of `drama` at bar 150 took effect at bar 151 (classic's 1-bar cycle).

### Pattern 3: Chord-follow mapping for frozen melody files (D-01/D-02)
**What:** after a melody generator returns its rows, `~ppFollowChord` re-voices every note onto the plan chord. Notes are located on the **chord-tone ladder** of the key chord (Am: A C E A' C' E' ...), and the same ladder position is read off the ladder of the current chord, with the current chord's root octave chosen so the triad's mean pitch is nearest to Am's (so the register stays where v1 had it).
- Under Am the mapping is the identity, and the code should short-circuit (`if (chord === the Am reference) { rows }`) so the classic rows stay byte-identical (parity with the golden).
- The lead one octave above the arp stays exactly 12 semitones above after mapping (ladder position + 3), which the existing selection tests assert under classic.
- Non-chord-tone input (a passing tone) maps to the nearest Am chord tone first (ties go lower), then follows. The output is therefore always a chord tone, which is what makes the strict chord-follow check possible.
- Chord arrays (rows whose note is an Array) are mapped element by element; `\rest` passes through.
**Verified prototype results (real sclang, this session):** identity for `[57, 60, 64, 60, 69, 72, 76, 72]` under Am; for all seven progressions the arp, lead, pad voicing, bass root and bass pickup were all inside the chord (`bad=0` for each). Selected outputs: F gives arp `[53, 57, 60, 57]`; C gives `[60, 64, 67, 64]`; G gives `[55, 59, 62, 59]`; Dm gives `[62, 65, 69, 65]`; E major (Drama) gives `[52, 56, 59, 56]`, i.e. the G# (56) is played.
**Opt-out for future melodies (recommended, see Open Question 1):** Phase 8 melody files will read `plan[\chord]` themselves; mapping them again would distort them. Define now that a melody module may declare an optional key (for example `ownHarmony: true`) and the core then skips the mapping. Unknown keys are already ignored by the validator, so declaring it later needs no validator change, but the *rule* (mapping on by default, off when declared) must exist before Phase 8.

### Pattern 4: Pad nearest voicing, held across the chord
**What:** the schedule keeps the previous voicing and picks, for the next chord, the inversion and octave whose sorted notes minimise the summed distance to the previous sorted voicing, inside a pad window. The first chord of a run is voiced nearest `[45, 48, 52]` (classic's Am pad), which keeps continuity with v1 when a run starts.
**Verified results (real sclang):** Anthem pad path `[45,48,52]` to `[45,48,53]` to `[43,48,52]` to `[43,47,50]` and back to `[45,48,52]` (summed movement per change 1, 3, 3 and 5 semitones, never a jump to root position); Drama's E major voices as `[44, 47, 52]` (G# B E); Deep's Am voices as `[45,48,52]`.
**Hold:** the first bar of a chord emits `[[voicing, 4, 0.06, 0.9 * chordBars]]`; later bars of the same chord emit `[[\rest, 4, 0, 1]]`. (Planning changed the first-bar legato to the smaller of `0.9 * chordBars` and `chordBars - 0.25`, so the gate closes at least one beat before the next chord; see the Pitfall 4 resolution.) The validator accepts both (`legato` only has to be > 0, amp 0 to 1; `[VERIFIED: validate.scd:49-54]` quote: `if (reason.isNil and: { finite.(r[2]).not or: { (r[2] < 0) or: { r[2] > 1 } } })` and `if (reason.isNil and: { finite.(r[3]).not or: { r[3] <= 0 } })`). Sustain is `dur * legato` [VERIFIED: sclang probe, `Event.default` with dur 4, legato 1.8 gave sustain 7.2]. Merge adjacent identical chords during expansion (Lift's `G G`, Deep's `Am Am`) so "re-attack only when the chord changes" (D-14) is literally true; Deep's Am then holds 4 bars.

### Pattern 5: Default bass (D-12/D-13)
Same eight-eighth skeleton as `classic.scd` (rest, note, rest, note, rest, note, rest, last), amp 0.1, legato 0.8 (the frozen values, `[VERIFIED: classic.scd:20-27]`, quote `[\rest, 0.5, 0.1, 0.8], [33, 0.5, 0.1, 0.8], ... [36, 0.5, 0.1, 0.8]`). The first three notes are the chord root folded into a bass window; the last eighth is:
- chord changes next bar: a **pickup that is a tone of the current chord** chosen by pitch-class distance to the next chord's root (the current root gets a +0.5 penalty on ties so the pickup audibly steps); the pickup stays in `[root, root + 11]`.
- no change: the chord's third (`root + intervals[1]`), the same feel as v1's C on top of A.
Keeping the pickup inside the *current* chord is what lets the strict chord-follow check treat every bass note uniformly.
**Verified examples (real sclang):** Anthem Am to F pickup 40 (E, a half step under F); F to C pickup 48 (C); C to G pickup 43; G to Am pickup 47 (B). An alternative that minimises MIDI distance to the next root was also run; it is valid but produces octave drops (G to Am pickup 31), so the pitch-class rule is the recommendation.

### Anti-Patterns to Avoid
- **A mutable `~ppChord` read by layers:** the ordering of two layers' same-beat reads is unspecified (research Anti-Pattern 2). Always pull the memoized entry.
- **Reading `~ppSel[\progressions]` per layer per bar (today's `~ppModuleFor.(cat)`):** a pick would switch bass and pad on the next bar while the arp mapping still uses the old chord. Take bass/pad from the entry's captured module.
- **Building the Auto candidate list from the registry alone at engine start:** `~ppLib[\progressions]` only holds `classic` plus whatever was selected. Prefetch every valid stem on disk (through `~ppLibEnsure`) before the Auto decision needs it.
- **Editing `classic.scd` or the melody classics:** guarded by `scripts/check.sh`; the core supplies the implicit Am chord and the mapping.
- **A second clock or any Routine for the schedule:** the schedule is pure data built on demand inside the layer Prouts; nothing to stop on teardown, nothing to stack (ENG-05).
- **Calling `RandStream`:** hangs headless sclang 3.14.1 here (Pitfall 6).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-layer "current chord" | A shared mutable variable updated by a conductor Routine | The memoized `~ppHarmonyFor` entry, pulled by `(bar, songBar)` | Removes the same-beat race by construction |
| Random choice for Auto | `RandStream`, `Array.scramble` on the global stream, wall-clock seeds | `thisThread.randSeed = f(autoSeed, decisionIndex)` then `rrand`/`rand`, same as `~ppSeedFor` | `RandStream` hangs here; the global stream is shared with generators |
| Name safety and file access for Auto's folder scan | A new directory walker that builds paths from `pathMatch` | `~ppStemValid` on every stem, then `~ppLibEnsure` (containment check, validation, registry put) | Already hardened against traversal, symlinks and bad names (Phase 4) |
| Library file validity | A second validator | Extend `~ppValidate` (one definition of "valid", shared by loader, library_test and the static check) | Existing contract in `validate.scd` |
| Row validity of the new default generators | Trust the core generators | Keep the existing `~ppRunGenerator` + `~ppRowsValid` try/fallback path for them too | A bug in a core default degrades one bar to classic instead of silencing a layer |
| Key handling | Per-file keys or transposition | One `~ppKeyRoot = 9`, files hold key-relative roots (D-07) | Keeps HARM-05 (key lifts) a later one-line change |

**Key insight:** every hard part of this phase is already solved by an existing engine mechanism (per-bar render, seeding, validation, containment, test harness). The new code is data expansion, one memo, and two small pure functions (voicing, follow); resist adding conductors, timers or Routines.

## Common Pitfalls

### Pitfall 1: The bass pickup needs a decision one bar early
**What goes wrong:** the entry for the last bar of a cycle needs the first chord of the next cycle, but the selection might change between that bar and the next.
**Why it happens:** deciding the next cycle at its own first bar means the last bar's `nextChord` was a guess.
**How to avoid:** decide the next cycle when the last bar of the current cycle is planned and store it in `~ppHarm[\cycles]`; later bars read the stored decision. A pick arriving after that point simply waits another cycle.
**Warning signs:** a bass pickup that steps toward a chord that then does not arrive.

### Pitfall 2: Run detection by `(clock, bar - songBar)` fails if one layer starts a bar late
**What goes wrong:** a layer joining a later bar presents a new signature at `songBar` 0 and clears the memo mid-run for the others.
**Why it happens:** `~ppStart` calls `Pbindef(name).play(~clock, quant: 4, doReset: true)` for each layer in a loop [VERIFIED: `main.scd:273`, quote `~ppLayers.do { |name| Pbindef(name).play(~clock, quant: 4, doReset: true) };`]; if that loop straddled a bar line, a layer would start a bar late. The library test recorder already guards against exactly this (`recorder start raced`).
**How to avoid:** accept (microseconds against a bar of seconds), plus the explicit `~ppHarmReset` in `~ppStart` so a normal start never relies on inference. Do not add cleverness that couples layers.
**Warning signs:** a log line "progression classic" printed twice at a start.

### Pitfall 3: Classic's pad F breaks a strict chord-follow check
**What goes wrong:** the frozen classic pad plays `[45, 48, 53]` (A C F) on odd bars [VERIFIED: `classic.scd:33`, quote `var chord = if (plan[\songBar].even) { [45, 48, 52] } { [45, 48, 53] };`], so the F (pitch class 5) is not in Am. A check "every pitched pitch class is in its own bar's chord" fails under classic.
**Why it happens:** v1 itself has that mild clash; D-14 requires it unchanged.
**How to avoid:** give the implicit classic chord a documented `extraPcs: [5]` (F) allowance and have the check accept `pcs` union `extraPcs`; every other progression is checked strictly. State this in the check's comment so a later reader does not "fix" classic.
**Warning signs:** the chord-follow check passes for the new files and fails only for classic.

### Pitfall 4: Pad release tail and attack overlap at a chord change
**What goes wrong:** the pad voice has a 0.4 s attack and a 1.2 s release [VERIFIED: `palettes/classic.scd:51`, quote `Env.adsr(0.4, 0.3, 0.7, 1.2)`], so the old chord rings about 1.4 s under the new one even with correct notes.
**How to avoid:** nearest-voicing keeps common tones (Anthem Am to F shares A and C), and legato 0.9 starts the release 0.4 beat before the bar line. Do not shorten the release (the palette is frozen; Phase 7 owns voices). Judge it in the listening UAT.
**Warning signs:** a brief wash of two chords exactly at the change, on chords with few common tones (C to G shares only G).
**Resolution in planning (06-01; a planner decision made in yolo mode, not heard or accepted by the rider):** the core default pad (chord-data progressions only) closes its gate at least one beat before every chord change. Its legato is the smaller of `0.9 * chordBars` and `chordBars - (~ppPadGapBeats / 4)`, with `~ppPadGapBeats = 1` (1-bar chords 0.75, 2-bar chords 1.75, 4-bar chords 3.6). By the Env.adsr release curve (-4, 1.2 s), at 128 BPM the outgoing chord is then about 14 dB under its held level when the next chord starts, instead of about 6 dB with legato 0.9, and the new chord still rises over its 0.4 s attack. D-14 is unchanged: one attack per chord, sounding through the chord. The release time stays as the frozen palette sets it. The gap is asserted by "chord follow anthem" (06-01) and by the per-file recording loop and strict static branch (06-02). `classic` keeps its frozen pad generator, so all-classic stays byte-identical to v1.0, with v1's own tail. What remains (the release fading under the start of the next chord, for longer at fast tempos) is a flagged assumption, judged by ear in the 06-05 listening check (step 4).

### Pitfall 5: Auto prefetch noise breaks existing log-window assertions
**What goes wrong:** the library test asserts that no log line contains "loading" inside the invalid-name window and counts ERROR lines in other windows. `~ppLibLoad` logs `PedalPulse: loading <path>` for every file [VERIFIED: `loader.scd:73`, quote `~ppLog.("PedalPulse: loading %".format(path));`]. A background prefetch that fires inside such a window would fail them.
**How to avoid:** prefetch only stems not yet in the registry, run it at well-defined moments (when `auto` is selected, and once per Auto progression), and keep it off the hot path. Remember failed stems (with the file's modification time) so a broken file logs its ERROR once, not every cycle. Make the new tests' windows robust.
**Warning signs:** intermittent failures in "invalid names ignored" after enabling Auto.

### Pitfall 6: `RandStream` hangs headless sclang 3.14.1
**What goes wrong:** constructing `RandStream(1234)` and `RandStream(\xoroshiro128plus, 1234)` never returned in `sclang -D` (killed by timeout, no output, exit 124) in four probes, while `thisThread.randSeed = 7; 3.rand` and `Pfunc({3}).asStream` returned immediately. An error inside such a script also leaves `sclang -D` hanging instead of exiting, so a failing probe looks like a hang.
**How to avoid:** use `thisThread.randSeed` (the engine's existing pattern). When writing probes, wrap in `try` and call `1.exit` on error, and do not trust output of a killed run (stdout is lost when the process is killed).
**Warning signs:** a test or script that prints nothing and times out.

### Pitfall 7: List/Array method gotchas found while probing
**What goes wrong:** `List.new.last(2)` returns `nil` on an empty list, so `.includes` throws "Message 'includes' not understood" (and the headless run then hangs). Use `asArray.keep(-2)`. `Event` literals with integer keys like `(70: \deep)` were avoided in favour of `Dictionary.put`.
**How to avoid:** write the history window as `history.asArray.keep(-2)`.

### Pitfall 8: Existing messages and tests mention the old semantics
**What goes wrong:** `~ppSelect` logs `auto -> auto (resolves to classic)` and `-> selected (rev N), plays from the next bar` for every category [VERIFIED: `loader.scd:190` and `loader.scd:212`, quotes `~ppLog.("PedalPulse: % auto -> auto (resolves to classic)".format(address));` and `~ppLog.("PedalPulse: % % -> selected (rev %), plays from the next bar".format(address, str, mod[\rev]));`]. For progressions these become false. `library/README.md` also says "The engine switches at the next bar line" and "`auto` ... plays classic for now".
**How to avoid:** category-specific wording for progressions ("switches at the end of the current progression cycle", "auto rotates"); update the README. Palettes and melodies keep their wording. No test asserts the current progression wording (a grep of `*.scd`, `scripts` and `python_app` found only the test comment at `library_test.scd:912`).

### Pitfall 9: Open Phase 4 findings that touch the code being changed
`04-REVIEW-DISPOSITION.md` lists WR-03..WR-06 as open [VERIFIED: read this session, `| WR-03 | warning | open | - |` through WR-06]. WR-06 (a refused newer selection cancels a valid older one) lives in `~ppSelect`, which this phase edits; do not worsen it, and consider fixing it while there since the progression picker is now the audition tool. STATE.md also records a pre-existing flaky smoke check (`epic glide up: PulseCount did not advance`, about 1 run in 3) that undermines the standing exit gate; rerun once before concluding a Phase 6 change broke the suite, and consider `/gsd-debug` for it.

## Spike results (STATE.md flag: same-beat ordering of harmony vs layers)

Run this session in real sclang 3.14.1 (`sclang -D`, seven `Pbindef`s with the same `Prout` shape as `~ppBuildLayers`, one `TempoClock`, tempo stepped 120 to 165 BPM during the run, then Stop, then Start with `doReset: true`):

| Probe | Result |
|-------|--------|
| Every layer sees the same run signature | 7 of 7 layers, `bar - songBar` identical within each run: `run base 1 : 56 requests, layers 7, songBar max 7, sameClock True`, then after Stop/Start `run base 10 : 35 requests, layers 7, songBar max 4, sameClock True` |
| `thisThread.clock === <the TempoClock>` inside the `Prout` | `True` for all requests |
| Bar start time exactness through a tempo glide | `max dist of beats from 4-multiple 0.0` (beats at every bar start are exact multiples of 4) |
| Request order per bar | `abcdefg` in every bar of both runs (Pbindef play order), but unspecified by SuperCollider, so the memo must not depend on it |
| Restart resets song bar | After Stop/Start the new run's first request is `songBar` 0 at a new base, so the signature differs |
| Sustain of a held pad row | `Event.default` with `dur 4, legato 1.8` gave `sustain=7.2` |

Conclusion: the memoized pull design is safe across Stop/Start and tempo glide; harmony is a pure function of `(run, songBar)`, never of who asks first.

## Code Examples

Verified in real sclang this session (prototype run, outputs quoted above). These are the building blocks; wiring into `render.scd` is new code for the planner.

### Chord expansion (key-relative root plus quality)
```supercollider
// keyRoot 9 = A. (root: 8, quality: \maj) -> pc (9 + 8) % 12 = 5 -> F major
expand = { |c|
	var iv, rootPc, nm;
	iv = c[\intervals] ? types[c[\quality]];
	rootPc = (keyRoot + c[\root]) % 12;
	nm = names[rootPc] ++ if (c[\quality] == \min) { "m" } { "" };
	(rootPc: rootPc, intervals: iv, pcs: iv.collect { |i| (rootPc + i) % 12 }, name: nm)
};
```
Root values for the seven files (semitones above A): Am 0, Dm 5, Em 7 (minor) and E 7 (major), F 8, C 3, G 10. Check: F is `(9 + 8) % 12 = 5`; C is `(9 + 3) % 12 = 0`; G is `(9 + 10) % 12 = 7`; E is `(9 + 7) % 12 = 4` (G# is pc 8, inside E major's `[4, 8, 11]`).

### Root octave, ladder and follow
```supercollider
// triad root octave: mean pitch of the root-position triad nearest Am's mean (60.33)
centroidRoot = { |ch|
	var best = nil, bestD = 1e9;
	[36, 48, 60, 72].do { |base|
		var r = base + ch[\rootPc], notes, m, d;
		notes = ch[\intervals].collect { |i| r + i };
		m = notes.sum / notes.size;
		d = (m - 60.3333).abs;
		if (d < bestD) { bestD = d; best = r };
	};
	best
};
// follow = ladderIdx(note, Am) - ladderIdx(Am root) -> ladderNote(k, currentChord, centroidRoot(currentChord))
```
(full `ladderIdx` / `ladderNote` / `follow` / `nearestVoicing` / `bassRoot` / `pickup` code ran in the scratch prototype; the planner can re-derive from the behaviour tables here. Register choices: arp roots land at F 53, G 55, C 60, Dm 62, Em 52, E 52.)

### Nearest voicing (pad)
```supercollider
// ch: chord record; prev: previous sorted voicing; window lo..hi (assumed 40..64)
// candidates: each inversion i (first i tones up an octave) x octave shifts -3..3, sorted;
// cost = sum |new[i] - prev[i]| (sorted-to-sorted is the optimal L1 match); ties -> lower
```

### Bass window and pickup
```supercollider
bassRoot = { |ch| 33 + ((ch[\rootPc] - 33) % 12) };    // folds into 33..44
// pickup: the tone of ch with the smallest pitch-class distance to the next root; current root gets +0.5 on ties
```
Resulting bass roots (verified): Am 33, C 36, Dm 38, E 40, Em 40, F 41, G 43.

### Chord data file (recommended shape)
```supercollider
(
desc: "Uplifting trance staple: Am F C G, one chord per bar",
barsPerChord: 1,                              // optional, default 1; per-chord bars: overrides it
chords: [
	(root: 0,  quality: \min),                // Am  (root = semitones above the key note A)
	(root: 8,  quality: \maj),                // F
	(root: 3,  quality: \maj),                // C
	(root: 10, quality: \maj)                 // G
]
)
```
Optional per chord: `bars: n`, or `intervals: [0, 3, 7]` instead of `quality`.

### The seven files (chord math verified, bars per chord per D-06)
| Stem | Chords (in A) | Key-relative roots (quality) | Bars per chord | Cycle |
|------|---------------|------------------------------|----------------|-------|
| anthem | Am F C G | 0 min, 8 maj, 3 maj, 10 maj | 1 | 4 |
| rocker | Am G F G | 0 min, 10 maj, 8 maj, 10 maj | 1 | 4 |
| lift | Am F G G (G G merges into a 2-bar G) | 0 min, 8 maj, 10 maj, 10 maj | 1 | 4 |
| return | Am C G F | 0 min, 3 maj, 10 maj, 8 maj | 1 | 4 |
| deep | Am Am F G (Am Am merges into a 4-bar Am) | 0 min, 0 min, 8 maj, 10 maj | 2 | 8 |
| melancholy | Am Em F Dm | 0 min, 7 min, 8 maj, 5 min | 1 | 4 |
| drama | Am Dm F E (E major, G#) | 0 min, 5 min, 8 maj, 7 maj | 1 | 4 |

Log line format (D-11): `PedalPulse: progression anthem: Am F C G` (merged chords listed once; Deep prints `Am F G`). Do not put the word "loading" in it (Pitfall 5).

## Validator, plan and test changes (what the planner must schedule)

**Validator (`validate.scd:87-91`)** [VERIFIED: read this session] currently: `if (cat == \progressions) { anyOf.([\bass, \pad]); checkFn.(\bass); checkFn.(\pad); };`. Change to accept a file that defines any of `bass`, `pad` **or** `chords`, and, when `chords` is present, check: non-empty Array of at most 16 entries; each an Event with `root` an Integer 0 to 11; `quality` a key of `~ppChordTypes` or `intervals` a 3 to 4 element Array of Integers 0 to 11 starting at 0; `bars` (per chord or `barsPerChord`) an Integer 1 to 8; total cycle bars 1 to 16. Contract-freeze rule stays: unknown keys are ignored. Cap sizes (Security). `classic.scd` (no `chords`, has bass/pad) must still pass unchanged.

**Plan keys (`render.scd:73-75`)** [VERIFIED: read this session] currently `~ppPlanFor = { |bar, songBar, role| (bar: bar, songBar: songBar, phraseBar: songBar % 8, role: role) };`. Add an optional fourth argument (the harmony entry) that merges extra keys; the three existing keys keep their meaning, and 3-argument callers (`library_test.scd:414` and `:476`) keep working. Recommended added keys: `progression` (stem), `chord` (record with `rootPc`, `intervals`, `pcs`, `name`, plus `extraPcs` for classic), `nextChord`, `chordBar`, `chordBars`, `cycleBar`, `cycleLen`, `voicing`, `bassRoot`, and optionally `scale` (A natural minor pitch classes `[9, 11, 0, 2, 4, 5, 7]` united with `chord[\pcs]`, so Drama's E major adds G#; this gives Phase 8 its per-chord scale for free).

**`~ppRenderBar`** (`render.scd:135-192`) changes: for bass/pad, resolve the module from the harmony entry's captured module instead of `~ppModuleFor.(cat)`; if that module defines the role use it, else use the core default; for arp/lead run the melody generator as today, then map the validated rows with `~ppFollowChord` unless the entry's chord is the Am reference or the melody module declares it owns harmony. The failure/fallback accounting (3 strikes returns the category to classic) must keep working for the progressions category (`~ppRenderFail` sets `~ppSel[cat] = \classic`). Wrap `~ppHarmonyFor` in `try`; on a throw return the implicit-Am classic entry so all layers still agree.

**Tests to add or change:**
- `library_test.scd` static tier: chord-data progressions have no `bass`/`pad` generators, so `roleGens` (`library_test.scd:342`) runs nothing for them today. Add a branch that expands the file's chords, renders the core default bass/pad for every bar of its cycle through `~ppRenderBar` with an explicit pure harmony entry (do not touch the live memo from the static tier), validates the rows with `~ppRowsValid`, and applies the strict in-chord check. Add negative controls: bad root, unknown quality, empty chords, 17 chords, bars 0, a cycle over 16 bars.
- `library_test.scd` chord-follow tier: `recordBars` already records `[layer, relBeat, instrument, midinote, ...]`; for each non-classic progression select it, record at least two full cycles (include a `recClock.tempo` change mid-run, as test 10 "plan bar is the played bar" does at `library_test.scd:1523`), read each bar's chord from `~ppHarmonyEntry.(songBar)` after the recording (the latest run's memo stays valid), and assert every bass, arp, pad and lead pitch class is in that bar's `pcs` (union `extraPcs`). Do the same across a Stop/Start by calling `recordBars` twice (each call is a fresh clock and a fresh run) and across `Pbindef.stop`/`play` mid-run.
- Cycle-end test: send `/pp/progression` mid-cycle; assert the chord source changes exactly at a cycle boundary, never mid-cycle, and stays until another pick.
- Auto test: with `auto`, the first cycle is classic, a later cycle is a different stem, no stem repeats within the last two, and a file added to a temporary library root is eventually eligible (use the existing temporary-root pattern, `library_test.scd:1161-1172`).
- Classic parity: the existing parity, "auto plays classic" (4 bars on Auto, which is still `classic` for 32+ bars) and golden checks must pass unchanged. Add a check that classic's implicit harmony entry leaves the arp, lead, bass and pad rows byte-identical.
- Smoke: the engine-level Stop checks (`stop silences every layer`, `stop cuts held pad`, ENG-05 no stacking) must stay green; add one check that after `~ppStop`/`~ppStart` with a non-classic progression selected the memo begins again at chord 0 and group children return to zero after Stop. The harmony memo holds no Routines, so the stacking counts (`after[\routines] != 1`) cannot be affected, but assert it.
- The `check.sh` file-count cross-check (`LIBCHECK OK` lines equal `.scd` files on disk, currently 8 files, baseline `CHECK PASS (library only)` in about 68 s this session) will count the seven new files automatically.

**Template:** `library/progressions/_template.scd` gains a chord-data example (it must itself validate, since the static check loads templates). It is outside the guard (`'supercollider/library/*/[a-z0-9]*.scd'` excludes `_template`) [VERIFIED: `scripts/check.sh` guard glob read this session].

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Mutable global current chord read in a `Pfunc` | Memoized plan pulled by bar number | Research Pattern 1 (2026-10-11); engine already pulls plans per bar since Phase 4 | Removes the same-beat race |
| Per-file bass and pad generators (v1.0 classic) | Chord data in the file, generic generators in the core | This phase | New progression = ~10 lines of data |
| Selection applies on the next bar (Phase 4) | Progression applies at the end of the cycle; Auto decides at the same point | This phase | HARM-04 |

**Deprecated/outdated:** `~ppResolveStem` for the progressions category (palettes and melodies keep using it; Auto rotation for those is Phases 7 and 8).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Bass roots fold into MIDI 33-44 (A1 to G#2), per PITFALLS Pitfall 17's suggested 33-45 window | Pattern 5 | Bass too high/low or too jumpy on small speakers; adjust by ear |
| A2 | Pad voicing window 40-64 and a first-chord reference of classic's `[45, 48, 52]` | Pattern 4 | Pad register wrong for the palette; adjust window by ear |
| A3 | Arp register rule: triad whose mean is nearest Am's (60.33), i.e. root octave F 53, G 55, C 60, Dm 62, Em 52, E 52 | Pattern 3 | Arp sits low/high for some chords (Em and E major arps start at 52); adjust by ear |
| A4 | Pickup rule: current-chord tone nearest the next root by pitch class, root penalised on ties, kept within root..root+11; no-change bars play the chord's third | Pattern 5 | Pickups may sound too similar to v1's C or not "stepping" enough; adjust by ear |
| A5 | Auto hold is `max(1, round(rrand(32, 64) / cycleLen))` cycles; returning from a named pick to Auto does not restart at classic (shuffle continues; planning changed this to adopt-then-hold, see Open Question 4) | Pattern 2 | "Start on classic" (D-09) could be meant for every return to Auto too |
| A6 | A Stop/Start restarts the song, so Auto restarts at classic and the memo clears | Pattern 1/2 | Rider might expect Auto to resume where it paused |
| A7 | Merge adjacent identical chords (Lift G G, Deep Am Am) so the pad re-attacks only on a real change | Pattern 4 | Deep's Am pad holds 4 bars (a very still start); decide whether D-06 "2-bar chords" intends a re-attack at bar 3 |
| A8 | Auto's engine-start seed: a fixed `~ppSongSeed`-derived seed makes every launch play the same Auto order | Open Question 3 | Rides feel identical run to run |
| A9 | An optional melody key (for example `ownHarmony: true`) disables the core mapping for Phase 8 files | Pattern 3 / Open Question 1 | Phase 8 melodies get double-mapped unless the rule exists |
| A10 | The seven files will sound clearly distinct to the rider; Anthem, Rocker, Lift and Return share the same chords in a different order at the same pace and arp shape | Progression table | Violates "variations must be audible"; needs the listening UAT, possible pace or chord tweaks (new files, since committed files never change) |
| A11 | Chord data cap (16 chords, bars 1-8, cycle at most 16) is a sufficient and safe validator limit | Validator | A legitimate long progression is refused (raise the cap) or a hostile file wastes memory |

## Open Questions (RESOLVED)

All five questions were resolved during planning. The project runs in yolo mode, so the resolutions are planner decisions; none of them has been confirmed by the user. The ones the rider can judge (1, 4 and the pad tail of Pitfall 4) are listed for the rider's review in the 06-05 SUMMARY and listening check.

1. **Should a melody be able to opt out of the core chord mapping?**
   - What we know: D-01/D-02 map every melody's notes by default; Phase 8 files will be chord-aware themselves.
   - What's unclear: whether the user wants that escape hatch defined now (D-01 is marked costly to reverse).
   - Recommendation: define it now as an optional module key checked by the core (default on), documented in the template and README. Confirm with the user in plan review.
   - **RESOLVED (planner decision in yolo mode; the user has not confirmed it):** the opt-out is defined now, as recommended. A melody module may declare `ownHarmony: true`; the core then leaves that module's own generator rows unmapped, while rows that came from the classic fallback are always mapped. Mapping stays on by default (D-01/D-02). Implemented in 06-01 Task 1 (render.scd), pinned by 06-02 Task 1 (i), documented in 06-05 Task 2 (README and melody template). No Phase 6 library file uses the key, so if the rider rejects it, removing it before Phase 8 is a core-only change. It is listed for the rider's review in the 06-05 SUMMARY section "Planner decisions for the rider to review".

2. **How should the chord-follow check treat classic's pad F?**
   - What we know: `classic.scd` is frozen and plays F on odd bars; success criterion 1 says "no clashing notes".
   - What's unclear: whether "classic is v1, exempt" is acceptable wording for verification.
   - Recommendation: `extraPcs: [5]` on the implicit classic chord and an explanatory comment (Pitfall 3).
   - **RESOLVED (planner decision):** as recommended. The implicit classic chord carries `extraPcs: [5]` with a comment explaining the frozen passing F; every chord-data file is checked strictly, with no allowance (06-01 Task 1 step 2b; 06-02 prohibition and Task 2 step 1).

3. **Should Auto differ from ride to ride?**
   - What we know: the engine seeds everything from `~ppSongSeed = 0` so restarts replay; a fixed Auto order means every launch plays the same sequence after classic.
   - What's unclear: whether the rider wants variety per launch (Phase 8 will log melody seeds, MEL-04).
   - Recommendation: seed Auto from a value chosen at engine start and logged once (`~ppAutoSeed = ~ppAutoSeed ? <date-derived>`), overridable so tests can fix it; this keeps a heard order reproducible from the log.
   - **RESOLVED (planner decision):** as recommended. `~ppAutoSeed = ~ppAutoSeed ? (Date.getDate.rawSeconds % 1000000).asInteger`, chosen once per interpreter, kept across re-evaluation, posted as `PedalPulse: progression auto seed <n>`, and set by the tests (06-04 objective and Task 1).

4. **When the rider goes from a named pick back to Auto mid-run, which progression plays next?**
   - Recommendation: shuffle from the end of the current cycle (no forced classic). "Start on classic" applies to the start of a run.
   - **RESOLVED, differently from the recommendation above (deliberate planner decision in yolo mode; not reviewed by the user): adopt, then hold.** When Auto is selected mid-run, Auto adopts the progression that is playing and holds it for one full Auto hold (whole cycles adding up to 32-64 bars), then shuffles with no quick repeats (D-10). Rationale: `main.scd` autostarts on evaluation (D-15) with `classic` as a named selection, and the app sends `auto` at every launch (Phase 5, `selector.send_initial()`), so the usual way Auto gets engaged is mid-run, while classic is already playing. Under "shuffle from the end of the current cycle", classic (a 1-bar cycle) would be replaced one or two bars after the app opens, and the rider would almost never hear the classic opening that D-09 asks for. Adopting keeps classic for a full hold in exactly that case. After a named pick, adopting also avoids an abrupt change one cycle after the rider's own choice, and it does not force a jump back to classic. D-09 still holds literally at the start of every run (Start, Stop then Start, or a re-evaluation while Auto is selected): the first Auto progression is classic. The departure from D-09's literal wording is limited to a mid-run selection of Auto, where the playing progression comes first. Recorded in 06-04 (objective and must_haves), explained in the README (06-05 Task 2), and put to the rider in the 06-05 listening check (step 9) and SUMMARY.

5. **Maximum cycle length.** Deep is 8 bars (about 15 s at 128 BPM, 21 s at 90 BPM), the stated ceiling. The validator allows 16 and the library check should print a `CHECK WARN` above 8 rather than fail. Confirm.
   - **RESOLVED (planner decision):** as recommended. The validator caps the cycle at 16 bars; the library check prints `CHECK WARN: progressions/<stem> cycle is <len> bars; ...` above 8 and does not fail (06-02 Task 2 step 1); every shipped file is 8 bars or less (06-03 "shipped progressions" check).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| SuperCollider sclang | Engine, all tests | yes | 3.14.1 at `/Applications/SuperCollider.app/Contents/MacOS/sclang` (not on PATH; `scripts/check.sh` uses the full path) | `SCLANG=...` override |
| Project venv | `scripts/check.sh` requires `.venv/bin/python` | yes | present | `./run.sh --setup` |
| Baseline gate | Phase 6 must keep it green | yes | `bash scripts/check.sh --library-only` ended `CHECK PASS (library only)` in about 68 s this session (8 library files) | - |
| Audio device / ears | Listening UAT for distinctness | user's machine | n/a | The headless suite cannot judge "sounds distinct" |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Headless sclang scripts with a `CHECK OK` / `LIBRARY PASS` / `SMOKE PASS` line protocol (library_test.scd, smoke_test.scd), driven by `scripts/check.sh`; pytest for the untouched Python side |
| Config file | none (`scripts/check.sh`, `scripts/smoke_test.sh`) |
| Quick run command | `bash scripts/check.sh --library-only` (about 68 s today) |
| Full suite command | `bash scripts/check.sh` (library guard, library check, then the smoke suite) |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HARM-01 | Every bass/arp/pad/lead pitch class is in its bar's chord, across tempo glide and Stop/Start; classic byte-identical | integration (recordBars) | `bash scripts/check.sh --library-only` | Wave 0: new chord-follow tier in `library_test.scd` |
| HARM-01 | Same-bar entry for all layers (no mutable chord) | unit/integration | same | Wave 0: pure `~ppHarmonyFor` tier |
| HARM-02 | Seven chord-data files plus classic validate, render valid rows, stay in chord | static | same | Wave 0: new static branch; files NEW |
| HARM-03 | Pad voicing is the nearest to the previous (summed movement bounded) and held across the chord | unit | same | Wave 0 |
| HARM-04 | A named pick lands only at a cycle boundary and persists; Auto starts classic, rotates, no quick repeats, picks up a new file | integration | same | Wave 0 |
| Exit gate | Stop silences all layers; re-evaluation stacks nothing; smoke + library check pass with every progression file | smoke | `bash scripts/check.sh` | exists (extend) |
| Python untouched | Dropdown lists the new stems | unit | `.venv/bin/python -m pytest python_app/tests/test_library_logic.py -q` | exists (no change expected) |

### Sampling Rate
- **Per task commit:** `bash scripts/check.sh --library-only`
- **Per wave merge:** `bash scripts/check.sh`
- **Phase gate:** full suite green (rerun once if the known flaky `epic glide up` check fails), then a listening UAT of the seven files on Auto and by name

### Wave 0 Gaps
- [ ] `core/harmony.scd` pure functions (expand, follow, voicing, bass pickup) with unit-style checks in `library_test.scd`
- [ ] Chord-follow tier using `recordBars` plus `~ppHarmonyEntry` for the expected chord per bar
- [ ] Negative controls for bad chord data
- [ ] Test-script core load lists updated in `library_test.scd:543` and `smoke_test.scd:2083`
- [ ] Listening UAT script: plain-language list of the seven names and what each should sound like

## Security Domain

`security_enforcement` is enabled (absent or true in `.planning/config.json`; `security_asvs_level: 1`).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | OSC is loopback-only (`srcID: NetAddr("127.0.0.1", nil)`), unchanged |
| V3 Session Management | no | - |
| V4 Access Control | no | - |
| V5 Input Validation | yes | `~ppStemValid` on every name (OSC and Auto's folder scan), `~ppValidate` for file shape and the new chord data ranges and size caps; nothing path-like is built from unvalidated input |
| V6 Cryptography | no | - |
| V12 Files and Resources | yes | `~ppLibContained` realpath containment and `File.exists` checks stay on the single load path (`~ppLibEnsure`); Auto's prefetch must call it, never `.load` a scanned path directly |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Path traversal / symlink escape through a name | Tampering | existing stem rule plus `~ppLibContained` (Phase 4); Auto scan filters with `~ppStemValid` and loads via `~ppLibEnsure` |
| Hostile or malformed chord data (NaN, huge counts, wrong types) causing a throw, hang or memory growth in the per-bar path | Denial of service | validate types and ranges at load; cap chords at 16, bars at 8, cycle at 16; core code runs under the existing try/fallback; memo pruned |
| A library file with load-time side effects | Tampering | existing lint (forbidden tokens) and side-effect checks in the static tier; chord-data files contain only literals |
| Auto repeatedly re-reading a broken file (log flood, wasted work) | Denial of service | remember failed stems with modification time; scan only at defined moments |

## Sources

### Primary (HIGH confidence)
- In-repo files read this session: `supercollider/core/render.scd`, `loader.scd`, `validate.scd`, `supercollider/main.scd`, `library/progressions/classic.scd`, `_template.scd`, `library/melodies/classic.scd`, `classic_lead.scd`, `classic_lead_loud.scd`, `library/palettes/classic.scd` (envelope lines), `supercollider/library_test.scd`, `supercollider/smoke_test.scd` (relevant sections), `scripts/check.sh`, `scripts/smoke_test.sh`, `library/README.md`
- Planning artifacts: `06-CONTEXT.md`, `REQUIREMENTS.md`, `STATE.md`, `.planning/research/ARCHITECTURE.md`, `FEATURES.md` (progression list), `PITFALLS.md` (Pitfalls 3, 13, 17), `04-REVIEW-DISPOSITION.md`
- Real sclang 3.14.1 probes run this session (scratch scripts in the session scratchpad): same-beat/run-signature spike across a tempo glide and Stop/Start; chord expansion, follow, voicing, bass and pickup prototype for all seven progressions; memo plus Auto plus cycle-end simulation; sustain probe; `RandStream` hang probes; `scripts/check.sh --library-only` baseline run

### Secondary (MEDIUM confidence)
- `.planning/research/FEATURES.md` progression table (genre practice; the file itself notes the lower rows are "common practice from my own knowledge, not individually verified")

### Tertiary (LOW confidence)
- None used. No web research was needed: this phase is in-repo engine work against a fixed local toolchain.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH, no new dependencies; sclang version verified.
- Architecture: HIGH for the pull/memo design and the integration seams (read in code and probed in real sclang); MEDIUM for the exact Auto edge semantics (A5, A6, Open Question 4).
- Pitfalls: HIGH for those reproduced or read in code (RandStream, log wording, test lists, classic F); MEDIUM for the pad-tail audibility.
- Musical parameters (registers, windows, pickup rule): MEDIUM, adjusted by ear in UAT.

**Research date:** 2026-10-12
**Valid until:** 2026-11-11 (stable; the repo changes only by this milestone's phases)
