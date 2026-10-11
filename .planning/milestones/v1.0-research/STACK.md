# Stack Research

**Domain:** Real-time generative electronic music engine (SuperCollider) controlled by a Python/Tkinter GUI over OSC
**Researched:** 2026-10-08
**Confidence:** MEDIUM (cross-verified across official docs, GitHub source, PyPI metadata, and multiple independent community threads; no single-source claim treated as authoritative)

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| SuperCollider | 3.14.1 (latest stable, released 2025-11-23) | Audio engine (scsynth) + music-logic language (sclang) | Already installed per project constraint. 3.14.x is the current stable line; universal binary for macOS 11+, legacy x64 build for macOS 10.15+. If the installed copy predates 3.14, no urgent need to upgrade — TempoClock/JITLib/OSCdef APIs used here are stable across the 3.1x line. |
| Python | 3.12 (3.13 acceptable) | Tkinter GUI + OSC client process | 3.12 has the widest third-party compatibility and is what most `python-tk` Homebrew/python.org packaging currently targets cleanly; 3.13 is equally viable (supported until 2029) if you want the newer runtime. Both bundle/pair with Tcl/Tk **8.6** on macOS, which is the version that actually works (see Tkinter gotcha below). Avoid anything below 3.10 — python-osc requires it. |
| python-osc | 1.10.2 (PyPI, `attwad/python-osc`) | Send OSC/UDP messages from Python to sclang | The de facto standard OSC library for Python: pure-Python, zero non-stdlib dependencies, actively maintained, trivially simple `SimpleUDPClient` API. Matches the project's "minimal dependencies" constraint better than any alternative. |
| Tkinter | stdlib (paired with Tcl/Tk 8.6) | GUI toolkit for the control app | Already the user's chosen GUI; ships in the Python standard library, so it is the only UI toolkit here with **zero** extra pip dependency. No reason to introduce PyQt/Kivy/etc. for a few sliders and buttons. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| python-osc | 1.10.2 | `pythonosc.udp_client.SimpleUDPClient` to send `/bpm`, `/epic`, `/transport`, `/volume` | Always — this is the only non-stdlib Python dependency this project needs. |
| pytest | latest 8.x | Test runner for the Python side | Dev-only. Use for unit tests of OSC-message construction, EPIC-preset mapping, and any value-clamping/formatting logic in the GUI layer. |
| (none) | — | SuperCollider side | Do **not** add any quark as a runtime dependency (see "Quarks" section below) — JITLib ships with stock SuperCollider and is sufficient. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `python3 -m venv .venv` | Isolate Python deps | Stdlib — no extra tool needed. `uv` is a fine modern alternative if you already use it elsewhere, but for one dependency (`python-osc`) plain `venv` + `pip` is simpler and has zero learning overhead. |
| `pip` | Install `python-osc` | `pip install python-osc` inside the venv. |
| sclang (headless, `QT_QPA_PLATFORM=offscreen`) | Smoke-test SC code without opening the IDE/GUI | Run `.scd` scripts from a shell script for quick "does it still compile and run" checks — see Testing section. |
| `ruff` (optional) | Lint/format Python | Optional; skip if you want to keep tooling minimal — Tkinter apps this size don't need it. |

## Installation

```bash
# macOS — verify/install SuperCollider (already installed per project constraint)
# Official signed/notarized build: https://supercollider.github.io/downloads.html
# or:
brew install --cask supercollider

# Python side
cd python_app/
python3 -m venv .venv
source .venv/bin/activate
pip install python-osc        # pythonosc.udp_client.SimpleUDPClient

# Dev dependencies (optional)
pip install pytest
```

No SuperCollider quark installation step is required — the project uses only classes that ship with stock SuperCollider (`TempoClock`, `OSCdef`, `Pbind`/`Pdef`/`Pseq`/`Prand`/`Pfunc`, `Ndef`, `ProxySpace`).

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|--------------------------|
| python-osc | `pyliblo3` / `pyliblo` | Only if you need liblo's C-level performance or its bundled OSC server threading model; it requires a compiled C extension against `liblo`, which is an extra native dependency with no real benefit for a handful of control messages sent a few times per minute. |
| python-osc | `osc4py3` | Only if you specifically need its process-based OSC server or multi-transport (serial/multicast) support; it is less actively maintained and heavier than needed here. |
| Tkinter | PyQt6 / PySide6 | If you later want a richer UI (custom-drawn widgets, animations, theming) — but this adds a large dependency and installer complexity that contradicts the "minimal dependencies" constraint for a slider-and-buttons control panel. |
| Tkinter | Kivy | If you ever want touch-first or mobile deployment — explicitly out of scope per PROJECT.md (desktop-only on the same Mac). |
| No quarks (stock JITLib) | `ddwCommon` / `ddwPatterns` / `cxpatterns` (James Harkins' dewdrop_lib quarks) | If you want convenience helpers (e.g. `ModalSpec`, chord-progression pattern classes) and are willing to accept `Quarks.install` as a network dependency and version-pinning concern. Not needed for v1 — `Pbind`/`Pdef`/scale/chord logic can be written directly. |
| Manual `.scd` script + shell-script smoke test | SuperCollider's internal C++ Boost.Test / ctest suite | Only relevant if you were modifying SuperCollider's own source — not applicable to an application built on top of it. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|--------------|
| Homebrew's bare `tcl-tk` formula with a python.org-installed Python | Homebrew moved `tcl-tk` to 9.0; CPython 3.12/3.13 do not fully support Tcl/Tk 9 yet ([cpython#124111](https://github.com/python/cpython/issues/124111)), and mixing a 9.0 Tcl/Tk with a Python built against 8.6 causes `_tkinter.TclError` crashes at import/runtime ([pyenv#3116](https://github.com/pyenv/pyenv/issues/3116), [Homebrew discussion #5809](https://github.com/orgs/Homebrew/discussions/5809)). | Use the official python.org macOS installer (bundles a matching Tcl/Tk 8.6), or `brew install python-tk@3.12` (pinned formula) which matches your Python's expected Tk version. |
| Apple's system-provided Tk (via `/usr/bin/python3` or old Xcode Python) | Known critical bugs, e.g. crashes on composite-character input, and a very old Tk 8.5. | Always use a python.org or Homebrew `python-tk@x.y`-paired Python, never the Apple system Python, for anything Tkinter. |
| Installing SuperCollider quarks "just in case" | Each quark is an extra `Quarks.install` network fetch + version pin that can silently break on a SuperCollider upgrade; for a single-user personal project this is pure fragility with no corresponding benefit, since JITLib + core Pattern classes already cover drums/bass/arps/pads generative needs. | Write the generative logic directly with stock `Pbind`/`Pdef`/`Tdef`/`Ndef`/`ProxySpace`. |
| `osc4py3`, raw `socket` + manual OSC byte-packing, or any OSC library requiring a compiled extension | Unnecessary complexity/fragility for a localhost, single-direction (mostly) control channel. | `python-osc`'s `SimpleUDPClient` — three lines of code to send a message. |
| Sending control OSC messages to SuperCollider's **server** port (57110, scsynth) | `OSCdef` handlers for custom paths like `/bpm` and `/epic` run inside **sclang**, which listens on the **language port** (57120 by default), not the server port. Messages sent to 57110 will simply be ignored by your `OSCdef`s. | Send to port 57120 (sclang's default language port) — confirm with `NetAddr.langPort` inside the running SC patch if you suspect it's non-default. |

## Stack Patterns by Variant

**If you later want the GUI to confirm the SC patch is alive / reflect current state back (e.g. "connected" indicator):**
- Add a `pythonosc.osc_server.BlockingOSCUDPServer` (or `ThreadingOSCUDPServer`) on a background thread in the Python app, listening on a second port (e.g. 57121), and have the SC patch's `OSCdef` handlers send an acknowledgement `NetAddr` message back.
- Because v1 only needs Python → SC (the GUI is the source of truth for BPM/EPIC/transport/volume state), this is **not needed for v1** — keep the Python side send-only.

**If you need the Python app to survive the SC patch not being started yet (per the "user starts SC separately" constraint):**
- `SimpleUDPClient.send_message()` over UDP does not raise on a missing listener (UDP is connectionless) — so the GUI will not crash or hang if sclang isn't running yet; messages are simply dropped. Worth surfacing a lightweight "no response" indicator later, but it is not a correctness requirement for v1.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|------------------|-------|
| `python-osc` 1.10.2 | Python ≥3.10 | Verified via PyPI metadata (`requires_python: ">=3.10"`); fine with the recommended Python 3.12/3.13. |
| Python 3.12 / 3.13 (python.org installer) | Tcl/Tk 8.6 | This is the pairing that actually works for `tkinter` on macOS as of late 2025; do not let Homebrew upgrade `tcl-tk` to 9.0 underneath a Tk-8.6-linked Python. |
| SuperCollider 3.14.1 | macOS 11+ (universal binary); macOS 10.15+ (legacy x64 build) | If the already-installed SuperCollider is older than 3.14, no forced upgrade is needed — `TempoClock`, `OSCdef`, and JITLib classes used here have been stable for many releases. |
| sclang default language port 57120 | `NetAddr("127.0.0.1", 57120)` on the Python side | This is the port `OSCdef`-registered custom paths (`/bpm`, `/epic`, etc.) receive on — distinct from scsynth's server port 57110. |

## Project Layout

```
PedalPulse/
├── supercollider/
│   ├── main.scd              # entry point: boots server, defines SynthDefs, starts TempoClock + patterns, registers OSCdefs
│   ├── synthdefs/            # one file per instrument/FX SynthDef (drums, bass, arp, pad, delay, reverb, filter)
│   ├── patterns/             # Pbind/Pdef definitions for drums/bass/arp/pad, tempo-ramp helper (Tdef)
│   └── test/
│       └── smoke_test.scd    # headless sanity script (see Testing below)
├── python_app/
│   ├── main.py                # Tkinter app entry point
│   ├── gui.py                 # widgets: BPM slider+entry, EPIC presets+slider, transport, volume
│   ├── osc_client.py          # thin wrapper around pythonosc.udp_client.SimpleUDPClient
│   ├── requirements.txt       # python-osc==1.10.2
│   └── tests/
│       └── test_osc_client.py # mock-socket unit tests (see Testing below)
└── .planning/                  # GSD planning artifacts (this file's home)
```

Keep the SC and Python trees as siblings, not nested — they are two independent processes started separately (per the "user starts SC separately" constraint) and share no filesystem dependency, only the OSC/UDP contract.

## Testing Approach

### Python side
- Use `pytest` with `unittest.mock.patch("socket.socket")` to intercept the UDP socket at the point `SimpleUDPClient` calls `sendto` — this is the exact pattern used in python-osc's own test suite (`pythonosc/test/test_udp_client.py`). Assert the correct OSC address and argument bytes were sent for `/bpm`, `/epic`, `/transport`, `/volume` without opening a real socket or requiring SuperCollider to be running.
- Unit-test pure logic separately from OSC I/O: EPIC preset → numeric value mapping, BPM clamping/validation, debouncing slider events — these don't need any mocking at all.
- GUI widget wiring (Tkinter callbacks) is the one layer not worth unit-testing in depth; a manual smoke test ("move the slider, see the OSC call happen") covers it more cheaply than Tkinter UI automation would.

### SuperCollider side
- sclang can run fully headless (no IDE, no X server): set `QT_QPA_PLATFORM=offscreen` and invoke `sclang path/to/script.scd` from the terminal. Use this for a `smoke_test.scd` that boots the server in **non-real-time** or a scratch real audio device, loads all SynthDefs, instantiates the patterns, and asserts (via `postln`/exit-code) that nothing threw a compile or runtime error.
- There is no project-level unit-testing framework convention for application-level SuperCollider code (SuperCollider's own `ctest`/Boost.Test suite is for the SC source tree itself, not consumer projects) — the practical, proven pattern for an app like this is a shell script that runs `sclang -D smoke_test.scd` and checks the exit code / log output, wired into a simple `make test` or `./test.sh`. This has been done for real by at least one public project (a "headless SuperCollider test pipeline" CI job).
- Treat this as a compile-and-boot smoke test, not a musical-correctness test — verifying "does the patch still load and run for N seconds without error" is the achievable, valuable bar; judging whether the generative music "sounds right" stays a manual/listening task.

## Packaging / Running

- This is a personal, single-machine tool — no need for `PyInstaller`/`py2app` packaging or a distributable `.app`. Running `python3 python_app/main.py` from an activated venv is sufficient.
- SuperCollider patch lifecycle is explicitly out of scope for the Python app (per PROJECT.md constraint: "SuperCollider patch is started separately by the user; the Python app only connects") — so the Python app should not try to launch, supervise, or shut down `sclang`/`scsynth`. It only opens a `SimpleUDPClient` to `127.0.0.1:57120` and starts sending.
- Recommended minimal `requirements.txt`:
  ```
  python-osc==1.10.2
  ```
- Recommended dev-only extra (not shipped, not required to run the app):
  ```
  pytest>=8.0
  ```

## Sources

- [SuperCollider GitHub — README_MACOS.md](https://github.com/supercollider/supercollider/blob/develop/README_MACOS.md) — macOS build/install notes (MEDIUM, websearch cross-checked against official repo)
- [SuperCollider downloads page](https://supercollider.github.io/downloads.html) — 3.14.1 current stable release, Nov 23 2025 (MEDIUM)
- [Homebrew supercollider cask](https://formulae.brew.sh/cask/supercollider) — `brew install --cask supercollider` (MEDIUM)
- [python-osc PyPI project page](https://pypi.org/project/python-osc/) — version 1.10.2, `requires_python >=3.10` (MEDIUM, verified directly via PyPI JSON API)
- [attwad/python-osc GitHub — client.rst / dispatcher.rst / server.rst / test_udp_client.py](https://github.com/attwad/python-osc) — `SimpleUDPClient`/`Dispatcher`/server API, official mock-socket test pattern (MEDIUM)
- [cpython#124111 — Update tkinter to use Tk 8.6.15 or Tk 9.0](https://github.com/python/cpython/issues/124111) — CPython 3.12/3.13 still pair with Tcl/Tk 8.6, Tk 9 support incomplete (MEDIUM)
- [pyenv#3116 — tcl-tk from homebrew is now 9.0, not 8.6](https://github.com/pyenv/pyenv/issues/3116) and [Homebrew discussion #5809](https://github.com/orgs/Homebrew/discussions/5809) — real-world breakage from Tk 9.0/8.6 mismatch (MEDIUM)
- [python.org — IDLE and tkinter with Tcl/Tk on macOS](https://www.python.org/download/mac/tcltk/) — official guidance, Tk 8.6 bundled with python.org installers (MEDIUM)
- [scsynth.org — "Smooth alteration of Tempo"](https://scsynth.org/t/smooth-alteration-of-tempo/6857) — community-standard Task/Routine-stepping pattern for ramping `TempoClock` tempo (MEDIUM)
- [doc.sccode.org — TempoClock](https://help.sccode.org/Scheduling/TempoClock.html) / [doc.sccode.org — OSC Communication](https://doc.sccode.org/Guides/OSC_communication.html) — official class/guide docs for `TempoClock` and `OSCdef`/`NetAddr` (MEDIUM)
- [SuperCollider Wiki — Unit Testing Guide](https://github.com/supercollider/supercollider/wiki/Unit-Testing-Guide) and [scsynth.org — "Scsynth without GUI?"](https://scsynth.org/t/scsynth-without-gui/2040) — headless sclang (`QT_QPA_PLATFORM=offscreen`) and SC-source-level test suite structure (MEDIUM)
- [SuperCollider Quarks Web Index](https://quarks.supercollider.online/) and ddwCommon/ddwChucklib/JITModular GitHub repos — scope of the dewdrop_lib quark ecosystem, confirming it is optional sugar over stock JITLib (MEDIUM)
- [SuperCollider Wiki — Path searching](https://github.com/supercollider/supercollider/wiki/Path-searching) / [Sclang Startup File](https://doc.sccode.org/Reference/StartupFile.html) — project/startup-file conventions (MEDIUM)

---
*Stack research for: Real-time generative music engine (SuperCollider) + Python/Tkinter OSC control app*
*Researched: 2026-10-08*
