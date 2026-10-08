# PedalPulse

## What This Is

PedalPulse is a personal soundtrack generator for indoor cycling workouts (e.g. Zwift). A SuperCollider engine continuously generates melodic techno / progressive trance (drums, bass, arpeggios, pads), and a small Tkinter Python app lets the rider set the tempo (BPM) to match the required cadence and an "EPIC level" that makes the music brighter and more energetic as the required effort rises. The app talks to the engine over OSC.

## Core Value

Moving the BPM or EPIC control in the Python GUI audibly and smoothly changes the live, generated music in SuperCollider — the Python → OSC → SuperCollider chain works end to end.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] SuperCollider engine generates continuous melodic techno / progressive trance: drums, bass, arpeggios, pads
- [ ] Music is generative/evolving (chord changes, arp variations) so it doesn't feel like a fixed loop over a long session
- [ ] Engine runs on a dedicated TempoClock driven by a BPM value
- [ ] BPM changes ramp smoothly over a few bars (no audible jolt)
- [ ] EPIC level (continuous 0–100) maps to brightness/energy: filter cutoff, drive, reverb/delay amount, synth richness
- [ ] Engine listens for OSC messages (e.g. `/bpm <value>`, `/epic <value>`) via OSCdef
- [ ] Tkinter GUI with a BPM control (slider + numeric input)
- [ ] Tkinter GUI with EPIC control: named preset level buttons (e.g. Recovery / Endurance / Tempo / Threshold / VO2) plus a fine-tune slider
- [ ] GUI sends control changes to SuperCollider in real time over OSC
- [ ] Basic transport/volume control from the GUI (start/stop music, master volume)

### Out of Scope

- Direct Zwift integration (API/telemetry) — unknown whether a suitable API exists; deferred until manual control is proven
- Automatic cadence → BPM mapping from sensors (ANT+/BLE cadence sensors, trainers) — v1 sets BPM manually
- Workout file playback (.zwo timelines driving BPM/EPIC automatically) — v1 is manual live control; good future candidate
- Python app launching/managing sclang — user starts the SuperCollider patch separately
- Multiple tracks / sub-styles selection — one generative style is enough for v1
- Layer density / builds & drops / harmonic mood driven by EPIC — v1 EPIC means brightness/energy; others are later enrichment
- Mobile / web control UI — Tkinter desktop app on the same Mac

## Context

- Use case: home cycling on Zwift, rider listens to music during structured workouts and wants the music to follow the workout's demanded cadence and effort. The rider adjusts controls by hand between intervals.
- User's design sketch (pasted during init): scsynth for low-latency audio with SynthDefs for drums, bass, melodic synths and FX (delay, reverb, filter); sclang as "musical core" using TempoClock, Pbind/Pdef/Prand/Pseq/Pfunc/Pchain/Ptpar; "scenes"/intensity levels (warm-up, steady, push, cool-down); an external control app sending OSC (`/bpm <value>`) received via OSCdef; an optional "musical direction" layer mapping intensity to scenes, density and filter/energy parameters.
- BPM is set directly by the user (not derived from cadence mathematically) — the user chooses a tempo that "feels like" the required cadence.
- Success bar for v1 is a technical proof: Python → OSC → SuperCollider works, and BPM and EPIC audibly change the sound. Musical polish is secondary but the music should still be generative rather than a static loop.
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
| Manual BPM setting instead of cadence→BPM formula | User wants direct control; cadence mapping can come later | — Pending |
| EPIC = brightness/energy (filters, drive, FX) for v1 | Most direct, audible mapping; density/harmony/builds deferred | — Pending |
| EPIC control = preset buttons + fine-tune slider | Quick hits between intervals plus fine control | — Pending |
| Smooth BPM ramps over a few bars | Avoid audible jolts mid-ride | — Pending |
| Tkinter for GUI | User preference, zero extra deps | — Pending |
| Start SC and Python separately | Simpler; avoids process management in v1 | — Pending |
| No Zwift integration in v1 | API availability/suitability unknown | — Pending |

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
*Last updated: 2026-10-08 after initialization*
