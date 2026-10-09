# Phase 3: EPIC Zones & Volume - Pattern Map

**Mapped:** 2026-10-09
**Files analyzed:** 9 (3 new, 6 modified)
**Analogs found:** 9 / 9 (all in-repo, Phase 1/2 code — no greenfield files this phase)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `supercollider/main.scd` (modify: +2 control buses, +1 audio bus, +1 Group, +2 SynthDefs (`\ppEpicSmoother`, `\ppFx`), `\ppMaster` gets `volumeBus` arg, +2 OSCdefs) | config/controller (SC entry file) | event-driven (OSC) + streaming (audio) | itself — Phase 1/2 `main.scd` (`/pp/bpm` OSCdef, `\ppMaster` SynthDef, re-evaluation teardown block) | exact — same file, extending established in-file idioms |
| `supercollider/smoke_test.scd` (modify: +EPIC-produces-measurable-change check, +EPIC-glides check, +max-EPIC-max-volume-no-clip check using `measurePeak`) | test | batch (headless compile/boot/behavior check) | itself — Phase 2 `smoke_test.scd` (`waitForApplyChange`, `measurePeak`/`\ppPeakProbe`) | exact |
| `python_app/bpm_logic.py` (modify: +`EpicController`, +`VolumeController`, +`clamp_volume`) | service (pure state + send policy) | request-response, event-driven (discrete click for EPIC) / request-response (slider-release for volume) | itself — `PlayController` (event-driven analog) and `BpmController` (slider-release analog), same file | exact — same file, parallel classes |
| `python_app/osc_client.py` (modify: +`send_epic`, +`send_volume`) | service (thin OSC wrapper) | request-response (fire-and-forget UDP send) | itself — `send_bpm`/`send_play` methods, same file | exact |
| `python_app/config.py` (modify: +`OSC_EPIC_ADDRESS`, +`OSC_VOLUME_ADDRESS`, +`EPIC_ZONES`, +`EPIC_DEFAULT_ZONE`, +`VOLUME_MIN/MAX/DEFAULT`) | config | — | itself — `OSC_BPM_ADDRESS`/`OSC_PLAY_ADDRESS`, `BPM_MIN/MAX/DEFAULT` constants | exact |
| `python_app/view.py` (modify: +5 zone buttons with selected-state highlight, +volume `Scale`, fix WR-01 entry-focus guard) | component (Tk view) | event-driven (button click) / request-response (slider drag+release) | itself — `nudge_buttons` row (button-row-from-dict analog) and the BPM `Scale` (slider-release analog), `play_button`/`_on_playing_changed` (listener-driven label/state-update analog) | exact |
| `python_app/tests/test_epic_logic.py` (new) | test | — | `python_app/tests/test_play_logic.py` | exact — same style, new file for `EpicController` |
| `python_app/tests/test_volume_logic.py` (new) | test | — | `python_app/tests/test_bpm_logic.py` | exact — same style (has a slider + clamp), new file for `VolumeController`/`clamp_volume` |
| `python_app/tests/test_osc_client.py` (modify: +`send_epic`/`send_volume` tests) | test | — | itself — existing `send_bpm`/`send_play` test functions | exact |
| `python_app/tests/test_view_tk.py` (modify: +zone-button-highlight-on-click, +volume-slider-send-on-release tests) | test | — | itself — existing BPM-scale/play-button Tk tests | exact |

## Pattern Assignments

### `supercollider/main.scd` (controller, event-driven + streaming)

**Analog:** itself — `supercollider/main.scd:93-96` (`\ppMaster` SynthDef + instantiation), `main.scd:272-299` (`/pp/bpm`/`/pp/play` OSCdefs), `main.scd:23-45` (re-evaluation teardown block)

**Bus-index-as-plain-control-arg idiom to reuse verbatim** (lines 93-96, current):
```supercollider
SynthDef(\ppMaster, { |in, out = 0, preGain = 1|
	var sig = In.ar(in, 2) * preGain;
	Out.ar(out, Limiter.ar(sig, 0.891251, 0.01));  // D-16: -1 dBFS = 10^(-1/20) ~= 0.891251
}).add;
...
~ppMixBus = Bus.audio(s, 2);
~ppInstrGroup = Group.new(s);
~ppMasterGroup = Group.after(~ppInstrGroup);
~ppMasterSynth = Synth(\ppMaster, [\in, ~ppMixBus, \out, 0, \preGain, ~preGain], ~ppMasterGroup);
```
Extend `\ppMaster` to accept `volumeBus = 0` and multiply `In.kr(volumeBus)` (Lag'd 0.2s) into `sig`, **before** `Limiter.ar` — never after (Pitfall 1). New `~ppFxGroup = Group.after(~ppInstrGroup)` goes between `~ppInstrGroup` and `~ppMasterGroup`; `~ppMasterGroup` becomes `Group.after(~ppFxGroup)`; `\ppMaster`'s `\in` arg changes from `~ppMixBus` to the new `~ppFxBus` (Pitfall 3 — this is the single easiest regression to introduce).

**OSCdef validation/clamp/logging shape to copy verbatim** (lines 272-285, `/pp/bpm`):
```supercollider
OSCdef(\pp_bpm, { |msg|
	var raw = msg[1];
	if (raw.isNumber.not or: { raw.isNaN }) {
		"PedalPulse WARNING: ignoring /pp/bpm with invalid argument %".format(raw).postln;
	} {
		var bpm = raw.asFloat.clip(60, 180);  // TEMPO-03, D-09
		~ppRampPendingBpm = bpm;
		"PedalPulse: /pp/bpm % -> % BPM (glide over % beats)".format(raw, bpm, ~ppRampBeats).postln;
	};
}, '/pp/bpm', srcID: NetAddr("127.0.0.1", nil));
```
New `OSCdef(\pp_epic, ...)` and `OSCdef(\pp_volume, ...)` must copy this exact `isNumber.not or: isNaN` guard, `.clip(0, 100)`, same `srcID: NetAddr("127.0.0.1", nil)` loopback guard, and same `"PedalPulse: ..."` log-line convention — per RESEARCH.md Pattern 1 (lines 191-200), the full adapted `/pp/epic` handler is already drafted there, writing into `~ppEpicBus.set(~epic.linlin(0, 100, 0, 1))` instead of a ramp-stepper var.

**Idempotent re-evaluation teardown to extend** (lines 23-33, current):
```supercollider
~ppLayers.do { |name| Pbindef(name).stop };
if (~ppRampStepper.notNil) { ~ppRampStepper.stop };
if (~clock.notNil) { ~clock.stop };
0.3.wait;
if (~ppMasterSynth.notNil) { ~ppMasterSynth.free };
if (~ppMasterGroup.notNil) { ~ppMasterGroup.free };
if (~ppInstrGroup.notNil) { ~ppInstrGroup.free };
if (~ppMixBus.notNil) { ~ppMixBus.free };
```
Add, in dependency order (free synths that *read* a bus before freeing the bus): `~ppFxSynth` + `~ppEpicSmoother` freed, then `~ppFxGroup` freed, then `~ppFxBus`/`~ppEpicBus`/`~ppEpicSmoothBus`/`~ppVolumeBus` freed — mirroring exactly how `~ppMasterSynth` → `~ppMasterGroup` → `~ppMixBus` are ordered today (Pitfall 2).

**New SynthDefs (RESEARCH.md Pattern 1 and 2 give full drafted code):**
```supercollider
SynthDef(\ppEpicSmoother, { |in, out|
    Out.kr(out, Lag.kr(In.kr(in), ~ppEpicLagSecs));
}).add;

SynthDef(\ppFx, { |in, out, epicBus = 0|
	var sig = In.ar(in, 2);
	var epic = In.kr(epicBus);  // already Lag'd by ~ppEpicSmoother -- 0..1
	var drive = epic.linlin(0, 1, 1.0, 3.5);
	var cutoff = epic.linexp(0, 1, 500, 9000);
	var richness = epic;
	var wet = epic.linlin(0, 1, 0.08, 0.35);

	sig = (sig * drive).softclip;
	sig = RLPF.ar(sig, cutoff, 0.5);
	sig = sig + (HPF.ar(sig, 3500) * richness * 0.35);
	sig = FreeVerb.ar(sig, wet, room: 0.6, damp: 0.3);
	Out.ar(out, sig);
}).add;
```
Note: these synths have **no envelope / no `doneAction`** — they are persistent, not per-note (unlike every existing instrument SynthDef, which uses `EnvGen.kr(..., doneAction: 2)`). This is a deliberate, documented exception to the project's `doneAction: 2` rule, not an oversight — do not add an envelope to these two.

**Node-order correctness:** instantiate `~ppEpicSmoother` with `addAction: \addToHead` inside `~ppFxGroup`, then `~ppFxSynth` normally (added after it, toward the group's tail) — this guarantees the smoother executes before `\ppFx` reads its output bus within the same control block (RESEARCH.md Pattern 2, "Node-order correctness note").

**RLPF reuse precedent:** `\ppBass` already uses `RLPF.ar(sig, 700, 0.6)` (`main.scd:65` approx, existing bass voice) — `\ppFx`'s filter stage reuses the exact same filter class for tonal consistency, just with a dynamic cutoff instead of the bass's fixed 700Hz.

---

### `supercollider/smoke_test.scd` (test, batch)

**Analog:** itself — `measurePeak`/`\ppPeakProbe` helper (`smoke_test.scd:888-916`, quoted verbatim in RESEARCH.md) and `waitForApplyChange` poll-with-timeout helper (Phase 2 pattern map, `smoke_test.scd:55-62`)

```supercollider
measurePeak = { |busIndex, durSec| var probe; peakVal = 0.0; probe = Synth.after(~ppMasterGroup, \ppPeakProbe, [\in, busIndex]); durSec.wait; probe.free; peakVal; };
```
Reuse this exact helper for the max-EPIC-max-volume no-clip check: send `/pp/epic 100` and `/pp/volume 100`, wait past both lag windows (≥1.5s + a margin), `measurePeak.(0, 4)`, assert `<= 0.892`. Reuse the `waitForApplyChange`-style while-loop-with-elapsed-counter idiom for the EPIC-glides-not-jumps check (poll `~ppEpicSmoothBus`'s value via a probe at intervals, assert monotonic convergence, not an instant jump). Every new check must follow the existing `checkOk.("name")` / `fail.("name", "detail")` contract — append as additional blocks in the same `fork({...}, AppClock)` body, before the final `"SMOKE PASS".postln;`.

---

### `python_app/bpm_logic.py` (service, request-response / event-driven)

**Analog:** itself — `PlayController` (lines 170-219, event-driven/discrete-click shape) and `BpmController` (lines 84-168, slider-release shape) plus `clamp_bpm` (lines 17-27)

**`clamp_bpm` to mirror for `clamp_volume`** (lines 17-27):
```python
def clamp_bpm(value: float) -> int:
    if not math.isfinite(value):
        raise ValueError(f"clamp_bpm: value must be finite, got {value!r}")
    rounded = int(math.floor(value + 0.5))
    return max(config.BPM_MIN, min(config.BPM_MAX, rounded))
```
`clamp_volume` copies this exact finite-check/half-up-round/clamp shape with `config.VOLUME_MIN`/`config.VOLUME_MAX`.

**`PlayController`'s track-value/notify-on-change/no-debounce shape to mirror for `EpicController`** (lines 170-219, quoted in full — already the exact shape needed, just swap `bool` state for a `str` zone name and `int` 1/0 send for a `float` zone-value send):
```python
class PlayController:
    def __init__(self, send, initial=True): ...
    def set_playing(self, playing: bool) -> None:
        new_state = bool(playing)
        if new_state == self._playing:
            return
        self._playing = new_state
        self._notify()
        self._send(1 if new_state else 0)
    def toggle(self) -> None: ...
    def send_initial(self) -> None:
        self._send(1 if self._playing else 0)
```
RESEARCH.md Pattern 3 (lines 254-298) already gives the fully-adapted `EpicController` using this exact shape with `zones: dict[str, float]` and `select_zone(zone_name)` replacing `toggle()`.

**`BpmController`'s slider-moved/slider-released shape to mirror for `VolumeController`** (lines 124-131, `_set`/`_notify` lines 107-118):
```python
def _set(self, new_value: int) -> bool:
    if new_value == self._value:
        return False
    self._value = new_value
    self._notify()
    return True

def slider_moved(self, raw: str | float) -> None:
    """Live update while dragging. Never sends (D-20)."""
    new_value = clamp_bpm(float(raw))
    self._set(new_value)

def slider_released(self) -> None:
    """Send the current value now (D-20)."""
    self._send_now()
```
`VolumeController` mirrors this exactly, minus the debounce/nudge/entry machinery `BpmController` has for its own reasons (no nudge buttons or entry field spec'd for volume, per RESEARCH.md Pattern 4) — full drafted code in RESEARCH.md lines 336-379.

**`send_initial()` philosophy to mirror** (line 165-167, `BpmController`):
```python
def send_initial(self) -> None:
    """Send the current value once, unconditionally (D-23)."""
    self._send_now()
```
Both `EpicController.send_initial()` and `VolumeController.send_initial()` must follow this same D-23 "send once unconditionally at launch" contract.

---

### `python_app/osc_client.py` (service, request-response)

**Analog:** itself — `send_bpm` (lines 35-48) and `send_play` (lines 50-63)

```python
def send_bpm(self, bpm: float) -> bool:
    try:
        self._client.send_message(config.OSC_BPM_ADDRESS, float(bpm))
    except OSError as exc:
        print(f"OscClient: failed to send /pp/bpm {bpm} to {self.target}: {exc}", file=sys.stderr)
        return False
    return True
```
New `send_epic(self, epic: float) -> bool` and `send_volume(self, volume: float) -> bool` must copy this try/except-OSError-returns-False shape verbatim (both are `float` args, unlike `send_play`'s `int` coercion — no special type-coercion concern like `send_play`'s bool→OSC-type-tag note applies here), swapping in `config.OSC_EPIC_ADDRESS`/`config.OSC_VOLUME_ADDRESS` and the same `f"OscClient: failed to send {address} {value} to {self.target}: {exc}"` error-message format.

---

### `python_app/config.py` (config)

**Analog:** itself — `OSC_BPM_ADDRESS = "/pp/bpm"` (line 9), `BPM_MIN/MAX/DEFAULT` (lines 11-13)

```python
OSC_BPM_ADDRESS = "/pp/bpm"
OSC_PLAY_ADDRESS = "/pp/play"
BPM_MIN = 60
BPM_MAX = 180
BPM_DEFAULT = 120
NUDGE_DEBOUNCE_MS = 150
```
Add, same module, same `OSC_<NAME>_ADDRESS` naming convention:
```python
OSC_EPIC_ADDRESS = "/pp/epic"
OSC_VOLUME_ADDRESS = "/pp/volume"
EPIC_ZONES = {
    "Recovery": 10,
    "Endurance": 30,
    "Tempo": 50,
    "Threshold": 75,
    "VO2": 100,
}
EPIC_DEFAULT_ZONE = "Recovery"
VOLUME_MIN = 0
VOLUME_MAX = 100
VOLUME_DEFAULT = 80
```

---

### `python_app/view.py` (component, event-driven + request-response)

**Analog:** itself — nudge-button-row-from-dict idiom (lines 73-82), BPM `Scale` slider-release wiring (lines 46-62), `play_button`/`_on_playing_changed` listener-driven label update (lines 113-120, 149-155)

**Button-row-from-dict idiom to copy for the 5 zone buttons** (lines 73-82):
```python
self.nudge_buttons: dict[int, tk.Button] = {}
for delta in (-5, -1):
    button = tk.Button(
        self.nudge_row,
        text=NUDGE_LABELS[delta],
        takefocus=0,
        command=lambda d=delta: controller.nudge(d),
    )
    button.pack(side="left", padx=4)
    self.nudge_buttons[delta] = button
```
Build a `self.zone_buttons: dict[str, tk.Button] = {}` loop over `config.EPIC_ZONES` keys the same way, `command=lambda z=name: epic_controller.select_zone(z)`, `takefocus=0` (same WR-01-adjacent discipline as every other button).

**Listener-driven highlight-state update to copy** (lines 113-120 construction, 154-155 listener):
```python
self.play_button = tk.Button(
    self.transport_row, text=PLAY_LABELS[play_controller.playing],
    width=8, takefocus=0, command=play_controller.toggle,
)
self.play_button.pack()
play_controller.add_listener(self._on_playing_changed)
...
def _on_playing_changed(self, playing: bool) -> None:
    self.play_button["text"] = PLAY_LABELS[playing]
```
Mirror this exact "construct widget → `add_listener` → listener mutates widget state" wiring for zone-button highlighting: `epic_controller.add_listener(self._on_zone_changed)`, where `_on_zone_changed(zone_name)` sets `relief="sunken"` (or similar) on the selected button and `relief="raised"` on all others — per Gray Areas, manual `relief` toggling (not `tk.Radiobutton`) to match the existing `Button`-only visual language.

**BPM `Scale` drag-live/send-on-release wiring to copy for the volume `Scale`** (lines 45-62):
```python
self.scale = tk.Scale(
    container, from_=config.BPM_MIN, to=config.BPM_MAX, orient="horizontal",
    resolution=1, length=320, label="BPM", variable=self.bpm_var,
    command=controller.slider_moved, takefocus=0,
)
self.scale.pack(fill="x")
self.scale.bind("<ButtonRelease-1>", lambda _event: controller.slider_released())
```
New volume `Scale` copies this exactly: `from_=config.VOLUME_MIN, to=config.VOLUME_MAX, label="Volume", command=volume_controller.slider_moved, takefocus=0` (Pitfall 4 — `takefocus=0` is load-bearing for keeping the root-bound arrow-key shortcuts unambiguous), `<ButtonRelease-1>` bound to `volume_controller.slider_released()`.

**WR-01 fix (in-scope this phase per STATE.md):** the root-level arrow-key bindings (lines 136-139) currently fire regardless of which widget has focus:
```python
self.root.bind("<Up>", lambda _event: self.handle_nudge_key(1))
self.root.bind("<Down>", lambda _event: self.handle_nudge_key(-1))
```
Add a focus guard in `handle_nudge_key` (or at the bind call sites) that no-ops when `self.root.focus_get() is self.entry` — this is a net-new guard, not copied from an existing pattern (no prior art for it in the file); keep it minimal and localized to `handle_nudge_key`.

---

### `python_app/tests/test_epic_logic.py` (new, test)

**Analog:** `python_app/tests/test_play_logic.py`

Mirror its structure: construct `EpicController` with a fake `send` callable (list-append spy) and `config.EPIC_ZONES`/`config.EPIC_DEFAULT_ZONE`; assert `select_zone` calls `send` with the correct float value only on an actual zone change (idempotent repeat is a no-op, no re-send); assert `send_initial()` sends the current zone's value unconditionally.

---

### `python_app/tests/test_volume_logic.py` (new, test)

**Analog:** `python_app/tests/test_bpm_logic.py`

Mirror its structure for the slider-drag-vs-release distinction: assert `slider_moved` never calls `send` (live-display-only, D-20), assert `slider_released` sends the current value, assert `clamp_volume` matches `clamp_bpm`'s half-up-round + `[0,100]` clamp contract (including the `ValueError` on non-finite input).

---

### `python_app/tests/test_osc_client.py` (modify, test)

**Analog:** itself — existing `send_bpm`/`send_play`-covering test functions (mock-socket interception pattern, per CLAUDE.md Testing Approach: `unittest.mock.patch("socket.socket")`)

Extend with parallel `send_epic`/`send_volume` test functions using the identical mock-socket pattern, asserting correct OSC address and float argument bytes without opening a real socket.

---

### `python_app/tests/test_view_tk.py` (modify, test)

**Analog:** itself — existing BPM-scale / play-button Tk widget tests

Extend with: a test clicking each zone button asserts the corresponding button's `relief` becomes the "selected" state and all others revert; a test dragging-then-releasing the volume `Scale` asserts `send` fires only once, on release, with the final dragged value.

## Shared Patterns

### Loopback-only + invalid-input-warns-and-ignores OSC guard
**Source:** `supercollider/main.scd:272-299` (`/pp/bpm`/`/pp/play` OSCdefs' `isNumber.not or: isNaN` guard, `srcID: NetAddr("127.0.0.1", nil)`)
**Apply to:** New `/pp/epic` and `/pp/volume` OSCdefs — same guard shape, `.clip(0, 100)` instead of `.clip(60, 180)`.

### "Track value / notify-on-change / caller decides send timing" controller shape
**Source:** `python_app/bpm_logic.py:107-118` (`BpmController._set`/`_notify`), `bpm_logic.py:195-211` (`PlayController.set_playing`)
**Apply to:** `EpicController.select_zone` (event-driven, no debounce, mirrors `PlayController`) and `VolumeController.slider_moved`/`slider_released` (drag-live/send-on-release, mirrors `BpmController`).

### try/except-OSError-returns-False OSC send shape
**Source:** `python_app/osc_client.py:35-48` (`send_bpm`), `osc_client.py:50-63` (`send_play`)
**Apply to:** `send_epic`, `send_volume` — identical error handling, both `float` args (no bool-coercion special case needed, unlike `send_play`).

### `send_initial()` D-23 philosophy (send once, unconditionally, at launch)
**Source:** `python_app/bpm_logic.py:165-167`, `bpm_logic.py:217-219`
**Apply to:** `EpicController.send_initial()`, `VolumeController.send_initial()` — both must fire once at app startup so the engine's `~epic`/`~volume` state matches the GUI's default-displayed zone/level.

### Listener-driven widget-state update (construct → `add_listener` → listener mutates widget)
**Source:** `python_app/view.py:113-120` (play button construction), `view.py:154-155` (`_on_playing_changed`)
**Apply to:** Zone-button highlight update (`_on_zone_changed`) and volume-display-label update if one is added (RESEARCH.md Open Question 2 recommends a small "Volume: NN%" label).

### Pre-limiter gain/FX staging, never a bypass
**Source:** `supercollider/main.scd:93-96` (`\ppMaster`'s existing `preGain * sig` placement before `Limiter.ar`)
**Apply to:** The new `volumeBus`-derived gain term inside `\ppMaster` (Pattern 5) and the entire `\ppFx` synth's output routing — both must feed into the unchanged `Limiter.ar(sig, 0.891251, 0.01)` call, never around it (Pitfall 1, success criterion 4).

### Idempotent re-evaluation teardown (free-before-rebuild, dependency order)
**Source:** `supercollider/main.scd:23-33` (existing guarded-free sequence for `~ppMasterSynth`/`~ppMasterGroup`/`~ppInstrGroup`/`~ppMixBus`)
**Apply to:** Every new Phase 3 object (`~ppFxSynth`, `~ppEpicSmoother`, `~ppFxGroup`, `~ppFxBus`, `~ppEpicBus`, `~ppEpicSmoothBus`, `~ppVolumeBus`) — add to the same sequence, synths before the groups/buses they read (Pitfall 2).

### `doneAction: 2` on every *enveloped* SynthDef — explicit non-applicability note
**Source:** CLAUDE.md non-negotiable rule, `supercollider/main.scd` existing kick/hat/bass/pad `EnvGen.kr(..., doneAction: 2)`
**Apply to:** Does **not** apply to `\ppEpicSmoother` or `\ppFx` — these are persistent (no envelope, no `doneAction`), a deliberate documented exception (RESEARCH.md line 20), not an oversight. Every other new SynthDef this phase might still need (none currently planned) would still require it.

## No Analog Found

None — every file in this phase is a modification to, or new sibling of, an existing Phase 1/2 file with a directly applicable in-repo analog (same situation as Phase 2's pattern map). The one genuinely novel mechanic — persistent (non-enveloped) SynthDefs (`\ppEpicSmoother`, `\ppFx`) and the `Lag.kr`-based control-bus smoother idiom — has no in-repo analog (every existing SynthDef is per-note/enveloped) but is fully grounded in official SuperCollider docs (`Lag`, `FreeVerb`, `RLPF`, `.softclip` — all `[VERIFIED]`/`[CITED]` in 03-RESEARCH.md's Pattern 1/2 and Don't Hand-Roll section) rather than a codebase analog.

| File/Mechanic | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `\ppEpicSmoother`, `\ppFx` SynthDefs (persistent, non-enveloped) | service (DSP) | streaming | No existing SynthDef in this codebase is persistent/non-enveloped — every current voice is per-note with `doneAction: 2`. Use 03-RESEARCH.md Pattern 1/2's fully-drafted code (official-docs-grounded) as the reference instead of an in-repo analog. |

## Metadata

**Analog search scope:** `supercollider/`, `python_app/` (full tracked tree, git-tracked source only — verified no gitignored mirrors referenced)
**Files scanned:** 9 (all files to be modified/created this phase); each analog is the file's own Phase 1/2 version, plus sibling classes/functions within the same file (`PlayController`/`BpmController` for the two new controllers, `send_bpm`/`send_play` for the two new OSC methods)
**Pattern extraction date:** 2026-10-09
