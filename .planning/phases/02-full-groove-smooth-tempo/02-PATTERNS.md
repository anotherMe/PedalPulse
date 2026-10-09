# Phase 2: Full Groove & Smooth Tempo - Pattern Map

**Mapped:** 2026-10-09
**Files analyzed:** 7 (2 new, 5 modified)
**Analogs found:** 7 / 7 (all in-repo, Phase 1 code — this is no longer greenfield)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `supercollider/main.scd` (modify: ramp stepper, arp/pad SynthDefs+Pbindefs, `/pp/play` OSCdef, `Group.set` gate release) | config/controller (SC entry file) | event-driven (OSC) + streaming (audio) | itself (Phase 1 `main.scd`, existing `/pp/bpm` handler + kick/hat/bass Pbindefs) | exact — same file, extending established in-file idioms |
| `supercollider/smoke_test.scd` (modify: extend with glide/retarget/Start-Stop/gate-broadcast checks) | test | batch (headless compile/boot/behavior check) | itself (Phase 1 `smoke_test.scd`) | exact |
| `python_app/bpm_logic.py` (modify: add `PlayController`) | service (pure state + send policy) | request-response (fire-and-forget, event-driven on discrete click) | itself — `BpmController` class in the same file | exact — same file, parallel class |
| `python_app/osc_client.py` (modify: add `send_play`) | service (thin OSC wrapper) | request-response (fire-and-forget UDP send) | itself — `send_bpm` method in the same file | exact |
| `python_app/config.py` (modify: add `OSC_PLAY_ADDRESS`) | config | — | itself — `OSC_BPM_ADDRESS` constant | exact |
| `python_app/tests/test_play_logic.py` (new) | test | — | `python_app/tests/test_bpm_logic.py` | exact — same style, new file for `PlayController` |
| `python_app/tests/test_osc_client.py` (modify: add `send_play` tests) | test | — | itself — existing `send_bpm` test functions | exact |

## Pattern Assignments

### `supercollider/main.scd` (controller, event-driven + streaming)

**Analog:** itself — `supercollider/main.scd:111-131` (`/pp/bpm` handler) and `main.scd:37-106` (SynthDef/Pbindef idiom)

**Latest-wins mutable-var idiom to generalize for the ramp stepper** (lines 111-131, already in file):
```supercollider
OSCdef(\pp_bpm, { |msg|
	var raw = msg[1];
	if (raw.isNumber.not or: { raw.isNaN }) {
		"PedalPulse WARNING: ignoring /pp/bpm with invalid argument %".format(raw).postln;
	} {
		var bpm = raw.asFloat.clip(60, 180);  // TEMPO-03, D-09
		~ppPendingBpm = bpm;
		if (~ppApplyScheduled.not) {
			~ppApplyScheduled = true;
			~clock.schedAbs(~clock.nextTimeOnGrid(1), {
				~clock.tempo = ~ppPendingBpm / 60;
				~bpm = ~ppPendingBpm;
				~ppLastApplyBeat = ~clock.beats;
				~ppTempoApplyCount = ~ppTempoApplyCount + 1;
				~ppApplyScheduled = false;
				nil;
			});
		};
	};
}, '/pp/bpm', srcID: NetAddr("127.0.0.1", nil));
```
Generalize this exact "one pending value(s) + one scheduled callback" shape to "one pending target+rate + one persistent stepper Routine" per RESEARCH.md Pattern 1 — do not rewrite the validation/clamp/logging shape, extend it.

**SynthDef + Pbindef idiom to copy for `\ppArp`/`\ppPad`/`\ppClap`** (lines 37-57, 78-106):
```supercollider
SynthDef(\ppBass, { |out = 0, amp = 0.25, freq = 55, gate = 1|
	var sig, env;
	env = EnvGen.kr(Env.adsr(0.005, 0.1, 0.6, 0.05), gate, doneAction: 2);
	sig = Saw.ar([freq, freq * 1.01]);
	sig = RLPF.ar(sig, 700, 0.6);
	Out.ar(out, sig * env * amp);
}).add;
...
Pbindef(\ppBass,
	\instrument, \ppBass,
	\dur, 0.5,
	\midinote, Pseq([\rest, 33, \rest, 33, \rest, 33, \rest, 36], inf),
	\legato, 0.8,
	\out, ~ppMixBus,
	\group, ~ppInstrGroup,
);
Pbindef(\ppBass).play(~clock, quant: 4);
```
Every new SynthDef MUST follow this exact `EnvGen.kr(..., gate, doneAction: 2)` shape (non-negotiable, CLAUDE.md). Every new Pbindef MUST use `\out, ~ppMixBus, \group, ~ppInstrGroup` and `.play(~clock, quant: 4)` — same clock instance, no new `TempoClock`.

**Idempotent re-evaluation teardown to extend** (lines 20-35) — the existing `.stop`/`.free` block at the top of `s.waitForBoot` must be extended to also `.stop` the new Pbindefs (`\ppClap`, `\ppArp`, `\ppPad`) and reset any new ramp-stepper state var, mirroring the existing `~ppApplyScheduled = false;` reset line.

**Error handling / validation pattern for `/pp/play`:** copy the `raw.isNumber.not` guard verbatim from the `/pp/bpm` handler above (RESEARCH.md Pattern 3 already gives the exact adapted code) — same warning-postln-on-invalid-input shape, same `srcID: NetAddr("127.0.0.1", nil)` loopback guard.

---

### `supercollider/smoke_test.scd` (test, batch)

**Analog:** itself — existing check blocks, e.g. the "B3: latest wins" block (lines 171-187) and `waitForApplyChange` helper (lines 55-62)

```supercollider
waitForApplyChange = { |before, timeoutSec|
	var elapsed = 0;
	while ({ (~ppTempoApplyCount == before) and: { elapsed < timeoutSec } }) {
		0.1.wait;
		elapsed = elapsed + 0.1;
	};
	~ppTempoApplyCount != before;
};
```
Copy this poll-with-timeout idiom for the new glide/retarget/Start-Stop checks (e.g. poll `~clock.tempo` trajectory, poll `s.numSynths` after Stop). Each new check must follow the existing `checkOk.("name")` / `fail.("name", "detail")` contract (lines 39-41, 35-37) — never introduce a different pass/fail signaling convention. Append new checks as additional `{ ... }.value;` blocks in the same `fork({...}, AppClock)` body, same place existing B1-B8 blocks live (lines 145-341), before the final `"SMOKE PASS".postln;`.

---

### `python_app/bpm_logic.py` (service, request-response / event-driven)

**Analog:** itself — `BpmController` class (lines 83-167) and its `_set`/`_notify` idiom (lines 106-117)

```python
def _notify(self) -> None:
    """Call every listener with the current value (no change required)."""
    for listener in self._listeners:
        listener(self._value)

def _set(self, new_value: int) -> bool:
    """Update the value and notify listeners only on an actual change."""
    if new_value == self._value:
        return False
    self._value = new_value
    self._notify()
    return True
```
`PlayController` (RESEARCH.md Pattern 4 gives the full target code) must follow this exact "track value, notify-on-change, caller decides when to send" shape — add it as a new class in the same module, after `BpmController`, importing nothing new (`from __future__ import annotations`, `Callable` already imported at top of file). No debounce needed (unlike `BpmController`, which wraps a `Debouncer`) — Start/Stop is a discrete click.

**`send_initial()` philosophy to mirror** (lines 164-166):
```python
def send_initial(self) -> None:
    """Send the current value once, unconditionally (D-23)."""
    self._send_now()
```

---

### `python_app/osc_client.py` (service, request-response)

**Analog:** itself — `send_bpm` method (lines 31-44)

```python
def send_bpm(self, bpm: float) -> bool:
    try:
        self._client.send_message(config.OSC_BPM_ADDRESS, float(bpm))
    except OSError as exc:
        print(f"OscClient: failed to send /pp/bpm {bpm} to {self.target}: {exc}", file=sys.stderr)
        return False
    return True
```
New `send_play(self, playing: int) -> bool` must copy this try/except-OSError-returns-False shape verbatim, swapping in `config.OSC_PLAY_ADDRESS` and an `int` argument (per RESEARCH.md Pattern 4 wire contract: `/pp/play <int>`, 1/0). Keep the same error-message format string style (`f"OscClient: failed to send {address} {value} to {self.target}: {exc}"`).

---

### `python_app/config.py` (config)

**Analog:** itself — `OSC_BPM_ADDRESS = "/pp/bpm"` (line 9)

```python
OSC_HOST = "127.0.0.1"
OSC_PORT = 57120  # sclang language port (NOT scsynth 57110)
OSC_BPM_ADDRESS = "/pp/bpm"
```
Add `OSC_PLAY_ADDRESS = "/pp/play"` as a sibling constant, same module, same naming convention (`OSC_<NAME>_ADDRESS`).

---

### `python_app/tests/test_play_logic.py` (new, test)

**Analog:** `python_app/tests/test_bpm_logic.py`

Read this file's structure (not reproduced here to save budget — it is small, pure-logic tests with no mocking, same pytest style as the rest of the suite) and mirror its test-function naming and assertion style for `PlayController`: construct with a fake `send` callable (a list-append spy), assert `set_playing`/`toggle`/`send_initial` call `send` with the right int (1/0) only on actual state changes, and assert idempotent repeated calls do not re-send.

---

### `python_app/tests/test_osc_client.py` (modify, test)

**Analog:** itself — existing `send_bpm`-covering test functions, e.g. `test_send_bpm_delivers_decodable_osc_message_over_real_socket` (RESEARCH.md line 457 references this by name)

Extend the same file with parallel `send_play` test functions using the identical mock-socket-interception pattern already used for `send_bpm` (per CLAUDE.md Testing Approach: `unittest.mock.patch("socket.socket")`, asserting correct OSC address/argument bytes without opening a real socket).

## Shared Patterns

### Latest-wins mutable-state idiom (applies to `main.scd`'s ramp stepper AND `/pp/play` OSCdef)
**Source:** `supercollider/main.scd:111-131` (`~ppPendingBpm`/`~ppApplyScheduled`)
**Apply to:** The new ramp-stepper's `~ppRampTargetBpm`/`~ppRampRateBpm` vars (generalizing "one pending value" to "one pending target+rate") and the idempotency check in `/pp/play` (`want != ~ppPlaying`, the same "only act on an actual change" philosophy as `BpmController._set`).

### `doneAction: 2` on every enveloped SynthDef (applies to `main.scd`'s new `\ppArp`, `\ppPad`, `\ppClap`)
**Source:** `supercollider/main.scd:39,46,53` (existing kick/hat/bass `EnvGen.kr(..., doneAction: 2)`), reaffirmed CLAUDE.md non-negotiable.
**Apply to:** Every new SynthDef this phase adds — no exceptions, including the pad's long-release envelope.

### "Track value / notify-on-change / caller decides send timing" controller shape (applies to `bpm_logic.py`'s new `PlayController`)
**Source:** `python_app/bpm_logic.py:106-117` (`BpmController._set`/`_notify`)
**Apply to:** `PlayController.set_playing`/`toggle` — same shape, no debounce layer.

### try/except-OSError-returns-False OSC send shape (applies to `osc_client.py`'s new `send_play`)
**Source:** `python_app/osc_client.py:31-44` (`send_bpm`)
**Apply to:** `send_play` — identical error handling, different address/value type.

### Loopback-only + invalid-input-warns-and-ignores guard (applies to `main.scd`'s new `/pp/play` OSCdef)
**Source:** `supercollider/main.scd:111-131` (`/pp/bpm` OSCdef's `isNumber.not` guard and `srcID: NetAddr("127.0.0.1", nil)`)
**Apply to:** `/pp/play` OSCdef — same guard shape, `isNumber` check before `.asInteger` (per RESEARCH.md Security Domain V5).

### Poll-with-timeout smoke-test helper (applies to new `smoke_test.scd` checks)
**Source:** `supercollider/smoke_test.scd:55-62` (`waitForApplyChange`)
**Apply to:** Any new check needing to wait for an async engine-side state change (glide convergence, numSynths settling after Stop, `~ppReady` after re-evaluation) — reuse or closely mirror this exact while-loop-with-elapsed-counter shape rather than inventing a new polling idiom.

## No Analog Found

None — every file in this phase is a modification to, or new sibling of, an existing Phase 1 file with a directly applicable in-repo analog. (Unlike Phase 1, which was greenfield, Phase 2 builds entirely on established in-repo precedent.)

## Metadata

**Analog search scope:** `supercollider/`, `python_app/` (full tracked tree, verified via `git ls-files`)
**Files scanned:** 7 (all files to be modified/created this phase; each analog is the file's own Phase 1 version — no cross-file analog search was needed since every file already exists)
**Pattern extraction date:** 2026-10-09
