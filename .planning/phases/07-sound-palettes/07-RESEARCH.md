# Phase 7: Sound Palettes - Research

**Researched:** 2026-10-13
**Domain:** SuperCollider 3.14.1 sound-palette rotation, loudness matching and library hardening inside the existing PedalPulse core (sclang + scsynth, headless sclang test harness)
**Confidence:** HIGH for the engine integration points and the measurement method (read from the code and proven by prototype runs this session); MEDIUM for the sound recipes and the Auto timing numbers (they need the rider's ears and a tempo assumption)

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** The first palettes are a **broad trance mix** of about 6 clearly different sound worlds: `anthem` (big supersaw pad and lead), `acid` (squelchy 303-style bass), `warm` (soft analog, round bass), `pluck` (bright digital plucks, crisp drums), `dark` (minimal, gritty, deep kick) and `air` (ethereal, glassy bells, soft pads). Names are working stems; the planner may adjust them within `^[a-z0-9_]+$`. Each must be recognisably different in the full mix (see the "variations must be audible" rule).
- **D-02:** A palette changes **its sounds plus its bass style**. It can pick a bass-pattern flavour such as rolling offbeat eighths (v1), rolling 16ths or octave pops. Phase 6 D-12 handed bass variety to palettes. Drum and arp rhythms stay as they are. Bass notes still follow the chord root and the Phase 6 pickup rule (D-13); `classic` must stay exactly v1. — **Reversibility:** costly — this adds a rhythm-affecting key to the palette file contract, which every later palette and the validator rely on.
- **D-03:** **Every palette has its own pitched voices** (bass, arp, pad, lead). Drums change only where the character needs it (e.g. `dark` gets a deeper kick); roles left out fall back to classic's voice, as the existing `~ppInstrumentFor` already does.
- **D-04:** **A palette supplies only the lead sound.** Whether the lead plays is still decided by the Melody selection (the `classic` melody keeps the lead silent; `classic_lead_loud` makes it audible). A palette never forces the lead on.
- **D-05:** On Auto, one palette holds for **about 4–6 minutes**, roughly every second progression change. Count the hold in song bars so Stop pauses it, like progressions.
- **D-06:** **A palette change always lands on a progression change**, on the same bar a new progression cycle starts, so the music has a single "new chapter" moment.
- **D-07:** If the progression is locked (no progression changes happen), Palette Auto still rotates on the same ~4–6 min timing, **landing at the end of the locked progression's cycle**.
- **D-08:** **Random from the start.** Palette Auto does *not* open on `classic` (unlike progressions, Phase 6 D-09); the first palette after Start is a random pick. After that it shuffles with no quick repeats (never the current one or the last couple played), and any new palette file joins the rotation automatically. `classic` stays in the rotation. Engine startup with no GUI still defaults to `classic` (Phase 4 D-07), so the all-`classic` parity check is unaffected.
- **D-09:** Every palette change (Auto or manual) **prints a post-window line with the palette's name and its `desc`** (e.g. `palette acid: squelchy 303 bass, ...`), so the rider can name what they heard. The app stays send-only.
- **D-10:** **Old notes ring out naturally.** Notes already playing finish their own release while the new palette's notes start on the downbeat: no hard cut, no gap, no click.
- **D-11:** **A named pick takes over from the next bar** (quick audition, matching the Phase 4 rule). It does not wait for the phrase or cycle end. Only Auto rotation waits for a progression change or cycle end (D-06/D-07).
- **D-12:** **No transition effect.** No sweep or riser on a palette change; transitions belong to Phase 9.
- **D-13:** **Loudness matching is measured, then checked by ear.** The library check renders each palette headlessly at a fixed EPIC level, compares its level with `classic`, and fails if the gap is more than about 1.5 dB (the planner picks the metric, e.g. RMS over a few bars). After that the rider does a short listening pass, switching palettes, at UAT. VO2 at volume 100 on the loudest palette must still never clip.
- **D-14:** **CPU budget: scsynth `s.avgCPU` below 25%** with the heaviest palette at VO2, calibrated on the riding Mac.
- **D-15:** **Measuring CPU takes one command plus a quick Zwift check.** A script/command locks the heaviest palette at VO2 for about 1 minute and prints average and peak CPU. The rider runs it once with Zwift open (no ride needed) and reports the numbers at UAT. The headless library check also probes CPU per palette and warns before a ride.
- **D-16:** **Phase 7 fixes both deferred Phase 4 review items.** WR-01: add upper bounds on row values in the validator. WR-02: a refused palette must not leave its SynthDefs behind, and the fallback must restore the classic voices. Both matter once 6+ palettes rotate automatically.

### Claude's Discretion

- **How the bass style reaches the bass layer:** bass rows today come from the progression's generator (`~ppRoleCategory` maps bass to `\progressions`). The planner decides how a palette's bass flavour applies, e.g. a palette key the core bass generator reads, or a palette-supplied rhythm the core combines with the chord roots. The frozen `progressions/classic.scd` and `palettes/classic.scd` must keep producing exactly v1.
- **How Auto palette state works with the progression Auto:** e.g. share the harmony module's cycle-end hook and hold counter, or keep a separate state. The draw counter must survive Stop/Start, like `~ppAutoPicks` (Phase 6 WR-02). Seeding must stay replayable.
- **Prepare ahead:** run a palette's `defs` + `s.sync` before its switch bar (research: one phrase ahead), so the switch bar never waits on the server.
- **A pad held across a next-bar manual switch:** whether the old pad rings to its release and the new pad enters on the switch bar, or waits for the next chord. Either way, no gap and no click (D-10).
- **Voice design:** follow the voice contract in `palettes/_template.scd` and the research CPU guidance (few detuned oscillators on the 16th-note arp, no per-voice reverb/delay; FX stay in the shared `\ppFx`).
- **Exact numbers:** hold-time jitter within 4–6 min, the loudness tolerance (~1.5 dB) and the level metric, and the CPU warning threshold in the headless check.

### Deferred Ideas (OUT OF SCOPE)

- Transition effects on palette changes (filter sweep, riser): rejected for Phase 7; belongs to song structure in Phase 9.
- A palette forcing the lead on: rejected; the lead stays controlled by the Melody selection (the real lead comes in Phase 8).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PAL-01 | At least 5 named palettes plus `classic` ship in the library. Each palette is a coherent set of lead, bass, pad, arp and drum sounds | Six prototype palettes (26 voices) loaded and passed the voice contract in this session; the voice recipes, the static/voice/file-count checks (15 -> 21 files) and the "own pitched voices, disjoint instrument sets" proxy are in Standard Stack, Code Examples and Validation Architecture |
| PAL-02 | In Auto mode the engine rotates palettes on its own every few minutes, switching only at section or phrase boundaries | Per-bar palette stored in the memoized harmony entry (all 7 layers agree on the bar's palette), Auto state in `~ppHarm`, boundary = cycle start where the progression changed (or every cycle start when the progression is locked), tunable bar-count hold, prefetch of all palette files so a pick never waits on the server |
| PAL-03 | Selecting a named palette locks it until Auto is selected again | Named pick is captured into the entry at the next bar build (D-11), never rotated; `auto` re-engages Auto; test plan in Validation Architecture |
| PAL-04 | Palettes are loudness-matched, so switching causes no noticeable volume jump and never bypasses the limiter | Measured post-FX RMS method (prototype: repeatable to 0.0 dB, gaps stable across EPIC 30/75/100), raw unmatched gaps of up to +8.2 dB for by-feel voices, per-voice gain constants as the trim mechanism, headroom and no-bypass checks |
</phase_requirements>

## Summary

Phase 7 is almost entirely engine work inside code that already exists. The library loader, the per-bar renderer, the memoized harmony entry (Phase 6) and the voice-contract tier of the library check already do most of what palettes need; I read all of them this session. Three things are genuinely new: (1) the palette in use must become **per-bar state shared by all seven layers** (today each layer resolves the palette on its own, and `auto` just means `classic`), (2) Auto palette rotation with its landing rule, and (3) a **real-time level and CPU tier** in the headless check. Hardening (WR-01 bounds, WR-02 SynthDef namespace) must land first because the Auto prefetch loads every palette file on disk and runs its `defs`.

I prototyped the risky unknowns in a scratch copy (not in the repo): six complete draft palettes (24 pitched voices plus 2 drum voices) loaded through the real `~ppLibEnsure`, passed the existing voice-contract logic, and were measured through the real engine. Findings that change the plan: by-feel voices are **up to +8.2 dB louder than classic** (warm), so the 1.5 dB gate is necessary and will fail first drafts; the RMS measurement is repeatable (two classic runs identical to 0.0 dB) and the gap is stable across EPIC 30/75/100 to within about 0.7 dB; **CPU is not a real constraint** for stock-UGen voices (heaviest draft 7.3% avg on this M1 versus 4–5% for classic, budget 25%); and the level/CPU loop costs an estimated 6.5 s per palette per EPIC point (1.3 s settle + 5.3 s of 4 bars at 180 BPM), which on top of the **138 s library-check baseline (watchdog 300 s)** forces a watchdog bump. One review suggestion would break shipped behaviour: WR-01's proposed `legato <= 4` rejects Phase 6's own default pad for chords of 5 or more bars (legato up to 7.2).

**Primary recommendation:** Do it in this order: (1) harden the loader and validator (WR-01 bounds with legato cap 8, WR-02 `pp_<stem>_` prefix plus SynthDescLib snapshot-diff guard and restore), (2) put `palette` into the memoized harmony entry and add Auto palette rotation (state inside `~ppHarm`, separate draw counter, prefetch generalised to palettes), (3) add the core bass-style table keyed by a `bassStyle` palette key, (4) build the level/CPU/headroom tier and tune the palette voices against it **before** the first commit of each palette file (committed files are frozen), (5) ship the six palettes, the CPU script and the UAT checklist.

## Project Constraints (from CLAUDE.md)

- Platform macOS, same machine as Zwift; the audio engine must stay light enough not to disturb Zwift.
- Audio engine is SuperCollider 3.14.x (installed: sclang 3.14.1, see Environment Availability); control app is Python + Tkinter with minimal dependencies; OSC over UDP on localhost (sclang language port 57120).
- The SuperCollider patch is started separately by the user; the Python app only connects (send-only). Phase 7 has **no GUI/Python change**.
- Do not add quarks or extra dependencies; write generative logic with stock classes. All palette voices must use stock UGens only.
- Work enters through a GSD command (no direct repo edits outside the workflow); commits follow the attribution line given in the session reminder.
- Memory-recorded preferences (treat as locked): the rider is not an SC musician and gives plain-language sound feedback; every variation is a new library file, never overwrite a committed one; variations must be obviously audible in the full mix (a faint 12 dB-down change was inaudible); keep the app simple, Python stays send-only with no engine-to-GUI feedback.
- Code convention from the existing core: Events are always read and written with `[\key]`, never dot syntax; library files are one parenthesized Event with no `~` variables.

## Architectural Responsibility Map

Phase 7 has no web tiers; the tiers are the engine's own layers.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Palette file contract (`desc`, `defs`, `roles`, `bassStyle`) and voice definitions | Library files (`supercollider/library/palettes/*.scd`) | scsynth (runs the SynthDefs) | Files are data plus a `defs` Function; nothing runs at load |
| Validation (shape, bounds, `pp_<stem>_` prefix) | Core `validate.scd` / `loader.scd` | `library_test.scd` calls the same functions | One definition of "valid" is the existing convention |
| Which palette applies to a given bar | Core `harmony.scd` memo (`entry[\palette]`) | `render.scd` (reads it) | All seven layers must agree for a bar; only the memo gives that by construction |
| Auto rotation (hold, landing, random pick, history) | Core `harmony.scd` | `loader.scd` (prefetch) | Landing depends on cycle starts and progression changes, which live in the harmony memo |
| Bass rhythm flavour | Core (`~ppBassStyles` table beside `~ppDefaultBass`) | Palette `bassStyle` key selects it | Keeps library files data-only and keeps pickup/chord rules in one place |
| Voice rendering, level, release, Stop | scsynth | Voice contract in the check | Each voice self-frees; Stop is the existing `\gate, 0` broadcast |
| Loudness / CPU / headroom measurement | `library_test.scd` real-time tier (isolated server 57141) | New CPU script (own isolated server) | Needs real-time audio and `s.avgCPU` |
| Post-window announcement of the palette | Core (`~ppLog` at bar build) | — | The rider's feedback channel; app stays send-only |
| Palette dropdown | Python GUI (unchanged) | — | Phase 5 already lists any `.scd` stem on disk; nothing to do |

## Standard Stack

### Core

No new packages. Everything is stock SuperCollider 3.14.1 plus the existing harness.

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SuperCollider (sclang + scsynth) | 3.14.1 [VERIFIED: `sclang -v` printed `sclang 3.14.1 (Built from tag 'Version-3.14.1' [426edf6])`] | Engine, SynthDefs, headless test harness | Project constraint |
| Stock UGens used by the draft voices | core `plugins` | `Saw`, `Pulse`, `LFTri`, `SinOsc`, `RLPF`, `LPF`, `HPF`, `BPF`, `Pluck`, `Splay`, `Pan2`, `EnvGen`, `XLine`, `.tanh`, `.fold2` | All loaded and passed the voice contract in the prototype (see Palette voice recipes); no sc3-plugins, no quarks |
| `SynthDescLib.global` / `SynthDef.removeAt` | core class library | Snapshot-diff of voice names around a palette's `defs`; remove a refused palette's voices | `SynthDef.removeAt` frees the desc and sends `/d_free` [VERIFIED: SCClassLibrary/Common/Audio/SynthDef.sc:567-573] |
| `Server:avgCPU` / `peakCPU` / `numSynths` / `numSynthDefs` | core class library | CPU and node observability | Exposed on `Server` [VERIFIED: Server.sc:916-921]; status polled every 0.7 s (`aliveThreadPeriod = 0.7`, ServerStatus.sc:6) so a 5 s window has about 7 CPU samples |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `RunningSum`, `Peak`, `SendReply`, `A2K` | core | Level probe: windowed mean square and peak sent to the language | The level tier (prototype below) |
| `BHiShelf`, `HPF` (BEQSuite) | core | Optional K-weighting approximation before the RMS | Only if plain RMS disagrees with the by-ear pass |
| pytest 8.4.2 in `.venv` (Python 3.13.12) | installed | Existing Python suite (191 tests); unaffected | Run once at the end to prove `python_app/` is untouched |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Per-voice gain constants as the level trim | A core-applied per-palette `trim` key multiplying row amp | A `trim` key is a second new contract key (costly to reverse) and the files are frozen anyway, so a wrong trim means a new file either way; voice-internal constants need no core change |
| Palette in the harmony entry | Separate palette memo module | A separate memo would have to re-implement cycle-start and progression-change detection that the harmony memo already has |
| Prefetch every palette file at Auto engage | Prepare one phrase ahead per pick | Per-pick preparation needs `s.sync` outside a Routine-safe place (the layers run in a Prout and cannot sync); with about 10 palettes the all-at-once cost is one-time (the prototype loaded all 7 palette files through the real `~ppLibEnsure` in one pass, about 4 to 6 SynthDefs each) |
| Level tier inside `library_test.scd` (CONTEXT D-13/D-15) | A new `palette_test.scd` with its own watchdog | Separate file keeps the existing 300 s budget but duplicates helpers (review IN-05 already flags the duplication); CONTEXT says "the library check", so default to the same file with a larger watchdog |

**Installation:** none. `npm`/`pip`/`cargo` are not used in this phase.

**Version verification:** no external packages are added. The only version-sensitive tool is sclang itself: 3.14.1 confirmed above, and every API used here (`SynthDef.removeAt`, `SynthDescLib.global.synthDescs`, `Server:avgCPU`) was read in the installed class library.

## Package Legitimacy Audit

No external packages are installed by this phase (no pip, npm, cargo, quark or sc3-plugins). `gsd-tools query package-legitimacy check` was not run because there is nothing to check.

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
 GUI (unchanged)                                   SuperCollider (sclang)
 ---------------                                   ----------------------------------------------
 Palette dropdown --/pp/palette "auto"|"acid"-->  OSCdef(\pp_palette) --> ~ppSelect
                                                       |  validates name (~ppStemValid), then
                                                       |  background Routine on SystemClock:
                                                       |    named -> ~ppLibEnsure (load, validate,
                                                       |            defs + s.sync, prefix guard)
                                                       |    auto  -> ~ppSel = \auto + ~ppAutoPrefetch(\palettes)
                                                       v                (loads EVERY palette file, once)
                                               ~ppSel[\palettes], ~ppLib[\palettes] (registry)
                                                       |
   each bar, first layer to ask builds the entry:      v
   +--------------------------------------------- ~ppHarmonyFor(bar, songBar) ---------------+
   | cycle decision (Phase 6)  --> cycleBar == 0 ? progChanged = (stem != lastStem)          |
   | palette stage (NEW), strictly in bar order:                                              |
   |   sel named & loaded -> that stem                                                        |
   |   sel auto           -> ~ppPalAutoNext: hold counter -=1 per bar; at a boundary bar     |
   |                         with hold expired -> seeded random pick from registered files   |
   |   log "palette <stem>: <desc>" when the stem differs from the last bar                  |
   |   entry[\palette] = stem                                                                 |
   +------------------------------------------------------------------------------------------+
        | memoized entry (same Event for all layers of that bar)
        v
   ~ppRenderBar(role, songBar, bar, layerState)  -- kick, hat, clap now also pull the entry
        palStem = entry[\palette] ? ~ppResolveStem.(\palettes)
        inst    = ~ppInstrumentFor.(role, palStem)        (palette voice, else classic's)
        bass    : mod = entry[\mod] (progression). If the core default bass plays, plan[\bassStyle]
                  = palette's bassStyle  -> ~ppBassStyles[style] rows (chord root + pickup)
        |
        v   rows [inst, note, dur, amp, legato] --> Pbindef (quant 4) on ~clock
   voices --> ~ppMixBus --> \ppFx (EPIC) --> \ppMaster Limiter(0.891251) --> out
   Stop: ~ppInstrGroup.set(\gate, 0)  (every pitched voice has gate; drums self-free)
```

### Recommended Project Structure

```
supercollider/
├── core/
│   ├── validate.scd   # WR-01 bounds in ~ppRowsValid; palette: bassStyle value, pp_<stem>_ prefix (stem arg)
│   ├── loader.scd     # ~ppLibEnsure palette branch: snapshot-diff guard + restore; ~ppAutoPrefetch(cat); auto message
│   ├── harmony.scd    # palette stage in ~ppHarmonyFor; ~ppPalAutoNext; ~ppBassStyles; tunables
│   └── render.scd     # drums pull the entry; ~ppInstrumentFor.(role, stem); bassStyle into plan
├── library/palettes/
│   ├── classic.scd    # frozen
│   ├── _template.scd  # not guarded (leading _): document bassStyle, prefix rule, level tuning
│   └── <6 new>.scd    # each FINAL when first committed
├── library_test.scd   # new tiers (levels, cpu, auto landing, bounds, prefix) ; watchdog 300 -> ~480
├── smoke_test.scd     # palette Stop / rotation-leak / VO2 no-clip checks ; (watchdog 360 has ~170 s headroom)
├── palette_cpu.scd    # NEW: one-minute CPU measurement for D-15 (own isolated server)
scripts/
├── check.sh           # TIMEOUT 330 -> match new watchdog
└── palette_cpu.sh     # NEW: wrapper, prints "avg/peak" and PASS/FAIL against 25%
```

### Pattern 1: Palette as per-bar harmony-entry state

**What:** Add `palette` (a stem Symbol) to the entry that `~ppHarmonyFor` builds once per song bar. Every layer, **including the three drum layers** (which do not pull the entry today), reads `entry[\palette]`.
**Why:** Today `~ppInstrumentFor.(role)` resolves the palette at the moment each layer renders its bar. With Auto, seven layers whose bar-start events land on the same beat in unspecified order could see different palettes on the switch bar (kick old, bass new). The memo already solves this for chords [VERIFIED: harmony.scd:7-13 header]. Falling back to `~ppResolveStem.(\palettes)` when `entry[\palette]` is nil keeps the non-memo paths (explicit 5-argument calls in the strict chord check, the fallback `~ppHarmClassicEntry`) identical to today.
**Hook points:** `~ppRenderBar` computes `inst` before it computes `entry` (render.scd:167 then 175-182 [VERIFIED]); reorder so the entry is pulled first for every role. Drums must keep byte-identical rows under classic (the parity golden).

### Pattern 2: Auto palette state and the landing rule

**What:** State inside the run memo, mirroring the Phase 6 progression Auto: `h[\palAuto] = (current:, holdLeft:, history:, waitedBars:)`. Created with the run in `~ppHarmonyFor` (a Start begins a new rotation, D-08 says the first pick is random, not classic).
**Rules (from D-05..D-08):**
- Count `holdLeft` down by one for every bar the memo builds (song bars, so Stop pauses it; the memo is rebuilt per run).
- A **boundary bar** is a cycle start (`cycleBar == 0`) where `progChanged` is true if the progression selection is `auto`, or every cycle start if the progression is a named lock. `progChanged` is `cyc[\stem] != h[\lastStem]` evaluated before `lastStem` is updated at harmony.scd:374-377 [VERIFIED]; at a run start `lastStem` is nil so the first cycle is a boundary (that is the "random from the start" pick).
- At a boundary with `holdLeft <= 0` (or at engage), draw a pick: seeded, never the current and never the last two (pool fallback `reject current only`), exactly like `~ppHarmAutoNext` (harmony.scd:258-263).
- **Fallback needed:** Phase 6's Auto can hold the same stem forever when it has no other candidate (`stem = if (pool.isEmpty) { cur } ...`, harmony.scd:263), so `progChanged` may never become true again. Add `maxWaitBars` (about one long cycle, 64): once `holdLeft <= -maxWaitBars`, the next cycle start is a boundary regardless.
- Draw counter: a **separate** global `~ppPalAutoPicks = ~ppPalAutoPicks ? 0` and a distinct salt in the seed formula, so palette draws never shift the replayable progression order promised in the README (Phase 6 WR-02: counter lives outside `~ppHarm` so Stop/Start continues the sequence). Reuse `~ppAutoSeed`.
- Candidates: registered palettes (sorted by name, valid name, file still in the library root, fewer than 3 render failures) — same filter as `~ppAutoCandidates` (harmony.scd:205-215).
- Mid-ride return to Auto after a named lock: mirror Phase 6's "Engage": adopt the palette that plays now and hold it for a fresh hold (README documents this for progressions). Open Question 2 asks the user to confirm.

**Tunable:** `~ppPalHoldBars = ~ppPalHoldBars ? [lo, hi]` (the `x = x ? default` idiom the module uses; see harmony.scd:55). Hold-time math in Common Pitfalls (tempo dependence).

### Pattern 3: Prefetch all palette files at Auto engage

**What:** Generalise `~ppAutoPrefetch` (loader.scd:184-221, scans only `progressions`) to take a category. For `\palettes` it runs `~ppLibEnsure` for every valid stem on disk not yet registered, inside the existing single background Routine. `~ppLibEnsure` already does `defs` + `s.sync` for palettes (loader.scd:135-145 [VERIFIED]).
**Why:** The layers call into the harmony memo from a Prout; they cannot `s.sync`. So Auto may only pick from palettes that are **already registered**. This also delivers "any new palette file joins the rotation automatically" and "prepare ahead" in one move.
**Triggers:** `~ppSelect` for `palettes` + `auto` (replace the "resolves to classic" branch at loader.scd:250-252), `main.scd:174` (stored auto selection after re-evaluation), and each palette Auto pick (as progressions do).
**Bounds:** cap the number of palette files prefetched (progressions use 256; each palette adds roughly 4–6 SynthDefs and the server default is `maxSynthDefs: 1024` [VERIFIED: Server.sc:71], so cap palettes near 32).
**First-pick race:** the engine autostarts and the GUI sends `auto` at launch (Phase 5 D-04), so the first bar can be built before the prefetch finishes. Then only `classic` is registered and the first pick is `classic`. Accept and document it, or have the run-start engage wait a few bars; tests must wait for `~ppAutoPrefetching != true` before asserting randomness.

### Pattern 4: Bass style as a core table selected by a palette key

**What:** A new optional top-level palette key `bassStyle: \<name>` (Symbol). The core defines `~ppBassStyles` next to `~ppDefaultBass`; each entry is a pure function `{ |chord, next, changesNext| }` returning rows that sum to 4 and keep the Phase 6 rules: sounding notes are chord tones, root first, the last slot is the pickup toward the next chord when `changesNext`, otherwise the chord's third.
**Applies only when the core default bass plays** (progression with `chords` and no own `bass` generator; render.scd:212-215 [VERIFIED]). Under `classic` progression the frozen generator keeps producing v1 rows whatever palette is picked; document this in the README so the rider is not surprised that `acid` + `classic` progression keeps v1 rhythm.
**Styles to ship (names are the planner's):** `eighths` (= current `~ppDefaultBass`, the default when the key is absent), `sixteenths` (rolling 16ths, rest on each beat's first 16th), `octave` (offbeat eighths alternating root and root+12).
**Validator:** a known key with an unknown value is refused (typo protection), matching how `defs is not a Function` is refused today. Unknown *keys* stay ignored per the contract-freeze rule (validate.scd:9-12 header).
**Existing check impact:** `strictChordCheck` asserts "sounds 4 notes, expected 4 offbeat notes" for the bass (library_test.scd:358-366 [VERIFIED]); it renders with explicit entries and `~ppSel[\palettes]` classic, so it stays valid for `eighths` and a new per-style loop covers the others.

### Pattern 5: Hardening — WR-02 defs guard (the pattern to implement)

Run the palette's `defs`, then diff `SynthDescLib.global.synthDescs` against a snapshot taken just before. Any **new or replaced** SynthDesc whose name does not start with `pp_<stem>_` refuses the file. Cleanup: `SynthDef.removeAt` every new name the file added; re-run `classic`'s `defs` (+ `s.sync`) if a foreign name was replaced; on a failed reload of an already registered stem, re-run the previously registered module's `defs`. Verified in a server-less prototype: a defs that adds `pp_x_bass` and redefines `\ppArp` reports `touched: [ppArp, pp_x_bass]`, foreign `[ppArp]`, and after `SynthDef.removeAt(\pp_x_bass)` only `[ppArp]` remains touched. Put it in one function used by `~ppLibEnsure`, the static tier (library_test.scd:608-615 runs `defs` directly) and the voice tier (1270-1275), so there is one definition.
Also add the static prefix rule to `~ppValidate` (needs the stem: pass it as an optional third argument; `~ppLibLoad` has it at load): every `roles[...][\instrument]` of a non-classic palette must start with `pp_<stem>_` **or** be one of classic's own role instruments (so the committed `_template.scd`, which maps all seven roles to `\ppKick ... \ppArp`, and the test fixture `bad_defs` stay valid).

### Pattern 6: Hardening — WR-01 bounds

Add to `~ppRowsValid` (validate.scd:100-142): rows per bar `<= 64`; `dur >= 1/32`; legato `<= 8`; note (Number) in `-12..127`; chord size `<= 8`. **Do not use the reviewer's `legato <= 4`:** Phase 6's default pad sets `legato = min(0.9 * plan[\chordBars], plan[\chordBars] - (~ppPadGapBeats / 4));` (harmony.scd:538) and chord `bars` may be 1 to 8 (validate.scd:78-80), so a 5-bar chord needs 4.5 and an 8-bar chord 7.2; a cap of 4 would make a legal progression fall back to classic on its pad. 8 covers 7.2. Optional aggregate guard against pile-ups: reject a bar whose `sum(dur * legato * max(1, chordSize))` exceeds a budget (shipped worst case is the 8-bar-chord pad at 4 * 7.2 * 3 = 86 voice-beats); this addresses "many long overlapping voices" that per-row caps alone allow (64 rows * 32 beats). Add negative cases to the `rows validation` block (library_test.scd:2347 onward).

### Pattern 7: Level / headroom / CPU tier (real time)

**Measurement as prototyped:** boot is already done by the library test (isolated server 57141, `s.volume.mute`). Insert a probe after `~ppFxGroup` reading `~ppFxBus` (post-FX, pre-limiter, unaffected by the mute because the mute lives at the root tail). Config for every palette including `classic`: tempo 180 BPM, progression `anthem` locked (chord data, so the core default bass and pad are active), melody `classic_lead_loud` (lead audible, so each palette's lead voice counts), EPIC fixed (D-13 says one level; use 50 and add 75 only if time allows). Settle one bar after switching, then measure exactly 4 bars (5.3 s at 180 BPM). Gap = `rms.ampdb - classicRms.ampdb`; fail at `abs(gap) > 1.5`.
**Pre-limiter peak at VO2:** EPIC 100, volume 100 (unity, see main.scd master): fail if the post-FX peak exceeds 0.80 (the limiter ceiling is 0.891251; classic measures about 0.5, matched drafts 0.55 to 0.57, the unmatched `warm` draft 0.845). Output peak at bus 0 must stay at or below 0.892 (existing `max epic max volume no clip` logic, smoke_test.scd:1783-1791).
**CPU:** read `s.avgCPU` and `s.peakCPU` in the same loop; print per palette; `CHECK WARN` above about 12% average, fail at the agreed 25% (the dev run is without Zwift).
**Authoring loop:** support `PP_PALETTE=<stem>` (the harness already reads `PP_GOLDEN_RECORD` with `getenv`, library_test.scd:62) so an author can iterate one palette in about 15 s instead of the whole tier.

### Pattern 8: One-command CPU measurement (D-15)

A small `scripts/palette_cpu.sh` + `supercollider/palette_cpu.scd`, shaped like `scripts/smoke_test.sh`: its own isolated server (a port not used by the live engine 57110/57120, smoke 57140, library 57141, for example 57142), load `main.scd`, set 180 BPM, EPIC 100, progression `anthem`, melody `classic_lead_loud`, lock the chosen palette (default: the one the library check measured heaviest), run 60 s sampling `s.avgCPU` every 0.7 s, print `mean`, `max sample` and `s.peakCPU`, and exit 0 only if mean is under 25. It does not touch the rider's running engine. The rider runs it with Zwift open; the number reflects contention because scsynth's load is measured against the audio callback budget.

### Anti-Patterns to Avoid

- **A library file that adds persistent synths, buffers or per-voice reverb/delay.** FX stay in `\ppFx` (PITFALLS Pitfall 6, STACK item 10). The static lint already forbids `Synth(`, `~`, `Server` and others (library_test.scd:475-480).
- **Deciding Auto inside the layer's own Prout without the memo.** Layers disagree on the switch bar.
- **Loading palette files lazily on the switch bar.** Needs `s.sync` outside a Routine; prefetch instead.
- **Editing a committed palette to fix its level.** The guard fails it; the fix is a new file (for example `acid2`). Tune before the first commit that reaches `origin/main`.
- **Changing `~ppDrumGrid` rows or any classic row.** The golden parity depends on it.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| "Which palette applies to this bar" for seven layers | A second memo or per-layer timers | The existing `~ppHarmonyFor` entry (add a field) | Order-independent by construction; already handles Stop/Start, tempo glide and the 64-bar keep window |
| Auto pick (seeded shuffle, history, no quick repeat) | New randomness code | Copy the structure of `~ppHarmAutoNext` with a separate counter | Already proven and test-covered (replay, bounded history) |
| Disk scan + safe load of files that appear while running | A new watcher | `~ppAutoPrefetch` generalised | Containment, name rule, one-at-a-time, broken-file-once logic already exist |
| Unregistering a refused palette's voices | Manual `/d_free` bookkeeping | `SynthDef.removeAt(name)` | Removes the client desc and frees on all servers in one call [VERIFIED: SynthDef.sc:567-573] |
| Voice safety check (own bus, no bus 0, gate honoured, frees) | A new check | The existing `voiceContractMany` tier (library_test.scd:1209-1264) | Already covers every palette stem on disk, including future ones |
| Level meter | A custom FFT loudness tool | `RunningSum` mean square + `Peak` via `SendReply`, averaged in the language | Prototype proved it repeatable (two classic runs identical). `Loudness` (FFT, sones) exists in core but adds nothing at this tolerance |
| Rider-facing palette naming | A GUI display | One `~ppLog` line `palette <stem>: <desc>` | App is send-only by decision |
| CPU "budget" metric | OS-level process sampling | `s.avgCPU` / `s.peakCPU` | This is the metric the decision names (D-14) |

**Key insight:** every hard part of this phase already has a working template in Phase 4 to 6 code. The risk is in the seams (render order, async loading, frozen files), not in new algorithms.

## Common Pitfalls

### Pitfall 1: By-feel voices are far louder than classic, and the limiter hides it
**What goes wrong:** Palettes written without measuring jump in level at rotation; a hot palette is also squashed by the limiter at VO2.
**Why it happens:** Row amps are shared by every palette (bass 0.1, arp 0.1, pad 0.06, kick/hat 0.1, clap 0.25), so loudness is set only by each voice's internal gain structure.
**Evidence:** [VERIFIED: prototype loop this session, post-FX RMS at EPIC 30/75/100, gap versus classic in dB, first drafts before any trim] supersaw -0.6/0.0/+0.1, acid +0.1/+0.5/+0.5, **warm +8.2/+7.8/+7.4**, pluck +2.7/+2.8/+2.7, dark +2.5/+2.4/+2.3, **air +5.2/+5.5/+5.2** (dark and air derived from the printed dBFS values: dark -20.5/-18.1/-17.0 and air -17.8/-15.0/-14.1 against classic -23.0/-20.5/-19.3). The unmatched `warm` peaked at 0.845 post-FX at EPIC 100 against the 0.891 limiter ceiling.
**How to avoid:** Measure first, then put one scalar gain per voice in the SynthDef, re-measure. Keep each voice's gain constant a literal in the file.
**Warning signs:** gap above 1.5 dB; post-FX peak above 0.8 at EPIC 100.

### Pitfall 2: Matching at one EPIC level does not prove matching at all levels
**What goes wrong:** `\ppFx` low-passes with a cutoff that follows EPIC (500 Hz to 9 kHz), so a bright palette can match at EPIC 50 and be quieter at Recovery.
**Evidence:** the matched drafts moved by up to 0.6 dB between EPIC 30 and 75, a small drift here, but a very bright or very bassy voice would drift more [prototype, same run].
**How to avoid:** gate at one EPIC (D-13) with a stricter authoring target (aim for |gap| <= 0.75 so the 1.5 dB gate holds across zones) and check a second EPIC in the by-ear pass. Pitfalls research lists EPIC 30 and 75 as the usual pair [CITED: .planning/research/PITFALLS.md Pitfall 7].

### Pitfall 3: The library check will blow its watchdog
**What goes wrong:** `library_test.scd` has a hard watchdog and `check.sh` its own timeout; the real-time tier adds minutes.
**Evidence:** baseline `bash scripts/check.sh --library-only` took **2:18 wall** this session (`real 2:18.63`, `CHECK PASS (library only)`); the library watchdog is `SystemClock.sched(300, {` (library_test.scd:51) and `TIMEOUT_CMD="timeout 330"` (check.sh:218). The prototype loop (7 palettes, 3 EPIC points, 3 s settle each) took **175 s** by itself. A leaner tier (one EPIC point for levels at about 6.5 s per palette, plus one VO2 pass) is about 90 to 100 s. The smoke suite took **3:10 wall** with a 360 s watchdog and `timeout 390` (smoke_test.scd:31, smoke_test.sh:32), so it has about 170 s of headroom.
**How to avoid:** raise the library watchdog and the `check.sh` timeout together in the same task that adds the tier (for example 300 -> 480 and 330 -> 510), keep the settle time minimal (the EPIC smoother needs about 3 s after a change, so change EPIC twice for the whole tier, not per palette), and provide `PP_PALETTE`.

### Pitfall 4: A committed palette file can never be tuned afterwards
**What goes wrong:** Level or CPU problems found after commit force a new stem.
**Evidence:** guard pattern `'supercollider/library/*/[a-z0-9]*.scd' 'supercollider/golden/*.scd'` (check.sh:79) fails on modify, delete or rename. The base is `LIBRARY_GUARD_BASE`, else the merge-base with `origin/main` (check.sh:202-205); `origin/main` exists (c18011d) so a file added after that commit and edited before pushing still reads as added and passes. Do not rely on that: treat "first commit" as final.
**How to avoid:** write the level tier before committing any palette; commit each palette only when its gap, peak, CPU and voice tier are green; leave the by-ear tuning for a new file.

### Pitfall 5: Existing tests encode "auto means classic" for palettes
**What goes wrong:** `auto plays classic` sends `auto` to all three categories and requires the next four bars to equal the golden (library_test.scd:1586-1598, quoted: `sendSel.('/pp/palette', 'auto');`), and the loader prints `"PedalPulse: % auto -> auto (resolves to classic)"` (loader.scd:251). With D-08 the first palette after Start is random, so this check fails by design.
**How to avoid:** change that check to melody + progression only (palette stays `classic`), move the palette Auto assertions into new checks, and update the log line, README ("For melodies and palettes it still plays classic until their own phases arrive"), and `~ppSelect` comments.

### Pitfall 6: Voices must respect the lint and the voice contract or the whole tier fails
**What goes wrong:** the static lint refuses a file containing any of these tokens (code only, comments and strings stripped): [VERIFIED: library_test.scd:475-480]
`"~", "Pbindef", "Pdef", "Tdef", "Ndef", "Pbind", ".play", "fork", ".wait", "Routine", "Task", "TempoClock", "SystemClock", "AppClock", "Server", "Synth(", "Synth.", "OSCdef", "OSCFunc", "NetAddr", "unixCmd", "systemCmd", "File", "Pipe", ".load", "thisProcess", "interpret"`.
`SynthDef(` does not contain `Synth(` so voices are fine. The voice tier spawns each voice on a private bus at amp 0.1 (pitched voices at freq 220), requires signal on that bus within 0.6 s, none on bus 0, and zero nodes 2.0 s after `gate 0` (library_test.scd:1241-1254). So: release must end within about 1.8 s; drums have no gate so their envelope must finish within about 2.5 s; a pad with attack longer than 0.6 s still passes because the probe only needs a non-zero peak.
**Warning signs:** `nodes left after gate 0`, `no signal on its out bus`.

### Pitfall 7: Filter cutoffs derived from freq can exceed Nyquist
**What goes wrong:** `RLPF.ar(sig, freq * 7.5)` at a high note exceeds 22 kHz and can be unstable; NaN on `~ppMixBus` is carried by the persistent FX chain (04-REVIEW WR-01).
**How to avoid:** clamp every derived cutoff (for example `(freq * 6).min(12000)`), keep resonant filters behind `.tanh`, and consider a voice-tier extension that spawns each pitched voice at an extreme `freq` (very low and about 8 kHz) and asserts a finite, bounded peak. WR-01's note cap also protects the engine from above.

### Pitfall 8: Unreliable exit code at the end of the smoke run
**What goes wrong:** the smoke suite printed `SMOKE PASS` then crashed during sclang shutdown with `libc++abi: terminating due to uncaught exception of type std::__1::system_error: mutex lock failed: Invalid argument`, so `scripts/smoke_test.sh` (which requires exit 0 and `SMOKE PASS`) reported `smoke test FAILED`.
**Evidence:** [VERIFIED: this session, `/var/folders/.../pedalpulse-smoke.log` tail and the run's own `smoke test FAILED (log: ...)` line; 72 `CHECK OK` lines]. The library run in the same session exited cleanly. Not a Phase 7 regression (no repo change); sclang 3.14.1 on macOS 26.6.2 (Darwin 25.6.0).
**How to avoid:** rerun once before attributing a failure to Phase 7; if it repeats, route to `/gsd-debug`. STATE.md already lists a flaky `epic glide up` check and a `/g_queryTree` stall as known flakes; this is a third, at exit.

### Pitfall 9: Hold time is in bars, so minutes depend on the rider's tempo
**What goes wrong:** "4 to 6 minutes" is a different number of bars at different BPM: minutes = bars * 4 / BPM.
**Table (computed):** 96 bars = 4.0 min at 96 BPM, 3.2 min at 120, 2.1 min at 180; 160 bars = 6.0 min at 107 BPM, 5.3 min at 120, 3.6 min at 180; 128 bars = 5.7 min at 90 BPM. Phase 6's `[32, 64]` for "2-3 minutes" (harmony.scd:55) implies the author assumed about 85 to 90 BPM (64 bars * 4 / 90 = 2.8 min). Auto adds a wait for the next progression change (up to one 32 to 64 bar stay).
**How to avoid:** pick the default `~ppPalHoldBars` for a ride tempo of about 90 to 110 BPM, for example `[80, 128]` (hold 3.0 to 5.3 min at 96 BPM, plus the average 16-bar-ish wait to a progression change), keep it a tunable, and confirm the assumed tempo (Open Question 1).

### Pitfall 10: Node and SynthDef growth over a long rotation
**What goes wrong:** rotation that re-adds SynthDefs per switch, or an unbounded prefetch, grows `s.numSynthDefs` and `SynthDescLib` (PITFALLS Pitfall 6).
**How to avoid:** prefetch registers each stem once (a registered stem is not reloaded by the scan, same rule as progressions, loader.scd:197), cap the number of palette files, and assert that `s.numSynthDefs` and the registry size are unchanged after N accelerated rotations. Long-release voices raise concurrent node counts: the draft `air` palette reached `s.numSynths` 21 to 23 (including the probe synth) against the classic-era smoke bound of 22 (smoke_test.scd:1664), so any per-palette node bound should be relative (for example classic + 12) or about 40, far under `maxNodes` 1024.

### Pitfall 11: A palette named like a progression confuses the rider
**What goes wrong:** progression `anthem` already ships (Am F C G) [VERIFIED: `ls supercollider/library/progressions` shows `anthem.scd`]; a palette called `anthem` makes "the anthem one is too loud" ambiguous in the plain-language feedback loop, and both lines would read `progression anthem` and `palette anthem` in the post window.
**How to avoid:** D-01 explicitly lets the planner adjust the stems; use a distinct stem such as `supersaw` for the big-saw palette (my prototype used it) and avoid reusing any progression or melody stem.

## Code Examples

All snippets below are drawn from running code in this session's scratch prototypes unless marked otherwise.

### Level probe and per-palette measurement (proven, repeatable to 0.0 dB)

```supercollider
// Source: scratchpad prototype (proto/loop.scd), run against the real main.scd engine
SynthDef(\ppProtoRms, { |in = 0|
	var sig = In.ar(in, 2);
	var p = (sig.squared.sum) * 0.5;
	var avg = RunningSum.ar(p, 8192) / 8192;
	SendReply.kr(Impulse.kr(20), '/pp/proto/ms', [A2K.kr(avg), Peak.ar(max(sig[0].abs, sig[1].abs))]);
}).add;
// measure: probe after ~ppFxGroup on ~ppFxBus, wait 4 bars at the current tempo,
// rms = (mean of replies' mean-square).sqrt ; gap = rms.ampdb - classicRms.ampdb
```
Note `Peak.ar(sig).asArray.maxItem` fails ("Non Boolean in test"): compare channels with `max(sig[0].abs, sig[1].abs)` first.

### Palette defs guard (WR-02), verified without a server

```supercollider
// Source: scratchpad prototype (proto/snap.scd)
snapshot = { SynthDescLib.global.synthDescs.copy };
touched = { |before|
	var out = List.new;
	SynthDescLib.global.synthDescs.keysValuesDo { |k, d| if (before[k] !== d) { out.add(k) } };
	out.asArray
};
before = snapshot.value;
mod[\defs].value;                       // inside the Routine, then s.sync
foreign = touched.(before).reject { |k| k.asString.beginsWith("pp_" ++ stem ++ "_") };
// foreign.notEmpty -> log ERROR, SynthDef.removeAt on every new name,
// re-run ~ppLib[\palettes][\classic][\defs].value ; s.sync, return false
```

### Palette file skeleton (loads, passes the voice contract; level numbers are pre-trim)

```supercollider
// Source: scratchpad prototype lib/palettes/acid.scd (voices passed the contract: bus peak > 0, bus0 0.0, 0 nodes left)
(
desc: "Acid: squelchy 303-style resonant bass, bright pulse arp, sharp acid lead, thin pad",
defs: {
	SynthDef(\pp_acid_bass, { |out = 0, amp = 0.1, freq = 55, gate = 1|
		var env = EnvGen.kr(Env.adsr(0.002, 0.1, 0.5, 0.05), gate, doneAction: 2);
		var fenv = EnvGen.kr(Env.perc(0.002, 0.2));
		var sig = Saw.ar(freq);
		sig = RLPF.ar(sig, (freq * 2) + (fenv * freq * 14), 0.2).tanh;
		Out.ar(out, (sig * env * amp * 1.5).dup);       // 1.5 = the level trim constant
	}).add;
	// ... pp_acid_arp, pp_acid_pad, pp_acid_lead
},
bassStyle: \sixteenths,                               // NEW optional key (Pattern 4)
roles: (
	bass: (instrument: \pp_acid_bass), arp: (instrument: \pp_acid_arp),
	pad: (instrument: \pp_acid_pad), lead: (instrument: \pp_acid_lead)
)
)
```

### Reading the palette per bar (shape of the change; not final code)

```supercollider
// in ~ppRenderBar, before the drum/pitched split (entry now pulled for every role)
entry = entry ? try { ~ppHarmonyFor.(bar, songBar) } { |err| ... ~ppHarmClassicEntry.() };
palStem = entry[\palette] ? ~ppResolveStem.(\palettes);
inst = ~ppInstrumentFor.(role, palStem);               // new optional 2nd argument
// bass: when gen === ~ppDefaultBass, plan[\bassStyle] = ~ppLib[\palettes][palStem][\bassStyle]
```

## Palette voice recipes (starting points, from the prototype)

All 26 voices below ran through the real loader and the voice-contract logic. Musical quality is **not** verified (no ears in this session): the rider's listening pass decides. Gain constants shown are the pre-trim values used in the run.

| Stem (working) | Character devices that loaded and met the contract | Pre-trim gap vs classic (EPIC 30/75/100) | Needed trim |
|----------------|---------------------------------------------------|------------------------------------------|-------------|
| supersaw (was anthem) | 7-saw `Splay` pad + `LPF` 3200; 5-saw `RLPF` arp (cutoff `min 12000`); 5-saw lead; saw+sub bass | -0.6 / 0.0 / +0.1 | none |
| acid | `Saw` -> `RLPF` rq 0.2 with a perc cutoff env + `.tanh` bass; resonant pulse arp; saw acid lead; thin pulse pad | +0.1 / +0.5 / +0.5 | none |
| warm | `LFTri` + sine bass `LPF` 500; `LFTri` pair arp; sine/`LFTri` pad with slow vibrato `SinOsc.kr`; vibrato lead | +8.2 / +7.8 / +7.4 | about -8 dB (my gains were too high) |
| pluck | `Pulse` bass with fast filter env; `Pluck.ar(WhiteNoise.ar(0.5), 1, 0.05, freq.reciprocal, 1.2, 0.3)` arp; PWM pulse pad; FM pluck lead; short hi-hat | +2.7 / +2.8 / +2.7 | about -2.7 dB |
| dark | longer deeper kick (`XLine.kr(110, 38, 0.2)`, 0.55 s) plus a click; saw bass `LPF` 380 into `.tanh`; `BPF` narrow-pulse arp; murky `LPF` 700 pad; folded lead | +2.5 / +2.4 / +2.3 | about -2.4 dB |
| air | sine bass; 2-op FM bell arp and lead (`SinOsc` modulated by `SinOsc` at 3.5x / 2.01x, perc index env); sine-stack shimmer pad with `HPF` 150 | +5.2 / +5.5 / +5.2 | about -5.3 dB |

Because `bassStyle` is not implemented in the core, these numbers do not include the style rhythms; re-measure after Pattern 4 lands. Voices that used the release lengths shown (pads 1.0 to 1.6 s) freed within the 2.0 s window.

## CPU findings (this M1 Mac, headless, muted)

[VERIFIED: prototype runs this session, `s.avgCPU` / `s.peakCPU`]
- Classic at EPIC 30/75/100: avg 5.1 / 4.7 / 4.3, peak 6.7 / 7.1 / 7.9. The repo's own smoke log shows `server CPU avg 4.2996397018433 peak 6.8914031982422`.
- A deliberately heavy first draft (7-saw pad, 5-saw arp and lead) at EPIC 50 to 100: avg 5.1 to 6.4, peak 8.2 to 8.7 (a separate 30 s run: avg 6.4).
- Final six-palette loop: highest avg 7.3 (supersaw at EPIC 75), highest peak 10.6; every other palette 3.9 to 5.6 avg.
- So the 25% budget is about 3.4x the heaviest measured palette. The check should still fail loudly if a future palette approaches it, but CPU will not be the binding constraint for stock-UGen voices at 16th-note arp rates. The unknown that only the rider's machine can answer is contention with Zwift; hence D-15's one-minute measurement with Zwift open.
- `s.avgCPU` is refreshed by the status poll every 0.7 s, so sample for at least 30 s on the rider's measurement (60 s as decided) and report the mean of the samples and the maximum.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `auto` palette resolves to `classic` (Phase 4 placeholder) | Auto = seeded rotation landing on progression changes | This phase | Real-ride startup now opens on a random palette; engine-only startup still defaults to classic |
| Instrument looked up per layer at render time | Instrument looked up from the bar's memoized entry | This phase | One palette per bar for all layers |
| WR-01 / WR-02 deferred (Phase 4 review disposition) | Fixed here | This phase | Needed before the prefetch loads many files |

**Deprecated/outdated:** the README sentence "For melodies and palettes it still plays classic until their own phases arrive" and the `palette auto` log wording; `ARCHITECTURE.md` says rotation lands on "section boundaries" and uses 128 to 256 bars, which CONTEXT D-05..D-07 supersede (landing on progression changes, about 4 to 6 minutes).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The rider's typical ride tempo is about 85 to 110 BPM, which sets the bar-count equivalent of "4 to 6 minutes" | Pitfall 9, Pattern 2 | Rotation noticeably faster or slower than intended; only a tunable default changes |
| A2 | The "riding Mac" is this M1 MacBook (Zwift.app is installed here; `sysctl` says Apple M1, macOS 26.6.2), so headless numbers here predict the Zwift-side numbers up to contention | CPU findings | CPU budget conclusions could shift on a different machine |
| A3 | A 0.80 post-FX peak ceiling at EPIC 100 is a sensible "limiter rarely engaged" gate (classic about 0.5, matched drafts about 0.55) | Pattern 7 | Too tight or too loose a gate; trivially retuned |
| A4 | Plain RMS over 4 bars at 180 BPM tracks perceived loudness well enough that the by-ear pass confirms it; K-weighting (`BHiShelf`/`HPF`) is the fallback | Pattern 7, Standard Stack | UAT finds audible jumps despite a green check; switch metric |
| A5 | A palette-switch bar overlapping an old pad release with a new pad attack does not produce an audible bump (so no crossfade logic is needed under D-10/D-12) | Pattern 1 | A short level bump at switches; mitigate with shorter pad attack or release, not a core change |
| A6 | Returning to Auto after a named lock should adopt the playing palette for a fresh hold (mirrors Phase 6 README), rather than rotating at the next boundary | Pattern 2 | Rider waits a full hold after picking Auto; UAT confusion |
| A7 | `maxWaitBars` of about 64 is the right fallback when Auto progression never changes again | Pattern 2 | Palette rotation could stall (too long) or fire off-chapter (too short) |
| A8 | Suggested `bassStyle` values per palette (acid sixteenths, dark sixteenths, pluck octave, others eighths) fit the characters | Palette recipes | Purely musical; rider can ask for new files |
| A9 | The six draft sound devices (supersaw, 303 resonant filter, FM bell, Pluck, etc.) will be recognisably different **by ear** | Palette recipes | Fails success criterion 1 at UAT; fixed by new files |
| A10 | The smoke-run exit crash (`mutex lock failed`) is an environment/shutdown flake and not caused by repo code | Pitfall 8 | The standing gate fails spuriously; needs `/gsd-debug` if it repeats |
| A11 | Capping prefetched palette files at about 32 is enough and safe | Pattern 3 | A very large library silently ignores files past the cap |

## Open Questions

1. **Default hold bars and the ride-tempo assumption (A1).**
   - What we know: D-05 says about 4 to 6 minutes, counted in bars; Phase 6 used 32 to 64 bars for "2 to 3 minutes".
   - What's unclear: the rider's usual BPM; whether the wait to the next progression change should count inside the 4 to 6 minutes.
   - Recommendation: default `[80, 128]` bars, tunable; ask the rider one question at UAT (what BPM do you ride at?).
2. **Auto after a named lock (A6).**
   - Recommendation: adopt-and-hold, same as progressions; confirm with the user because the success criteria say only "until Auto is picked again".
3. **Which palette is "heaviest" for D-15.**
   - What we know: the draft loop ranked supersaw highest, but final voices will differ.
   - Recommendation: the library tier prints per-palette CPU; the CPU script defaults to the highest from that run and accepts a stem argument.
4. **`classic` progression plus a styled palette.** The frozen classic bass generator ignores `bassStyle`. Confirm that is acceptable (it keeps parity) and document it; the alternative (restyling classic's rows in the core) risks the golden.
5. **First pick on a cold start.** The prefetch may not have finished when the first bar is built, so the first palette can be `classic`. Accept, or delay the engage by a few bars?
6. **Voice-tier extension for extreme frequencies (Pitfall 7).** Recommended but optional; decide whether it is in scope as part of WR-01.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| sclang / scsynth | all engine work and checks | yes | 3.14.1 (`/Applications/SuperCollider.app/Contents/MacOS/sclang`) | none needed |
| Project venv Python + pytest | Python regression run | yes | Python 3.13.12, pytest 8.4.2 | none needed |
| `timeout` / `gtimeout` | `check.sh` watchdog wrapper | yes | `/opt/homebrew/bin/timeout`, `/opt/homebrew/bin/gtimeout` | script runs without a timeout if both are absent |
| Zwift | D-15 CPU measurement by the rider | yes (`/Applications/Zwift.app`, `ZwiftLauncher-OSX` present) | — | run the CPU script without Zwift and report the delta |
| git with `origin/main` | library guard base | yes (`origin/main` = c18011d) | — | guard falls back to HEAD |
| Audio device | real-time server boot in tests | yes (library and smoke runs booted and ran today) | — | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none.

Machine: Apple M1, macOS 26.6.2 [VERIFIED: sysctl / sw_vers]. Ports in use by the harnesses: smoke 57140, library test 57141; the prototype used 57150; choose a different one for the CPU script (for example 57142) so a running engine (57110 / 57120) is never touched.

## Validation Architecture

Nyquist validation is enabled (`workflow.nyquist_validation: true` in `.planning/config.json`).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Headless sclang 3.14.1 scripts with a `CHECK OK` / `LIBRARY PASS` / `SMOKE PASS` line protocol; shell driver `scripts/check.sh`; pytest 8.4.2 for the (untouched) Python side |
| Config file | none (`scripts/check.sh`, `scripts/smoke_test.sh`) |
| Quick run command | `bash scripts/check.sh --library-only` (baseline 2:18 wall, 15 files; will grow) |
| Full suite command | `bash scripts/check.sh` (guard, library check, then smoke; smoke baseline 3:10 wall) |
| Single-palette authoring loop | proposed `PP_PALETTE=<stem> sclang -D supercollider/library_test.scd` (environment filter for the real-time tier) |
| Python regression | `.venv/bin/python -m pytest -q` (191 tests today; `python_app/` must stay byte-identical) |

### Phase Requirements -> Test Map

Check names are proposals (the planner is authoritative); existing check names are quoted from the Phase 6 logs.

| Req ID | Behavior | Test Type | Automated Command / Expected line | File Exists? |
|--------|----------|-----------|-----------------------------------|-------------|
| PAL-01 | 6 palettes + classic load, validate, lint clean, render their own voices | static + voice + count | `bash scripts/check.sh --library-only` -> `LIBCHECK OK: palettes/<stem>` per file, `CHECK OK: voices <stem>` per palette, `CHECK OK: library file count (21 files)` (15 today + 6) | tiers exist; new files are Wave 0 |
| PAL-01 | Every palette has its own pitched voices (disjoint instrument sets with each other and with classic) and a unique `desc` | static (new) | `CHECK OK: palettes are distinct` | no (new) |
| PAL-01 | "Recognisably different" in the mix | manual | by-ear UAT pass, switching palettes | UAT |
| PAL-02 | Auto rotates; first pick after Start is random; no quick repeats; lands only on a progression change (Auto progression) or a cycle start (locked) and on the same bar for all seven layers | integration (`recordBars`, instrument per bar, `~ppHarmCycleLog`) with a small `~ppPalHoldBars` | `CHECK OK: auto palette rotates`, `CHECK OK: auto palette lands on a progression change`, `CHECK OK: auto palette with a locked progression`, `CHECK OK: auto palette no quick repeats` | no (new) |
| PAL-02 | Replayable draws; counter survives Stop/Start; hold counts song bars | integration | `CHECK OK: auto palette replays from the seed`, `CHECK OK: auto palette hold survives stop and start` | no (new) |
| PAL-02 | New palette file joins; failing / broken palette skipped, reported once; registry and `numSynthDefs` bounded | integration | `CHECK OK: auto adds a new palette file`, `CHECK OK: auto skips a failing palette`, `CHECK OK: auto palette stays bounded` | no (new) |
| PAL-03 | Named pick takes over from the next bar and never rotates; `auto` re-engages | integration | `CHECK OK: named palette locks`, `CHECK OK: named palette plays from the next bar` | no (new) |
| PAL-03 | Existing selection checks keep passing with `auto plays classic` limited to melody + progression | integration (modified) | `CHECK OK: auto plays classic`, `CHECK OK: select palette and progression`, `CHECK OK: invalid names ignored`, `CHECK OK: latest wins` | yes (edit) |
| PAL-04 | RMS gap to classic within 1.5 dB at the fixed EPIC for every palette; prints the numbers | real-time tier (new) | `PedalPulse libtest: palette level <stem> gap=<x> dB` then `CHECK OK: palette level <stem>` | no (new) |
| PAL-04 | VO2 + volume 100: post-FX peak <= 0.80 and output peak <= 0.892 for every palette (loudest included) | real-time tier + smoke | `CHECK OK: palette headroom <stem>`; smoke `CHECK OK: palette max epic max volume no clip` | no (new) |
| PAL-04 | No volume jump across a switch (bar RMS before/after a switch within a few dB) | real-time tier (optional) | `CHECK OK: palette switch no jump` | no (new) |
| PAL-04 | Nothing bypasses the limiter | voice tier (exists) | `CHECK OK: voices <stem>` (bus 0 stays silent) plus existing `CHECK OK: limiter no bypass` | yes |
| D-02 | Each `bassStyle` keeps notes in the chord, rows valid, rests/pickup rule; classic progression unchanged under any palette | integration | `CHECK OK: bass styles follow the chord`, `CHECK OK: classic bass unchanged under every palette`, existing `CHECK OK: parity` | partly (extend `strictChordCheck`) |
| D-16 / WR-01 | Row bounds enforced; shipped data (including the 7.2 legato pad) still valid | unit + negative cases | extend `CHECK OK: rows validation`; add `CHECK OK: shipped rows within bounds` | edit |
| D-16 / WR-02 | A palette that redefines a foreign voice or leaves voices behind is refused and classic's voices are restored | integration with fixtures | `CHECK OK: palette defs stay in their prefix`, `CHECK OK: refused palette leaves no voices` | no (new fixtures) |
| Exit gate | Stop silences every layer under a non-classic palette; rotation leaks no routines, nodes or SynthDefs; re-evaluation with a stored auto selection stacks nothing | smoke | existing `CHECK OK: stop silences every layer`, `CHECK OK: eng-05 no stacking`, `CHECK OK: eng-05 module re-evaluation`; new `CHECK OK: palette stop and start`, `CHECK OK: palette rotation leaks nothing` | extend |
| D-14 / D-15 | CPU per palette probed and warned in the library check; heaviest at VO2 measured by script | real-time tier + script | `CHECK OK: palette cpu <stem>` or `CHECK WARN: palette cpu <stem> ...`; `scripts/palette_cpu.sh` prints mean/peak and exits 0 under 25% | no (new) |
| Python untouched | No GUI change | regression | `.venv/bin/python -m pytest -q` (191 passed) and `git diff --stat -- python_app` empty | yes |

### Sampling Rate

- **Per task commit:** `bash scripts/check.sh --library-only`. Expect about 4 to 5 minutes once the real-time tier is in; use `PP_PALETTE=<stem>` while authoring a single palette and run the full library tier before the commit.
- **Per wave merge:** `bash scripts/check.sh` (adds the smoke suite, about 3 more minutes). Rerun once if the smoke run reports the exit-time crash or the known flaky checks (Pitfall 8, STATE.md).
- **Phase gate:** full `bash scripts/check.sh` green, `pytest` green with `python_app/` untouched, then the manual UAT below.

### Manual-only checks (UAT, cannot be automated)

1. **By-ear loudness pass** (D-13): on Auto with the real GUI and music, then by name, switch between every palette at a low and a high EPIC and at the rider's usual volume; no palette may jump or hide. Record which palette sounded louder or quieter in plain words.
2. **Recognisably different** (success criterion 1): the rider names each palette from the post-window line and says whether they can tell them apart in the full mix (the "faint 12 dB-down" rule).
3. **VO2 at volume 100 on the loudest palette** sounds clean (no distortion pumping), a listening confirmation of the numeric peak gate.
4. **Auto rotation feel:** one ride of about 15 minutes at the rider's tempo confirms a change lands on a chord-chapter change and every few minutes; confirm the first palette after Start is not always classic.
5. **Zwift-side CPU** (D-15): rider runs `scripts/palette_cpu.sh` once with Zwift open and reports mean and peak; pass if mean is under 25%.

### Wave 0 Gaps

- [ ] Level / headroom / CPU real-time tier in `supercollider/library_test.scd` (probe, per-palette loop, `PP_PALETTE` filter) and the raised watchdog plus `check.sh` timeout
- [ ] Auto palette test tier (rotation, landing, locked progression, named lock, replay, bounded, new file, failing file) with a tunable small `~ppPalHoldBars`
- [ ] WR-01 negative cases and WR-02 fixtures (a palette redefining `\ppArp`; a palette whose `defs` throws after adding a voice) in `library_test.scd`
- [ ] Update `auto plays classic` so it covers melody + progression only
- [ ] `supercollider/palette_cpu.scd` + `scripts/palette_cpu.sh`
- [ ] Smoke additions: Stop under a non-classic palette, rotation leak check, VO2 no-clip per palette (or for the loudest)
- [ ] `palettes/_template.scd` and `library/README.md` updates (guard excludes `_template.scd`, so it is editable); document `bassStyle`, the prefix rule, the level-tuning loop, and the Auto behaviour
- [ ] A listening UAT script (plain-language palette names and what each should sound like), like Phase 6's

## Security Domain

Security enforcement is enabled (`security_enforcement: true`, ASVS level 1, block on high).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | single-user local tool, no accounts |
| V3 Session Management | no | none |
| V4 Access Control | partly | OSC accepted from loopback only (`srcID: NetAddr("127.0.0.1", nil)`, main.scd:404-406) |
| V5 Input Validation | yes | `~ppStemValid` on every OSC name before a path is built (loader.scd:43-58); `~ppValidate` on file shape; WR-01 magnitude bounds in `~ppRowsValid`; validator refuses unknown `bassStyle` values |
| V6 Cryptography | no | none |
| V12 Files and Resources | yes | `~ppLibContained` realpath containment (loader.scd:63-68); prefetch scans only valid stems under the library root |
| V14 Configuration | partly | library files are code run by sclang; mitigated by the static lint and by the fact that the rider's repo is the only source |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Path traversal through `/pp/palette ../../x` | Tampering / Information disclosure | existing stem rule plus realpath containment; keep both for the prefetch scan |
| Hostile or accidental library file with huge magnitudes (400000-row bar, legato 100, note 500, NaN-producing cutoff) hanging sclang or poisoning `~ppMixBus` | Denial of service | WR-01 bounds (rows 64, dur >= 1/32, legato <= 8, note -12..127, chord <= 8) plus optional aggregate voice-beat budget; clamp cutoffs in voices |
| A palette redefining a classic SynthDef (name clobbering) so every palette changes sound, or leaving voices behind | Tampering | WR-02 prefix rule plus SynthDescLib snapshot-diff, `SynthDef.removeAt`, restore classic `defs` |
| Unbounded prefetch registering thousands of SynthDefs | Denial of service | cap the number of palette files; `maxSynthDefs` default is 1024 |
| A voice writing to bus 0 or ignoring `gate` (bypasses limiter / survives Stop) | Elevation of function (safety gate) | existing voice tier on every palette stem, run on a bare server |
| Runaway nodes from a long-release voice | Denial of service | release length enforced by the 2.0 s drain in the voice tier; relative node bound in smoke |

## Sources

### Primary (HIGH confidence)
- Local code read this session (the authoritative sources for every in-repo value above): `supercollider/core/loader.scd`, `render.scd`, `validate.scd`, `harmony.scd`; `supercollider/main.scd`; `supercollider/library_test.scd` (static tier 428-683, voice tier 1169-1332, selection tier 1443-1700, rows validation 2347); `supercollider/smoke_test.scd` (1655-1800, 2100-2200); `scripts/check.sh`, `scripts/smoke_test.sh`; `supercollider/library/palettes/_template.scd`, `classic.scd`, `library/README.md`
- Installed SuperCollider 3.14.1 class library: `Common/Audio/SynthDef.sc` (`add`, `*removeAt`), `Common/Audio/SynthDesc.sc` (`SynthDescLib`, `removeAt`), `Common/Control/Server.sc` and `ServerStatus.sc` (`avgCPU`, `peakCPU`, `numSynthDefs`, `maxSynthDefs: 1024`, status poll 0.7 s)
- This session's scratch prototypes (not in the repo): `proto/measure.scd`, `proto/loop.scd`, `proto/snap.scd`, six draft palette files; plus today's runs of `bash scripts/check.sh --library-only` (CHECK PASS, 2:18) and `bash scripts/smoke_test.sh` (72 CHECK OK, SMOKE PASS, then an exit-time sclang crash, 3:10)
- Phase artifacts: `07-CONTEXT.md`, `REQUIREMENTS.md`, `STATE.md`, `04-REVIEW.md` (WR-01, WR-02 text), `06-CONTEXT.md` (D-08 to D-14), `06-VALIDATION.md`, `06-REVIEW-DISPOSITION.md`

### Secondary (MEDIUM confidence)
- `.planning/research/ARCHITECTURE.md` (palette file shape, prepare-on-demand rationale, rotation policy; its section-boundary / 128 to 256 bar guidance is superseded by CONTEXT D-05..D-07), `PITFALLS.md` Pitfalls 6 and 7, `STACK.md` item 10

### Tertiary (LOW confidence)
- Voice recipe musicality and the suggested `bassStyle` assignments are training-knowledge sound design; nothing was listened to. Marked [ASSUMED] in the Assumptions Log.

No external web sources were needed: the domain is the project's own code plus the locally installed SuperCollider class library, and the research-plan seam (Context7 / web) would not have added authority over reading the installed source.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH, no new dependencies; APIs read in the installed class library and exercised by prototype
- Architecture: HIGH, integration points read line by line; the per-bar palette in the memo and the prefetch design follow existing proven patterns, the new rotation code itself is unwritten (MEDIUM until tested)
- Loudness / CPU method: HIGH, measured and repeatable on this Mac
- Auto timing numbers and sound recipes: MEDIUM, depend on the ride-tempo assumption and the rider's ears
- Pitfalls: HIGH for the ones with evidence from this session (levels, watchdog, legato cap, exit crash)

**Research date:** 2026-10-13
**Valid until:** 2026-11-12 (stable local codebase; re-check if Phase 8 changes `~ppRenderBar` or the plan keys first)
