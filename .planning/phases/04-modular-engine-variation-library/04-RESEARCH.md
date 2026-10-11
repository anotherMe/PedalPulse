# Phase 4: Modular Engine & Variation Library - Research

**Researched:** 2026-10-11
**Domain:** SuperCollider 3.14.1 modular pattern engine (sclang loader, per-bar pattern rendering), headless test harness, shell/git guard. No Python or UI work.
**Confidence:** HIGH for the mechanisms (almost everything below was run against the installed SC 3.14.1 headless this session); MEDIUM for the contract-evolution design (it must survive Phases 6-9, which are not built yet).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Proving "sounds like v1.0"**
- **D-01:** Parity is proven two ways: an **automated note-level comparison** plus a **short listening check by the user** at the end of the phase. The automated check records what v1.0 plays per layer (instrument, notes/midinote, dur, timingOffset, legato, amp and the effective amp, out/group routing) before the split, and asserts the split engine with all-`classic` selections emits the same events. Both are required; neither alone is enough.
- **D-02:** The v1.0 reference must capture the **effective** amp per layer. In v1.0, kick/hat/bass set no `\amp` and get the default event amp 0.1 (overriding the SynthDef default), while clap/arp/pad set `\amp` explicitly (see `supercollider/main.scd` comment above `Pbindef(\ppClap`). The `classic` files must reproduce exactly this, not "fix" it.
- **D-03:** BPM glide, Start/Stop, EPIC zones and volume must behave exactly as in v1.0. The existing smoke checks stay green unchanged, apart from the deliberate addition of the 7th layer to the expected layer sets.

**The 7th layer (lead)**
- **D-04:** Add the lead layer `\ppLead` now as the 7th entry in `~ppLayers`, with full wiring: `~ppMixBus` through the limiter, `~ppInstrGroup`, obeys Stop/gate, self-frees, and is covered by the ENG-05 re-evaluation and Stop checks. — **Reversibility:** costly — the layer list and smoke expected-sets are shared by every later phase.
- **D-05:** `library/melodies/classic.scd` = pure v1.0: the lead is **silent** (rests or no events), so all-`classic` is note-for-note v1.0.
- **D-06:** A second melody file, **`library/melodies/classic_lead.scd`**, makes the lead **double the arp line one octave up at a faint level**, well below the arp, adding shimmer without reading as a new part. It reuses the v1.0 arp voice character unless a different simple voice sounds better at the listening check. This is the first non-`classic` library file and doubles as the live proof that selecting by name works.
- **D-07:** **Startup defaults to `classic`** for all three categories, so `main.scd` sounds exactly like v1.0 and the automated parity check runs against the default startup. The user hears the lead by sending `/pp/melody classic_lead` (one OSC message until the Phase 5 GUI selectors exist). The phase should document that one-liner (e.g. via `python_app/osc_client.py` or a tiny script).

### Claude's Discretion
The user didn't discuss these areas. Claude uses the defaults below, and the planner may refine them:
- **Reload semantics:** re-selecting a name (even the current one) re-reads that file from disk. No separate `/pp/reload` address unless planning finds a clear need. `auto` in Phase 4 resolves to `classic`, since only classic-family entries exist. A selection applies on a bar boundary, never mid-bar, with no gap in playback.
- **Broken-file fallback:** if a file fails to load or validate, the engine posts an error naming the file and keeps the **last good copy** of the current selection; if there is none, it uses `classic`. The music never stops. Unknown names or names that break the stem rules (`^[a-z0-9_]+$`, `auto` reserved, path kept inside the library root) are ignored with a warning.
- **Never-overwrite guard (LIB-03):** besides Claude's convention, the library check should **fail if a library file that is already committed in git has been modified** (compared against HEAD), so an accidental overwrite is caught. New, uncommitted files pass. `_template.scd` and dot-files are skipped as selectable entries.
- **Lead level:** the exact `classic_lead` amp is tuned by ear at the listening check, starting faint, roughly -12 dB or more under the arp.
- **Library check shape:** a separate `library_test.scd` (not an extension of the 1,920-line `smoke_test.scd`), run together with the smoke suite from one command. Keep the total runtime reasonable.
- All loader, registry and plan mechanics follow `.planning/research/ARCHITECTURE.md`. The phase includes the research VERIFY probes listed in STATE.md: `Pbindef.quant = 4` surviving `doReset: true`, `thisThread.beats` inside Plazy equal to bar start, and per-(song, bar, role) seeding.

### Deferred Ideas (OUT OF SCOPE)
None. The discussion stayed within the phase scope. The real lead melody is already planned for Phase 8.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LIB-01 | Start from `main.scd` exactly as before; loads core plus library modules; with only `classic` selected it sounds like v1.0 | Per-bar `Prout` rendering reproduced all 496 recorded v1.0 rows with 0 mismatches (prototype, section "Parity"); golden-recorder design; core/library split table |
| LIB-02 | Each progression/melody/palette is its own named `.scd`; the file name is its identity | Loader injects `name` from the stem, never trusts an in-file name; name rules incl. the verified trailing-newline regex hole; frozen Phase 5 interface |
| LIB-03 | New variations are new files; existing files never overwritten | Git-HEAD guard design (`git diff --name-status --no-renames HEAD`), verified semantics, self-test, `_template.scd` exemption, tuning escape hatch |
| LIB-04 | A broken or invalid file never stops the music; error logged; keep or fall back to `classic` | Verified load-failure modes (syntax error, runtime error, non-Event, missing); generator containment (verified that an uncaught generator error silently kills a layer while `isPlaying` stays true) |
| LIB-05 | A file added or changed while running can be selected or reloaded without restart or interruption | Lazy ensure in a forked Routine, latest-wins token, bar-boundary apply by construction (selection read at bar start), hot-reload procedure |
| LIB-06 | An automated check validates every library file (loads, shape, voices respect limiter/Stop/gate) and runs with the smoke suite | `library_test.scd` tiers, verified voice-contract test with negative controls, one-command wrapper, file-count cross-check |
| ENG-05 | Re-evaluating `main.scd` or a module never stacks routines or leaks nodes; Stop silences every new layer and source | Measured invariants on v1.0 across 4 re-evaluations (`Pdef.all.keys`, `TempoClock.all.size`, clock-queue class histogram, `s.numGroups`, `s.numSynthDefs`); `Pbindef(...).clear` against merge leftovers; lead Stop check must not be vacuous |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

Extracted from `/Users/marcogiordano/Documents/personali/lab/PedalPulse/.claude/CLAUDE.md` (treated with the authority of locked decisions):

- **No quarks, no sc3-plugins, no new pip packages.** Stock SuperCollider 3.14.1 classes only; Python stays `python-osc` + stdlib.
- **Platform/engine:** macOS, same machine as Zwift; the engine must stay light. SuperCollider patch is started separately by the user; the Python app never launches/supervises sclang.
- **Protocol:** OSC over UDP to sclang language port 57120 (never scsynth 57110); loopback only. New OSCdefs reuse `srcID: NetAddr("127.0.0.1", nil)`.
- **Testing:** headless `sclang -D` (never `QT_QPA_PLATFORM=offscreen`, it aborts sclang 3.14.1 on macOS with exit 134; `unset` it in every script). SC side is a compile-and-boot smoke test, not a musical-correctness test. Python side uses pytest (150 tests currently pass).
- **GSD workflow enforcement:** repo edits go through a GSD command (`/gsd-execute-phase` for this phase's planned work).
- **Memory/user preferences (from the invoking prompt):** keep the app simple and minimal in scope; Python app stays send-only (no engine-to-GUI channel); the user is not an SC musician, gives plain-language sound feedback, and every variation is kept as a new library file.

## Summary

Phase 4 is a behaviour-preserving refactor plus a loader. The engine becomes `main.scd` (clock, ramp stepper, buses, FX, master, transport, all OSCdefs) plus three server-free core modules (`core/loader.scd`, `core/validate.scd`, `core/render.scd`) and a `library/` tree whose `classic` files reproduce v1.0 exactly. Every layer stays one permanent `Pbindef` named in `~ppLayers` (now seven names), but its content comes from a per-bar `Prout` that, at each bar start, reads the currently selected library module from a registry and emits one bar of rows. Because the selection is read at the moment each bar starts, a switch is bar-quantized and gapless by construction: no `Pbindef` redefinition, no phase drift. `[VERIFIED: prototype this session]`

The central claim of the phase, "split engine is note-for-note v1.0", is feasible and cheaply testable. A custom Event type (`\ppRecord`) records what each `Pbindef` plays; running it against the unmodified v1.0 `main.scd` on an isolated server produced a deterministic 496-row golden for 16 bars (kick 64, hat 64, clap 32, bass 64, arp 256, pad 16; effective amps 0.1/0.1/0.25/0.1/0.1/0.06). A language-only prototype of the split design (classic data tables, per-bar `Prout`, multi-key columns) matched that golden with **0 mismatches**, and switching the melody to a `classic_lead`-style module made the lead emit at the next bar line. The golden must be recorded before `main.scd` is touched.

The ENG-05 and LIB-06 gates are also measurable. On v1.0 the following are constant across four consecutive re-evaluations: `Pdef.all.keys`, `TempoClock.all.size`, the class histogram of `~clock.queue`, `s.numGroups`, `s.numSynthDefs`, `OSCdef.all.size`. A voice-contract test (spawn on a private bus, read peaks on that bus and on bus 0, gate off, count group children) discriminates good voices from three deliberately bad ones. Several traps found in this session change the obvious implementation: `[...].hash` is not stable across processes, the `$` regex anchor accepts a trailing newline, an uncaught generator error silently kills a layer while `isPlaying` stays true, compile errors from `String:load` do not name the file, and `~vars` inside event-type functions resolve against the event, not the global environment.

**Primary recommendation:** Record the v1.0 golden first, then build `core/` + `classic` files as pure data/functions (no load-time side effects), render every layer through one `Prout`-per-bar function with `try`/fit-to-bar containment, wire `main.scd`, and gate the phase on `scripts/check.sh` (git guard, then `library_test.scd`, then the existing smoke suite with the ENG-05 additions).

## Architectural Responsibility Map

The web-tier template does not apply (no browser/SSR/CDN). Tiers for this project:

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Clock, tempo ramp, buses, FX, master/limiter, transport, OSCdefs | Core engine (`main.scd`) | — | v1.0 invariants (sole tempo writer `~ppRampStepper`, Stop = gate broadcast, `~ppMixBus` through the limiter); untouched |
| Registry, scan, safe load, validation, ensure/reload, name rules | Core module (`core/loader.scd`, `core/validate.scd`) | — | Must be server-free so the static library check can load it with no scsynth |
| Per-bar rendering, fit-to-bar, containment, role-to-module mapping, fixed drum grid | Core module (`core/render.scd`) | Library file (supplies rows) | Core forces `out`/`group`/instrument resolution so a library file cannot bypass the limiter or Stop |
| Musical content (notes, voices) | Library files (`library/<cat>/<stem>.scd`) | — | Pure data plus pure functions; effects only inside `defs` that the engine calls |
| SynthDef registration for a palette | Server (via engine `defs` call + `s.sync`) | Library file (holds the `defs` function) | SynthDef add is async; must run in a Routine, never at file load |
| Never-overwrite guard | Shell + git (`scripts/library_check.sh`) | — | Needs git history; sclang has no business shelling out to git |
| Library validation and parity | Test harness (`supercollider/library_test.scd`) | Shell wrapper | Separate file from the 1,920-line smoke block (CONTEXT) |
| ENG-05 re-evaluation checks | Test harness (`smoke_test.scd`) | — | Re-evaluation helpers and `instrChildCount` already live there |
| Selection by name | OSC (`/pp/progression`, `/pp/palette`, `/pp/melody`) | Python (Phase 5, not here) | Phase 4 only needs a raw-send one-liner |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SuperCollider (sclang + scsynth) | 3.14.1 `[VERIFIED: sclang -D banner "Welcome to SuperCollider 3.14.1", this session]` | Engine, loader, test harness | Project constraint; every needed class is stock |
| Stock classes: `String:load`, `Pbindef`, `Prout`, `Pseq`, `Event.addEventType`, `TempoClock`, `OSCdef`, `SynthDescLib`, `File` | 3.14.1 | Loader, rendering, recorder, hot-swap | Verified by probes below; no quarks |
| git | 2.50.1 `[VERIFIED: git --version]` | Never-overwrite guard | Already the project VCS |
| bash + `timeout` | `/opt/homebrew/bin/timeout` `[VERIFIED: which timeout]` | One-command wrapper | Existing `scripts/smoke_test.sh` pattern |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| python-osc | 1.10.2 (already in `.venv`) `[VERIFIED: import ok in .venv/bin/python]` | One-line raw sender for `/pp/melody classic_lead` | Documented one-liner only; no Python source change in Phase 4 |
| pytest | 8.x (existing) | Keep the 150 existing Python tests green | Regression only; `.venv/bin/python -m pytest -q` -> 150 passed `[VERIFIED: ran this session]` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Prout`-per-bar rows | `Plazy` per bar (ARCHITECTURE sketch) | Both give the exact bar-start `thisThread.beats` (verified for Plazy). `Prout` additionally gives a per-stream bar counter (`songBar`) that resets on `doReset: true` with no global state. Prototype used `Prout` and matched the golden. Either is acceptable; `Prout` is recommended because `songBar` is needed for the v1.0 pad alternation after Stop/Start |
| Regex stem check | Character loop | `"^[a-z0-9_]+$".matchRegexp("abc\n")` returns **true** `[VERIFIED: probe]`; use a char loop (or reject control characters first) |
| Git check inside sclang | Shell step | Shell is simpler and testable against a temp repo |
| New `scripts/check.sh` | Extend `scripts/smoke_test.sh` | Recommended: new umbrella `scripts/check.sh` calling `library_check.sh` then `smoke_test.sh`; keeps the smoke script and its docs unchanged. Either satisfies success criterion 4 |

**Installation:** none. `# Nothing to install` — no new packages in this phase.

**Version verification:** no packages are added. SuperCollider 3.14.1 and python-osc 1.10.2 are the existing pinned versions (`python_app/requirements.txt`).

## Package Legitimacy Audit

Not applicable: this phase installs no external packages (no pip, no npm, no quarks, no sc3-plugins). Nothing was discovered via WebSearch or training data. **Packages removed due to [SLOP]:** none. **Packages flagged [SUS]:** none.

## Architecture Patterns

### System Architecture Diagram

```
 OSC (loopback UDP 57120)                                    DISK (source of truth for names)
 /pp/progression|palette|melody <auto|stem>                  supercollider/library/{progressions,melodies,palettes}/<stem>.scd
        |                                                                  ^
        v  OSCdef x3 (srcID loopback; validate arg: nil/number -> warn)    | path built ONLY from validated stem
 +------------------------------------------------------------------+     |
 | handler: stem rules? ("auto" -> set). else token++ and fork        |     |
 |   ~ppLibEnsure.(cat, stem, reload:true)  [Routine, SystemClock]    |-----+
 |     load (try) -> validate -> (palette: defs + s.sync) -> put      |
 |     ok  -> ~ppSel[cat] = stem  (only if token still latest)        |
 |     bad -> ~ppLog error NAMING THE FILE; selection + registry unchanged
 +------------------------------------------------------------------+
        |   ~ppSel / ~ppLib are read at the START of every bar
        v
 ~clock (TempoClock; sole tempo writer ~ppRampStepper)
   +-- Routine ~ppRampStepper (unchanged)
   +-- Pbindef x7 (~ppLayers): ppKick ppHat ppClap ppBass ppArp ppPad ppLead
         each = Prout { loop { rows = try { render(role, songBar) } -> fit-to-4-beats / fallback to classic;
                               Pseq(rows).embedInStream; songBar++ } }   (columns incl. \instrument)
         + constants \out ~ppMixBus, \group ~ppInstrGroup (forced by core), \timingOffset for drums
        |
        v  Synth(inst, out: ~ppMixBus, group: ~ppInstrGroup)  -> ~ppFx -> \ppMaster (Limiter -1 dBFS)
```

Role-to-module mapping (core table, Phase 4):

| Layer | role | Instrument from | Notes/rhythm from |
|-------|------|-----------------|-------------------|
| `\ppKick` | kick | palette `roles.kick` | core fixed drum grid |
| `\ppHat` | hat | palette `roles.hat` | core fixed drum grid (`timingOffset` 0.5) |
| `\ppClap` | clap | palette `roles.clap` | core fixed drum grid (`timingOffset` 1) |
| `\ppBass` | bass | palette `roles.bass` | progression `bass` generator |
| `\ppPad` | pad | palette `roles.pad` | progression `pad` generator |
| `\ppArp` | arp | palette `roles.arp` | melody `arp` generator |
| `\ppLead` | lead | palette `roles.lead` | melody `lead` generator (absent in `classic` -> rest bar) |

### Recommended Project Structure

```
supercollider/
├── main.scd                 # captures ~ppRoot (line 1-5), loads core/*.scd at TOP LEVEL, then s.waitForBoot as today
├── core/
│   ├── loader.scd           # ~ppLib registry, ~ppLibScan/~ppLibLoad/~ppLibEnsure/~ppReload, name rules, ~ppLog
│   ├── validate.scd         # ~ppValidate[cat] -> Array of error Strings (pure, server-free)
│   └── render.scd           # ~ppLayerRole table, drum grid, ~ppRenderBar, ~ppPlanFor stub, ~ppBuildLayers
├── library/
│   ├── README.md            # contract + how to add a variation (never edit, always add)
│   ├── progressions/  classic.scd  _template.scd
│   ├── melodies/      classic.scd  classic_lead.scd  _template.scd
│   └── palettes/      classic.scd  _template.scd
├── golden/v1_events.scd     # frozen v1.0 recording (Wave 0), loaded by library_test
├── smoke_test.scd           # existing; +\ppLead in the line-833 set, + ENG-05 block
└── library_test.scd         # NEW: static -> voices -> parity -> selection/fallback
scripts/
├── check.sh                 # NEW one command: library_check.sh then smoke_test.sh
├── library_check.sh         # NEW: git guard (+self-test), library_test.scd, LIBCHECK count cross-check
├── smoke_test.sh            # existing (unchanged)
└── pp_select.sh             # NEW tiny sender: pp_select.sh melody classic_lead
```

Do NOT create empty `conductor.scd` / `arrange.scd` stubs: YAGNI; the `~ppPlanFor` stub lives in `render.scd` as the seam Phase 6 fills.

### Pattern 1: Library file = one side-effect-free Event; the loader registers it

Rule: the file's last expression is an Event; loading must not add SynthDefs, create Pbindefs, assign `~globals`, touch the server, or play anything. The loader overwrites `name` (= file stem), `path`, `category`, `rev`. The engine, not the file, calls `defs`/`init`/generators later. `[CITED: .planning/research/ARCHITECTURE.md "Library File Contract"]`

**Phase 4 contracts (frozen; additions only, ever):**

```supercollider
// library/progressions/classic.scd   (v1.0 bass + pad; no `chords` key: Phase 6 adds that for NEW files)
(
  desc: "v1.0 groove: A-minor bass, C on beat 4, two-bar Am / Am+F pad",
  bass: { |plan, state| /* rows for exactly one bar */ },
  pad:  { |plan, state| /* rows for exactly one bar; uses plan.songBar % 2 */ }
)
// library/melodies/classic.scd       (v1.0 arp; NO lead key -> lead layer plays rest bars)
(
  desc: "v1.0 arp A3 C4 E4 C4, silent lead",
  arp: { |plan, state| /* rows */ }
)
// library/palettes/classic.scd       (the six v1.0 SynthDefs move here)
(
  desc: "v1.0 voices",
  defs: { SynthDef(\ppKick, { ... }).add; /* ...six, verbatim from main.scd */ },   // run by the engine, then s.sync
  roles: (
    kick: (instrument: \ppKick), hat: (instrument: \ppHat), clap: (instrument: \ppClap),
    bass: (instrument: \ppBass), arp: (instrument: \ppArp), pad: (instrument: \ppPad),
    lead: (instrument: \ppArp)          // D-06: lead reuses the arp voice; no new SynthDef
  )
)
```

Row format for every generator: `[note, dur, amp, legato]` where `note` is a Number, an Array of Numbers (chord), or `\rest`; `dur` > 0; the durs of one bar sum to 4.0; `amp` 0..1; `legato` > 0. `plan` (Phase 4) = `(bar:, songBar:, phraseBar:, role:)`; later phases add fields, never change meaning. `state` is an Event per role, reset on Start and on select/reload (calls the file's optional `init`).

**Contract-freeze rule (the costly-reversibility point):** every field added in Phases 6-9 (chords, mode, args, ampTrim, weight, density...) MUST be optional with a core default, and validators MUST ignore unknown keys. Then `classic` files written now never need an edit. Without this rule the git guard blocks the fix and LIB-03 is violated.

### Pattern 2: One render function; selection is read at bar start

```supercollider
// Source: prototype run in this session (proto_split.scd): 0 mismatches vs the v1.0 golden.
// Columns differ per role: drums have no \midinote (the default 60.0 is what v1.0 recorded).
~ppBuildLayers = {
    ~ppLayers.do { |name|
        var role = ~ppLayerRole[name];            // e.g. \ppKick -> \kick
        var drum = ~ppDrumGrid[role];             // nil for pitched roles
        var cols = if (drum.notNil) { [\instrument, \dur, \amp, \legato] }
                                    { [\instrument, \midinote, \dur, \amp, \legato] };
        Pbindef(name).clear;                      // kill merge leftovers from an older definition
        Pbindef(name,
            cols, Prout({ |inEvent|
                var songBar = 0;
                loop {
                    // ~ppRenderBar returns finished rows incl. the instrument; never throws; always sums to 4 beats
                    inEvent = Pseq(~ppRenderBar.(role, songBar), 1).embedInStream(inEvent);
                    songBar = songBar + 1;
                }
            }),
            \timingOffset, if (drum.notNil) { drum[\timingOffset] } { 0 },
            \out, ~ppMixBus, \group, ~ppInstrGroup
        );
        Pbindef(name).quant = 4;                  // survives .clear and doReset (verified); protects live edits
    };
};
```

Why `~ppRenderBar` is called through the global each bar: stream-time code (`Prout`/`Pfunc`/`Plazy`) sees global `~vars` even when `Pbindef.play` was triggered from an OSCdef callback (`currentEnvironment === topEnvironment` was `true`) `[VERIFIED: probe]`, so re-evaluating `render.scd` alone takes effect on the next bar and cannot stack anything.

Drum rows (core-owned, must equal the golden): kick `[60, 1, 0.1, 0.8]` x4, hat the same with `timingOffset` 0.5, clap `[60, 2, 0.25, 0.8]` x2 with `timingOffset` 1 (amps are the *effective* v1.0 amps, legato 0.8 is the Event default).

### Pattern 3: Selection and hot-reload (all in a forked Routine; handlers only validate and delegate)

1. OSCdef handler: `msg[1]` arrives as a **Symbol** (a missing arg gives `nil`, a number stays a number) `[VERIFIED: probe: 'classic_lead' Symbol, no arg -> Nil size=1, 3 -> Integer, '../x' Symbol]`. Reject nil/number with a warning; convert with `.asString`; `auto` sets `~ppSel[cat] = \auto`; otherwise validate stem, then `fork` the ensure.
2. `~ppLibEnsure.(cat, stem, reload)`: build the path from the validated stem, `File.realpath` it and check it is inside the realpath of the library root, `try { path.load } { |e| ... }`, validate, (palette only) run `defs` then `s.sync`, then one atomic `put` into `~ppLib[cat][stem]` and bump `rev`. Any failure: `~ppLog` an error that **names the file path**, leave registry and selection untouched, return false.
3. Latest-wins token per category (`~ppSelReq[cat] = ~ppSelReq[cat] + 1`; apply only if still latest) because a palette ensure yields on `s.sync` and two quick selections would otherwise interleave.
4. Resolution at bar start: `auto` resolves to `\classic` in Phase 4 (Phase 6+ replaces this one function). If the selected stem is missing from the registry, use `classic`.
5. Runtime containment inside `~ppRenderBar`: `try` around the generator; validate the rows (Array of 4-element rows, finite numbers, `\rest` allowed, durs sum to 4.0 within 1e-6); on any problem use the same role's `classic` generator for that bar, bump an error counter, `~ppLog` the file stem; after 3 errors for the same (category, stem) revert `~ppSel[cat]` to `\classic`.

### Anti-Patterns to Avoid

- **Self-registering library files** (file calls `~ppRegister`, adds SynthDefs, or sets globals at load): cannot be validated headless or loaded aside during playback.
- **Redefining Pbindefs to switch content:** drifts phase; `Pbindef` merges keys (verified: `Pbindef(\m, \a, 1, \b, 2)` then `Pbindef(\m, \a, 5)` keeps `b`).
- **Using `[a, b, c].hash` for seeds or ids:** differs per process (see Pitfall 4).
- **A second TempoClock or any wall-clock scheduling for musical events:** keep everything on `~clock`.
- **`~vars` inside Event-type functions or SynthDef-play hooks:** they resolve against the Event (verified `nil`).
- **Wrapping `main.scd` in parentheses** to get a "region": changes the IDE evaluation story; keep the select-all-and-evaluate flow.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Loading a file and getting its value | A custom parser/`interpret` of file text | `path.load` inside `try`, then validate the returned Event | Returns the last expression; nil on compile error or missing file; throws on runtime error (all verified) |
| Bar-quantized swap | Swap scheduler / `Pbindef` redefinition on a timer | Read the selection at bar start inside the per-bar `Prout` | Quantization is free and cannot drift |
| Stop of every new layer | New stop registry | Existing `~ppLayers` + `~ppInstrGroup.set(\gate, 0)` (v1.0 Stop) | Lead is a normal layer; palette voices honour `gate` |
| Event capture for parity | Reading scsynth OSC traffic | `Event.addEventType(\ppRecord, ...)` + `Pbindef(n).play(clock, protoEvent: ...)` | Semantic-level capture matches D-01 and ran deterministically (identical md5 on two runs) |
| Counting live routines | Reading `Routine` internals | `~clock.queue` class histogram + `TempoClock.all.size` + `Pdef.all.keys` | Verified constant across 4 re-evaluations |
| Name safety | Regex-only check | Char loop over `[a-z0-9_]`, reject `auto`, reject leading `_`, then `File.realpath` containment | Regex `$` accepts a trailing newline (verified) |
| Never-overwrite | A checksum manifest | `git diff --name-status --no-renames HEAD -- supercollider/library` | History is already in git |

**Key insight:** every hard part (quantized swap, phase lock, Stop, tempo glide) is already solved by "one permanent Pbindef per layer on `~clock`". The phase adds data lookup in front of that and must not replace it.

## Runtime State Inventory

Phase 4 is a split/refactor, not a rename, but the rider's already-running interpreter holds state that a re-evaluation must migrate:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — verified: no database/datastore; engine state lives in the sclang interpreter only | none |
| Live service config | The rider's live sclang session (IDE) may hold the v1.0 `Pbindef`s with their old key sets. `Pbindef` redefinition **merges** keys (verified), so a stale key could leak into the new definition | Code edit: `Pbindef(name).clear` immediately before each redefinition in `~ppBuildLayers`. Also keep persisted `~bpm ~epic ~volume ~ppPlaying` and add `~ppSel = ~ppSel ? (...)` |
| OS-registered state | None — verified: nothing registered with launchd/Task Scheduler | none |
| Secrets/env vars | None — no secrets; `QT_QPA_PLATFORM` must stay **unset** in scripts | none |
| Build artifacts / installed packages | None — no compiled artifacts; SynthDefs live on the server and are re-added by name on boot (`numSynthDefs` stays 115 across re-evals, verified) | none |

Migration note: the first evaluation of the new `main.scd` over an old live session is exactly the "re-evaluation" case; the existing teardown frees old nodes, and `Pbindef(...).clear` plus keyed `OSCdef`s (replace by key) cover the rest.

## Common Pitfalls

### Pitfall 1: A generator error silently kills a layer, and `isPlaying` lies
**What goes wrong:** An exception inside a `Prout`/`Plazy` body ends that layer's stream. `Pbindef(name).isPlaying` stays `true` `[VERIFIED: probe: layer "throws" isPlaying=true, 4 events then silence; the guarded layer kept playing, 18 events]`.
**Why:** The error is raised in the stream's Routine, not at the `Pbindef` object.
**How to avoid:** Wrap every generator call in `try`, validate rows, fall back to classic for that bar (Pattern 3.5). Test by **event counts**, never by `isPlaying`.
**Warning signs:** One layer goes quiet after a library edit; an `ERROR:` line in the post window and no further events.

### Pitfall 2: Compile errors do not name the file
**What goes wrong:** A syntax error in a library file posts `ERROR: syntax error ... in interpreted text line 1 char 26` — no file path `[VERIFIED: probe]`. SC then returns `nil` (a missing file posts `file "./missing.scd" does not exist.` and returns `nil`; a runtime error throws, a non-Event such as `42` loads fine and must be rejected by validation; an empty or comment-only file returns `nil`).
**How to avoid:** The loader posts its own line before and after: `PedalPulse: loading <path>` and, on nil/throw/invalid, `PedalPulse ERROR: library file <path> ...`. Route through `~ppLog` so tests can capture it and assert the path is present.

### Pitfall 3: `thisProcess.nowExecutingPath` and nested loads
**What goes wrong:** On the 3.14.1 headless run the path was still valid after a `wait` and was restored after a nested `.load` `[VERIFIED: probe]` (contradicting the 2007-era claim), but it is a **relative** path when sclang is started with a relative script path. The IDE behaviour (nil for an unsaved document) is `[CITED: .planning/research/PITFALLS.md P1]` and not reproducible headless.
**How to avoid:** First lines of `main.scd`: `~ppRoot = File.realpath(thisProcess.nowExecutingPath).dirname` guarded for nil (keep a previous `~ppRoot`, else `Error(...).throw` with a "save main.scd and evaluate the file" message). Use absolute paths only; never `loadRelative`. Core modules are loaded at top level, before `waitForBoot`, via a small `~ppLoadCore` helper that throws if a module returns `nil` (each core module ends with a non-nil value).

### Pitfall 4: `Array.hash` is not stable across processes
**What goes wrong:** `[\lead, 20].hash` gave 439186787, 1690052431, -936489373 on three runs, while `"lead".hash` and `\lead.hash` were the same stable 823170625 in all runs `[VERIFIED: probes]`.
**How to avoid:** Derive per-(song, bar, role) seeds arithmetically: `((songSeed * 1000003) + (bar * 7919) + role.hash.abs) & 0x7FFFFFFF`. `thisThread.randSeed = seed` then reproduced identical `rrand`/`choose` output across two processes `[VERIFIED: probe: seed 2057332707 -> [66, 69, 67, 70] in both runs]`. Phase 4 uses no randomness, but this fixes the formula before Phase 8.

### Pitfall 5: Name validation holes
**What goes wrong:** `"^[a-z0-9_]+$".matchRegexp("abc\n")` is `true` (and `"abc "` is `false`) `[VERIFIED: probe]`; the CONTEXT regex also matches `_template` and `auto`.
**How to avoid:** Validate with a character loop; additionally reject: empty, `auto`, anything starting with `_` or `.`, and any stem whose resolved `File.realpath` is not inside the library root.

### Pitfall 6: `~vars` inside Event-type functions are the Event's, not the global environment
**What goes wrong:** In the recorder's `\ppRecord` type function, `~ppMixBus` resolved to `nil` (event-play environment) while a `Pfunc` in the same pattern saw the global `~foo` `[VERIFIED: probe: "[event-play ~foo, nil]" vs "[Pfunc ~foo, 5, true]"]`.
**How to avoid:** Capture `~ppMixBus`/`~ppInstrGroup` into closure variables after boot and compare with `===` to normalize `out`/`group` to `\mix`/`\instr`.

### Pitfall 7: Rests never reach the Event type
**What goes wrong:** The recorder logs 496 rows for 16 bars; the bass layer's rests are absent (64 sounding bass rows, not 128) `[VERIFIED: golden counts]`. A rest-only layer logs zero events (`events=nil`) yet is playing.
**Consequence:** Parity compares *sounding* events and their onset beats, which fully determines the rhythm. Do not assert on rest rows. A silent `classic` lead is therefore "0 recorded lead rows".

### Pitfall 8: Vacuous Stop/gate tests for the lead
**What goes wrong:** Under `classic` the lead never sounds, so "Stop silences the lead" passes trivially.
**How to avoid:** Run the lead Stop/obey-gate assertions with `classic_lead` selected (wait until lead events are flowing, Stop, expect the instrument group empty within 2.5 s). Add one negative control (a deliberately gate-less voice must make the check fail).

### Pitfall 9: The git guard blocks legitimate tuning
**What goes wrong:** `classic_lead` is to be "tuned by ear" at the end-of-phase listening check, after it was committed; a HEAD-diff guard then fails.
**How to avoid:** See Open Question 1. Recommended: guard covers only selectable stems (`library/*/[a-z0-9]*.scd`, not `_*.scd`, not README), and has a loud explicit override `PP_LIBRARY_ALLOW_EDIT="melodies/classic_lead.scd"` that prints `ALLOWED EDIT`. Also keep file creation and first tuning inside one commit where possible.

### Pitfall 10: Smoke runtime budget
**What goes wrong:** Baseline `scripts/smoke_test.sh` took **2:24** wall and 67 checks `[VERIFIED: ran this session, 67 CHECK OK, time 2:24.13]` (STATE.md's "~75 s" is stale). The in-test watchdog is 300 s (`smoke_test.scd:28`), the shell timeout 330 s.
**How to avoid:** Put new heavy work in `library_test.scd` (own watchdog, own port 57141). Add only the ENG-05 block (about 10 s: three re-evaluations at roughly 1.5 s each plus settle) to the smoke file. Target total `check.sh` runtime of about 3 minutes.

### Pitfall 11: Test-only globals and event types leak
`Event.addEventType(\ppRecord, ...)` is process-global. It is safe because each test is its own sclang process, but never define it in `main.scd`.

## Code Examples

### Recorder (Event type) and golden/parity row format
```supercollider
// Source: scratchpad rec_v1b.scd, run against the unmodified v1.0 main.scd (deterministic: identical md5 on two runs)
// Row: [layer, relBeat, instrument, midinote, dur, timingOffset, legato, sustain, effectiveAmp, outRole, groupRole]
Event.addEventType(\ppRecord, { |server|
    log.add([~ppRecLayer, thisThread.beats, ~instrument, ~midinote.value, ~dur, ~timingOffset,
             ~legato, ~sustain.value, ~amp.value,
             if (~out === refs[\mix]) { \mix } { ~out }, if (~group === refs[\instr]) { \instr } { ~group }]);
});
// after main.scd is ready and the engine's own streams are stopped:
refs[\mix] = ~ppMixBus; refs[\instr] = ~ppInstrGroup;
recClock = TempoClock(32);                       // 1920 BPM: wall time irrelevant, logical beats compared
~ppLayers.do { |n| Pbindef(n).stop };
~ppLayers.do { |n|
    Pbindef(n).play(recClock, protoEvent: Event.default.copy.put(\type, \ppRecord).put(\ppRecLayer, n), quant: [4, 0]);
};
// wait nBars*4/32 + 1.5 s, stop, then: startBeat = min of recorded beats; keep rows with (beat - startBeat) < nBars*4; sort by (beat, layer)
```
Boot: `Server.default = s = Server(\ppRec, NetAddr("127.0.0.1", <isolated port>))`, `s.boot`, poll `s.serverRunning`, `s.volume.mute`, `(root +/+ "supercollider/main.scd").load`, poll `~ppReady`. Compare columns 0-8 with `==` for symbols/ints and `abs < 1e-9` for floats; ignore columns 9-10 only if the engine's refs differ. Golden self-check (guards against a drifted regeneration): effective amps ppKick/ppHat/ppBass/ppArp = 0.1, ppClap = 0.25, ppPad = 0.06; counts 64/64/32/64/256/16 for 16 bars.

### v1.0 values the `classic` files must reproduce
```
// Source: supercollider/main.scd (read this session)
:269  \midinote, Pseq([\rest, 33, \rest, 33, \rest, 33, \rest, 36], inf),   // bass, \dur 0.5 (:265), \legato 0.8 (:270)
:258  \timingOffset, 0.5,  // offbeat 8th: the "and" of each beat           // hat, \dur 1
:283-285  \dur, 2,  // beats 2 and 4  /  \timingOffset, 1,  /  \amp, 0.25,   // clap
:294  \midinote, Pseq([57, 60, 64, 60], inf),  :295 \legato, 0.6,  :296 \amp, 0.1,   // arp, \dur 0.25 (:292)
:305  \midinote, Pseq([[45, 48, 52], [45, 48, 53]], inf),  :306 \legato, 0.9,  :307 \amp, 0.06,   // pad, \dur 4 (:303)
:49   ~ppLayers = [\ppKick, \ppHat, \ppClap, \ppBass, \ppArp, \ppPad];
```
SynthDef control sets (the voice-contract targets): `\ppKick |out = 0, amp = 0.5|` (:72), `\ppHat |out = 0, amp = 0.15|` (:79), `\ppBass |out = 0, amp = 0.25, freq = 55, gate = 1|` (:86), `\ppClap |out = 0, amp = 0.25|` (:94), `\ppArp |out = 0, amp = 0.1, freq = 440, gate = 1|` (:101), `\ppPad |out = 0, amp = 0.06, freq = 220, gate = 1|` (:109). Drums have no `gate`/`freq` (self-ending percussive envelopes); pitched roles require `out amp freq gate`.

### Voice-contract test (works, with negative controls)
```supercollider
// Source: scratchpad probe8.scd. Bare isolated server (NO main.scd, so bus 0 has no master): any write to bus 0 is a bypass.
// per instrument: g = Group.new(s); b = Bus.audio(s, 2);
// probe synths AFTER the group: SynthDef(\pk, { |in = 0, id = 0| SendReply.kr(Impulse.kr(20), '/pp/test/peak', Peak.ar(In.ar(in, 2)), id) })
// spawn Synth(inst, [\out, b.index], g); wait 0.6; g.set(\gate, 0); wait 2.0;
// assert: controls include out+amp (+freq+gate for pitched roles); peak on b > 0; peak on bus 0 == 0; /g_queryTree numChildren(g) == 0
// Measured: ppPad out-peak 0.021, bus0 0.0, leftover 0   | ppKick 0.486 / 0.0 / 0
//           badBus0 (Out.ar(0,...)):   out 0.0, bus0 0.1   -> caught
//           badNoDone (no doneAction): leftover 1           -> caught
//           badNoGate (no gate/env):   leftover 1           -> caught
```
Keep the three bad voices as in-test fixtures (defined in `library_test.scd`, never in `library/`) and require the check to FAIL on each; that proves the check can fail.

### Git never-overwrite guard
```bash
# Source: verified in a scratch repo this session.
# 'A' (added) passes; 'M' modified, 'D' deleted, 'T' type change, renames (--no-renames turns R into D+A) fail.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "CHECK SKIP: library guard (not a git work tree)"; exit 0; }
bad=$(git diff --name-status --no-renames HEAD -- 'supercollider/library/*/[a-z0-9]*.scd' | grep -v '^A' || true)
# untracked new files are not listed by git diff at all -> they pass, as required
[ -z "$bad" ] || { echo "LIBRARY GUARD FAIL (existing library files must never be edited; add a new file instead):"; echo "$bad"; exit 1; }
```
Self-test it against a temp repo (committed file modified -> must exit 1; new file added -> exit 0; deleted -> exit 1).

### Counting for ENG-05 (all measured constant over 4 re-evaluations on v1.0)
```supercollider
// Source: scratchpad probe7.scd
var q = ~clock.queue;   // flat Array: [n, time, item, time, item, ...]; item count = (q.size - 1) / 3
Pdef.all.keys.asArray.sort;                 // v1.0: [ppArp, ppBass, ppClap, ppHat, ppKick, ppPad]; expect the 7 layer names (Pbindef shares Pdef.all)
TempoClock.all.size;                        // v1.0: 2 (default + ~clock); a leaked clock raises it
q.select(_.isKindOf(EventStreamPlayer)).size   // v1.0: 6 -> expect 7;  q.select(_.isKindOf(Routine)).size: v1.0 1 (ramp stepper) -> expect 1
s.numGroups; s.numSynthDefs; OSCdef.all.size;   // v1.0: 6, 115, 4 -> expect 6, 115, 7 (three new OSCdefs); s.numSynths varies 12-14, do not pin it
```
A stopped clock keeps its stale `queue` array in the language (read `queue` only on the live clock). Compare the *same* quantities after the first evaluation and after three more.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| v1.0 hard-coded `Pbindef` literals in `main.scd` | `Pbindef` whose content is a per-bar `Prout` reading library modules | This phase | New variations are files; the layer list and Stop path are unchanged |
| Six layers | Seven (`\ppLead`) | This phase (D-04) | Smoke set at `smoke_test.scd:833` gains `\ppLead`; the set at `:851` (sounding SynthDef names) does NOT change because the `classic` lead is silent and `classic_lead` reuses `\ppArp` |

**Deprecated/outdated:** STATE.md's "~75 s" smoke runtime (measured 144 s); PITFALLS' claim that `nowExecutingPath` is nil after a wait (not reproduced headless; keep the top-of-file capture anyway).

## Resolution of the three STATE.md research VERIFY flags

| Flag | Result | Evidence |
|------|--------|----------|
| `Pbindef(name).quant = 4` survives `doReset: true` | **Yes.** Default is `1.0`; stays `4` after `play(..., quant: 4, doReset: true)`, after stop/play, and after `.clear` `[VERIFIED: probes 3 and 13]`. In the `Prout` design no source swap happens, so it is a safety net for live `Pbindef(name, key, val)` edits, not a mechanism. Assert `Pbindef(n).quant == 4` in the smoke or library test. |
| `thisThread.beats` inside the per-bar body equals the bar start | **Yes, exactly.** 13 consecutive bars for two layers logged `beats` = 0.0, 4.0, 8.0, ... and `beats % 4 = 0.0` through two mid-run tempo changes (clock at 8, then 6, then 12 beats/s) `[VERIFIED: probe 3, Plazy inside Pbindef]`. Still floor with `(beats / 4 + 1e-6)`. |
| Per-(song, bar, role) seeding | **Yes, with an arithmetic seed.** `thisThread.randSeed = n` inside the per-bar body reproduced identical output across two processes; `Array.hash` must not be used (Pitfall 4). Two interleaved layers kept independent streams `[VERIFIED: probes 3 and 11]`. |

## Frozen Phase 4 -> Phase 5 interface (freeze now; Phase 5 depends only on this)

- Folders: `supercollider/library/progressions/`, `.../melodies/`, `.../palettes/`; items are `<stem>.scd`.
- Selectable stems: character set `a-z 0-9 _`, non-empty, not starting with `_` or `.`, not `auto`, not `README`-like non-`.scd` files; `classic` hoisted first by consumers; sorted otherwise.
- OSC (loopback, one string argument): `/pp/progression`, `/pp/palette`, `/pp/melody` with `auto` or a stem. Unknown/invalid -> engine warning, music unchanged; no reply is ever sent.
- `auto` in Phase 4 means `classic`; the wire keyword stays `auto` for all later phases.
- Re-sending the current name re-reads the file from disk (reload).

## Recommended plan decomposition (for the planner)

| Wave | Plan | Content | Gate |
|------|------|---------|------|
| 0 | A. Golden + harness | Recorder + parity-compare helpers, `golden/v1_events.scd` recorded from the **unmodified** `main.scd`, `library_check.sh` skeleton with the git guard and its self-test, `pp_select.sh` | Golden re-record yields identical md5; guard self-test passes; `scripts/smoke_test.sh` still 67 OK |
| 1 | B. Core + library (no `main.scd` edits) | `core/validate.scd`, `core/loader.scd`, `core/render.scd`, the 7 library files + 3 `_template.scd` + README; static `library_test.scd` layer (load every file, shape, side-effect and lint checks, language-only parity of the render function vs golden using stub out/group) | Static check green without a server |
| 2 | C. Split `main.scd` | `~ppRoot` capture, top-level core loads, move the six SynthDefs into `classic` palette `defs` (infrastructure SynthDefs stay), `\ppLead` as 7th layer, `~ppBuildLayers`, three OSCdefs, `~ppSel` persistence, teardown, banner; update `smoke_test.scd:833` | Existing smoke 67/67 plus parity green on the real engine |
| 3 | D. Gates | `library_test.scd` server layer (voice contract + negative controls, select/reload/fallback via a temp library root, no-gap and bar-line assertions, lead Stop with `classic_lead`), ENG-05 block in `smoke_test.scd`, `scripts/check.sh`, README one-liner, listening check | `scripts/check.sh` green; user listening check (checkpoint) |

Tests need an overridable library root (`~ppLibRoot`, default `~ppRoot +/+ "library"`) so fixtures (broken syntax, runtime error, non-Event, wrong shape, new valid file) can live in a temp directory and never in `library/`.

## `library_test.scd` shape (separate process, isolated port 57141)

1. **Static (no server, ~2 s):** load `core/validate.scd` + `core/loader.scd` directly; for every `library/<cat>/*.scd` (including `_template.scd`) assert: loads, returns an Event, `desc` present, stem valid, shape per category, no `~` use or forbidden calls in comment-stripped source (`~name`, `Pbindef|Pdef|Tdef|Ndef`, `.play`, `.fork`, `.wait`, clocks), load adds nothing to `Pdef.all`/`Tdef.all`, generators called outside a Routine return rows with durs summing to 4.0 over 16 synthetic bars. Print `LIBCHECK OK: <cat>/<stem>` per file.
2. **Voices (bare server):** palette `defs` -> `s.sync` -> voice-contract test with the three negative controls.
3. **Parity (load `main.scd`, as in the recorder):** record 16 bars, compare to the golden; the all-`classic` default must produce 0 lead rows.
4. **Selection/fallback (real UDP to `NetAddr.langPort`):** valid add-while-playing; broken syntax / runtime error / non-Event / wrong shape / unknown name / `../x` / empty / number: selection unchanged, music continues (event counts keep rising), captured `~ppLog` text contains the file path; `classic_lead`: first lead row lands on a bar line (`beat % 4 == 0`) and arp rows have no missing 16th across the switch.
5. Finish with `LIBRARY PASS` and exit 0; any failure prints `LIBRARY FAIL: <name>: <detail>` and exits 1. Own watchdog.

`library_check.sh` then cross-checks `grep -c "^LIBCHECK OK" log` against `find supercollider/library -name '*.scd' | wc -l` so a silently skipped file fails the run.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| SuperCollider (sclang/scsynth) | everything | ✓ | 3.14.1, `/Applications/SuperCollider.app/Contents/MacOS/sclang` | — |
| Audio device for isolated scsynth | server tests | ✓ (booted muted on ports 57140/57150/57151 this session) | — | — |
| git | guard | ✓ | 2.50.1 | guard prints `CHECK SKIP` outside a work tree |
| `timeout` | wrappers | ✓ | `/opt/homebrew/bin/timeout` (+ `gtimeout`) | wrapper already tolerates absence |
| `.venv/bin/python` + python-osc | smoke `sendCli`, `pp_select.sh` | ✓ | Python 3.13.12, python-osc import ok | `./run.sh --setup` |
| A running user engine on 57120 | must NOT be disturbed | none running at research time (`pgrep` empty) | — | tests use `NetAddr.langPort` and isolated server ports, never 57110/57120 explicitly |

**Missing dependencies with no fallback:** none. **Missing with fallback:** none.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | headless sclang scripts (`CHECK OK` / `SMOKE FAIL` / `LIBRARY FAIL` protocol) + bash wrappers; pytest 8.x for Python (unchanged) |
| Config file | none; `scripts/smoke_test.sh`, new `scripts/library_check.sh`, `scripts/check.sh` |
| Quick run command | `scripts/library_check.sh` (target 30-45 s) |
| Full suite command | `scripts/check.sh` (guard + library check + 67+ smoke checks; target about 3 min) and `.venv/bin/python -m pytest -q` (150 pass) |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| LIB-01 | all-`classic` startup emits the v1.0 events; smoke unchanged | parity + regression | `scripts/library_check.sh` (parity) ; `scripts/smoke_test.sh` | ❌ Wave 0 (golden, `library_test.scd`); smoke ✅ |
| LIB-02 | every file known by stem; folders and `classic` exist; count cross-check | static | `scripts/library_check.sh` | ❌ Wave 0/1 |
| LIB-03 | modified/deleted committed library file fails | shell + self-test | `scripts/library_check.sh` | ❌ Wave 0 |
| LIB-04 | broken/invalid/unknown/hostile names refused, error names the file, music continues | integration | `scripts/library_check.sh` (selection block) | ❌ Wave 3 |
| LIB-05 | add/change while playing, select by name over OSC, applied on a bar line with no missing 16th | integration | `scripts/library_check.sh` | ❌ Wave 3 |
| LIB-06 | every file validates; voices obey out/gate/doneAction; negative controls fail | server | `scripts/library_check.sh` | ❌ Wave 1/3 |
| ENG-05 | 3 re-evaluations + module re-evaluation leave identical counts; Stop empties instrument group incl. lead under `classic_lead` | smoke | `scripts/smoke_test.sh` (new block) | ❌ Wave 3 (extends existing file) |

### Sampling Rate
- **Per task commit:** the relevant script only (`library_check.sh` for loader/library work; `smoke_test.sh` for `main.scd` work).
- **Per wave merge:** `scripts/check.sh`.
- **Phase gate:** `scripts/check.sh` green, pytest green, then the user listening check (D-01), before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `supercollider/golden/v1_events.scd` — recorded from the unmodified v1.0 `main.scd` (covers LIB-01)
- [ ] `supercollider/library_test.scd` — recorder/compare helpers first, other blocks per wave (LIB-01..06)
- [ ] `scripts/library_check.sh`, `scripts/check.sh`, guard self-test fixture (LIB-03)
- [ ] Framework install: none

## Security Domain

`security_enforcement` is enabled (ASVS level 1, block on high). The attack surface is small: loopback UDP strings that choose a file to execute.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | loopback-only `srcID: NetAddr("127.0.0.1", nil)` (existing pattern, reused) |
| V3 Session Management | no | stateless UDP |
| V4 Access Control | yes (file access) | path built only from a validated stem and a fixed category whitelist; `File.realpath` containment inside the library root |
| V5 Input Validation | yes | char-loop stem rules (not regex), type checks on `msg[1]`, `auto` reserved, leading `_`/`.` rejected |
| V6 Cryptography | no | none |
| V12 Files/Resources | yes | only `*.scd` under the library root are loadable; no OSC-supplied path; library files are code executed by `load`, so the trust boundary is "files committed to this repo" |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Path traversal via the OSC name (`../x`) | Tampering / EoP | stem char whitelist + realpath containment; `'../x'` arrives as a Symbol and must be rejected (probe confirmed it arrives intact) |
| Trailing-newline bypass of an anchored regex | Tampering | char loop (verified regex hole) |
| Symlink inside `library/` pointing outside | EoP | compare `File.realpath(candidate)` prefix with `File.realpath(root)` |
| Hostile/buggy library file (runtime error, infinite loop, `Out.ar(0)`) | DoS / Tampering | `try`, row validation, voice-contract test; an infinite loop in a file cannot be contained in-process (accepted: files are repo-controlled; the library check catches it before a ride) |
| Non-loopback OSC sender | Spoofing | existing `srcID` guard on all three new OSCdefs |
| Shell injection in the guard script | Tampering | the script uses fixed arguments and no user/OSC input |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | In the SC IDE, `thisProcess.nowExecutingPath` can be nil for an unsaved document or after async resumes (not reproduced headless) | Pitfall 3 | Low: the top-of-file capture plus a clear thrown error handle both cases |
| A2 | Re-adding an identical SynthDef while its synths sound leaves running synths unaffected and new notes use the (identical) new def | Pattern 3 / palette reload | Low for `classic` (identical bytes); revisit in Phase 7 when defs differ |
| A3 | A starting `classic_lead` amp of about 0.025 (arp 0.1 minus 12 dB) will read as "faint shimmer" | D-06 | Low: it is tuned by ear; the git-guard escape hatch exists |
| A4 | Compile/load cost of library files is negligible next to `s.latency` (measured `String:compile` of 18 KB and 73 KB sources: 0.2 ms and 1.1 ms; real `load` of library-size files not separately timed) | Pattern 3 | Low |
| A5 | The 4 `Function` items in the clock queue (v1.0) are stable and not part of the ENG-05 invariant | Code Examples | Low: assert on the `EventStreamPlayer`/`Routine` class counts only |
| A6 | The user accepts a loud, explicit `PP_LIBRARY_ALLOW_EDIT` override for tuning `classic_lead` after commit | Pitfall 9 / Open Question 1 | Medium: user may prefer a different mechanism; needs confirmation |
| A7 | A silent 7th layer adds negligible CPU next to Zwift | Summary | Low; the real-ride check is Phase 9 (ENG-03) |

## Open Questions (RESOLVED)

1. **Tuning `classic_lead` after it is committed vs the never-overwrite guard**
   - What we know: D-06/Discretion say the level is tuned at the end-of-phase listening check; the guard compares against HEAD and fails on a modified committed file; `human_verify_mode` is end-of-phase (config).
   - What's unclear: whether the user wants the override env var, or prefers that any post-commit change becomes `classic_lead2.scd`.
   - Recommendation: implement the explicit per-file override (printed loudly), keep `classic_lead` the only file expected to use it, and let the planner confirm with the user at the checkpoint.
   - RESOLVED (orchestrator, from the user's stated preferences: keep it simple, every variation is a new file): no `PP_LIBRARY_ALLOW_EDIT` override is built. The guard stays strict. If the listening check asks for a different `classic_lead` level or voice, it lands as a new library file (for example `classic_lead_soft.scd`) and the committed file stays untouched and selectable. Assumption A6 is closed the same way. Plans 04-01 (guard) and 04-06 (listening check) carry this.
2. **One command: new `scripts/check.sh` or extend `scripts/smoke_test.sh`?**
   - What we know: either satisfies success criterion 4; STATE.md calls `smoke_test.sh` the regression harness.
   - Recommendation: new `scripts/check.sh` (guard, then library check, then smoke), leaving `smoke_test.sh` byte-identical in behaviour.
   - RESOLVED: new `scripts/check.sh` with a `--library-only` fast loop. To keep the number of scripts minimal, there is no separate `scripts/library_check.sh` and no `scripts/pp_select.sh`; the selection one-liner is documented in `supercollider/library/README.md`. `scripts/smoke_test.sh` is unchanged (Plans 04-01, 04-05).
3. **Should `auto` for palettes/progressions already accept being "set" while behaving as `classic`?**
   - Recommendation: yes, store `\auto` in `~ppSel` and resolve in one function so Phases 6-7 change one place.
   - RESOLVED: yes. `\auto` is stored in `~ppSel` and resolved to `classic` by `~ppResolveStem` (Plans 04-02, 04-03).
4. **Does a melody file that omits `arp` fall back to `classic`'s arp?**
   - Recommendation: yes (per ARCHITECTURE); for `lead`, `classic` has none, so the fallback is a rest bar.
   - RESOLVED: yes. The order is module generator, then the classic generator, then a single rest bar (Plans 04-02, 04-03).

## Sources

### Primary (HIGH confidence)
- Local SC 3.14.1 headless probes run this session (`sclang -D`, isolated servers 57140/57150/57151): load semantics, `nowExecutingPath`, `Pbindef` quant/clear/merge/redefinition, bar-start `thisThread.beats`, seeding, hash stability, OSC string argument classes, regex edge, recorder, golden determinism, prototype parity (0 mismatches), ENG-05 invariants over 4 re-evaluations, voice-contract test with negative controls, generator-error behaviour, compile timings
- `supercollider/main.scd`, `supercollider/smoke_test.scd`, `scripts/smoke_test.sh`, `python_app/osc_client.py`, `python_app/config.py` (read this session)
- Baseline run of `scripts/smoke_test.sh`: 67 `CHECK OK`, `SMOKE PASS`, 2:24 wall; `pytest`: 150 passed
- Scratch git repo experiments for the guard semantics

### Secondary (MEDIUM confidence)
- `.planning/research/ARCHITECTURE.md`, `SUMMARY.md`, `STACK.md`, `PITFALLS.md` (project research, partly re-verified above); `04-CONTEXT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`

### Tertiary (LOW confidence)
- IDE-specific `nowExecutingPath` behaviour (documentation/forum claims in PITFALLS.md; not reproducible headless)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all classes exercised.
- Architecture: HIGH for parity, loader, ENG-05 and voice tests (prototyped); MEDIUM for the forward-compatible contract (depends on Phases 6-9 honouring "additive and optional").
- Pitfalls: HIGH — each of the numbered pitfalls 1-8 was reproduced or measured this session.

**Research date:** 2026-10-11
**Valid until:** 2026-11-10 (stable SC 3.14.1 line; re-check only if SuperCollider is upgraded)
