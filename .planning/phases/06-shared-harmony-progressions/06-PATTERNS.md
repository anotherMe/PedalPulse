# Phase 6: Shared Harmony & Progressions - Pattern Map

**Mapped:** 2026-10-12
**Files analyzed:** 17 (1 new core module, 4 modified core/main files, 2 test scripts, 8 library files incl. template, 1 README)
**Analogs found:** 16 / 17 (all analogs are git-tracked; every path below is in `git ls-files`)

All code is sclang. Conventions common to every file: Events accessed with `[\key]` never dot syntax; core files only define `~` variables at load and end with a `\ppName` symbol; no server access at load; logging through `~ppLog` with the `PedalPulse:` prefix (`PedalPulse ERROR:` / `PedalPulse WARNING:` for problems).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `supercollider/core/harmony.scd` (NEW) | core module (schedule, memo, Auto, voicing, follow, default bass/pad) | transform + per-bar pull | `supercollider/core/render.scd` (file shape, seeding, `~ppRunGenerator`) | role-match |
| `supercollider/core/render.scd` (MOD: `~ppPlanFor`, `~ppRenderBar`) | core renderer | request-response (per bar) | itself (extend in place) | exact |
| `supercollider/core/validate.scd` (MOD: progressions branch) | validator | transform | itself, `cat == \palettes` branch (nested field checks) | exact |
| `supercollider/core/loader.scd` (MOD: `~ppSelect` wording, Auto prefetch) | loader / selection | event-driven | itself; `~ppLibEnsure` for prefetch | exact |
| `supercollider/main.scd` (MOD: load list, `~ppStart`/teardown reset) | entry / config | request-response | itself, lines 36-38 and 273 | exact |
| `supercollider/library/progressions/{anthem,rocker,lift,return,deep,melancholy,drama}.scd` (NEW x7) | library data file | config (data-only) | `supercollider/library/progressions/classic.scd` (header, Event shape) + RESEARCH "Chord data file" | role-match |
| `supercollider/library/progressions/_template.scd` (MOD content) | library template | config | itself | exact |
| `supercollider/library/README.md` (MOD) | docs | n/a | itself | exact |
| `supercollider/library_test.scd` (MOD: load list, static chord branch, chord-follow/cycle/Auto tiers) | test | batch / recorder | itself (`roleGens` static tier, `recordBars` tiers) | exact |
| `supercollider/smoke_test.scd` (MOD: load list, engine checks) | test | batch | itself (line ~2083 load list) | exact |
| `scripts/check.sh` (MOD only if cycle `CHECK WARN` > 8 bars is added) | script | batch | itself | exact |
| Python app | none | none | no change (Phase 5 dropdown rescans) | n/a |

## Pattern Assignments

### `supercollider/core/harmony.scd` (core module, per-bar pull transform)

**Analog:** `supercollider/core/render.scd` (header style, `~x = ~x ? default` survive-reeval idiom, seeding, try/containment).

**Header and load idiom** (render.scd 1-13, 83): top-of-file comment block stating "server-free at load: definitions only", Events with `[\key]`, state kept across re-evaluation with `?`:
```supercollider
~ppSongSeed = ~ppSongSeed ? 0;
~ppRoleNotes = ~ppRoleNotes ? IdentityDictionary.new;
...
\ppRender        // last line: module returns a Symbol, main.scd's ~ppLoadCore treats nil as failure
```
Use `\ppHarmony` as the last line. Use `~ppHarm = ~ppHarm ? nil` style only for state that must survive re-evaluation (the memo itself should be reset by `~ppHarmReset`, per RESEARCH).

**Deterministic randomness** (render.scd 84-86, 98): never `RandStream`; seed the thread right before the pick:
```supercollider
~ppSeedFor = { |songSeed, bar, role|
	((songSeed * 1000003) + (bar * 7919) + role.hash.abs) & 0x7FFFFFFF
};
...
thisThread.randSeed = ~ppSeedFor.(~ppSongSeed, songBar, role);
```
Auto: `thisThread.randSeed = (autoSeed * 1000003) + (decisionIndex * 7919)` then `rrand`/`choose`.

**Name safety for the Auto folder scan** (loader.scd 40-55, 60-65, 126): scan `~ppLibRoot +/+ "progressions"`, filter every stem with `~ppStemValid`, load only through `~ppLibEnsure` (never `.load` a scanned path). `~ppLibEnsure` runs only inside a Routine (palettes use `s.sync`), so the prefetch runs in a `Routine(...).play(SystemClock)` the same way `~ppSelect` does (loader.scd 198-220), wrapped in `env.use { }`.

**Containment/log style** (render.scd 107-123): `~ppLog.("PedalPulse ERROR: ...")`; wrap schedule building in `try` and fall back to an implicit-Am classic entry so all layers still agree (RESEARCH "~ppRenderBar changes").

**Run-signature memo and chord math:** no codebase analog (new); copy behaviour from RESEARCH Pattern 1 sketch (`sig = [thisThread.clock, bar - songBar]`) and "Code Examples" (expansion, `centroidRoot`, `bassRoot = 33 + ((rootPc - 33) % 12)`, nearest voicing). Bar derivation matches render.scd 215: `bar = (thisThread.beats / 4 + 1e-6).floor.asInteger`.

**Default bass rows** (copy skeleton from `library/progressions/classic.scd` 19-28; first three notes become `plan[\chord]` root, last eighth the pickup):
```supercollider
[\rest, 0.5, 0.1, 0.8], [33, 0.5, 0.1, 0.8], [\rest, 0.5, 0.1, 0.8], [33, 0.5, 0.1, 0.8],
[\rest, 0.5, 0.1, 0.8], [33, 0.5, 0.1, 0.8], [\rest, 0.5, 0.1, 0.8], [36, 0.5, 0.1, 0.8]
```
**Default pad rows**: first bar of a chord `[[voicing, 4, 0.06, legato]]` with legato the smaller of `0.9 * chordBars` and `chordBars - (~ppPadGapBeats / 4)` (gate closes at least one beat before the next chord; 06-01-PLAN.md and RESEARCH Pitfall 4 resolution), later bars `[[\rest, 4, 0, 1]]` (amp 0.06 from classic.scd 34; `\rest` row shape from render.scd 187).

---

### `supercollider/core/render.scd` (MOD, renderer, per-bar request-response)

**Analog:** itself.

**`~ppPlanFor` seam** (73-75) currently:
```supercollider
~ppPlanFor = { |bar, songBar, role|
	(bar: bar, songBar: songBar, phraseBar: songBar % 8, role: role)
};
```
Add an optional 4th argument `entry` (default nil) that merges `progression, chord, nextChord, chordBar, chordBars, cycleBar, cycleLen, voicing, bassRoot, scale`. Existing three keys unchanged; 3-arg callers (`library_test.scd` ~414, ~476) must keep working.

**`~ppRenderBar` pitched branch** (135-192): the points to change are
- 145 `mod = ~ppModuleFor.(cat);` : for `\bass`/`\pad`, take the module from the harmony entry's captured module instead (a pick must not switch bass/pad mid-cycle). Keep `~ppModuleFor` for `\arp`/`\lead`.
- 168-173 generator selection: if the module has no `mod[role]`, use the core default bass/pad (today it falls through to classic at 178-186).
- 187 `out = if (res.notNil) { res[\rows] } ...`: for arp/lead, apply `~ppFollowChord` to validated rows here, short-circuiting when the entry chord is the Am reference or the melody module declares `ownHarmony: true`.
- 174-177 failure accounting (`~ppRenderFail`, 3 strikes -> `~ppSel[cat] = \classic`) must keep working for `\progressions`.

**Layer Prout** (211-227): each layer calls `~ppRenderBar.(role, songBar, bar, layerState)` inside `env.use { }` under `try`. Harmony must be pulled inside `~ppRenderBar` (or via a call from the Prout) using the same `(bar, songBar)`. Do not add a Routine or second clock.

---

### `supercollider/core/validate.scd` (MOD, validator)

**Analog:** itself, the palettes branch for nested field checks and the `anyOf`/`checkFn` helpers.

**Current progressions branch** (87-91) to replace:
```supercollider
if (cat == \progressions) {
	anyOf.([\bass, \pad]);
	checkFn.(\bass);
	checkFn.(\pad);
};
```
Change `anyOf.([\bass, \pad, \chords])`, keep both `checkFn` lines, then if `module[\chords].notNil` add checks following the palettes style (99-115): type check first, `reasons.add("... ")` strings, loop with `.do`. Required checks (RESEARCH): non-empty Array, at most 16; each entry an Event; `root` Integer 0-11; `quality` a key of `~ppChordTypes` or `intervals` a 3-4 element Integer Array 0-11 starting 0; `bars`/`barsPerChord` Integer 1-8; total cycle 1-16. Guard every access so hostile values add a reason rather than throw (loader treats a throw as refusal anyway, loader.scd 101-105). `~ppChordTypes` is defined in harmony.scd, which loads after validate.scd, so either define the table in validate.scd or read it lazily at call time. Unknown keys stay ignored (header lines 9-11). `classic.scd` (bass+pad, no `chords`) must still validate.

---

### `supercollider/core/loader.scd` (MOD, `~ppSelect`)

**Analog:** itself.

Strings to change for `\progressions` only (palettes and melodies keep wording):
- line 190: `"PedalPulse: % auto -> auto (resolves to classic)"` -> auto rotates, starts on classic.
- line 212: `"... -> selected (rev %), plays from the next bar"` -> "switches at the end of the current progression cycle".

Keep: token/`~ppSelReq` latest-wins (196-198, 209), the background `Routine({ env.use { ... } }).play(SystemClock)` (199-220), refusal keeps last good copy (216-218). The auto branch (186-190) additionally triggers the Auto prefetch hook. Do not use the word "loading" in new log lines (the library test asserts none in invalid-name windows; `~ppLibLoad` already logs "loading" at line 73). RESEARCH Pitfall 9 notes WR-06 (refused newer selection cancels valid older one) lives here; do not worsen it.

---

### `supercollider/main.scd` (MOD)

**Analog:** itself.

**Core load list** (36-38): add `harmony.scd` after `loader.scd`, before `render.scd`:
```supercollider
~ppLoadCore.("validate.scd");
~ppLoadCore.("loader.scd");
~ppLoadCore.("render.scd");
```
**Start/stop** (273 onward): add `~ppHarmReset.value;` inside `~ppStart` before the `Pbindef(name).play(~clock, quant: 4, doReset: true)` loop, and in the main teardown. Selection defaults (line 41-ish, `~ppSel = ~ppSel ? (progressions: \classic, ...)`) unchanged. The OSC `/pp/progression` handler stays as is.

---

### `supercollider/library/progressions/{anthem,rocker,lift,return,deep,melancholy,drama}.scd` (NEW, data-only)

**Analog:** `supercollider/library/progressions/classic.scd` for header comment style (lines 1-9) and the single parenthesized Event with a required `desc:` (10-12). Never edit classic. No `~` vars, no clocks, no functions needed.

Data shape (RESEARCH "Chord data file"; root = semitones above key A):
```supercollider
(
desc: "Uplifting trance staple: Am F C G, one chord per bar",
barsPerChord: 1,
chords: [
	(root: 0,  quality: \min),
	(root: 8,  quality: \maj),
	(root: 3,  quality: \maj),
	(root: 10, quality: \maj)
]
)
```
Per-file values (D-04/D-05/D-06): anthem `0min 8maj 3maj 10maj` pace 1; rocker `0min 10maj 8maj 10maj` 1; lift `0min 8maj 10maj 10maj` 1 (G G merges); return `0min 3maj 10maj 8maj` 1; deep `0min 0min 8maj 10maj` barsPerChord 2 (cycle 8); melancholy `0min 7min 8maj 5min` 1; drama `0min 5min 8maj 7maj` 1 (E major, G#). Header comment says "FINAL when first committed" like classic.scd. Stems must match `^[a-z0-9_]+$`. `desc` plain-language and distinct (variations-must-be-audible rule). Do NOT use the filename `auto`.

---

### `supercollider/library/progressions/_template.scd` (MOD content)

**Analog:** itself (lines 1-50). Keep the comment contract block (8-25) but change "A progression provides bass and pad" to "chords (data) or bass/pad generators", and add a chord-data example. It must itself validate (static check loads templates). Outside the never-edit guard.

---

### `supercollider/library_test.scd` (MOD)

**Analog:** itself.

**Core load list** (line 543):
```supercollider
["validate.scd", "loader.scd", "render.scd"].do { |name|
	var r = (~ppRoot +/+ "core" +/+ name).load;
	if (r.isNil) { fail.("static", "core module % failed to load".format(name)) };
};
```
Insert `"harmony.scd"` after `"loader.scd"`.

**Static tier** `roleGens = (progressions: [\bass, \pad], melodies: [\arp, \lead]);` (342) runs generators found in the file; chord-data files have none, so add a branch that expands `chords`, renders the core defaults for every bar of the cycle via `~ppRenderBar` with an explicit pure entry (not the live memo), checks `~ppRowsValid`, and applies the strict in-chord check. Per-file success prints `LIBCHECK OK: <cat>/<stem>` (line 498); the failure collector is `add.("...")` (340). Add negative controls (bad root, unknown quality, empty chords, 17 chords, bars 0, cycle > 16).

**Recorder tiers:** `recordBars.(nBars, tempo, during)` (109), used e.g. at 938 and 1521 with a `{ |recClock, startBeat| ... }` mid-run tempo change. Copy the "plan bar is the played bar" test (around 1521) as the model for the chord-follow tier, and two successive `recordBars` calls (1490-1491) for the Stop/Start case. The temporary library root pattern for the Auto "new file joins" test is at ~1161-1172 (also see 336-340: swaps `~ppLibRoot`, `~ppLib`, `~ppSel`, `~ppRenderErrors`; restore afterward). Check line protocol: `CHECK OK: name` (79). Classic pad F: give the implicit classic chord `extraPcs: [5]` and comment why.

---

### `supercollider/smoke_test.scd` (MOD)

**Analog:** itself, line ~2083 holds the same `["validate.scd", "loader.scd", "render.scd"].do` load list in the module re-evaluation check; add `harmony.scd` there. Extend the engine-level Stop/ENG-05 (no stacking) checks per RESEARCH "Tests": after `~ppStop`/`~ppStart` with a non-classic progression selected, the memo restarts at chord 0 and group children return to zero after Stop. Reminder: pre-existing flaky check `epic glide up: PulseCount did not advance` (~1 in 3); rerun once.

---

### `supercollider/library/README.md` (MOD)

**Analog:** itself. Replace "switches at the next bar line" and "auto ... plays classic for now" for progressions with cycle-end switching, Auto rotation (start classic, 32-64 bars, shuffle no quick repeats) and the chord-data file recipe; document the `ownHarmony` opt-out for melodies (Open Question 1, resolved in planning as a planner decision the user has not yet confirmed; see RESEARCH.md).

## Shared Patterns

### Memoized "layers pull" (no mutable current chord)
**Source:** RESEARCH Pattern 1 (no existing code). **Apply to:** harmony.scd, render.scd. Every layer calls `~ppHarmonyFor.(bar, songBar)`; same key gives the same entry; run signature `[thisThread.clock, bar - songBar]`; prune entries older than ~8 bars.

### Try / fallback containment
**Source:** `supercollider/core/render.scd` 95-105 and 174-186. **Apply to:** core default bass/pad and the follow mapping. Rows always pass through `~ppRunGenerator` then `~ppRowsValid`; a failure plays classic for that bar and counts via `~ppRenderFail`.

### Name and path safety
**Source:** `supercollider/core/loader.scd` 40-65, 126. **Apply to:** Auto prefetch. `~ppStemValid` then `~ppLibEnsure`.

### Row contract
**Source:** `supercollider/core/validate.scd` 22-64. **Apply to:** all generated rows: `[note, dur, amp, legato]`, durs sum to 4, amp 0-1, legato > 0; note is a number, a number Array, or `\rest`.

### Logging
**Source:** `supercollider/core/loader.scd` 20-26. **Apply to:** D-11 line, e.g. `~ppLog.("PedalPulse: progression %: %".format(stem, chordNames.join(" ")))`, printed when a cycle of a new stem starts. Avoid the word "loading".

### Committed library files are frozen
**Source:** `scripts/check.sh` guard (`supercollider/library/*/[a-z0-9]*.scd` vs HEAD). Do not edit `classic.scd`, melody classics or the golden; core supplies the implicit Am chord ("Am every bar", `extraPcs: [5]`).

## No Analog Found

| File / Piece | Role | Data Flow | Reason |
|---|---|---|---|
| Run-keyed memo and Auto rotation inside `core/harmony.scd` | schedule state | pull / memo | No memoized or cross-bar state exists in the engine today; use RESEARCH Patterns 1-2 and the verified sketches |
| Chord-follow ladder mapping, nearest voicing, bass pickup | pure functions | transform | New music logic; use RESEARCH Patterns 3-5 and the verified output tables |
| Chord-data file shape | library data | config | `classic.scd` is generator-based; use RESEARCH "Chord data file" |

## Metadata

**Analog search scope:** `supercollider/core`, `supercollider/library`, `supercollider/main.scd`, `supercollider/*_test.scd`, `scripts/` (all tracked files listed via `git ls-files`)
**Files scanned:** about 14 read (full or targeted), 40 tracked files listed
**Pattern extraction date:** 2026-10-12
