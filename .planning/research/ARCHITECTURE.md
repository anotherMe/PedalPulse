# Architecture Research

**Domain:** Modular generative-music engine (SuperCollider) with a send-only Tkinter controller
**Milestone:** v2.0 Living Music (integration with the shipped v1.0 engine)
**Researched:** 2026-10-11
**Confidence:** MEDIUM-HIGH. The design is derived from reading the shipped `supercollider/main.scd` (435 lines), `smoke_test.scd`, and `python_app/*`. A handful of sclang behaviours are flagged "VERIFY" below. They are cheap to confirm with a 10-line headless probe in the first phase and must not be assumed.

Scope: only what is NEW for v2.0. v1.0 mechanisms that stay as-is (ramp stepper, EPIC bus/smoother/FX, master + limiter, transport gate-release, loopback `srcID` guard) are referenced, not redesigned.

---

## Standard Architecture

### System Overview

```
 PYTHON (send-only, unchanged philosophy)                         DISK (source of truth for names)
┌──────────────────────────────────────────────┐        ┌─────────────────────────────────────────┐
│ view.py: BPM / zones / play / volume         │        │ supercollider/library/                  │
│   + NEW 3 selectors (Auto | item ...)        │        │   palettes/     classic.scd dark.scd ...│
│ library_logic.py (NEW) LibraryController     │◄───────┤   progressions/ classic.scd ...         │
│ library_scan.py  (NEW) pure folder scan      │  scan  │   melodies/     classic.scd ...         │
│ osc_client.py: + send_library(category,name) │  once  │   _template.scd in each (never loaded)  │
└───────────────┬──────────────────────────────┘        └──────────────────▲──────────────────────┘
                │ UDP 57120, loopback                                       │ File.exists / load (sclang reads the
                │ /pp/bpm /pp/play /pp/epic /pp/volume   (existing)         │ same files; lazy-load on selection)
                │ /pp/palette "dark|auto"  /pp/progression  /pp/melody (NEW)│
                ▼                                                            │
 SCLANG ─────────────────────────────────────────────────────────────────────┼───────────────────────────
┌─────────────────────────────────────────────────────────────────────────────┴───────────────────────────┐
│ main.scd (CORE: clock, ramp stepper, buses/groups, FX, master+limiter, transport, ALL OSCdefs)           │
│   loads at top (before waitForBoot, path captured first):                                                │
│ core/loader.scd   registry ~ppLib[category][name] = Event, scan / load / validate / ensure / reload       │
│ core/conductor.scd ~ppCond: selections + auto-rotation + section machine + memoized per-BAR PLAN         │
│ core/render.scd   per-layer bar renderers; defines Pbindefs for every name in ~ppLayers                  │
│        │                       │ plan(bar)                      │ module Events (pure data + functions)  │
│        ▼                       ▼                                ▼                                        │
│  ~clock (TempoClock, sole tempo writer = ~ppRampStepper)   library modules (never touch server state)    │
│   ├─ Routine: conductor tick (plans bar+1, once per bar)                                                 │
│   └─ Pbindef x7: kick hat clap bass arp pad LEAD  -- each = Pn(Plazy{ render bar from plan(bar) })       │
└───────────────┬──────────────────────────────────────────────────────────────────────────────────────────┘
                │ Synth(inst, [out: ~ppMixBus, ...]) in ~ppInstrGroup  (voices self-free, honour \gate)
                ▼
   ~ppMixBus -> \ppFx (EPIC drive/cutoff/reverb, unchanged) -> \ppMaster (volume, Limiter -1 dBFS) -> out
```

Four time scales, all driven from `~clock` beats (never wall-clock), all resolved at bar granularity:

| Scale | Unit | What changes | Who decides |
|-------|------|--------------|-------------|
| Note | 16th | arp accents, per-note amp | layer renderer inside the module generator |
| Bar | 4 beats | current chord, drum variation | `plan(bar).chord` from the progression |
| Phrase | 4/8 bars | motif repeat vs mutate, drum fill, melody style swap | `plan.phraseBar`, `plan.fill`, melody `state` |
| Section | 8-32 bars | intro / groove / build / drop / breakdown, density macro | section machine in conductor (scaled by EPIC) |
| Movement | ~3-10 min | palette, progression, melody-style rotation | rotation timers in conductor, executed at section/phrase boundary |

### Component Responsibilities

| Component | Status | Responsibility | Implementation |
|-----------|--------|----------------|----------------|
| `main.scd` | MODIFIED | Core only. Capture `~ppRoot`, load core files, own clock/buses/FX/master/transport/OSC. Adds `\ppLead` to `~ppLayers`, adds 3 OSCdefs, stops the conductor Routine in teardown. | Existing structure; drum SynthDefs may stay inline |
| `core/loader.scd` | NEW | Registry, folder scan, safe load, validation, lazy ensure, hot reload, name rules. Never throws. | Plain functions in the environment (`~ppLib*`) |
| `core/validate.scd` | NEW (or section of loader) | Pure per-category validators returning a list of error strings. Same function used at runtime AND by the test. | Pure functions, no server |
| `core/conductor.scd` | NEW | Selections (`~ppSel`), rotation, section machine, memoized plan(bar). Single source of "what is happening musically". | One persistent Event `~ppCond` + one Routine on `~clock` |
| `core/render.scd` | NEW | Turns `plan(bar)` + resolved modules into Pbindef events for each layer; time-fit, error containment, fallback. | `Pn(Plazy{...})` inside `Pbindef` (keeps `Pbindef(name).play/stop/isPlaying`) |
| `core/arrange.scd` | NEW (or part of conductor) | Core-owned tables: layer on/off thresholds vs density, section templates, fill vocabulary, EPIC to density curve. Not in the library (not rotated). | Data tables + small functions |
| `library/<cat>/<name>.scd` | NEW | Musical content. Evaluates to ONE Event. No side effects on load. | See contracts below |
| `python_app/library_scan.py` | NEW | Pure: `scan_library(root) -> {category: [stem, ...]}`. No Tk, no OSC. | `pathlib`, regex filter, sorted |
| `python_app/library_logic.py` | NEW | `LibraryController` (per-category selection, send on change, `send_initial`). Pure, injected `send`. | Mirrors `PlayController` pattern |
| `python_app/osc_client.py` | MODIFIED | `send_library(address, name:str)` + CLI flags for raw tests | Same `(OSError, OverflowError, BuildError)` guard |
| `python_app/view.py` / `main.py` / `config.py` | MODIFIED | 3 selector rows, wiring, addresses, library path | `tk.OptionMenu` with `takefocus=0` |
| `supercollider/smoke_test.scd` | MODIFIED | Layer set now includes `\ppLead`; new engine checks | See Smoke test section |
| `supercollider/library_test.scd` | NEW | Validates every library file (static, then server) | See Smoke test section |

---

## Recommended Project Structure

```
supercollider/
├── main.scd                    # CORE (modified). Line 1-5: capture ~ppRoot BEFORE anything async
├── core/
│   ├── loader.scd              # registry + scan/load/ensure/reload
│   ├── validate.scd            # per-category validators (pure)
│   ├── conductor.scd           # ~ppCond, plan(bar), rotation, sections
│   ├── arrange.scd             # density tables, section templates, fills
│   └── render.scd              # per-layer bar renderers + Pbindef definitions
├── library/
│   ├── palettes/      classic.scd  _template.scd  dark.scd ...
│   ├── progressions/  classic.scd  _template.scd  ...
│   └── melodies/      classic.scd  _template.scd  ...
├── smoke_test.scd              # existing harness (modified)
└── library_test.scd            # NEW: validates every file under library/
python_app/
├── library_scan.py   library_logic.py            # NEW
├── config.py osc_client.py view.py main.py       # MODIFIED
└── tests/ test_library_scan.py test_library_logic.py (+ edits to test_osc_client / test_view_tk)
scripts/smoke_test.sh           # MODIFIED: also runs library_test.scd + file-count cross-check
```

### Structure Rationale

- **`core/` vs `library/`:** core is code that must always work and is edited rarely; library is content that grows by adding files. The rider never edits either. Core files are `.load`ed by `main.scd`, so re-evaluating `main.scd` reloads them (idempotent re-eval preserved).
- **`classic.scd` in each category is mandatory:** it reproduces the v1 sound/progression/arp exactly. It is the A/B reference, the failure fallback, and the first behaviour-preserving milestone check. `main.scd` refuses to finish boot with a loud error if a `classic` is missing or invalid.
- **`_` prefix = not a selectable item:** `_template.scd` (authoring example for Claude) and any shared helper are skipped by both the Python scan and the engine scan.
- **File stem is the ONE name.** Lowercase ASCII `[a-z0-9_]+`, e.g. `dark.scd` is `"dark"`. The Python label is derived (`dark` -> "Dark"). The Event's own `\name` is ignored/overwritten by the loader, so file and registry can never disagree. `auto` is a reserved word; `auto.scd` is rejected by both sides.

---

## Library File Contract

**Rule 0 (all categories):** the file is one SuperCollider expression whose LAST value is an Event. Loading = `path.load` (returns that value; VERIFY on 3.14.1). Loading must have **no side effects**: no SynthDef `.add`, no `Pbindef`, no `~global =`, no server access, no `.play`. All effects live inside functions the engine calls later at a controlled time. This is what makes files validate-able headless, hot-swappable, and safe to load while music plays.

The loader, not the file, registers it: `~ppLib[category][stem] = ev.put(\name, stem).put(\path, path).put(\rev, n)`. There is no self-registration call, therefore nothing to forget and no way to register under a wrong name.

### Progression (`library/progressions/<name>.scd`)

```supercollider
(
  desc: "Aeolian i-VI-III-VII, two bars per chord",       // required, one line, used in logs/test output
  mode: \minor,                                           // required: key into core ~ppModes (dorian, phrygian, ...)
  chords: [                                               // required, 1..16 entries
    (root: 0,  quality: \min, bars: 2),                   // root = semitones above session key root
    (root: 8,  quality: \maj, bars: 2),                   // quality: key into core ~ppChordTypes, OR intervals: [0,3,7,10]
    (root: 3,  quality: \maj, bars: 2),
    (root: 10, quality: \maj, bars: 2),
  ],
  // optional: weight: 1 (Auto rotation odds), bassPattern hints are NOT here (those belong to palette/melody)
)
```

Validator: `chords` non-empty; each `root` 0-11; `quality` known or `intervals` a non-empty int array; `bars` int 1-8; total bars in `{4, 8, 16, 32}` (warn, not fail, otherwise: cycle will not align to 8-bar phrases); `mode` known. The session key root lives in the conductor (`\keyRoot`, default 9 = A, preserving v1), so a progression is key-independent and a future "key change on drop" needs no library change.

### Melody style (`library/melodies/<name>.scd`)

```supercollider
(
  desc: "Sparse stepwise lead, 2-bar motif, mutate every 4th repeat",
  init: { |state| state.motif = nil; state.age = 0 },     // required: reset evolving state (called on select/reload/Start)
  lead: { |plan, state| ... },                            // generator for role \lead   (optional)
  arp:  { |plan, state| ... },                            // generator for role \arp    (optional)
  // at least one of lead/arp. Missing role -> core falls back to classic's generator for that role.
)
```

Generator signature: `{ |plan, state| -> [[note, dur, amp, legato], ...] }` for exactly one bar.
- `note`: MIDI number, `\rest`, or an Array (chord/dyad). `dur` in beats. **The durs must sum to 4.0.** (Renderer enforces `fit-to-bar`: truncate overflow, pad with a rest, count a warning, so a bad file can never desync a layer from the bar grid.)
- `plan` is read-only (schema below). `state` is an Event owned by the conductor, one per (role), surviving across bars and reset by `init`. Generators must be **pure functions of (plan, state) plus the thread random stream**: no `~vars`, no clocks, no I/O. The engine does `thisThread.randSeed = hash(songSeed, bar, role)` before each call (VERIFY `Thread:randSeed_` exists and is honoured inside Routines; fallback: pass an explicit `RandStream` and use `rng.rand`/`rng.rrand`), so output is deterministic per (song seed, bar, role). Consequences: unit-testable, and "that melody at minute 23" is reproducible from a logged seed.
- "Motif then mutate" lives in `state`: store the motif, count repeats via `plan.phraseBar`, mutate (transpose a step, drop/add a note, rhythm shift) at phrase boundaries. Chord-following comes from `plan.chord` / `plan.scale`.

### Palette (`library/palettes/<name>.scd`)

```supercollider
(
  desc: "Dark: low-passed saw bass, hollow pad, plucky arp",
  defs: { |s| SynthDef(\pp_dark_bass, { ... }).add; SynthDef(\pp_dark_pad, { ... }).add; },  // optional, run on PREPARE
  roles: (                                                // any subset; missing role -> classic's voice
    bass: (instrument: \pp_dark_bass, args: [\cutoff, 600], octave: 0, ampTrim: 1.0),
    pad:  (instrument: \pp_dark_pad,  args: [],             octave: 0, ampTrim: 0.9),
    arp:  (instrument: \pp_dark_arp,  args: [], ...),
    lead: (instrument: \pp_dark_lead, args: [], ...),
    // optional drum overrides: kick, hat, clap
  ),
  // optional: weight: 1 (rotation odds)
)
```

Voice contract (every SynthDef a palette names): controls `out`, `freq`, `amp`, `gate` (pitched voices; drums: `out`, `amp` only); envelope with `doneAction: 2`; writes `Out.ar(out, stereo)` and nothing else; no persistent state; name prefixed `pp_<palette>_` (prevents cross-palette collisions and makes reload = "same name replaces def"). The renderer forces `out` (= `~ppMixBus`) and `group` (= `~ppInstrGroup`); a palette's `args` cannot override them. This keeps Stop (gate broadcast to `~ppInstrGroup`) and the EPIC FX path valid for every present and future palette with no per-palette work. Palettes do NOT touch EPIC/FX/master: EPIC brightness applies to every palette because it is post-mix.

Why `defs` is run on **prepare**, not on load: sclang's default `maxSynthDefs` is 1024 and each SynthDef costs a server round-trip; adding every palette at boot would not scale to a growing library. The engine prepares a palette (runs `defs` + `s.sync`) on demand and, for Auto rotation, one phrase ahead of the switch.

### Plan schema (what generators and renderers read)

`plan = ~ppPlanFor.(bar)`; an Event, immutable once built:

| Key | Meaning |
|-----|---------|
| `bar`, `songBar` | absolute bar index (`floor(beats/4)`), bars since the last Start |
| `phraseBar` | 0..7 position in the 8-bar phrase; `fill` = true on the last bar of a phrase (bigger on section ends) |
| `chord` | `(root: midi pitch class base, notes: [midi...] voiced around octave 3-4, bass: midi, pcs: [0..11], name: \Am7)` |
| `nextChord` | for anticipations/passing tones |
| `scale` | absolute pitch classes of the progression mode in the session key |
| `section`, `sectionBar`, `sectionLen` | `\intro \groove \build \drop \breakdown` |
| `density` | 0..1 arrangement density (EPIC x section); `layersOn` = Set of layer names active this bar |
| `epic` | 0..1 raw EPIC at plan time |
| `palette`, `progression`, `melody` | RESOLVED module Events captured at plan time (this is what makes a swap bar-quantized) |

---

## Architectural Patterns

### Pattern 1: Memoized per-bar plan, layers PULL (no mutable "current chord")

**What:** the conductor never pushes state into layers. A pure-ish function `~ppPlanFor.(bar)` returns the plan for an absolute bar, computing and caching it (and any missing earlier bars, strictly in order) on first request. A conductor Routine on `~clock` (`quant: 4`) calls `~ppPlanFor.(currentBar + 1)` once per bar, so the plan is always built one bar before it is played. Each layer's Pbindef is `Pn(Plazy { var bar = (thisThread.beats / 4 + 1e-6).floor; render.(role, ~ppPlanFor.(bar)) })`; each Plazy evaluation yields one bar of events with durs summing to 4.
**When:** always; this is the core data-flow decision.
**Why it is the right shape for this codebase:** it removes the bar-boundary race (layer note-on and conductor tick at the same logical beat in unspecified order), keeps every layer on `~clock` (invariant), and makes harmony changes, palette swaps, and density changes naturally bar-quantized. Requests (GUI select, EPIC change) arriving in bar n take effect from plan(n+2) at the earliest: 1-2 bars (~2-4 s at 128 BPM) of latency, which sounds musical rather than laggy.
**Trade-off:** Plazy-per-bar rather than a long-lived `Pseq`; slightly more code per layer, in exchange for deterministic, testable, hot-swappable output.
**VERIFY:** `thisThread.beats` inside a Plazy evaluated within a Pbindef stream equals the bar-start logical time. Add a smoke check that records (bar from plan, bar from event time) for 32 events per layer and asserts equality.

```supercollider
// core/render.scd (sketch)
~ppMakeLayer = { |role|
    Pbindef(role.asSymbol,
        \instrument, Pfunc { ~ppInstrumentFor.(role) },    // palette role resolved from plan, falls back to classic
        [\midinote, \dur, \amp, \legato], Pn(Plazy {
            var bar = (thisThread.beats / 4 + 1e-6).floor.asInteger;
            Pseq(~ppRenderBar.(role, ~ppPlanFor.(bar)), 1)   // try/catch + fit-to-4-beats inside
        }, inf),
        \out, ~ppMixBus, \group, ~ppInstrGroup
    )
};
```
(`\instrument` must come from the same plan as the notes; in the real code resolve it inside the same Plazy and emit it as a fifth multi-key column so instrument and notes can never come from different bars.)

### Pattern 2: Selection = request now, resolve at plan time

`~ppSel = (palettes: \auto, progressions: \auto, melodies: \auto)` is persistent (like `~bpm`). OSC handlers only write `~ppSel` after the target is confirmed loaded. `~ppMakePlan` reads `~ppSel` and, for `\auto`, the rotation state; it resolves to concrete module Events and stores them in the plan. Policy per category is data in `arrange.scd`:

| Category | Manual (named) | Auto rotation |
|----------|----------------|---------------|
| palette | next plan (<= 2 bars) | timer 128-256 bars (jittered, in SONG bars so Stop pauses it); executed at the next section boundary within 16 bars, else next phrase boundary; weighted pick excluding current and last 2; prepared one phrase ahead |
| progression | next plan, restart cycle at chord 0 | after N complete cycles (2-4), at cycle end aligned to phrase |
| melody | next plan, `init` the state | per section (e.g. on `groove` and `drop` entry) |

Why section-boundary for Auto palette: a timbre swap on an arrangement change (build into drop, after a breakdown) reads as intentional; mid-groove it reads as a glitch. Why 1-2 bars for manual: the rider is auditioning and a 60 s wait is hostile. Old notes finish through their own release (pad 1.2 s release, bass legato), new notes use the new instrument; no gate broadcast, no cut, so the switch is a natural crossfade.

### Pattern 3: Pure modules, impure engine (hot-swap safety)

Modules = data + pure functions; engine owns all state (`state` Events, buses, groups, SynthDefs on the server). Hot-swapping one module is therefore: load aside, validate, prepare, replace one dictionary entry. Single-threaded sclang means no torn reads (a Routine only yields at `wait`/`sync`).

---

## Data Flow

### Select a palette (manual)

```
Tk OptionMenu "Dark" -> LibraryController.select("palettes","dark") [send only on change]
   -> OscClient.send_library("/pp/palette","dark")  ---UDP--->  OSCdef(\pp_palette)  (srcID loopback)
        validate arg: String/Symbol, lowercase [a-z0-9_]+ (path-traversal guard), or "auto"
        -> {  ~ppLibEnsure.(\palettes, \dark)      // fork Routine: lazy load from disk if not in registry,
              //                                       validate, run defs, s.sync  (never s.sync in the OSCdef thread)
              ok  -> ~ppSel.palettes = \dark ; post "palette dark queued"
              bad -> post warning, ~ppSel unchanged (music continues, no state change)   }.fork
   plan(n+2) resolves palette=dark -> layers read plan.palette.roles at their next bar
```

### One bar of audio

```
conductor Routine @bar n:   ~ppPlanFor.(n+1)  -> section machine step, rotation checks, chord from progression,
                                                  density = f(EPIC, section), layersOn, resolve ~ppSel -> modules
layer Plazy @bar n+1 start: plan = ~ppPlanFor.(n+1) (cache hit)
                            events = module.generator.(plan, state)  [seeded, try/catch, fit to 4 beats]
                            -> Pbindef emits Synth(inst, out: ~ppMixBus, group: ~ppInstrGroup)
```

### EPIC (extended, not replaced)

`/pp/epic` still writes `~epic` and the raw bus (brightness path unchanged). NEW: the conductor reads `~epic` at plan time, so arrangement density changes land on the next bar line. No new OSC message, no new Python code for density.

### State management

| State | Owner | Survives re-eval of `main.scd`? | Survives Stop/Start? |
|-------|-------|---------------------------------|----------------------|
| `~bpm ~epic ~volume ~ppPlaying` | existing | yes | n/a |
| `~ppSel` (selections) | conductor | **yes** (`~ppSel = ~ppSel ?? (...)`) | yes |
| `~ppLib` registry | loader | no, rebuilt (cheap; modules are data) | yes |
| song position, section, plans, melody `state` | conductor | no (song restarts from intro at next bar) | reset on Start, frozen on Stop |
| rotation timers | conductor, in song bars | no | frozen while stopped |

---

## Hot-swap of one module (safe re-evaluation)

Entry points: lazy `~ppLibEnsure` (new file), `~ppReload.(category, name)` (changed file; IDE one-liner; an optional loopback `/pp/reload "palettes" "dark"` is trivial but not required, since the rider cannot edit files anyway). Full `main.scd` re-eval remains available and idempotent but has an audible 0.3 s+ teardown, so it is the heavy hammer.

Procedure, all inside one forked Routine (never in the OSCdef thread, never on `~clock`):
1. `try { ev = path.load }`; failure -> post error, keep old entry, return false.
2. `validate(ev)`; any errors -> post them all, keep old entry, return false.
3. Palette only: run `ev.defs` (SynthDefs under the `pp_<name>_` prefix replace same-named defs; running synths keep their compiled def, only NEW notes use the new one), `s.sync`, then assert each role's instrument exists in `SynthDescLib.global` with controls `out freq amp gate`.
4. Melody only: `ev.init.(state)` for each role state.
5. Swap: `~ppLib[cat][name] = ev` (one atomic put), bump `\rev`.
6. Plans already built keep their captured old Event; the first plan built after the swap picks the new one. Hot-swap is therefore bar-quantized by construction.
7. Runtime containment: every generator call is `try`-wrapped; on error the bar renders from `classic`'s generator, an error counter increments, and after 3 errors for the same (category, name) the conductor reverts that selection to `classic` and posts why. A buggy new experiment can degrade to the v1 sound but can never silence or crash the ride.

---

## Python Discovery and Name Mismatch

`library_scan.scan_library(root)`: for each category in `config.LIBRARY_CATEGORIES = ("palettes","progressions","melodies")`: `sorted(p.stem for p in (root/cat).glob("*.scd") if re.fullmatch(r"[a-z0-9][a-z0-9_]*", p.stem) and p.stem != "auto")`, with `classic` hoisted first. Root default: `Path(__file__).resolve().parent.parent / "supercollider" / "library"`, overridable by `--library` / `PEDALPULSE_LIBRARY`. Scan happens once at startup (before building widgets). Missing folder or empty category -> selector shows only "Auto", status line says "library not found", app does not crash. Selector values sent are the stems; labels are display-only.

`LibraryController` mirrors `PlayController`: injected `send`, send only on a real change, `send_initial()` sends all three at startup (default `"auto"`), consistent with how BPM/EPIC/volume already resync on app start.

| Mismatch | Behaviour | Why acceptable |
|----------|-----------|----------------|
| GUI offers a name the engine cannot find (file deleted, engine pointed elsewhere) | Engine posts "palette X not found", keeps current selection | send-only: no error reaches the GUI; log is the diagnostic |
| File added after the engine booted | Works: `ensure` lazy-loads from disk on first selection | Removes the need to restart/re-evaluate after Claude adds a file |
| File on disk but invalid | Engine posts all validator errors, keeps current; next selection retries the load (file may have been fixed) | Failure is visible in the post window, music never affected |
| Engine has an item the GUI did not list (app started before the file existed) | Item takes part in Auto rotation but is not selectable until the app restarts | Optional cheap fix: a "Rescan" action that re-scans and re-sends current state |
| Engine restarted while GUI shows a locked item | Engine is back on Auto while GUI says locked | Existing accepted W2 limitation; a Rescan/Resend action fixes it with no new protocol |
| Hostile or malformed name (`../x`, empty, number) | Rejected at both ends by the same charset rule; no path is ever built from unvalidated input | Loopback-only already; this is defense in depth against a bad file name |
| Case / spaces | Not supported: stems are lowercase snake_case by rule; test enforces it | No normalization layer to desync |

OSC detail: python-osc sends a `str` as OSC type `s`; sclang delivers it as a **Symbol** in `msg[1]`. The handler must `.asString`-validate (not `.isString`). Use a `try`-free `isKindOf(Symbol) or: isKindOf(String)` check before it, same "ignore with warning" style as the existing OSCdefs.

Tk gotcha for the selectors: the app binds root-level `<Up>/<Down>` to BPM nudges. A `ttk.Combobox` or focusable listbox would consume those keys AND let them reach the root binding. Use `tk.OptionMenu` (menubutton) with `takefocus=0`, consistent with the zone buttons, and keep the "no focus" rule in the view test.

---

## Smoke Test: validating every library file

Principle: tests iterate the folder, never a hand-kept list, so a new file is covered the moment it exists. The engine and the test share `~ppLibValidate` (single source of truth).

**Layer 1 — static, no server (`library_test.scd`, runs in ~2 s):**
For each `library/<cat>/*.scd` (including `_template.scd`, which must also validate, so the authoring example never rots):
1. Loads without exception and returns an Event; stem matches the charset; not `auto`; has `desc`.
2. `~ppLibValidate[cat]` returns no errors.
3. No load-time side effects: node count and `~ppLib` unchanged after load (cheap structural assertion).
4. Progressions: expand to chord Events; every chord has >=3 ints in MIDI 24-96; total bars computed; `plan(bar)` for 64 bars works for each.
5. Melodies: cross every melody x every progression x sections {groove, build, drop, breakdown} x densities {0.2, 0.6, 1.0} x 64 synthetic bars. Assert: returns Array of `[note,dur,amp,legato]`; **durs sum to 4.0 (1e-9)**; notes are numbers within the role's range or `\rest`; amps in 0..1; same seed twice gives identical output (determinism); over 32 bars at least 2 distinct bar patterns (not constant) and at least one repeated pattern (a motif exists); out-of-scale/out-of-chord ratio reported as a warning (`CHECK WARN`), not a failure.
6. Prints `LIBCHECK OK: <cat>/<name>` per file.

**Layer 2 — server, isolated port 57141 (same file, second half):**
For each palette: `ensure` (runs `defs`, `s.sync`); every named instrument exists in `SynthDescLib` with controls `out freq amp gate` (drums: `out amp`); spawn every role at once into a scratch group, hold ~0.5 s, sample `s.avgCPU` (warn above a threshold so a heavy supersaw palette is caught before a ride), set `gate 0`, wait the longest release + margin, assert the group has **zero children** (proves `doneAction: 2` and gate honouring, the exact failure that would break Stop and ENG-03).

**Layer 3 — integration, in the existing `smoke_test.scd` harness (it already boots main.scd on 57140):**
- Layer set is now the 7 names; update the `Set[...]` expectations at the two existing sites (lines ~833 and ~851).
- Chord-follow: with a trace hook (`~ppTrace` ring buffer, bounded, off by default) assert every pitched event's pitch class is in the plan chord/scale of its OWN bar, for bass, pad, arp and lead (GEN-01 proof).
- Selection: send `/pp/palette`, `/pp/progression`, `/pp/melody` for each library name via direct `sendMsg`; poll `~ppCond` until the plan shows the item; assert it applied on a bar line (not mid-bar) within 2 bars; assert `s.numSynths` and group child counts return to baseline.
- Unknown name, `../x`, empty, numeric arg: selection unchanged, music keeps playing, warning posted.
- Hot-reload: point `~ppLibRoot` at a temp copy containing a deliberately broken file (and a valid-then-broken edit); assert old entry survives and playback never stops.
- Density: `/pp/epic 10` vs `/pp/epic 100`: assert `layersOn` and measured event counts per bar are strictly higher at 100, and the existing EPIC brightness checks still pass.
- Re-evaluation of `main.scd`: existing three checks, plus `~ppSel` survives and no Routine/Pbindef/node leaks (conductor Routine stopped in teardown).
- Soak hook for ENG-03: sample `s.numSynths`, `s.numGroups`, `~ppCond.plans.size` (must stay <= a small constant because old plans are pruned), and `Process.memory`-style counters every N bars.

**Shell wrapper:** `scripts/smoke_test.sh` runs both scripts and cross-checks that the number of `LIBCHECK OK:` lines equals `find supercollider/library -name '*.scd' | wc -l`, so a file silently skipped by a bug in the test fails the run. A pytest `test_library_scan.py` also scans the REAL library folder and asserts every stem is valid and `classic` exists in each category, which ties the Python view of the folder to the same rule.

---

## Anti-Patterns

### Anti-Pattern 1: Self-registering library files
**What people do:** the file calls `~ppRegister.(\palettes, \dark, (...))`, adds SynthDefs, and sets globals at load.
**Why it's wrong:** cannot be validated without side effects, cannot be loaded aside during playback, name can differ from filename, reload leaks state.
**Do this instead:** file evaluates to an Event; loader registers under the file stem; effects only inside `defs`/`init`, called by the engine.

### Anti-Pattern 2: Layers reading a mutable "current chord"
**What people do:** conductor Routine sets `~chord` at each bar; layers read `~chord` in `Pfunc`.
**Why it's wrong:** ordering between conductor and layer events at the same logical beat is unspecified, so the first note of a bar sometimes plays the previous chord. Bug looks random.
**Do this instead:** layers pull `plan(bar)` computed by bar number from their own event time.

### Anti-Pattern 3: Library modules touching the engine environment
**What people do:** generators use `~clock`, `~epic`, `~ppMixBus`, global `rrand` with no seed.
**Why it's wrong:** not testable with synthetic plans, couples content to core internals, breaks determinism.
**Do this instead:** everything arrives through `plan`/`state`; the engine seeds randomness; core forces `out`/`group`.

### Anti-Pattern 4: `s.sync` or `wait` in an OSCdef function, or loading inside `waitForBoot` to find paths
**Why it's wrong:** OSCdef functions are not Routines (`s.sync` throws). Also `thisProcess.nowExecutingPath` is only reliable at the top level of the executing file; inside `s.waitForBoot`'s Routine it can be nil or point at a different file after a nested `.load`.
**Do this instead:** capture `~ppRoot = PathName(thisProcess.nowExecutingPath).pathOnly` (guard nil: if nil, reuse the previous `~ppRoot` or print "save main.scd and evaluate the file") on line 1-5 of `main.scd`, before `waitForBoot`; any OSC action needing sync is `{ ... }.fork`.

### Anti-Pattern 5: Eagerly adding every palette's SynthDefs at boot
**Why it's wrong:** boot time and the 1024 `maxSynthDefs` ceiling both scale with library size; one broken `defs` could abort boot.
**Do this instead:** prepare on demand and one phrase ahead.

### Anti-Pattern 6: Second clock, or a conductor that writes tempo
**Why it's wrong:** violates the phase-lock and sole-tempo-writer invariants that made v1's glide work.
**Do this instead:** conductor is a Routine on `~clock`; it only reads `~clock.beats`.

### Anti-Pattern 7: Python reading file contents or sending richer payloads
**Why it's wrong:** duplicates schema knowledge in Python and grows the protocol.
**Do this instead:** Python knows only folder names; everything else stays in SuperCollider.

---

## Scaling Considerations (library size and ride length, the real axes here)

| Concern | 5 items/category, 60 min | 50 items/category, 3 h |
|---------|--------------------------|------------------------|
| SynthDefs on server | prepare-on-demand keeps it ~ tens | still fine; prepare-on-demand avoids the 1024 ceiling |
| Test time | seconds | melody x progression cross-product grows quadratically (50x50x64 bars is still well under a few seconds of pure sclang; sample sections/densities if it gets slow) |
| Memory in sclang | prune plans older than 4 bars; bounded trace buffer | same; verify with soak counters |
| CPU | per-bar rendering of 7 layers is negligible; the cost is voices (arp at 16ths x lead x pad) | `library_test` CPU probe flags heavy palettes before a ride |
| GUI | OptionMenu with a handful of entries | still fine; scan once |

First bottleneck: voice CPU in a heavy palette alongside Zwift, not sclang logic. Second: reload/`defs` leaving server-side defs around (negligible).

---

## Integration Points

### New vs modified (explicit)

| Item | NEW / MODIFIED | Detail |
|------|----------------|--------|
| `supercollider/core/*.scd` (5 files) | NEW | loader, validate, conductor, arrange, render |
| `supercollider/library/**` | NEW | `classic` x3 + templates first, then experiments |
| `main.scd` | MODIFIED | capture `~ppRoot`; load core; `~ppLayers` gains `\ppLead`; v1 Pbindef literals move into render with `classic` reproducing them; teardown stops conductor Routine; 3 new OSCdefs (same loopback `srcID`); `~ppStart` resets song (`~ppCond.restart`); startup banner lists new addresses |
| `smoke_test.scd` | MODIFIED | layer-name sets (lines ~833, ~851), new checks listed above; the 67 existing checks stay as the regression net |
| `library_test.scd` | NEW | static + server library validation |
| `scripts/smoke_test.sh` | MODIFIED | run both; file-count cross-check |
| `python_app/library_scan.py`, `library_logic.py` | NEW | pure, pytest-able without Tk or sockets |
| `python_app/config.py` | MODIFIED | `OSC_PALETTE_ADDRESS` etc. (or one dict by category), `LIBRARY_CATEGORIES`, default library path |
| `osc_client.py` | MODIFIED | `send_library`; CLI `--palette --progression --melody` for raw engine tests |
| `view.py`, `main.py` | MODIFIED | 3 selector rows; scan at startup; `send_initial` |
| Protocol | EXTENDED | `/pp/palette /pp/progression /pp/melody <string>`; still Python to engine only |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| OSCdef to loader/conductor | function call, fork for anything async | handlers only validate and delegate |
| conductor to layers | pull `plan(bar)` | no push, no shared mutable chord |
| module to engine | return value (Event) + calls with `(plan, state)` | no `~vars` in modules |
| palette to server | via `defs` run by engine, voices write `~ppMixBus` | contract-tested |
| Python to engine | OSC strings of file stems | folder is the only shared "schema" |

### Invariant check (v1 invariants kept)

- `~ppRampStepper` sole tempo writer: untouched; conductor and renderers only read beats.
- `~ppLayers` single list: still the one list, now 7 entries; Start/Stop/teardown/smoke loops unchanged apart from the expected-set.
- Stop = gate release to `~ppInstrGroup`: unchanged and extended to all palettes via the voice contract + zero-children test.
- Voices write `~ppMixBus`, `doneAction: 2`: enforced by core forcing `out`/`group` and by the test.
- Idempotent, transport-preserving re-eval: `~ppSel`/`~epic`/`~bpm` persisted; conductor Routine added to the teardown list.
- OSCdefs loopback-only: three new ones use the same `srcID: NetAddr("127.0.0.1", nil)`.
- Python send-only: no reply path; mismatches are diagnosed in the SC post window.

---

## Suggested Build Order

Ordered by dependency; each step ends with the full existing smoke suite green.

1. **Core split + loader + contract, behaviour-preserving.** Move to `core/`, add `~ppRoot` capture, registry, validators, `classic` palette/progression/melody that reproduce v1 notes exactly, render via per-bar Plazy, plan with a single static chord and stub section/density. Add `\ppLead` as an (initially silent or classic-arp-doubled) layer. Outputs: `library_test.scd` Layer 1, `_template.scd` files, the VERIFY probes (`load` return value, `thisThread.beats` in Plazy, `randSeed_`, `nowExecutingPath` from IDE and `-D`). This is the riskiest, foundation-setting step; do not add new music here.
2. **Conductor + shared harmony (GEN-01).** Real progression expansion, chord plan, bass/pad/arp follow it, 2-3 progressions, `/pp/progression` with lazy ensure, chord-follow smoke check, bar-quantized swap.
3. **Palettes + hot-swap + Auto rotation.** `defs`/prepare, voice-contract server test, 2-4 palettes, `/pp/palette`, rotation at section/phrase boundary (with stub sections it rotates at phrase boundary), reload path, fault containment and revert-to-classic.
4. **Python selectors.** Depends only on the three OSC addresses and folder layout, so it could overlap 2-3; place here so end-to-end is exercised for palette and progression (melody selector is one config line once `/pp/melody` exists in step 1's OSC plumbing). Includes scan tests, controller tests, view test, mismatch behaviours, optional Rescan.
5. **Rule-based melodies/lead + arp styles.** Needs the plan's chord/scale (step 2) and state/seed plumbing (step 1). Motif-then-mutate generators, determinism/evolution tests, `/pp/melody` selection.
6. **Structure + EPIC density (GEN-02, GEN-03).** Section machine, fills, phrase events, density tables, layer thresholds; replaces the stubs in the plan so everything built before consumes it unchanged. Palette rotation now lands on real section boundaries.
7. **Soak and authoring polish (ENG-03).** 60-minute run with node/plan/memory counters, CPU probe thresholds, README "how to add a library file" for the Claude-writes-files workflow.

Rationale: the plan schema is fixed in step 1 and filled in over steps 2-6, so no later step changes a contract. Palettes come before melodies because they need only the loader and have the highest audible payoff per line of code, and because a broken module path (fallback/revert) should be proven on simple content first.

## Open VERIFY items (confirm in step 1 with a headless probe)

1. `"path".load` returns the file's last value on 3.14.1 under `sclang -D` and from the IDE.
2. `thisProcess.nowExecutingPath` at the top of `main.scd` when run via IDE (saved file), via `.load` from the smoke test, and its value (or nil) inside `waitForBoot`.
3. `thisThread.beats` inside Plazy in a Pbindef stream equals the bar-start logical time (no off-by-epsilon at bar edges).
4. `Thread:randSeed_` inside a Routine yields reproducible `rrand`/`choose`; otherwise use explicit `RandStream`.
5. `SynthDef.add` makes the desc visible in `SynthDescLib.global` after `s.sync` (client side), for the contract test.
6. Multi-key `[\midinote, \dur, \amp, \legato], Pseq(arrayOfArrays)` in `Pbindef` unpacks as expected, and `\rest` in the first column rests correctly.

## Sources

- Project code read directly: `supercollider/main.scd`, `supercollider/smoke_test.scd`, `scripts/smoke_test.sh`, `python_app/{main,view,osc_client,config,bpm_logic}.py`, `.planning/PROJECT.md` (HIGH for existing-architecture claims).
- [SuperCollider Process class docs (nowExecutingPath semantics: interactive code only, set to the loaded file's path by `load`/`loadPaths`; nil outside supported editors)](https://docs.supercollider.online/Classes/Process.html), MEDIUM.
- [SuperCollider Environment docs (`~var` resolves against `currentEnvironment`; `topEnvironment` initial)](https://docs.supercollider.online/Classes/Environment.html), MEDIUM. Routine-environment inheritance was not confirmed from docs; v1's ramp stepper already uses `~vars` inside a Routine successfully, but new code passes state by argument anyway.
- [sc-users thread on nowExecutingPath tracking the last loaded file](https://listarc.cal.bham.ac.uk/lists/sc-users-2007/msg08249.html), LOW (2007, community-level) -- the reason `~ppRoot` is captured once at the very top.
- Existing project research conclusions carried forward: stock JITLib/Pattern classes, no quarks, `TempoClock` shared clock (`.claude/CLAUDE.md` stack section), MEDIUM.
- Remaining sclang behaviours (`Plazy` per-bar, multi-key Pbind, `randSeed_`, OSC string arriving as Symbol, `maxSynthDefs` default 1024) are from SuperCollider knowledge, LOW-MEDIUM until the step-1 probes confirm them.

---
*Architecture research for: PedalPulse v2.0 Living Music*
*Researched: 2026-10-11*
