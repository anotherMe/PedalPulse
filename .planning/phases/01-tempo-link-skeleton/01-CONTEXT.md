# Phase 1: Tempo Link Skeleton - Context

**Gathered:** 2026-10-08
**Status:** Ready for planning

<domain>
## Phase Boundary

The walking skeleton of the Python → OSC → SuperCollider chain. A single sclang entry file (`main.scd`) boots the server, posts its OSC language port, and autostarts a basic loop (kick + hat + simple bassline) on a dedicated TempoClock routed through a master limiter. A Tkinter app (run from a local `.venv`, with a startup Tk check) lets the user set BPM via slider, entry and nudge buttons. It sends `/pp/bpm` over OSC without flooding, and the engine clamps the value to 60–180 and changes tempo.

Requirements: ENG-02, ENG-04, TEMPO-03, GUI-01, GUI-04, LINK-01.

**Not in this phase:** smooth beat-synced tempo glides and mid-ramp retargeting (Phase 2), start/stop transport (Phase 2), full drums/bass/arp/pad groove (Phase 2), EPIC and master volume (Phase 3), heartbeat/connection indicator and engine-reported BPM display (Phase 4).

</domain>

<decisions>
## Implementation Decisions

### Python environment & Tk check
- **D-01:** Do not use a global Python install. The app runs from a project-local virtualenv in `.venv/` (gitignored).
- **D-02:** `.venv` is created from Homebrew `python3.13`, which pairs with Tk 9.0.3. On this Mac it is the only interpreter with a working tkinter: Homebrew `python3` (3.14) and `python3.12` both lack `_tkinter`. This supersedes the research's "Tk 8.6 only" recommendation. The risk research flagged was an 8.6/9.0 *mismatch*, not a matched 9.0 build. The planner should include a quick smoke test that the slider, entry and buttons behave correctly under Tk 9. — **Reversibility:** reversible — recreating `.venv` from another interpreter is a one-line change in `run.sh`.
- **D-03:** Startup check (GUI-04): the app is "incompatible" if `tkinter`/`_tkinter` fails to import or `TkVersion < 8.6`. Tk 8.6 and 9.x both pass. No exact build-pairing check.
- **D-04:** On a failed check, print a clear terminal message explaining what is wrong and how to fix it (e.g. "run via ./run.sh / use the .venv built from python3.13"), then exit non-zero. No GUI dialog, since Tk may not be loadable.
- **D-05:** Launch through a small `./run.sh` wrapper. It creates `.venv` from `python3.13` if missing, installs `requirements.txt` (python-osc), and launches the app with the venv interpreter.

### BPM controls & window (GUI-01)
- **D-06:** Controls are a slider, an integer entry field, and two nudge pairs laid out as `−5 −1 [value] +1 +5`. All of them stay in sync.
- **D-07:** Start/default BPM is 120 in both the GUI and the engine.
- **D-08:** GUI controls are limited to 60–180. The engine clamps independently (TEMPO-03). Engine clamping is verified by sending raw out-of-range OSC from a test script, not through the GUI.
- **D-09:** BPM is a whole number in the GUI. The engine accepts and clamps floats.
- **D-10:** The entry applies on Enter or focus-out. Invalid text reverts to the current value. Out-of-range numbers snap to 60 or 180.
- **D-11:** Keyboard shortcuts while the window has focus: Up/Down arrows ±1, Shift+Up/Down ±5.
- **D-12:** The window is compact, with an "On top" checkbox that toggles always-on-top so it can float over Zwift.

### Skeleton loop sound (ENG-02, ENG-04)
- **D-13:** The loop is a four-on-the-floor kick, a hat, and a simple bassline: A minor, offbeat rolling 8ths on the root, with a note change at the bar end. SynthDefs should be reusable as the starting point for Phase 2's groove.
- **D-14:** Until Phase 2's ramp exists, a BPM change applies instantly, quantized to the next beat boundary. No glide yet.
- **D-15:** The loop autostarts once `main.scd` finishes booting (no transport command in Phase 1).
- **D-16:** The master limiter ceiling is −1 dBFS (≈0.89 linear) on the master bus. All audio goes through it.
- **D-17:** The hot-gain limiter check (success criterion 5) uses a debug pre-limiter gain variable in `main.scd` (e.g. `~preGain`). The user raises it, re-evaluates, and watches peaks stay at the ceiling. No separate automated limiter test is required.
- **D-18:** The user runs `main.scd` from the SuperCollider IDE for normal playing. A terminal script runs a headless smoke test by calling `/Applications/SuperCollider.app/Contents/MacOS/sclang` directly, since sclang is not on PATH. Use `QT_QPA_PLATFORM=offscreen` per the stack notes.

### OSC contract & send policy (LINK-01)
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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Scope & requirements
- `.planning/ROADMAP.md` §"Phase 1: Tempo Link Skeleton": goal, success criteria 1–5
- `.planning/REQUIREMENTS.md`: ENG-02, ENG-04, TEMPO-03, GUI-01, GUI-04, LINK-01 definitions
- `.planning/PROJECT.md`: constraints (macOS, Zwift coexistence, SC started separately, minimal deps) and key decisions

### Research
- `.planning/research/SUMMARY.md`: stack, critical pitfalls (port drift, boot gating, node leaks, clipping, slider spam, Tk mismatch)
- `.planning/research/ARCHITECTURE.md` §"Recommended Project Structure": suggested `supercollider/` and `python/` layout and Python MVC split
- `.planning/research/PITFALLS.md`: detailed pitfall prevention (server boot gating, `doneAction: 2`, limiter, throttling)
- `.planning/research/STACK.md`: versions, python-osc `SimpleUDPClient`, headless sclang smoke-test approach

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None. This is a greenfield repo: only `README.md`, `.gitignore`, `.planning/` and `.claude/` exist.

### Established Patterns
- None yet. This phase establishes them: boot-gated OSCdefs (`s.waitForBoot`), a master limiter bus, self-freeing synths, the `/pp/*` address namespace, and `.venv` + `run.sh` launch.

### Integration Points
- sclang language port 57120 (default). `main.scd` must post `NetAddr.langPort`, and Python `config.py` must match it.
- Environment facts (verified 2026-10-08): SuperCollider 3.14.1 at `/Applications/SuperCollider.app`, with sclang at `/Applications/SuperCollider.app/Contents/MacOS/sclang` and not on PATH. Python: Homebrew `python3.13` (3.13.12) with Tk 9.0.3 works; `python3` (3.14) and `python3.12` have no `_tkinter`.

</code_context>

<specifics>
## Specific Ideas

- The window should be usable while Zwift is full-screen, hence the "On top" toggle.
- The bassline should feel trance/progressive (offbeat rolling 8ths in A minor) even in the skeleton, so the tempo change is felt musically and not only heard as clicks.

</specifics>

<deferred>
## Deferred Ideas

None. The discussion stayed within phase scope. (Live tempo tracking during a slider drag was considered and rejected in favor of release-only sends, so no follow-up is needed.)

</deferred>

---

*Phase: 01-tempo-link-skeleton*
*Context gathered: 2026-10-08*
