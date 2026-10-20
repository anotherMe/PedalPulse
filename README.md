# PedalPulse

PedalPulse makes a soundtrack for indoor cycling workouts (Zwift, for example). It is made of two parts:

- **The engine** (`supercollider/`) is a SuperCollider patch. It keeps generating melodic techno / progressive trance (drums, bass, arpeggios, pads and a lead) for as long as it runs.
- **The control app** (`python_app/`) is a small Python + Tkinter window. You use it to set the tempo (BPM) to match your target cadence, and to set an **EPIC** level that makes the music brighter and more energetic as the effort goes up. It also has play/stop, master volume, and dropdowns to pick the palette, chord progression and melody.

The app sends OSC messages over UDP to the engine on `127.0.0.1:57120`, the sclang language port. You start the engine yourself. The app only connects to it and never starts or stops SuperCollider.

## Requirements

- **SuperCollider** 3.13 or newer (3.14.x recommended).
- **Python** 3.10 or newer (3.12 or 3.13 recommended), with **Tkinter** and Tcl/Tk 8.6 or newer.
- One Python package: `python-osc` (installed in the steps below).

This README does not cover installing Python or SuperCollider.

## Installation

Clone or download the repository, then set up a virtual environment in the project root.

### macOS

The `run.sh` launcher creates `.venv`, installs the dependencies and checks Tkinter:

```bash
./run.sh --setup
```

By default it uses `python3.13`. To use another interpreter, set `PEDALPULSE_PYTHON`:

```bash
PEDALPULSE_PYTHON=python3.12 ./run.sh --setup
```

Use a Python from python.org or Homebrew (with `python-tk@3.x`), not the Apple system Python, whose Tk is too old.

### Linux

`run.sh` works on Linux as well:

```bash
PEDALPULSE_PYTHON=python3 ./run.sh --setup
```

Or set things up by hand:

```bash
python3 -m venv .venv
.venv/bin/pip install -r python_app/requirements.txt
.venv/bin/python python_app/tkcheck.py
```

Some distributions ship Tkinter as a separate package (for example `python3-tk` on Debian/Ubuntu). If the Tk check fails, install that package. SuperCollider on Linux also needs a working audio server (JACK or PipeWire with its JACK layer).

### Windows

`run.sh` is a bash script, so on Windows set things up by hand in PowerShell or Command Prompt:

```powershell
py -m venv .venv
.venv\Scripts\pip install -r python_app\requirements.txt
.venv\Scripts\python python_app\tkcheck.py
```

The python.org installer includes Tkinter by default ("tcl/tk and IDLE" option).

### Developer extras (optional)

To run the Python tests, also install `pytest`:

```bash
.venv/bin/pip install -r python_app/requirements-dev.txt        # macOS / Linux
.venv\Scripts\pip install -r python_app\requirements-dev.txt    # Windows
```

## Running

### 1. Start the engine

1. Open `supercollider/main.scd` in the SuperCollider IDE.
2. Select the whole file (Cmd+A on macOS, Ctrl+A on Windows/Linux) and evaluate it (Cmd+Return / Ctrl+Enter).
3. Wait for the server to boot. The post window shows when the engine is ready.

To run it from a terminal instead, use `sclang supercollider/main.scd`.

The engine listens on sclang's language port, 57120. If another sclang instance already holds that port, sclang picks a different one. Run `NetAddr.langPort.postln;` in the IDE to check.

### 2. Start the control app

```bash
./run.sh                                        # macOS / Linux
.venv\Scripts\python python_app\main.py         # Windows
```

If sclang listens on a non-default port, pass it with `--port`:

```bash
./run.sh --port 57121
```

### 3. Ride

Press play. Set the BPM to your target cadence, and move EPIC up (or use the zone buttons, from Recovery to VO2) as the effort rises. Tempo and EPIC changes glide in smoothly instead of jumping.

UDP has no connection, so the app runs fine before the engine is up. Messages sent before then are just dropped.

PedalPulse plays about 2.5x louder than it used to, so you can hear it next to Zwift without turning the Mac's volume way up. If it is still too quiet or too loud, open `supercollider/main.scd`, change the number on the `~ppMasterBoost = 2.5;` line (1.0 is the original level; keep it at 3.0 or below), then select the whole file and evaluate it again. A limiter keeps the sound from clipping at any setting.

## Variation library

The sounds, chord progressions and melodies are plain `.scd` files under `supercollider/library/`. Each file is one named variation that you can pick from the app's dropdowns. See [supercollider/library/README.md](supercollider/library/README.md) for how to add your own.

## Tests (macOS)

```bash
.venv/bin/python -m pytest python_app/tests   # Python unit tests
bash scripts/check.sh                         # library guard, library check and headless engine smoke test
```

`scripts/check.sh` expects sclang at the default macOS app path. Override it with `SCLANG=/path/to/sclang`.
