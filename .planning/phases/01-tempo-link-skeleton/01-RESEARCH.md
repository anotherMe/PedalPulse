# Phase 1: Tempo Link Skeleton - Research

**Researched:** 2026-10-08
**Domain:** SuperCollider audio-engine entry file (boot gating, TempoClock-driven loop, master limiter) + Python/Tkinter control app (slider/entry/nudge BPM controls, throttled OSC send) connected over localhost OSC/UDP
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Python environment & Tk check
- **D-01:** Do not use a global Python install. The app runs from a project-local virtualenv in `.venv/` (gitignored).
- **D-02:** `.venv` is created from Homebrew `python3.13`, which pairs with Tk 9.0.3. On this Mac it is the only interpreter with a working tkinter: Homebrew `python3` (3.14) and `python3.12` both lack `_tkinter`. This supersedes the research's "Tk 8.6 only" recommendation. The risk research flagged was an 8.6/9.0 *mismatch*, not a matched 9.0 build. The planner should include a quick smoke test that the slider, entry and buttons behave correctly under Tk 9. — **Reversibility:** reversible — recreating `.venv` from another interpreter is a one-line change in `run.sh`.
- **D-03:** Startup check (GUI-04): the app is "incompatible" if `tkinter`/`_tkinter` fails to import or `TkVersion < 8.6`. Tk 8.6 and 9.x both pass. No exact build-pairing check.
- **D-04:** On a failed check, print a clear terminal message explaining what is wrong and how to fix it (e.g. "run via ./run.sh / use the .venv built from python3.13"), then exit non-zero. No GUI dialog, since Tk may not be loadable.
- **D-05:** Launch through a small `./run.sh` wrapper. It creates `.venv` from `python3.13` if missing, installs `requirements.txt` (python-osc), and launches the app with the venv interpreter.

#### BPM controls & window (GUI-01)
- **D-06:** Controls are a slider, an integer entry field, and two nudge pairs laid out as `−5 −1 [value] +1 +5`. All of them stay in sync.
- **D-07:** Start/default BPM is 120 in both the GUI and the engine.
- **D-08:** GUI controls are limited to 60–180. The engine clamps independently (TEMPO-03). Engine clamping is verified by sending raw out-of-range OSC from a test script, not through the GUI.
- **D-09:** BPM is a whole number in the GUI. The engine accepts and clamps floats.
- **D-10:** The entry applies on Enter or focus-out. Invalid text reverts to the current value. Out-of-range numbers snap to 60 or 180.
- **D-11:** Keyboard shortcuts while the window has focus: Up/Down arrows ±1, Shift+Up/Down ±5.
- **D-12:** The window is compact, with an "On top" checkbox that toggles always-on-top so it can float over Zwift.

#### Skeleton loop sound (ENG-02, ENG-04)
- **D-13:** The loop is a four-on-the-floor kick, a hat, and a simple bassline: A minor, offbeat rolling 8ths on the root, with a note change at the bar end. SynthDefs should be reusable as the starting point for Phase 2's groove.
- **D-14:** Until Phase 2's ramp exists, a BPM change applies instantly, quantized to the next beat boundary. No glide yet.
- **D-15:** The loop autostarts once `main.scd` finishes booting (no transport command in Phase 1).
- **D-16:** The master limiter ceiling is −1 dBFS (≈0.89 linear) on the master bus. All audio goes through it.
- **D-17:** The hot-gain limiter check (success criterion 5) uses a debug pre-limiter gain variable in `main.scd` (e.g. `~preGain`). The user raises it, re-evaluates, and watches peaks stay at the ceiling. No separate automated limiter test is required.
- **D-18:** The user runs `main.scd` from the SuperCollider IDE for normal playing. A terminal script runs a headless smoke test by calling `/Applications/SuperCollider.app/Contents/MacOS/sclang` directly, since sclang is not on PATH. Use `QT_QPA_PLATFORM=offscreen` per the stack notes.

#### OSC contract & send policy (LINK-01)
- **D-19:** Addresses are namespaced. Phase 1 uses `/pp/bpm <float>`. Later phases follow the same scheme (`/pp/epic`, `/pp/play`, `/pp/volume`). — **Reversibility:** costly — the address names form the contract between `main.scd` OSCdefs and the Python client, and later phases add handlers against this scheme.
- **D-20:** The slider sends **only on release** (one message per drag), not continuously during the drag. The GUI number still updates live while dragging. This satisfies LINK-01: no flooding, and the final value always arrives.
- **D-21:** Nudge buttons and held arrow keys are debounced. The GUI value updates immediately, and a single `/pp/bpm` goes out after ~150 ms with no further changes. The entry sends once on apply (D-10).
- **D-22:** Host and port live as constants in a `config.py` (`127.0.0.1:57120`). The window shows a small status line, e.g. "Sending to 127.0.0.1:57120", so it can be checked against the port `main.scd` posts (ENG-04).
- **D-23:** On launch, the GUI sends its current BPM (120) once, because the GUI is the source of truth for state.
- **D-24:** The Python side is send-only in Phase 1. The receive path and heartbeat belong to Phase 4.

### Claude's Discretion
- Exact synth design for the kick, hat and bass (timbre, envelopes), within D-13 and the requirement that every enveloped synth uses `doneAction: 2`.
- Hat pattern detail (offbeat open hat vs 8th/16th closed hats).
- Internal file split of the SC code and Python code. The research layout in ARCHITECTURE.md is a guide, not a mandate, and the skeleton may keep fewer files.
- Widget styling and exact layout within the compact window.
- Unit test scope for pure Python logic (clamping, entry parsing, debounce), following the pytest + mocked-socket pattern from the stack notes.

### Deferred Ideas (OUT OF SCOPE)
None. The discussion stayed within phase scope. (Live tempo tracking during a slider drag was considered and rejected in favor of release-only sends, so no follow-up is needed.)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ENG-02 | Master output never clips — a limiter on the master bus holds peaks even at maximum EPIC and volume | Pattern 3 (master limiter, −1 dBFS ceiling via `Limiter.ar`) + Pitfall 4; validated manually per D-17 (`~preGain` debug hook) |
| ENG-04 | User starts the engine from a single sclang entry file, which waits for server boot and posts the OSC port it is listening on | Pattern 1 (`s.waitForBoot` boot gate + `NetAddr.langPort.postln`) + Pattern 8 (headless smoke test per D-18) |
| TEMPO-03 | BPM values outside 60–180 are clamped to that range by the engine | Pattern 2 (`msg[1].asFloat.clip(60, 180)` inside the quantized-apply `OSCdef`); verified independently of the GUI per D-08 via `send_raw_bpm.py` (Wave 0 gap) |
| GUI-01 | User can set BPM via a slider, a numeric entry field, and +/- nudge buttons, all kept in sync | Pattern 4 (release-only slider + debounced nudge) binds all three to one `tk.IntVar`; Architectural Responsibility Map entry for GUI-01 |
| GUI-04 | The Tkinter app launches on macOS with a working Tcl/Tk 8.6; on an incompatible Tk it shows a clear warning instead of failing silently | Pattern 5 (`tkinter.TkVersion` check run before any `Tk()` widget); Standard Stack + Environment Availability confirm the actual installed pairing is Tk 9.0.3, which D-03 already accounts for |
| LINK-01 | Every GUI control change reaches the engine over OSC in real time; rapid slider drags are throttled/coalesced so they don't flood the engine | Pattern 4 (release-only send + `after(150, ...)` debounce) + Pitfall 5 (slider-spam prevention) |
</phase_requirements>

## Summary

Phase 1 is the walking skeleton: one `main.scd` that boots the server, posts its OSC language port, and autostarts a four-on-the-floor kick/hat/bassline loop on a dedicated `TempoClock` routed through a master `Limiter.ar`; and one Tkinter app (run from a project-local `.venv`) whose slider/entry/nudge controls stay in sync, clamp to 60–180, and send a throttled `/pp/bpm <float>` over OSC to port 57120. Every risky mechanic for this phase is a known, well-documented SuperCollider/Tkinter/python-osc idiom — boot-gated `OSCdef`s via `s.waitForBoot`, a `Limiter.ar` safety net on the master bus, `doneAction: 2` on every enveloped synth, release-only `<ButtonRelease-1>` slider sends plus `after()`-based debounce for nudges/arrows, and `tkinter.TkVersion` as the compatibility gate. None of this requires novel design — the existing project-level research (`.planning/research/{STACK,ARCHITECTURE,PITFALLS}.md`) already covers these patterns in general; this document narrows them to Phase 1's exact scope and fills in the one mechanic those documents don't cover: **instant-but-beat-quantized** tempo application (no glide yet — that's Phase 2's `TempoClock` ramp routine).

The environment for this phase was independently re-verified in this session and matches `01-CONTEXT.md` exactly: SuperCollider 3.14.1 at `/Applications/SuperCollider.app/Contents/MacOS/sclang` (confirmed via `sclang -v`, not on `PATH`), and Homebrew `python3.13` (3.13.12) pairing with Tcl/Tk **9.0.3** (confirmed by actually instantiating a `tkinter.Tk()` window, not just importing the module) — `python3` (3.14) and `python3.12` both lack `_tkinter` on this machine. This phase's GUI-04 compatibility check must therefore accept Tk 9.x, not gate on "8.6 only" as the stale project-level `STACK.md` recommends — `01-CONTEXT.md` D-02/D-03 already supersede that, and this research carries the correction forward.

**Primary recommendation:** Build `main.scd` as boot-gated OSCdefs writing into a tiny set of top-level vars (`~bpm`, `~clock`), apply BPM changes with `clock.schedAbs(clock.nextTimeOnGrid(1), {...})` (next-beat quantization, no ramp), and put `Limiter.ar(mix, 0.891251, 0.01)` (−1 dBFS ≈ 0.891251 linear) as the last stage before `Out.ar`. On the Python side, bind the `Scale` widget's live value display to `command=`, send OSC only from `<ButtonRelease-1>`, and debounce nudge/arrow-key sends with `root.after(150, send)` cancel-and-reschedule — both are the standard, documented way to satisfy LINK-01 without hand-rolling a threading-based rate limiter.

## Project Constraints (from CLAUDE.md)

Directives extracted from `./.claude/CLAUDE.md`, treated with the same authority as locked CONTEXT.md decisions:

- **Platform/engine:** macOS, same machine running Zwift; SuperCollider is the fixed audio engine (already installed); Python + Tkinter is the fixed control app. Do not substitute either.
- **Minimal dependencies:** Only non-stdlib Python dependency allowed is `python-osc`. No PyQt/Kivy, no `osc4py3`/`pyliblo`/raw-socket OSC, no SuperCollider quarks.
- **Lifecycle:** The Python app must never launch, supervise, or shut down `sclang`/`scsynth` — it only opens a `SimpleUDPClient` and sends. SC is started separately by the user (confirmed consistent with D-18/D-24).
- **Protocol/port:** OSC over UDP, localhost only. Send to sclang's **language port** (57120 default), never scsynth's server port (57110) — `OSCdef`s for `/pp/*` paths live in sclang, not the server.
- **Tk provisioning:** Never let Homebrew's bare `tcl-tk` formula collide with a mismatched Python build; CLAUDE.md's own "What NOT to Use" table is superseded for *this* project by `01-CONTEXT.md` D-02 (matched `python3.13` + Tk 9.0.3 pairing verified working, not a mismatch) — the underlying principle (avoid version *mismatch*) still holds and is what GUI-04's check enforces.
- **Every enveloped synth uses `doneAction: 2`** — stated identically in both CLAUDE.md and `01-CONTEXT.md`'s Claude's Discretion section; non-negotiable for all SynthDefs in this phase.
- **Testing conventions:** Python side uses `pytest` + `unittest.mock.patch("socket.socket")` for OSC client tests (matches python-osc's own test suite pattern); pure logic (clamping, debounce) tested without mocking. SC side uses a headless `sclang -D smoke_test.scd` script with `QT_QPA_PLATFORM=offscreen`, treated as a compile-and-boot smoke test, not a musical-correctness test.
- **No packaging step:** Running `python3 python_app/main.py` (or `./run.sh`) from an activated venv is sufficient — no PyInstaller/py2app needed.

## Architectural Responsibility Map

This is a two-process desktop app, not a web app — "tiers" below map to the two OS processes plus the OS-level Tk/Tcl layer the GUI process depends on. There is no Browser/CDN/Database tier in this project.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| BPM slider/entry/nudge sync (GUI-01) | Client (Tkinter GUI process) | — | All three widgets read/write one in-process Python value; no engine round-trip needed to stay in sync |
| OSC send throttling/coalescing (LINK-01) | Client (Python OSC layer) | Engine (idempotent handler) | The flood-prevention burden is on the sender (debounce/release-only); the receiver should still tolerate occasional redundant messages cheaply |
| BPM clamp 60–180 (TEMPO-03) | Engine (sclang `OSCdef` handler) | Client (GUI widget bounds, for UX only) | TEMPO-03 explicitly requires engine-side clamping regardless of what the GUI sends — verified by sending raw out-of-range OSC bypassing the GUI (D-08) |
| Server boot gating + port announce (ENG-04) | Engine (`main.scd` entry file) | — | Only the engine process knows when `s.boot` has actually completed; Python has no visibility into SC's boot state |
| Beat loop playback (kick/hat/bass) | Engine | — | Audio synthesis and scheduling live entirely in sclang/scsynth |
| Master limiter / clip protection (ENG-02) | Engine (master audio bus) | — | Audio-domain safety net; nothing in Python can protect against SC-side clipping |
| Tk compatibility check (GUI-04) | Client (Python, pre-GUI-construction) | OS (Tcl/Tk runtime) | Must run before any `Tk()` widget is constructed, since a broken `_tkinter` import or old `TkVersion` means the GUI itself may not be buildable |
| Instant-but-quantized tempo apply (supports TEMPO-03 / D-14) | Engine (`TempoClock` + `schedAbs`) | — | Beat-boundary scheduling is a clock-internal mechanic; Python only ever sends the target value |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SuperCollider | 3.14.1 | Audio engine (`scsynth`) + control language (`sclang`) | Already installed at `/Applications/SuperCollider.app`; `sclang -v` confirms `3.14.1 (Built from tag 'Version-3.14.1')` `[VERIFIED: /Applications/SuperCollider.app/Contents/MacOS/sclang -v, this session]`. `TempoClock`/`OSCdef`/`Limiter` APIs used here are stable across the 3.1x line `[CITED: doc.sccode.org]`. |
| Python | 3.13.12 (Homebrew) | Tkinter GUI + OSC client process | `[VERIFIED: /opt/homebrew/bin/python3.13 --version, this session]`. This is the **only** interpreter on this Mac with a working `_tkinter` (`python3`/3.14 and `python3.12` both lack it, per `01-CONTEXT.md` D-02, consistent with this session's `which python3.13` + successful `tkinter.Tk()` construction). |
| Tcl/Tk | 9.0.3 (Homebrew, paired with python3.13) | GUI toolkit native backend | `[VERIFIED: python3.13 -c "import tkinter; tkinter.Tcl().eval('info patchlevel')" → 9.0.3, this session]`. This supersedes the stale project-level `STACK.md` guidance that only Tcl/Tk 8.6 works — on **this** machine Tk 9.0.3 is matched to the interpreter (not a mismatched Homebrew-9.0-under-an-8.6-built-Python situation the old guidance warned about) and a real `Tk()` window was constructed successfully in this session, not just imported. |
| python-osc | 1.10.2 | `pythonosc.udp_client.SimpleUDPClient` — send `/pp/bpm` | `[VERIFIED: PyPI JSON API https://pypi.org/pypi/python-osc/json, this session — info.version=1.10.2, info.requires_python=">=3.10"]`. See Package Legitimacy Audit below — the automated gate flagged this SUS on incomplete signals; independently falsified. |
| Tkinter | stdlib, paired with Tcl/Tk 9.0.3 | GUI toolkit for the control app | Zero extra pip dependency; already the chosen GUI per `CLAUDE.md`. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| pytest | 8.x (dev-only) | Unit tests for BPM clamping, entry-field parsing, debounce logic | Phase 1's pure-Python logic (clamp, parse, debounce) per `01-CONTEXT.md`'s "Claude's Discretion" note — mock-socket pattern from `pythonosc/test/test_udp_client.py` for anything that touches `SimpleUDPClient` |

### Alternatives Considered

No new alternatives beyond what `.planning/research/STACK.md` already documents (pyliblo3/osc4py3 for OSC, PyQt6/Kivy for GUI) — none apply differently for this phase; see that file for the full table. `01-CONTEXT.md` D-02 is the one material delta: the global stack research's "must be Tcl/Tk 8.6" constraint is **not** a hard requirement on this machine — it was a mismatch warning (8.6-built-Python + 9.0-Homebrew-Tcl/Tk), not a blanket "9.x never works" claim, and D-03 already encodes the corrected check (`TkVersion >= 8.6`, 8.6 and 9.x both pass).

**Installation:**
```bash
# Python side — from repo root
python3.13 -m venv .venv
source .venv/bin/activate
pip install python-osc==1.10.2

# Dev-only
pip install pytest
```

**Version verification performed this session:**
- `pip index versions python-osc` → latest visible via pip's index was 1.8.3 (pip's own resolver cache/mirror lag); the PyPI JSON API (authoritative registry source) returned the true latest: **1.10.2**, `requires_python >= 3.10` `[VERIFIED: pypi.org/pypi/python-osc/json]`. Pin to 1.10.2 in `requirements.txt`, not whatever a local `pip index` happens to resolve.
- `sclang -v` → `3.14.1` `[VERIFIED, this session]`.
- `python3.13 --version` → `3.13.12` `[VERIFIED, this session]`.

## Package Legitimacy Audit

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| python-osc | PyPI | 12+ yrs (first release 2013-07-27) | 86,447/month (pypistats.org `recent_downloads.last_month`) | `github.com/attwad/python-osc` (declared in PyPI `project_urls.Repository`) | Automated gate: **SUS** (`unknown-downloads`, `no-repository`) — independently refuted | **Approved** |

**Independent falsification of the automated SUS verdict:** `gsd_run query package-legitimacy check --ecosystem pypi python-osc` returned `SUS` with reasons `unknown-downloads` and `no-repository`. Both signals were checked directly against authoritative sources this session and found false:
- `curl https://pypi.org/pypi/python-osc/json` → `info.project_urls = {"Repository": "https://github.com/attwad/python-osc"}`, `info.author = "attwad"`, 31 releases, first upload `2013-07-27T02:23:23` `[VERIFIED: PyPI JSON API, this session]`.
- `curl https://pypistats.org/api/packages/python-osc/recent` → `{"last_day":4423,"last_month":86447,"last_week":28697}` `[VERIFIED: pypistats.org API, this session]`.

Per the provenance protocol, a probe that succeeds refutes the SLOP/SUS claim rather than downgrading it — the gate's signal extraction appears to have missed `project_urls` and the download-stats mirror it queried, not that the package is actually new/unsourced. No `checkpoint:human-verify` is required before installing `python-osc`.

**Packages removed due to `[SLOP]` verdict:** none.
**Packages flagged as suspicious `[SUS]` after independent verification:** none (python-osc cleared above).

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────── Python process (Tkinter, main thread only) ───────────────────────────┐
│                                                                                                      │
│   Tk compatibility check (runs BEFORE any Tk() widget is built)                                    │
│     import tkinter; TkVersion >= 8.6? ──fail──▶ print fix instructions to terminal, exit(1)        │
│     │ pass                                                                                          │
│     ▼                                                                                               │
│   Window: Slider ◄──sync──► Entry field ◄──sync──► [-5 -1 [value] +1 +5] nudge buttons              │
│     │ drag (live label update only, no send)        │ Enter/focus-out: validate, clamp 60–180      │
│     │ <ButtonRelease-1>: send final value             │ Up/Down ±1, Shift+Up/Down ±5 (debounced)    │
│     ▼                                                 ▼                                             │
│   debounce/coalesce (after(150ms) cancel+reschedule, or release-only for the slider)                │
│     ▼                                                                                               │
│   SimpleUDPClient.send_message("/pp/bpm", float(value))  ── non-blocking sendto, main thread safe   │
└──────────────────────────────────────────┬──────────────────────────────────────────────────────────┘
                                             │ UDP, localhost, port 57120 (sclang language port)
┌────────────────────────────────────────── ▼ ──────────────────────────────────────────────────────┐
│                           SuperCollider process (sclang + scsynth), main.scd                        │
│                                                                                                       │
│   s.waitForBoot({ ... })  ── gates everything below until the server is actually ready              │
│     ├─▶ "OSC port: ".post; NetAddr.langPort.postln;  (ENG-04: posts the listening port)             │
│     ├─▶ Group/Bus topology: instrument Group → master Group (limiter)                               │
│     ├─▶ SynthDefs: kick, hat, bass (each EnvGen.kr(env, doneAction: 2))                              │
│     ├─▶ ~clock = TempoClock.new(120/60); Pbindef(\drums,...).play(~clock); (ENG-02/D-15: autostart)  │
│     └─▶ OSCdef(\pp_bpm, { |msg|                                                                      │
│             var bpm = msg[1].clip(60, 180);                      (TEMPO-03: engine-side clamp)      │
│             ~clock.schedAbs(~clock.nextTimeOnGrid(1), {          (D-14: quantize to next beat,       │
│                 ~clock.tempo_(bpm/60); nil;                        no glide — instant at that beat)  │
│             });                                                                                      │
│         }, '/pp/bpm');                                                                              │
│                                                                                                       │
│   Master bus: mix ── Limiter.ar(mix, 0.891251, 0.01) ── Out.ar(0, limited)  (ENG-02: −1 dBFS ceiling)│
│   Debug: ~preGain var raises pre-limiter gain for the hot-signal manual test (D-17)                 │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

`01-CONTEXT.md`'s "Claude's Discretion" explicitly allows fewer files than the project-level `ARCHITECTURE.md` layout — this is the Phase 1-right-sized version of it:

```
supercollider/
└── main.scd                 # Everything: boot gate, port post, SynthDefs (kick/hat/bass),
                              # groups/limiter, TempoClock + Pbindef loop, OSCdef(\pp_bpm, ...)
                              # — splitting into core/synths/patterns/osc/ (per ARCHITECTURE.md)
                              # is optional polish for this phase, not required.

python_app/
├── run.sh                   # Creates .venv from python3.13 if missing, pip installs
│                             # requirements.txt, launches main.py with the venv interpreter (D-05)
├── requirements.txt         # python-osc==1.10.2
├── config.py                # HOST = "127.0.0.1"; PORT = 57120; DEFAULT_BPM = 120
├── tkcheck.py                # Startup compatibility check (GUI-04) — runs before importing
│                             # anything that constructs a Tk() widget
├── main.py                  # Entry point: runs tkcheck, builds OscClient + View, mainloop
├── osc_client.py            # Thin wrapper: send_bpm(float) -> SimpleUDPClient.send_message
├── view.py                  # Slider/entry/nudge widgets, debounce/release-only send wiring,
│                             # "On top" checkbox, status line showing target host:port
└── tests/
    ├── test_clamp.py        # Pure-logic: BPM clamp/validate (no mocking needed)
    └── test_osc_client.py   # mock-socket pattern (patch socket.socket) per STACK.md Testing Approach
```

### Pattern 1: Boot-gated OSCdef registration

**What:** Nothing in the patch — OSCdefs, pattern `.play`, port-posting — executes until `s.boot` has actually completed.
**When to use:** Always, for every SC entry file; this is ENG-04's literal requirement ("waits for the server to boot").
**Example:**
```supercollider
// Source: doc.sccode.org/Guides/OSC_communication.html, doc.sccode.org/Classes/TempoClock.html [CITED]
s.waitForBoot({
    ("OSC port: " ++ NetAddr.langPort).postln;   // ENG-04: posts the listening port
    // ... SynthDefs, groups, OSCdefs, pattern .play all go inside this block ...
});
```

### Pattern 2: Instant-but-quantized tempo apply (Phase 1 only — no glide)

**What:** D-14 requires the new BPM to take effect "instantly, quantized to the next beat boundary" — distinct from Phase 2's multi-beat ramp (`ARCHITECTURE.md` Pattern 3). Use `TempoClock.schedAbs` + `TempoClock.nextTimeOnGrid` to defer the `.tempo_` write to the next beat, not the current (possibly mid-beat) instant.
**When to use:** Phase 1's `/pp/bpm` handler only. Do **not** reuse this for Phase 2 — that phase replaces this with a ramp routine per `ARCHITECTURE.md` Pattern 3, which supersedes this snapping behavior.
**Example:**
```supercollider
// nextTimeOnGrid(1) == "the next whole beat" [CITED: doc.sccode.org/Classes/TempoClock.html]
// schedAbs schedules a function at that absolute beat time [CITED: doc.sccode.org/Classes/TempoClock.html]
OSCdef(\pp_bpm, { |msg|
    var bpm = msg[1].asFloat.clip(60, 180);   // TEMPO-03: engine clamps independently of GUI
    ~bpm = bpm;
    ~clock.schedAbs(~clock.nextTimeOnGrid(1), {
        ~clock.tempo_(bpm / 60);
        nil;  // returning nil = one-shot, don't reschedule
    });
}, '/pp/bpm');
```
**Note:** `msg[1].asFloat.clip(60, 180)` satisfies D-09 (engine accepts and clamps floats even though the GUI sends whole numbers) and TEMPO-03's independent-of-GUI clamp requirement (D-08) in one line.

### Pattern 3: Master limiter with debug pre-gain hook

**What:** Final-stage `Limiter.ar` at a −1 dBFS ceiling (≈0.891251 linear, `10^(-1/20)`), with a debug `~preGain` var the user can raise to deliberately drive the signal hot for the manual listening check (D-17 — success criterion 5).
**Example:**
```supercollider
// Limiter.ar(in, level: 1.0, dur: 0.01) [CITED: doc.sccode.org/Classes/Limiter.html]
~preGain = 1.0;  // debug: raise this (e.g. to 4.0), re-evaluate, confirm output still holds at ceiling
SynthDef(\master, { |in = 0, out = 0|
    var mix = In.ar(in, 2) * ~preGain;
    Out.ar(out, Limiter.ar(mix, 0.891251, 0.01));  // ENG-02: −1 dBFS ceiling, no clipping
}).add;
```

### Pattern 4: Release-only slider send + debounced nudge/arrow sends

**What:** Tkinter's `Scale` `command=` callback fires continuously during a drag; D-20 requires sending only on release. Bind the **live visual update** to `command=` (cheap, local, no OSC) and the **actual send** to `<ButtonRelease-1>`. For nudge buttons and held arrow keys (D-21), update the GUI value immediately but debounce the OSC send with `after(150, ...)` cancel-and-reschedule so only the final value after ~150ms of inactivity goes out.
**Example:**
```python
# Source: pattern confirmed via community docs (tkinter.Scale command fires per-drag-tick;
# <ButtonRelease-1>/<B1-Motion> binding is the standard way to gate sends to release only) [CITED: forums.raspberrypi.com, wiki.tcl-lang.org/page/tkinter.Scale]
import tkinter as tk
from osc_client import OscClient

class BpmControl:
    def __init__(self, root, client: OscClient, initial=120):
        self.client = client
        self.value = tk.IntVar(value=initial)
        self._debounce_id = None

        self.scale = tk.Scale(root, from_=60, to=180, orient="horizontal",
                               variable=self.value)  # live display only, no command= send
        self.scale.bind("<ButtonRelease-1>", self._send_now)

    def _send_now(self, _event=None):
        self.client.send_bpm(float(self.value.get()))

    def nudge(self, delta, root):
        new_value = max(60, min(180, self.value.get() + delta))
        self.value.set(new_value)  # GUI updates immediately (D-21)
        if self._debounce_id is not None:
            root.after_cancel(self._debounce_id)
        self._debounce_id = root.after(150, self._send_now)  # one send ~150ms after last nudge
```

### Pattern 5: Tk compatibility check (GUI-04), run before any widget is built

**What:** GUI-04 requires a clear terminal warning (not a GUI dialog, since Tk may not even be loadable) on an incompatible Tk, instead of a silent/cryptic failure. D-03: "incompatible" = `_tkinter` import fails OR `TkVersion < 8.6`; 8.6 and 9.x both pass.
**Example:**
```python
# Source: tkinter.TkVersion is the documented compatibility signal [CITED: docs.python.org/3/library/tkinter.html]
import sys

def check_tk_compatible():
    try:
        import tkinter
    except ImportError as e:
        print(f"ERROR: tkinter/_tkinter could not be imported ({e}).\n"
              f"Fix: run via ./run.sh, which builds .venv from Homebrew python3.13 "
              f"(the only interpreter on this Mac with working Tkinter).", file=sys.stderr)
        sys.exit(1)
    if tkinter.TkVersion < 8.6:
        print(f"ERROR: Tcl/Tk {tkinter.TkVersion} is too old (need >= 8.6).\n"
              f"Fix: run via ./run.sh / use the .venv built from python3.13.", file=sys.stderr)
        sys.exit(1)
    return tkinter

# main.py
tkinter = check_tk_compatible()  # exits non-zero BEFORE any Tk() widget is constructed
root = tkinter.Tk()
```

### Pattern 6: "On top" toggle (D-12)

```python
# Source: attributes('-topmost', bool) works on both Windows and macOS [CITED: tkdocs.com/tutorial/windows.html]
on_top = tk.BooleanVar(value=False)
def toggle_on_top():
    root.attributes("-topmost", on_top.get())
tk.Checkbutton(root, text="On top", variable=on_top, command=toggle_on_top).pack()
```

### Pattern 7: `run.sh` launch wrapper (D-05)

```bash
#!/usr/bin/env bash
# Source: standard venv bootstrap pattern [CITED: docs.python.org/3/library/venv.html]
set -euo pipefail
cd "$(dirname "$0")"
PYTHON=python3.13
if [ ! -d .venv ]; then
    "$PYTHON" -m venv .venv
    .venv/bin/pip install -r requirements.txt
fi
exec .venv/bin/python main.py
```

### Pattern 8: Headless sclang smoke test (D-18)

```bash
#!/usr/bin/env bash
# sclang is not on PATH; invoke the binary directly. QT_QPA_PLATFORM=offscreen avoids
# requiring a GUI/X server for a headless run. [CITED: scsynth.org/t/scsynth-without-gui/2040,
# github.com/supercollider/supercollider/wiki/Unit-Testing-Guide]
SCLANG=/Applications/SuperCollider.app/Contents/MacOS/sclang
QT_QPA_PLATFORM=offscreen "$SCLANG" -D supercollider/smoke_test.scd
echo "exit code: $?"
```

### Anti-Patterns to Avoid

- **Setting `.tempo_` directly without quantization:** causes an audible jolt mid-beat, not a clean apply at the next beat boundary — violates D-14. Always route through `schedAbs(nextTimeOnGrid(1), ...)` even in Phase 1's "instant" mode.
- **Sending `/pp/bpm` on every `Scale` `command=` tick:** floods the engine on every pixel of drag, violating LINK-01. `command=` is for the live label only; the actual send is `<ButtonRelease-1>`-gated.
- **Sending control OSC to port 57110 (scsynth) instead of 57120 (sclang):** `OSCdef`s registered in `main.scd` run inside **sclang**, which listens on the language port, not the server port `[CITED: .planning/research/STACK.md "What NOT to Use"]`. Hardcoding the wrong port produces silent message loss — no error on either side.
- **Missing `doneAction: 2` on the kick/hat/bass SynthDefs:** even in a short Phase 1 smoke run this doesn't crash anything, but it establishes a leak pattern that compounds across Phase 2–4's longer soak tests — bake it in from this phase's SynthDefs since D-13 explicitly calls for them to be "reusable as the starting point for Phase 2's groove."
- **Gating the Tk compatibility check behind a `try/except` that still proceeds to build a `Tk()` window on failure:** GUI-04 requires exiting non-zero with a terminal message, not a degraded GUI attempt.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| OSC wire-format encoding/sending | A custom UDP packet builder for OSC addresses/args | `python-osc`'s `SimpleUDPClient.send_message(address, value)` | Pure-Python, zero deps, non-blocking `sendto`, exactly matches the project's "minimal dependencies" constraint |
| Beat-boundary scheduling | A custom timer thread that polls wall-clock time and guesses the next beat | `TempoClock.schedAbs` + `TempoClock.nextTimeOnGrid` | These exist specifically to answer "when is the next beat/bar," already handle the clock's logical-vs-physical time mapping correctly |
| Master-bus clip protection | A hand-rolled soft-clip/`tanh` saturator tuned by ear | `Limiter.ar(signal, 0.891251, 0.01)` | `Limiter` uses lookahead so it clamps peaks without the harsh distortion a naive clip produces; a hand-rolled saturator risks being either too aggressive (constant coloration) or too weak (still clips) |
| Slider-drag rate limiting | A background thread with a sleep loop sampling the slider value | Tkinter's own `<ButtonRelease-1>` binding (slider) + `root.after(ms, fn)` cancel-and-reschedule (nudge/arrow keys) | Both are single-threaded, main-thread-safe, and are the documented idioms for exactly this UI pattern — no threading needed at all for Phase 1's send-only design |
| Tk version/health check | Shelling out to `tclsh`/parsing `wish` version strings | `tkinter.TkVersion` (float) checked in Python before any `Tk()` call | It's the value the `tkinter` module itself derives from the loaded Tcl/Tk library — no subprocess needed, and it fails cleanly with `ImportError` first if `_tkinter` itself is missing |

**Key insight:** Every mechanic this phase needs (scheduling, limiting, debouncing, version-checking) already has a one-line-or-few-line stdlib/class-library answer. The only place a custom implementation is appropriate is the musical content of the loop itself (kick/hat/bass SynthDef design) — explicitly left to Claude's discretion in `01-CONTEXT.md`.

## Common Pitfalls

> Condensed from `.planning/research/PITFALLS.md` (project-level) to the pitfalls that are live risks **in this phase's exact scope**. Pitfalls 2 (ramp), 7 (receive-thread safety), 9 (heartbeat), and 10 (harmonic coherence) belong to later phases per that document's own "Phase to address" column and `01-CONTEXT.md`'s "Not in this phase" list — they are not re-litigated here.

### Pitfall 1: Hardcoding OSC port 57120 with no visibility into the actual port

**What goes wrong:** If a stray `sclang` process is already bound to 57120, a fresh boot silently falls back to a different port; the GUI's sends then go into the void with zero error (UDP has no delivery feedback).
**Why it happens:** Dev/test is usually done with a single, freshly-booted SC instance where the port is always 57120 — the drift case only shows up after a crash or a second instance is left running.
**How to avoid:** `main.scd` must `.postln` `NetAddr.langPort` on boot (ENG-04 requirement, not just a nice-to-have); the Python status line (D-22) must show the configured target port so a human can diff it against the SC post window.
**Warning signs:** GUI slider changes produce zero audible or logged effect; multiple `sclang`/SuperCollider processes visible in Activity Monitor.

### Pitfall 2: Server boot timing — OSCdefs/pattern-start executed before `s.boot` completes

**What goes wrong:** Code outside `s.waitForBoot{}` can run before the server is ready, silently dropping the first few messages or failing to register handlers at all.
**Why it happens:** On an idle dev machine the server boots in well under a second, masking the race; it becomes visible only on a colder boot or a loaded machine.
**How to avoid:** Everything in Pattern 1 above — the whole patch body lives inside `s.waitForBoot({...})`.
**Warning signs:** `main.scd` appears to run without error but the loop never starts, or the posted port line never appears.

### Pitfall 3: Missing `doneAction: 2` on enveloped synths

**What goes wrong:** Kick/hat/bass synths that don't free themselves on envelope completion accumulate as dead nodes; invisible in a short test, compounding over Phase 4's 60-minute soak.
**Why it happens:** A leaked node is inaudible by itself; only a long run or an explicit `s.numSynths` check surfaces it.
**How to avoid:** Every `SynthDef` in this phase uses `EnvGen.kr(env, doneAction: 2)` — this is explicitly required by `01-CONTEXT.md`'s Claude's Discretion note and sets the pattern Phase 2's groove reuses.
**Warning signs:** `s.numSynths` trends upward instead of staying flat during a short manual test.

### Pitfall 4: No limiter / unprotected master bus

**What goes wrong:** Even a simple kick+hat+bass loop can produce unexpected peaks when the debug `~preGain` is raised for the D-17 hot-signal test; without a limiter, that's audible clipping instead of a controlled ceiling.
**Why it happens:** Easy to skip "just for a quick test loop" and forget to add before any multi-voice combination is tried.
**How to avoid:** Pattern 3 above — the limiter is wired in from the first version of `main.scd`, not added after the loop "sounds right."
**Warning signs:** Harsh crackle specifically when `~preGain` is raised; master meter pinning instead of holding at the ceiling.

### Pitfall 5: Tkinter slider spams OSC on every drag tick

**What goes wrong:** `command=` on a `Scale` fires dozens of times per second during a fast drag; sending on every tick floods the OSC handler and can cause competing quantized-apply schedules.
**Why it happens:** `command=send_osc` is the simplest possible wiring and looks correct in a slow manual test.
**How to avoid:** Pattern 4 above — `command=` only updates the live label; `<ButtonRelease-1>` is the only OSC trigger for the slider. Nudge/arrow-key paths get the separate `after(150, ...)` debounce since they have no natural "release" event.
**Warning signs:** SC post window shows far more `/pp/bpm` messages than drag gestures performed; audible stutter during a fast drag (not applicable yet since Phase 1 has no ramp, but redundant quantized-apply reschedules are still wasted work).

### Pitfall 6: macOS Tcl/Tk version mismatch (the one this phase must actively check for)

**What goes wrong:** A Python built against one Tcl/Tk ABI paired with a different one at runtime causes `_tkinter.TclError` or visibly broken widget rendering (fonts, theming) without a clean crash.
**Why it happens:** `pip install` can't fail on a missing `_tkinter` (it's stdlib, not a pip package) — the first signal is a runtime error or just-wrong-looking UI.
**How to avoid:** Pattern 5 above (`tkinter.TkVersion` check) — but note `01-CONTEXT.md` D-02/D-03 already correct the specific threshold for this project: Tk 8.6 **and** 9.x both pass; the risk is a *mismatched* pairing, not "9.x is categorically broken." This session independently reconfirmed a matched `python3.13` + Tk 9.0.3 pairing actually renders (a real `Tk()` window was constructed, not just imported).
**Warning signs:** `ModuleNotFoundError: No module named '_tkinter'`; GUI opens but looks visually wrong.

## Code Examples

See the eight numbered patterns under **Architecture Patterns** above — they are the verified, phase-specific code examples for this document (boot gate, quantized tempo apply, limiter, release-only slider, debounce, Tk check, on-top toggle, run.sh, headless smoke test). No separate restatement needed here.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| "Tkinter on macOS requires Tcl/Tk 8.6, full stop" (project-level `STACK.md` guidance, based on CPython #124111 reporting incomplete Tk 9 support as of late 2025) | On *this* machine, Homebrew `python3.13` is matched to Homebrew Tcl/Tk **9.0.3** and it works — confirmed by actually constructing a `Tk()` window this session, not just importing the module | Discovered during `01-discuss-phase` (D-02) and reconfirmed in this research session | GUI-04's compatibility gate must accept `TkVersion >= 8.6` (both 8.6 and 9.x), not hardcode "must be exactly 8.6" — the real risk was always a cross-version *mismatch* (8.6-built Python + 9.0 Tcl/Tk), not 9.x itself being broken |
| `pip index versions <pkg>` as the source of truth for "latest version" | The PyPI JSON API (`pypi.org/pypi/<pkg>/json`) is more current — `pip index` returned 1.8.3 as "latest" for python-osc in this session while the registry's actual latest is 1.10.2 | Observed this session | Always cross-check a package's version against the PyPI JSON API directly, not just a local `pip`/mirror cache, before pinning in `requirements.txt` |

**Deprecated/outdated:** None specific to this phase beyond the Tk-version note above.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `tkinter.Scale`'s `command=` callback firing rate during a fast drag is "dozens of times per second" (exact figure, not independently benchmarked on this machine) | Common Pitfalls #5 / Pattern 4 | Low — the mitigation (release-only send) is correct regardless of the exact tick rate; only the stated frequency is unverified, not the design decision it informs |
| A2 | `Limiter.ar`'s `dur` parameter default (0.01s / ~10ms lookahead) is acceptable for this phase's loop without audible pumping at the −1 dBFS ceiling | Pattern 3 | Low-Medium — if 0.01s produces audible lookahead artifacts on the bass/kick combination, the fix is a one-parameter tweak (`dur` arg), not a redesign; D-17's manual listening test is designed to catch this |

**Note:** No assumption here concerns package legitimacy, compliance, retention, or security posture — those categories were either verified directly (python-osc) or are not applicable to this phase (see Security Domain below).

## Open Questions

1. **Exact nudge-button value (±1/±5) interaction with the 150ms debounce window when the user clicks rapidly in succession**
   - What we know: D-21 specifies "a single `/pp/bpm` goes out after ~150ms with no further changes" — a cancel-and-reschedule `after()` pattern (Pattern 4) satisfies this.
   - What's unclear: Whether rapid alternating +1/-1 clicks within the window should coalesce to the *net* value (expected, and what the cancel-and-reschedule pattern naturally produces) or whether any intermediate value should ever be visible to the user before the send — not specified in `01-CONTEXT.md`.
   - Recommendation: Treat "net value after 150ms of inactivity" as correct (what Pattern 4 implements); flag to the user only if observed behavior during manual testing feels wrong.

2. **Whether `~clock.nextTimeOnGrid(1)` ever returns the *current* beat (zero-wait) if the OSC message happens to arrive exactly on a beat boundary, causing an apparent "double application" if a second message arrives in the same beat**
   - What we know: `nextTimeOnGrid` is documented to return "the next whole beat" `[CITED: doc.sccode.org/Classes/TempoClock.html]`.
   - What's unclear: Edge-case behavior at exact beat boundaries wasn't tested by executing SC code in this research session (no SC audio session was run).
   - Recommendation: Not a planning blocker — D-14's debounce on the Python side (Pattern 4) means messages won't arrive dense enough in practice for this edge case to matter in Phase 1; worth a one-line comment in the code, not a dedicated task.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| SuperCollider (`sclang`/`scsynth`) | ENG-02, ENG-04, TEMPO-03 | ✓ | 3.14.1 `[VERIFIED, this session]` | — |
| Homebrew `python3.13` | GUI-01, GUI-04, LINK-01 | ✓ | 3.13.12 `[VERIFIED, this session]` | — |
| Tcl/Tk (paired with python3.13) | GUI-04 | ✓ | 9.0.3 `[VERIFIED, this session — real Tk() window constructed]` | — |
| `python3` (Homebrew, 3.14) | — (not used) | ✗ (`_tkinter` missing) | 3.14 | Not needed — `run.sh` pins `python3.13` explicitly (D-05) |
| `python3.12` (Homebrew) | — (not used) | ✗ (`_tkinter` missing) | 3.12 | Not needed — same as above |
| `python-osc` (pip package, not yet installed in a project `.venv`) | LINK-01 | — (no `.venv` exists yet; this phase creates it) | target 1.10.2 | `run.sh` installs it fresh — no fallback needed, no network dependency risk beyond PyPI being reachable |
| pytest (dev-only) | Unit tests (Claude's Discretion) | not yet installed | target 8.x | Tests can be deferred/skipped if pytest install fails; not a phase blocker |

**Missing dependencies with no fallback:** None — every dependency this phase needs is already present on the machine or is installed by `run.sh` as part of the phase's own deliverables.

**Missing dependencies with fallback:** None beyond the pytest note above (non-blocking).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | pytest 8.x (none installed yet — Wave 0 gap) |
| Config file | none — see Wave 0 Gaps |
| Quick run command | `.venv/bin/pytest python_app/tests/ -x -q` |
| Full suite command | `.venv/bin/pytest python_app/tests/ -q` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEMPO-03 | Engine clamps raw OSC `/pp/bpm` values outside 60–180 to that range | manual (raw OSC from a test script, not through the GUI, per D-08) | `python3 python_app/tests/send_raw_bpm.py 300` then listen/observe engine tempo caps at 180 | ❌ Wave 0 — script doesn't exist yet |
| GUI-01 | Slider/entry/nudge buttons stay in sync | unit (pure logic) | `pytest python_app/tests/test_sync.py -x` | ❌ Wave 0 |
| GUI-01 / D-10 | Entry applies on Enter/focus-out; invalid text reverts; out-of-range snaps to 60/180 | unit | `pytest python_app/tests/test_clamp.py -x` | ❌ Wave 0 |
| LINK-01 | Slider sends only on release; nudge/arrow debounced to one send after ~150ms | unit (mock socket) + manual (drag test) | `pytest python_app/tests/test_osc_client.py -x` ; manual: drag slider fast end-to-end, confirm one `/pp/bpm` logged | ❌ Wave 0 |
| GUI-04 | Tk compatibility check exits non-zero with clear message on incompatible Tk | unit (can be tested by monkeypatching `tkinter.TkVersion` or mocking the import) | `pytest python_app/tests/test_tkcheck.py -x` | ❌ Wave 0 |
| ENG-02 | Master limiter holds peaks at ceiling under a deliberately hot `~preGain` | manual (D-17 — no automated limiter test required) | manual: raise `~preGain`, re-evaluate `main.scd`, watch SC meter | n/a — explicitly manual per D-17 |
| ENG-04 | `main.scd` waits for boot, posts OSC port, autostarts loop | manual smoke test (headless sclang) | `QT_QPA_PLATFORM=offscreen /Applications/SuperCollider.app/Contents/MacOS/sclang -D supercollider/smoke_test.scd` | ❌ Wave 0 — `smoke_test.scd` doesn't exist yet |

### Sampling Rate
- **Per task commit:** `.venv/bin/pytest python_app/tests/ -x -q` (quick run)
- **Per wave merge:** `.venv/bin/pytest python_app/tests/ -q` (full suite) + the two manual checks (D-17 limiter, D-18 headless smoke test)
- **Phase gate:** Full suite green + both manual checks performed before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `python_app/tests/test_clamp.py` — covers GUI-01/D-10 (entry parsing, clamp-to-60/180, revert-on-invalid)
- [ ] `python_app/tests/test_sync.py` — covers GUI-01 (slider/entry/nudge stay in sync)
- [ ] `python_app/tests/test_osc_client.py` — covers LINK-01 (release-only send, debounce), mock-socket pattern per `pythonosc/test/test_udp_client.py`
- [ ] `python_app/tests/test_tkcheck.py` — covers GUI-04 (compatibility gate logic)
- [ ] `python_app/tests/send_raw_bpm.py` — manual-test helper script for TEMPO-03 (sends raw out-of-range `/pp/bpm` bypassing the GUI, per D-08)
- [ ] `supercollider/smoke_test.scd` — headless boot/compile sanity check for ENG-04/D-18
- [ ] Framework install: `pip install pytest` inside `.venv` (via `run.sh` dev-extras or a separate `requirements-dev.txt`)

## Security Domain

`security_enforcement` is enabled (`.planning/config.json` → `workflow.security_enforcement: true`, `security_asvs_level: 1`). This is a single-user, localhost-only desktop app with no network exposure beyond loopback UDP and no authentication surface — most ASVS categories are explicitly not applicable, documented below rather than silently omitted.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Single-user local desktop app; no login/identity concept exists or is needed |
| V3 Session Management | No | No sessions; the app is a single long-lived process with in-memory state only |
| V4 Access Control | No | No multi-user/role concept; the only "access" is whoever is at the keyboard on the same Mac |
| V5 Input Validation | **Yes** | Engine-side clamp on every incoming OSC argument (`msg[1].asFloat.clip(60, 180)` — Pattern 2) regardless of what the Python GUI sends, per TEMPO-03 and `.planning/research/PITFALLS.md` "Security Mistakes" table |
| V6 Cryptography | No | Localhost loopback traffic only; no secrets, no stored credentials, no data at rest requiring encryption in this phase |
| V13 API/OSC input handling | **Yes** (project-specific extension of V5) | Bind any OSC listener explicitly to `127.0.0.1`, never `0.0.0.0` — this phase's `OSCdef` is sclang-internal (not a separate bindable socket Python controls), so the binding is inherited from sclang's default language-port binding, not something this phase's code configures |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed/out-of-range OSC argument to `/pp/bpm` (e.g. negative, NaN, absurdly large) crashing the `schedAbs` scheduling or producing an absurd tempo | Tampering / Denial of Service | `.clip(60, 180)` on every incoming value before use, applied in the `OSCdef` handler itself — never trust the sender, even though it's "your own" GUI (per `.planning/research/PITFALLS.md` Security Mistakes table) |
| A stray process (another SC instance, or anything else on the LAN if the listener were ever bound to `0.0.0.0`) sending unsolicited `/pp/bpm` messages | Spoofing | sclang's language-port listener binds to loopback by default on a single-machine setup; this phase introduces no new listening socket on the Python side (send-only, per D-24), so there is no additional attack surface to secure beyond SC's existing default |
| OSC port drift (Pitfall 1) mistaken for a security issue when it is actually a reliability issue | — (not a STRIDE category, included for clarity) | Not a security concern — `NetAddr.langPort` posting and the GUI's status line (D-22) are reliability/debuggability controls, not security controls; noted here only to avoid miscategorizing it during security review |

## Sources

### Primary (HIGH confidence)
- `sclang -v` (this session) — confirmed SuperCollider 3.14.1 at the exact installed path
- `python3.13 --version`, `python3.13 -c "import tkinter; tkinter.Tk()"`, `python3.13 -c "...info patchlevel"` (this session) — confirmed Python 3.13.12 + working Tk 9.0.3
- PyPI JSON API `https://pypi.org/pypi/python-osc/json` (this session) — version 1.10.2, `requires_python>=3.10`, repo URL, author, release history
- pypistats.org API `https://pypistats.org/api/packages/python-osc/recent` (this session) — download counts refuting the automated legitimacy gate's `unknown-downloads` signal
- [Limiter — doc.sccode.org](https://doc.sccode.org/Classes/Limiter.html) — `Limiter.ar(in, level, dur)` signature
- [TempoClock — doc.sccode.org](https://doc.sccode.org/Classes/TempoClock.html) — `schedAbs`, `nextTimeOnGrid` semantics
- [docs.python.org/3/library/tkinter.html](https://docs.python.org/3/library/tkinter.html) — `tkinter.TkVersion` as the compatibility signal

### Secondary (MEDIUM confidence)
- [tkinter.Scale — wiki.tcl-lang.org](https://wiki.tcl-lang.org/page/tkinter.Scale) and [Raspberry Pi Forums thread on Scale ButtonRelease binding](https://forums.raspberrypi.com/viewtopic.php?t=327361) — release-only send pattern
- [tkdocs.com Windows and Dialogs tutorial](https://tkdocs.com/tutorial/windows.html) — `attributes('-topmost', ...)` cross-platform behavior
- `.planning/research/{STACK,ARCHITECTURE,PITFALLS,SUMMARY}.md` (project-level research, dated 2026-10-08, MEDIUM-HIGH per that document's own confidence assessment) — reused for boot-gating, master-bus topology, doneAction, Tkinter thread-safety, and project layout guidance not re-derived in this document

### Tertiary (LOW confidence)
- None used as the basis for any claim in this document — every claim above is either `[VERIFIED]` this session, `[CITED]` to an official doc page, or explicitly logged in the Assumptions Log.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every version pin independently verified this session against the actual installed toolchain or the authoritative registry (PyPI JSON API), not training-data recall
- Architecture: HIGH — all patterns are direct applications of official SuperCollider class docs (`TempoClock`, `Limiter`, `OSCdef`) and documented Tkinter idioms, narrowed from the already-MEDIUM-HIGH project-level `ARCHITECTURE.md`
- Pitfalls: HIGH — condensed from the project-level `PITFALLS.md` (itself MEDIUM-HIGH, grounded in official docs/GitHub issues) to only the subset verified relevant to this phase's exact scope

**Research date:** 2026-10-08
**Valid until:** 2026-11-07 (30 days — stable toolchain; re-verify sooner only if Homebrew pushes another Tcl/Tk major version bump before this phase executes)
