---
phase: 06-shared-harmony-progressions
reviewed: 2026-10-12T22:10:00Z
depth: standard
files_reviewed: 19
files_reviewed_list:
  - scripts/check.sh
  - scripts/smoke_test.sh
  - supercollider/core/harmony.scd
  - supercollider/core/loader.scd
  - supercollider/core/render.scd
  - supercollider/core/validate.scd
  - supercollider/library/README.md
  - supercollider/library/melodies/_template.scd
  - supercollider/library/progressions/_template.scd
  - supercollider/library/progressions/anthem.scd
  - supercollider/library/progressions/deep.scd
  - supercollider/library/progressions/drama.scd
  - supercollider/library/progressions/lift.scd
  - supercollider/library/progressions/melancholy.scd
  - supercollider/library/progressions/return.scd
  - supercollider/library/progressions/rocker.scd
  - supercollider/library_test.scd
  - supercollider/main.scd
  - supercollider/smoke_test.scd
findings:
  critical: 0
  warning: 4
  info: 4
  total: 8
status: issues_found
---

# Phase 6: Code Review Report

**Reviewed:** 2026-10-12T22:10:00Z
**Depth:** standard
**Files Reviewed:** 19
**Status:** issues_found

## Summary

The shared-harmony module is sound. I exercised it in a headless sclang:

- Every shipped chord is voiced inside the 40-64 window with exactly its own pitch classes.
- Chord following is correct, including negative ladder indexes.
- Event key lookup never falls through to the default Event parent for ordinary keys.
- A 250-bar Auto simulation made one decision per cycle boundary, with no mid-cycle change.
- Two layers pulling the same bar always got the identical (`===`) entry.
- `changesNext` was never wrongly true.

`scripts/check.sh --library-only` passes (LIBRARY PASS, 15 files, 138 s).

No crash, data-loss or injection defect was found. The issues are robustness gaps in the registry and Auto path, a weak guard, and doc/code drift.

## Structural Findings (fallow)

None provided.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: Registry Events treat the stems `parent` and `proto` as prototypes, not entries

**File:** `supercollider/core/loader.scd:159` (also `supercollider/core/loader.scd:40-55`, `supercollider/core/loader.scd:194`)
**Issue:** `~ppLib[cat]` is an Event. `Event:put(\parent, x)` and `put(\proto, x)` set the Event's parent and proto slots. They do not create dictionary keys. I confirmed this in sclang:

- After `e.put(\parent, (desc: "x", chords: [1]))`, `e[\desc]` returns `"x"` and `e[\chords]` returns `[1]`.
- `e.keys` does not list `parent`.

`~ppStemValid` accepts `parent.scd` and `proto.scd`. The Auto prefetch now registers every valid file in the progressions folder automatically.

Two effects follow for a file with either name:

- It is registered but invisible to `~ppAutoCandidates`, because that function iterates `.keys`.
- Every later lookup of one of its module keys in `~ppLib[\progressions]` (`desc`, `bass`, `pad`, `chords`, `name`, `path`, `rev`, `category`) returns a non-nil value from the module. That includes the stems `name` and `bass`.

Consequences:

- `~ppResolveStem`, `~ppHarmDecide` and the prefetch's `.isNil` check treat those stems as loaded when they are not.
- `~ppHarmCycle` then receives a Symbol or Function as `mod` and throws. `~ppHarmDecide` catches this and plays classic, but only after logging a confusing error.
- A file named `desc.scd` is never prefetched, because `~ppLib[\progressions][\desc]` is already non-nil.

The trust boundary is the library folder, which already runs arbitrary code. This is therefore a correctness and robustness gap, not privilege escalation.

**Fix:** Reject the reserved names in `~ppStemValid` (for example `["auto", "parent", "proto"].includes(str)` returns not ok), and document them in the README name rule. A more robust option is to make the registry and `~ppRenderErrors` category tables `IdentityDictionary` instead of Event:

```supercollider
~ppLib = ~ppLib ? (progressions: IdentityDictionary.new, melodies: IdentityDictionary.new, palettes: IdentityDictionary.new);
```

### WR-02: Every Start replays the identical Auto order

**File:** `supercollider/core/harmony.scd:229` (state created at `supercollider/core/harmony.scd:333`)
**Issue:** `~ppHarmReset` sets `~ppHarm = nil`, and the next run builds `auto: (..., picks: 0)`. The seed formula is `f(~ppAutoSeed, picks)`, and `~ppAutoSeed` is fixed per interpreter, so `picks` restarts at 0 on every Start. A rider who presses Stop/Start between workouts, without restarting SuperCollider, hears the same progression order every time (same library contents). In my seed-42 simulation the run began classic, then lift, rocker, melancholy and classic.

The README says Auto "rotates", and the seed is meant to make one heard order replayable, not to remove variety between rides. The file header says "a new run begins a new rotation". That is only true when the candidate set changes.

**Fix:** Keep `picks` across runs, so a replay needs the same seed from engine start. Store the counter outside the per-run `~ppHarm`:

```supercollider
~ppAutoPicks = ~ppAutoPicks ? 0;   // in the tunables, survives ~ppHarmReset
// seedFor: use ~ppAutoPicks and increment it instead of a[\picks]
```

If identical replay per Start is intended, say so explicitly in the README.

### WR-03: `~ppAutoPrefetching` is reset on every load of loader.scd

**File:** `supercollider/core/loader.scd:180`
**Issue:** `~ppAutoPrefetching = false;` is assigned unconditionally. Every other persistent flag in these modules uses the `~x = ~x ? default` idiom, which harmony.scd's header states as the rule. Re-evaluating main.scd mid-ride reloads loader.scd while a prefetch Routine may be in flight, and the Routine is not tied to a generation. Two scanners can then run at once and both call `~ppLibEnsure` for the same file. Those loads bump `rev`, reset the render error counts and reset layer state.

**Fix:**
```supercollider
~ppAutoPrefetching = ~ppAutoPrefetching ? false;
```
The teardown in main.scd can clear the flag explicitly if a stale scan is a concern.

### WR-04: The library guard only compares the working tree with HEAD

**File:** `scripts/check.sh:60-62`
**Issue:** `git diff --name-status --no-renames HEAD -- ...` reports only uncommitted changes. If an edit to a committed library file or to the golden is committed, the guard passes. The README and header promise "fails when a committed file was changed".

The shipped-groove golden still catches classic changes. The other seven progression files and the melody and palette files have no committed-change protection. In a repo with no HEAD, git errors and `|| true` turns that into a silent pass.

**Fix:** Diff against a stable base, for example `${LIBRARY_GUARD_BASE:-origin/main}` or the merge-base with main. Also treat a missing HEAD as a skip with a printed notice, as the non-work-tree case already does.

## Info

### IN-01: Doc/code drift in the README and the progression template

**File:** `supercollider/library/README.md:109`, `supercollider/library/progressions/_template.scd:35`
**Issue:**

- The README says Auto "changes progression every 2 to 3 minutes". `~ppAutoHoldBars` is `[32, 64]` bars. At 128 BPM that is 1 to 2 minutes. At a typical cycling 90 BPM it is about 85 to 170 seconds.
- The template says that for custom generators "the check enforces" that every note is in the bar's chord. The check only runs against committed files. At runtime a generator that plays a wrong note is not stopped; only an invalid row triggers the classic fallback.

**Fix:** State the hold as bars, or compute the minutes for a stated BPM. Reword the template to "the check enforces it for shipped files".

### IN-02: `~ppAutoHistoryCap` is not retunable

**File:** `supercollider/core/harmony.scd:53`
**Issue:** `~ppAutoHistoryCap = 8;` lacks the `~x = ~x ? default` idiom that every other tunable in the block uses.

**Fix:** `~ppAutoHistoryCap = ~ppAutoHistoryCap ? 8;`

### IN-03: The voicing Array is shared by reference

**File:** `supercollider/core/harmony.scd:182`, `supercollider/core/render.scd:89`
**Issue:** The same Array object is stored in `h[\voicing]`, `entry[\voicing]` and every layer's `plan[\voicing]`. It is also the `prev` for the next chord's voicing. A user bass or pad generator that mutates it in place (for example `plan[\voicing].sort` or `.add`) silently corrupts the memo for the other layers and for the next chord's nearest-voicing cost. Library generators are trusted code, but the plan is documented as an extension seam.

**Fix:** Hand out a copy in `~ppPlanFor`: `plan[\voicing] = entry[\voicing].copy`.

### IN-04: Test and gate timing

**File:** `supercollider/library_test.scd:42`, `scripts/check.sh:167-171`, `scripts/smoke_test.sh:32-36`
**Issue:**

- The watchdog is a fixed 300 s. The library check took 138 s here. The comment says the Phase 6 tiers record every chord-data progression on disk, so runtime grows with each new progression file. The project rule is "add a new file for every variation", so the gate will eventually trip its own watchdog and the shell `timeout 330`. Both limits have now been bumped by hand in this phase.
- The shell timeout silently does nothing when neither `timeout` nor `gtimeout` exists. That is the default state of a stock macOS.

**Fix:** Scale the watchdog by the file count, for example `120 + 25 * stemCount`. Alternatively cap the per-progression recording tier at a fixed sample. Warn in the scripts when no timeout binary is found.

---

_Reviewed: 2026-10-12T22:10:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
