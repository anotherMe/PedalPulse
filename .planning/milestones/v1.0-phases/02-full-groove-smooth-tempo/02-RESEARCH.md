# Phase 2: Full Groove & Smooth Tempo - Research

**Researched:** 2026-10-09
**Domain:** SuperCollider TempoClock tempo-ramping (beat-synchronous glide + mid-glide retarget), JITLib Pdef/Pbindef groove layering (drums/bass/arp/pad), clean transport stop/start (no hanging notes), and the matching Python OSC transport control
**Confidence:** HIGH for the TempoClock/JITLib mechanics (grounded in official class docs + this session's reading of the actual Phase 1 code); MEDIUM for musical/arrangement choices (inherently a matter of taste, explicitly left to discretion); LOW/ASSUMED for one specific interaction (`Group:set` broadcast to child synths lacking a matching control) that could not be empirically verified in this session — see Assumptions Log.

<user_constraints>
## User Constraints (from CONTEXT.md)

**No CONTEXT.md exists for Phase 2.** The user chose "Continue without context" at the plan-phase gate (per the orchestrator's instructions). There are no locked Phase 2 decisions to copy here.

In its place, this research surfaces every gray area the planner would otherwise have to guess at — see **## Gray Areas Needing a Default** below — each with a concrete recommended default, a rationale, and a reversibility note. Treat that section as the substitute for a `## Decisions` block: the planner should either accept the defaults as working decisions or escalate them back to the user, not invent its own without reading them.

### Still-binding decisions from Phase 1 (`01-CONTEXT.md`, verified by reading this session)

These remain in force for Phase 2 because nothing in the Phase 2 goal supersedes them:

- OSC namespace is `/pp/*`; Phase 1 D-19 (quoted verbatim, `01-RESEARCH.md:45`): "Addresses are namespaced. Phase 1 uses `/pp/bpm <float>`. Later phases follow the same scheme (`/pp/epic`, `/pp/play`, `/pp/volume`)." — Phase 2's transport address is therefore `/pp/play`, not `/pp/transport` or anything else. **Reversibility: costly** (same as D-19 — it's the contract between `main.scd` and the Python client).
- `/pp/bpm` sends to sclang's language port 57120, loopback-only via `srcID: NetAddr("127.0.0.1", nil)` — reuse exactly, including for the new `/pp/play` OSCdef.
- Every enveloped SynthDef uses `doneAction: 2` (CLAUDE.md + Phase 1 CONTEXT, non-negotiable, applies to every new SynthDef this phase adds: arp, pad).
- The engine clamps BPM to 60–180 independently of the GUI (TEMPO-03, already implemented in `main.scd`); Phase 2 does not touch this clamp, only what happens *after* clamping (glide instead of instant-at-next-beat).
- Python side stays send-only (D-24) — no OSC receive path yet; that's Phase 4 (LINK-02/03).
- `.venv` + `run.sh` launch, `python3.13`/Tk 9.0.3 pairing — unchanged, no new Python dependency this phase.

### Claude's Discretion (carried forward, same spirit as Phase 1)

- Exact arp/pad SynthDef design (timbre, envelope shape, voicing) — within "melodic techno / progressive trance" and the `doneAction: 2` rule.
- Exact ramp step granularity and curve shape — flagged explicitly below as a gray area with a recommended default, not a locked decision, because STATE.md already flags it as needing a listening-test spike.
- Internal file split inside `supercollider/main.scd` (single file vs. split) — Phase 1 kept one file; Phase 2 can keep doing so or split if it gets unwieldy.

### Deferred Ideas (OUT OF SCOPE for Phase 2)

Per REQUIREMENTS.md v2 scope and PROJECT.md "Out of Scope": generative/evolving harmony (GEN-01/02/03, shared harmony clock, multi-timescale variation), EPIC-driven density/arrangement, user-configurable ramp time (CTRL-02), multiple styles (STYL-01). Phase 2's groove is a **fixed loop** — same spirit as Phase 1's fixed kick/hat/bass loop, now extended to 5 layers (kick/hat/clap or snare/bass/arp/pad).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ENG-01 | Engine plays drums, bass, arpeggio and pad continuously in melodic techno/progressive trance style, all on one TempoClock (fixed loop OK) | Pattern 2 (groove layering — all `Pbindef`s play on the single shared `~clock`, which is what keeps every layer phase-locked automatically) |
| TEMPO-01 | New BPM glides over ~1–2 bars, beat-synchronous, no audible jolt | Pattern 1 (single persistent ramp-stepper Routine + mutable target/rate, engaged via `schedAbs(nextTimeOnGrid(1))`) |
| TEMPO-02 | Mid-glide BPM change retargets smoothly from current tempo, no restart/jump | Pattern 1 — the stepper always reads the *current* instantaneous tempo and recomputes rate toward whatever target is currently set; no cancel/replace needed |
| GUI-02 | Start/Stop from the GUI | Pattern 3 (engine-side idempotent `/pp/play` OSCdef + `Group`-wide gate-release) + Pattern 4 (Python `PlayController` mirroring the existing `BpmController`) |
</phase_requirements>

## Summary

Phase 2 extends the Phase 1 skeleton (one `main.scd`, one `BpmController`-driven Tkinter window) in three ways: (1) the fixed kick/hat/bass loop grows to a full 5-layer groove (kick, hat, clap/snare, bass, arpeggio, pad — "drums, bass, arpeggio, pad" per ENG-01, where "drums" is itself kick+hat+clap), all playing on the **one** `~clock` that already exists, which is what automatically keeps every layer phase-locked through a tempo change — no per-layer bookkeeping needed; (2) the existing "snap instantly at the next beat" BPM apply (Phase 1's `schedAbs`/`nextTimeOnGrid` one-shot) is replaced with a **continuously-running ramp-stepper Routine** that nudges `~clock.tempo` toward a mutable target at a fixed BPM-per-beat rate, recomputed from the clock's *current* tempo every time a new target arrives — this single mechanism satisfies both "glide over 1–2 bars, beat-synchronous" (TEMPO-01) and "retarget mid-glide without jump/restart" (TEMPO-02) with no cancel-and-replace logic; (3) Start/Stop becomes a new `/pp/play <int>` OSCdef (following Phase 1's own documented naming convention) that toggles all five `Pbindef`s and, critically, **broadcasts `\gate, 0` to the instrument `Group`** so any note that happens to be mid-sustain (a held pad chord) is cut off with its own release envelope instead of left hanging or popped.

The riskiest mechanic — tempo-ramping a clock from inside a Routine that is itself scheduled on that same clock — is a documented, if sparsely-covered, SuperCollider idiom (confirmed via the scsynth.org community thread and the official `TempoClock` docs for `sched`/`schedAbs`/`tempo_`/`nextTimeOnGrid`). The second-riskiest mechanic — releasing a sustained pad note on Stop without tracking individual Synth objects — relies on `Group:set` broadcasting to all child Nodes (confirmed via official `Node.html` docs: "If this Node is a Group this will set all Nodes within the Group"), combined with the well-documented Pbind/Event gate-release contract (confirmed via `doc.sccode.org`'s Pattern Guide). The one piece of this design **not** independently verified this session is whether a synth *without* a matching control name silently ignores an out-of-scope `/n_set`, or errors — official docs do not say either way, and an attempt to verify it empirically with a short headless sclang script did not complete in this session (see Assumptions Log A3). This is a low-risk assumption (it is extremely well-established, commonly-relied-upon SuperCollider behavior) but the planner should add a one-line Wave 0 smoke-test check for it rather than take it fully on faith.

**Primary recommendation:** Build the ramp as one long-lived `Routine` started once at boot (alongside the clock), driven by two mutable vars (`~ppRampTargetBpm`, `~ppRampRateBpm`) that the `/pp/bpm` OSCdef updates on every message (recomputing the rate from the clock's *live* tempo each time, so a mid-ramp retarget is just "update the target/rate," never "stop and restart a Routine"). Build Start/Stop as a single idempotent `/pp/play` OSCdef that calls `.play(~clock, quant: 4)` / `.stop` on all five `Pbindef`s and additionally does `~ppInstrGroup.set(\gate, 0)` on Stop to guarantee no hanging sustain regardless of what any individual layer's envelope is doing. Extend `python_app/bpm_logic.py`'s existing `BpmController`/`Debouncer` pattern with a small `PlayController` (no debounce needed — Start/Stop is a discrete click, not a drag) that mirrors `send_initial()`'s "GUI is the source of truth" philosophy.

## Architectural Responsibility Map

Same two-process architecture as Phase 1 (desktop app, no Browser/CDN/Database tier) — Phase 2 adds no new tier, only new capabilities within the existing two.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Full groove layering (ENG-01: kick/hat/clap/bass/arp/pad) | Engine (`main.scd`, `~clock` + `Pbindef`s) | — | Pure audio synthesis/sequencing; nothing in Python needs to know the arrangement |
| Beat-synchronous tempo glide (TEMPO-01) | Engine (`TempoClock` + ramp-stepper Routine) | — | The glide is a clock-internal mechanic; Python only ever sends the target BPM, same as Phase 1 |
| Mid-glide retarget (TEMPO-02) | Engine (mutable `~ppRampTargetBpm`/`~ppRampRateBpm` read by the stepper) | — | Retargeting is "update a variable the running Routine already reads," entirely engine-side |
| Start/Stop command (GUI-02) | Client (Python sends `/pp/play`) | Engine (idempotent `OSCdef` + `Group`-wide gate release) | Same split as BPM: client is the source of truth for *intent*, engine is the source of truth for *safe execution* (idempotency, clean release) |
| Clean note release on Stop (no hanging notes) | Engine (`Group.set(\gate, 0)` + per-note Pbind auto-release) | — | Audio-domain cleanup; Python has no visibility into which synths are currently sounding |

## Standard Stack

No new libraries or runtime dependencies this phase. Phase 1's stack (`.planning/phases/01-tempo-link-skeleton/01-RESEARCH.md` Standard Stack section, verified 2026-10-08 against the actual installed toolchain) is reused unchanged:

| Library | Version | Still Current? |
|---------|---------|-----------------|
| SuperCollider | 3.14.1 | Yes — same installation, `TempoClock`/`Pdef`/`Pbindef`/`Group`/`Node` APIs used here are all stable, long-standing classes, no version-specific concern |
| Python | 3.13.12 (Homebrew) | Yes — unchanged venv |
| python-osc | 1.10.2 | Yes — `send_message` is all Phase 2's new `/pp/play` send needs; no new OSC library feature required |
| Tkinter | stdlib, Tk 9.0.3 | Yes — Phase 2 adds one or two `Button`/toggle widgets, no new Tk feature |

### Alternatives Considered

No new alternatives beyond what Phase 1's research already covered. One Phase-2-specific question is whether to use `Pdef` or `Pbindef` for the new arp/pad layers — **use `Pbindef`**, matching the three layers already built in Phase 1's `main.scd` (`\ppKick`, `\ppHat`, `\ppBass`), for consistency. `Pdef` and `Pbindef` share the same `TaskProxy`/`EventPatternProxy` superclass chain and `.play`/`.stop`/`.quant` semantics `[CITED: doc.sccode.org/Classes/Pbindef.html, doc.sccode.org/Classes/Pdef.html]` — `Pbindef` additionally lets individual pattern keys be hot-swapped without rebuilding the whole event stream, which is the property Phase 1 already relies on for its re-evaluation workflow (D-17's "edit a var, re-evaluate" loop).

**Installation:** None — no new packages.

## Package Legitimacy Audit

**Not applicable this phase.** No new external packages (Python or SuperCollider quark) are introduced. `CLAUDE.md`'s "No quarks" constraint and Phase 1's `python-osc` pin are reused unchanged; see `01-RESEARCH.md`'s Package Legitimacy Audit for that prior verification.

## Architecture Patterns

### System Architecture Diagram

```
┌──────────────────────────── Python process (unchanged shape, new PlayController) ─────────────────────┐
│                                                                                                             │
│   BpmWindow (existing)              NEW: Start/Stop control (button or toggle)                           │
│     slider/entry/nudge → BpmController   → click → PlayController.toggle()                                │
│                                                       │ (no debounce — discrete click, not a drag)        │
│                                                       ▼                                                    │
│                                            SimpleUDPClient.send_message("/pp/play", 1 or 0)                │
└──────────────────────────────────────────┬────────────────────────────────────────────────────────────────┘
                                             │ UDP, localhost:57120 (same port/contract as /pp/bpm)
┌────────────────────────────────────────── ▼ ──────────────────────────────────────────────────────────────┐
│                         SuperCollider process — main.scd, inside s.waitForBoot (unchanged gate)             │
│                                                                                                               │
│   ~clock (ONE TempoClock, unchanged identity) ◄──────────────┐                                              │
│     │                                                          │ .tempo= every ~ppRampStepBeats             │
│     │  ┌─────────────────────────────────────────┐             │                                            │
│     ├─▶│ Pbindef(\ppKick) │ \ppHat │ \ppClap       │─┐          │   ~ppRampStepper (Routine, started once    │
│     ├─▶│ \ppBass │ \ppArp (NEW) │ \ppPad (NEW)      │ │          │   at boot, lives forever, loops forever)   │
│     │  └─────────────────────────────────────────┘ │          │     reads ~ppRampTargetBpm / ~ppRampRateBpm │
│     │   all .play(~clock, quant: 4) — ONE clock =    │          │     nudges ~clock.tempo toward target      │
│     │   automatic phase-lock across every layer      │          │     every ~ppRampStepBeats beats ──────────┘
│     │                                                │
│     ▼                                                │
│  OSCdef(\pp_bpm) ── clamp 60–180 (unchanged) ── schedAbs(nextTimeOnGrid(1)) ── sets ~ppRampTargetBpm/Rate   │
│                                                        (computed from clock's CURRENT tempo — TEMPO-02)     │
│                                                                                                               │
│  OSCdef(\pp_play) ── NEW ── idempotent: want != ~ppPlaying? ─┬─ true  → .play all 5 Pbindefs, quant: 4       │
│                                                                └─ false → .stop all 5 Pbindefs               │
│                                                                           + ~ppInstrGroup.set(\gate, 0)      │
│                                                                             (release any mid-sustain note)   │
│                                                                                                               │
│  Master bus: unchanged Limiter.ar(mix, 0.891251, 0.01) ── Out.ar(0, limited)                                │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Pattern 1: Beat-synchronous tempo glide with mid-glide retarget (TEMPO-01, TEMPO-02)

**What:** Replace Phase 1's one-shot "snap at next beat" apply with a continuously-running ramp-stepper `Routine`, started once at boot, that always steers `~clock.tempo` toward a mutable target at a rate recomputed from the clock's *live* tempo. This means a mid-glide retarget is never "cancel and restart a Routine" — it's "update two variables"; the already-running stepper picks up the new target on its very next step, continuing from whatever the instantaneous tempo happens to be.

**Why this design, not cancel-and-replace:** A cancel-and-replace approach (stop the old ramp Routine, compute a new one from scratch) works but introduces an ordering hazard — if the cancel and the restart aren't atomic relative to the clock's own scheduling, there's a window where either two ramp routines are briefly alive (double-stepping the tempo) or zero are (a stall). The single-persistent-stepper design sidesteps this category of bug entirely, and is a direct extension of the "latest wins" idiom Phase 1's `/pp/bpm` OSCdef **already uses** for its own one-shot apply — read `supercollider/main.scd:111-131` this session: `~ppPendingBpm` is a mutable var the handler always overwrites with the latest value, and a single `~ppApplyScheduled` flag ensures only one callback is ever pending `[VERIFIED: supercollider/main.scd:111-131, this session]`. Pattern 1 generalizes that exact idiom from "one pending value, one scheduled one-shot" to "one pending target+rate, one persistent stepper."

**Grounding for the underlying mechanics** `[CITED: doc.sccode.org/Classes/TempoClock.html]`:
- `tempo_`: "Sets or gets the current tempo in beats per second at the current logical time."
- `schedAbs(beat, item)`: "Schedules a task to be performed at a particular time in beats."
- `sched(delta, item)`: "Schedules a task to be performed delta amount of beats after the current Thread's logical time."
- `nextTimeOnGrid(quant: 1, phase: 0, referenceBeat)`: "With default values, returns the next whole beat."
- A `Routine` that `.wait()`s inside is scheduled relative to the clock it plays on, and when that clock's tempo changes mid-routine, the *real* (wall-clock) duration of its subsequent waits changes accordingly — this is exactly the self-referential mechanic this phase needs (the ramp naturally speeds up/slows down in wall-clock terms as its own tempo changes), confirmed by the community pattern at `[CITED: scsynth.org/t/smooth-alteration-of-tempo/6857]`, which demonstrates the same idiom: `Task { (1,1.01..2).do { |t| TempoClock.default.tempo = t; 0.1.wait } }.play` — stepping tempo from inside a Task playing on the very clock being changed.

**Example (Claude's discretion default: 8-beat ramp = 2 bars at 4/4, 16th-note step granularity, linear-in-BPM):**
```supercollider
// Started ONCE inside s.waitForBoot, alongside ~clock itself — not per-message.
~ppRampTargetBpm = ~bpm;     // starts "at rest" at the current tempo
~ppRampRateBpm = 0;          // BPM change per beat; 0 = not currently ramping
~ppRampStepBeats = 0.25;     // update every 16th note — fine enough to sound continuous
~ppRampActive = false;       // true only while schedAbs is waiting for the FIRST beat boundary

~ppRampStepper = Routine({
    loop {
        var now = ~clock.tempo * 60;
        var diff = ~ppRampTargetBpm - now;
        if (diff.abs < 0.1) {
            // Close enough: land exactly, stop nudging until the next target change.
            ~clock.tempo = ~ppRampTargetBpm / 60;
            ~bpm = ~ppRampTargetBpm;
        } {
            var maxStep = ~ppRampRateBpm * ~ppRampStepBeats;
            var step = diff.clip(maxStep.neg, maxStep);
            ~clock.tempo = (now + step) / 60;
        };
        ~ppRampStepBeats.wait;
    };
}).play(~clock);

// /pp/bpm handler: clamp, then quantize the START of a NEW ramp to the next beat
// (TEMPO-01's "starting on a beat boundary"). A mid-ramp retarget does NOT need
// its own beat-quantized start — the stepper above is already running continuously,
// so updating its target takes effect on its very next 16th-note step, which reads
// as "immediate and smooth," not as a jump (TEMPO-02).
OSCdef(\pp_bpm, { |msg|
    var raw = msg[1];
    if (raw.isNumber.not or: { raw.isNaN }) {
        "PedalPulse WARNING: ignoring /pp/bpm with invalid argument %".format(raw).postln;
    } {
        var bpm = raw.asFloat.clip(60, 180);
        var rampBeats = 8;  // ~2 bars at 4/4 — Claude's discretion default, see Gray Areas
        var engageNewRamp = { |targetBeat|
            // Recompute rate from the clock's CURRENT tempo at the moment the ramp
            // actually engages (not the tempo at message-receive time) — this is
            // what makes a mid-ramp retarget correct: "current" always means "now."
            var nowBpm = ~clock.tempo * 60;
            ~ppRampTargetBpm = bpm;
            ~ppRampRateBpm = (bpm - nowBpm).abs / rampBeats;
        };
        if (~ppRampRateBpm > 0 or: { ~ppRampActive }) {
            // Already ramping: retarget immediately, no beat-quantized restart (TEMPO-02).
            engageNewRamp.value(nil);
        } {
            // At rest: quantize the START of this new ramp to the next beat (TEMPO-01).
            ~ppRampActive = true;
            ~clock.schedAbs(~clock.nextTimeOnGrid(1), {
                engageNewRamp.value(nil);
                ~ppRampActive = false;
                nil;
            });
        };
    };
}, '/pp/bpm', srcID: NetAddr("127.0.0.1", nil));
```

**Curve shape note:** The example above is **linear in BPM** (constant BPM-per-beat rate) — the simplest, most predictable default, and what the community thread's own example uses. STATE.md already flags that "the tempo-ramp curve shape needs a short spike" (a listening test) — see Gray Areas below; an exponential or cosine-eased curve (`[CITED: scsynth.org thread]` mentions a `ListeningClock.fadeTempo(target, dur, \cos)` idiom for this) is a drop-in replacement for the `step` calculation if linear sounds too mechanical, with no change to the retarget logic.

### Pattern 2: Full groove layering on one shared clock (ENG-01)

**What:** Extend Phase 1's three `Pbindef`s (`\ppKick`, `\ppHat`, `\ppBass`) with two more (`\ppArp`, `\ppPad`), all `.play(~clock, quant: 4)` on the **same** `~clock` instance Phase 1 already created. This is the single most important fact for "every layer staying in time" (success criterion 2/3): because `TempoClock` defines musical time as "beats," and every `Pbindef` scheduled on one clock shares that clock's notion of "beat," a single `~clock.tempo_=` write (from Pattern 1's stepper) instantly and simultaneously changes the effective playback rate of **every** layer — there is no per-layer tempo tracking to get wrong, as long as nothing introduces a second clock.

**Anti-pattern this guards against:** Giving the arp or pad its own `TempoClock` (e.g. for a different internal subdivision) would desynchronize it from the ramp the instant a glide starts, since only `~clock`'s tempo is being nudged by the stepper. Keep every layer, including any future layer, on `~clock`.

**Example (arp + pad additions, same SynthDef/Pbindef idiom already established in Phase 1's bass — self-contained envelope, `doneAction: 2`, gate-driven sustain so Pbind's own event-stream auto-release handles normal note-offs without any Stop-specific code):**
```supercollider
SynthDef(\ppArp, { |out = 0, amp = 0.18, freq = 440, gate = 1|
    var sig, env;
    env = EnvGen.kr(Env.adsr(0.002, 0.05, 0.4, 0.08), gate, doneAction: 2);
    sig = Pulse.ar(freq, 0.3) + Pulse.ar(freq * 1.002, 0.3);  // slight detune, cheap
    sig = LPF.ar(sig, freq * 4);
    Out.ar(out, (sig * env * amp) ! 2);
}).add;

SynthDef(\ppPad, { |out = 0, amp = 0.2, freq = 220, gate = 1|
    var sig, env;
    env = EnvGen.kr(Env.adsr(0.4, 0.3, 0.7, 1.2), gate, doneAction: 2);  // slow attack/release = pad character
    sig = Saw.ar([freq, freq * 1.005, freq * 0.997]);  // 3-voice detune for width
    sig = LPF.ar(sig, 1200);
    Out.ar(out, Splay.ar(sig) * env * amp);
}).add;

Pbindef(\ppArp,
    \instrument, \ppArp,
    \dur, 0.25,  // 16th notes
    // A minor arpeggio, reusing Phase 1's A-minor root (MIDI 33 = A1 bass; arp an octave+ up)
    \midinote, Pseq([57, 60, 64, 60], inf),  // A3, C4, E4, C4
    \legato, 0.6,  // < 1.0: Pbind auto-releases each note via gate before the next one (no hang)
    \out, ~ppMixBus, \group, ~ppInstrGroup,
).play(~clock, quant: 4);

Pbindef(\ppPad,
    \instrument, \ppPad,
    \dur, 4,  // one chord per bar
    \midinote, Pseq([[45, 48, 52], [45, 48, 53]], inf),  // Am, then Am with a passing tone — fixed loop
    \legato, 0.9,
    \out, ~ppMixBus, \group, ~ppInstrGroup,
).play(~clock, quant: 4);
```
Source for the `\legato`-driven auto-release mechanism `[CITED: doc.sccode.org Pattern Guide, PG_08_Event_Types_and_Parameters]`: "Pbind plays one or more Synth nodes... with an automatic release after `\sustain` beats if the SynthDef has a gate argument"; sustain is computed from `\dur * \legato` when not given directly. With `\legato` < 1.0, every arp/pad note releases itself on schedule without any Stop-time intervention — Pattern 3's `Group`-wide gate broadcast below exists only to handle the Stop-pressed-mid-note case, not normal operation.

### Pattern 3: Idempotent Start/Stop with guaranteed clean release (GUI-02)

**What:** A single `/pp/play <int>` OSCdef (int: 1 = play, 0 = stop) that is a no-op if the requested state already matches `~ppPlaying` (mirrors the "notify listeners only on an actual change" idiom already in `python_app/bpm_logic.py`'s `BpmController._set` — read this session, `python_app/bpm_logic.py:111-117`, quoted: `"""if new_value == self._value: return False"""`). On Stop, in addition to `.stop`-ing all five `Pbindef`s (which only stops *scheduling new events* — it does **not** touch synths already running on the server), broadcast `\gate, 0` to the instrument `Group` so any currently-sustaining note (most likely the pad, since it has the longest legato/release) is cut off via its own release envelope — a clean fade, not a hard pop, and definitely not left hanging.

**Why `.stop` alone is not enough:** `Pdef`/`Pbindef`'s `.stop` is documented only as "stops the player" `[CITED: doc.sccode.org/Classes/Pdef.html]`, inherited from `TaskProxy`/`EventPatternProxy`, with no documented claim that it also frees or releases already-spawned server-side Synth nodes — and by the general Node/Pattern model (a `Pbind`'s event stream spawns independent `Synth` nodes on the server; stopping the *stream* does not reach back into nodes it already spawned), a pad note with a long sustain that happens to be mid-note when Stop is pressed would otherwise ring out for its full, possibly multi-beat, duration. This is exactly the gap the `Group.set(\gate, 0)` broadcast closes.

**Grounding:** `Node.set` on a `Group` broadcasts to every contained Node — `[CITED: doc.sccode.org/Classes/Node.html]`, quoted verbatim: *"If this Node is a Group this will set all Nodes within the Group."* What is **not** documented, and could not be independently verified by execution in this session (see Assumptions Log A3), is whether a Synth lacking a matching control name (e.g. `\ppKick`/`\ppHat`, which have no `gate` argument) errors or silently ignores the out-of-scope set. This is extremely well-established, widely-relied-upon SuperCollider behavior (any synth missing a named control simply has no effect from that part of the message) but is flagged `[ASSUMED]` here rather than `[VERIFIED]` because this session's attempt to prove it by running a short headless sclang script did not complete (timed out without producing the needed output; see Assumptions Log A3). **The planner should add exactly one check to the Wave 0 smoke test harness that sends `\gate, 0` to the full instrument group (including kick/hat, which lack a gate arg) and asserts no error is logged and kick/hat continue playing afterward** — this converts the assumption into a verified fact for ~10 lines of smoke-test code, cheaper than re-deriving it here.

**Example:**
```supercollider
~ppPlaying = true;  // matches Phase 1's D-15 autostart-on-boot default — see Gray Areas for why

~ppStart = {
    [\ppKick, \ppHat, \ppClap, \ppBass, \ppArp, \ppPad].do { |name|
        Pbindef(name).play(~clock, quant: 4);  // quant: 4 = next bar — "brings the groove back in time"
    };
    ~ppPlaying = true;
};

~ppStop = {
    [\ppKick, \ppHat, \ppClap, \ppBass, \ppArp, \ppPad].do { |name| Pbindef(name).stop };
    ~ppInstrGroup.set(\gate, 0);  // release any mid-sustain note NOW, regardless of its own envelope
    ~ppPlaying = false;
};

OSCdef(\pp_play, { |msg|
    var raw = msg[1];
    if (raw.isNumber.not) {
        "PedalPulse WARNING: ignoring /pp/play with invalid argument %".format(raw).postln;
    } {
        var want = raw.asInteger != 0;
        if (want != ~ppPlaying) {       // idempotent: repeated Start/Stop is a no-op
            if (want) { ~ppStart.value } { ~ppStop.value };
        };
    };
}, '/pp/play', srcID: NetAddr("127.0.0.1", nil));
```

**`doReset` note:** `Pdef`/`Pbindef`'s `.play` accepts a `doReset` argument that **defaults to `false`** `[CITED: doc.sccode.org/Classes/Pdef.html]` — meaning a bare `.play` after `.stop` resumes the pattern's event stream from wherever it left off, not from the top. For a fixed, cyclically-repeating loop (every pattern above is `Pseq(..., inf)`) this makes essentially no audible difference and is the simpler default; pass `doReset: true` explicitly only if a deterministic "always starts the bass's note-change-at-bar-end from the same spot" feel is wanted for testing. Flagged as a gray area below, not a hard requirement.

### Pattern 4: Python-side transport control (mirrors `BpmController`)

**What:** A small `PlayController`, structurally parallel to the existing `BpmController` in `python_app/bpm_logic.py` (read this session) — same "track current value, notify listeners on change, send on explicit action" shape, but **no debounce**: Start/Stop is a single discrete click, not a value that changes 60 times during a drag, so there is nothing to coalesce.

**Example:**
```python
# python_app/bpm_logic.py (extension, same module — no new file needed)
class PlayController:
    """Tracks play/stop intent and sends /pp/play on actual change (GUI-02).

    No debounce: unlike BpmController, a button click is a single discrete
    event, not a stream of drag ticks to coalesce.
    """

    def __init__(self, send: Callable[[int], object], initial: bool = True) -> None:
        self._send = send
        self._playing = initial
        self._listeners: list[Callable[[bool], None]] = []

    @property
    def playing(self) -> bool:
        return self._playing

    def add_listener(self, fn: Callable[[bool], None]) -> None:
        self._listeners.append(fn)

    def set_playing(self, playing: bool) -> None:
        if playing == self._playing:
            return  # idempotent, same spirit as BpmController._set
        self._playing = playing
        for listener in self._listeners:
            listener(playing)
        self._send(1 if playing else 0)

    def toggle(self) -> None:
        self.set_playing(not self._playing)

    def send_initial(self) -> None:
        """Send current state once on launch (same D-23 philosophy: GUI is the
        source of truth), unconditionally — mirrors BpmController.send_initial."""
        self._send(1 if self._playing else 0)
```
`OscClient` needs one new thin method, `send_play(self, playing: int) -> bool`, following the exact same try/except-OSError-returns-False shape as `send_bpm` (read this session, `python_app/osc_client.py:31-44`) — reuse that code structure verbatim, just a different address constant (`config.OSC_PLAY_ADDRESS = "/pp/play"`).

### Anti-Patterns to Avoid

- **Giving arp/pad their own `TempoClock`:** breaks phase-lock the instant a glide starts (Pattern 2). Every layer must share `~clock`.
- **Cancel-and-replace the ramp Routine on every retarget:** works, but introduces an ordering hazard (brief double-stepping or a stall) that the single-persistent-stepper design (Pattern 1) avoids entirely. Don't reach for `Routine.stop` + `Routine.new` as the retarget mechanism.
- **Relying on `Pbindef(...).stop` alone to guarantee "no hanging notes":** it stops the *pattern stream*, not already-spawned server-side synths (Pattern 3). A long pad note mid-sustain will keep sounding unless something explicitly releases it.
- **Giving the pad an un-gated, infinitely-sustaining `SynthDef` (no `gate` control at all):** even with the `Group.set(\gate, 0)` safety net, a synth with no `gate` argument can't be released that way — it would need `.free` (a hard cutoff, audible pop) instead of a clean release. Always give the pad a `gate`-driven `Env.adsr`/`Env.asr`.
- **Treating `rampBeats`/step-granularity as fixed forever:** CTRL-02 (v2, user-configurable ramp time) already anticipates this becoming a tunable; keep it a named var (`rampBeats` in the OSCdef), not a magic literal buried in the stepper.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-layer tempo tracking during a glide | A separate "current rate" var per instrument, manually recomputing each layer's note timing as tempo changes | One shared `~clock`; every `Pbindef.play(~clock, ...)` | `TempoClock` already defines "beat" as the one unit every pattern on it shares — this is the entire point of the class, don't duplicate its bookkeeping |
| Releasing a sustained voice on Stop | Tracking every spawned pad `Synth` object in an array so Stop can `.release` each one individually | `~ppInstrGroup.set(\gate, 0)` — one line, reaches every current and future child Node | `Group` already exists specifically to let you address "everything currently inside it" as one unit `[CITED: doc.sccode.org/Classes/Node.html]`; a hand-rolled registry duplicates what the server's own node tree already tracks, and is a classic source of leaks if a note is missed |
| Per-note release timing for arp/bass/hat | Manually scheduling a `gate=0` message `N` beats after each note-on | `\legato` < 1.0 on the `Pbind`/`Pbindef` | Pbind's event-stream already computes and sends the gate-off automatically from `\dur * \legato` `[CITED: doc.sccode.org Pattern Guide]` — this is precisely what Phase 1's bass pattern already relies on |
| Smooth multi-step tempo interpolation | A custom easing/tweening library or manual delta-time accumulator | A `Routine` stepping on the clock itself, `wait()`-ing in beats | The clock's own beat-relative scheduling is the "tween engine" here; a Routine playing on `~clock` naturally speeds up/slows down its own step rate as the tempo it's adjusting changes, for free |

**Key insight:** Every new mechanic Phase 2 needs (phase-locked multi-layer sequencing, smooth tempo interpolation, group-wide voice release) is a class of problem `TempoClock`/`Pbindef`/`Group`/`Node` already solve by design — the Phase 2 work is almost entirely *composition* of existing SC primitives, not new infrastructure. The only genuinely custom code is the musical content (which notes, which synth timbres) and the two mutable vars driving the ramp stepper.

## Common Pitfalls

### Pitfall 1: Tempo-ramping from inside a Routine scheduled on the clock being changed

**What goes wrong:** If the ramp stepper's `wait()` calls are interpreted as *wall-clock* time instead of *beat* time, or if the stepper runs on a *different* clock than the one it's adjusting, the glide's actual duration drifts from the intended "1-2 bars" as tempo changes, or desyncs from the instrument patterns entirely.
**Why it happens:** It's easy to reach for `SystemClock`/`AppClock` (wall-clock-based) for "a timer that fires every N milliseconds" out of habit, since that's the obvious tool for "do something repeatedly." That's wrong here — the ramp must be beat-relative so it inherits the same musical-time notion as the instrument patterns.
**How to avoid:** `.play(~clock)` on the stepper `Routine` itself (Pattern 1), and use `.wait()` with a beat-domain value (`~ppRampStepBeats`), never a seconds-domain sleep.
**Warning signs:** The glide duration feels wrong (too fast/slow) specifically at extreme tempos (60 BPM or 180 BPM), or the ramp and the instrument patterns audibly drift apart during a glide.

### Pitfall 2: `.stop` on a Pbindef does not free already-playing synths

**What goes wrong:** Covered in depth in Pattern 3 — Stop appears to "work" in casual testing (because most notes are short) but a held pad chord keeps ringing for its full duration after Stop is pressed, violating "music stops cleanly (no hanging notes)."
**Why it happens:** `.stop`'s name suggests "everything stops," and for short percussive notes that's true in practice (they finish almost immediately on their own). The gap only becomes audible with a long-sustain voice.
**How to avoid:** Pattern 3's `Group.set(\gate, 0)` broadcast on every Stop, unconditionally — not just "when a pad note happens to be playing."
**Warning signs:** Stop sounds clean in a quick manual test but a pad chord audibly keeps ringing if Stop is pressed right after a new chord triggers.

### Pitfall 3: Forgetting `doneAction: 2` on the new arp/pad SynthDefs

**What goes wrong:** Same node-leak risk Phase 1 already flagged for kick/hat/bass, now doubled with two more layers — leaked nodes are invisible in a short test, compounding toward Phase 4's 60-minute soak (ENG-03).
**Why it happens:** Easy to copy an existing `SynthDef` shape and forget the `doneAction: 2` on a *new* `EnvGen.kr` call when writing arp/pad from scratch.
**How to avoid:** Every new `SynthDef` in Pattern 2's examples includes it; keep it non-negotiable per CLAUDE.md.
**Warning signs:** `s.numSynths` trending upward during a short manual test with Start/Stop cycling.

### Pitfall 4: CPU growth from adding two more continuously-triggering layers

**What goes wrong:** Arp (16th-note triggering) and pad (overlapping long-release voices) are both more CPU-hungry per layer than Phase 1's sparse kick/hat/bass loop; while the full 60-minute soak is Phase 4's job (ENG-03), a Phase 2 groove that's already heavy risks competing with Zwift for CPU per the project's core platform constraint.
**Why it happens:** It's tempting to reach for convolution reverb, multiple detuned oscillators per voice, or very short control-rate periods "because it sounds better," without checking the aggregate cost.
**How to avoid:** Keep FX (reverb/delay/drive) out of Phase 2 entirely — EPIC-01's filter/drive/reverb/richness mapping is explicitly Phase 3's job (EPIC-01/02 traceability). Phase 2's SynthDefs should stay as cheap as Phase 1's (a couple of oscillators, simple filters), deferring anything CPU-heavier to when EPIC's lagged-parameter system exists to justify it.
**Warning signs:** Noticeably higher `s.avgCPU`/`s.peakCPU` than Phase 1's loop when watched manually; audible dropouts when Zwift is also running.

### Pitfall 5: `/pp/play` sent with the wrong argument type or address casing

**What goes wrong:** Same class of bug as Phase 1's Pitfall 1 (port drift) — if the Python side sends a string ("play"/"stop") instead of an int, or if the address doesn't exactly match `/pp/play`, the engine's `OSCdef` either ignores the message or (if the handler doesn't validate) throws.
**Why it happens:** Easy to be inconsistent about the wire format between the one-off `/pp/bpm <float>` precedent and a new `/pp/play <?>` message if the type isn't pinned down up front.
**How to avoid:** Pin the contract explicitly in this research (done: `/pp/play <int>`, 1=play/0=stop) and in `config.py` (`OSC_PLAY_ADDRESS`), matching the existing `OSC_BPM_ADDRESS` convention.
**Warning signs:** Start/Stop button clicks produce no engine effect; `main.scd`'s post window shows no `/pp/play` log line matching Pattern 3's warning-on-invalid-argument branch.

## Code Examples

See the four numbered patterns under **Architecture Patterns** above — they are the verified, phase-specific code examples (ramp stepper + retarget, arp/pad groove layering, idempotent Start/Stop with gate broadcast, Python `PlayController`). No separate restatement needed here.

## Gray Areas Needing a Default

**No CONTEXT.md exists for this phase.** These are the design decisions a `/gsd-discuss-phase` session would normally have locked; each has a concrete recommended default below so the planner isn't blocked, but each should be treated as **provisional** (easy to flag for user confirmation at review time), not as locked as a `01-CONTEXT.md` D-NN decision would be.

| Gray area | Recommended default | Rationale | Reversibility |
|-----------|---------------------|-----------|----------------|
| Groove arrangement (which drum voices, bass line, arp pattern, pad progression) | Kick (four-on-the-floor, unchanged from Phase 1) + offbeat hat (unchanged) + a new clap/snare on beats 2/4 + Phase 1's existing A-minor bass line (unchanged) + a 16th-note A-minor arp (A3-C4-E4-C4) + a one-chord-per-bar Am pad with a passing tone | Reuses Phase 1's established key (A minor) and two of three existing layers verbatim — lowest-risk path to "feels like a continuation," not a reboot | Easy — it's a fixed loop; swapping notes/patterns later is a content edit, not a structural change |
| Glide duration | 8 beats (2 bars at 4/4) | Matches the requirement's "roughly 1-2 bars," landing at the upper (safer, smoother) end | Easy — `rampBeats` is a named var in the OSCdef, trivially tunable; CTRL-02 (v2) plans to expose it to the user anyway |
| Glide curve shape | Linear in BPM (constant BPM-per-beat rate) | Simplest, most predictable; matches the community-standard example found this session; STATE.md already flags this needs a listening-test spike before being considered final | Easy — isolated to the `step` calculation inside the stepper Routine; swapping to exponential/cosine easing doesn't touch the retarget logic |
| Ramp step granularity | 0.25 beats (16th notes) | Fine enough to sound continuous, coarse enough to be cheap; no citation found for an exact "right" value — a pure engineering tradeoff | Easy — one number |
| Mid-glide retarget semantics | Immediate update of target/rate, no beat-quantized restart (see Pattern 1) | TEMPO-02 says "no restart, no jump" — waiting for a beat boundary to retarget would itself look like a tiny stall; immediate update avoids that while still being musically smooth, since the stepper's own 16th-note cadence already provides continuity | Moderate — changing this later means touching the OSCdef's branching logic, not just a constant |
| Stop semantics | Immediate (stop scheduling + broadcast gate-release), not "wait for the current bar to finish" | The requirement says "stops cleanly (no hanging notes)," which reads as "stop promptly and tidily," not "finish the phrase first" — an end-of-bar stop would directly conflict with "no hanging notes" if a pad chord just started | Moderate — an end-of-bar-quantized stop is a legitimate alternative read of the requirement; flag for user confirmation if the immediate-stop feel doesn't match expectations in testing |
| Start semantics | Restart at `quant: 4` (next bar boundary), not a precise resume of frozen mid-note state | "Brings the full groove back in time" reads as "re-enters cleanly on a bar line," which is what `quant: 4` already does elsewhere in this codebase (Phase 1's existing autostart) | Easy — `quant` value is a one-line change |
| `doReset` on restart | Leave default (`false` — patterns resume their `Pseq` position, don't reset to index 0) | For an infinite, cyclically-repeating fixed loop this is inaudible in practice and is the simpler default (one less thing to get wrong); flip to `true` only if a specific "always restarts identically" feel is wanted for deterministic testing | Easy — one keyword argument |
| Engine boot-time play state | `~ppPlaying = true` (autostart, same as Phase 1's D-15) | Keeps the engine's existing "autostarts on boot" behavior unchanged; the GUI's `PlayController` should default its own `initial=True` and `send_initial()` on launch, matching `BpmController.send_initial()`'s philosophy of "GUI is the source of truth," so the two never start out of sync | Easy — a single boolean default in two places |
| GUI control shape (one toggle button vs. separate Start/Stop buttons) | A single toggle `Button` whose label swaps between "Start" and "Stop" based on `PlayController.playing` | Matches the existing compact-window aesthetic (D-12) better than two buttons; one widget, one click target | Easy — pure view-layer choice, no controller/engine impact either way |

## Runtime State Inventory

Not applicable — Phase 2 is additive (new SynthDefs, new OSCdefs, new Pbindefs), not a rename/refactor/migration. No existing stored data, service config, OS-registered state, secrets, or build artifacts reference anything being renamed or moved.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The community-sourced ramp-stepping idiom (`Task`/`Routine` calling `.tempo_=` repeatedly while playing on the clock it's adjusting) scales cleanly to a *continuously-running* stepper (this research's design) rather than the *one-shot, fixed-N-steps* examples actually found (`(1,1.01..2).do {...}`) | Pattern 1 | Low — the underlying mechanic (beat-relative `wait()` on the same clock) is identical in both forms; the "run forever, read a mutable target" structure is a standard Routine idiom independent of this specific use, not something that needs extra validation |
| A2 | Linear-in-BPM is an acceptable default curve shape for "no audible jolt" | Pattern 1, Gray Areas | Low-Medium — if it sounds mechanical, STATE.md already anticipates a listening-test spike to pick a better curve; the fix is a one-line change to the `step` formula, not a redesign |
| A3 | A `Synth` lacking a matching control name (e.g. `\ppKick`/`\ppHat` receiving a broadcast `\gate` set) silently ignores it rather than erroring | Pattern 3 | **Medium** — if this assumption is wrong, the Stop command's `Group.set(\gate, 0)` broadcast could throw an error for every percussive layer every time Stop is pressed. Official docs (`Node.html`) confirm the *broadcast* behavior but not this specific edge case; an attempt to verify empirically via a headless sclang script in this session did not complete within the available time (process had to be killed after not producing output within 120s on two attempts — not a falsification, just an inconclusive probe, so this stays `[ASSUMED]` rather than being marked disproven or confirmed). **Recommend a Wave 0 smoke-test check** (send `\gate, 0` to the full instrument group including kick/hat, assert no error and that kick/hat still play afterward) before relying on this in the shipped Stop implementation |
| A4 | `Pbindef`'s inherited `.stop`/`.play`/`quant` semantics (documented at the `Pdef`/`EventPatternProxy`/`TaskProxy` superclass level, since `Pbindef`'s own doc page doesn't restate them) apply identically to `Pbindef` instances | Standard Stack, Pattern 2/3 | Low — `Pbindef`'s own doc page explicitly describes itself as "combining PbindProxy and Pdef," and Phase 1's existing code already calls `.play(~clock, quant: 4)` / would call `.stop` successfully on `Pbindef` instances today, so this inheritance is already implicitly relied upon and working in the shipped Phase 1 code |

## Open Questions

1. **Exact arp/pad note content and voicing**
   - What we know: Phase 1 established A minor as the key; Gray Areas above proposes a concrete default (16th-note arp A3-C4-E4-C4, one-chord-per-bar Am pad).
   - What's unclear: Whether this specific voicing reads as "melodic techno / progressive trance" to the user's ear — this is inherently a listening-test judgment, not something research can settle from docs.
   - Recommendation: Treat the proposed default as a reasonable starting point for implementation, explicitly expect it to be revised after a manual listening pass (same spirit as D-13's "exact synth design... Claude's Discretion" in Phase 1).

2. **Whether the Wave 0 smoke-test Group-broadcast check (Assumption A3) should block planning or just be a planned task**
   - What we know: The underlying SC behavior is almost certainly fine (extremely common idiom in the SC community); the only gap is this session couldn't execute a verifying script before running out of budget for that side-investigation.
   - What's unclear: Whether the planner should spend a dedicated task proving this before building Pattern 3, or fold it into the same task that builds the Stop OSCdef (verify-as-you-build).
   - Recommendation: Fold it in — add the Group-broadcast-to-mismatched-control assertion as one extra check inside whatever task extends `supercollider/smoke_test.scd` for Phase 2's Start/Stop behavior, rather than a separate research-blocking spike.

## Environment Availability

No new external dependencies this phase (see Standard Stack). Phase 1's `01-RESEARCH.md` Environment Availability table — SuperCollider 3.14.1, Homebrew `python3.13`, Tcl/Tk 9.0.3, `python-osc` 1.10.2, pytest — is unchanged and still applicable; re-verified indirectly this session by reading the actual installed code and Phase 1's passing smoke test (`scripts/smoke_test.sh`, `supercollider/smoke_test.scd`), which exercises the live SuperCollider install end-to-end.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | pytest 8.x (already installed in `.venv`, per Phase 1) + the existing headless-sclang smoke-test harness |
| Config file | none — same as Phase 1 |
| Quick run command | `.venv/bin/pytest python_app/tests/ -x -q` |
| Full suite command | `.venv/bin/pytest python_app/tests/ -q` && `scripts/smoke_test.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ENG-01 | All 5+ layers play continuously on one clock | smoke (headless sclang) | extend `supercollider/smoke_test.scd`: assert all `Pbindef`s report `.isPlaying` after boot | ❌ Wave 0 — extend existing file |
| TEMPO-01 | New BPM glides over ~1-2 bars, starting on a beat boundary, reaching the target | smoke | extend smoke test: send a BPM change, poll `~clock.tempo` at intervals, assert it moves monotonically toward target and lands within `rampBeats` ± tolerance; assert the first tempo change happens on a whole-beat boundary (reuse Phase 1's `~ppLastApplyBeat`-style check, adapted) | ❌ Wave 0 |
| TEMPO-02 | Mid-glide retarget continues from current tempo, no restart/jump | smoke | extend smoke test: start a ramp toward X, after a few steps send a new target Y, assert tempo trajectory is continuous (no instantaneous jump > one step's worth) and converges on Y, not X | ❌ Wave 0 |
| GUI-02 (engine side) | `/pp/play 0` stops all patterns and leaves zero running synths after release time; `/pp/play 1` restarts quantized to the bar; repeated Start/Stop is idempotent (no double-trigger) | smoke | extend smoke test: trigger Stop while a pad note is mid-sustain, wait past the release time, assert `s.numSynths` returns to the resting baseline; trigger Start, assert all `Pbindef`s report `.isPlaying` again; send duplicate `/pp/play 1` twice, assert no error/double-start | ❌ Wave 0 |
| GUI-02 (Group broadcast safety, Assumption A3) | `Group.set(\gate, 0)` on a group containing synths without a `gate` control does not error | smoke | new check in smoke test: broadcast `\gate, 0` to the instrument group immediately after boot (before any Stop is otherwise tested), assert no error logged and kick/hat continue to produce audio afterward | ❌ Wave 0 |
| GUI-02 (Python side) | `PlayController` sends `/pp/play 1`/`0` on an actual state change, is idempotent (no duplicate sends), `send_initial()` sends once | unit (pure logic, no mocking needed — same style as `test_bpm_logic.py`) | `pytest python_app/tests/test_play_logic.py -x` | ❌ Wave 0 — new file, same pattern as existing `test_bpm_logic.py` |
| GUI-02 (OSC wire format) | `send_play` delivers `/pp/play <int>` correctly | unit (mock socket, same pattern as existing `test_osc_client.py`) | `pytest python_app/tests/test_osc_client.py -x` (extend existing file with new test functions, same style as `test_send_bpm_delivers_decodable_osc_message_over_real_socket`) | ❌ Wave 0 — extend existing file |
| ENG-01 musical feel ("melodic techno / progressive trance style") | Whether the arrangement actually sounds right | **manual-only** | Listen to `main.scd` running normally in the IDE; no automated check can judge musical quality | n/a — explicitly manual, same precedent as Phase 1's D-17 limiter check |
| TEMPO-01/02 "no audible jolt" (the subjective, not the measurable, half of these requirements) | Whether the glide actually *sounds* smooth, not just whether the numbers move monotonically | **manual-only** | Listen while dragging the BPM slider repeatedly, including rapid back-and-forth retargets | n/a — explicitly manual; the smoke test proves the mechanism is correct, not that it sounds good (same split Phase 1 used for the limiter) |

### Sampling Rate
- **Per task commit:** `.venv/bin/pytest python_app/tests/ -x -q` (quick run)
- **Per wave merge:** full pytest suite + `scripts/smoke_test.sh` (extended) + the two manual listening checks (groove arrangement, glide smoothness)
- **Phase gate:** Full suite + smoke test green, both manual listening checks performed, before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `supercollider/smoke_test.scd` — extend with: all-layers-playing check, glide-reaches-target + monotone-trajectory check, beat-boundary-start check, mid-glide-retarget-continuity check, Stop-leaves-zero-synths-after-release check, Start-is-quantized-and-idempotent check, Group-broadcast-to-mismatched-control-doesn't-error check (Assumption A3)
- [ ] `python_app/tests/test_play_logic.py` — new file, covers `PlayController` (GUI-02 Python side), same style as `test_bpm_logic.py`
- [ ] `python_app/tests/test_osc_client.py` — extend existing file with `send_play` tests, same style as the existing `send_bpm` tests
- [ ] `python_app/config.py` — add `OSC_PLAY_ADDRESS = "/pp/play"` constant
- [ ] No new framework installs needed — pytest and the smoke-test harness both already exist from Phase 1

## Security Domain

`security_enforcement` is enabled (`.planning/config.json` → `workflow.security_enforcement: true`, `security_asvs_level: 1`). Same posture as Phase 1 — single-user, localhost-only desktop app, no network exposure beyond loopback UDP, no authentication surface. Phase 2 adds one new OSC input surface (`/pp/play`); everything else is unchanged from Phase 1's assessment.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Unchanged from Phase 1 — single-user local desktop app |
| V3 Session Management | No | Unchanged from Phase 1 |
| V4 Access Control | No | Unchanged from Phase 1 |
| V5 Input Validation | **Yes** | New `/pp/play` OSCdef must validate its argument is a number before calling `.asInteger` (Pattern 3's `raw.isNumber.not` guard), exactly mirroring the existing `/pp/bpm` handler's `isNumber`/`isNaN` guard — never trust the argument type, even from "your own" GUI |
| V6 Cryptography | No | Unchanged from Phase 1 |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed `/pp/play` argument (string, NaN, missing arg entirely) crashing the handler or leaving `~ppPlaying` in an inconsistent state | Tampering / Denial of Service | Validate `raw.isNumber` before `.asInteger`, same pattern as the existing `/pp/bpm` handler; on invalid input, log a warning and leave state unchanged (never half-apply) |
| Rapid repeated `/pp/play` toggling (e.g. a buggy GUI retry loop) causing overlapping Start/Stop races | Denial of Service (self-inflicted) | The idempotency check (`want != ~ppPlaying`) in Pattern 3 already prevents a flood of identical messages from doing anything beyond the first — no additional debounce needed engine-side, matching the fact the Python `PlayController` only sends on an actual state change |
| A stray non-loopback sender triggering `/pp/play` | Spoofing | Same mitigation already in place for `/pp/bpm` — `srcID: NetAddr("127.0.0.1", nil)` on the new `/pp/play` OSCdef, no new attack surface introduced |

## Sources

### Primary (HIGH confidence)
- `doc.sccode.org/Classes/TempoClock.html` — `tempo_`, `schedAbs`, `sched`, `nextTimeOnGrid` exact signatures/semantics, fetched and quoted this session
- `doc.sccode.org/Classes/Node.html` — `Node.set` Group-broadcast behavior, quoted verbatim this session
- `doc.sccode.org/Classes/Pdef.html` — `.play` signature including `doReset: false` default, `.stop`/`.clear` documented behavior, fetched this session
- `doc.sccode.org/Classes/Pbindef.html` — class relationship to `Pdef`/`PatternProxy`, quant-schedules-to-beat confirmation, fetched this session
- `doc.sccode.org` Pattern Guide (`PG_08_Event_Types_and_Parameters`) — `\legato`/`\sustain`/gate auto-release mechanism, via WebSearch this session
- `supercollider/main.scd` (this repo) — read in full this session; `~ppPendingBpm`/`~ppApplyScheduled` latest-wins idiom (lines 111-131) is the in-repo precedent Pattern 1 generalizes
- `python_app/bpm_logic.py` (this repo) — read in full this session; `BpmController`/`Debouncer` structure is the in-repo precedent Pattern 4 mirrors
- `python_app/osc_client.py`, `python_app/view.py`, `python_app/main.py`, `python_app/config.py` (this repo) — read in full this session for the existing OSC-send and Tk-wiring conventions Phase 2 extends
- `.planning/phases/01-tempo-link-skeleton/01-RESEARCH.md`, `01-CONTEXT.md` (this repo) — read in full this session; source of the still-binding D-19 OSC-naming convention (quoted verbatim) and all "unchanged from Phase 1" claims

### Secondary (MEDIUM confidence)
- `scsynth.org/t/smooth-alteration-of-tempo/6857` — community thread, Task/Routine tempo-stepping idiom and `ListeningClock.fadeTempo` curve-shape mention, via WebFetch this session
- `.planning/phases/01-tempo-link-skeleton/01-UI-REVIEW.md` — read this session for the existing compact-window aesthetic informing the Start/Stop control-shape gray area

### Tertiary (LOW confidence)
- None used as the basis for any claim in this document beyond what's logged in the Assumptions Log above.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies, Phase 1's verification carries forward unchanged
- Architecture (TempoClock ramp, groove layering): HIGH — grounded in official class docs plus direct reading of the actual Phase 1 code this new design extends
- Architecture (Stop/gate-release): MEDIUM — the broadcast mechanism itself is `[CITED]`/well-documented; the specific "ignores mismatched control" edge case is `[ASSUMED]` pending a cheap Wave 0 smoke-test check (Assumption A3)
- Pitfalls: HIGH — each is a direct, specific consequence of the documented mechanics above, not speculative
- Gray areas: MEDIUM by construction — these are explicitly provisional defaults substituting for an absent CONTEXT.md, not verified facts

**Research date:** 2026-10-09
**Valid until:** 2026-11-08 (30 days — stable toolchain, no version-sensitive claims; re-verify sooner only if the Assumption A3 smoke-test check surfaces a surprise)
