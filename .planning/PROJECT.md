# PedalPulse

## What This Is

PedalPulse is a personal soundtrack generator for indoor cycling workouts (e.g. Zwift). A SuperCollider engine continuously generates melodic techno / progressive trance (drums, bass, arpeggios, pads), and a small Tkinter Python app lets the rider set the tempo (BPM) to match the required cadence and an "EPIC level" that makes the music brighter and more energetic as the required effort rises. The app talks to the engine over OSC.

## Current State

**Shipped:** v1.0 Technical Proof (2026-10-10). The whole Python → OSC → SuperCollider chain works end to end. A six-layer fixed-loop trance groove plays on one TempoClock, and the GUI controls BPM (gliding over 2 bars), Start/Stop, five EPIC zones and master volume, all going through a −1 dBFS limiter. About 2,800 lines of Python (app + tests) and 2,350 lines of SuperCollider (engine + smoke test). There are 150 pytest tests and a 67-check headless smoke suite.

**Open:** ENG-03, the 60-minute stability check, is still waiting on a manual test ride.

## Current Milestone: v2.0 Living Music

**Goal:** Replace the fixed A-minor loop with music that keeps changing over a 60+ minute ride, in harmony, melody, sound and structure, built on a growing library of named variations that the rider can always switch back to.

**Target features:**
- Modular engine: `main.scd` keeps the core (clock, buses, EPIC FX, limiter, OSC, transport); musical content lives in separately loaded modules
- Variation library: progressions, melody styles and sound palettes are each a named `.scd` file under `supercollider/library/<category>/`; new experiments are added as new files and never overwrite old ones
- Shared harmony clock: the current progression drives bass, arp, pad and lead together (GEN-01)
- Melodies built from rules: motifs follow the current chord, repeat, then mutate
- Song structure on several timescales: fills, motif changes, and breakdown, build and drop sections (GEN-02)
- EPIC also drives arrangement density: Recovery sparse, VO2 full-on (GEN-03)
- GUI library selectors: palette, progression and melody style each offer Auto or a specific item; lists are read from the library folder on disk; selections go out as send-only OSC messages

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

Shipped in v2.0:

- ✓ Engine core (`supercollider/core/` loader, renderer, validator) split from musical content in `supercollider/library/`; the split plays the shipped groove note for note (0 parity mismatches) and re-evaluating never stacks layers or routines — Phase 4
- ✓ Named, never-overwritten library files for progressions, melodies and palettes, selectable live by name over OSC (`/pp/progression`, `/pp/palette`, `/pp/melody`, loopback-only) from the next bar; a broken file is refused and the last good copy keeps playing; `bash scripts/check.sh` guards, validates every file and runs the smoke suite — Phase 4
- ✓ GUI dropdowns for palette, progression and melody (Auto or a named item), built from the library folder and rescanned each time a dropdown opens, so new files appear without a restart; send-only, a repeat pick sends nothing, BPM keys keep working — Phase 5
- ✓ Shared chord progression followed by bass, arp, pad and lead together, with no clashes at chord changes; `classic` plus 7 named progressions (anthem, rocker, lift, return, deep, melancholy, drama); pad voice-leading to the nearest voicing; picks switch at the end of the current cycle, and Auto rotates every 32-64 bars without an immediate repeat — Phase 6

### Active

Milestone v2.0 Living Music (detailed REQ-IDs in REQUIREMENTS.md):

- [ ] Rule-based, evolving melodies instead of fixed note lists
- [ ] Multi-timescale song structure (fills, motif changes, breakdown/build/drop sections)
- [ ] EPIC drives arrangement density in addition to brightness/energy
- [ ] Long-session stability (ENG-03: 60+ min without node/CPU growth). Carried over from v1.0; more important now that the engine does more

### Out of Scope

- Direct Zwift integration (API/telemetry) — unknown whether a suitable API exists; deferred until manual control is proven
- Automatic cadence → BPM mapping from sensors (ANT+/BLE cadence sensors, trainers) — v1 sets BPM manually
- Workout file playback (.zwo timelines driving BPM/EPIC automatically) — v1 is manual live control; good future candidate
- Python app launching/managing sclang — user starts the SuperCollider patch separately
- EPIC fine-tune slider — presets only in v1, deferred to v2
- Multiple genres — v2.0 varies palettes, harmony and melody within melodic techno / progressive trance
- Live-coding by the rider — the user isn't proficient in SuperCollider; new variations are described in plain words ("brighter", "heavier") and written by Claude as new library files
- EPIC fine-tune slider (CTRL-01), configurable ramp time (CTRL-02) — not in v2.0 scope
- Mobile / web control UI — Tkinter desktop app on the same Mac
- Engine → GUI feedback (heartbeat connection indicator, live engine BPM/EPIC readout) — dropped 2026-10-10 to keep the app simple; the Python app stays send-only

## Context

- Use case: home cycling on Zwift, rider listens to music during structured workouts and wants the music to follow the workout's demanded cadence and effort. The rider adjusts controls by hand between intervals.
- User's design sketch (pasted during init): scsynth for low-latency audio with SynthDefs for drums, bass, melodic synths and FX (delay, reverb, filter); sclang as "musical core" using TempoClock, Pbind/Pdef/Prand/Pseq/Pfunc/Pchain/Ptpar; "scenes"/intensity levels (warm-up, steady, push, cool-down); an external control app sending OSC (`/bpm <value>`) received via OSCdef; an optional "musical direction" layer mapping intensity to scenes, density and filter/energy parameters.
- BPM is set directly by the user (not derived from cadence mathematically) — the user chooses a tempo that "feels like" the required cadence.
- Success bar for v1 is a technical proof: Python → OSC → SuperCollider works, and BPM and EPIC audibly change the sound. Musical polish and generative evolution are deferred to v2 (decided during requirements scoping); a fixed loop is acceptable for v1.
- Research (.planning/research/) recommends: SC 3.14.x with stock classes, Python 3.12/3.13 with Tcl/Tk 8.6 (avoid Homebrew tcl-tk 9.0), python-osc; conductor state layer in sclang; beat-synchronous tempo-ramp routine; EPIC via lagged control buses; heartbeat for connection status.
- v2.0 motivation (2026-10-11): the v1 music is too simple and repetitive ("the same 5 notes for an hour"). The user wants variety in harmony, melody, sound palette and song structure, and every experiment kept so they can switch back later.
- v2.0 workflow: the user listens on rides and gives plain-language feedback; Claude turns it into new named library files. Names (e.g. palette "Dark") are the shared vocabulary for feedback.
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
| v2.0: core + modules layout instead of one big .scd or one self-contained file per style | One big file grows unmanageable; per-style full patches duplicate the engine and stop the music when switching | ✓ Good — Phase 4 (parity 0 mismatches; UAT: default startup sounds like v1.0) |
| v2.0: variation library lives in SuperCollider as named `.scd` files under `supercollider/library/<category>/`; new experiments are new files, never edits of old ones | The rider must be able to switch back to any earlier experiment; musical content is SC code anyway; git keeps history | ✓ Good — Phase 4 (check.sh guard; `classic_lead_loud` added as a new file and switched to live) |
| v2.0: GUI builds its selector lists by reading the library folder on disk; selections are sent by name over OSC | Keeps the app send-only (no engine → GUI channel) and needs no separate Python config to keep in sync | ✓ Good — Phase 5 (UAT: new file appears on the next open, unknown names refused by the engine, no crash with the engine stopped) |
| v2.0: one memoized harmony entry per bar feeds every pitched layer; a melody can opt out with `ownHarmony`; the pad releases one beat before each change; Auto picked mid-ride holds the current progression for one full hold first | Layers can never disagree on the chord; the rider confirmed all three planner choices | ✓ Good — Phase 6 (UAT 10/10) |
| v2.0: Auto's draw counter survives Stop/Start (`~ppAutoPicks`) | Review WR-02: every Start replayed the identical Auto order | ✓ Good — Phase 6 (UAT test 10) |
| v2.0: palettes rotate automatically, and a GUI selector can lock one | Variety by default on long rides, plus a way to audition and name what to give feedback on | — Pending |
| v2.0: EPIC drives arrangement density as well as brightness/energy | Recovery should feel sparse and VO2 full-on | — Pending |
| v2.0: a new variation's change must be clearly audible in the full mix | Phase 4 UAT: `classic_lead` (octave-up lead 12 dB under the arp) could not be heard; `classic_lead_loud` at the arp's level could | ✓ Good — Phase 4 |
| v2.0: library-hardening review findings WR-01 (no upper bounds on row values) and WR-02 (refused palette leaves SynthDefs; fallback does not restore classic voices) deferred | Library files are written by Claude and checked before a ride; accepted by the rider in 04-UAT | ⚠️ Revisit — before palettes multiply (Phase 7) |

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
*Last updated: 2026-10-13 after Phase 6*
