---
status: complete
phase: 05-library-selectors-in-the-gui
source: [05-VERIFICATION.md]
started: 2026-10-12T12:24:59Z
updated: 2026-10-12T15:11:29.498Z
---

## Current Test

[testing complete]

## Tests

### 1. Launch shows three dropdowns on Auto and the engine confirms auto
expected: A column on the right shows Palette, Progression and Melody, each on Auto. The post window shows one 'auto -> auto (resolves to classic)' line each for /pp/palette, /pp/progression and /pp/melody.
result: pass

### 2. Picking a melody changes the music; picking it again sends nothing
expected: Open the Melody dropdown with a normal click: it lists Auto, classic, classic_lead, classic_lead_loud. Pick classic_lead_loud: from the next bar the louder lead is audible and the post window shows '/pp/melody classic_lead_loud -> selected'. Pick it again: no new line.
result: pass

### 3. BPM keys still work after using a dropdown
expected: Right after using a dropdown, Up, Down, Shift-Up and Shift-Down change the BPM by 1, 1, 5 and 5, exactly as before.
result: pass

### 4. A new file shows up without a restart
expected: cp supercollider/library/melodies/_template.scd supercollider/library/melodies/zz_try.scd, then open the Melody dropdown: zz_try is at the bottom. rm the file and open it again: zz_try is gone. (Leave no zz_try.scd behind: a stray file fails the library file-count check.)
result: pass

### 5. An unknown name is refused and the music keeps playing
expected: .venv/bin/python -c "from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/melody', 'no_such_melody')" makes the post window show 'PedalPulse ERROR: library file ... does not exist' and '... refused -- still playing ...'; the music continues without a gap.
result: pass

### 6. No crash with the engine stopped
expected: Pick Auto in the Melody dropdown, quit SuperCollider, then pick items in each dropdown: the app keeps working, with no freeze and no error window.
result: pass

## Summary

total: 6
passed: 6
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
