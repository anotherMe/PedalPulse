# Requirements: PedalPulse

**Defined:** 2026-10-11
**Milestone:** v2.0 Living Music
**Core Value:** Moving the BPM or EPIC control in the Python GUI audibly and smoothly changes the live, generated music in SuperCollider — the Python → OSC → SuperCollider chain works end to end.

## v2.0 Requirements

Requirements for this milestone. Each maps to roadmap phases. Research: `.planning/research/SUMMARY.md`.

### Library and modular engine (LIB)

- [ ] **LIB-01**: User starts the engine exactly as before, from `main.scd`. It loads the core plus library modules from `supercollider/library/`, and with only the `classic` entries selected it sounds like v1.0
- [ ] **LIB-02**: Each progression, melody style and palette is its own named `.scd` file under `library/progressions/`, `library/melodies/` or `library/palettes/`. The file name is its identity in the engine, the GUI and OSC
- [ ] **LIB-03**: New variations are added as new files and existing files are never overwritten, so every earlier variation can still be selected
- [ ] **LIB-04**: A broken or invalid library file never stops the music. The engine logs the error and keeps or falls back to `classic`
- [ ] **LIB-05**: A library file added or changed while the engine runs can be selected or reloaded without restarting the engine or interrupting playback
- [ ] **LIB-06**: An automated check validates every library file (loads, correct shape, voices respect limiter/Stop/gate) and runs with the smoke suite

### Harmony (HARM)

- [ ] **HARM-01**: Music follows a chord progression. Bass, arp, pad and lead always play over the same current chord, with no clashes at chord changes (GEN-01)
- [ ] **HARM-02**: At least 6 named progressions plus `classic` ship in the library
- [ ] **HARM-03**: Pad chords move smoothly between chords (voice-leading) instead of jumping
- [ ] **HARM-04**: User can select a progression (Auto or a named one). Changes take effect at the end of the current progression cycle

### Melody (MEL)

- [ ] **MEL-01**: A lead voice plays motifs built from the current chord and scale. A motif repeats, mutates one aspect at a time, and is replaced roughly every 16 bars
- [ ] **MEL-02**: The arp follows the current chord and changes pattern every few bars
- [ ] **MEL-03**: At least 3 named melody styles plus `classic` ship in the library; user can select Auto or a named style
- [ ] **MEL-04**: Each melody is generated from a seed that is logged, so a melody heard on a ride can be reproduced and saved as a library entry

### Sound palettes (PAL)

- [ ] **PAL-01**: At least 5 named palettes plus `classic` ship in the library. Each palette is a coherent set of lead, bass, pad, arp and drum sounds
- [ ] **PAL-02**: In Auto mode the engine rotates palettes on its own every few minutes, switching only at section or phrase boundaries
- [ ] **PAL-03**: Selecting a named palette locks it until Auto is selected again
- [ ] **PAL-04**: Palettes are loudness-matched, so switching causes no noticeable volume jump and never bypasses the limiter

### Song structure (STRU)

- [ ] **STRU-01**: Music changes on several timescales: fills at phrase ends, motif/arp changes every 8–16 bars, sections every few minutes (GEN-02)
- [ ] **STRU-02**: Sections cycle through groove, breakdown, build and drop
- [ ] **STRU-03**: At Threshold/VO2 breakdowns are short and kick + bass keep playing; full breakdowns only at low EPIC

### EPIC density (EPIC)

- [ ] **EPIC-04**: EPIC also controls how many layers play and how busy they are: sparse at Recovery, full-on at VO2. Changes apply on bar lines, combined with v1 brightness (GEN-03)
- [ ] **EPIC-05**: A manual EPIC change takes over at the next bar line, even in the middle of a section (it may cut the section short)

### GUI selectors (GUI)

- [ ] **GUI-05**: The GUI has palette, progression and melody-style selectors, each offering Auto plus every item found in the library folder on disk
- [ ] **GUI-06**: A selection reaches the engine over send-only OSC by name. Unknown names are ignored by the engine with a warning, and the GUI never crashes
- [ ] **GUI-07**: The selectors don't interfere with the existing BPM keyboard shortcuts

### Stability (ENG)

- [ ] **ENG-03**: (carried over from v1.0) 60+ minutes of play without dropouts, node growth or CPU growth, with the full v2.0 engine running next to Zwift
- [ ] **ENG-05**: Re-evaluating `main.scd` or a module never stacks routines or leaks nodes, and Stop silences every new layer and source

## Future Requirements

Deferred. Tracked but not in the current roadmap.

- **FX-01**: Reactive riser/fill when the EPIC zone changes
- **HARM-05**: Occasional key lift after a few sections
- **HARM-06**: Chord substitutions and mode-aware scales (Dorian, harmonic minor)
- **MEL-05**: Call-and-response lead; second lead voice at VO2
- **CTRL-01**: EPIC fine-tune slider (continuous 0–100) alongside presets
- **CTRL-02**: User-configurable BPM ramp time
- **AUTO-01**: Load a workout file (.zwo) and have BPM/EPIC follow its timeline
- **AUTO-02**: Derive BPM from a cadence sensor (ANT+/BLE)
- **AUTO-03**: Zwift integration (if a suitable API exists)
- **LINK-04**: Resync GUI state to the engine after an engine restart (v1.0 audit W2)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Fully random or Markov/ML melodies | Sounds aimless; rule-based motifs that repeat and mutate are the genre norm |
| Randomized drums or changes at random times | The genre's fixed drum grid and phrase-aligned changes are what keep it danceable |
| Long kick-less breakdowns at high EPIC | Fights the workout effort (see STRU-03) |
| Engine → GUI "now playing" display | The Python app stays send-only (decided 2026-10-10) |
| Library file watcher / automatic hot-reload | Selecting or explicitly reloading is enough; keeps the engine simple |
| Song endings / outros | The music runs for the whole ride |
| Live-coding by the rider | The user describes changes in words; Claude writes new library files |
| Multiple genres | v2.0 varies sound within melodic techno / progressive trance |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|

**Coverage:**
- v2.0 requirements: 28 total
- Mapped to phases: 0
- Unmapped: 28 ⚠️

---
*Requirements defined: 2026-10-11*
*Last updated: 2026-10-11 after initial definition*
