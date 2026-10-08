# Architecture Research

**Domain:** Generative music engine (SuperCollider) + external real-time controller (Python/Tkinter) over OSC
**Researched:** 2026-10-08
**Confidence:** MEDIUM-HIGH (core SC idioms and python-osc/Tkinter threading pattern are well-documented and cross-checked against official docs + community sources; the specific "conductor + shared harmony" composition shown here is a synthesis of established JITLib/Patterns idioms, not a single canonical reference)

## Standard Architecture

### System Overview

```
┌───────────────────────────── Python process (Tkinter) ──────────────────────────────┐
│                                                                                        │
│  ┌──────────────┐      ┌───────────────┐      ┌────────────────────────────────┐    │
│  │   Tk View    │◄────►│  App Model    │◄────►│   OSC Client (send)             │    │
│  │ sliders/btns │      │ bpm, epic,    │      │ python-osc SimpleUDPClient      │    │
│  │ (main thread)│      │ playing, vol  │      └───────────────┬────────────────┘    │
│  └──────▲───────┘      └───────▲───────┘                      │ UDP /pp/*           │
│         │ .after(ms, poll)     │ pushes via Queue              ▼                     │
│  ┌──────┴───────────────┐      │                      ┌────────────────────┐        │
│  │ Queue (thread-safe)  │◄─────┴──────────────────────┤ OSC Server (recv)  │◄───┐   │
│  └──────────────────────┘                              │ daemon thread      │    │   │
│                                                         └────────────────────┘    │   │
└─────────────────────────────────────────────────────────────────────────────────┼───┘
                                                                                     │ UDP /pp/status, /pp/heartbeat
┌─────────────────────────────── SuperCollider process (sclang + scsynth) ──────────┼───┐
│                                                                                     │   │
│  ┌──────────────────┐   sets   ┌───────────────────────────┐   sends every N sec  │   │
│  │ OSCdef handlers   ├─────────►  Conductor (global state)  ├──────────────────────┘   │
│  │ /pp/bpm /pp/epic  │          │ ~bpm ~epic ~playing ~vol  │                           │
│  │ /pp/play /pp/vol  │          │ TempoClock.default        │                           │
│  └──────────────────┘          └─────────┬──────────────────┘                          │
│                                           │ reads                                        │
│              ┌────────────────────────────┼────────────────────────────┐                │
│              ▼                            ▼                            ▼                │
│      ┌───────────────┐           ┌───────────────┐            ┌───────────────┐         │
│      │ Harmony clock │  writes   │ Pdefn/control  │   reads    │ Tempo ramp    │         │
│      │ (chord state) │◄─────────►│ bus fan-out    │◄───────────│ routine       │         │
│      └───────┬───────┘           └───────┬───────┘            └───────────────┘         │
│              │ shared root/degree         │ \epic value (pattern + audio rate)            │
│    ┌─────────┼─────────┬──────────────────┼───────────────┐                              │
│    ▼         ▼         ▼                  ▼                                              │
│  Pbindef   Pbindef   Pbindef         Ndef/SynthDef params (filter cutoff, drive,          │
│  (bass)    (arp)     (pad)           reverb/delay mix) via control-bus .map               │
│    │         │         │                   │                                              │
│    └─────────┴─────────┴───────────────────┘                                              │
│                        ▼                                                                   │
│              Synths Group (addToHead)                                                     │
│                        ▼  (audio bus / send)                                              │
│              FX Group — reverb/delay/filter (addToTail)                                   │
│                        ▼                                                                   │
│              Master Group — volume, limiter → hardware out                               │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|-------------------------|
| SynthDefs | Define drum voices, bass, arp, pad timbres, and FX processors (filter, drive, delay, reverb) as server-side DSP graphs | `SynthDef(\name, {...}).add` in a dedicated `synthdefs.scd`, loaded once at boot |
| Groups / audio buses | Enforce signal order: instruments render first, FX reads from a shared bus and processes, master applies volume/limiting | `Group.new` (addToHead) for instruments, `Group.after(instrGroup)` for FX, a final master `Synth` or `Ndef(\master)` reading the mix bus |
| Conductor (state layer) | Single source of truth for `bpm`, `epic` (0-100), `playing`, `volume`; everything else reads from here, nothing else owns these values | A plain `Event`/`Dictionary` in an `Environment` variable (e.g. `~conductor`), or simply top-level `~bpm`, `~epic` vars — deliberately simple, not a class |
| TempoClock | Drives all `Pdef`/`Pbindef` timing; its `.tempo` is the only tempo authority in the engine | `TempoClock.default` (or a dedicated `TempoClock.new` stored in the conductor) |
| Tempo ramp routine | Moves the clock's actual tempo toward a target over musical time without an audible jump | A `Routine`/`Tdef` scheduled on the clock itself, stepping `clock.tempo_` once per beat (or every N beats) |
| Harmony clock | Owns the chord/scale progression; advances on a bar/phrase boundary; is the *only* writer of root/degree/scale | A `Routine` (or a `Pdefn` driven by a slow `Pseq`/`Pwrand` over chord indices) writing into shared `Pdefn`s |
| Pdefn fan-out (value patterns) | Broadcasts current harmony and EPIC-derived *musical* parameters (density, note choice, probability of fills) to every instrument pattern that asks | `Pdefn(\root, ...)`, `Pdefn(\epic, Pfunc({ ~epic }))`, consumed via `Pdef`/`Pbindef` argument references |
| Control bus fan-out (continuous/audio-rate) | Broadcasts EPIC-derived *timbral* parameters (filter cutoff, drive amount, reverb/delay mix) to running synths with zero pattern-rate latency | `Bus.control(s, 1)`, set directly with `.set(value)` (sends `/c_set`), read inside SynthDefs via `In.kr(bus)` or via `.map` on an `Ndef`/running `Synth` |
| Pbindef per instrument | One `Pbindef` (or `Pdef` wrapping a `Pbind`) per musical voice: drums, bass, arp, pad; each reads the shared `Pdefn`s for harmony/epic rather than deciding independently | `Pbindef(\bass, \instrument, \bass, \degree, Pdefn(\root) + ..., \dur, ...)` |
| OSCdef handlers | Parse incoming `/pp/*` messages, validate, write into the conductor, trigger side effects (start/stop ramp routines) | One `OSCdef` per address in a dedicated `osc.scd`, all writing only to conductor state — no business logic inline |
| Status/heartbeat sender | Periodically (and/or on request) sends current engine state back to Python so the GUI can reflect reality (e.g. after a reconnect) | A `Routine` on `SystemClock` (not the music `TempoClock`, so it keeps ticking even if music tempo is near zero) sending `/pp/heartbeat` |
| Python Model | Holds `bpm`, `epic`, `playing`, `volume` as the GUI's own source of truth; notifies the View on change | Plain Python class/dataclass with simple observer callbacks, or just instance attributes mutated by the Controller |
| Python OSC Client | Fire-and-forget sender of control messages to SC | `pythonosc.udp_client.SimpleUDPClient` wrapped in a thin `OscClient` class |
| Python OSC Server | Receives async replies (`/pp/status`, `/pp/heartbeat`) from SC without blocking the GUI | `pythonosc.osc_server.ThreadingOSCUDPServer` run inside a dedicated `threading.Thread(daemon=True)` |
| Python Tk View | Renders sliders/buttons, reads/writes the Model, never touches OSC directly | Tkinter widgets + `tkinter.Variable`s bound to Model fields |
| Thread-safe bridge | Moves data from the OSC server thread to the Tk main thread safely | `queue.Queue()` filled by the server thread; drained on the main thread via `root.after(50, poll_queue)` |

## Recommended Project Structure

```
supercollider/
├── main.scd                # Boots server, sets options, loads everything else, starts engine
├── core/
│   ├── conductor.scd        # ~bpm, ~epic, ~playing, ~volume vars + TempoClock + helper setters
│   ├── groups_buses.scd     # Group hierarchy (instruments/fx/master) + shared audio/control buses
│   └── tempo_ramp.scd       # Routine/Tdef implementing smooth tempo glide
├── synths/
│   ├── drums.scd            # SynthDefs: kick, hat, clap, perc
│   ├── bass.scd             # SynthDef: bass voice
│   ├── arp.scd              # SynthDef: arp/pluck voice
│   ├── pad.scd               # SynthDef: pad voice
│   └── fx.scd                # SynthDefs: filter/drive, delay, reverb, master limiter
├── harmony/
│   └── harmony_clock.scd    # Routine advancing chord/scale, writes Pdefn(\root)/Pdefn(\scale)
├── patterns/
│   ├── drums_pattern.scd    # Pbindef(\drums, ...)
│   ├── bass_pattern.scd     # Pbindef(\bass, ...) — reads Pdefn(\root), Pdefn(\epic)
│   ├── arp_pattern.scd       # Pbindef(\arp, ...)  — reads Pdefn(\root), Pdefn(\epic)
│   └── pad_pattern.scd       # Pbindef(\pad, ...)  — reads Pdefn(\root), Pdefn(\epic)
└── osc/
    └── osc_handlers.scd     # OSCdef(\pp_bpm, ...), OSCdef(\pp_epic, ...), heartbeat Routine

python/
├── main.py                  # Entry point: builds Model, OscClient, OscServer, View; starts mainloop
├── model.py                 # AppState dataclass: bpm, epic, playing, volume + change callbacks
├── osc_client.py            # OscClient: thin wrapper over SimpleUDPClient, one method per /pp/* address
├── osc_server.py            # OscServer: ThreadingOSCUDPServer + dispatcher + Queue, run in daemon thread
├── view.py                  # Tk widgets: BPM slider+entry, EPIC presets+slider, play/stop, volume
└── app.py                   # Controller glue: wires View callbacks → OscClient, polls Queue via after()
```

### Structure Rationale

- **`core/` before `synths/`/`patterns/`:** the conductor and bus/group topology must exist before anything else is defined against them — load order in `main.scd` encodes the real dependency graph.
- **`synths/` separate from `patterns/`:** SynthDefs are server-side and expensive to redefine; patterns are client-side and cheap to hot-swap during live coding. Keeping them in separate files means you can re-run a `Pbindef` file without re-sending SynthDefs.
- **`harmony/` as its own concern:** the chord/scale progression is logically independent of any one instrument — it must be loaded before the instrument patterns that consume it, and isolating it makes "does the bass/arp/pad agree harmonically" a one-file question.
- **`osc/` loaded last:** OSCdefs should only ever write to already-existing conductor state and already-running patterns; loading it last avoids referencing not-yet-defined `Pdefn`s/synths.
- **Python mirrors the classic Model/View/Controller-with-a-wire split:** `model.py` has zero knowledge of OSC or Tk; `osc_client.py`/`osc_server.py` have zero knowledge of Tk; `view.py` has zero knowledge of OSC. `app.py` is the only file that imports all of them — this is what keeps the OSC server thread from ever touching a Tk widget directly.

## Architectural Patterns

### Pattern 1: Conductor as single mutable source of truth

**What:** All externally-controllable state (`bpm`, `epic`, `playing`, `volume`) lives in one place (a small set of top-level `Environment` vars or a single `Event`). OSCdefs are the *only* writers. Everything else (patterns, ramps, FX) only reads.

**When to use:** Always, for any value the GUI can change. Avoids the classic bug where a pattern "remembers" an old EPIC value because it captured it at `.play` time instead of reading it live.

**Trade-offs:** Global mutable state is normally a code smell, but in a single-process live-coding engine with one controller, it is the simplest correct answer — the alternative (passing state through message queues between Patterns) adds complexity with no real benefit at this scale.

**Example:**
```supercollider
// core/conductor.scd
~bpm = 128;
~epic = 50;       // 0-100
~playing = true;
~volume = 0.8;
~clock = TempoClock.new(~bpm/60).permanent_(true);
```

### Pattern 2: Dual fan-out for EPIC — control bus for timbre, Pdefn for pattern decisions

**What:** EPIC 0-100 has two different kinds of consumers: (a) continuous audio/control-rate synth parameters (filter cutoff, drive, reverb/delay mix) that should respond *instantly and smoothly*, and (b) pattern-rate decisions (note density, fill probability, which scale degree pool to draw from) that only need to be read once per event. Route (a) through a `Bus.control`, route (b) through a `Pdefn` that reads the conductor.

**When to use:** Whenever one logical "knob" needs to affect both sound-shaping and compositional decisions.

**Trade-offs:** Two mechanisms for one concept adds a small amount of indirection, but conflating them (e.g. trying to make a `Pdefn` drive a continuously-modulated filter) produces audible stepping because patterns only update at event boundaries, not continuously — mapping to a bus is strictly smoother for audio-rate parameters.

**Example:**
```supercollider
// core/groups_buses.scd
~epicBus = Bus.control(s, 1).set(~epic.linlin(0, 100, 0, 1));

// osc/osc_handlers.scd
OSCdef(\pp_epic, { |msg|
    ~epic = msg[1].clip(0, 100);
    ~epicBus.set(~epic.linlin(0, 100, 0, 1));
}, '/pp/epic');

// patterns/bass_pattern.scd (pattern-rate consumer)
Pdefn(\epic, Pfunc({ ~epic }));
Pbindef(\bass,
    \instrument, \bass,
    \degree, Pdefn(\root) + Prand([0,2,4], inf),
    \dur, Pfunc({ (Pdefn(\epic).value > 70).if({ 0.25 }, { 0.5 }) })
);

// synths/fx.scd (audio-rate consumer)
SynthDef(\filterFx, { |in=0, out=0, epicCtl=0|
    var sig = In.ar(in, 2);
    var cutoff = epicCtl.linexp(0, 1, 400, 8000); // reads ~epicBus via .map
    Out.ar(out, RLPF.ar(sig, cutoff, 0.3));
}).add;
// when instantiating: Synth(\filterFx, [...]).map(\epicCtl, ~epicBus);
```

### Pattern 3: Beat-synchronous tempo ramp (not audio-rate interpolation)

**What:** `TempoClock` has no built-in glide; changing `.tempo_` instantly causes every running pattern to snap to the new speed mid-phrase, which is audible as a jolt. The standard fix is a `Routine`/`Tdef` that nudges `clock.tempo_` by a small increment once per beat (or every N beats) until it reaches the target, scheduled *on the music clock itself* so the ramp duration is musically relative (e.g. "finish within 4 bars") rather than wall-clock relative.

**When to use:** Any time BPM changes while music is playing — i.e. always in this project, since the rider changes BPM mid-ride.

**Trade-offs:** Linear per-beat stepping is simple, predictable, and easy to reason about ("done in exactly N beats"). An exponential/asymptotic approach (`new = current + (target - current) * factor` each beat) feels more "eased" but can leave a long, barely-perceptible tail that never quite reaches the target — needs an explicit snap-to-target threshold. **Recommendation: linear step-per-beat over a fixed number of beats** (e.g. one bar = 4 beats, or configurable), because it's deterministic and simplest to debug when something sounds wrong.

**Example:**
```supercollider
// core/tempo_ramp.scd
~tempoRampRoutine = nil;

~rampTempoTo = { |targetBpm, beats = 8|
    ~tempoRampRoutine.stop;
    ~tempoRampRoutine = Routine({
        var startTempo = ~clock.tempo;
        var targetTempo = targetBpm / 60;
        var step = (targetTempo - startTempo) / beats;
        beats.do({ |i|
            ~clock.tempo_(startTempo + (step * (i+1)));
            1.wait; // one beat on ~clock
        });
        ~clock.tempo_(targetTempo); // guarantee exact landing
    }).play(~clock);
};

// osc/osc_handlers.scd
OSCdef(\pp_bpm, { |msg| ~bpm = msg[1]; ~rampTempoTo.(~bpm, 8); }, '/pp/bpm');
```

### Pattern 4: Harmony clock as the single writer of chord/root state

**What:** A dedicated `Routine` (the "harmony clock") advances a chord progression index on a bar/phrase boundary and writes the resulting root/scale into shared `Pdefn`s. Every instrument's `Pbindef` reads those `Pdefn`s instead of independently choosing a root — this is what keeps bass, arp, and pad harmonically locked without explicit inter-pattern messaging.

**When to use:** Whenever more than one pattern needs to agree on "what key/chord are we in right now."

**Trade-offs:** Centralizing harmony makes each instrument pattern simpler (just "follow the shared root"), at the cost of needing the harmony clock to be loaded and started before instrument patterns reference it (ordering dependency, mitigated by file load order above).

**Example:**
```supercollider
// harmony/harmony_clock.scd
~chordDegrees = [0, 5, 3, 4]; // e.g. i - v - iv progression in scale degrees
~chordIndex = 0;
Pdefn(\root, Pfunc({ ~chordDegrees[~chordIndex] }));
Pdefn(\scale, Pfunc({ Scale.minor }));

~harmonyRoutine = Routine({
    loop({
        4.wait; // advance every bar (assuming 4/4, one event per beat elsewhere)
        ~chordIndex = (~chordIndex + 1) % ~chordDegrees.size;
    });
}).play(~clock, quant: 4); // quantize start to bar boundary

// patterns/pad_pattern.scd
Pbindef(\pad, \instrument, \pad, \degree, Pdefn(\root), \scale, Pdefn(\scale), \dur, 4);
```

## Data Flow

### Control Flow (GUI → sound)

```
User drags BPM slider (Tk, main thread)
    ↓
View updates tkinter.DoubleVar → Controller callback fires
    ↓
Model.bpm updated (in-process, no I/O)
    ↓
OscClient.send_bpm(value) → SimpleUDPClient.send_message("/pp/bpm", value)
    ↓ UDP, localhost
OSCdef(\pp_bpm) fires in sclang
    ↓
~bpm updated (conductor) → ~rampTempoTo.(~bpm, 8) scheduled on ~clock
    ↓
Routine steps ~clock.tempo_ once per beat for 8 beats
    ↓
All Pbindefs scheduled on ~clock audibly speed/slow up smoothly
```

### Status Flow (sound → GUI)

```
SystemClock Routine in sclang fires every ~1s (independent of music tempo)
    ↓
NetAddr("127.0.0.1", pythonPort).sendMsg('/pp/heartbeat', ~bpm, ~epic, ~playing.binaryValue)
    ↓ UDP
ThreadingOSCUDPServer (Python, daemon thread) receives message, dispatcher invokes handler
    ↓
Handler pushes (address, args) onto queue.Queue() — no Tk calls here, this is a background thread
    ↓
Tk main thread's root.after(50, poll_queue) wakes up, drains queue
    ↓
Controller updates Model from the received values, Model notifies View
    ↓
View widgets refreshed on the main thread only — Tkinter is never touched off-thread
```

### Key Data Flows

1. **One-way control (Python → SC):** GUI action → Model → OscClient → UDP → OSCdef → Conductor write → propagates to control bus (instant) and/or Pdefn (next pattern tick). This is the only flow required for the project's core value proposition and should be built and proven first.
2. **Harmony propagation (SC-internal):** Harmony clock → `Pdefn(\root)`/`Pdefn(\scale)` → every instrument `Pbindef` reads the same `Pdefn` at its own next event — no instrument-to-instrument messaging, only shared-source reads.
3. **Status feedback (SC → Python):** Conductor state → periodic `SystemClock` Routine → UDP → OSC server thread → `Queue` → `after()` poll → Model → View. This is optional for core value but important for GUI correctness after reconnect or if SC-side state diverges from GUI-side assumptions (e.g. SC restarted independently).

## Scaling Considerations

This is a single-user, single-machine, localhost application — "scaling" here means headroom for more instruments/features, not more users.

| Scale | Architecture Adjustments |
|-------|--------------------------|
| v1 (drums+bass+arp+pad, manual BPM/EPIC) | Flat file structure above is sufficient; no need for classes or OOP abstractions in sclang |
| Add cadence-sensor-driven auto BPM | Conductor already decouples "what sets bpm" from "what consumes bpm" — add a new OSC-independent writer (sensor listener) without touching patterns |
| Add more instrument layers / density-driven EPIC enrichment | Dual fan-out pattern (Pattern 2) already generalizes — add new `Pdefn`s/buses rather than new mechanisms |
| Multiple simultaneous "scenes" (warm-up/push/cool-down presets) | Conductor gains a `~scene` var; scenes become named bundles of target `epic`/density/FX settings applied via the same ramp machinery |

### Scaling Priorities

1. **First real risk:** CPU load from reverb/delay FX + many concurrent synths on the same Mac running Zwift — mitigate by keeping FX synths few and shared (one reverb bus serving all instruments via sends, not one reverb per instrument).
2. **Second real risk:** OSC message flooding from a slider being dragged continuously (Tk fires many events per second) — mitigate by throttling the GUI's OSC send rate (e.g. only send on `after(50ms)` coalescing, or on mouse-release) rather than on every pixel of slider movement.

## Anti-Patterns

### Anti-Pattern 1: Re-triggering/redefining Pbindefs or Synths on every OSC message

**What people do:** Treat an incoming `/pp/epic` message as "stop the pattern, rebuild it with new parameters, play it again."
**Why it's wrong:** Causes audible retriggering/glitching of running voices and can lose sync with the shared clock/harmony state.
**Do this instead:** OSCdef should only *write conductor state* (vars/buses). Already-running `Pbindef`s and `Synth`s should be written to continuously read that state (via `Pdefn`/`Pfunc`/control-bus `.map`) so they update in place on their own next cycle.

### Anti-Pattern 2: Instant tempo snap

**What people do:** `OSCdef(\bpm, { |msg| TempoClock.default.tempo = msg[1]/60; })`.
**Why it's wrong:** Every pattern scheduled on that clock jumps speed mid-beat — audible as a jolt, explicitly called out as unwanted in the project's requirements.
**Do this instead:** Route every tempo change through the beat-synchronous ramp routine (Pattern 3), never set `.tempo_` directly from an OSCdef.

### Anti-Pattern 3: Each instrument pattern independently deciding harmony

**What people do:** Give the bass its own `Prand` over possible roots, and the pad a separate one, assuming "it'll usually sound fine."
**Why it's wrong:** Produces audible clashes/dissonance once the two independent random choices diverge, and is undebuggable (no single place holds "the current key").
**Do this instead:** One harmony clock, one set of shared `Pdefn`s, every instrument pattern reads the same source (Pattern 4).

### Anti-Pattern 4: Blocking the Tk main thread with OSC I/O

**What people do:** Run `BlockingOSCUDPServer.serve_forever()` on the main thread, or call `time.sleep()`/synchronous socket reads inside a button callback.
**Why it's wrong:** Freezes the entire GUI (no redraw, no input) for the duration of the block — Tkinter has a single-threaded event loop and is not safe to drive from multiple threads directly.
**Do this instead:** Run `ThreadingOSCUDPServer` in a `daemon=True` background thread; only ever touch Tk widgets from the main thread, bridging via `queue.Queue` drained by `root.after(ms, poll)`.

### Anti-Pattern 5: Polling or updating Tk widgets directly from the OSC server thread

**What people do:** Call `label.config(text=...)` directly inside the OSC dispatcher handler because "it's just one line."
**Why it's wrong:** Tkinter is explicitly not thread-safe; this works "most of the time" in testing and then corrupts widget state or crashes intermittently in real use — a classic heisenbug.
**Do this instead:** Handler only enqueues data; `after()`-scheduled poll function (running on the main thread) is the only code that touches widgets.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| SuperCollider server (scsynth) | Local, started independently by `sclang` boot code in `main.scd`; not managed by Python | Per project constraints, Python never launches/manages sclang — it only sends/receives OSC to an already-running instance |
| Zwift | None in v1 (explicitly out of scope) | Keep the engine CPU-light so it doesn't compete with Zwift's rendering; this is a reason to prefer shared FX buses over per-voice effects (see Scaling Priorities) |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Python Model ↔ Python View | Direct in-process calls / `tkinter.Variable` bindings | Keep the Model OSC-agnostic — it shouldn't know `pythonosc` exists |
| Python Controller ↔ OscClient | Direct method calls (`client.send_bpm(128)`) | One method per `/pp/*` address keeps the OSC schema in one file |
| OSC server thread ↔ Tk main thread | `queue.Queue` + `root.after()` polling | The only sanctioned cross-thread communication in the Python app |
| sclang OSCdefs ↔ Conductor vars | Direct var assignment | OSCdefs are intentionally "dumb" — all they do is validate + write |
| Conductor ↔ Patterns/Synths | `Pdefn`/`Pfunc` reads (pattern-rate) and `Bus.control` reads (audio-rate) | Never the reverse — patterns/synths must not write conductor state |
| Harmony clock ↔ Instrument patterns | Shared `Pdefn(\root)`/`Pdefn(\scale)` reads | Harmony clock is the only writer |

## Suggested Build Order

This order is driven by hard dependencies (you cannot test layer N+1 without layer N working) and by "prove the riskiest/most valuable thing first":

1. **SynthDefs + hardcoded patterns in SC, no OSC, no Python.** Write drum/bass/arp/pad SynthDefs, play them with literal `Pbind`s on a fixed `TempoClock`. Goal: it sounds like continuous generative melodic techno. This validates the hardest, most subjective requirement first.
2. **Groups/bus topology + FX chain.** Introduce instrument Group → FX Group → Master Group ordering, route instruments through a shared reverb/delay bus, add a master volume stage. Still no OSC — test by editing literals in sclang directly.
3. **Harmony clock + shared Pdefn(\root)/\scale.** Replace independent per-instrument note choices with the shared harmony source (Pattern 4). Validates "generative, not a static loop" and "bass/arp/pad agree" before any external control exists.
4. **Conductor vars + manual-trigger OSCdefs, tested from sclang itself.** Add `~bpm`/`~epic`/conductor, OSCdefs for `/pp/bpm`/`/pp/epic`/`/pp/play`/`/pp/volume`, and prove them by sending test OSC messages from sclang's own `NetAddr` (no Python yet). This isolates OSC-layer bugs from Python-layer bugs.
5. **EPIC dual fan-out (control bus + Pdefn).** Wire `~epicBus` into FX SynthDef params and `Pdefn(\epic)` into pattern-rate decisions (Pattern 2). Test by sending `/pp/epic` values from sclang and listening for both timbral and compositional changes.
6. **Beat-synchronous tempo ramp.** Add the ramp routine (Pattern 3), replacing any direct `.tempo_` sets from step 4. Test by sending a sequence of `/pp/bpm` values and confirming no audible jolt.
7. **Python app skeleton: Model + OscClient + minimal Tk view (send-only).** Build `model.py`, `osc_client.py`, a bare-bones `view.py` with sliders, and `app.py` wiring them. This is the first point where the full Python → OSC → SC chain exists end to end — the project's stated core value. Defer the OSC server entirely.
8. **Full Tk view: BPM slider+entry, EPIC presets+slider, play/stop, volume.** Flesh out the GUI per requirements; still send-only.
9. **Python OSC server + heartbeat/status round-trip.** Add `osc_server.py` (`ThreadingOSCUDPServer` in a daemon thread), the `Queue`, and `root.after()` polling; add the `SystemClock` heartbeat Routine on the SC side. This is additive and lower-risk — build it after the one-way path is proven solid.
10. **Polish pass.** Throttle slider-drag OSC send rate, handle SC-not-running / connection-lost gracefully in the GUI (using heartbeat timeout), tune ramp durations and chord progression musically.

**Why this order:** Steps 1-3 de-risk the single hardest requirement (does the generative music actually sound good and non-repetitive) before any plumbing is built. Steps 4-6 build and prove the SC-internal control surface in isolation (easier to debug without a second process involved). Steps 7-8 deliver the stated "core value" checkpoint as early as possible once the SC side is ready. Steps 9-10 add robustness/feedback that improves the experience but isn't required for the core value proposition to be demonstrated.

## Sources

- [TempoClock — SuperCollider Help](https://help.sccode.org/Scheduling/TempoClock.html) — MEDIUM confidence (official doc, cross-checked)
- [Smooth alteration of Tempo — scsynth forum](https://scsynth.org/t/smooth-alteration-of-tempo/6857) — MEDIUM confidence (community, cross-checked against official docs' lack of built-in ramp)
- [Routines & Tasks — Algorithmic Composition](https://bzoennchen.github.io/supercollider-book/chapters/supercollider/scheduling/3-routines-tasks.html) — MEDIUM confidence
- [Ndef — SuperCollider Help](https://doc.sccode.org/Classes/Ndef.html) and [Ndef to control bus? — scsynth forum](https://scsynth.org/t/ndef-to-control-bus/2934) — MEDIUM confidence
- [Pdef — SuperCollider Help (dxscdoc mirror)](https://depts.washington.edu/dxscdoc/Help/Classes/Pdef.html) — MEDIUM confidence
- [HarmonicToolkitSC](https://github.com/madskjeldgaard/HarmonicToolkitSC) — MEDIUM confidence (community quark, illustrates shared-harmony idioms)
- [python-osc Server documentation](https://python-osc.readthedocs.io/en/latest/server.html) — HIGH confidence (official library docs)
- [python-osc examples/simple_server.py](https://github.com/attwad/python-osc/blob/main/examples/simple_server.py) and [docs/server.rst](https://github.com/attwad/python-osc/blob/main/docs/server.rst) — HIGH confidence (official repo)
- [Tkinter is not thread safe — Python bug tracker issue 11077](https://bugs.python.org/issue11077) — HIGH confidence (CPython project)
- Domain synthesis (conductor pattern, dual EPIC fan-out, harmony-clock sharing, file/project layout, build order): MEDIUM confidence — composed from the above idioms plus established SuperCollider JITLib/Patterns conventions; not independently published as a single named "architecture," so treat as an opinionated recommendation to validate hands-on in phase 1-3 above.

---
*Architecture research for: SuperCollider generative music engine + Python/Tkinter OSC controller*
*Researched: 2026-10-08*
