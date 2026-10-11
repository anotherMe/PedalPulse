# Phase 4: Modular Engine & Variation Library - Pattern Map

**Mapped:** 2026-10-11
**Files analyzed:** 27 new/modified
**Analogs found:** 14 exact/role-match / 27 (rest are new-contract files with no analog; RESEARCH.md prototypes apply)

Codebase is tiny: only `supercollider/main.scd`, `supercollider/smoke_test.scd`, `scripts/smoke_test.sh`, `python_app/osc_client.py` exist as SC/shell analogs. All paths below are git-tracked (verified with `git ls-files`). Line numbers refer to the current v1.0 files.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `supercollider/main.scd` (MODIFY) | engine entry / config | event-driven | itself (v1.0) | exact |
| `supercollider/core/loader.scd` | service (registry, safe load) | request-response / file-I/O | `main.scd` OSCdef + teardown style | partial |
| `supercollider/core/validate.scd` | utility (pure) | transform | `main.scd` OSCdef arg validation (366-375) | partial |
| `supercollider/core/render.scd` | service (per-bar Prout rows) | streaming | `main.scd` Pbindefs (248-310) | role-match |
| `supercollider/library/palettes/classic.scd` | library data (SynthDefs) | transform | `main.scd` SynthDefs (72-116) | exact (move verbatim) |
| `supercollider/library/progressions/classic.scd` | library data | transform | `main.scd` bass/pad Pbindefs (263-273, 301-310) | exact |
| `supercollider/library/melodies/classic.scd` | library data | transform | `main.scd` arp Pbindef (290-299) | exact |
| `supercollider/library/melodies/classic_lead.scd` | library data | transform | `melodies/classic.scd` + arp Pbindef | role-match |
| `supercollider/library/*/_template.scd` (x3) | template | n/a | the matching `classic.scd` | role-match |
| `supercollider/library/README.md` | docs | n/a | `README.md` (repo root) | partial |
| `supercollider/golden/v1_events.scd` | test fixture | batch | none (recorded output) | none |
| `supercollider/library_test.scd` | test | event-driven | `supercollider/smoke_test.scd` | exact |
| `supercollider/smoke_test.scd` (MODIFY) | test | event-driven | itself | exact |
| `scripts/library_check.sh` | script | batch | `scripts/smoke_test.sh` | exact |
| `scripts/check.sh` | script | batch | `scripts/smoke_test.sh` | role-match |
| `scripts/pp_select.sh` | script | request-response | `python_app/osc_client.py` CLI | role-match |
| Python app | none changed in Phase 4 | | | |

## Pattern Assignments

### `supercollider/main.scd` (MODIFY, engine entry)

**Analog:** itself. Keep the whole structure; changes are surgical.

**Header and tunables (1-32)**: keep as is. Add `~ppRoot` capture before line 13, per RESEARCH Pitfall 3:
```supercollider
~ppRoot = File.realpath(thisProcess.nowExecutingPath).dirname   // guard nil: keep previous ~ppRoot else throw
```
Then load `core/*.scd` at top level (before `s.waitForBoot`, line 34), absolute paths only, via `~ppLoadCore` that throws on `nil`. Note `smoke_test.scd:32` uses the same `File.realpath(thisProcess.nowExecutingPath)` idiom.

**Layer list (lines 44-50)**: the single source of truth; append `\ppLead`:
```supercollider
~ppLayers = [\ppKick, \ppHat, \ppClap, \ppBass, \ppArp, \ppPad];   // -> add \ppLead as 7th
~ppLayers.do { |name| Pbindef(name).stop };
```

**Idempotent re-eval / state persistence (43, 169, 184, 193)**: copy the `~x = ~x ? default` idiom for `~ppSel`:
```supercollider
~ppWasPlaying = ~ppPlaying ? true;
~epic = ~epic ? 10;
~bpm = ~bpm ? 120;
// new: ~ppSel = ~ppSel ? (progression: \classic, palette: \classic, melody: \classic);
```

**Teardown block (57-70)**: unchanged; no new nodes/buses are created by Phase 4 (lead is a normal layer in `~ppInstrGroup`).

**SynthDefs (72-116)**: the six per-note voice defs move into `library/palettes/classic.scd` `defs`. Infrastructure defs (`\ppMaster` 118-126, `\ppEpicSmoother` 132, `\ppFx` 136-150) STAY. `s.sync` at line 152 stays; engine calls palette `defs` then `s.sync` before building layers.

**Pbindefs (248-310)**: replace the six literal Pbindefs with `~ppBuildLayers` (RESEARCH Pattern 2) which does `Pbindef(name).clear`, one Prout-per-bar definition, and `Pbindef(name).quant = 4`. Retain `\out, ~ppMixBus, \group, ~ppInstrGroup` forced by core.

**Transport (316-350)**: keep verbatim; they already iterate `~ppLayers`, so the lead is covered automatically:
```supercollider
~ppStart = { ~ppLayers.do { |name| Pbindef(name).play(~clock, quant: 4, doReset: true) }; ... };
~ppStop  = { ~ppLayers.do { |name| Pbindef(name).stop }; ... ~ppInstrGroup.set(\gate, 0); ... };
```

**OSCdef pattern (366-375), copy for `/pp/progression`, `/pp/palette`, `/pp/melody`**:
```supercollider
OSCdef(\pp_bpm, { |msg|
	var raw = msg[1];
	if (raw.isNumber.not or: { raw.isNaN }) {
		"PedalPulse WARNING: ignoring /pp/bpm with invalid argument %".format(raw).postln;
	} {
		...
		"PedalPulse: /pp/bpm % -> % BPM (glide over % beats)".format(raw, bpm, ~ppRampBeats).postln;
	};
}, '/pp/bpm', srcID: NetAddr("127.0.0.1", nil));
```
Differences for the new handlers: `msg[1]` arrives as a Symbol (reject nil/number with the same WARNING format, `.asString`, char-loop stem check, `auto` allowed, then `fork` the `~ppLibEnsure` call). Same `srcID` loopback guard and `"PedalPulse: ..."` post prefixes. Update the ready banner (433) to list the new addresses; update the OSC-port warning block (428-432) unchanged.

**Banner/ready (433-434)**: keep `~ppReady = true` as the last statement (smoke polls it).

---

### `supercollider/core/loader.scd`, `core/validate.scd`, `core/render.scd` (core modules)

**Analog:** no existing module system. Use main.scd conventions: `~pp`-prefixed environment variables, `"PedalPulse: ..."` / `"PedalPulse WARNING: ..."` / `"PedalPulse ERROR: ..."` postln format, comments explaining the why. Each module ends with a non-nil value (RESEARCH Pitfall 3). Server-free (no `s.` calls) so `library_test.scd` static tier can load `validate.scd` and `loader.scd` alone. Use RESEARCH Patterns 1-3, Pitfalls 2, 4, 5 as the code source (prototype excerpts in 04-RESEARCH.md lines 227-248, 257-261). `~ppLog` must be a function so tests can capture output and assert the file path appears.

Drum rows in `render.scd` must equal the v1.0 literals: kick `dur 1` (main.scd:250), hat `dur 1, timingOffset 0.5` (258), clap `dur 2, timingOffset 1, amp 0.25` (283-285); kick/hat/bass have no `\amp` (effective 0.1, comment at 275-280).

---

### `supercollider/library/palettes/classic.scd` (library data)

**Analog:** `main.scd` lines 72-116. Copy the six SynthDefs verbatim into a `defs: { ... }` function, nothing changed (voice contracts: `out amp freq gate`, `doneAction: 2`):
```supercollider
SynthDef(\ppBass, { |out = 0, amp = 0.25, freq = 55, gate = 1|
	var sig, env;
	env = EnvGen.kr(Env.adsr(0.005, 0.1, 0.6, 0.05), gate, doneAction: 2);
	sig = Saw.ar([freq, freq * 1.01]);  // detuned pair -> stereo
	sig = RLPF.ar(sig, 700, 0.6);
	Out.ar(out, sig * env * amp);
}).add;
```
Wrap per RESEARCH Pattern 1: `(desc: ..., defs: { ... }, roles: (kick: (instrument: \ppKick), ..., lead: (instrument: \ppArp)))`. File must be side-effect-free at load (no `.add` outside the `defs` function).

### `supercollider/library/progressions/classic.scd`

**Analog:** `main.scd` 263-273 and 301-310. Values to reproduce as one-bar rows `[note, dur, amp, legato]`:
```supercollider
\midinote, Pseq([\rest, 33, \rest, 33, \rest, 33, \rest, 36], inf),  // bass, dur 0.5, legato 0.8, NO amp (effective 0.1)
\midinote, Pseq([[45, 48, 52], [45, 48, 53]], inf),                 // pad, dur 4, legato 0.9, amp 0.06, alternation via plan.songBar % 2
```

### `supercollider/library/melodies/classic.scd`

**Analog:** `main.scd` 290-299: arp `dur 0.25`, `Pseq([57, 60, 64, 60], inf)`, `legato 0.6`, `amp 0.1`. No `lead` key (silent lead; D-05).

### `supercollider/library/melodies/classic_lead.scd`

**Analog:** `melodies/classic.scd` plus the arp row. `arp` identical to classic; `lead` = same notes + 12, `amp` starting about 0.025 (arp 0.1 minus 12 dB, RESEARCH A3), tuned by ear. Instrument comes from palette `roles.lead` (`\ppArp`). Because this is the live proof of select-by-name, it is the only file expected to need `PP_LIBRARY_ALLOW_EDIT` (RESEARCH Pitfall 9).

### `_template.scd` x3 and `library/README.md`

Copy each category's `classic.scd` shape with commented guidance; skipped as selectable (leading `_`). README states "never edit, always add a new file".

---

### `supercollider/library_test.scd` (test, event-driven)

**Analog:** `supercollider/smoke_test.scd`. Copy structure:

**Header/protocol** (1-12): `CHECK OK:` / `SMOKE FAIL:` become `LIBCHECK OK:` / `LIBRARY FAIL:` / `LIBRARY PASS`.

**Setup (14-44)**: single parenthesized block with var list, watchdog first, root capture, isolated server, throwing `fail`:
```supercollider
SystemClock.sched(300, { "SMOKE FAIL: watchdog timeout".postln; 1.exit; nil });
root = File.realpath(thisProcess.nowExecutingPath).dirname.dirname;
Server.default = s = Server(\ppSmoke, NetAddr("127.0.0.1", 57140));   // use \ppLib, port 57141
~ppReady = false;
~ppPlaying = nil;
fail = { |name, detail| Error("%: %".format(name, detail)).throw; };
checkOk = { |name| "CHECK OK: %".format(name).postln; };
```

**Group inspection helpers (206-278)**: reuse `instrChildCount`, `instrDefNames`, `groupChildDefs` verbatim (OSCFunc on `/g_queryTree.reply`, polling loop, `replyMsg[3]`).

**Probe SynthDef + OSCdef (282-284, 321-324)**: reuse the `SendReply.kr(Impulse.kr(20), '/pp/test/peak', Peak.ar(sig))` probe for the voice-contract test.

**Boot + run (302-318, 1913-1919)**:
```supercollider
fork({
	s.boot; /* poll s.serverRunning up to 30 s */ s.volume.mute;
	...
	{ ... }.try({ |err| "SMOKE FAIL: %".format(err.errorString).postln; s.quit(onComplete: { 1.exit }); });
}, AppClock);
// success: "SMOKE PASS".postln; s.quit(onComplete: { 0.exit });
```
Raw OSC sends for selection tests: `NetAddr("127.0.0.1", NetAddr.langPort).sendMsg('/pp/melody', 'classic_lead')` (pattern from `sendBpm`, line 94).

### `supercollider/smoke_test.scd` (MODIFY)

Only the deliberate edits: line 833 `var expected = Set[\ppKick, \ppHat, \ppClap, \ppBass, \ppArp, \ppPad];` gains `\ppLead`. Line 851 set (sounding SynthDef names) does NOT change. Add the ENG-05 block (3 re-evals + counts) following the existing re-evaluation checks that use `~ppLayers.do { |name| ... fail.(...) }` (e.g. 1901-1910) and end each check with `checkOk.("...")`.

---

### `scripts/library_check.sh`, `scripts/check.sh`

**Analog:** `scripts/smoke_test.sh`. Copy exactly:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SCLANG="${SCLANG:-/Applications/SuperCollider.app/Contents/MacOS/sclang}"
if [ ! -x "$SCLANG" ]; then echo "... FAILED: sclang not found ..." >&2; exit 1; fi
unset QT_QPA_PLATFORM          # lines 22-26: never set offscreen, aborts with 134
LOG="${TMPDIR:-/tmp}/pedalpulse-smoke.log"
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD="timeout 330"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD="gtimeout 330"; fi
rc=0
$TIMEOUT_CMD "$SCLANG" -D supercollider/smoke_test.scd > "$LOG" 2>&1 || rc=$?
cat "$LOG"
if [ "$rc" -eq 0 ] && grep -q "SMOKE PASS" "$LOG"; then exit 0; else echo "... FAILED (log: $LOG)" >&2; exit 1; fi
```
Use a different `LOG` name (`pedalpulse-library.log`), `grep -q "LIBRARY PASS"`, a shorter timeout (about 120). Prepend the git guard from RESEARCH lines 397-403 and the LIBCHECK count cross-check. `check.sh` just runs `scripts/library_check.sh` then `scripts/smoke_test.sh` under `set -euo pipefail`. Keep tab indentation as in the analog.

### `scripts/pp_select.sh`

**Analog:** `python_app/osc_client.py` (send-only, `SimpleUDPClient`, port 57120, address constants in `python_app/config.py`). Use `.venv/bin/python` (same check as `smoke_test.sh:16-20`) with a one-line `SimpleUDPClient("127.0.0.1", 57120).send_message("/pp/<category>", "<stem>")`. No change to Python source (Phase 5 adds the GUI side).

---

## Shared Patterns

### OSC handler guard and logging
**Source:** `supercollider/main.scd:366-375` (shown above). Apply to all three new OSCdefs: type-check `msg[1]`, `"PedalPulse WARNING: ignoring ... with invalid argument %"`, `srcID: NetAddr("127.0.0.1", nil)`.

### Re-evaluation idempotence
**Source:** `main.scd:43-70`. Persist selection with `~x = ~x ? default`; stop all `~ppLayers` Pbindefs before rebuild; `Pbindef(name).clear` before redefining; OSCdefs replace by key.

### Invariants a library file must never bypass
**Source:** `main.scd:154-160, 190, 316-350`. Voices write to `~ppMixBus` in `~ppInstrGroup`, have `gate` (pitched) and `doneAction: 2`; core forces `out`/`group`; only `~ppRampStepper` writes `~clock.tempo`; Stop is `~ppInstrGroup.set(\gate, 0)`.

### Test-harness protocol
**Source:** `smoke_test.scd:14-60, 302-318, 1913-1919`; `unset QT_QPA_PLATFORM` in scripts; isolated server on a non-default port; tests throw via `fail`, top-level `try` prints FAIL and exits 1.

### Post message convention
`"PedalPulse: ..."`, `"PedalPulse WARNING: ..."`, `"PedalPulse ERROR: ... <file path>"` (errors must name the file; `String:load` compile errors do not).

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `supercollider/golden/v1_events.scd` | fixture | batch | Generated by the recorder (RESEARCH "Recorder" example lines 349-367) from the UNMODIFIED `main.scd` in Wave 0 |
| `supercollider/core/loader.scd` registry/ensure/realpath containment | service | file-I/O | No loader exists; use RESEARCH Pattern 3 and Pitfalls 2, 5 |
| `scripts/library_check.sh` git guard | script | batch | No git tooling in repo; use RESEARCH lines 397-404 |
| Recorder `\ppRecord` Event type, voice-contract test, ENG-05 counters | test helpers | event-driven | New; use RESEARCH lines 349-414 |

## Metadata

**Analog search scope:** whole repo (`git ls-files`): `supercollider/`, `scripts/`, `python_app/`
**Files scanned:** 4 read in detail (`main.scd`, `smoke_test.scd` ranges 1-140, 200-330, 1895-1920, `scripts/smoke_test.sh`, `osc_client.py` header)
**Pattern extraction date:** 2026-10-11
