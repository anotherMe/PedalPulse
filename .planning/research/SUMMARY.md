# Project Research Summary

**Project:** PedalPulse
**Domain:** Real-time generative music engine (SuperCollider) controlled via OSC from Python/Tkinter GUI on macOS
**Researched:** 2026-10-08
**Confidence:** MEDIUM-HIGH

## Executive Summary

PedalPulse is a personal generative music control tool built on a two-process architecture: a SuperCollider audio engine synthesizing melodic techno/trance on a shared TempoClock, and a Python/Tkinter GUI sending BPM/intensity (EPIC) control messages over localhost OSC. The research validates this split-process approach and confirms that all core technologies are well-established and compatible, but also reveals that the project's success depends critically on getting the generative engine's internal state-management and feedback mechanisms right from the start — particularly: shared harmonic state (no per-layer independent randomization), beat-synchronous tempo ramping (never instant), and connection-status feedback from SC to Python so users can distinguish "the audio is responding" from "nothing is happening because SC crashed."

The recommended stack is minimal by design: SuperCollider 3.14.1, Python 3.12/3.13 with python-osc 1.10.2, Tkinter stdlib. No external quarks needed; the engine uses only stock JITLib/Patterns classes. The biggest upfront risk is macOS Tcl/Tk version mismatch during Python provisioning, which is silent and invisible until the GUI tries to render — flagged for immediate setup-phase verification. The second-biggest risk is that generative variety and harmonic coherence are not "bolted on" late but must be architected in from the moment the first Pbind is written, or the engine will sound monotonous and dissonant even if technically "correct."

Build order prioritizes proving the hardest requirement first (does the generative music actually sound good and non-repetitive over a long session?) before any plumbing is built, then proves the OSC control chain end-to-end, then adds feedback. This front-loads risk reduction and validates success criteria early.

## Key Findings

### Recommended Stack

SuperCollider 3.14.1, Python 3.12/3.13 paired with Tcl/Tk 8.6, python-osc 1.10.2. Zero additional dependencies: JITLib ships with stock SC; Tkinter is stdlib; python-osc is the single minimal OSC dependency.

**Core technologies:**
- **SuperCollider 3.14.1**: Audio engine; TempoClock/Pbind/Pdef/OSCdef are all stable across 3.1x line
- **Python 3.12/3.13 + Tcl/Tk 8.6**: Must use python.org installer or `brew install python-tk@3.12` (critical: Homebrew moved tcl-tk to 9.0, which breaks CPython 3.12/3.13)
- **python-osc 1.10.2**: Pure-Python OSC client; `SimpleUDPClient` is fire-and-forget non-blocking UDP
- **Tkinter (stdlib)**: GUI toolkit; zero extra dependencies

### Expected Features

**Must have (table stakes):**
- BPM control (slider + numeric entry); smooth ramping over a few bars (not instant snaps)
- EPIC multi-parameter mapping (filter cutoff, drive, reverb/delay, synth richness together)
- Named presets for training zones (Recovery/Endurance/Tempo/Threshold/VO2)
- Transport (start/stop) + master volume
- **Engine status/connection indicator** — critical gap vs PROJECT.md; UDP has no delivery feedback; users need to know if SC is actually running

**Differentiators:**
- True generative synthesis (SuperCollider), not song selection/time-stretching
- Unlimited session length with zero loop repetition via generative variation (chord changes, arp evolution)
- Zero-latency, zero-network local control loop
- Continuous EPIC fine-tune alongside presets (preset as default, slider as escape hatch for feel)

**Defer (v2+):**
- Zwift API integration, ANT+/BLE auto cadence→BPM, workout file (.zwo) playback, multiple styles/genres, mobile/web UI

### Architecture Approach

Split-process: Python GUI sends OSC to SC's language port (57120). SC maintains Conductor state (`~bpm`, `~epic`, `~playing`, `~volume`) read live by all patterns. BPM changes never set directly; beat-sync Routine ramps `TempoClock.tempo_` over N beats. EPIC fans out two ways: `Bus.control` for audio-rate synth parameters (instant), `Pdefn` for pattern-rate decisions (note density, scale choices). All pitched layers read shared `Pdefn(\root)` / `Pdefn(\scale)` from a Harmony Clock routine — essential to avoid harmonic clashes and keep layers locked.

**Major components:**
1. Conductor (state layer, SC) — single mutable source of truth
2. TempoClock + Tempo Ramp Routine — smooth tempo glide
3. Harmony Clock — shared harmonic truth for all pitched instruments
4. Pbindef per voice — bass, arp, pad, drums each follows shared roots instead of choosing independently
5. SynthDefs + Group/Bus topology — enforced signal flow; every enveloped synth uses `doneAction: 2`
6. Python Model + View — in-process state + Tkinter widgets
7. OscClient (SimpleUDPClient) — send-only for v1
8. OscServer + Queue bridge — receive heartbeat/status, safe cross-thread to Tkinter via queue+after()

### Critical Pitfalls & Prevention

1. **OSC port drift** — UDP sends succeed silently even if port wrong. SC must post `NetAddr.langPort` at startup; Python port must be visible config value.
2. **Tempo snapping** — Setting `.tempo_` directly causes audible jolts. Always use beat-sync ramp routine.
3. **Server boot timing** — Messages sent before `s.boot` completes are dropped. Gate all OSCdefs on `s.waitForBoot{}`.
4. **Node leaks** — Missing `doneAction: 2` on enveloped synths accumulates over 60+ minutes. Every SynthDef must free itself; soak-test 30+ min confirming flat node count.
5. **Master clipping** — Generative layering produces unpredictable peaks. Use `Limiter.ar` on final output.
6. **Slider spam** — Tkinter fires 30+ times/sec on drag. Debounce/coalesce updates (30–50ms timer).
7. **Tkinter thread-safety** — Blocking OSC calls or cross-thread widget updates crash GUI. Use non-blocking sends on main thread; if receiving, background thread + queue+after() pattern only.
8. **macOS Tcl/Tk version mismatch** — CPython 3.12/3.13 built against Tcl/Tk 8.6; Homebrew `tcl-tk` is 9.0. Use python.org installer or pinned Homebrew formula. Add startup check.
9. **No SC connection feedback** — Users can't tell if nothing happened because SC crashed or change is subtle. Implement heartbeat-based connected/disconnected indicator.
10. **Generative monotony/harmonic clashes** — Independent note generation per layer causes both. Use shared harmonic source; structure at multiple timescales; validate with 20–30 min listening test.

## Implications for Roadmap

Suggested 7-phase structure (ordered by hard dependencies and risk):

### Phase 1: Foundational Audio Engine (Synth Design & Soak Testing)
De-risk the hardest requirement first: does generative music sound good and non-repetitive over 30+ minutes? Deliver: drum/bass/arp/pad SynthDefs, group/bus topology with master limiter, hardcoded patterns on fixed clock, 30–60 min soak test confirming flat CPU/node count and no loop fatigue via real listening.

### Phase 2: Harmony Architecture & Conductor State
Validate internal state management before adding OSC. Deliver: Conductor vars, Harmony Clock routine with shared Pdefn(\root)/\scale, updated patterns reading shared harmony, beat-sync tempo ramp, dual EPIC fan-out (audio-rate + pattern-rate).

### Phase 3: Engine OSC Interface (SC-side, No Python Yet)
Prove control surface in isolation. Deliver: OSCdef handlers for /pp/bpm, /pp/epic, /pp/play, /pp/volume; port visibility logging; heartbeat Routine; test via sclang's own NetAddr.

### Phase 4: Project Setup & Python GUI Skeleton
Catch Tcl/Tk issues early. Deliver: Python 3.12 environment with Tcl/Tk 8.6 verified at startup; minimal Tkinter GUI (sliders, buttons); AppState Model class; visual render test on actual target Python install.

### Phase 5: Python → SC OSC Client (Send-Only)
Core value prop: move slider, hear change. Deliver: OscClient wrapping SimpleUDPClient; Controller wiring; end-to-end Python→OSC→SC chain proven; debounce/coalesce logic on rapid slider changes.

### Phase 6: Python ↔ SC Status Feedback (Receive & Queue Bridge)
Add connection visibility. Deliver: OscServer in daemon thread; Queue bridge to main thread; connected/disconnected GUI indicator driven by heartbeat timeout; thread-safe pattern established for future enhancements.

### Phase 7: Polish & Integration Testing
Stress-test under real conditions. Deliver: 1+ hour soak test with Zwift running; BPM ramp stress (change mid-ramp), EPIC edge cases (0→100→0), SC kill/restart scenarios; 20–30 min listening test confirming no monotony/clashes at all EPIC levels; documentation (setup guide, troubleshooting, known limits).

**Phase ordering rationale:** Phase 1 before everything (audio quality is hardest, slowest to iterate, highest risk). Phase 2 before Python (state management must be right before external control added). Phase 3 before Python OSC (test SC control in isolation, simpler to debug). Phase 4 before Phase 5 (validate Python environment early). Phase 5 before Phase 6 (prove send-only happy path before adding receiver complexity). Phase 7 last (stress-test only after core is proven).

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 1 (Audio Engine):** Musical composition and generative algorithm choices are domain-specific. Include "reference listen" to melodic techno/trance exemplars and prototype/iterate on feel.
- **Phase 2 (Tempo ramp curve):** Ramp mechanism (Routine stepping TempoClock) is confirmed, but curve shape (linear vs eased, step granularity, interaction with in-flight patterns) needs a short spike.
- **Phase 3 (SC port handling):** Confirm 57120 is default on fresh boot; document port-drift recovery. Bake into acceptance checklist.

**Phases with standard patterns (skip research):**
- **Phase 2 (Harmony Clock/Conductor):** JITLib Patterns, TempoClock, Pdefn idioms are well-documented.
- **Phase 4 (Python/Tkinter setup):** python.org docs, Homebrew docs, PyPI metadata all solid.
- **Phase 5 (OscClient):** python-osc SimpleUDPClient is trivial; debounce is standard UI pattern.
- **Phase 6 (OscServer):** Tkinter thread-safety via queue+after() is the official recommended pattern (Python #11077).

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM-HIGH | Official docs verified; single risk: macOS Tcl/Tk 8.6 requirement is environment-dependent and fails silently; mitigated by startup check |
| Features | MEDIUM | Competitor research via web search (cross-referenced 2-3 sources per claim); table-stakes validated via established products; differentiators inferred from domain analysis |
| Architecture | MEDIUM-HIGH | Patterns are compositions of well-documented SuperCollider/python-osc/Tkinter idioms; each component HIGH confidence, full stack is opinionated synthesis |
| Pitfalls | MEDIUM-HIGH | Grounded in official docs, GitHub issues, or audio-engineering practice; "generative monotony" is synthesized from theory + community practice, hence MEDIUM not HIGH |

**Overall confidence:** MEDIUM-HIGH. Stack is solid; architecture is sound; features are validated. Primary gap: audio-design choices (scale, chord progressions, reverb params) are subjective and require iteration — not a research gap but a musical-iteration cycle. Secondary gap: exact CPU/timing with Zwift coexistence only knowable via soak-testing.

### Gaps to Address

1. **Audio design requires iterative ear judgment:** Research provides technical framework, not a "does it sound good" answer. Mitigation: explicit "reference listen" + "A/B iteration" as UAT steps in the audio engine phase.
2. **Generative variation design space is large:** Research provides anti-patterns (don't use uniform Prand, don't let layers choose independently) but not a single correct solution. Mitigation: experiment with concrete variations and validate via listening.
3. **Zwift CPU/timing interaction unknown without live testing:** Mitigation: soak-test with Zwift running, monitoring for glitches/jitter/CPU spikes.
4. **Visual/UX design not covered by research:** Mitigation: start with simple layout; refine based on real use.
5. **macOS audio-device switching (Bluetooth, AirPlay) not deeply tested:** SC's ServerOptions must match the device Zwift uses. Mitigation: include device-switching test scenarios and document workarounds.

## Sources

### Primary (HIGH confidence)
- SuperCollider official docs (doc.sccode.org): TempoClock, OSCdef, Pdef/Pdefn, Bus, NetAddr — see STACK.md / ARCHITECTURE.md
- python-osc official docs and PyPI metadata (1.10.2, requires_python>=3.10)
- CPython bug tracker: Tkinter thread-safety (#11077), Tcl/Tk 9.0 incompatibility (cpython#124111)
- SuperCollider GitHub issues on Pdef quant behavior (#4767, #4803)

### Secondary (MEDIUM confidence)
- pyenv#3116, Homebrew discussion #5809 (Tcl/Tk 8.6 vs 9.0 on macOS)
- scsynth.org community threads on tempo ramping, headless sclang, generative pattern design
- Competitor product material: Weav, RockMyRun, Endel, Spotify cadence features (see FEATURES.md)

### Tertiary (LOW confidence)
- General algorithmic-composition literature on multi-timescale variation (see PITFALLS.md Pitfall 10)

---
*Research completed: 2026-10-08*
*Ready for roadmap: yes*
