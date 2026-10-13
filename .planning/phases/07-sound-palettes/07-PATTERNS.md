# Phase 7: Sound Palettes - Pattern Map

**Mapped:** 2026-10-13
**Files analyzed:** 17 (6 new palettes + 2 new scripts + 9 modified)
**Analogs found:** 17 / 17 (all analogs verified git-tracked via `git ls-files`)

All paths are relative to repo root. Line numbers are from the current tree.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `supercollider/library/palettes/{supersaw,acid,warm,pluck,dark,air}.scd` (stems are the planner's; avoid `anthem`, it is a progression) | library data (voices) | event-driven (voices self-free) | `supercollider/library/palettes/classic.scd` | exact |
| `supercollider/library/palettes/_template.scd` (doc `bassStyle`, prefix rule) | template | n/a | itself (not guarded, leading `_`) | exact |
| `supercollider/core/validate.scd` (WR-01 bounds, bassStyle value, prefix rule) | validator | transform | same file `~ppRowsValid` (100-142), `~ppValidate` palette branch (~196-216) | exact |
| `supercollider/core/loader.scd` (WR-02 guard, prefetch per category, `auto` message) | loader | batch / request-response | same file `~ppLibEnsure` (125-170), `~ppAutoPrefetch` (184-221), `~ppSelect` auto branch (~250) | exact |
| `supercollider/core/harmony.scd` (palette stage, `~ppPalAutoNext`, `~ppBassStyles`) | service | event-driven (per-bar memo) | same file `~ppHarmAutoNext` (229-272), `~ppAutoCandidates` (205-215), `~ppDefaultBass` (507) | exact |
| `supercollider/core/render.scd` (`~ppInstrumentFor.(role, stem)`, drums pull entry, bassStyle into plan) | service | transform | same file `~ppInstrumentFor` (61), `~ppRenderBar` (165) | exact |
| `supercollider/main.scd` (re-engage Auto at ~174) | config/entry | event-driven | same file | exact |
| `supercollider/library_test.scd` (level/CPU/headroom tier, bounds, prefix, Auto landing; watchdog 300 to ~480) | test | batch | same file voice tier (1209-1280), `auto plays classic` (1586-1598) | exact |
| `supercollider/smoke_test.scd` (Stop/rotation leak, VO2 no clip) | test | batch | same file (~1664 node bound, ~1783 no-clip) | exact |
| `supercollider/palette_cpu.scd` (NEW, D-15) | test/script | batch | `supercollider/smoke_test.scd` (isolated server) | role-match |
| `scripts/palette_cpu.sh` (NEW) | script | request-response | `scripts/smoke_test.sh` | exact |
| `scripts/check.sh` (TIMEOUT 330 to ~510) | script | batch | itself (line ~218) | exact |
| `supercollider/library/README.md` | doc | n/a | itself | exact |

## Pattern Assignments

### Palette files `supercollider/library/palettes/<stem>.scd` (library, voices)

**Analog:** `supercollider/library/palettes/classic.scd` (69 lines). One parenthesized Event, no `~` variables, nothing runs at load (lint token list: research Pitfall 6). Header comment must say "FINAL when first committed".

**Structure to copy** (classic.scd lines 7-12, 33-39, 55-68):
```supercollider
(
desc: "Shipped voices: ...",
defs: {
	SynthDef(\ppBass, { |out = 0, amp = 0.25, freq = 55, gate = 1|
		var sig, env;
		env = EnvGen.kr(Env.adsr(0.005, 0.1, 0.6, 0.05), gate, doneAction: 2);
		sig = Saw.ar([freq, freq * 1.01]);
		sig = RLPF.ar(sig, 700, 0.6);
		Out.ar(out, sig * env * amp);
	}).add;
	// pitched voices: controls out, amp, freq, gate; drums: out, amp, doneAction 2 envelope
},
roles: (
	bass: (instrument: \ppBass),
	arp: (instrument: \ppArp),
	pad: (instrument: \ppPad),
	lead: (instrument: \ppArp)
)
)
```
**Phase 7 deltas:** SynthDef names `\pp_<stem>_<role>` (WR-02 prefix); add optional `bassStyle: \sixteenths` (Symbol); supply bass/arp/pad/lead (+ drums only where needed, e.g. `dark` kick); omit roles to fall back to classic (D-03). Level trim = a literal gain constant inside each voice (RESEARCH Pitfall 1, warm needs about -8 dB). Clamp derived cutoffs `(freq * 6).min(12000)` (Pitfall 7). Pitched release must free within 2.0 s of `gate 0`; drums must self-free within about 2.5 s. Voice sketches: RESEARCH "Palette file skeleton" and the voice-recipe table. Tune before first commit (files are frozen once committed).

---

### `supercollider/core/validate.scd` (validator)

**Analog:** same file.

**WR-01 bounds go in `~ppRowsValid` (lines 100-142).** Existing per-row structure to extend (finite helper at 102, row loop 106-128):
```supercollider
finite = { |x| x.isNumber and: { x.isNaN.not and: { x.abs < inf } } };
...
if (reason.isNil and: { finite.(r[1]).not or: { r[1] <= 0 } }) {
	reason = "row %: dur is not a number above 0".format(n);
};
if (reason.isNil and: { finite.(r[3]).not or: { r[3] <= 0 } }) {
	reason = "row %: legato is not a number above 0".format(n);
};
```
Add the same `if (reason.isNil and: {...}) { reason = "row %: ..." }` shape for: rows <= 64, dur >= 1/32, legato <= 8 (NOT 4: default pad legato reaches 7.2, harmony.scd:538), note in -12..127, chord size <= 8.

**Palette branch (`~ppValidate`, `if (cat == \palettes)` block):** add bassStyle check in the style of `checkFn`: known key with unknown value is refused, unknown keys ignored (header contract-freeze rule). Use `reasons.add("... ".format(...))`. Add optional 3rd arg `stem` for `pp_<stem>_` prefix (allow classic's own instruments so `_template.scd` and the `bad_defs` fixture stay valid).

**Voice check** `~ppValidateVoices` (lines ~215-236) already iterates roles and `SynthDescLib.global.at(inst)`; reuse, do not duplicate.

---

### `supercollider/core/loader.scd` (loader)

**Analog:** same file.

**WR-02 guard in `~ppLibEnsure` palette branch (lines ~135-145 of the quoted block):**
```supercollider
if (mod[\defs].isFunction) {
	try {
		mod[\defs].value;
		s.sync;
	} { |err|
		~ppLog.("PedalPulse ERROR: library file % defs failed: %".format(mod[\path], err.errorString));
		ok = false;
	};
};
```
Wrap with the snapshot-diff from RESEARCH "Palette defs guard": snapshot `SynthDescLib.global.synthDescs.copy` before, diff after, any new/replaced name not starting `pp_<stem>_` refuses; cleanup via `SynthDef.removeAt` for new names; re-run classic `defs` + `s.sync` if a foreign name was replaced. Put it in ONE function used by `~ppLibEnsure`, the static tier (library_test.scd ~608-615) and voice tier (~1270-1275). Keep the "registry put only on success" rule (final `if (ok) { ... ~ppLib[cat].put(...) }`).

**Prefetch generalisation (`~ppAutoPrefetch`, 184-221):** copy the whole body, parameterise on `cat`:
```supercollider
~ppAutoFailed = ~ppAutoFailed ? Dictionary.new;
~ppAutoPrefetching = ~ppAutoPrefetching ? false;
~ppAutoPrefetch = {
	var env;
	if (~ppAutoPrefetching != true) {
		~ppAutoPrefetching = true;
		env = currentEnvironment;
		Routine({
			env.use {
				try {
					paths = (~ppLibRoot +/+ "progressions" +/+ "*.scd").pathMatch;   // -> cat
					paths.keep(256).do { |path| ... ~ppLibEnsure.(\progressions, stem.asSymbol) ... }
```
Keep the `~ppStemValid` guard, mtime failed-once map, one-at-a-time flag. Cap palettes near 32. Keep the zero-arg call working (default `\progressions`) so existing callers/tests stay valid.

**`~ppSelect` auto branch (lines ~246-253):** replace the `"(resolves to classic)"` else-branch for `\palettes` with a log line plus `~ppAutoPrefetch.(\palettes)`, mirroring the progressions branch:
```supercollider
if (cat == \progressions) {
	~ppLog.("PedalPulse: % auto -> auto (rotates progressions at cycle ends; ...)".format(address));
	~ppAutoPrefetch.value;
} { ~ppLog.("PedalPulse: % auto -> auto (resolves to classic)".format(address)); };
```
Named-pick log already says "plays from the next bar" for palettes (D-11); add the D-09 `palette <stem>: <desc>` line (emitted at bar build, see harmony).

---

### `supercollider/core/harmony.scd` (per-bar palette state + Auto)

**Analog:** same file, `~ppHarmAutoNext` (229-272).

**Seeded draw + history + no-quick-repeat to mirror** (lines 233-263):
```supercollider
seedFor = {
	thisThread.randSeed = ((~ppAutoSeed * 1000003) + (~ppAutoPicks * 7919) + 104729) & 0x7FFFFFFF;
	~ppAutoPicks = ~ppAutoPicks + 1;
};
...
recent = a[\history].asArray.keep(-2);          // asArray.keep(-2), never List.last(2)
pool = cands.reject { |c| (c == cur) or: { recent.includes(c) } };
if (pool.isEmpty) { pool = cands.reject { |c| c == cur } };
seedFor.value;
stem = if (pool.isEmpty) { cur } { pool.choose };
while { a[\history].size > ~ppAutoHistoryCap } { a[\history].removeAt(0) };
```
For palettes: new `~ppPalAutoPicks = ~ppPalAutoPicks ? 0;` (global, outside `~ppHarm`, survives Stop/Start like lines 51-58), distinct salt constant, reuse `~ppAutoSeed`; tunable `~ppPalHoldBars = ~ppPalHoldBars ? [80, 128];` (idiom at line 55). Candidates: copy `~ppAutoCandidates` (205-215) with `\palettes` and `~ppLibPath.(\palettes, n)`.

**Hook point:** `~ppHarmonyFor` (330) cycle-start block (lines 365-380) already computes `cycleBar == 0` and the `cyc[\stem] != h[\lastStem]` progChanged test before `lastStem` update; add the palette stage there (boundary = cycleBar 0 and (progChanged or locked progression or `holdLeft <= -maxWaitBars`)), write `entry[\palette]`, and `~ppLog.("PedalPulse palette %: %".format(stem, desc))` modelled on `~ppLog.("PedalPulse: progression %: %"...)` (line ~377). Create `h[\palAuto]` next to `pending/lastStem/auto` in the run-state Event (line ~338).

**Bass style table:** add `~ppBassStyles` beside `~ppDefaultBass` (507-525). `eighths` must equal the current rows exactly; each entry has the signature `{ |plan, state| ... }`, 8 or 16 rows summing to 4, root via `~ppBassRoot.(chord)`, last slot `~ppBassPickup.(chord, plan[\nextChord])` when `plan[\changesNext] == true`, otherwise `root + chord[\intervals][1]`:
```supercollider
last = if (plan[\changesNext] == true) { ~ppBassPickup.(chord, plan[\nextChord]) } { root + chord[\intervals][1] };
[ [\rest, 0.5, 0.1, 0.8], [root, 0.5, 0.1, 0.8], ... [last, 0.5, 0.1, 0.8] ]
```

---

### `supercollider/core/render.scd` (renderer)

**Analog:** same file.

**`~ppInstrumentFor` (61-76)** add optional 2nd arg `stem`; when given use `~ppLib[\palettes][stem]` instead of `~ppModuleFor.(\palettes)`; keep the classic-fallback block unchanged:
```supercollider
~ppInstrumentFor = { |role|
	var pal, fallback, inst;
	pal = ~ppModuleFor.(\palettes);
	if (pal.notNil and: { pal[\roles].notNil and: { pal[\roles][role].notNil } }) { inst = pal[\roles][role][\instrument]; };
	if (inst.isNil) { fallback = ~ppLib[\palettes][\classic]; ... };
	inst ? \default
};
```
**`~ppRenderBar` (165):** currently `inst = ~ppInstrumentFor.(role)` precedes the entry pull and drums bypass the entry. Reorder: pull entry first for every role using the existing try/fallback block (lines ~172-178: `try { ~ppHarmonyFor.(bar, songBar) } { |err| ~ppLog.(...); ~ppHarmClassicEntry.() }`), then `palStem = entry[\palette] ? ~ppResolveStem.(\palettes); inst = ~ppInstrumentFor.(role, palStem)`. Drum rows `drum[\rows].collect { |r| [inst, r[1], r[2], r[3]] }` stay byte-identical for classic (golden parity). Bass: where `gen = ~ppDefaultBass` is chosen (lines ~212-215), set `plan[\bassStyle]` from `~ppLib[\palettes][palStem][\bassStyle]` and dispatch through `~ppBassStyles`; classic's frozen generator path is untouched. `~ppHarmClassicEntry` needs no `palette` (nil falls back to the resolved stem).

---

### `supercollider/library_test.scd` (test)

**Analog:** same file.
- Voice tier: `voiceContractMany` (1209-1264) and the per-palette-stem loop (1266-1280) run every palette on disk automatically (picks up new files; add extreme-freq spawn, optional).
- Replace test "auto plays classic" (1586-1598): drop `sendSel.('/pp/palette', 'auto')` from it (keep melody and progression), add palette Auto assertions as separate checks using the same helpers (`sendSel`, `waitFor`, `fail.(name, msg)`, `checkOk.(name)`, `matchGold4`).
- Rows validation block (~2347 on): add negative cases for each WR-01 bound in the same style.
- Static lint at 475-480 (token ban list) applies to every new palette.
- Watchdog `SystemClock.sched(300, {` at line 51 to ~480; `getenv` idiom at line 62 (`PP_GOLDEN_RECORD`) is the model for the new `PP_PALETTE`.
- Level tier: use the RunningSum/Peak/SendReply probe from RESEARCH "Level probe" on the isolated server 57141; config 180 BPM, progression locked to a chord-data one, melody `classic_lead_loud`, fixed EPIC; fail at `abs(gap) > 1.5` dB; peak at EPIC 100/vol 100 <= 0.80 post-FX; print `s.avgCPU`/`s.peakCPU` per palette, WARN above about 12, fail at 25.

### `supercollider/smoke_test.scd` (test)
**Analog:** same file. Reuse the existing no-clip check (~1783-1791, output peak <= 0.892) for the loudest palette at VO2; relax the node bound (~1664, classic-era 22) to a relative bound (classic + 12). Watchdog 360 has about 170 s headroom.

### `supercollider/palette_cpu.scd` + `scripts/palette_cpu.sh` (new)

**Analog:** `scripts/smoke_test.sh` (47 lines) copy wholesale: `set -euo pipefail`, `cd "$(dirname "$0")/.."`, `SCLANG` default `/Applications/SuperCollider.app/Contents/MacOS/sclang`, `.venv` check (drop if unneeded), `unset QT_QPA_PLATFORM`, LOG under `${TMPDIR:-/tmp}`, `timeout` / `gtimeout` fallback, run `"$SCLANG" -D supercollider/palette_cpu.scd > "$LOG" 2>&1`, `cat "$LOG"`, exit 0 only if rc 0 and a `PASS` marker. The `.scd` mirrors smoke_test.scd setup (isolated server on a free port such as 57142, load `main.scd`); body per RESEARCH Pattern 8 (60 s sampling every 0.7 s, print mean/max/`peakCPU`, pass if mean < 25).

### `scripts/check.sh`
**Analog:** itself: `TIMEOUT_CMD="timeout 330"` (line ~218) raise together with the library watchdog; library guard glob at line ~79 (`'supercollider/library/*/[a-z0-9]*.scd'`) means new palettes are added-only, and `_template.scd` is exempt.

## Shared Patterns

### Library files are data only and frozen
**Source:** `supercollider/library/palettes/classic.scd` header (lines 1-6), `scripts/check.sh:79`
**Apply to:** all six new palettes. One Event, no `~`, no Synth/Routine/etc. (lint), never edit after commit.

### Events accessed with `[\key]`, never dot syntax; `x = x ? default` for tunables
**Source:** `harmony.scd:55-58`, throughout core
**Apply to:** all core edits.

### Log through `~ppLog`, prefix `PedalPulse`, errors `PedalPulse ERROR:`
**Source:** `loader.scd` (e.g. `~ppLog.("PedalPulse ERROR: library file % defs failed: %".format(...))`)
**Apply to:** palette-change line (D-09), guard failures, Auto pick failures (wrap draws in `try { } { |err| ... classic }` like `~ppHarmDecide`, harmony.scd:285-289).

### Failure falls back to classic, registry written only on success
**Source:** `loader.scd ~ppLibEnsure` tail; `render.scd` `~ppRenderFail` + classic generator fallback
**Apply to:** WR-02 restore path, palette Auto candidate filter (render errors < 3, file still on disk).

### Voices: own bus only, `gate` honoured, `doneAction: 2`, FX only in shared `\ppFx`
**Source:** classic.scd voices; voice-contract tier library_test.scd:1209-1280
**Apply to:** every new SynthDef.

## No Analog Found

| File / piece | Role | Reason |
|---|---|---|
| Real-time level (RMS) probe and CPU sampler | test | No existing level meter; use RESEARCH "Level probe" code (proved repeatable to 0.0 dB). Pattern only partly mirrors the `\ppLibPeak` probe used in the voice tier. |
| Palette voice DSP (supersaw, 303, FM bell, etc.) | voices | Only classic's six voices exist; use RESEARCH voice-recipe table as starting points, tuned by measurement then by ear. |
| `~ppBassStyles` sixteenths / octave rows | generator | Only `~ppDefaultBass` (eighths) exists; derive from it keeping root-first and pickup rules. |

## Metadata

**Analog search scope:** `supercollider/` (core, library, tests, main), `scripts/`
**Files scanned:** about 20 (tracked file list checked; all named analogs tracked)
**Pattern extraction date:** 2026-10-13
