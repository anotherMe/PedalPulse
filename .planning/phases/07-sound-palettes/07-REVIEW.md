---
phase: 07-sound-palettes
reviewed: 2026-10-20T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - README.md
  - supercollider/main.scd
  - supercollider/smoke_test.scd
findings:
  critical: 0
  warning: 2
  info: 1
  total: 3
status: issues_found
---

# Phase 7: Code Review Report

**Reviewed:** 2026-10-20
**Depth:** standard (incremental: changes since 1081b38, quick task 261015-uez)
**Files Reviewed:** 3
**Status:** issues_found

## Summary

This review covers only the master boost change: `~ppMasterBoost`, the `\boost` control in `\ppMaster`, the volume log line, the README paragraph, and the new "master boost" smoke check.

The DSP wiring is correct. `boost` defaults to 1, so scratch masters stay at unity. It sits before `Limiter.ar`, so the -1 dBFS ceiling still holds. It is passed at the only real `Synth(\ppMaster, ...)` site. The smoke check follows the existing probe pattern. It cleans up scratch nodes before asserting, and `fail` throws, so nothing falls through. `get` precision for float32 is well inside the 1e-4 tolerance.

The defects are in the user-tunable contract. The README invites retuning, but the gate rejects some values the README allows. Nothing at runtime guards a mistyped value.

No Critical issues. No structural findings were provided.

## Warnings

### WR-01: Smoke gate rejects values the README tells the user they may set

**File:** `supercollider/smoke_test.scd:1659-1661` (contract in `README.md:108` and `supercollider/main.scd:66-77`)
**Issue:** The README says "1.0 is the original level; keep it at 3.0 or below". The `main.scd` comment says the same. The smoke check (a) fails unless `2.0 <= ~ppMasterBoost <= 3.0`.

A user who follows the README and sets `~ppMasterBoost = 1.0` or `1.5` (quieter than the shipped default, but valid and documented) gets a failing `scripts/check.sh` gate. The failure message, "is not a number from 2.0 to 3.0", is not explained anywhere in the README. The 2.0 floor encodes the one-off task requirement ("at least double"), not an engine invariant. It is a policy assertion mixed into a functional smoke test.

**Fix:** Make the config-range check match the documented range, which is a positive number up to 3.0. Keep the "at least double" floor only as a test of the shipped default, for example by comparing against a constant in the test. If the floor stays, say so in the README.
```supercollider
if (~ppMasterBoost.isNumber.not or: { (~ppMasterBoost <= 0) or: { ~ppMasterBoost > 3.0 } }) {
	fail.("master boost", "~ppMasterBoost % is not a number above 0 and up to 3.0".format(~ppMasterBoost));
};
```
The gain and ceiling probes need `boost * 0.5 >= 0.9` to reach the limiter, which is a boost of at least 1.8. Guard probe (d) with that condition, or choose `preGain` as `max(1, 2 / ~ppMasterBoost)` so it always overdrives the limiter.

### WR-02: No runtime validation of the user-edited boost; a typo gives a full-scale blast

**File:** `supercollider/main.scd:77` and `supercollider/main.scd:233`
**Issue:** `~ppMasterBoost` is meant to be hand-edited, and the README documents that. Its only guard is the smoke test, which a user does not run before pressing evaluate. A typo such as `25` instead of `2.5`, or `~ppMasterBoost = nil` after a stray edit, is passed straight to `Synth(\ppMaster, ...)`.

- At 25, every signal is slammed into the limiter. The output is heavily clipped and sits at -1 dBFS the whole time. This is a hearing-safety and speaker-safety problem on a tool meant to be played next to a workout, and the limiter does not make it less loud.
- With a non-numeric value, the `Synth` constructor throws partway through the `waitForBoot` block. That leaves the engine half-built, with no master synth and `~ppReady` unset.

The comment's "Keep it at or below 3.0" is advisory only.

**Fix:** Sanitize it once at the definition and again where it is consumed, so a re-evaluation with a bad value degrades safely.
```supercollider
~ppMasterBoost = 2.5;
~ppMasterBoost = if (~ppMasterBoost.isNumber) { ~ppMasterBoost.clip(0.1, 3.0) } { 1.0 };
```
Log a warning when the value is clamped. If clamping is added, the README sentence "keep it at 3.0 or below" becomes enforced behavior and can say so.

## Info

### IN-01: README wording is imprecise and slightly self-contradictory

**File:** `README.md:108`
**Issue:** "plays about 2.5x louder" is an amplitude factor (+8 dB). Perceived loudness is roughly 1.9x. The `main.scd` comment correctly says "about +8 dB". Saying "2.5x louder" invites users to expect something different from what they hear. Also, "A limiter keeps the sound from clipping at any setting" sits next to "keep it at 3.0 or below". Both are true, but as written they read as contradicting each other. The limiter prevents digital clipping, while higher values still flatten (pump) the loud EPIC levels, as the `main.scd` comment explains.
**Fix:** Reword along the lines of: "PedalPulse now plays about 8 dB (2.5x in amplitude) louder... A limiter prevents clipping at any setting, but values above 3.0 will make loud passages sound squashed."

---

_Reviewed: 2026-10-20_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
