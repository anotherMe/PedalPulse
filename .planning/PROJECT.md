# PedalPulse

## What This Is

PedalPulse is a personal soundtrack generator for indoor cycling workouts (e.g. Zwift). A SuperCollider engine continuously generates melodic techno / progressive trance (drums, bass, arpeggios, pads), and a small Tkinter Python app lets the rider set the tempo (BPM) to match the required cadence and an "EPIC level" that makes the music brighter and more energetic as the required effort rises. The app talks to the engine over OSC.

## Current State

**Shipped:** v1.0 Technical Proof (2026-10-10). The whole Python → OSC → SuperCollider chain works end to end. A six-layer fixed-loop trance groove plays on one TempoClock, and the GUI controls BPM (gliding over 2 bars), Start/Stop, five EPIC zones and master volume, all going through a −1 dBFS limiter. About 2,800 lines of Python (app + tests) and 2,350 lines of SuperCollider (engine + smoke test). There are 150 pytest tests and a 67-check headless smoke suite.

**Open:** ENG-03, the 60-minute stability check, is still waiting on a manual test ride.

## Next Milestone Goals

Not defined yet; start with `/gsd-new-milestone`. The v2 candidates come from the deferred requirements:
- Generative music: a shared harmony clock (GEN-01), variation across several timescales so a 60-minute ride doesn't feel looped (GEN-02), and EPIC also driving arrangement density (GEN-03)
- Controls: an EPIC fine-tune slider (CTRL-01) and a configurable ramp time (CTRL-02)
- Automation: playing back .zwo workout files (AUTO-01), deriving BPM from a cadence sensor (AUTO-02), and Zwift integration (AUTO-03)

## Core Value

Moving the BPM or EPIC control in the Python GUI audibly and smoothly changes the live, generated music in SuperCollider — the Python → OSC → SuperCollider chain works end to end.

## Requirements

### Validated

All shipped in v1.0:

- ✓ Engine runs on a dedicated TempoClock driven by a BPM value (kick + hat + A-minor bass loop) — Phase 1
- ✓ Engine listens for OSC via OSCdef: `/pp/bpm <float>`, loopback-only, clamped 60–180, applied on the next beat — Phase 1
- ✓ Master limiter on the output bus holds peaks below −1 dBFS — Phase 1
- ✓ Tkinter GUI with a BPM control: slider, numeric entry, ±1/±5 nudge buttons and arrow keys, kept in sync — Phase 1
- ✓ GUI sends BPM changes to SuperCollider in real time over OSC (send on slider release, 150 ms nudge debounce) — Phase 1
- ✓ SuperCollider engine plays a continuous melodic techno / progressive trance groove: kick, hat, clap, bass, 16th-note arpeggio, pad, all on one TempoClock (fixed loop) — Phase 2
- ✓ BPM changes glide over ~2 bars from a beat boundary, retarget smoothly mid-glide, clamped 60–180 — Phase 2
- ✓ Start/Stop the music from the GUI (`/pp/play <int>`): clean gate-release Stop, bar-synced Start — Phase 2
- ✓ Engine listens for `/pp/epic <float 0–100>` over OSC (loopback-only, clamped, malformed-arg tolerant) — Phase 3
- ✓ EPIC level maps to brightness/energy: one lagged EPIC value drives filter cutoff, drive, reverb amount and synth richness together, gliding smoothly between zones — Phase 3
- ✓ Tkinter GUI with five EPIC zone preset buttons (Recovery 10 / Endurance 30 / Tempo 50 / Threshold 75 / VO2 100) and a visible selected-zone highlight — Phase 3
- ✓ Master volume slider in the GUI (`/pp/volume <float 0–100>`, squared taper, default 80); gain applied before the limiter, so VO2 at full volume never clips — Phase 3

### Active

- [ ] Long-session stability (ENG-03: 60+ min without node/CPU growth). Carried over from v1.0. The static support is in place (per-note voices free themselves, the node count is bounded in the smoke test); it still needs the manual test ride

### Out of Scope

- Direct Zwift integration (API/telemetry) — unknown whether a suitable API exists; deferred until manual control is proven
- Automatic cadence → BPM mapping from sensors (ANT+/BLE cadence sensors, trainers) — v1 sets BPM manually
- Workout file playback (.zwo timelines driving BPM/EPIC automatically) — v1 is manual live control; good future candidate
- Python app launching/managing sclang — user starts the SuperCollider patch separately
- Generative evolution (shared harmony clock, multi-timescale variation) — v1 is a tech proof; fixed loop is acceptable, deferred to v2
- EPIC fine-tune slider — presets only in v1, deferred to v2
- Multiple tracks / sub-styles selection — one style is enough for v1
- Layer density / builds & drops / harmonic mood driven by EPIC — v1 EPIC means brightness/energy; others are later enrichment
- Mobile / web control UI — Tkinter desktop app on the same Mac
- Engine → GUI feedback (heartbeat connection indicator, live engine BPM/EPIC readout) — dropped 2026-10-10 to keep the app simple; the Python app stays send-only

## Context

- Use case: home cycling on Zwift, rider listens to music during structured workouts and wants the music to follow the workout's demanded cadence and effort. The rider adjusts controls by hand between intervals.
- User's design sketch (pasted during init): scsynth for low-latency audio with SynthDefs for drums, bass, melodic synths and FX (delay, reverb, filter); sclang as "musical core" using TempoClock, Pbind/Pdef/Prand/Pseq/Pfunc/Pchain/Ptpar; "scenes"/intensity levels (warm-up, steady, push, cool-down); an external control app sending OSC (`/bpm <value>`) received via OSCdef; an optional "musical direction" layer mapping intensity to scenes, density and filter/energy parameters.
- BPM is set directly by the user (not derived from cadence mathematically) — the user chooses a tempo that "feels like" the required cadence.
- Success bar for v1 is a technical proof: Python → OSC → SuperCollider works, and BPM and EPIC audibly change the sound. Musical polish and generative evolution are deferred to v2 (decided during requirements scoping); a fixed loop is acceptable for v1.
- Research (.planning/research/) recommends: SC 3.14.x with stock classes, Python 3.12/3.13 with Tcl/Tk 8.6 (avoid Homebrew tcl-tk 9.0), python-osc; conductor state layer in sclang; beat-synchronous tempo-ramp routine; EPIC via lagged control buses; heartbeat for connection status.
- The README lists brainstormed app names; "PedalPulse" is the working name (folder name).

## Constraints

- **Platform**: macOS, same machine running Zwift — audio engine must be light enough not to disturb Zwift
- **Audio engine**: SuperCollider (already installed) — user's chosen engine
- **Control app**: Python + Tkinter — user preference; minimal dependencies
- **Protocol**: OSC over UDP between Python and sclang (localhost)
- **Lifecycle**: SuperCollider patch is started separately by the user; the Python app only connects

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Manual BPM setting instead of cadence→BPM formula | User wants direct control; cadence mapping can come later | ✓ Good — Phase 1 UAT confirmed the manual BPM chain end to end |
| EPIC = brightness/energy (filters, drive, FX) for v1 | Most direct, audible mapping; density/harmony/builds deferred | ✓ Good — Phase 3 UAT: each zone up sounds brighter and more energetic, all parameters moving together |
| EPIC control = zone preset buttons only in v1 | Quick hits between intervals; fine-tune slider deferred to v2 | ✓ Good — Phase 3 five zone buttons |
| Fixed loop music for v1, generative evolution in v2 | v1 is a tech proof of the control chain | ✓ Good — Phase 2 six-layer fixed loop accepted by ear as melodic techno / trance |
| Add heartbeat-based connection indicator | Research: UDP OSC fails silently | ✗ Dropped 2026-10-10 — not needed for a deliberately simple app; the Python app stays send-only (no engine → GUI channel) |
| Smooth BPM ramps over a few bars | Avoid audible jolts mid-ride | ✓ Good — Phase 2: one long-lived `~ppRampStepper` is the sole tempo writer (8-beat glide, beat-aligned engage, mid-glide retarget); UAT confirmed no jolt |
| Tkinter for GUI | User preference, zero extra deps | ✓ Good — Phase 1 window works under Tk 9.0 |
| Start SC and Python separately | Simpler; avoids process management in v1 | ✓ Good — `main.scd` in the SC IDE + `./run.sh` |
| No Zwift integration in v1 | API availability/suitability unknown | ✓ Good — v1.0 shipped without it; still a v2 candidate (AUTO-03) |
| Accept Tk 8.6 and 9.x; project venv is python3.13 with Tk 9.0 via `./run.sh` | Research advised avoiding Tk 9.0, but the real Tk 9.0.3 widgets pass a widget-level smoke test; the startup gate only rejects Tk < 8.6 or a missing `_tkinter` | ✓ Good — Phase 1 |
| OSC address `/pp/bpm` with loopback-only `srcID`, engine-side clamp and latest-wins next-beat apply | Engine validates independently of the GUI; bursts cost one apply per beat | ✓ Good — Phase 1 (19-check headless smoke test) |
| GUI sends BPM on slider release and debounces nudges/keys at 150 ms | Prevents flooding the engine during drags and key auto-repeat | ✓ Good — Phase 1 |
| Transport is `/pp/play <int>` (1 start, 0 stop), loopback-only and idempotent; Stop broadcasts `\gate, 0` to the instrument group (immediate + guarded second broadcast after `s.latency`) instead of freeing nodes | Every voice ends through its own release envelope (no click), in-flight notes are caught; occasional harmless `FAILURE IN SERVER /n_set Node N not found` on Stop is expected | ✓ Good — Phase 2 (UAT passed) |
| `~ppLayers` is the single list of groove layers; Start uses `doReset: true` + `quant: 4` | Teardown, Start/Stop and smoke checks iterate one list; layers re-enter in phase on the bar | ✓ Good — Phase 2 |
| GUI `PlayController` sends an int only on a real state change, no debounce; button takes no focus | Engine is idempotent so rapid clicks are harmless; no interference with arrow-key BPM shortcuts | ✓ Good — Phase 2 |
| EPIC = one raw control bus → one `Lag.kr` smoother (1.5 s) → one `\ppFx` synth deriving drive/cutoff/richness/reverb from that single value | All four parameters move in lockstep by construction; glides retarget smoothly mid-glide with no zipper | ✓ Good — Phase 3 (UAT: smooth zone glides, including back-to-back clicks) |
| Master volume is a 0.2 s lagged gain inside `\ppMaster`, strictly before `Limiter.ar`, with a squared taper `(v/100)²` | Never bypass the limiter; equal slider moves feel like roughly equal loudness steps | ✓ Good — Phase 3 (VO2 + volume 100 peak ≤ limiter ceiling, UAT confirmed no clipping) |
| Persistent FX/smoother synths have no envelope and are freed by the teardown block | Deliberate exception to the `doneAction: 2` rule, which still applies to per-note voices | ✓ Good — Phase 3 (leak-free re-evaluation checked headlessly) |
| Re-evaluating `main.scd` keeps the transport state (`~ppWasPlaying = ~ppPlaying ? true`); only the first-ever evaluation autostarts | Milestone audit W1: re-evaluating after Stop used to restart the music while the GUI still showed "Start" | ✓ Good — quick task 261010-hyl (smoke checks for autostart / stays stopped / keeps playing) |
| No resync after an engine restart (the GUI keeps its last values, the engine resets to defaults) | Follows from the send-only design; restarting the app resyncs | ⚠️ Revisit — milestone audit W2, accepted as tech debt in v1.0 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-10-10 after v1.0 milestone*
