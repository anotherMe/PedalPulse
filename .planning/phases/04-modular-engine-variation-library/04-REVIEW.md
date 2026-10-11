---
phase: 04-modular-engine-variation-library
reviewed: 2026-10-11T00:00:00Z
depth: standard
files_reviewed: 16
files_reviewed_list:
  - scripts/check.sh
  - supercollider/core/loader.scd
  - supercollider/core/render.scd
  - supercollider/core/validate.scd
  - supercollider/golden/shipped_groove.scd
  - supercollider/library/README.md
  - supercollider/library/melodies/_template.scd
  - supercollider/library/melodies/classic.scd
  - supercollider/library/melodies/classic_lead.scd
  - supercollider/library/palettes/_template.scd
  - supercollider/library/palettes/classic.scd
  - supercollider/library/progressions/_template.scd
  - supercollider/library/progressions/classic.scd
  - supercollider/library_test.scd
  - supercollider/main.scd
  - supercollider/smoke_test.scd
findings:
  critical: 0
  warning: 6
  info: 6
  total: 12
status: issues_found
---

# Phase 4: Code Review Report

**Reviewed:** 2026-10-11
**Depth:** standard
**Files Reviewed:** 16
**Status:** issues_found

## Summary

The core split (validate / loader / render), the name and path hardening
(character-loop name check, realpath containment), the latest-wins selection
token, per-bar containment with classic fallback, and the seeding scheme are
sound. I traced the selection, reload, fallback and re-evaluation paths and found
no data-loss or security defect: library files are local, trusted code, and names
are validated before any path is built.

The weaknesses are all in the claims the phase makes about containment and
immutability:

- The row validator has no upper bounds, so a "valid" bar can still flood or
  poison the engine.
- A refused palette still leaves its SynthDefs behind, and the fallback to classic
  does not restore classic's voices.
- The immutability guard is bypassed by committing, and it fails open when git errors.
- Two documented contracts (shared state, voice naming) do not match the code.

`supercollider/golden/shipped_groove.scd` has the expected format: header
comments, then a single Array literal. It is loaded with `.load`, checked by the
golden self-check, and is covered by the guard's `supercollider/golden/*.scd`
pathspec. No problems there.

## Warnings

### WR-01: Row validation has no upper bounds (note range, legato, row count), so a "valid" bar can still disturb the engine

**File:** `supercollider/core/validate.scd:22-64`
**Issue:** `~ppRowsValid` checks only that values are finite and above 0 (and amp is in 0..1). It does not cap:

- **Row count.** A bar of 400000 rows with `dur = 1e-5` sums to 4.0 and passes. The renderer then builds a 400000-element `Pseq` and schedules that many events and synths from a single bar, which hangs sclang and the shared `~clock`. A chord with thousands of notes spawns thousands of synths per row.
- **Legato.** Legato 100 on a sixteenth-note arp holds each voice for 25 beats (about 1600 beats of overlap per bar). Gated voices pile up until Stop, and the "node bound" guarantee the smoke test checks for the classic groove does not hold.
- **Note range.** A note of 500 passes (`freq` is about 4e13), and so does MIDI 115 or higher. `ppArp` runs `LPF.ar(sig, freq * 4)`, and a cutoff above Nyquist can make a biquad unstable. A NaN or inf written to `~ppMixBus` is carried by the persistent FX chain (`RLPF`, `FreeVerb2`) and silences the engine until the next re-evaluation.

LIB-04 ("a misbehaving file cannot take the engine down") is therefore only partly true: the check catches wrong shapes but not hostile or accidental magnitudes. The `rows validation` test in `library_test.scd` has no case for any of these.
**Fix:**
```supercollider
// in ~ppRowsValid
if (rows.size > 64) { reason = "bar has % rows (max 64)".format(rows.size) };
// per row
// note: -12..127 for a Number, chord size <= 8
// legato: finite, > 0, <= 4
// dur: finite, >= 1/32 (0.03125)
```
Add matching negative cases to the `rows validation` block of `library_test.scd`.

### WR-02: A refused (or fallen-back) palette leaves its SynthDefs behind, and the fallback to classic does not restore classic's voices

**File:** `supercollider/core/loader.scd:126-154` (also `supercollider/core/validate.scd:129-154`, `supercollider/library/README.md:100-103`)
**Issue:** `~ppLibEnsure` runs the palette's `defs` (and `s.sync`) before `~ppValidateVoices`. A palette that fails validation, or throws halfway through `defs`, has already registered its SynthDefs with the client and the server. SynthDef names are not namespaced: the README says voices "start with `pp_<palette>_`", but nothing enforces it, and classic itself uses `ppKick`, `ppArp` and so on.

Concrete failure:
1. A palette `x` redefines `\ppArp` (for example with a different envelope) and then fails the voice check on another role.
2. The load is refused, with "the last good copy keeps playing". The currently selected palette, which uses `ppArp`, now sounds different.
3. The same holds after a successful load of `x`. The 3-failures fallback and `auto` only set `~ppSel[\palettes] = \classic` and never re-run classic's `defs`. "Back to classic" then plays classic's instrument names with `x`'s definitions.

Re-sending `classic` by hand does restore them, because selection reloads and re-runs `defs`.
**Fix:** In `~ppValidate`, reject a palette whose `defs` would define a name outside its own prefix. That check can only be done statically on the file, so enforce the `pp_<stem>_` prefix on every non-classic `roles[...][\instrument]`. In addition, when `~ppSel[\palettes]` is reset to classic (render fallback and `auto`), re-run `~ppLib[\palettes][\classic][\defs]` followed by `s.sync` inside a Routine, so the voices are restored.

### WR-03: The immutability guard is bypassed by committing the edit, and it fails open when git errors

**File:** `scripts/check.sh:64-66`
**Issue:**
- `git diff --name-status --no-renames HEAD` compares the working tree to `HEAD`. Edit a library file, commit it, then run `check.sh`: the committed edit is now the baseline, so the guard passes. The success criterion is "every earlier variation stays selectable and sounds as it did", but the guard only catches uncommitted edits.
- The whole pipeline ends in `|| true`, so any git failure (no `HEAD`, a broken index, lock contention) produces an empty `bad` and prints "CHECK OK: library guard". The guard never says it did not run.

**Fix:**
```bash
# compare against a fixed baseline instead of HEAD, e.g. the merge-base with main
# or a recorded manifest:  sha256 of every guarded file in scripts/library.sha256
out=$(git -C "$repo" diff --name-status --no-renames "$BASE" -- ... ) || { echo "LIBRARY GUARD FAIL: git diff failed" >&2; return 1; }
bad=$(printf '%s\n' "$out" | grep -v '^A' || true)
```
A committed hash manifest (new files append, existing lines never change) removes the dependency on git history entirely.

### WR-04: The documented `state` contract is wrong: arp and lead (and bass and pad) do not share a state

**File:** `supercollider/library/melodies/_template.scd:15-16` (code in `supercollider/core/render.scd:211-212,152-163`)
**Issue:** The template says `init` "sets up the state Event the generators share". In the renderer, `layerState = ()` is created inside each layer's own `Prout`, and `layerState[\state]` is created per layer. `init` therefore runs once per layer, and `arp` and `lead` get two separate state Events. A melody author who follows the documented contract (put a chord choice in `state` from `arp`, read it in `lead`) gets `nil` in `lead`, and the lead falls back to classic (silent) for three bars. Committed files can never be edited, so the wrong contract text is permanent in the template and the README. The progression template has the same problem for `bass` and `pad`, and its text implies a progression `init` that nothing documents, although the renderer calls it.
**Fix:** Either document that state is per role and that `init` runs once per role, or give the renderer one state Event per category (shared by the layers of that category). Whichever is chosen, say it in `_template.scd`, `progressions/_template.scd` and the README, and add a test for it.

### WR-05: Startup tears the engine down before it knows classic can be loaded

**File:** `supercollider/main.scd:86-152`
**Issue:** On re-evaluation, the clock, stepper, synths, groups and buses are freed first. Only then is `classic` loaded from disk, and a failure `throw`s an Error from inside `s.waitForBoot`. The engine is left half torn down: no clock, no groups, no buses. `~ppReady` still holds the previous value (`true`), `~ppPlaying` is still `true`, and the old `OSCdef`s are still live. `/pp/play 1` is swallowed as "already playing", and `/pp/epic` and `/pp/volume` call `.set` on freed buses. The failure mode is the one the library design promises to avoid ("on any failure the registry is left untouched and the last good copy keeps playing").
**Fix:** Load and validate the three classic files, and the stored non-classic selections, into a local candidate registry before the teardown. Swap them in only if all of them loaded. Also set `~ppReady = false` at the start of the evaluation.

### WR-06: A refused newer selection cancels a valid older one

**File:** `supercollider/core/loader.scd:196-215`
**Issue:** The request token is taken before the file is read. If request A (valid) is still loading when request B (broken or a typo) arrives, B bumps the token, A finishes and logs "loaded but superseded", and B is then refused. The result is that neither A nor B is selected, although A was a valid, wanted selection. This is most visible for palettes, where `defs` plus `s.sync` makes the window wide. The test `broken never wins a race` accepts either `fresh2` or `classic`, so it does not pin the behaviour.
**Fix:** Bump the token only when the new request succeeds, or let a superseded request still apply if the superseding request failed (keep the last successful token and compare against the last *accepted* request).

## Info

### IN-01: Unused declarations in `staticCheck`

**File:** `supercollider/library_test.scd:331-334`
**Issue:** `grown`, `hit`, `names`, `sel` and `ok` are declared but never used.
**Fix:** Remove them from the `var` lists.

### IN-02: The forbidden-token lint is a substring match, so it false-positives and is easy to bypass

**File:** `supercollider/library_test.scd:310-315,394-398`
**Issue:** `"File"`, `"Task"`, `"Pipe"`, `"Server"`, `"fork"` and `".play"` are matched anywhere in the code. A legitimate identifier such as `Profile`, `Tasks`, `pipeline` or `forkJoin`, or a method such as `.playRange`, fails a file for a reason the author cannot see. Equally, `String:compile`, `Platform`, `Library`, `Archive` and `Main` are not on the list. The lint is described as a safety check ("A file is data plus pure functions") but is only advisory.
**Fix:** Match whole identifiers (a boundary-aware scan on the stripped source) and extend the list. Say in the README that the lint is advisory.

### IN-03: The silent drum fallback plays the `\default` SynthDef at amp 0

**File:** `supercollider/core/render.scd:206`
**Issue:** If the renderer throws for a drum role, the fallback bar is `[[\default, 4, 0, 1]]`. That spawns an inaudible `\default` voice each bar into the mix bus. The pitched fallback uses `\rest`.
**Fix:** Use a rest for the drum fallback too, for example `\rest` in the `\dur` column, or a short silent Event.

### IN-04: The README hard-codes the current library contents and a naming rule that is not enforced

**File:** `supercollider/library/README.md:15-17,100-103`
**Issue:** "Right now the library holds ..." will drift as soon as a file is added. The voice-name rule (`pp_<palette>_`) is described as part of the contract, but classic breaks it and nothing checks it (see WR-02).
**Fix:** Drop the file list, or generate it. Either enforce the voice-name rule or soften it to a recommendation.

### IN-05: Test and helper duplication; one 1573-line harness

**File:** `supercollider/library_test.scd`, `supercollider/smoke_test.scd`
**Issue:** `fail`, `checkOk`, `sendSel`, `waitFor` and the group-query helpers are defined twice, with small differences. `library_test.scd` holds the static, voice, parity, selection, fallback and containment tiers in one parenthesized block, so a failure in a late tier needs the whole run to reproduce. `smoke_test.scd` has several assigned-but-unused variables (`peakOSCdef`, `ctlOSCdef`, `bandOSCdef`, `lastTrace`, `tempoOk`).
**Fix:** Move shared helpers into a small file loaded by both, and allow selecting a tier by environment variable.

### IN-06: Minor shell and logging issues

**File:** `scripts/check.sh:81,163`, `supercollider/main.scd:276,305,316,325-381`
**Issue:**
- `$g` is an unquoted command string containing `$tmp`, so a `TMPDIR` with spaces breaks the self-test.
- The fallback `LIB_LOG` path in `/tmp` is predictable (a symlink clobber risk when `TMPDIR` is unset).
- The self-test uses `mktemp -d` for the "not a work tree" case, and it would fail if `TMPDIR` were inside a git work tree.
- Library messages go through `~ppLog`, which keeps the app-facing log, but the transport and BPM/EPIC/volume handlers in `main.scd` use `.postln` directly, so the log is incomplete.

**Fix:** Use an array for the git command, create the log with `mktemp`, and route all engine messages through `~ppLog`.

---

_Reviewed: 2026-10-11_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
