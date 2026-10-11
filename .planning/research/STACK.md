# Stack Research: v2.0 Living Music (additions only)

**Domain:** Generative melodic techno / progressive trance engine in SuperCollider, with a send-only Tkinter control app
**Researched:** 2026-10-11
**Confidence:** HIGH. Every SC claim below was run against the installed SuperCollider 3.14.1 with headless `sclang -D` on 2026-10-11. The Python claims were checked against the project venv (Python 3.13, Tk 9.0, python-osc 1.10.2).

## Headline

**v2.0 needs zero new dependencies.** There are no new pip packages, no quarks and no sc3-plugins. Everything is stock SuperCollider 3.14.1 classes plus Python stdlib (`pathlib`, `tkinter.ttk`) and the existing `python-osc==1.10.2`. `requirements.txt` stays one line. The work is in the patterns and conventions below, not in libraries.

Things I expected to be stock and are **not** (verified against the installed class library, so do not plan around them):

| Expected | Reality in 3.14.1 | Use instead |
|----------|-------------------|-------------|
| `MarkovSet` / `MarkovSetN` | Not in the stock class library (they come from a quark) | A transition table `Dictionary` plus `Array.wchoose(weights)` (about 5 lines) |
| `Pmarkov` | Not in the stock class library | The same transition table, called from a `Routine` or `Pfunc` |
| `Pdegrees` | Not a class | The `\degree` / `\scale` / `\root` / `\octave` keys of the default `\note` event |
| `Pchoose` | Not a class | `Prand` / `Pwrand` |

## Recommended Stack Additions

### Core: SuperCollider stock classes for the new features

All of these exist in 3.14.1 (checked with `.asClass.notNil`). No version change to SC: stay on the installed 3.14.1.

| Capability | Class / API | Why this one | Integration point |
|------------|-------------|--------------|-------------------|
| Load a library file by absolute path | `String:load` (`path.load`) returns the file's **last expression** | A library file is just a script whose last line is an `Event` of Functions/data, e.g. `(name: \dark, make: { ... })`. No `Quarks`, no `Require`. The loaded file sees `thisProcess.nowExecutingPath` as its own path (verified), so a module can find sibling files | `main.scd` does `(~ppRoot +/+ "library/palettes/*.scd").pathMatch.do { |p| ... p.load ... }` |
| Enumerate the library | `String:pathMatch` (glob) or `PathName(dir).entries`, plus `.fileNameWithoutExtension` | `pathMatch` returns full paths, sorted. File stem = the name shown in the GUI and sent over OSC, so one naming source of truth | Same scan in SC (build the registry) and in Python (build the dropdown) |
| Locate the project root from inside `main.scd` | `File.realpath(thisProcess.nowExecutingPath).dirname` | Already the pattern in `smoke_test.scd`. A relative `nowExecutingPath` is possible when sclang is given a relative path, so resolve it. Do **not** rely on `loadRelative` from within `waitForBoot`: it needs the executing path at call time, so capture the root into `~ppRoot` once at the top of the file, outside `waitForBoot` | `~ppRoot` defined at file top, next to the other tuning globals |
| Registry of loaded content | Plain `Event` / `Dictionary` per category (`~ppLib = (palettes: (), progressions: (), melodies: ())`) keyed by name `Symbol` | Re-evaluating a module is just `~ppLib[\palettes][\dark] = path.load`. No class, no proxies, trivially inspectable, trivially smoke-testable | New globals; re-scan on `main.scd` re-evaluation and optionally on a new `/pp/rescan` |
| Live-swap a layer's content | `Pbindef(\ppArp, \key, newPattern)` on the **existing named** Pbindef | Verified: changing a key of a playing `Pbindef` takes effect on the next event. But the new `Pseq` restarts from index 0, which loses phase against the bar | **Set `Pbindef(name).quant = 4` once at build time** (default is 1.0). Verified: a swap issued mid-bar (beat 26) took effect on the next bar line (beat 28) and the old pattern played out until then |
| Shared harmony state | One `Event` (`~ppHarm = (root: 9, scale: Scale.minor.degrees, chord: [0,2,4], bar: 0)`) mutated by one `Routine` on `~clock`; layers read it with `Pfunc` | One writer, many readers, no proxies to manage, same pattern as `~ppRampStepper` being the sole tempo writer. `Pdefn(\root, x)` also works (verified) but applies **mid-bar** (next event), so it adds nothing over a plain event and hides the writer | Layers: `\root, Pfunc { ~ppHarm.root }`, `\degree, Pfunc { ~ppHarm.chord }` |
| Pitch from scale degrees | Default `\note` event keys `\degree`, `\scale`, `\root`, `\octave`, `\mtranspose`, `\ctranspose` | Verified: `(degree: [0,2,4], scale: Scale.minor, root: 9, octave: 4)` yields MIDI `[57, 60, 64]` and an array `\degree` is a chord. This is what lets one chord drive bass, arp, pad and lead with the right octave per layer, and lets the key move without rewriting any note list | Replaces the hard-coded `\midinote, Pseq([57,60,64,60])` in `ppBass/ppArp/ppPad`. `Scale.minor.degrees` etc. are stock (`Scale.dorian`, `phrygian`, `harmonicMinor` ...) |
| Weighted / random melody choice | `Pwrand`, `Prand`, `Pxrand` (no immediate repeats), `Pwalk`, `Pbrown`/`Pgbrown`, `Pwhite` | `Pwalk` is a stepwise random walk over an index list (good for melodic contour); `Pxrand` avoids stuttering; `Pwrand` biases to chord tones. All stock | Lead/arp note generation inside a module's `make` function |
| Motif repeat + mutate | A `Routine` (or `Tdef`) owning a motif `Array` in the environment, mutated with plain `Array` methods (`rotate`, `reverse`, `scramble`, `put`, `perform`), plus `Pfunc`/`Pseq(motif)` for playback | Motif state is a visible array, mutation is explicit rules (transpose one note by a step, drop a note, rotate). Easier to describe in plain words and to unit-check than `Pfsm` or lazy nested pattern graphs | Lead layer reads `~ppMotif` via `Pfunc`; a phrase-boundary Routine mutates it |
| Weighted state machines (progression next-chord, section order) | `Array:wchoose(weights)` / `Array:windex` over a transition `Dictionary` | Verified. Stock `Pfsm` exists but its nested-array syntax is opaque; for 5-8 states a dictionary of weights is clearer and printable | Harmony Routine picks next chord; structure Routine picks next section |
| Repeatable randomness for tests | `thisThread.randSeed = n` / `Pseed` | Verified. Lets the smoke test assert deterministic motif output without mocking | `smoke_test.scd` |
| Structure on several timescales | One `Routine`/`Tdef` per timescale, all `.play(~clock, quant: 4)` (phrase, section) | Same clock as every layer, so sections stay phase-locked through tempo glides (the v1 rule). Do **not** create a second `TempoClock` | Section Routine flips flags (`~ppSection = \build`) that layers read via `Pfunc` |
| Rests / fills | `\rest` symbol (already used) or `Rest(dur)` (stock in 3.14.1) | Density via EPIC = probability of rest: `Pfunc { if (0.0.rrand(1.0) < ~ppDensity) { note } { \rest } }` | EPIC arrives on `~epic`; derive `~ppDensity` from it (the engine already holds `~epic` as a float, no new bus needed for control-rate pattern decisions) |
| String OSC args | `OSCdef` handler, `msg[1]` | **Verified: a string arrives as a `Symbol`** (class `Symbol`, spaces preserved, empty string arrives as the empty Symbol, no argument gives `nil`). Do **not** call `.isSymbol` (not a method in 3.14.1: it throws `doesNotUnderstand` inside the handler) or `.isString`. Validate with `msg[1].notNil` then look the name up in the registry | New `OSCdef(\pp_palette / \pp_progression / \pp_melody, ...)`, same loopback-only `srcID: NetAddr("127.0.0.1", nil)` as the existing four |

### Supporting: Python (stdlib only)

| Need | Use | Version | Why / integration |
|------|-----|---------|-------------------|
| Scan `supercollider/library/<category>/*.scd` | `pathlib.Path.glob("*.scd")` | stdlib | Sorted stems become the dropdown values. Prefix with the literal `"Auto"`. Keep the scan in a small pure function (e.g. `library.py`) so it is pytest-able with `tmp_path` and no Tk |
| Locate the library folder | `Path(__file__).resolve().parent.parent / "supercollider" / "library"` | stdlib | Same project-relative convention as `run.sh`; no config file, no env var |
| Dropdown selectors (Auto or named item) | `tkinter.ttk.Combobox(state="readonly")` | stdlib, verified present under Tk 9.0.3 in the project venv | Readonly means the rider can only pick a value that exists on disk. The existing `view.py` uses plain `tk` widgets; `ttk` is the same package, no dependency, no new import risk |
| Send a name | `SimpleUDPClient.send_message("/pp/palette", "Dark Pad")` | python-osc 1.10.2 (unchanged) | Verified: a Python `str` packs as an OSC `s` argument (`b',s\x00\x00Dark Pad\x00...'`). No bytes/encoding handling needed. Keep the existing `except (OSError, OverflowError, BuildError)` envelope in `OscClient` |
| Lock palette rotation | `int` over OSC (`/pp/palette_lock 0|1`) or the sentinel name `"Auto"` | python-osc 1.10.2 | Prefer the sentinel: "Auto" = rotate, any real name = locked. One message, no second control, nothing to desync |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `scripts/smoke_test.sh` (existing) | Extend with library checks | Keep `unset QT_QPA_PLATFORM` (offscreen aborts sclang 3.14.1 on macOS, exit 134). Add: every file in `library/` loads and returns the expected shape; a deliberately broken module does not stop the music; unknown name over OSC is ignored with a warning; no node count growth over N bars |
| `pytest` 8.4.2 (existing) | Test `library.py` scan, the dropdown wiring helper and the new send methods | Use `tmp_path` for a fake library; no new dev dependency |
| `thisThread.randSeed` | Deterministic melody tests in SC | Seed inside the check, restore afterwards |

## Installation

```bash
# Nothing to install. requirements.txt stays:
#   python-osc==1.10.2
# requirements-dev.txt stays:
#   -r requirements.txt
#   pytest==8.4.2
# SuperCollider stays 3.14.1 (installed). No Quarks.install, no sc3-plugins.
```

## Integration Notes (things that will bite if ignored)

1. **Module file contract.** Every library file's last expression is the module value. Make it an `Event` with a fixed shape per category, for example a palette: `(name: "Dark", synthDefs: { ... .add ... }, voices: (arp: \ppDarkArp, pad: \ppDarkPad, ...))`. Keep side effects (SynthDef `.add`) inside a function the core calls at a known moment (inside the `waitForBoot` Routine, followed by `s.sync`), not at file top level. This keeps load order predictable and makes each file re-evaluable.
2. **Loading must run inside a Routine.** `s.sync` needs a thread; the existing `s.waitForBoot` already provides one. Calling `.load` on a nonexistent path does not throw, it posts `file "..." does not exist.` and returns `nil` (verified). Wrap each load in `try { path.load } { |e| ... nil }` and check `notNil` and the expected keys before registering, so a typo'd module is skipped, not fatal.
3. **Module `.load` isolation.** A file's `var` declarations are local to that file (verified with a `var x = 3` module), so modules cannot clobber each other. Do not use `~globals` inside modules for state the core also owns, except through the documented registry/harmony event.
4. **SynthDef names.** Namespace per palette (`\ppDark_arp`, not `\arp`). `SynthDef(...).add` with an existing name replaces it for new notes, which is exactly the re-evaluation behaviour wanted, but two palettes sharing a name would silently overwrite each other. The existing teardown frees nodes, not SynthDefs, so no cleanup is needed.
5. **Fixed Pbindef names, never fresh ones.** Layers keep the six v1 names in `~ppLayers`. Creating uniquely named `Pdef`/`Pbindef`/`Tdef` per section would grow `Pdef.all` forever and break the ENG-03 60-minute stability goal. Swap content into existing proxies.
6. **Same-beat ordering.** A bar-boundary `Routine` and a layer `Pfunc` that both fire on beat N have no specified order. In a test the harmony routine happened to win (the layer saw bar N on beat N, i.e. the updater ran first, probably because it was scheduled first), but that is insertion-order luck: restarting a layer (Stop/Start does `doReset: true`) reschedules it. Either (a) make the harmony Routine publish the chord for the **next** bar a beat early into a `next` slot that layers promote only at their own bar start, or (b) compute the chord statelessly from the bar index, `~ppChordAt.(thisThread.clock.beats.div(4))`. Pick (b) if possible: no shared mutable state, no race. This is a design decision for ARCHITECTURE; flag it as a Phase-1 spike.
7. **Palette swap timing.** Swapping `\instrument` on a playing `Pbindef` with `quant = 4` changes sound at the bar line while sustaining notes (pads) ring out on their old SynthDef's release. This is the right behaviour; do not try to free nodes.
8. **Re-evaluation vs rescan.** Python reads the folder at app launch (and may re-scan on a small "Refresh" action); the engine reads it at `main.scd` evaluation. A file added after both started is only visible once both rescan. With a send-only app, handle an unknown name defensively on the engine (warn, keep the current item). An optional `/pp/rescan` OSC message (engine reloads the folder) keeps the rider from re-running `main.scd`; it is not required for v2.0.
9. **Names are the shared vocabulary.** File stem == GUI label == OSC string == registry key. Keep stems filesystem and OSC friendly (letters, digits, `_`, `-`, space tolerated: spaces survive the OSC Symbol round trip). Sort alphabetically on both sides so the lists agree.
10. **CPU on the Zwift Mac.** Prefer a few SynthDefs per palette with parameters over many nodes. EPIC density should reduce **event count** (rests), which cuts node churn at Recovery. Check the server stays under default limits (`maxNodes` 1024, `memSize` 8192 KB are ample for six layers; reverb stays the single shared `\ppFx`). Do not add per-voice reverb/delay UGens: FX stay in the shared `\ppFx`.

## Alternatives Considered

| Recommended | Alternative | When the alternative is better |
|-------------|-------------|--------------------------------|
| `String:load` + registry `Event` | `Require` / `loadRelative` chains from the `Require` quark | Never here: `Require` is a quark (breaks the no-quarks rule). `loadRelative` works but resolves against the *calling* file and awkwardly inside `waitForBoot`; absolute `~ppRoot +/+ path` is simpler and testable |
| Plain event + `Pfunc` for harmony | `Pdefn` or `Ndef`/`ProxySpace` to hold chord state | `Pdefn` if a separate pattern must *stream* chord values quantized by proxy; verified it applies mid-bar, so it needs extra quantization anyway. `Ndef`/`ProxySpace` are server-side node proxies, not needed for control-rate pattern decisions |
| `wchoose` transition dictionaries | `Pfsm`, or `MarkovSet`/`Pmarkov` (quark) | `Pfsm` if you already think in nested state arrays; `MarkovSet` if you want to *learn* transitions from example melodies (not a v2.0 need, and it is a quark) |
| `Routine`s on `~clock` for structure | `Ptpar`/`Pspawner`/`PatternConductor` | `Pspawner` if the whole song is one declarative score; here sections must react to live EPIC and GUI locks, which a Routine handles more directly |
| `ttk.Combobox` | `tk.OptionMenu` or `tk.Listbox` | `OptionMenu` matches the v1 plain-`tk` look more closely; `Combobox` has better keyboard behaviour and a readonly mode. Either is stdlib; choose `Combobox` unless the visual style clashes in the existing `view.py` |
| Python scans the folder on disk | Engine sends the list back over OSC | Only if engine-to-GUI feedback is ever reinstated. It was deliberately dropped (send-only app), so no |
| Name-only OSC messages | Sending whole module contents or numeric indices | Indices desync the moment a file is added in one side; names are stable |

## What NOT to Use

| Avoid | Why | Use instead |
|-------|-----|-------------|
| Any quark (`ddwPatterns`, `Require`, `MarkovSet`, `JITLibExtensions`, `cxpatterns`, `Bjorklund` quark) | Project rule; each is a network install plus a version-pin that can break on SC upgrade. Verified the installed machine has 0 quarks | Stock `Pwrand`/`Pwalk`/`wchoose`, hand-rolled Euclidean rhythm (about 10 lines) if wanted |
| sc3-plugins UGens | Extra native install, not needed for melodic synths | Stock UGens (`Saw`, `Pulse`, `SinOsc`, `RLPF`, `LPF`, `Splay`, `FreeVerb2`, `Limiter`, `Lag`) |
| A second `TempoClock`, or `SystemClock`/`AppClock` for musical events | Breaks phase-lock through tempo glides (the v1 rule) | `.play(~clock, quant: 4)` for every Routine and pattern |
| New `Pdef`/`Pbindef`/`Tdef`/`Ndef` names created at runtime per section or per palette | `Pdef.all` growth defeats ENG-03 and makes teardown incomplete | Swap content into the fixed proxy names in `~ppLayers` and `~ppStruct*` |
| `.isSymbol` / `.isString` on OSC string args | `isSymbol` throws `doesNotUnderstand` in 3.14.1; strings are Symbols anyway | `msg[1].notNil` then `msg[1].asSymbol` as the registry key |
| Python-side watchers (`watchdog`, `inotify`), PyYAML/TOML config, `mido`, `music21`, `numpy` | A whole dependency for a one-off `glob`; the music logic lives in SC, not Python | `pathlib.Path.glob`; rescan on launch (and a Refresh button if wanted) |
| Heartbeat/ack/reply channel from the engine | Dropped on 2026-10-10; the app stays send-only | Engine validates names itself and warns on the post window |
| Running library files with `interpret`/`.asCompileString` round trips, or `thisProcess.interpreter.executeFile` directly | Reimplements `load` and loses error isolation | `path.load` inside `try` |
| Python threads, asyncio or an OSC server in the app | Nothing in v2.0 needs inbound OSC | Keep the single `SimpleUDPClient` |

## Stack Patterns by Variant

**If a module needs its own SynthDefs (every palette does):**
- Put `SynthDef(...).add` inside a `setup`/`build` Function stored in the module `Event`, called by the core inside the boot Routine, then `s.sync`.
- Because top-level side effects at load time cannot `sync` and make "load all files to build the GUI list" unsafe.

**If a progression or melody style is data only (no SynthDefs):**
- Return an `Event` of arrays/Functions and nothing else; no `s.sync` needed.
- Because these can be re-evaluated mid-playback with zero server traffic, which is the cheapest re-evaluation path.

**If the rider locks a palette:**
- Palette rotation Routine checks a `~ppPaletteLocked` flag at its own bar boundary and skips; a named OSC selection sets the flag, `"Auto"` clears it.
- Because the lock then needs no separate message type or Python state.

## Version Compatibility

| Item | Compatible With | Notes |
|------|-----------------|-------|
| SuperCollider 3.14.1 (installed, verified) | All APIs above | `Rest`, `Pwalk`, `Pwrand`, `Pfsm`, `Pdict`, `Pseed`, `Pbindef.quant` all present. No upgrade needed. |
| python-osc 1.10.2 | Python 3.13, `str` OSC args | Unchanged; string packing verified |
| Tk 9.0 (project venv) | `ttk.Combobox` | Class present; the v1 widget-level smoke test approach (`test_view_tk.py`) extends to it |
| sclang headless (`sclang -D`) | Library loading in smoke tests | Scripts run on the main thread: any `.wait` must be inside a `Routine`, or sclang errors with "yield was called outside of a Routine" (hit this during research) |

## Gaps / Needs a Spike (not blocking)

- Same-beat ordering between the harmony writer and layer `Pfunc`s (see note 6): confirm stateless lookup survives a mid-song Stop/Start and a tempo glide. Spike in the harmony phase.
- Whether `Pbindef(name).quant = 4` is reset by `Pbindef(name).play(..., doReset: true)` on Start (the v1 Start path). Quick check with the existing smoke harness.
- Real CPU/node cost of 6 layers plus a lead plus fills on the Zwift machine: only measurable on a ride; the ENG-03 60-minute check should record node count and CPU for the new engine.
- Behaviour of long-lived `Routine`s across `main.scd` re-evaluation: the v1 teardown stops `~ppRampStepper` explicitly; every new Routine (harmony, structure, palette rotation, motif mutator) needs the same stop-and-nil in the teardown block, or re-evaluation stacks them.

## Sources

- Local verification on the installed SuperCollider 3.14.1 (`/Applications/SuperCollider.app`), 2026-10-11, headless `sclang -D` scripts (HIGH): stock class presence checks, `String:load`/`pathMatch`/`PathName`, load of a missing file, `var` isolation in loaded files, `OSCdef` string argument class (`Symbol`), `Pbindef` key swap timing with and without `quant = 4`, `Pdefn` update timing, `\degree`/`\scale`/`\root`/`\octave` to MIDI conversion, `wchoose`/`windex`/`randSeed`, 0 quarks installed.
- Local verification in the project venv (`.venv`, Python 3.13, Tk 9.0, python-osc 1.10.2), 2026-10-11 (HIGH): `ttk.Combobox` present; `OscMessageBuilder.add_arg("Dark Pad")` packs an OSC `s` argument.
- `/Users/marcogiordano/Documents/personali/lab/PedalPulse/supercollider/main.scd`, `python_app/osc_client.py`, `python_app/config.py`, `scripts/smoke_test.sh`, `.planning/PROJECT.md` (HIGH): existing integration points.
- SuperCollider documentation (Pattern Guide, Pbindef, Pdefn, OSCdef, String help) was not re-fetched; behaviour above is empirical on 3.14.1, which is the stronger source for this machine.

---
*Stack research for: v2.0 Living Music (modular, generative SuperCollider engine plus library selectors)*
*Researched: 2026-10-11*
