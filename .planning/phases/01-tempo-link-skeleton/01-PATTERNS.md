# Phase 1: Tempo Link Skeleton - Pattern Map

**Mapped:** 2026-10-08
**Files analyzed:** 11
**Analogs found:** 0 / 11 (greenfield repo)

## Codebase State

Verified via `git ls-files` at repo root: only `.claude/CLAUDE.md`, `.gitignore`, `README.md` are tracked. No `supercollider/`, `python_app/`, or any application source exists yet. There is no prior commit containing app code — Phase 1 is the first implementation phase (ROADMAP Phase 1), so there are zero in-repo analogs for any role/data-flow combination used here.

**Consequence:** every file below has "no analog" — the planner must build directly from RESEARCH.md's Architecture Patterns (Patterns 1–8) and CONTEXT.md's decisions (D-01..D-24), not from codebase precedent. This is expected and correct for a phase-1 skeleton; do not fabricate analogs.

## File Classification

| New File | Role | Data Flow | Closest Analog | Match Quality |
|----------|------|-----------|-----------------|----------------|
| `supercollider/main.scd` | config/controller (SC entry file) | event-driven (OSC) + streaming (audio) | none | no analog |
| `supercollider/smoke_test.scd` | test | batch (headless compile/boot check) | none | no analog |
| `python_app/run.sh` | config (launcher script) | batch | none | no analog |
| `python_app/requirements.txt` | config | — | none | no analog |
| `python_app/config.py` | config | — | none | no analog |
| `python_app/tkcheck.py` | utility (startup gate) | request-response (sync check) | none | no analog |
| `python_app/main.py` | controller (entry point) | event-driven (Tk mainloop) | none | no analog |
| `python_app/osc_client.py` | service (thin OSC wrapper) | request-response (fire-and-forget UDP send) | none | no analog |
| `python_app/view.py` | component (Tk widgets) | event-driven (UI callbacks) + request-response (OSC send) | none | no analog |
| `python_app/tests/test_clamp.py` | test | — | none | no analog |
| `python_app/tests/test_osc_client.py` | test | — | none | no analog |

## Pattern Assignments

Since no in-repo analogs exist, each file's canonical pattern comes directly from RESEARCH.md. Reference by pattern number — do not re-derive:

### `supercollider/main.scd` (config/controller, event-driven + streaming)
- **Source:** `01-RESEARCH.md` Pattern 1 (boot-gated OSCdef registration, `s.waitForBoot`), Pattern 2 (instant-but-quantized tempo apply via `schedAbs`/`nextTimeOnGrid`), Pattern 3 (master limiter with `~preGain` debug hook)
- Everything (SynthDefs, groups, OSCdef, pattern `.play`) lives inside the `s.waitForBoot({...})` block — see RESEARCH.md lines ~231-235 example.
- `/pp/bpm` handler: `msg[1].asFloat.clip(60, 180)` then `schedAbs` to next beat — RESEARCH.md lines ~245-253.
- Master bus: `Limiter.ar(mix, 0.891251, 0.01)` with `~preGain` var — RESEARCH.md lines ~262-267.
- Every enveloped SynthDef (kick/hat/bass) MUST use `EnvGen.kr(env, doneAction: 2)` (CLAUDE.md + CONTEXT.md non-negotiable).

### `supercollider/smoke_test.scd` (test, batch)
- **Source:** RESEARCH.md Pattern 8 (headless sclang smoke test), invoked via `/Applications/SuperCollider.app/Contents/MacOS/sclang -D` with `QT_QPA_PLATFORM=offscreen` since sclang isn't on PATH.

### `python_app/tkcheck.py` (utility, request-response)
- **Source:** RESEARCH.md Pattern 5 (Tk compatibility check) — exact code given, lines ~308-320. Check `_tkinter` import then `tkinter.TkVersion < 8.6`; must run and exit(1) before any `Tk()` is constructed (D-03/D-04).

### `python_app/main.py` (controller, event-driven)
- **Source:** RESEARCH.md Pattern 5's usage snippet (lines ~322-324): call `check_tk_compatible()` first, then build `OscClient` + `View`, then `root.mainloop()`. On launch, send current BPM once (D-23).

### `python_app/osc_client.py` (service, request-response)
- **Source:** RESEARCH.md "Don't Hand-Roll" table — use `pythonosc.udp_client.SimpleUDPClient.send_message("/pp/bpm", float(value))`, non-blocking `sendto`, no retry/ack logic needed (D-24 send-only).

### `python_app/view.py` (component, event-driven + request-response)
- **Source:** RESEARCH.md Pattern 4 (release-only slider + debounced nudge/arrow) — full code example lines ~279-298. Bind `Scale` `command=` to live-label update only; bind actual OSC send to `<ButtonRelease-1>`. Nudge/arrow sends go through `root.after(150, ...)` cancel-and-reschedule.
- **Source:** RESEARCH.md Pattern 6 (On-top toggle) — `root.attributes("-topmost", bool)` bound to a `Checkbutton`, lines ~331-334.
- Entry field: apply on Enter/focus-out, revert on invalid, snap to 60/180 on out-of-range (D-10) — implement as plain validation in this file, no external pattern needed beyond RESEARCH.md's text description.

### `python_app/config.py` (config)
- **Source:** CONTEXT.md D-22 — `HOST = "127.0.0.1"`, `PORT = 57120`, `DEFAULT_BPM = 120` as module constants.

### `python_app/run.sh` (config/launcher)
- **Source:** RESEARCH.md Pattern 7 (run.sh launch wrapper) — full script given, lines ~339-350. Pins `python3.13`, creates `.venv` if missing, installs `requirements.txt`, execs with venv interpreter.

### `python_app/requirements.txt` (config)
- **Source:** RESEARCH.md Standard Stack — pin `python-osc==1.10.2`.

### `python_app/tests/test_clamp.py` and `test_osc_client.py` (test)
- **Source:** RESEARCH.md Validation Architecture section + Testing Approach in CLAUDE.md — `test_osc_client.py` uses `unittest.mock.patch("socket.socket")` to intercept `SimpleUDPClient`'s `sendto` call, matching `pythonosc/test/test_udp_client.py`'s own pattern. `test_clamp.py` tests pure logic (clamp/parse/revert) with no mocking.

## Shared Patterns

### OSC send discipline (applies to `osc_client.py`, `view.py`)
**Source:** RESEARCH.md Anti-Patterns — never send on every `Scale` `command=` tick (slider-spam, Pitfall 5); never target port 57110 (scsynth) instead of 57120 (sclang language port).

### Engine-side independent clamping (applies to `main.scd`)
**Source:** RESEARCH.md Security Domain V5 — `.clip(60, 180)` must happen in the `OSCdef` handler itself regardless of what the GUI already clamped to (TEMPO-03, D-08), verified via a raw out-of-range OSC test script bypassing the GUI.

### doneAction: 2 on every enveloped SynthDef (applies to `main.scd`)
**Source:** CONTEXT.md Claude's Discretion + CLAUDE.md — non-negotiable for kick/hat/bass, prevents node leaks compounding into later phases' soak tests.

## No Analog Found

All 11 files — this is a greenfield repository (git-tracked files: `.claude/CLAUDE.md`, `.gitignore`, `README.md` only). No prior application code exists to pattern-match against. The planner should treat `01-RESEARCH.md`'s eight numbered Architecture Patterns as the canonical source of concrete code to copy/adapt, not search for in-repo precedent.

## Metadata

**Analog search scope:** full repo (`git ls-files`)
**Files scanned:** 3 tracked non-planning files (none are source analogs)
**Pattern extraction date:** 2026-10-08
