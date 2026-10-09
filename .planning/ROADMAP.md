# Roadmap: PedalPulse

## Overview

PedalPulse is built as four vertical slices. Each one adds a capability the rider can hear or see, end to end through the Python GUI, OSC, and SuperCollider chain. Phase 1 is the walking skeleton. A single sclang entry file plays a basic loop on a dedicated TempoClock through a limited master bus. A Tkinter app (with a Tcl/Tk 8.6 check) sends BPM over OSC, and the tempo changes. Phase 2 builds that into the full drums/bass/arp/pad groove, with beat-synchronous tempo glides and start/stop. Phase 3 adds the EPIC zone presets and master volume, so energy and loudness follow the workout. Phase 4 closes the loop in the other direction. An engine heartbeat drives a connection indicator, the GUI shows the engine's actual BPM and EPIC, and a 60-minute soak proves the engine can last a full ride. Some safety conventions start in Phase 1 and every later slice inherits them: the master limiter, self-freeing synths (doneAction: 2), the posted OSC port, and server-boot gating. v1 music is a fixed loop; generative evolution is v2.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Tempo Link Skeleton** - Single sclang entry file plays a basic loop; Tkinter BPM control changes its tempo over OSC
- [ ] **Phase 2: Full Groove & Smooth Tempo** - Drums, bass, arp and pad play together, glide beat-synchronously to new BPMs, and start/stop from the GUI
- [ ] **Phase 3: EPIC Zones & Volume** - Five zone preset buttons make the music brighter and more energetic; master volume from the GUI, never clipping
- [ ] **Phase 4: Live Feedback & Ride Endurance** - Heartbeat connection indicator, live engine BPM/EPIC display, and 60+ minute stability

## Phase Details

### Phase 1: Tempo Link Skeleton

**Goal:** As a rider, I want to set BPM in the app and hear the engine loop change tempo, so that I know the control chain works.
**Mode:** mvp
**Depends on:** Nothing (first phase)
**Requirements:** ENG-02, ENG-04, TEMPO-03, GUI-01, GUI-04, LINK-01
**Success Criteria** (what must be TRUE):
  1. User runs a single sclang entry file; it waits for the server to boot, posts the OSC port it is listening on, and a basic beat loop starts playing on a dedicated TempoClock
  2. User launches the Tkinter app; with Tcl/Tk 8.6 the window opens normally, and with an incompatible Tk it shows a clear warning instead of failing silently
  3. User sets BPM with the slider, the numeric entry, or the +/- nudge buttons (all three stay in sync), and the loop audibly changes tempo
  4. Dragging the BPM slider rapidly does not flood the engine (updates are throttled/coalesced and the final value always arrives), and BPM values outside 60–180 sent to the engine are clamped to that range
  5. All engine audio passes through a master limiter: with the loop's gain pushed deliberately hot, output peaks stay at the limiter ceiling with no clipping

**Plans:** 2/3 plans executed

Plans:
**Wave 1**
- [x] 01-01-PLAN.md — Engine walking skeleton: tracer (Python OscClient → /pp/bpm → OSCdef → TempoClock) + kick/hat/bass loop, limiter, clamp and the headless smoke-test contract (wave 1)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 01-02-PLAN.md — Launchable BPM window: pytest legitimacy gate, ./run.sh + Tk compatibility gate, slider (send on release) + debounced nudge buttons (wave 2)

**Wave 3** *(blocked on Wave 2 completion)*
- [ ] 01-03-PLAN.md — Entry field + Up/Down/Shift shortcuts, all controls in sync, Tk 9 widget smoke test, end-to-end acceptance (wave 3)

**UI hint**: yes

### Phase 2: Full Groove & Smooth Tempo

**Goal:** As a rider, I want to start, stop and retempo a full trance groove from the app, so that tempo changes never jolt my ride.
**Mode:** mvp
**Depends on:** Phase 1
**Requirements:** ENG-01, TEMPO-01, TEMPO-02, GUI-02
**Success Criteria** (what must be TRUE):
  1. The engine plays drums, bass, arpeggio and pad together continuously in a melodic techno / progressive trance style, all locked to the same TempoClock
  2. When the user sets a new BPM, the music glides to it over roughly 1–2 bars, starting on a beat boundary, with no audible jolt and every layer staying in time
  3. When the user changes BPM again mid-glide, the music retargets from its current tempo without restarting or jumping
  4. User presses Stop in the app and the music stops cleanly (no hanging notes); pressing Start brings the full groove back in time

**Plans:** TBD
**UI hint**: yes

### Phase 3: EPIC Zones & Volume

**Goal:** As a rider, I want to pick my effort zone and set the volume, so that the music's energy matches my interval without clipping.
**Mode:** mvp
**Depends on:** Phase 2
**Requirements:** EPIC-01, EPIC-02, EPIC-03, GUI-03
**Success Criteria** (what must be TRUE):
  1. User clicks one of five zone buttons (Recovery / Endurance / Tempo / Threshold / VO2) and the engine moves to that zone's preset EPIC value
  2. Moving up the zones makes the music audibly brighter and more energetic, with filter cutoff, drive/saturation, reverb/delay amount and synth richness all moving together
  3. Switching zones glides smoothly to the new energy level with no stepping, zipper noise or clicks
  4. User adjusts master volume from the app and loudness changes smoothly; with VO2 selected and volume at maximum, the output still never clips

**Plans:** TBD
**UI hint**: yes

### Phase 4: Live Feedback & Ride Endurance

**Goal:** As a rider, I want to see the engine is alive and what it is actually playing, so that I can trust it through a full ride.
**Mode:** mvp
**Depends on:** Phase 3
**Requirements:** ENG-03, LINK-02, LINK-03
**Success Criteria** (what must be TRUE):
  1. The GUI shows "connected" while the engine runs. It switches to "disconnected" within a few seconds of quitting sclang (or if sclang was never started), and returns to "connected" on its own when the engine comes back
  2. The GUI shows the engine's actual current BPM, updating live through a tempo glide (mid-ramp values visible), and the current EPIC level as reported by the engine
  3. The GUI stays responsive while engine status streams in, with no freezes or crashes from status traffic
  4. User leaves the engine playing for 60+ minutes (with BPM and zone changes along the way, alongside Zwift) without audio dropouts, and the server's synth node count and CPU load stay flat

**Plans:** TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Tempo Link Skeleton | 2/3 | In Progress | - |
| 2. Full Groove & Smooth Tempo | 0/TBD | Not started | - |
| 3. EPIC Zones & Volume | 0/TBD | Not started | - |
| 4. Live Feedback & Ride Endurance | 0/TBD | Not started | - |
