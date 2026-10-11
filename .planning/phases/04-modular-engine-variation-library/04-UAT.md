---
status: testing
phase: 04-modular-engine-variation-library
source: [04-VERIFICATION.md]
started: 2026-10-11T20:43:02Z
updated: 2026-10-11T20:43:02Z
---

## Current Test

number: 1
name: Rider listening check (D-01, D-06)
expected: |
  Default startup sounds like the shipped v1.0 engine (same drums, bass, arp, pad, same loudness; BPM glide, Start/Stop, EPIC zones and volume unchanged). /pp/melody classic_lead only adds a faint octave-up shimmer to the arp from the next bar, not a new tune; Stop silences the shimmer too; /pp/melody classic removes it again.
awaiting: user response

## Tests

### 1. Rider listening check (D-01, D-06)
steps: Evaluate supercollider/main.scd in the IDE as always and run ./run.sh. Listen for a minute; move BPM, press Stop/Start, click effort zones, move volume. Then send /pp/melody classic_lead with the python one-liner in supercollider/library/README.md, press Stop (shimmer goes quiet too) and Start, then send /pp/melody classic.
expected: Default startup sounds like the shipped v1.0 engine (same drums, bass, arp, pad, same loudness; BPM glide, Start/Stop, EPIC zones and volume unchanged). classic_lead only thickens the arp with a faint octave-up shimmer from the next bar; Stop silences it; /pp/melody classic removes it.
result: [pending]

### 2. Decision on code-review warnings WR-01 and WR-02
expected: Accept them as hardening for a later phase (record `deferred` with a reason in 04-REVIEW-DISPOSITION.md), or ask for a gap-closure plan before later phases add more library content. WR-01: row validation has no upper bounds (row count, legato, note range). WR-02: a refused palette leaves its SynthDefs behind, and falling back to classic does not restore classic's voices.
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
