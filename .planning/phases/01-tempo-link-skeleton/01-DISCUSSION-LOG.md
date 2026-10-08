# Phase 1: Tempo Link Skeleton - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-08
**Phase:** 01-tempo-link-skeleton
**Areas discussed:** Python env & Tk check, BPM controls & window, Skeleton loop sound, OSC contract & throttling

---

## Python env & Tk check

User note at area selection: "Don't want to use the env Python installation, just create a local virtualenv in .venv folder."

Environment scan: `python3` (3.14) and `python3.12` have no `_tkinter`; `python3.13` has Tk 9.0.3.

| Option | Description | Selected |
|--------|-------------|----------|
| Homebrew python3.13 (Tk 9.0) | Works now, no installs; matched 9.0 build | ✓ |
| Install python.org 3.12/3.13 (Tk 8.6) | Research-recommended pairing; one-time installer | |
| brew install python-tk@3.12 | Adds tkinter to 3.12; may also link Tk 9.0 | |

| Option | Description | Selected |
|--------|-------------|----------|
| Missing tkinter or Tk < 8.6 | 8.6 and 9.x both pass | ✓ |
| Only accept exact build pairing | Stricter patchlevel check | |
| You decide | | |

| Option | Description | Selected |
|--------|-------------|----------|
| Clear terminal message + exit | Dialog impossible if Tk can't load | ✓ |
| Dialog when possible, else terminal | | |

| Option | Description | Selected |
|--------|-------------|----------|
| .venv/bin/python python/main.py | Plain | |
| Small ./run.sh wrapper | Creates venv, installs deps, launches | ✓ |
| Makefile targets | | |

---

## BPM controls & window

| Question | Options | Selected |
|----------|---------|----------|
| Nudge step | ±1 and ±5 / ±1 only / ±2 | ±1 and ±5 |
| Start BPM | 120 / 90 / 128 | 120 |
| GUI range | GUI limited 60–180 + engine clamp / GUI allows wider range | GUI limited, engine clamps too |
| Window | Small with on-top toggle / Normal / Always on top | Small with on-top toggle |
| Entry apply | Enter or focus-out / Enter only | Enter or focus-out |
| Precision | Whole numbers / One decimal | Whole numbers |
| Shortcuts | Arrows ±1, Shift ±5 / None | Arrows ±1, Shift ±5 |

---

## Skeleton loop sound

| Question | Options | Selected |
|----------|---------|----------|
| Loop | Kick + offbeat hat / Kick + hat + simple bassline / Metronome click | Kick + hat + simple bassline |
| Tempo apply (pre-Phase 2) | Instant on next beat / Immediate / Start ramp now | Instant on next beat |
| Autostart | Yes / No | Yes |
| Limiter ceiling | −1 dBFS / −3 dBFS / You decide | −1 dBFS |
| Bassline | A minor offbeat 8ths / A minor 16ths / You decide | A minor offbeat rolling 8ths |
| Hot-gain test | Debug gain var in main.scd / Separate test script | Debug gain var |
| SC launch | IDE + terminal smoke test / Terminal only / IDE only | IDE + terminal smoke test |

---

## OSC contract & throttling

| Question | Options | Selected |
|----------|---------|----------|
| Addresses | /pp/bpm / bare /bpm | /pp/bpm |
| Slider send | Continuous 50ms coalesced / Only on release / Continuous 100ms | Only on release |
| Port config | config.py shown in window / CLI flags / Constants hidden | config.py shown in window |
| Initial sync | Send on launch / Only on change | Send on launch |
| Key repeat / nudges | Debounce ~150ms / Send every step | Debounce ~150ms |

**Notes:** User chose release-only over the recommended continuous coalescing; still satisfies LINK-01 (no flood, final value arrives).

---

## Claude's Discretion

- Synth timbres/envelopes, hat pattern detail, internal file split, widget styling, unit-test scope.

## Deferred Ideas

None.
