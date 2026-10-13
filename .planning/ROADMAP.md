# Roadmap: PedalPulse

## Milestones

- ✅ **v1.0 Technical Proof**: Phases 1-3 (shipped 2026-10-10). Full details are in [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md).
- 🚧 **v2.0 Living Music**: Phases 4-9 (in progress)

## Phases

<details>
<summary>✅ v1.0 Technical Proof (Phases 1-3), shipped 2026-10-10</summary>

- [x] Phase 1: Tempo Link Skeleton (3/3 plans), completed 2026-10-09
- [x] Phase 2: Full Groove & Smooth Tempo (4/4 plans), completed 2026-10-09
- [x] Phase 3: EPIC Zones & Volume (4/4 plans), completed 2026-10-09

</details>

## 🚧 v2.0 Living Music

**Milestone Goal:** Replace the fixed A-minor loop with music that keeps changing over a 60+ minute ride, in harmony, melody, sound and structure, built on a growing library of named variations that the rider can always switch back to.

### Overview

v2.0 follows the research build order: contract first, then harmony, palettes, melodies, and finally structure. Phase 4 splits the engine into a core plus a `supercollider/library/` of named files. Only `classic` entries exist at that point, so it still sounds like v1.0. Phase 5 adds the three library selectors to the GUI right away, earlier than the research order placed them. GUI-05, GUI-06 and GUI-07 each cover all three selectors, so they can't be split across the content phases without leaving half-built features. The GUI depends only on the folder layout and the selection addresses that Phase 4 creates. Each list is read from disk, so new progressions, palettes and melody styles appear in the selectors automatically as later phases add files. That means every later content phase is auditioned through the real GUI, by the same names the rider uses for feedback.

Phase 6 brings in the shared chord progression that every pitched layer follows. Phase 7 adds sound palettes with auto-rotation and lock. Phase 8 adds the rule-based lead and arp. Phase 9 adds song structure and EPIC-driven density, and it closes with the 60-minute real-ride soak (ENG-03). The soak is part of Phase 9, not a phase of its own: it needs the complete engine, and the same ride also serves as the listening test for each zone's density.

**Standing exit gate for every engine phase (4, 6, 7, 8, 9):** the smoke suite and the library check pass, Stop silences every new layer and source, and re-evaluating `main.scd` or a module leaves no stacked routines or leaked nodes (ENG-05, introduced in Phase 4). The Python app stays send-only throughout.

**Phase Numbering:**
- Integer phases (4, 5, 6): planned milestone work, continuing from v1.0
- Decimal phases (5.1, 5.2): urgent insertions (marked with INSERTED)

- [x] **Phase 4: Modular Engine & Variation Library** - The engine is split into a core plus `supercollider/library/` modules with `classic` entries and still sounds exactly like v1.0. Adds safe loading, fallback, reload by name and a library check (completed 2026-10-12)
- [x] **Phase 5: Library Selectors in the GUI** - Palette, Progression and Melody selectors list Auto plus every library file on disk and send the chosen name over send-only OSC (completed 2026-10-12)
- [x] **Phase 6: Shared Harmony & Progressions** - One chord progression drives bass, arp and pad together, with voice-led pads and at least 6 selectable progressions (completed 2026-10-13)
- [ ] **Phase 7: Sound Palettes** - At least 5 loudness-matched sound palettes that rotate on their own in Auto and lock when picked by name
- [ ] **Phase 8: Evolving Melodies** - A rule-based lead whose motifs repeat, mutate and get replaced, a chord-following arp, at least 3 melody styles, and logged seeds
- [ ] **Phase 9: Song Structure, EPIC Density & Ride Soak** - Fills, breakdown/build/drop sections and EPIC-driven layer density, proven on a real 60+ minute ride next to Zwift

## Phase Details

### Phase 4: Modular Engine & Variation Library

**Goal:** As a rider, I want the engine split into a core plus a library of named variation files, with no change to what I hear, so that new variations can be added as files and switched to without ever stopping the music.
**Mode:** mvp
**Depends on:** Phase 3 (shipped v1.0 engine)
**Requirements:** LIB-01, LIB-02, LIB-03, LIB-04, LIB-05, LIB-06, ENG-05
**Success Criteria** (what must be TRUE):
  1. User starts the engine from `main.scd` exactly as before and hears the v1.0 groove unchanged (only the `classic` entries exist). BPM glide, Start/Stop, EPIC zones and volume from the GUI behave exactly as in v1.0
  2. `supercollider/library/` holds `progressions/`, `melodies/` and `palettes/` folders, each with a `classic.scd`. Every file is known by its file name. A new variation is always added as a new file and never by editing an existing one, so every earlier file stays loadable and selectable
  3. A library file added or changed while the music plays can be selected by name over OSC (`/pp/progression`, `/pp/palette`, `/pp/melody`, taking `auto` or a file name), or reloaded, without restarting the engine and with no gap in playback. A broken or invalid file is refused with a post-window error that names it, and the music keeps playing on `classic`
  4. One command runs the existing smoke suite plus a new library check. The check validates every library file (it loads, has the right shape, and its voices go through the limiter and obey Stop and gate) and reports pass or fail
  5. Re-evaluating `main.scd` or a module several times leaves exactly one copy of every layer playing, with no extra nodes or routines, and Stop silences every layer and source

**Plans:** 6/6 plans complete

Plans:
**Wave 1**
- [x] 04-01-PLAN.md — Record the shipped groove (golden) from the unmodified engine with a proven parity check; `scripts/check.sh` with the never-overwrite guard

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 04-02-PLAN.md — Tracer: play every layer from `library/*/classic.scd` through the new loader and renderer (0 parity mismatches against the golden)

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 04-03-PLAN.md — The 7th layer (lead), `classic_lead.scd`, and select-by-name over `/pp/progression`, `/pp/palette`, `/pp/melody` with bar-line switching

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 04-04-PLAN.md — Broken files never stop the music: validation, refusal naming the file, last good copy, per-bar classic fallback, seeding

**Wave 5** *(blocked on Wave 4 completion)*
- [x] 04-05-PLAN.md — One command checks every library file: static tier, voice contract with negative controls, file-count cross-check, templates, README

**Wave 6** *(blocked on Wave 5 completion)*
- [x] 04-06-PLAN.md — ENG-05 gate: no stacking on re-evaluation, Stop silences the lead too, full check and the listening check

### Phase 5: Library Selectors in the GUI

**Goal:** As a rider, I want Palette, Progression and Melody selectors in the PedalPulse window, so that I can pick Auto or any named variation using the same names I use when giving feedback.
**Mode:** mvp
**Depends on:** Phase 4 (library folders and selection addresses)
**Requirements:** GUI-05, GUI-06, GUI-07
**Success Criteria** (what must be TRUE):
  1. The window shows Palette, Progression and Melody selectors. Each one lists Auto first, then every variation file found in its library folder on disk (hidden and `_template` files are skipped). An empty or missing folder shows Auto only. Relaunching the app picks up newly added files
  2. Picking an item sends its name to the engine over OSC, only when the choice actually changes, and the engine's post window confirms the selection it received. The app stays send-only and keeps working when the engine is not running
  3. A name the engine doesn't know (for example, a file deleted after the app started) is ignored by the engine with a warning while the music keeps playing, and the GUI never crashes
  4. After using any selector, the Up/Down arrow keys and the other BPM shortcuts still change BPM exactly as before. The selectors never take keyboard focus

**Plans:** 3/3 plans complete

Plans:
**Wave 1**
- [x] 05-01-PLAN.md — Tracer: a Melody pick in the window reaches the engine over UDP; then Palette, Progression and Melody in a right-hand column, with auto sent to all three at launch

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 05-02-PLAN.md — The dropdowns only offer names the engine accepts (test-first scan rule); the send-on-change and never-crash send contracts proven

**Wave 3** *(blocked on Wave 2 completion; no shared files with 05-02, but its full-suite gate runs 05-02's tests, so it waits for 05-02's GREEN commit)*
- [x] 05-03-PLAN.md — A new file appears when a dropdown is opened; the BPM keys keep working (GUI-07); README section; engine library check; the rider's end-of-phase selector check

**UI hint**: yes

### Phase 6: Shared Harmony & Progressions

**Goal:** As a rider, I want the music to move through chord progressions that bass, arp and pad follow together, so that it stops sounding like the same few notes for an hour.
**Mode:** mvp
**Depends on:** Phase 5 (Progression selector, used to audition progressions)
**Requirements:** HARM-01, HARM-02, HARM-03, HARM-04
**Success Criteria** (what must be TRUE):
  1. The music moves through a chord progression. Bass, arp and pad change chord together, with no clashing notes at chord changes, including during BPM glides and after Stop/Start. The lead added in Phase 8 follows the same chord
  2. Pad chords move smoothly to the nearest voicing of the next chord instead of jumping
  3. The Progression selector lists at least 6 named progressions plus `classic`, and each one sounds distinct. On Auto, the engine chooses progressions on its own
  4. Picking a named progression switches to it at the end of the current progression cycle, never mid-cycle, and it stays until another choice is made
  5. The standing exit gate holds: Stop silences every layer, re-evaluating stacks nothing, and the smoke suite plus the library check pass with every progression file

**Plans:** 5/5 plans complete

Plans:
**Wave 1**
- [x] 06-01-PLAN.md — Tracer: pick anthem and bass, pad, arp and lead all play Am F C G together (memoized harmony entry, core bass/pad, chord-follow mapping); a mid-cycle pick waits for the cycle end

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 06-02-PLAN.md — The strict harmony gate before more files are frozen: exact rule tables, classic byte-identical, bounded memo, strict chord-data static branch, malformed-data refusals, chord-follow recording for every progression on disk

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 06-03-PLAN.md — Six more progressions (rocker, lift, return, deep, melancholy, drama) pinned by a table check, chord-data template, names in the app

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 06-04-PLAN.md — Auto: classic first, a new progression every 2-3 minutes at cycle ends, no quick repeats, new files join; bounded, failing and broken files handled

**Wave 5** *(blocked on Wave 4 completion)*
- [x] 06-05-PLAN.md — Exit gate on the real engine (Stop/Start and re-evaluation with anthem and auto), README and melody template, full gate, the rider's listening check

### Phase 7: Sound Palettes

**Goal:** As a rider, I want the engine to change its whole sound set every few minutes, or keep one I like, so that a long ride never sounds the same and I can name what I want more or less of.
**Mode:** mvp
**Depends on:** Phase 6
**Requirements:** PAL-01, PAL-02, PAL-03, PAL-04
**Success Criteria** (what must be TRUE):
  1. The Palette selector lists at least 5 named palettes plus `classic`. Each palette is a coherent set of lead, bass, pad, arp and drum sounds, recognisably different from the others
  2. With Palette on Auto, the sound changes to another palette on its own every few minutes, always at a phrase boundary and never mid-phrase
  3. Picking a named palette locks it. It stays for the rest of the ride until Auto is picked again
  4. Switching palettes causes no noticeable volume jump, and VO2 at volume 100 on the loudest palette still never clips
  5. The standing exit gate holds for every palette (Stop silences its voices, nothing bypasses the limiter). CPU with the heaviest palette at VO2 is measured on the riding Mac and stays within the agreed budget for running next to Zwift

**Plans:** TBD

### Phase 8: Evolving Melodies

**Goal:** As a rider, I want a lead melody that develops over the ride, repeating, varying and moving on, so that the music has hooks instead of a fixed list of notes.
**Mode:** mvp
**Depends on:** Phase 7 (palettes supply the lead sound; harmony from Phase 6 supplies chord and scale)
**Requirements:** MEL-01, MEL-02, MEL-03, MEL-04
**Success Criteria** (what must be TRUE):
  1. A lead voice plays short motifs built from the current chord and scale. Each motif repeats, changes one thing at a time, and is replaced by a new one roughly every 16 bars
  2. The arp follows the current chord and switches to a different pattern every few bars, without masking the lead
  3. The Melody selector lists at least 3 named melody styles plus `classic`. Auto or a picked style audibly changes how the lead and arp behave
  4. The seed of each melody is posted to the post window. Replaying that seed reproduces the same melody, so a melody heard on a ride can be saved as a new library entry
  5. The standing exit gate holds with the lead playing: Stop silences the lead too, re-evaluating stacks nothing, and the smoke suite plus the library check pass with every melody style

**Plans:** TBD

### Phase 9: Song Structure, EPIC Density & Ride Soak

**Goal:** As a rider, I want the music to build, break down and drop on its own, thin out or fill up with my effort zone, and run my whole ride without a glitch, so that a 60+ minute workout feels like a set that follows my intervals.
**Mode:** mvp
**Depends on:** Phase 8 (structure and density read harmony, palettes and melodies)
**Requirements:** STRU-01, STRU-02, STRU-03, EPIC-04, EPIC-05, ENG-03
**Success Criteria** (what must be TRUE):
  1. Over a ride, the music changes on several timescales: fills at phrase ends, motif or arp changes every 8–16 bars, and a new section (groove, breakdown, build, drop) every few minutes. In Auto, palette changes land on section boundaries
  2. Recovery sounds sparse (few, light layers) and VO2 sounds full-on (every layer, busiest patterns). Each zone in between adds or removes layers on bar lines, together with the v1.0 brightness change
  3. Clicking an EPIC zone mid-section takes effect at the next bar line, even if that cuts a breakdown or build short
  4. At Threshold and VO2, breakdowns are short and kick and bass keep playing. Long, full breakdowns happen only at low EPIC
  5. A real 60+ minute ride next to Zwift with the full v2.0 engine has no audio dropouts, and synth node count and CPU stay flat. An accelerated soak in the test suite checks the same thing in minutes

**Plans:** TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 4 → 5 → 6 → 7 → 8 → 9

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Tempo Link Skeleton | v1.0 | 3/3 | Complete | 2026-10-09 |
| 2. Full Groove & Smooth Tempo | v1.0 | 4/4 | Complete | 2026-10-09 |
| 3. EPIC Zones & Volume | v1.0 | 4/4 | Complete | 2026-10-09 |
| 4. Modular Engine & Variation Library | v2.0 | 6/6 | Complete    | 2026-10-12 |
| 5. Library Selectors in the GUI | v2.0 | 3/3 | Complete    | 2026-10-12 |
| 6. Shared Harmony & Progressions | v2.0 | 5/5 | Complete    | 2026-10-13 |
| 7. Sound Palettes | v2.0 | 0/TBD | Not started | - |
| 8. Evolving Melodies | v2.0 | 0/TBD | Not started | - |
| 9. Song Structure, EPIC Density & Ride Soak | v2.0 | 0/TBD | Not started | - |
