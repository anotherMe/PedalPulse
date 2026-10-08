# Feature Research

**Domain:** Adaptive / generative workout music (tempo-controllable generative melodic techno/trance for indoor cycling, controlled from a small desktop GUI)
**Researched:** 2026-10-08
**Confidence:** MEDIUM

## Context: Products Surveyed

| Product | Category | What it teaches PedalPulse |
|---|---|---|
| **Weav Music / Weav Run** | Real-time adaptive-tempo running music | Cadence-locked BPM matching, a "fixed tempo" mode distinct from auto-match, instructor-style interval cueing |
| **RockMyRun** | DJ-curated workout music w/ BPM sync | Progressive BPM build-up across a session, manual BPM override, discovery-by-BPM |
| **Endel** | Generative ambient soundscapes | Named mode presets, context-driven continuous parameter modulation, true non-repeating generative engine |
| **Spotify Running Mode** | Mainstream streaming BPM feature | Simpler "dial in a BPM up front" model (no live sensor loop), time-stretch toggle |
| **Game adaptive music (general)** | Interactive scoring (film/game audio theory) | Vertical remixing (layer stems by intensity) + horizontal re-sequencing (branch between sections) as the two canonical techniques for "music that reacts" |
| **Generative/live-coding music practice** | SuperCollider/TidalCycles performance culture | Concrete anti-loop-fatigue techniques: continuous FX automation, probabilistic variation, swing/humanization, re-voicing |
| **DJ software (Serato/rekordbox-class)** | Tempo control UX | Smooth BPM ramp via automation curve, symmetric up/down smoothness, sync button as "good default" |
| **Zwift / TrainerRoad** | Indoor cycling training structure | Named-zone interval model (Recovery/Endurance/Tempo/Threshold/VO2) as the universal mental model riders already have |

PedalPulse's own PROJECT.md already encodes most of the "table stakes" decisions (BPM slider+numeric, EPIC presets+slider, smooth ramps, transport/volume, OSC control). This research validates those choices against the wider ecosystem and identifies a few gaps (status/connection indicator, graceful degradation) that PROJECT.md doesn't yet mention explicitly.

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete or broken mid-ride.

| Feature | Why Expected | Complexity | Notes |
|---|---|---|---|
| **BPM control: slider + numeric entry, live** | Every tempo-aware product (Weav fixed-tempo mode, Spotify Running Mode, DJ software) lets the user see and set an exact number, not just "slow/fast". Riders mid-interval need to dial a precise number fast. | LOW | Already in PROJECT.md. Numeric entry matters more than slider precision — riders glance down between pedal strokes. |
| **Smooth BPM ramping (no audible jolt)** | DJ software treats this as foundational: a tempo change is only acceptable if it ramps over an automation curve, not a hard cut; a 130→120 ramp must feel as smooth as 120→130. A hard tempo jump breaks the "it's alive" illusion and is physically jarring to pedal to. | MEDIUM | PROJECT.md specifies "ramp over a few bars." Confirm ramp is tempo-direction-symmetric and bar-quantized (commit at next beat/bar boundary, not instantly) — this is the DJ-software lesson. |
| **Intensity/energy control mapped to audible timbral change** | Every adaptive product ties its single "more energy" dial to a *stack* of simultaneous musical parameters, not one knob. Endel modulates rhythm+intensity+tone together; game vertical-remixing blends in extra layers *and* raises mix intensity together. A single-parameter energy change (e.g. only volume) reads as fake. | MEDIUM | PROJECT.md's EPIC→{filter cutoff, drive, reverb/delay, synth richness} multi-parameter mapping is the right shape and matches industry practice — keep it, don't simplify to one parameter. |
| **Named presets for training zones, not just raw numbers** | Zwift/TrainerRoad train every structured-workout user to think in zone *names* (Recovery, Endurance, Tempo, Threshold, VO2), not raw percentages. A tool that only exposes a 0-100 slider forces unnecessary mental translation during a hard interval. | LOW | PROJECT.md already specifies this (preset buttons + fine-tune slider). This is the single most important "speaks the rider's language" feature — keep it prominent and one-click. |
| **Transport (start/stop) + master volume from the control surface** | Every surveyed product and every piece of music software has this baseline. Without it, the user must alt-tab or reach the SC console during a workout. | LOW | PROJECT.md already specifies this. |
| **Generative variation over the session (non-looping)** | RockMyRun explicitly builds BPM/mood across a station; Endel's whole pitch is "never repeats"; game audio's whole discipline exists because static loops break immersion. A ~60 min workout on a fixed 8-16 bar loop is the single most common complaint pattern in this category ("loop fatigue"). | MEDIUM-HIGH | PROJECT.md already lists this as a requirement (chord changes, arp variation). This is a musical/engine concern more than a GUI concern — see Dependencies below. |
| **Engine connection / status indicator** | Not explicit in PROJECT.md, but table stakes once the architecture is "control app talks to a separately-launched, decoupled audio engine over UDP OSC" — a protocol with **no delivery guarantee or acknowledgment**. DJ/audio software always shows device/engine connection state because disconnection is silent otherwise. | LOW | **Gap vs PROJECT.md** — recommend adding this explicitly. See Pitfalls/Architecture research for detail; flagged here because its absence is a table-stakes failure mode: user moves a slider, nothing happens, and has no idea why. |

### Differentiators (Competitive Advantage)

Not required for this to work, but valuable for *this specific personal tool* vs. generic alternatives (Spotify, a plain Spotify BPM playlist, YouTube "workout mix").

| Feature | Value Proposition | Complexity | Notes |
|---|---|---|---|
| **True audio-level generative engine (SuperCollider), not song selection/stretching** | This is PedalPulse's actual core differentiator vs. every surveyed consumer product. Weav/Spotify/RockMyRun all manipulate *pre-recorded songs* (time-stretch, crossfade, pick-from-library). PedalPulse *synthesizes* the music live, so BPM and energy changes are native rather than pitch/time-stretched — no audible artifacts from tempo-shifting a fixed recording, and energy changes are genuine timbral synthesis changes, not just volume/EQ on a fixed stem. | N/A (already the chosen architecture) | This is the single biggest "why build this instead of using Spotify" answer — worth stating explicitly in product framing, not just treating as an implementation detail. |
| **Unlimited session length with no repeat** | A curated-track approach (RockMyRun, Spotify) eventually repeats a song; a generative engine with proper variation (per PROJECT.md's chord/arp changes) genuinely never repeats within any realistic session length. | MEDIUM | Depends on the "generative variation" table-stakes feature being done well — see Dependencies. |
| **Zero-latency, zero-network local control loop** | Localhost UDP OSC is lower latency and has no cloud dependency, unlike Spotify/RockMyRun which need network/licensing. Response to a slider move can be near-instant. | LOW (already the architecture) | Worth highlighting as a felt quality (snappy, reliable, no buffering) rather than a feature per se. |
| **Continuous EPIC fine-tune alongside named zone presets** | DJ software's "sync button + manual override" pattern and RockMyRun's "manual BPM override" both validate: give users a fast default (preset) *and* an escape hatch (slider) for when the preset doesn't match how they actually feel in the moment. | LOW (already specified) | PROJECT.md already has this; worth confirming the fine-tune slider recenters to the preset's value when a preset is clicked (anchor point), so "fine-tune" reads as a relative nudge, not an independent competing control. |
| **Energy mapped to a *recognizable musical arc* (brightness build), independent of literal workout data** | Because EPIC is set by feel rather than computed from a sensor, the rider effectively acts as their own "music director" — closer to the live-coding/DJ performance model than to a passive adaptive-audio consumer product. This is actually a different and arguably more satisfying UX than full automation for a tool used by one person who already knows their own workout. | LOW (already the architecture) | Reframe for roadmap: this is a *performance interface* (like a DJ deck), not a *sensor dashboard* — keep the GUI's visual language closer to "instrument" than "telemetry." |

### Anti-Features (Commonly Requested, Often Problematic — Correctly Out of Scope per PROJECT.md)

These map directly onto PROJECT.md's "Out of Scope" list; included here with the ecosystem rationale for *why* each is correctly deferred, for the record and for later milestones.

| Feature | Why Requested | Why Problematic for v1 | Alternative / Future Path |
|---|---|---|---|
| **Direct Zwift integration (API/telemetry)** | "It should just know my workout automatically" — this is what every adaptive-music competitor without manual override is missing when the workout changes by scripted intervals. | Zwift has no public, stable third-party API for real-time workout telemetry; building against private/reverse-engineered hooks is high effort and fragile (breaks on Zwift updates). Also removes the "performance" quality of manual control. | Future milestone: investigate Zwift's companion API / FIT file export, or a generic ANT+/BLE/FTMS trainer-data listener (see next row) once manual control is proven valuable. |
| **Automatic cadence→BPM from sensors (ANT+/BLE cadence, trainer FTMS)** | Every competitor surveyed (Weav, RockMyRun Body-Driven Music) treats auto-sensing as their headline feature. | Adds a sensor-pairing subsystem, noise/smoothing logic, and a mapping-curve problem (cadence doesn't equal felt effort — Weav's own split into "Match My Stride" vs. "Fixed Tempo" shows even the auto-matching leaders ship a manual escape hatch). Pulling this in before the manual loop is validated risks building the wrong mapping curve. | Future milestone, and even then keep manual override (every competitor that has auto-sensing still ships a manual mode). |
| **Workout file (.zwo) playback driving BPM/EPIC on a timeline** | "Automate it like a workout program" — this is exactly the horizontal re-sequencing / scripted-program model used by Spotify Running Mode's "25 preset programs" and RockMyRun's progressive-BPM stations. | Requires a .zwo parser, a scheduler independent of live user input, and UI for authoring/selecting programs — all before the core manual control loop is proven. Also raises the question of what happens when manual override and program-driven control fight each other (same risk DJ "sync" vs. manual pitch controls manage via explicit mode switching). | Strong, well-validated future candidate — this is the most common pattern across multiple competitors (Spotify's prompted programs, RockMyRun's stations, Weav's instructor-led workouts). Build only after manual control is validated, and design it as an *optional automation layer* that can be manually overridden at any time (don't remove the manual loop). |
| **Density / builds-drops / harmonic mood as EPIC dimensions** | Game adaptive-music theory (vertical remixing) and generative-music practice both treat density and structural "drop" moments as core intensity levers, not just filter/drive. | Correctly deferred: this requires a more complex scene/structure model (explicit "warm-up / steady / push / cool-down" scenes per the user's own design sketch) layered on top of the simpler filter/drive/FX brightness mapping — more moving parts to debug before the basic pipeline is proven end-to-end. | Future enrichment once EPIC-as-brightness is validated; the user's own sketch (scenes, Pseq/Prand/Ptpar structures) is the natural extension point — see ARCHITECTURE.md. |
| **Multiple tracks / sub-styles / genre selection** | Competitors (RockMyRun's genre filters, Spotify's preferences) all let users pick a vibe. | A style-selection UI and multiple SynthDef sets multiply engine complexity and testing surface before a single style's control loop is proven. | Future: once one generative style works reliably, parametrize it or add alternates. |
| **Mobile/web control UI** | Convenience — "control it from my phone/handlebars." | Desktop Tkinter app on the same Mac is simpler, has no network/security surface, and matches the single-user, single-machine setup. A phone UI would need a web server, auth, and a second OSC relay hop. | Future: a minimal local web UI (Flask + same OSC bridge) is the natural next step if ever needed — low cost to add later because OSC control surface is already decoupled from the GUI framework. |
| **Automatic reconnection retry storms / silent auto-fix of engine disconnects** | Looks like good robustness ("just reconnect for me"). | OSC over UDP has no delivery acknowledgment; aggressive auto-retry logic can mask a genuinely dead SC process and give false confidence the music is responding. For a single-user tool, a clear status indicator + manual "reconnect" action is more honest and far simpler than connection-state machinery. | Covered under the status-indicator table-stakes feature above: show state (`connected`/`no engine detected`/`send failed`), let the user act manually. |

## Feature Dependencies

```
Generative engine (SC continuous synthesis)
    └──requires──> TempoClock driven by live BPM value
                       └──enhances──> Smooth BPM ramping (ramp target feeds the same clock)

Generative variation (chord/arp changes over session)
    └──requires──> Pattern-level structure (Pseq/Prand/Pfunc per user's own design sketch)
    └──enhances──> "No loop fatigue over 60 min" (table stakes)
    └──enhances──> "Unlimited session length with no repeat" (differentiator)

EPIC control (0-100 continuous)
    └──requires──> Multi-parameter mapping (filter cutoff + drive + reverb/delay + synth richness together)
    └──requires──> Named zone presets (discrete anchor points) ──paired-with──> fine-tune slider (continuous nudge)

OSC control channel (Python → SC)
    └──requires──> Engine connection/status indicator (table stakes gap)
                       └──prevents-silent-failure-of──> BPM control, EPIC control, Transport (all look functional but do nothing if OSC send fails or SC isn't running)

Workout-file / scripted-program playback (anti-feature, future)
    └──requires──> Manual BPM/EPIC control loop (must ship and be proven first)
    └──conflicts──> nothing structurally, IF designed as an optional override layer on top of manual control (not a replacement)

Automatic sensor-driven cadence→BPM (anti-feature, future)
    └──requires──> Manual BPM control loop (must ship and be proven first; every competitor keeps a manual escape hatch alongside auto-sensing)
    └──enhances──> nothing in v1; is a parallel future input source feeding the *same* `/bpm` OSC target
```

### Dependency Notes

- **Generative variation requires pattern-level structure, not just randomization bolted onto a fixed loop.** The anti-loop-fatigue research (automation, probabilistic variation, swing, re-voicing) is additive polish on top of an underlying pattern engine that actually changes over time (chord progressions, arp patterns cycling) — the PROJECT.md requirement already implies this; make sure the phase that builds the generative engine budgets for pattern structures (Pseq/Prand/Pfunc), not just FX automation.
- **EPIC's multi-parameter mapping enhances, and is enhanced by, the preset+slider pairing.** Presets should set a target point across *all* the mapped parameters at once (not just a number the slider also controls) — this is what makes "Threshold" feel qualitatively different from "Endurance," matching how Endel's mode presets and game vertical-remixing both shift multiple parameters together per intensity tier.
- **The status/connection indicator is a cross-cutting dependency, not an isolated feature.** Every other control (BPM, EPIC, transport) depends on it for the user to trust that an action had effect — recommend building it alongside the first OSC send, not as a later polish pass.
- **Scripted workout-file playback (future) and sensor-driven auto-BPM (future) both explicitly depend on the manual control loop shipping first**, and both should be designed as optional layers feeding the same underlying `/bpm`/`/epic` OSC targets the manual GUI already drives — this keeps the anti-feature deferrals cheap to revisit later rather than requiring a redesign.

## MVP Definition

### Launch With (v1)

Minimum viable product — matches PROJECT.md's Active requirements; validates the core Python→OSC→SuperCollider loop end to end.

- [ ] Generative SC engine: drums, bass, arps, pads on a shared TempoClock — essential to prove "it's actually music, not a sequencer demo"
- [ ] Generative variation (chord/arp changes) — essential to avoid the single most common failure mode in this category (loop fatigue) even in a short v1 demo session
- [ ] BPM control: slider + numeric, smooth multi-bar ramp — essential, this is the core value prop ("moving a control audibly changes the music")
- [ ] EPIC control: 0-100 continuous mapped to filter/drive/reverb-delay/synth richness, exposed as named zone presets + fine-tune slider — essential, second half of the core value prop
- [ ] Transport (start/stop) + master volume — essential baseline, every competitor has it
- [ ] **Engine status/connection indicator** — recommend adding explicitly even though not yet in PROJECT.md; without it, a silent OSC failure is indistinguishable from "it's working," which undermines the entire "audibly and smoothly changes" success bar

### Add After Validation (v1.x)

Features to add once the core manual-control loop is proven and feels good on real rides.

- [ ] Persisted "last used" BPM/EPIC per session (small quality-of-life; no competitor treats this as core, but any desktop control app accumulates this expectation fast)
- [ ] More explicit "scene" model (warm-up/steady/push/cool-down) sitting on top of the EPIC number, per the user's own design sketch — trigger: once brightness-only EPIC feels musically thin
- [ ] Visual feedback of current BPM/EPIC state directly in the GUI (e.g. a simple level meter or beat-flash) — trigger: if "is it actually responding" uncertainty persists even with the status indicator

### Future Consideration (v2+)

Explicitly deferred; matches PROJECT.md's Out of Scope with added rationale from this research (see Anti-Features table above for full detail).

- [ ] Zwift API/telemetry integration — defer: no confirmed stable API; also removes the "performance interface" feel
- [ ] ANT+/BLE sensor-driven auto cadence→BPM — defer: needs a sensor subsystem and a felt-effort mapping curve; every competitor keeps manual override anyway
- [ ] Workout file (.zwo) timeline playback — defer: strong pattern validated by competitors (Spotify programs, RockMyRun stations), but must be built as an optional layer over the proven manual loop, not instead of it
- [ ] Density/builds-drops/harmonic-mood EPIC dimensions — defer: needs the scene/structure model first
- [ ] Multiple styles/genres — defer: multiplies engine testing surface
- [ ] Mobile/web control UI — defer: no need until multi-device or non-desktop use is actually requested

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---|---|---|---|
| Generative engine (drums/bass/arp/pad on shared clock) | HIGH | HIGH | P1 |
| Smooth BPM ramp control | HIGH | MEDIUM | P1 |
| EPIC multi-parameter energy mapping | HIGH | MEDIUM | P1 |
| EPIC named presets + fine-tune slider | HIGH | LOW | P1 |
| Generative variation (anti-loop-fatigue) | HIGH | MEDIUM-HIGH | P1 |
| Transport + volume | MEDIUM | LOW | P1 |
| Engine status/connection indicator | HIGH | LOW | P1 (recommend promoting into PROJECT.md Active) |
| Persisted last-used settings | LOW | LOW | P2 |
| Explicit scene model (warm-up/push/cool-down) | MEDIUM | MEDIUM | P2 |
| Visual beat/level feedback in GUI | MEDIUM | LOW | P2 |
| Workout file (.zwo) playback layer | MEDIUM (strong future differentiator) | HIGH | P3 |
| Sensor-driven auto cadence→BPM | MEDIUM | HIGH | P3 |
| Zwift API integration | LOW (unproven availability) | UNKNOWN/HIGH | P3 |
| Multiple styles/genres | LOW | MEDIUM | P3 |
| Mobile/web UI | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Must have for launch (matches PROJECT.md Active requirements, plus the status-indicator addition)
- P2: Should have, add when possible
- P3: Nice to have, future consideration (matches PROJECT.md Out of Scope)

## Competitor Feature Analysis

| Feature | Weav Music | RockMyRun | Endel | Spotify Running Mode | Our Approach |
|---|---|---|---|---|---|
| Tempo source | Live sensor (accelerometer) auto-match, or fixed-tempo mode | Sensor (HR/cadence) auto-match, or manual override | N/A (not tempo-based) | User-set target BPM up front, no live tracking | Manual, user-set (deliberate choice per PROJECT.md) — closer to Spotify/DJ model than to sensor auto-match |
| Tempo change smoothness | Continuous re-composition in real time | Not detailed; sync via time-stretch | N/A | Optional time-stretch toggle | Multi-bar ramp on the TempoClock — more like a DJ tempo-automation curve than a hard snap |
| Energy/intensity control | Implicit via workout program, not a user dial | BPM-based station build, not a separate energy dial | Context-driven (HR, time, weather) multi-parameter modulation | Minimal — BPM target only | Explicit continuous EPIC dial (0-100) mapped to multiple synthesis parameters at once — more direct user control than any surveyed competitor |
| Named presets | Workout-program steps | BPM/mood/genre filters | Mode presets (Focus/Relax/Sleep/Move) | Preset running programs | Training-zone-named presets (Recovery/Endurance/Tempo/Threshold/VO2) — borrows the mental model from Zwift/TrainerRoad rather than from any music competitor |
| Anti-repetition / generative variation | Re-composition of real songs per stride | Curated track sequencing, not generative | True generative algorithmic engine, core selling point | Curated playlist, not generative | True generative synthesis (SuperCollider), closer to Endel's approach than to the track-manipulation approach of Weav/RockMyRun/Spotify |
| Manual override alongside automation | Yes (Fixed Tempo mode) | Yes (manual BPM) | No manual override surfaced | Yes (it's manual-first) | Fully manual in v1 by design; automation layers are explicitly future work, always as an override-able layer per the dependency analysis above |
| Status/connection feedback | N/A (self-contained mobile app) | N/A (self-contained mobile app) | N/A (self-contained mobile app) | N/A (self-contained mobile app) | **Needed and currently missing from PROJECT.md** — PedalPulse's split-process OSC architecture is the one surveyed design with a real disconnection failure mode, because every competitor is a single self-contained app with no external engine process to lose sync with |

## Sources

- [What's So Adaptive About Our Music? (Weav Music, Medium)](https://medium.com/@weavmusic/whats-so-adaptive-about-our-music-bc9190772890) — MEDIUM confidence
- [Weav unveils adaptive audio workout tool for runners (endurance.biz)](https://endurance.biz/2020/industry-news/weav-unveils-adaptive-audio-workout-tool-for-runners/) — MEDIUM confidence
- [Weav Music Launches First Personalized Audio Workouts for Runners (BusinessWire)](https://www.businesswire.com/news/home/20200630005225/en/Weav-Music-Launches-First-Personalized-Audio-Workouts-for-Runners) — MEDIUM confidence
- [RockMyRun — Music that Moves You (official)](https://www.rockmyrun.com/) — MEDIUM confidence
- [RockMyRun myBeat MatchMe launch (PR Newswire)](https://www.prnewswire.com/news-releases/rockmyrun-launches-mybeat-matchme---a-unique-feature-that-will-forever-change-how-we-workout-259068341.html) — MEDIUM confidence
- [Endel (app) — Wikipedia](https://en.wikipedia.org/wiki/Endel_(app)) — MEDIUM confidence
- [Endel — official site](https://endel.io/) — MEDIUM confidence
- [Spotify's new Running Mode (Yahoo Tech)](https://tech.yahoo.com/audio/articles/spotify-running-mode-takes-workout-143827276.html) — MEDIUM confidence
- [How to Get the Most Out of Running Mode — Spotify Newsroom](https://newsroom.spotify.com/2026-08-18/running-mode-how-to-personalization/) — MEDIUM confidence
- [Making Your Game's Music More Dynamic: Vertical Layering vs. Horizontal Resequencing (The Game Audio Co.)](https://www.thegameaudioco.com/making-your-game-s-music-more-dynamic-vertical-layering-vs-horizontal-resequencing) — MEDIUM confidence
- [Adaptive music — Wikipedia](https://en.wikipedia.org/wiki/Adaptive_music) — MEDIUM confidence
- [The history of adaptive music in video games (Splice blog)](https://splice.com/blog/adaptive-music-video-games/) — MEDIUM confidence
- [How to Keep Repetition in Music Interesting (iZotope)](https://www.izotope.com/en/learn/how-to-keep-repetition-in-music-interesting.html) — MEDIUM confidence
- [Interacting with Generative Music through Live Coding (ResearchGate)](https://www.researchgate.net/publication/27478005_Interacting_with_Generative_Music_through_Live_Coding) — MEDIUM confidence
- [BPM Controls, Tips, and FAQs (DJ.Studio)](https://help.dj.studio/en/articles/8261956-bpm-controls-tips-and-faqs) — MEDIUM confidence
- [Automation-Powered Mixing: Beatmatching, Tempo Sync (DJ.Studio blog)](https://dj.studio/blog/automation-powered-mixing-beatmatching-tempo-sync) — MEDIUM confidence
- [Beatmatching — Wikipedia](https://en.wikipedia.org/wiki/Beatmatching) — MEDIUM confidence
- [Zwift vs TrainerRoad: which is right for you? (BikeRadar)](https://www.bikeradar.com/advice/buyers-guides/zwift-vs-trainerroad) — MEDIUM confidence
- [Indoor Cycling Training Plans: Zwift & TrainerRoad (BikeTips)](https://biketips.com/indoor-cycling-training-plans/) — MEDIUM confidence

All findings sourced via general web search (no curated docs provider available for this domain); cross-referenced across 2-3 independent sources per claim where possible, hence MEDIUM rather than LOW confidence throughout. No HIGH-confidence (official/curated-docs) sources exist for this domain since it spans consumer products without public technical documentation — treat specific mechanism claims (e.g. exact BPM ranges, exact algorithm names) as directionally reliable but not verbatim-accurate.

---
*Feature research for: Adaptive/generative workout music control app (PedalPulse)*
*Researched: 2026-10-08*
