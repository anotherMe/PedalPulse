---
phase: 07-sound-palettes
reviewed: 2026-10-13T00:00:00Z
depth: standard
files_reviewed: 21
files_reviewed_list:
  - scripts/check.sh
  - scripts/palette_cpu.sh
  - scripts/palette_level.sh
  - scripts/smoke_test.sh
  - supercollider/core/harmony.scd
  - supercollider/core/loader.scd
  - supercollider/core/render.scd
  - supercollider/core/validate.scd
  - supercollider/library/README.md
  - supercollider/library/palettes/_template.scd
  - supercollider/library/palettes/acid.scd
  - supercollider/library/palettes/air.scd
  - supercollider/library/palettes/dark.scd
  - supercollider/library/palettes/pluck.scd
  - supercollider/library/palettes/supersaw.scd
  - supercollider/library/palettes/warm.scd
  - supercollider/library/progressions/_template.scd
  - supercollider/library_test.scd
  - supercollider/main.scd
  - supercollider/palette_meter.scd
  - supercollider/smoke_test.scd
findings:
  critical: 0
  warning: 2
  info: 4
  total: 6
status: issues_found
---

# Phase 7: Code Review Report

**Reviewed:** 2026-10-13
**Depth:** standard
**Files Reviewed:** 21

## Summary

The core (loader, validate, render, harmony), the shell scripts, the palette meter and the six palette files were read in full. `library_test.scd` (3833 lines) and `smoke_test.scd` (2633 lines) were reviewed structurally only (watchdogs, process and file handling, cleanup, exit paths) and not line by line. Nothing was executed.

No crash, data-loss or security defect was found. Specifically:
- Palette names are validated by an ASCII loop in `~ppStemValid` before any path is built.
- The shell scripts re-validate names with an anchored regex before they reach sclang.
- The defs guard (`~ppPaletteDefs`) snapshots and diffs `SynthDescLib`, and undoes on refusal.
- `SynthDef.removeAt` exists in the installed class library, and it sends `/d_free`.
- The row validator bounds are consistent.
- The bass styles sum to 4 beats and meet the validator.

The two warnings are a hole in the voice-namespace rule that the phase set out to close, and a fixed test time budget against a library designed to grow without bound. The remaining items are informational.

## Warnings

### WR-01: Voice-namespace rule can be bypassed with a longer palette name (prefix collision)

**File:** `supercollider/core/validate.scd:256-262`, `supercollider/core/loader.scd:187-193`
**Issue:** The WR-02 rule ("a palette may only use its own voices") is a plain `beginsWith("pp_<stem>_")` test, in both the validator for roles and the defs guard for added voices.
- Stems `a` and `a_b` share the start `pp_a_`, so palette `a` may define or map a role to `pp_a_b_x`. That name belongs to palette `a_b`.
- The loader comment says the case is handled, but the guard only checks the owner for **replaced** names (`replaced.includes(nm).not or: { ownerOf.(nm) == stem }`). A name that is merely **added** is accepted on the prefix alone.
- If `a` is loaded first and `a_b` is added later, `a_b` is allowed to redefine `pp_a_b_x`, because `ownerOf` says `a_b` owns it. `a`'s sound then changes silently.
- This breaks the frozen-library guarantee that a committed palette never changes sound. The guarantee is the reason the namespace rule exists.

Reaching this takes a deliberately crafted file name. It is unlikely, but it is a hole in the rule itself.

**Fix:** Make ownership, not the prefix, the criterion in both places. In `~ppPaletteDefs`:
```supercollider
allowed = { |nm|
	if (stem == \classic) {
		~ppClassicVoices.includes(nm)
	} {
		nm.asString.beginsWith(ownPrefix) and: { ownerOf.(nm) == stem }
	}
};
```
`ownerOf` already includes this stem in its candidate list and takes the longest prefix. The result is that `a` is refused for `pp_a_b_x` once `a_b` is registered, and `a_b` can never take over a name that `a` already owns. In `~ppValidate`, add a check that no registered stem with a longer matching prefix claims the instrument. `~ppValidate` does not see the registry today, so the cheaper option is to rely on the defs guard and the voice check in `~ppValidateVoices`.

### WR-02: Fixed watchdogs do not scale with the library, which grows by one file per variation

**File:** `supercollider/palette_meter.scd:78`, `supercollider/library_test.scd:55`, `supercollider/smoke_test.scd:32`, `scripts/check.sh:221-231`
**Issue:** The project rule is that every variation is a new file and none is ever removed.
- The palette meter measures every palette on disk. At 180 BPM that costs about 20 to 25 s per palette (settle, 4-bar level window, 4-bar VO2 window, extreme-note probe), plus boot.
- With a hard `SystemClock.sched(480, ...)` watchdog, the meter will fail with the unexplained line `PALETTE FAIL: watchdog timeout` at roughly 18 to 20 palettes.
- `check.sh` then reports "CHECK FAILED: palette levels", with no hint that the budget ran out instead of a palette being bad.
- The library test already needed its watchdog raised once (the comment records 2:49 against 300 s), and it records every chord-data progression on disk. The same ceiling applies to it.
- The meter's watchdog (480 s) is also 30 s below the shell timeout (510 s), which leaves little room if boot is slow.

**Fix:** Scale the meter's budget with the work, once the stems are known. For example, after computing `stems`:
```supercollider
// reschedule: 40 s boot + 30 s per palette (+ 90 s in cpu mode)
```
Alternatively, print the number of palettes and the elapsed time in the watchdog message so a timeout is recognisable as a budget problem. Raise the shell `timeout` to match, or make it a function of the file count.

## Info

### IN-01: Empty error handlers swallow failures in the defs undo path

**File:** `supercollider/core/loader.scd:218`, `supercollider/core/loader.scd:258`
**Issue:** Two handlers are empty: `try { SynthDef.removeAt(nm) } { |err| nil }` and `try { s.sync } { |err| nil }` (inside `undoNow`).
- Elsewhere in this file every failure is logged with a `PedalPulse ERROR:` line.
- A failed `s.sync` after an undo means the server may still hold the refused voice, and nothing says so.

**Fix:** Log them the same way, for example `~ppLog.("PedalPulse ERROR: sync after undo of % failed: %".format(stem, err.errorString))`.

### IN-02: Comment misstates the hat row amplitude (frozen file, cannot be edited)

**File:** `supercollider/library/palettes/pluck.scd:19`
**Issue:** The header says the shared row amps include "hat 0.15", but `~ppDrumGrid` in `render.scd` sends hat rows at `0.1`. The SynthDef default of 0.15 never applies.
- The level was tuned with the meter, so sound is unaffected. Only the comment is wrong.
- The file is frozen by the library guard, so this is documented rather than fixable.

**Fix:** None in the file. Optionally note the correct value in `library/README.md`.

### IN-03: Mis-indented lines in `main.scd`

**File:** `supercollider/main.scd:175-177`
**Issue:** The new palette-prefetch comment and the `if` sit at column 0 inside a tab-indented `waitForBoot` body. The rest of the block is indented one level. It is harmless but looks like it is outside the block.

**Fix:** Indent the three lines with a single tab.

### IN-04: `smoke_test.sh` matches the pass line without anchoring

**File:** `scripts/smoke_test.sh:42`
**Issue:** `grep -q "SMOKE PASS"` is a substring match. The sibling scripts (`check.sh`, `palette_level.sh`, `palette_cpu.sh`) use `grep -qx`.
- Exit code 0 is also required, so the practical risk is low. The pass condition is still inconsistent across scripts.

**Fix:** Use `grep -qx 'SMOKE PASS'`. `smoke_test.scd:2626` prints it as a line of its own.

---

_Reviewed: 2026-10-13_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
