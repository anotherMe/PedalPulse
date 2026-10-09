---
status: testing
phase: 01-tempo-link-skeleton
source: [01-VERIFICATION.md]
started: 2026-10-09T08:20:00Z
updated: 2026-10-09T08:20:00Z
---

## Current Test

number: 1
name: Listen to the groove and the limiter ceiling in the SC IDE (Plan 01)
expected: |
  Kick + offbeat hat + A-minor offbeat bass loop at 120 BPM, snapping audibly to 180 then 60 BPM on the next beat
  when 300 and 10 are sent via osc_client.py; with ~preGain = 8.0 the meter holds at about -1 dBFS with no clip
  indicator and no crackle; re-evaluating main.scd never doubles the loop.
awaiting: user response

## Tests

### 1. Listen to the groove and the limiter ceiling in the SC IDE (Plan 01, D-17/D-13)
How: evaluate `supercollider/main.scd` in the SC IDE; send `300` then `10` with `.venv/bin/python python_app/osc_client.py 300` / `... 10`; set `~preGain = 8.0`, re-evaluate, open `s.meter`, listen ~10 s; restore `~preGain = 1.0` and re-evaluate.
expected: Kick + offbeat hat + A-minor offbeat bass loop at 120 BPM, snapping audibly to 180 then 60 BPM on the next beat; with preGain 8 the meter holds at about -1 dBFS with no clip indicator and no crackle; re-evaluating never doubles the loop.
result: [pending]

### 2. Launch the BPM window, drag the slider, click nudges, toggle "On top" (Plan 02)
How: with `main.scd` running, launch `./run.sh`; drag the slider, click the nudge buttons, then tick "On top" while a full-screen app is frontmost.
expected: Window is compact and shows "Sending to 127.0.0.1:57120"; dragging updates the display live and the SC post window shows a single `/pp/bpm` line only after release; nudges show one net line; the window floats over the full-screen app only when "On top" is ticked.
result: [pending]

### 3. End-to-end acceptance walk-through (Plan 03)
How: evaluate `main.scd`, run `./run.sh`, then (1) drag+release the slider, (2) type 140 + Enter, (3) type abc + Enter, (4) type 300 + click away, (5) press Up ×3 quickly, (6) hold Shift+Down ~1 s, (7) click −5 then +1, (8) tick "On top" over Zwift.
expected: After every gesture the slider, entry and audible tempo agree and the loop retempos on the next beat; the SC post window shows exactly one `/pp/bpm` line per gesture (never a stream during a drag or key hold); "abc" reverts without sending; 300 snaps to 180; three quick Up presses produce one line with net +3; the held Shift+Down produces one line after release; the window floats over Zwift when "On top" is ticked.
result: [pending]

### 4. OSC-port-mismatch warning appears when sclang is not on 57120
How: start one sclang instance so it holds port 57120, boot another, and evaluate `main.scd` in it.
expected: The posted "PedalPulse: listening for OSC on port <N>" line (N ≠ 57120) is immediately followed by "PedalPulse WARNING: OSC port is <N> but python_app/config.py sends to 57120 -- quit other sclang instances or pass --port <N>".
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
