# Phase 3: EPIC Zones & Volume - Research

**Researched:** 2026-10-09
**Domain:** SuperCollider control-bus-driven FX chain (filter/drive/reverb/"richness") smoothed with `Lag`/`VarLag`, a shared-EPIC-value "conductor" pattern feeding multiple DSP consumers in sync, pre-limiter master-volume gain staging, and the matching Python Tkinter zone-preset-button + volume-slider GUI over OSC
**Confidence:** HIGH for the SuperCollider mechanics (grounded in official class docs fetched this session, plus direct reading of the actual `main.scd`/`python_app/*.py` code this phase extends) and for the Python-side controller/view patterns (direct extensions of Phase 1/2's own established, working code). MEDIUM for the specific FX chain composition (which UGens, what order, where "richness" lives) and all preset/default values, since there is no CONTEXT.md to lock these — see **Gray Areas Needing a Default**.

<user_constraints>
## User Constraints (from CONTEXT.md)

**No CONTEXT.md exists for Phase 3.** The user chose to continue without a `/gsd-discuss-phase` session. There are no locked Phase 3 decisions to copy here.

In its place, this research surfaces every gray area the planner would otherwise have to guess at — see **## Gray Areas Needing a Default** below — each with a concrete recommended default, a rationale, and a reversibility note. Treat that section as the substitute for a `## Decisions` block.

### Still-binding decisions from Phase 1/2 (verified by reading `01-CONTEXT.md`, `supercollider/main.scd`, `python_app/*.py` this session)

These remain in force for Phase 3 because nothing in the Phase 3 goal supersedes them:

- OSC namespace is `/pp/*`, and Phase 1's D-19 (quoted verbatim, `01-RESEARCH.md`/`01-CONTEXT.md`): "Addresses are namespaced. Phase 1 uses `/pp/bpm <float>`. Later phases follow the same scheme (`/pp/epic`, `/pp/play`, `/pp/volume`)." — Phase 3 therefore adds exactly `/pp/epic <float>` and `/pp/volume <float>`, matching this pre-named scheme. **Reversibility: costly** (contract between `main.scd` and the Python client).
- Both new OSCdefs are loopback-only via `srcID: NetAddr("127.0.0.1", nil)`, same guard already on `/pp/bpm` and `/pp/play` `[VERIFIED: supercollider/main.scd:281, 300]`.
- Every enveloped `SynthDef` uses `doneAction: 2` (CLAUDE.md, non-negotiable); Phase 3's FX/smoother synths are **persistent** (not per-note), so they have no envelope and no `doneAction` — see Common Pitfalls for the matching risk (teardown, not envelope).
- The engine clamps independently of the GUI (same shape as TEMPO-03): `/pp/epic` clamps to 0–100, `/pp/volume` clamps to 0–100, mirroring `/pp/bpm`'s `raw.asFloat.clip(60, 180)` `[VERIFIED: supercollider/main.scd:277]`.
- Python side stays send-only (D-24) — no OSC receive path yet; that's Phase 4 (LINK-02/03).
- `~ppRampStepper` is the only writer of `~clock.tempo`; Phase 3 must not touch tempo at all — EPIC and volume are entirely orthogonal to the tempo-glide mechanism (STATE.md, Phase 2 decision, quoted verbatim: "Phase 3 EPIC changes must not write tempo").
- `.venv` + `run.sh` launch, Homebrew `python3.13`/Tk 9.0.3 pairing — unchanged, no new Python dependency this phase.
- Master bus limiter ceiling stays `Limiter.ar(sig, 0.891251, 0.01)` (D-16, −1 dBFS) — Phase 3 must route all its new gain-staging (volume) and FX (drive/saturation) **through** this existing limiter, never around it; this is the entire mechanism by which "max EPIC + max volume never clips" (success criterion 4) is satisfied.
- Carry-over WR-01 (`python_app/view.py:115-118`, Up/Down arrow keys nudge BPM even while the BPM entry has focus): **this phase adds more GUI controls** (zone buttons, volume slider), which is exactly the trigger STATE.md flagged this fix for ("fix before adding more GUI controls in Phase 3"). See Common Pitfalls — this is now in-scope, not optional cleanup.
- Carry-over Phase 2 code-review findings (`osc_client.py` WR-01/WR-02, IN-01 glide landing ~7.75 beats) do not block Phase 3 but are adjacent files Phase 3 extends (`osc_client.py` gets two new `send_*` methods) — the planner should decide whether to fold the WR-01 OSError→Exception broadening into the same touch of that file, since Phase 3 edits it anyway.

### Claude's Discretion (carried forward, same spirit as Phase 1/2)

- Exact FX chain UGen choice/ordering and what "synth richness" concretely means (no existing code or decision defines it) — flagged below with a concrete recommended default.
- Exact zone-to-EPIC-value preset mapping (five numbers 0–100) — flagged below.
- GUI layout/widget choice for the zone buttons and volume slider — flagged below.
- Whether `VolumeController`/`EpicController` are new sibling classes in `bpm_logic.py` (matching how `PlayController` was added in Phase 2) or a shared base class refactor — flagged below.

### Deferred Ideas (OUT OF SCOPE for Phase 3)

Per REQUIREMENTS.md v2 scope: EPIC fine-tune slider alongside presets (CTRL-01, v2 — Phase 3 ships presets **only**, per EPIC-03's literal wording "via five zone preset buttons"), EPIC-driven arrangement/density changes (GEN-03, v2 — Phase 3's EPIC only drives timbre/FX, not note density or pattern content), user-configurable ramp/glide time (CTRL-02, v2). LINK-02/LINK-03 (heartbeat, GUI displaying engine-reported EPIC) are explicitly Phase 4.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| EPIC-01 | EPIC 0–100 audibly changes brightness/energy via filter cutoff, drive/saturation, reverb/delay amount and synth richness, together | Pattern 1 (shared EPIC conductor bus + smoother), Pattern 2 (single `\ppFx` synth driving all four parameters from one smoothed value) |
| EPIC-02 | EPIC changes glide smoothly (lagged parameters), no stepping/clicks | Pattern 1 (`Lag.kr` smoother stage — this is literally the "lagged parameters" the requirement names) |
| EPIC-03 | Five zone preset buttons (Recovery/Endurance/Tempo/Threshold/VO2), each mapped to a predefined EPIC value | Pattern 3 (`EpicController`, Python-side zone→value mapping; engine never knows zone names) |
| GUI-03 | User adjusts master volume from the GUI | Pattern 4 (`VolumeController`, mirrors `BpmController`'s slider-release-send shape) + Pattern 5 (pre-limiter volume gain stage in `\ppMaster`) |
</phase_requirements>

## Summary

Phase 3 adds exactly one new engine-side mechanic — a shared, smoothed "EPIC" control value that drives a single new FX synth sitting between the existing instrument layer and the existing master/limiter stage — plus one new gain stage (volume) inside the existing master synth. Both are pure extensions of patterns Phase 1/2 already established and this session verified by reading the actual code: the "conductor" idiom (`~bpm`/`~ppPlaying` as the single source of truth, read by consumers, written only by OSCdefs — confirmed in `supercollider/main.scd`), the "pass a plain number as a SynthDef control arg and use it directly as a bus index inside `In.ar`/`In.kr`" idiom (already proven working in `\ppMaster`'s own `in` argument, `supercollider/main.scd:93-96`), and the "idempotent re-evaluation teardown" idiom (the `s.waitForBoot` block's existing free-everything-then-rebuild sequence, `supercollider/main.scd:33-45`) which Phase 3's new bus/group/synth must be added to or they will leak on every re-evaluation.

The single riskiest new design decision is **how "filter cutoff, drive/saturation, reverb/delay amount and synth richness" move "together"** (success criterion 2) without each DSP stage drifting independently or stepping. The research's recommendation: route the raw EPIC value through exactly **one** `Lag.kr` smoothing stage into a shared control bus (not N independent `Lag.kr`s inside N consumers), and have **one** FX `SynthDef` read that single smoothed bus and derive all four audible parameters (cutoff via `.linexp`, drive via `.linlin` into `.softclip`, reverb wet mix via `.linlin` into `FreeVerb.ar`, and "richness" as a high-frequency exciter blend) from that one value in one UGen graph — this guarantees perfect synchrony by construction (one input, one smoothing stage, one synth), is cheap (one Lag computation, one synth, not six), and keeps the entire FX concern in a single new file/`SynthDef`, untouched by the existing six instrument `SynthDef`s (no risk of regressing Phase 2's groove). `Lag`/`VarLag`, `FreeVerb`, and `.softclip`/`.distort` are all confirmed stock, core SuperCollider UGens/methods this session (no quark, no plugin) — consistent with CLAUDE.md's "no quarks" constraint.

Volume is architecturally simpler and deliberately **not** routed through the EPIC/FX path at all: it is a second multiplicative gain term inside the existing `\ppMaster` SynthDef (alongside the existing `preGain` debug var), smoothed with its own short `Lag.kr` (zipper-noise prevention on nudges, not a "glide to a zone" musical effect), applied **before** the existing `Limiter.ar` call — which is the entire mechanism that satisfies "max EPIC + max volume never clips" (GUI-03 + success criterion 4): the limiter already holds the final ceiling regardless of what feeds it, exactly as it already does for ENG-02 (marked complete), so Phase 3 does not need to invent new clip protection, only avoid ever bypassing the existing one.

**Primary recommendation:** Insert a new `~ppFxGroup = Group.after(~ppInstrGroup)` between the existing instrument and master groups; change `~ppMasterGroup = Group.after(~ppFxGroup)` (was `Group.after(~ppInstrGroup)`); add `~ppMixBus` (unchanged, still instruments' output) → new `~ppFxBus` (FX synth's output) → existing `~ppMasterGroup`'s synth now reads `~ppFxBus` instead of `~ppMixBus`. Add two control buses (`~ppEpicBus` raw, `~ppEpicSmoothBus` lagged) and one tiny smoother `SynthDef`, one `\ppFx` synth, and extend `\ppMaster` with a `volumeBus` control arg. Python side: two new sibling controller classes (`EpicController`, `VolumeController`) in `bpm_logic.py` mirroring `PlayController`/`BpmController`'s exact shape, two new `OscClient.send_*` methods mirroring `send_bpm`/`send_play`'s exact try/except shape, and new Tk widgets in `view.py` (five zone buttons with a selected-state highlight, one volume `Scale`) following the exact `NUDGE_LABELS`/`PLAY_LABELS` dict-driven, listener-driven pattern already in the file.

## Architectural Responsibility Map

Same two-process architecture as Phase 1/2 — Phase 3 adds no new tier.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Zone name → EPIC numeric value mapping (EPIC-03) | Client (Python `EpicController`/`config.EPIC_ZONES`) | — | The engine has no concept of zone names, only a numeric 0–100 EPIC value — same "client decides intent, engine executes" split as BPM/transport |
| EPIC-driven FX chain (filter/drive/reverb/richness) (EPIC-01) | Engine (`main.scd`, one `\ppFx` SynthDef) | — | Pure audio synthesis; nothing in Python needs to know the FX graph |
| Lagged/smooth EPIC propagation (EPIC-02) | Engine (`Lag.kr` smoother synth + shared control bus) | — | Smoothing is a control-bus-domain concern entirely internal to the engine; Python only ever sends the raw target value, same as BPM |
| Master volume gain (GUI-03) | Client (Python sends `/pp/volume`) | Engine (`\ppMaster`'s volume arg + its own `Lag.kr`) | Same split as BPM: client is source of truth for intent, engine executes safely (smoothing, clamping, pre-limiter placement) |
| No-clip guarantee at max EPIC + max volume (success criterion 4) | Engine (existing `Limiter.ar` on `\ppMaster`, unchanged) | — | Already-built safety net (ENG-02); Phase 3 must route everything new *through* it, not invent a new one |

## Standard Stack

No new runtime dependencies this phase — this is a SuperCollider-DSP-and-Tkinter-widgets phase, same two-process stack as Phase 1/2.

| Library | Version | Still Current? |
|---------|---------|-----------------|
| SuperCollider | 3.14.1 | Yes — `Lag`, `VarLag`, `FreeVerb`, `RLPF`, `.softclip`/`.distort`, `Bus.control`, `Group.after` are all long-standing stock classes/UGens/methods, no version-specific concern `[VERIFIED: doc.sccode.org/Classes/Lag.html, VarLag.html, FreeVerb.html — fetched this session]` |
| Python | 3.13.12 (Homebrew) | Yes — unchanged venv |
| python-osc | 1.10.2 | Yes — Phase 3's two new `send_message` calls need nothing beyond what `send_bpm`/`send_play` already use |
| Tkinter | stdlib, Tk 9.0.3 | Yes — Phase 3 adds `Button`s (zone presets) and one more `Scale` (volume), both widget types already used in `view.py` |

### Alternatives Considered

| Instead of | Could use | Tradeoff |
|------------|-----------|----------|
| `Lag.kr` (exponential smoothing) for the EPIC conductor value | `VarLag.kr` with a non-default `warp` (e.g. `\sine` or `\welch`) | `VarLag` offers shaped (non-exponential) curves `[CITED: doc.sccode.org/Classes/VarLag.html — "Similar to Lag but with other curve shapes than exponential... warp: step, linear, exponential, sine, welch, squared, or cubed"]`. Use it only if a listening test finds `Lag`'s exponential "snap-then-settle" character wrong for a zone change; `Lag` is the simpler default and is what Phase 2's tempo-ramp research already treated as the baseline choice for "smooth, predictable, easy to debug." |
| One shared `Lag.kr` smoother synth + one shared smoothed bus | Independent `Lag.kr` inside each of N FX-parameter-consuming synths | Functionally equivalent *if* every consumer uses the identical lag time and reads the identical raw input — but that duplicates the lag computation N times and is a classic place for one consumer's lag time to silently drift from another's during a later edit, breaking "all moving together." The one-FX-synth design sidesteps this by having only one `Lag.kr` in the whole engine. |
| `FreeVerb.ar` for reverb/delay | `GVerb.ar`, or a `CombL.ar`/`PingPong.ar` delay in addition to reverb | `FreeVerb` is cheaper (fewer internal comb/allpass stages than `GVerb`) and is a single UGen covering the requirement's "reverb/delay amount" as one knob — appropriate given Phase 2's established CPU-budget concern (Pitfall 4, "keep FX light, don't compete with Zwift"). A true additional delay line is an easy future addition (same wet-bus pattern) but not needed to satisfy the literal requirement text. |
| `.softclip` for drive/saturation | `.distort`, `Shaper.ar` with a wavetable, analog-modeled distortion (e.g. community `analogcurve` UGen) | `.softclip` and `.distort` are both stock `Signal`/UGen methods `[CITED: sc-users mailing list thread "distortion"; doc.sccode.org Tour_of_UGens.html]` — simplest, cheapest, no table-building or external UGen. A wavetable `Shaper` gives more tonal control but is unnecessary complexity for an MVP "drive" knob. |
| `tk.Button` with manual `relief` toggling for the 5 zone buttons | `tk.Radiobutton` (built-in mutually-exclusive selection) | `Radiobutton` gives "only one selected" semantics for free, but renders with a different visual language (radio dot) than the project's existing `Button`-only aesthetic (nudge buttons, Start/Stop). Manual highlighting (same technique already used for `PLAY_LABELS` state swap) keeps visual consistency with the rest of the compact window. |

**Installation:** None — no new packages, no new quarks (CLAUDE.md "No quarks" constraint — `Lag`/`VarLag`/`FreeVerb`/`RLPF`/`.softclip` are all stock SuperCollider, confirmed this session).

## Package Legitimacy Audit

**Not applicable this phase.** No new external packages (Python or SuperCollider quark) are introduced — same as Phase 2. `python-osc` 1.10.2 is already audited in `01-RESEARCH.md`.

## Architecture Patterns

### System Architecture Diagram

```
┌────────────────────────── Python process (new EpicController, VolumeController) ───────────────────────┐
│                                                                                                            │
│  BpmWindow (existing)                NEW: 5 zone buttons             NEW: Volume Scale                  │
│    slider/entry/nudge → BpmController    [Recovery|Endurance|Tempo|Threshold|VO2]  drag → live display    │
│    (unchanged)                            click → EpicController.select_zone(name)   release → send       │
│                                              │ (no debounce — discrete click,            │ (D-20 pattern:  │
│                                              │  mirrors PlayController)                   │  send on       │
│                                              ▼                                             │  release only) │
│                                   SimpleUDPClient.send_message("/pp/epic", zone_value)      ▼               │
│                                                                                   send_message("/pp/volume")│
└──────────────────────────────────────────┬───────────────────────────────────────┬───────────────────────┘
                                             │ UDP localhost:57120 (same contract as /pp/bpm, /pp/play)      │
┌────────────────────────────────────────── ▼ ───────────────────────────────────── ▼ ───────────────────────┐
│                     SuperCollider process — main.scd, inside s.waitForBoot (unchanged gate)                  │
│                                                                                                                │
│  OSCdef(\pp_epic) ── clamp 0-100 ── ~epic = raw ── ~ppEpicBus.set(~epic/100)                                  │
│  OSCdef(\pp_volume) ── clamp 0-100 ── ~volume = raw ── ~ppVolumeBus.set(~volume/100)                          │
│                                                                                                                │
│  ~ppEpicBus (raw, instant) ──▶ ~ppEpicSmoother Synth (Lag.kr, ~1.5s) ──▶ ~ppEpicSmoothBus (smoothed)          │
│                                 (head of ~ppFxGroup — MUST execute before \ppFx reads it, same control block) │
│                                                                      │                                        │
│  ~ppInstrGroup (unchanged, Phase 2 groove) ──▶ ~ppMixBus ──▶ ~ppFxGroup: Synth(\ppFx) ──▶ ~ppFxBus           │
│                                                                 reads ~ppEpicSmoothBus, derives:               │
│                                                                   drive (softclip) → filter (RLPF) →          │
│                                                                   richness (HF exciter blend) → reverb (FreeVerb) │
│                                                                                                                │
│  ~ppMasterGroup (after ~ppFxGroup, was after ~ppInstrGroup) ──▶ Synth(\ppMaster):                            │
│     reads ~ppFxBus (was ~ppMixBus) * preGain * Lag.kr(~ppVolumeBus, 0.2s) ──▶ Limiter.ar(., 0.891251, 0.01) │
│     ──▶ Out.ar(0, .)   [UNCHANGED safety net — this is what guarantees no clipping at max EPIC + max volume] │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

No new files required — same single-`main.scd` / same `python_app/` flat layout Phase 1/2 already use (both phases explicitly kept one `.scd` file and extended `bpm_logic.py` in place rather than splitting). Phase 3 follows the same precedent:

```
supercollider/
└── main.scd            # extended: +2 buses (~ppEpicBus/~ppEpicSmoothBus), +1 bus (~ppFxBus), +1 bus (~ppVolumeBus),
                         #   +1 Group (~ppFxGroup), +2 SynthDefs (\ppEpicSmoother, \ppFx), \ppMaster gets volumeBus arg,
                         #   +2 OSCdefs (/pp/epic, /pp/volume), teardown block extended to free all of the above

python_app/
├── bpm_logic.py          # extended: +EpicController, +VolumeController (sibling classes, same file as BpmController/PlayController)
├── config.py             # extended: +OSC_EPIC_ADDRESS, +OSC_VOLUME_ADDRESS, +EPIC_ZONES dict, +EPIC/VOLUME min/max/default
├── osc_client.py         # extended: +send_epic, +send_volume (same try/except-OSError shape as send_bpm/send_play)
├── view.py               # extended: +zone button row, +volume Scale row
└── tests/
    ├── test_bpm_logic.py     # unchanged
    ├── test_play_logic.py    # unchanged
    ├── test_epic_logic.py    # NEW — mirrors test_play_logic.py's style
    ├── test_volume_logic.py  # NEW — mirrors test_bpm_logic.py's style (has a slider + clamp)
    ├── test_osc_client.py    # extended with send_epic/send_volume tests
    └── test_view_tk.py       # extended with zone-button-highlight and volume-slider tests
```

### Pattern 1: Shared EPIC conductor value + single smoothing stage (EPIC-02)

**What:** The raw EPIC value (`~epic`, 0–100) is written **instantly** by `OSCdef(\pp_epic)` into a raw control bus (`~ppEpicBus`, normalized 0–1) — exactly like `~bpm`/`~ppPlaying` are written instantly by their own OSCdefs today. A single, always-running `SynthDef(\ppEpicSmoother)` continuously reads that raw bus through `Lag.kr` and writes the result into a second control bus (`~ppEpicSmoothBus`). Every DSP consumer of "the current EPIC level" (just one consumer in this phase's design — see Pattern 2) reads **only** the smoothed bus, never the raw one. This is the control-bus analogue of Phase 2's Pattern 1 (ramp stepper reads a mutable target, steps toward it) — here the "stepping" is delegated entirely to the `Lag` UGen's built-in exponential convergence instead of a hand-rolled `Routine`, because the quantity being smoothed is a continuous audio/control-rate parameter, not a musical-time tempo.

**Why one smoother synth, not N independent `Lag.kr`s:** If `\ppFx`'s cutoff-deriving and drive-deriving and reverb-deriving computations each ran their own `Lag.kr(In.kr(rawBus), lagTime)`, they would track the raw input identically *only if every lag time is kept in sync* — a maintenance hazard (Alternatives Considered). Centralizing the lag into one synth, one bus, makes "all four parameters glide in lockstep" true by construction, not by discipline.

**Grounding** `[VERIFIED: doc.sccode.org/Classes/Lag.html, fetched this session]`: "Lag is essentially the same as OnePole except that instead of supplying the coefficient directly, it is calculated from a 60 dB lag time," smoothing "using exponential decay, converging to within 0.01% of a target value over the specified lag time." Confirmed as a stock core UGen (not a plugin/quark).

**Example:**
```supercollider
// New buses (added to the bus-creation block, alongside ~ppMixBus):
~ppEpicBus = Bus.control(s, 1);        // raw, written instantly by OSCdef
~ppEpicSmoothBus = Bus.control(s, 1);  // lagged -- every FX consumer reads THIS one

~ppEpicLagSecs = 1.5;  // Claude's Discretion default -- see Gray Areas

SynthDef(\ppEpicSmoother, { |in, out|
    Out.kr(out, Lag.kr(In.kr(in), ~ppEpicLagSecs));
}).add;

// Instantiated once, at the HEAD of ~ppFxGroup -- see Pattern 2's ordering note
// for why this must execute before \ppFx in the same control block.
~ppEpicSmoother = Synth(\ppEpicSmoother,
    [\in, ~ppEpicBus.index, \out, ~ppEpicSmoothBus.index],
    ~ppFxGroup, addAction: \addToHead);

~epic = ~epic ? 10;  // Gray Areas: default = Recovery zone's value
~ppEpicBus.set(~epic.linlin(0, 100, 0, 1));

OSCdef(\pp_epic, { |msg|
    var raw = msg[1];
    if (raw.isNumber.not or: { raw.isNaN }) {
        "PedalPulse WARNING: ignoring /pp/epic with invalid argument %".format(raw).postln;
    } {
        ~epic = raw.asFloat.clip(0, 100);
        ~ppEpicBus.set(~epic.linlin(0, 100, 0, 1));
        "PedalPulse: /pp/epic % -> %".format(raw, ~epic).postln;
    };
}, '/pp/epic', srcID: NetAddr("127.0.0.1", nil));
```

### Pattern 2: Single FX synth deriving filter/drive/reverb/richness from one smoothed value (EPIC-01)

**What:** One new persistent `SynthDef(\ppFx)`, instantiated once (not per-note, unlike the kick/hat/bass/arp/pad voices), sitting in a new `~ppFxGroup` between the existing instrument group and the existing master group. It reads the **already-mixed** instrument signal from `~ppMixBus` (unchanged — instruments keep writing here exactly as Phase 2 built them), applies drive → filter → richness-exciter → reverb in series, and writes the result to a new `~ppFxBus`, which `\ppMaster` now reads instead of `~ppMixBus`.

**Bus-index-as-plain-control-arg idiom (reused, not invented):** `\ppFx`'s `epicBus` argument is a plain number (the smoothed bus's `.index`), used directly inside `In.kr(epicBus)`. This is not a new technique — it is the exact mechanism already proven working in this codebase's own `\ppMaster` SynthDef, read this session: `[VERIFIED: supercollider/main.scd:93-96]`, quoted verbatim:
```
SynthDef(\ppMaster, { |in, out = 0, preGain = 1|
	var sig = In.ar(in, 2) * preGain;
	Out.ar(out, Limiter.ar(sig, 0.891251, 0.01));  // D-16: -1 dBFS = 10^(-1/20) ~= 0.891251
}).add;
```
`in` here is a plain control arg whose *value* (set once at `Synth.new` time to `~ppMixBus`'s index) is used directly as the bus index for `In.ar`. `\ppFx`'s `epicBus` arg does the identical thing for `In.kr`.

**Why one combined synth instead of per-instrument EPIC wiring:** Modifying all six existing instrument `SynthDef`s to each accept and react to an EPIC-derived "richness" argument would touch every voice built in Phase 2 (regression risk) and raise the CPU floor even at EPIC=0 (violates Phase 2's own Pitfall 4, "keep FX light... deferring anything CPU-heavier to when EPIC's lagged-parameter system exists to justify it" — which is precisely now, but still argues for *adding* cost proportionally to EPIC, not as a fixed per-voice tax). Folding all four EPIC-driven effects into one new post-mix synth means: zero changes to the six existing `SynthDef`s, CPU cost that scales with the signal already flowing through one bus (not six), and the "all four move together" guarantee is automatic (one input, one synth, one UGen graph).

**Grounding for the UGens used** — all confirmed stock/core this session:
- `.softclip` (drive/saturation): `[CITED: sc-users mailing list "distortion" thread; doc.sccode.org Tour_of_UGens.html]` — a `Signal`/UGen method; "drive (pre-gain) can be combined with softclip processing," the standard idiom being `(sig * drive).softclip`.
- `RLPF.ar` (filter cutoff): already a stock UGen used by Phase 2's `\ppBass` (`RLPF.ar(sig, 700, 0.6)`, `[VERIFIED: supercollider/main.scd:65]`) — reusing the exact same filter class keeps tonal character consistent with the existing bass voice.
- `FreeVerb.ar` (reverb/delay amount): `[VERIFIED: doc.sccode.org/Classes/FreeVerb.html, fetched this session]` — "ships with the standard SuperCollider 3.14.0 installation," arguments `in, mix (0-1), room (0-1), damp (0-1)`.
- "Synth richness" as a high-frequency exciter blend: this is a **design interpretation**, not a sourced technique — the requirement does not define "richness" precisely and no prior-phase decision does either. The recommended MVP reading: blend in a proportionally-louder high-pass-filtered copy of the already-processed signal (`sig + (HPF.ar(sig, 3500) * richness * 0.35)`), which reads as "gets more harmonically present/brighter" as EPIC rises, cheaply (no new oscillators, no per-voice changes) and automatically synchronized with the rest of the chain (same smoothed `epic` value). Flagged as a gray area — see below — with an alternative (per-voice detune/extra-oscillator richness) noted for future polish.

**Example:**
```supercollider
SynthDef(\ppFx, { |in, out, epicBus = 0|
	var sig = In.ar(in, 2);
	var epic = In.kr(epicBus);  // already Lag'd by ~ppEpicSmoother -- 0..1
	var drive = epic.linlin(0, 1, 1.0, 3.5);
	var cutoff = epic.linexp(0, 1, 500, 9000);
	var richness = epic;
	var wet = epic.linlin(0, 1, 0.08, 0.35);

	sig = (sig * drive).softclip;
	sig = RLPF.ar(sig, cutoff, 0.5);
	sig = sig + (HPF.ar(sig, 3500) * richness * 0.35);
	sig = FreeVerb.ar(sig, wet, room: 0.6, damp: 0.3);
	Out.ar(out, sig);
}).add;

~ppFxSynth = Synth(\ppFx,
    [\in, ~ppMixBus.index, \out, ~ppFxBus.index, \epicBus, ~ppEpicSmoothBus.index],
    ~ppFxGroup);  // added AFTER ~ppEpicSmoother within the same group (see ordering note below)
```

**Node-order correctness note:** `~ppEpicSmoother` must execute before `\ppFx` **within the same control block** so `\ppFx`'s `In.kr(epicBus)` read sees that block's freshly-written value, not the previous block's — `addAction: \addToHead` on the smoother plus creating `\ppFx` normally (added after it, i.e. toward the group's tail) guarantees this ordering `[CITED: doc.sccode.org/Guides/Order-of-execution.html — "if one synth node is processing the output of another, the processing node (the effect) has to come later in the execution chain than the source"]`. Getting this backwards does not break anything audibly (the smoothed value would simply lag by one control block, ~1ms at the default block size — inaudible) but is worth setting up correctly for clarity and to avoid confusion when debugging.

### Pattern 3: Zone presets as a pure Python-side mapping (EPIC-03)

**What:** The engine never learns zone names — it only ever receives a numeric `/pp/epic <float 0-100>`, exactly as it only ever receives numeric `/pp/bpm`. `EpicController` (new, `bpm_logic.py`) tracks the **currently selected zone name** (for the GUI's own button-highlight state) and a `config.EPIC_ZONES` dict maps each name to its preset numeric value. Structurally this mirrors `PlayController` almost exactly: a controller with discrete, immediate (non-debounced) actions, "notify listeners only on an actual change," and a `send_initial()` for launch-time sync — the same shape already proven for GUI-02's Start/Stop.

**Example** (new code in `python_app/bpm_logic.py`, alongside `PlayController`):
```python
class EpicController:
    """Tracks the selected EPIC zone and sends its preset value (EPIC-03).

    Mirrors PlayController's shape: track state, notify listeners on an
    actual change, send immediately (no debounce -- a zone click is a
    single discrete action, not a drag).
    """

    def __init__(
        self,
        send: Callable[[float], object],
        zones: dict[str, float],
        initial_zone: str,
    ) -> None:
        self._send = send
        self._zones = zones
        self._zone = initial_zone
        self._listeners: list[Callable[[str], None]] = []

    @property
    def zone(self) -> str:
        return self._zone

    @property
    def value(self) -> float:
        return self._zones[self._zone]

    def add_listener(self, fn: Callable[[str], None]) -> None:
        self._listeners.append(fn)

    def _notify(self) -> None:
        for listener in self._listeners:
            listener(self._zone)

    def select_zone(self, zone_name: str) -> None:
        if zone_name == self._zone:
            return  # idempotent, same spirit as BpmController._set/PlayController.set_playing
        self._zone = zone_name
        self._notify()
        self._send(float(self._zones[zone_name]))

    def send_initial(self) -> None:
        """Send the current zone's value once, unconditionally (D-23 philosophy)."""
        self._send(float(self._zones[self._zone]))
```
`config.py` additions:
```python
OSC_EPIC_ADDRESS = "/pp/epic"
EPIC_ZONES = {
    "Recovery": 10,
    "Endurance": 30,
    "Tempo": 50,
    "Threshold": 75,
    "VO2": 100,
}
EPIC_DEFAULT_ZONE = "Recovery"
```
`OscClient` gets one new method, `send_epic(self, epic: float) -> bool`, identical try/except-OSError shape to `send_bpm` `[VERIFIED: python_app/osc_client.py:35-48, this session]`, quoted verbatim for the shape being mirrored:
```python
    def send_bpm(self, bpm: float) -> bool:
        try:
            self._client.send_message(config.OSC_BPM_ADDRESS, float(bpm))
        except OSError as exc:
            print(f"OscClient: failed to send /pp/bpm {bpm} to {self.target}: {exc}", file=sys.stderr)
            return False
        return True
```

### Pattern 4: Volume slider mirrors BpmController's slider-release-send shape (GUI-03)

**What:** Volume is a continuously-draggable control (a `Scale`, like BPM), so it inherits the exact same flooding risk Pitfall 6 (project PITFALLS.md) already documents for BPM — and the exact same fix Phase 1 already built (D-20: live display while dragging, one send on release). Rather than inventing a new debounce mechanism, `VolumeController` should structurally mirror `BpmController`'s `slider_moved`/`slider_released`/`send_initial` shape (it does not need `BpmController`'s nudge-button debounce machinery, since Phase 3 does not specify nudge buttons for volume — only a slider, per GUI-03's plain wording "adjust master volume").

**Example:**
```python
def clamp_volume(value: float) -> int:
    """Same half-up-round-then-clamp contract as clamp_bpm, 0..100 range."""
    if not math.isfinite(value):
        raise ValueError(f"clamp_volume: value must be finite, got {value!r}")
    rounded = int(math.floor(value + 0.5))
    return max(config.VOLUME_MIN, min(config.VOLUME_MAX, rounded))


class VolumeController:
    """Tracks master volume (GUI-03); mirrors BpmController's slider shape.

    No nudge buttons, no entry field -- just drag-live/send-on-release,
    same D-20 pattern BpmController's Scale already uses.
    """

    def __init__(
        self,
        send: Callable[[float], object],
        initial: int = config.VOLUME_DEFAULT,
    ) -> None:
        self._send = send
        self._value = clamp_volume(initial)
        self._listeners: list[Callable[[int], None]] = []

    @property
    def value(self) -> int:
        return self._value

    def add_listener(self, fn: Callable[[int], None]) -> None:
        self._listeners.append(fn)

    def _notify(self) -> None:
        for listener in self._listeners:
            listener(self._value)

    def _set(self, new_value: int) -> bool:
        if new_value == self._value:
            return False
        self._value = new_value
        self._notify()
        return True

    def slider_moved(self, raw: str | float) -> None:
        """Live update while dragging. Never sends (same D-20 rule as BPM)."""
        self._set(clamp_volume(float(raw)))

    def slider_released(self) -> None:
        self._send(float(self._value))

    def send_initial(self) -> None:
        self._send(float(self._value))
```
`config.py` additions: `OSC_VOLUME_ADDRESS = "/pp/volume"`, `VOLUME_MIN = 0`, `VOLUME_MAX = 100`, `VOLUME_DEFAULT = 80` (Gray Areas). `OscClient.send_volume` mirrors `send_bpm`/`send_epic` exactly.

**Don't-hand-roll note:** `clamp_bpm`/`clamp_volume` share identical logic (half-up round, then clamp to a `[min, max]`) — the planner may choose to generalize both into one `clamp_to_range(value, lo, hi)` helper rather than duplicating the floor-plus-0.5 rounding idiom a third time. This is a refactor-or-duplicate judgment call, not a correctness requirement — flagged under Gray Areas.

### Pattern 5: Volume as a pre-limiter gain stage, never a bypass (GUI-03 + success criterion 4)

**What:** Volume is applied **inside** `\ppMaster`, multiplied into the signal exactly where `preGain` already is, and **before** the existing `Limiter.ar` call — never as a separate `Synth` after the limiter, and never by scaling hardware output level outside SuperCollider. This is what makes "max EPIC + max volume never clips" true for free: the limiter is already proven (ENG-02, complete) to hold its ceiling regardless of what feeds it; Phase 3's job is only to make sure volume (and the new FX chain's drive/richness) feed **into** that same limiter, not around it.

**Example:**
```supercollider
SynthDef(\ppMaster, { |in, out = 0, preGain = 1, volumeBus = 0|
	var volume = Lag.kr(In.kr(volumeBus), 0.2);  // short lag: de-zippers nudges, doesn't need EPIC's slow "zone glide" feel
	var sig = In.ar(in, 2) * preGain * volume;
	Out.ar(out, Limiter.ar(sig, 0.891251, 0.01));  // D-16, UNCHANGED
}).add;

~ppMasterSynth = Synth(\ppMaster,
    [\in, ~ppFxBus.index, \out, 0, \preGain, ~preGain, \volumeBus, ~ppVolumeBus.index],
    ~ppMasterGroup);  // \in is now ~ppFxBus, was ~ppMixBus
```
0.2s was chosen deliberately shorter than EPIC's ~1.5s: volume is a direct physical-feeling "turn it up/down" control (DJ-mixer-style instant response expected), whereas EPIC's lag is a deliberate musical "the energy builds" effect — these are different UX intents even though both use `Lag.kr`, so they should not share one lag-time constant. Flagged as a gray area below.

### Anti-Patterns to Avoid

- **Giving each FX parameter (cutoff, drive, reverb mix) its own independent `Lag.kr` inside separate synths:** breaks the "all move together" guarantee the moment lag times drift apart during a future edit (Pattern 1's rationale). Use one shared smoother synth and one shared smoothed bus.
- **Applying volume or EPIC-driven drive *after* the `Limiter.ar` call, or in a separate `Synth` placed after `~ppMasterGroup`:** defeats the entire no-clip guarantee — the limiter can only protect what passes through it.
- **Reading `~ppMixBus` directly in `\ppMaster` (forgetting to re-point it at `~ppFxBus`):** silently makes the entire new FX chain inaudible (instruments still play, but nothing EPIC-related is heard) while every automated check that only inspects `~epic`/`~ppEpicBus` would still pass — a classic "looks done but isn't."
- **Forgetting to add the new bus/group/synth to the existing re-evaluation teardown block:** Phase 1/2's `s.waitForBoot` block starts with an explicit free-everything-then-rebuild sequence, read this session `[VERIFIED: supercollider/main.scd:33-45]`, quoted: `"""if (~ppMasterSynth.notNil) { ~ppMasterSynth.free }; if (~ppMasterGroup.notNil) { ~ppMasterGroup.free }; if (~ppInstrGroup.notNil) { ~ppInstrGroup.free }; if (~ppMixBus.notNil) { ~ppMixBus.free };"""`. Every new Phase 3 object (`~ppFxSynth`, `~ppEpicSmoother`, `~ppFxGroup`, `~ppFxBus`, `~ppEpicBus`, `~ppEpicSmoothBus`, `~ppVolumeBus`) must be added to this same guarded-free sequence, in dependency order (free synths that *read* a bus before freeing the bus itself), or every live-coding re-evaluation leaks one more copy of each.
- **Modifying the six existing instrument `SynthDef`s to add EPIC-reactive controls:** unnecessary regression risk to Phase 2's proven groove and raises the CPU floor at EPIC=0 (Pattern 2's rationale) — keep all new EPIC-driven DSP in the one new `\ppFx` synth.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Smoothing a control value to avoid zipper noise/stepping | A manual per-block interpolation `Routine`/stepper (Phase 2's tempo-ramp style hand-rolled stepper) | `Lag.kr`/`VarLag.kr` | This is a solved, built-in UGen problem for *continuous audio/control-rate* parameters — unlike tempo (which is inherently beat-relative and needs the `Routine`-on-the-clock idiom), EPIC's FX parameters are plain control-rate values with no musical-time dependency, so the stock smoothing UGen is strictly simpler and cheaper than reimplementing Phase 2's Pattern 1 for a different domain |
| Reverb/delay effect | A hand-written comb-filter/allpass reverb network | `FreeVerb.ar` | Stock, well-tuned, one line `[VERIFIED: doc.sccode.org/Classes/FreeVerb.html]` — no reason to reimplement Schroeder/Moorer reverb topology for a personal workout tool |
| Drive/saturation | A custom waveshaping table or polynomial distortion curve | `.softclip`/`.distort` | Both are stock `Signal`/UGen methods `[CITED: doc.sccode.org Tour_of_UGens.html]` — a hand-built Chebyshev waveshaper is the kind of thing worth doing only if a specific tonal character is being chased, not for an MVP "drive" knob |
| Zone-name → numeric-value mapping and "which zone is currently selected" state | A new engine-side concept of "zones" (e.g. an `OSCdef` per zone name) | A plain Python `dict` (`config.EPIC_ZONES`) read entirely client-side, sending the already-resolved number over the existing `/pp/epic` address | The engine already has exactly the numeric interface it needs (0-100 EPIC); adding zone-awareness engine-side would duplicate business logic across two languages/processes for no benefit — same "client decides intent, engine just executes" split Phase 2 already used for Start/Stop |
| Debouncing a continuously-dragged volume slider | A new ad-hoc timer/threshold mechanism | The existing D-20 "live display + send-on-`ButtonRelease-1`" pattern already proven for the BPM `Scale` | Exact same widget type, exact same flooding risk (Pitfall 6), exact same fix — no reason to design a second debounce strategy |

**Key insight:** Every new engine-side mechanic Phase 3 needs (smoothed control propagation, a reverb/drive FX chain, pre-limiter gain staging) is a stock SuperCollider UGen or a direct composition of Phase 1/2's own already-proven idioms (bus-index-as-control-arg, guarded re-evaluation teardown, conductor-var-written-only-by-OSCdef). The only genuinely new code is: one small FX `SynthDef`, one smoother `SynthDef`, two new `OSCdef`s, and the Python-side mirror-pattern controllers — no new infrastructure category, same shape as Phase 2's own summary.

## Common Pitfalls

### Pitfall 1: Volume or drive bypassing the limiter (re-clipping risk)

**What goes wrong:** If volume is applied as a separate gain `Synth` placed *after* `~ppMasterGroup` (post-limiter), or if the FX synth's drive stage is tuned so aggressively that `.softclip`'s own internal clipping produces inter-sample peaks the *existing* limiter's lookahead window (0.01s, D-16) doesn't fully catch at extreme settings, the "never clips" guarantee (success criterion 4) can be silently violated even though the code "looks like" it goes through the limiter.
**Why it happens:** It's tempting to add volume as "just one more `Synth.new` in the chain" without checking its position relative to `~ppMasterGroup`, since `Group.after`/`Group.before` ordering mistakes compile and run without error — the bug is audible only at max settings, which (per project PITFALLS.md Pitfall 5) are exactly the least-tested states during casual development.
**How to avoid:** Volume lives *inside* `\ppMaster`, pre-`Limiter.ar` (Pattern 5) — not a separate synth, not a separate group. Explicitly test the worst case (EPIC=100 + volume=100) with the smoke test's existing `measurePeak` helper (see Validation Architecture) before calling this phase done, not just a moderate-settings spot check.
**Warning signs:** Harsh distortion or a visibly pinned meter specifically at max EPIC + max volume, but clean at moderate settings.

### Pitfall 2: Forgetting to extend the re-evaluation teardown block for new objects

**What goes wrong:** Every live-coding re-evaluation of `main.scd` (the D-17 "edit a var, re-evaluate" workflow this project relies on for iteration) frees and rebuilds the full signal chain — but only for objects the teardown block explicitly knows about. If `~ppFxGroup`/`~ppFxBus`/`~ppEpicBus`/`~ppEpicSmoothBus`/`~ppVolumeBus`/`~ppFxSynth`/`~ppEpicSmoother` are not added to the guarded-free sequence at the top of the file, each re-evaluation leaves the previous copies running (same category of bug Pitfall 4 in Phase 2's research already flagged for node leaks, now at the bus/group level instead of per-note).
**Why it happens:** The existing teardown block (`supercollider/main.scd:33-45`) was written before these objects existed; it is easy to add the *creation* code for a new bus/group without remembering to add the matching *teardown* line, since the file compiles and runs fine either way on the very next re-evaluation (the bug only compounds over *multiple* re-evaluations).
**How to avoid:** Add every new Phase 3 object to the existing `if (X.notNil) { X.free }` sequence, in dependency order — free `~ppFxSynth`/`~ppEpicSmoother` before `~ppFxGroup`/the buses they read, exactly mirroring how `~ppMasterSynth` is freed before `~ppMasterGroup` is freed before `~ppMixBus` is freed today.
**Warning signs:** `s.numSynths`/bus-allocation creeping upward across repeated manual re-evaluations during development (not during a single run — this is specifically a live-coding-workflow bug).

### Pitfall 3: FX synth reading the wrong bus (silently inaudible EPIC changes)

**What goes wrong:** If `\ppMaster`'s `in` control arg is left pointing at `~ppMixBus` (forgotten to update to `~ppFxBus`), the instruments still play correctly and the engine still boots and runs — but every EPIC change becomes completely inaudible, because the signal path `\ppFx` writes to is never read by anything. This is exactly the kind of bug that would pass a casual "does the engine still boot and play" smoke test while failing the actual requirement.
**Why it happens:** Two bus variables (`~ppMixBus`, `~ppFxBus`) with similar names and purposes, one small `\in` argument change easy to miss in a larger diff.
**How to avoid:** The smoke test must specifically assert that changing `/pp/epic` produces a *measurable* change somewhere in the post-FX signal (e.g., spectral centroid or peak level shift when EPIC jumps from 0 to 100 with a holding test tone/noise through the chain) — not just that the OSCdef updates `~epic` and the bus value. See Validation Architecture.
**Warning signs:** `~epic`/`~ppEpicBus` updates correctly (observable in sclang), but the music sounds identical regardless of EPIC/zone selection.

### Pitfall 4: WR-01 (arrow-key BPM nudge while entry has focus) compounding with new controls

**What goes wrong:** STATE.md explicitly flags this as "fix before adding more GUI controls in Phase 3" — the existing bug (`python_app/view.py:115-118`, Up/Down arrow keys nudge BPM even while the BPM entry field has focus, discarding half-typed text) gets worse, not better, once more widgets exist in the same window: a zone button or the volume slider receiving focus could interact with the same root-level `<Up>`/`<Down>` bindings in ways not yet tested, since those shortcuts were bound on `root`, not on the BPM `Scale` specifically — `[VERIFIED: python_app/view.py:140-143]`, quoted: `"""self.root.bind("<Up>", lambda _event: self.handle_nudge_key(1)); ... self.root.bind("<Shift-Down>", lambda _event: self.handle_nudge_key(-5));"""`.
**Why it happens:** `root.bind` is global to the whole window regardless of which widget has focus; adding new focusable widgets (the volume `Scale`, if it does not set `takefocus=0` like the BPM `Scale` does) expands the surface area where this interacts unexpectedly.
**How to avoid:** Give the new volume `Scale` the same `takefocus=0` the BPM `Scale` already uses (`[VERIFIED: python_app/view.py:55]`: `"""takefocus=0,"""` on the BPM `Scale`'s constructor), so the arrow-key shortcuts' meaning stays unambiguous; separately, fix WR-01 itself (the entry-focus guard) as part of this phase's work per STATE.md's explicit flag, rather than deferring it again.
**Warning signs:** Typing a BPM value, then clicking a zone button, produces an unexpected BPM nudge; pressing arrow keys while the volume slider has focus does something other than what's expected for volume.

### Pitfall 5: CPU growth from an always-on FX chain (carries Phase 2's Pitfall 4 forward)

**What goes wrong:** `FreeVerb.ar` and a filter are now running continuously on the full mix, every second of every session, not just during note attacks — unlike the per-note instrument synths (which only cost CPU while actually sounding), this new FX synth is a constant tax from boot to shutdown. Combined with the project's platform constraint (must not disturb Zwift), an unnecessarily expensive `FreeVerb` configuration (e.g. very large room size with heavy damping computation, or running it in true stereo with unnecessarily high internal buffer sizes) could measurably raise baseline CPU.
**Why it happens:** Reverb UGens are among the more CPU-expensive stock UGens relative to a bare filter; it's easy to not notice the baseline cost increase in a short manual listen.
**How to avoid:** One shared `FreeVerb.ar` instance (not per-voice, not per-layer) — already the design in Pattern 2. Confirm with a quick `s.avgCPU`/`s.peakCPU` comparison before/after this phase, same spirit as Phase 2's own Pitfall 4 recommendation, though a dedicated 60-minute soak test is explicitly Phase 4's job (ENG-03).
**Warning signs:** Noticeably higher `s.avgCPU` than Phase 2's baseline even at EPIC=0 (the FX synth runs constantly regardless of EPIC value, so its *baseline* cost, not just its peak cost, matters).

## Gray Areas Needing a Default

**No CONTEXT.md exists for this phase.** Each gray area below has a concrete recommended default so the planner isn't blocked; treat each as **provisional**, not locked.

| Gray area | Recommended default | Rationale | Reversibility |
|-----------|---------------------|-----------|----------------|
| Zone → EPIC value mapping | Recovery=10, Endurance=30, Tempo=50, Threshold=75, VO2=100 | Five roughly-evenly-spaced points spanning the full 0–100 range, with VO2 deliberately at the maximum (so "max EPIC + max volume never clips" — success criterion 4 — is tested at a value a real zone button actually produces, not an arbitrary edge case) | Easy — a Python `dict` literal, no engine-side change needed |
| Default boot/launch EPIC value | 10 (Recovery) | Mirrors D-15's "safe, low-energy" autostart philosophy — a rider should not be greeted by VO2-level intensity before they've chosen anything; matches the natural "warm up, then build" workout arc the project's own FEATURES.md research notes elsewhere | Easy — one default constant in two places (Python `EPIC_DEFAULT_ZONE`, engine `~epic = ~epic ? 10`) |
| Default/max volume value and GUI range | 0–100 GUI scale, default 80, linear mapping to 0.0–1.0 pre-limiter gain | Leaves the limiter doing noticeably less work at the "normal" default than at the explicit max-volume test case, consistent with Pitfall 5 (project PITFALLS.md: "let the limiter be a safety net, not primary leveling") | Easy — one constant; a non-linear (e.g. perceptual/dB-taper) mapping is a drop-in replacement for the `linlin` call if 0–100 feels non-perceptual in testing |
| EPIC smoothing lag time | 1.5s | Long enough to read as a deliberate "the energy builds" transition between zones (not instant, satisfying EPIC-02's "glide smoothly"), short enough that clicking a new zone mid-interval still responds within a few seconds, not tens of seconds | Easy — one named var (`~ppEpicLagSecs`), isolated to the smoother `SynthDef`'s instantiation |
| Volume lag time | 0.2s | Deliberately much shorter than EPIC's — volume is expected to feel like an immediate physical "turn it up" response (DJ-mixer convention), not a musical build; 0.2s is enough only to de-zipper a slider drag's per-block jumps, not to create a perceptible glide | Easy — one literal inside `\ppMaster` |
| "Synth richness" concrete meaning | A high-frequency exciter blend (`sig + HPF.ar(sig, 3500) * richness * 0.35`) applied post-filter, pre-reverb, inside the shared `\ppFx` synth | The requirement text lists "synth richness" as a fourth, distinct knob alongside filter/drive/reverb, but defines it precisely nowhere in the project; an HF-exciter blend is cheap (no new oscillators), automatically synchronized (reads the same smoothed EPIC value), and audibly reads as "gets more present/harmonically rich" as EPIC rises — the MVP-appropriate interpretation given "mvp" mode and the absence of a CONTEXT.md decision | Moderate — changing to a per-voice richness design (e.g., adding a bus-mapped detune/extra-oscillator control to the pad/arp `SynthDef`s specifically, per `PG_06f_Server_Control`'s Bus-as-pattern-value idiom) is a bigger change touching the instrument layer, not just the FX synth |
| FX chain order (drive → filter → richness → reverb) | As listed | Standard analog-signal-chain convention (gain-stage/distortion shapes harmonics, filter then shapes *those* harmonics, reverb is a time-based effect applied last so it doesn't get re-driven/re-filtered) | Easy — reordering four lines inside one `SynthDef` |
| Zone button widget choice | `tk.Button` × 5 with manual `relief` highlight for "selected" | Matches existing `Button`-only visual language (nudge buttons, Start/Stop) better than `tk.Radiobutton`'s different rendering; directly answers Phase 2's own UI review finding #3 ("no visual state feedback") by using `relief` to show the *selected* zone | Easy — swapping to `Radiobutton` later is a view-layer-only change, no controller impact |
| Volume widget choice | A second `tk.Scale`, vertical or horizontal | Reuses the exact BPM-slider interaction pattern (D-20) the user already knows from this same window; a horizontal scale keeps the compact window's existing aspect ratio (D-12) | Easy — pure view-layer choice |
| GUI layout order | BPM slider → nudge row → entry → **zone button row (NEW)** → transport row → **volume row (NEW)** → status label → On-top checkbox | Groups "what sound is playing" (tempo, then energy/zone) before "control" (transport, volume, meta) — a plausible reading order for a rider glancing down mid-interval | Easy — pure layout, no logic impact |
| `VolumeController`/`clamp_volume` vs. generalizing `BpmController`/`clamp_bpm` | Add `VolumeController` as a new sibling class (same precedent as `PlayController` in Phase 2), with its own small `clamp_volume` function | Phase 2 already set the precedent of adding a sibling controller class rather than refactoring `BpmController` into a shared base; consistency with that choice outweighs the minor duplication of the clamp logic | Moderate — generalizing into a shared `clamp_to_range`/base class later is a pure refactor, not a behavior change |

## Runtime State Inventory

Not applicable — Phase 3 is additive (new SynthDefs, new OSCdefs, new buses/groups, new Python controller classes), not a rename/refactor/migration. No existing stored data, service config, OS-registered state, secrets, or build artifacts reference anything being renamed or moved.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A high-frequency-exciter blend is an acceptable MVP interpretation of "synth richness" | Pattern 2, Gray Areas | Medium — this is explicitly a design interpretation, not a sourced requirement; if a listening test finds it doesn't read as "richness," the fix is isolated to the one `\ppFx` SynthDef, not a rearchitecture (flagged as "moderate" reversibility in Gray Areas) |
| A2 | 1.5s is an acceptable default EPIC smoothing lag time, and 0.2s an acceptable volume lag time | Pattern 1, Pattern 5, Gray Areas | Low-Medium — both are isolated named constants with no architectural coupling; STATE.md's own precedent (Phase 2 flagged the tempo-ramp curve shape as needing a listening-test spike) suggests this project already expects a tuning pass after first listen, not a one-shot perfect guess |
| A3 | Zone preset values (10/30/50/75/100) are a reasonable mapping of the five named training zones to a 0-100 EPIC scale | Pattern 3, Gray Areas | Low — purely a Python-side `dict`, trivially re-tunable without touching the engine or any test beyond updating expected values |
| A4 | `Node`/`Group` ordering (`addAction: \addToHead` on the smoother synth within `~ppFxGroup`) is sufficient to guarantee same-control-block read-after-write for the bus hop between `~ppEpicSmoother` and `\ppFx` | Pattern 2 | Low — grounded in the official Order-of-execution guide's documented node-tree traversal semantics; this is the same category of guarantee the existing codebase already relies on implicitly for `~ppInstrGroup` → `~ppMasterGroup` (sound must be mixed before it's limited) |

## Open Questions

1. **Does "synth richness" need to be audibly distinguishable from the filter-cutoff change, or is some perceptual overlap acceptable?**
   - What we know: Both "cutoff" and the recommended "richness" design affect high-frequency content, so they could read as redundant rather than as four independently-perceivable axes.
   - What's unclear: Whether a listening test will find the HF-exciter blend adds a genuinely distinct quality ("more harmonically present") versus just "sounds the same as a brighter filter."
   - Recommendation: Build the MVP default as specified, but treat this as the first thing to listen-test once Phase 3 is running — if redundant, the cheapest fix is widening the gap between the filter's cutoff range and the richness blend's frequency/amount curve (e.g., richness could instead modulate stereo width via `Splay`/detune amount, which is clearly distinct from brightness).

2. **Should the volume control also have GUI-displayed dB or percentage text, given the entry-field precedent BPM already has?**
   - What we know: BPM has slider + numeric entry + nudge buttons (D-06); GUI-03's wording is simply "adjust master volume from the GUI," with no entry-field requirement.
   - What's unclear: Whether a slider-only control (no numeric read-out) is sufficient UX, or whether Phase 2's own UI review precedent (valuing visible state) suggests adding at least a label showing the current percentage.
   - Recommendation: Ship slider-only for MVP (matches the literal requirement wording and keeps parity with "mvp" mode), but add a small text label next to it (e.g., "Volume: 80%") as a low-cost addition, consistent with the BPM window's existing status-line precedent.

## Environment Availability

No new external dependencies this phase — same stack as Phase 1/2 (SuperCollider 3.14.1, Homebrew `python3.13`, Tcl/Tk 9.0.3, `python-osc` 1.10.2, pytest). All new SuperCollider classes/UGens used (`Lag`, `VarLag`, `FreeVerb`, `RLPF`, `.softclip`) were confirmed this session as stock/core (fetched from `doc.sccode.org`), requiring no quark install, consistent with CLAUDE.md's "No quarks" constraint.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | pytest 8.x (already installed in `.venv`) + the existing headless-sclang smoke-test harness (`supercollider/smoke_test.scd`, `scripts/smoke_test.sh`) |
| Config file | none — unchanged from Phase 1/2 |
| Quick run command | `.venv/bin/pytest python_app/tests/ -x -q` |
| Full suite command | `.venv/bin/pytest python_app/tests/ -q && scripts/smoke_test.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| EPIC-01 | `/pp/epic` 0 vs 100 produces a *measurable* change in the post-FX signal (not just that `~epic`/`~ppEpicBus` update) | smoke (headless sclang) | extend `supercollider/smoke_test.scd`: hold a test tone/noise through the instrument layer, probe `~ppFxBus` peak/spectral content at EPIC=0 vs EPIC=100 via the existing `\ppPeakProbe`/`measurePeak` pattern (`[VERIFIED: supercollider/smoke_test.scd:888-896]`), assert a measurable difference (e.g. peak level or a simple `Amplitude`/`FFT`-based brightness probe) | ❌ Wave 0 — extend existing file, reuse existing peak-probe idiom |
| EPIC-02 | EPIC change glides (no instantaneous jump) when a new zone is sent | smoke | extend smoke test: send `/pp/epic 100` from rest, poll `~ppEpicSmoothBus`'s value (via a probe `OSCdef`/`SendReply` reading the control bus) at intervals, assert monotonic convergence over roughly the expected lag window, not an instant jump | ❌ Wave 0 |
| EPIC-03 | Each of the 5 zone names maps to its documented EPIC value and is sent correctly | unit (pure logic, no mocking) | `pytest python_app/tests/test_epic_logic.py -x` | ❌ Wave 0 — new file, same pattern as `test_play_logic.py` |
| EPIC-03 (OSC wire format) | `send_epic` delivers `/pp/epic <float>` correctly | unit (mock socket) | `pytest python_app/tests/test_osc_client.py -x` (extend existing file, same pattern as `send_bpm`/`send_play` tests) | ❌ Wave 0 — extend existing file |
| GUI-03 (Python side) | `VolumeController` sends `/pp/volume` only on release (not on every drag tick), clamps 0-100, `send_initial()` sends once | unit | `pytest python_app/tests/test_volume_logic.py -x` | ❌ Wave 0 — new file, same pattern as `test_bpm_logic.py` |
| GUI-03 (engine side, no-clip) | At `/pp/epic 100` + `/pp/volume 100` (the documented max-EPIC-max-volume zone/value), the master output (`~ppMasterGroup`, bus 0) peak never exceeds the limiter ceiling (0.891251) plus a small tolerance | smoke | extend smoke test: reuse the existing `measurePeak` helper `[VERIFIED: supercollider/smoke_test.scd:888-896, quoted: """measurePeak = { |busIndex, durSec| var probe; peakVal = 0.0; probe = Synth.after(~ppMasterGroup, \ppPeakProbe, [\in, busIndex]); durSec.wait; probe.free; peakVal; };"""]`, send `/pp/epic 100` and `/pp/volume 100`, wait past both lag windows, `measurePeak.(0, 4)`, assert `<= 0.892` | ❌ Wave 0 — extend existing B7-style check |
| EPIC-01/02 "all four parameters moving together," audible brightness/energy change | Whether the combined effect actually *sounds* like "brighter and more energetic" | **manual-only** | Listen while clicking through all 5 zones in sequence, both ascending and descending | n/a — explicitly manual, same split Phase 1/2 used for musical-quality judgments |
| Success criterion 3 ("no stepping, zipper noise or clicks" on zone switch) | Whether the glide actually *sounds* smooth, not just whether `~ppEpicSmoothBus` moves monotonically | **manual-only** | Listen while rapidly clicking between zones, including back-to-back clicks before a prior glide finishes | n/a — explicitly manual; the smoke test proves the mechanism is correct, not that it sounds good |

### Sampling Rate
- **Per task commit:** `.venv/bin/pytest python_app/tests/ -x -q` (quick run)
- **Per wave merge:** full pytest suite + `scripts/smoke_test.sh` (extended) + the two manual listening checks (brightness/energy change, glide smoothness)
- **Phase gate:** Full suite + smoke test green, both manual listening checks performed, before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `supercollider/smoke_test.scd` — extend with: EPIC-produces-measurable-change check, EPIC-glides-not-jumps check, max-EPIC-max-volume-never-clips check (reusing `measurePeak`), teardown-survives-re-evaluation check for the new buses/groups/synths (same style as the existing "re-evaluation" check at the end of the file)
- [ ] `python_app/tests/test_epic_logic.py` — new file, covers `EpicController` (EPIC-03)
- [ ] `python_app/tests/test_volume_logic.py` — new file, covers `VolumeController`/`clamp_volume` (GUI-03)
- [ ] `python_app/tests/test_osc_client.py` — extend with `send_epic`/`send_volume` tests
- [ ] `python_app/tests/test_view_tk.py` — extend with zone-button-highlight-on-click and volume-slider-send-on-release tests
- [ ] `python_app/config.py` — add `OSC_EPIC_ADDRESS`, `OSC_VOLUME_ADDRESS`, `EPIC_ZONES`, `EPIC_DEFAULT_ZONE`, `VOLUME_MIN/MAX/DEFAULT` constants
- [ ] No new framework installs needed — pytest and the smoke-test harness both already exist

## Security Domain

`security_enforcement` is enabled (`.planning/config.json` → `workflow.security_enforcement: true`, `security_asvs_level: 1`). Same posture as Phase 1/2 — single-user, localhost-only desktop app, no network exposure beyond loopback UDP, no authentication surface. Phase 3 adds two new OSC input surfaces (`/pp/epic`, `/pp/volume`); everything else is unchanged from Phase 1/2's assessment.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Unchanged — single-user local desktop app |
| V3 Session Management | No | Unchanged |
| V4 Access Control | No | Unchanged |
| V5 Input Validation | **Yes** | Both new OSCdefs (`/pp/epic`, `/pp/volume`) must validate their argument is a number before calling `.asFloat`/`.clip`, exactly mirroring the existing `/pp/bpm`/`/pp/play` handlers' `isNumber`/`isNaN` guard `[VERIFIED: supercollider/main.scd:273-275, 288-290]` — never trust the argument type, even from "your own" GUI. Additionally, both values must be clamped engine-side (0-100) independently of whatever range the GUI enforces, mirroring TEMPO-03's "engine clamps independently" precedent. |
| V6 Cryptography | No | Unchanged |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed `/pp/epic`/`/pp/volume` argument (string, NaN, out-of-range, missing arg) crashing the handler or driving the FX chain/volume gain to an absurd value | Tampering / Denial of Service | Validate `raw.isNumber`/`raw.isNaN` before `.asFloat`, same pattern as `/pp/bpm`; clamp to `[0, 100]` regardless of what's received; on invalid input, log a warning and leave state unchanged |
| An extreme-but-valid EPIC/volume combination (100/100) producing clipping despite passing input validation | Tampering (self-inflicted, not an external attacker) | This is exactly success criterion 4 / Pitfall 1 above — the mitigation is architectural (volume+drive pre-limiter, Pattern 5), verified by the smoke test's `measurePeak` check, not an input-validation concern |
| A stray non-loopback sender triggering `/pp/epic`/`/pp/volume` | Spoofing | Same mitigation already in place for `/pp/bpm`/`/pp/play` — `srcID: NetAddr("127.0.0.1", nil)` on both new OSCdefs, no new attack surface introduced |

## Sources

### Primary (HIGH confidence)
- `doc.sccode.org/Classes/Lag.html` — exact description, arguments, confirmed stock UGen, fetched this session
- `doc.sccode.org/Classes/VarLag.html` — curve-shape alternatives (`warp`: step/linear/exponential/sine/welch/squared/cubed), confirmed stock UGen, fetched this session
- `doc.sccode.org/Classes/FreeVerb.html` — exact description, arguments (`mix`/`room`/`damp`), confirmed stock (ships with SC 3.14.0 install, no plugin/quark), fetched this session
- `doc.sccode.org/Classes/Limiter.html` — exact description/arguments, confirmed this session (no change to the existing D-16 limiter design, reused as-is)
- `doc.sccode.org/Guides/Order-of-execution.html` — node-tree execution order guarantee grounding the smoother-before-FX-synth ordering requirement
- `supercollider/main.scd` (this repo) — read in full this session; `\ppMaster`'s bus-index-as-control-arg idiom (lines 93-96), the re-evaluation teardown block (lines 33-45), `/pp/bpm`/`/pp/play` OSCdef validation shape (lines 272-300) are all in-repo precedents this research's patterns extend
- `supercollider/smoke_test.scd` (this repo) — read in full this session; `measurePeak`/`\ppPeakProbe` peak-probing idiom (lines 171-200, 888-916) is the precedent reused for the new max-EPIC-max-volume no-clip check
- `python_app/bpm_logic.py`, `python_app/osc_client.py`, `python_app/view.py`, `python_app/config.py` (this repo) — read in full this session; `BpmController`/`PlayController`/`Debouncer` structure and `send_bpm`/`send_play` shape are the in-repo precedents `EpicController`/`VolumeController`/`send_epic`/`send_volume` mirror
- `.planning/STATE.md`, `.planning/REQUIREMENTS.md`, `.planning/phases/01-tempo-link-skeleton/01-CONTEXT.md`, `.planning/phases/02-full-groove-smooth-tempo/02-RESEARCH.md`, `.planning/phases/02-full-groove-smooth-tempo/02-UI-REVIEW.md` (this repo) — read in full this session; source of all "still-binding decision" quotes, the carry-over WR-01/Phase-2-review findings, and the UI-review precedent informing the zone-button highlight design

### Secondary (MEDIUM confidence)
- sc-users mailing list "distortion" thread, `doc.sccode.org/Guides/Tour_of_UGens.html` — `.softclip`/`.distort` as stock Signal/UGen methods, via WebSearch this session
- `doc.sccode.org/Tutorials/A-Practical-Guide/PG_06f_Server_Control.html` (referenced, not directly fetched) — Bus-as-pattern-value auto-mapping idiom, noted as an alternative "richness" design for future polish, via WebSearch this session
- `.planning/research/ARCHITECTURE.md` — project-level "Conductor" and "dual fan-out" patterns (control bus for timbre, Pdefn for pattern decisions) that this phase's Pattern 1/2 are a concrete instantiation of
- `.planning/research/PITFALLS.md` — Pitfall 5 (master bus clipping/headroom), Pitfall 6 (slider OSC spam/debounce), Pitfall 4 (CPU/node-leak growth) — all directly informing this phase's Common Pitfalls

### Tertiary (LOW confidence)
- None used as the basis for any claim beyond what's logged in the Assumptions Log above.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; every new SC class/UGen confirmed stock this session
- Architecture (conductor/bus-index-as-arg/teardown idioms): HIGH — grounded in official docs plus direct reading of the actual Phase 1/2 code this design extends
- Architecture (FX chain composition, "richness" interpretation): MEDIUM — the individual UGens are `[VERIFIED]`/`[CITED]`, but their specific combination and the "richness" interpretation are this research's own design synthesis, not a single sourced reference
- Pitfalls: HIGH — each is a direct, specific consequence of the documented mechanics above or a carry-over of an already-flagged project concern (WR-01, Phase 2 Pitfall 4/5/6)
- Gray areas: MEDIUM by construction — explicitly provisional defaults substituting for an absent CONTEXT.md, not verified facts

**Research date:** 2026-10-09
**Valid until:** 2026-11-08 (30 days — stable toolchain, no version-sensitive claims; re-verify sooner only if a listening test overturns the "richness"/lag-time gray-area defaults)
