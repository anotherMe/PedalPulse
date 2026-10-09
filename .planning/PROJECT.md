# PedalPulse

## What This Is

PedalPulse is a personal soundtrack generator for indoor cycling workouts (e.g. Zwift). A SuperCollider engine continuously generates melodic techno / progressive trance (drums, bass, arpeggios, pads), and a small Tkinter Python app lets the rider set the tempo (BPM) to match the required cadence and an "EPIC level" that makes the music brighter and more energetic as the required effort rises. The app talks to the engine over OSC.

## Core Value

Moving the BPM or EPIC control in the Python GUI audibly and smoothly changes the live, generated music in SuperCollider — the Python → OSC → SuperCollider chain works end to end.

## Requirements

### Validated

- ✓ Engine runs on a dedicated TempoClock driven by a BPM value (kick + hat + A-minor bass loop) — Phase 1
- ✓ Engine listens for OSC via OSCdef: `/pp/bpm <float>`, loopback-only, clamped 60–180, applied on the next beat — Phase 1
- ✓ Master limiter on the output bus holds peaks below −1 dBFS — Phase 1
- ✓ Tkinter GUI with a BPM control: slider, numeric entry, ±1/±5 nudge buttons and arrow keys, kept in sync — Phase 1
- ✓ GUI sends BPM changes to SuperCollider in real time over OSC (send on slider release, 150 ms nudge debounce) — Phase 1

### Active

- [ ] SuperCollider engine generates continuous melodic techno / progressive trance: drums, bass, arpeggios, pads
- [ ] Long-session stability (60+ min without node/CPU growth) — master limiter already shipped in Phase 1; soak test in Phase 4
- [ ] BPM changes ramp smoothly over a few bars (no audible jolt), retargeting safely mid-ramp, clamped to 60–180
- [ ] Engine listens for `/epic` over OSC (the `/pp/bpm` OSCdef pattern from Phase 1 extends to it)
- [ ] EPIC level (0–100) maps to brightness/energy: filter cutoff, drive, reverb/delay amount, synth richness — with smoothed (lagged) changes
- [ ] Tkinter GUI with EPIC control: named zone preset buttons (Recovery / Endurance / Tempo / Threshold / VO2)
- [ ] Basic transport/volume control from the GUI (start/stop music, master volume)
- [ ] Connection indicator in the GUI driven by an engine heartbeat (UDP OSC fails silently otherwise)
- [ ] GUI displays the engine's actual current BPM (mid-ramp) and EPIC

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
| EPIC = brightness/energy (filters, drive, FX) for v1 | Most direct, audible mapping; density/harmony/builds deferred | — Pending |
| EPIC control = zone preset buttons only in v1 | Quick hits between intervals; fine-tune slider deferred to v2 | — Pending |
| Fixed loop music for v1, generative evolution in v2 | v1 is a tech proof of the control chain | — Pending |
| Add heartbeat-based connection indicator | Research: UDP OSC fails silently | — Pending |
| Smooth BPM ramps over a few bars | Avoid audible jolts mid-ride | — Pending |
| Tkinter for GUI | User preference, zero extra deps | ✓ Good — Phase 1 window works under Tk 9.0 |
| Start SC and Python separately | Simpler; avoids process management in v1 | ✓ Good — `main.scd` in the SC IDE + `./run.sh` |
| No Zwift integration in v1 | API availability/suitability unknown | — Pending |
| Accept Tk 8.6 and 9.x; project venv is python3.13 with Tk 9.0 via `./run.sh` | Research advised avoiding Tk 9.0, but the real Tk 9.0.3 widgets pass a widget-level smoke test; the startup gate only rejects Tk < 8.6 or a missing `_tkinter` | ✓ Good — Phase 1 |
| OSC address `/pp/bpm` with loopback-only `srcID`, engine-side clamp and latest-wins next-beat apply | Engine validates independently of the GUI; bursts cost one apply per beat | ✓ Good — Phase 1 (19-check headless smoke test) |
| GUI sends BPM on slider release and debounces nudges/keys at 150 ms | Prevents flooding the engine during drags and key auto-repeat | ✓ Good — Phase 1 |

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
*Last updated: 2026-10-09 after Phase 1*
