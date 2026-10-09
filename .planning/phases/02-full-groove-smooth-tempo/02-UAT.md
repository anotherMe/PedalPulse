---
status: testing
phase: 02-full-groove-smooth-tempo
source: [02-VERIFICATION.md]
started: 2026-10-09T15:42:23Z
updated: 2026-10-09T15:42:23Z
---

## Current Test

number: 1
name: Groove style at 120 BPM
expected: |
  Evaluate supercollider/main.scd in the SuperCollider IDE, then run ./run.sh. Listen for at least 8 bars at 120 BPM.
  The groove reads as melodic techno / progressive trance: four-on-the-floor kick, offbeat hat, clap on 2 and 4,
  rolling A-minor bass, 16th-note arpeggio and a sustained pad, all in time.
awaiting: user response

## Tests

### 1. Groove style at 120 BPM
expected: Four-on-the-floor kick, offbeat hat, clap on 2 and 4, rolling A-minor bass, 16th-note arpeggio and sustained pad, all in time; reads as melodic techno / progressive trance (ENG-01)
result: [pending]

### 2. Glide and mid-glide retarget
expected: Drag the BPM slider 120 → 170 and release; while still gliding, type 90 in the entry and press Enter. Each change is a smooth speed-up/slow-down over about two bars; the retarget bends from wherever the tempo is, with no jump, stutter or restart, and no layer drifts out of time (TEMPO-01, TEMPO-02)
result: [pending]

### 3. Rapid nudges keep retargeting smoothly
expected: Click +5 several times, then −5 several times, quickly. The target keeps changing mid-glide with no jump, stutter or restart, and every layer stays in time (TEMPO-02)
result: [pending]

### 4. Stop tail and Start
expected: Press Stop right after a new pad chord starts. Short natural tail (pad fades in about a second), no click, no note left hanging. Press Start: every layer comes back together on a bar line, bass and pad from the start of their phrase (GUI-02)
result: [pending]

### 5. Repeated Stop/Start and button label
expected: Press Stop and Start a few times at different points in the bar. Button always reads "Stop" while music plays and "Start" while silent; the SC post window shows one /pp/play line per click; Start always lands on a bar line (GUI-02)
result: [pending]

### 6. Optional: coexistence with Zwift
expected: Repeat tests 1–4 with Zwift running and watch the IDE's CPU readout. No audible dropouts; CPU stays modest (the 60-minute soak is Phase 4, ENG-03)
result: [pending]

## Summary

total: 6
passed: 0
issues: 0
pending: 6
skipped: 0
blocked: 0

## Gaps
