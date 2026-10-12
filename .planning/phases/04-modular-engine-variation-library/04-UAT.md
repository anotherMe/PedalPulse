---
status: complete
phase: 04-modular-engine-variation-library
source: [04-01-SUMMARY.md, 04-02-SUMMARY.md, 04-03-SUMMARY.md, 04-04-SUMMARY.md, 04-05-SUMMARY.md, 04-06-SUMMARY.md, 04-VERIFICATION.md]
started: 2026-10-12T06:52:34Z
updated: 2026-10-12T06:59:41.313Z
---

## Current Test

[testing complete]

## Tests

### 1. Default startup sounds like v1.0
expected: Evaluate supercollider/main.scd as always and run ./run.sh, sending no library commands. The music is the same groove as before the split: same drums, bass, arpeggio and pad, same loudness. BPM glide, Start/Stop, the effort-zone buttons and the volume slider all behave as before.
result: pass

### 2. classic_lead adds a faint shimmer
expected: Sending /pp/melody classic_lead (one-liner in supercollider/library/README.md) adds a faint octave-up shimmer to the arpeggio from the next bar, without stopping the music; it thickens the arp and is not a new tune. Sending /pp/melody classic removes it.
result: pass

### 3. Stop silences the added lead
expected: With a lead melody playing (classic_lead_loud makes it audible), pressing Stop silences everything including the lead; Start brings the music back on a bar line.
result: pass

### 4. Library README is understandable
expected: supercollider/library/README.md explains in plain words how to add a variation (always a new file, never edit an old one), how to try one by name with the copy-paste one-liners, and how to run the check.
result: pass

### 5. Decision on code-review warnings WR-01 and WR-02
expected: Accept them as hardening for a later phase, or ask for a fix plan now. WR-01: library files are not checked for absurd values (thousands of notes in a bar, extreme pitches). WR-02: a refused palette file can leave its synth sounds behind, and falling back to classic does not restore classic's sounds.
result: pass

### 6. Golden recorded from the unmodified engine: 496 rows, per-layer counts 64/64/32/64/256/16, effective amps 0.1/0.1/0.25/0.1/0.1/0.06
expected: Golden recorded from the unmodified engine: 496 rows, per-layer counts 64/64/32/64/256/16, effective amps 0.1/0.1/0.25/0.1/0.1/0.06
result: pass
source: automated
coverage_id: D1 (04-01-SUMMARY.md)

### 7. Note-level parity check passes on the unmodified engine with 0 mismatches in every column (recording is repeatable)
expected: Note-level parity check passes on the unmodified engine with 0 mismatches in every column (recording is repeatable)
result: pass
source: automated
coverage_id: D2 (04-01-SUMMARY.md)

### 8. Never-overwrite guard with self-test (modify, delete, rename, golden fail; new and re-saved files pass; non-git prints CHECK SKIP)
expected: Never-overwrite guard with self-test (modify, delete, rename, golden fail; new and re-saved files pass; non-git prints CHECK SKIP)
result: pass
source: automated
coverage_id: D3 (04-01-SUMMARY.md)

### 9. One command runs guard, library check and smoke suite (CHECK PASS)
expected: One command runs guard, library check and smoke suite (CHECK PASS)
result: pass
source: automated
coverage_id: D4 (04-01-SUMMARY.md)

### 10. Engine emits the shipped groove note for note from the library: 16-bar parity, 0 mismatches against the unchanged golden (496 rows)
expected: Engine emits the shipped groove note for note from the library: 16-bar parity, 0 mismatches against the unchanged golden (496 rows)
result: pass
source: automated
coverage_id: D1 (04-02-SUMMARY.md)

### 11. Each classic file is registered under its category and file stem; the loader sets name, path, category and rev
expected: Each classic file is registered under its category and file stem; the loader sets name, path, category and rev
result: pass
source: automated
coverage_id: D2 (04-02-SUMMARY.md)

### 12. main.scd holds no per-note voice or layer pattern literal; infrastructure SynthDefs (master, epic smoother, fx) remain
expected: main.scd holds no per-note voice or layer pattern literal; infrastructure SynthDefs (master, epic smoother, fx) remain
result: pass
source: automated
coverage_id: D3 (04-02-SUMMARY.md)

### 13. Existing smoke checks pass unchanged (BPM glide, Start/Stop, EPIC, volume, limiter, re-evaluation): 67 CHECK OK lines
expected: Existing smoke checks pass unchanged (BPM glide, Start/Stop, EPIC, volume, limiter, re-evaluation): 67 CHECK OK lines
result: pass
source: automated
coverage_id: D4 (04-02-SUMMARY.md)

### 14. /pp/melody classic_lead brings in a faint lead doubling the arp one octave up from a bar line, with no missing arp sixteenth; /pp/melody classic returns to the shipped sound
expected: /pp/melody classic_lead brings in a faint lead doubling the arp one octave up from a bar line, with no missing arp sixteenth; /pp/melody classic returns to the shipped sound
result: pass
source: automated
coverage_id: D1 (04-03-SUMMARY.md)

### 15. Re-sending a name re-reads its file from disk (rev goes up); the documented python-osc one-liner works; auto plays classic
expected: Re-sending a name re-reads its file from disk (rev goes up); the documented python-osc one-liner works; auto plays classic
result: pass
source: automated
coverage_id: D2 (04-03-SUMMARY.md)

### 16. Invalid names (empty, number, uppercase, trailing newline, non-ASCII, space, ../x, leading _, 65 characters, ../../main) are ignored with a WARNING before any path is built; an unknown name logs an ERROR naming the file and changes nothing; back-to-back selections end on the second
expected: Invalid names (empty, number, uppercase, trailing newline, non-ASCII, space, ../x, leading _, 65 characters, ../../main) are ignored with a WARNING before any path is built; an unknown name logs an ERROR naming the file and changes nothing; back-to-back selections end on the second
result: pass
source: automated
coverage_id: D3 (04-03-SUMMARY.md)

### 17. Seven layers in the engine with the lead silent under classic: parity still 0 mismatches over 496 rows and the smoke suite passes unchanged (67 checks) with the 7th layer in the expected set
expected: Seven layers in the engine with the lead silent under classic: parity still 0 mismatches over 496 rows and the smoke suite passes unchanged (67 checks) with the 7th layer in the expected set
result: pass
source: automated
coverage_id: D4 (04-03-SUMMARY.md)

### 18. A broken or invalid library file never stops the music: syntax error, throw on load, empty, comment-only, not an Event, missing desc, wrong shape, symlink outside the library, palette defs that throw, palette naming a missing voice, a progression with a non-Function, and a missing name are each refused with an ERROR line naming the file; the selection is unchanged and all six sounding layers keep their per-bar counts for 40 bars
expected: A broken or invalid library file never stops the music: syntax error, throw on load, empty, comment-only, not an Event, missing desc, wrong shape, symlink outside the library, palette defs that throw, palette naming a missing voice, a progression with a non-Function, and a missing name are each refused with an ERROR line naming the file; the selection is unchanged and all six sounding layers keep their per-bar counts for 40 bars
result: pass
source: automated
coverage_id: D1 (04-04-SUMMARY.md)

### 19. A generator that throws, or returns a bar that fills 3.5 beats, keeps its layer playing the classic part; the third failure returns the category to classic with an ERROR line naming the file
expected: A generator that throws, or returns a bar that fills 3.5 beats, keeps its layer playing the classic part; the third failure returns the category to classic with an ERROR line naming the file
result: pass
source: automated
coverage_id: D2 (04-04-SUMMARY.md)

### 20. A valid file added while the engine runs is selectable by name; a changed file plays from a bar line with no bar mixing old and new rows; a broken edit keeps the last good copy playing; a broken selection racing a valid one never becomes the selection
expected: A valid file added while the engine runs is selectable by name; a changed file plays from a bar line with no bar mixing old and new rows; a broken edit keeps the last good copy playing; a broken selection racing a valid one never becomes the selection
result: pass
source: automated
coverage_id: D3 (04-04-SUMMARY.md)

### 21. Every library file is validated by the same pure functions the tests use: rows summing to 4.0 within 1e-6 pass, 3.5 and 4.5 fail, empty, a dur of 0, an amp of 1.5, a string note and a 3-item row fail; unknown keys are ignored
expected: Every library file is validated by the same pure functions the tests use: rows summing to 4.0 within 1e-6 pass, 3.5 and 4.5 fail, empty, a dur of 0, an amp of 1.5, a string note and a 3-item row fail; unknown keys are ignored
result: pass
source: automated
coverage_id: D4 (04-04-SUMMARY.md)

### 22. Seeds replay bar for bar after a restart, and the plan's bar equals the played bar across a tempo change (research VERIFY flags)
expected: Seeds replay bar for bar after a restart, and the plan's bar equals the played bar across a tempo change (research VERIFY flags)
result: pass
source: automated
coverage_id: D5 (04-04-SUMMARY.md)

### 23. bash scripts/check.sh validates every library file (selectable files and templates) without a server: loads, is an Event with a desc, right shape, no load-time side effects, no forbidden calls, generators fill 4 beats over 16 bars and replay from the same seed; one LIBCHECK OK line per file, and check.sh fails if the count differs from the files on disk
expected: bash scripts/check.sh validates every library file (selectable files and templates) without a server: loads, is an Event with a desc, right shape, no load-time side effects, no forbidden calls, generators fill 4 beats over 16 bars and replay from the same seed; one LIBCHECK OK line per file, and check.sh fails if the count differs from the files on disk
result: pass
source: automated
coverage_id: D1 (04-05-SUMMARY.md)

### 24. Six kinds of bad file each make the static check fail, naming the file or category
expected: Six kinds of bad file each make the static check fail, naming the file or category
result: pass
source: automated
coverage_id: D2 (04-05-SUMMARY.md)

### 25. Every selectable stem round-trips through the primary use path (registered under category and stem, rendered by ~ppRenderBar with no classic fallback); every category has classic.scd
expected: Every selectable stem round-trips through the primary use path (registered under category and stem, rendered by ~ppRenderBar with no classic fallback); every category has classic.scd
result: pass
source: automated
coverage_id: D3 (04-05-SUMMARY.md)

### 26. Every palette voice writes only to its own out bus, releases on gate 0 and frees itself; a bus 0 writer, a voice without doneAction and a voice without gate each fail the same check
expected: Every palette voice writes only to its own out bus, releases on gate 0 and frees itself; a bus 0 writer, a voice without doneAction and a voice without gate each fail the same check
result: pass
source: automated
coverage_id: D4 (04-05-SUMMARY.md)

### 27. All 7 layer Pbindefs keep quant 4 after a Stop and a Start with doReset
expected: All 7 layer Pbindefs keep quant 4 after a Stop and a Start with doReset
result: pass
source: automated
coverage_id: D5 (04-05-SUMMARY.md)

### 28. Re-evaluating main.scd three times while playing leaves exactly one copy of everything: 7 Pdefs, 7 EventStreamPlayers and 1 Routine on the live clock, and identical clock, group, SynthDef and OSCdef counts
expected: Re-evaluating main.scd three times while playing leaves exactly one copy of everything: 7 Pdefs, 7 EventStreamPlayers and 1 Routine on the live clock, and identical clock, group, SynthDef and OSCdef counts
result: pass
source: automated
coverage_id: D1 (04-06-SUMMARY.md)

### 29. Re-evaluating validate.scd, loader.scd and render.scd twice each while playing changes no counts, every role keeps rendering notes, and the registry keeps classic and classic_lead
expected: Re-evaluating validate.scd, loader.scd and render.scd twice each while playing changes no counts, every role keeps rendering notes, and the registry keeps classic and classic_lead
result: pass
source: automated
coverage_id: D2 (04-06-SUMMARY.md)

### 30. A selection survives re-evaluation: classic_lead is still selected and the lead still plays after three re-evaluations; no ERROR or 'playing classic for this bar' line appears
expected: A selection survives re-evaluation: classic_lead is still selected and the lead still plays after three re-evaluations; no ERROR or 'playing classic for this bar' line appears
result: pass
source: automated
coverage_id: D3 (04-06-SUMMARY.md)

### 31. Stop silences every layer with the classic_lead lead playing: empty instrument group within 2.5 s, no role renders another bar, no Pbindef plays
expected: Stop silences every layer with the classic_lead lead playing: empty instrument group within 2.5 s, no role renders another bar, no Pbindef plays
result: pass
source: automated
coverage_id: D4 (04-06-SUMMARY.md)

### 32. The whole phase passes the one-command gate and the Python suite
expected: The whole phase passes the one-command gate and the Python suite
result: pass
source: automated
coverage_id: D5 (04-06-SUMMARY.md)

## Summary

total: 32
passed: 32
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps
