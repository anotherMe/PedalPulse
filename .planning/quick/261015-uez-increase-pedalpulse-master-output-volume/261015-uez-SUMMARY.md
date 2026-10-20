---
phase: 261015-uez-increase-pedalpulse-master-output-volume
plan: 01
status: complete
completed: 2026-10-20
commits: [f75fde8]
files_modified:
  - supercollider/main.scd
  - supercollider/smoke_test.scd
  - README.md
---

# Quick 261015-uez: 2.5x master loudness boost

PedalPulse now plays 2.5x louder (about +8 dB) so it can be heard next to Zwift without turning the Mac's volume way up. The boost is one constant, `~ppMasterBoost = 2.5;` in `supercollider/main.scd`, applied in `\ppMaster` before the −1 dBFS limiter. It cannot be set over OSC; the Python app is unchanged.

## What changed

- **Task 1 (f75fde8):** `~ppMasterBoost` and a `\boost` control in `SynthDef(\ppMaster)`; new "master boost" smoke check (config range, live wiring, gain probe, limiter ceiling).
- **Task 2:** README note on the louder default and how to retune it (1.0 is the original level; keep it at 3.0 or below).

## Gate (scripts/check.sh, 2026-10-20): CHECK PASS

| Measurement | Value |
|-------------|-------|
| Output peak at volume 100 (EPIC 10) | 0.619 (0.24 before the boost) |
| Volume 50 / volume 100 ratio | 0.234 (squared taper, expected 0.25) |
| master boost probe | gain 0.4, ceiling 0.891 — CHECK OK |
| VO2 + volume 100 output peak | 0.8913 (held at the limiter ceiling 0.891251) |
| Palette meter | PALETTE PASS |

The `FAILURE IN SERVER /n_set Node … not found` lines in the smoke log are the existing Stop broadcast reaching nodes that have already freed themselves; they do not fail any check.

## Deviations

- The session paused before Task 2 was committed. A local experiment raised the boost to 8.5; the rider reverted it to 2.5 before closing the task (8.5 is past the ~3.5 point where the limiter pumps and the "volume scales output" smoke check fails).

## Human check

The rider confirmed the listening check (audible next to Zwift, VO2 clean at volume 100) as part of the Phase 07 UAT on 2026-10-20.
