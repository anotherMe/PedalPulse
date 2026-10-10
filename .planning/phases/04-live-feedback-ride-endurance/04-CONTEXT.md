# Phase 4: Live Feedback & Ride Endurance - Context

**Gathered:** 2026-10-10
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers the first engine → GUI channel:
- A heartbeat sent from sclang drives a connected/disconnected indicator in the Tkinter window (LINK-02).
- The window shows the engine's actual current BPM, including values mid-glide, and the EPIC target the engine accepted (LINK-03).
- The GUI stays responsive while status messages stream in.
- Leveled stdout logging, enabled with `--log`, makes the 60+ minute stability check (ENG-03) objective when the user rides it.

The Python app stops being send-only. It never launches or manages sclang.

**Not in this phase:** new controls, Zwift integration, cadence sensors, and EPIC fine-tuning. These remain out of scope per PROJECT.md.

</domain>

<decisions>
## Implementation Decisions

### Connection indicator (LINK-02)
- **D-01:** The indicator is a colored dot plus a word, readable at a glance over Zwift. Example: green ● "Engine connected" / grey ● "Engine not responding". It replaces or sits beside the existing "Sending to 127.0.0.1:57120" status line. The target address may stay visible somewhere in the window.
- **D-02:** The indicator flips to disconnected after about **3 seconds** with no heartbeat. The engine sends heartbeats several times per second, so this tolerates a brief sclang stall. When heartbeats resume, the indicator returns to connected on its own.
- **D-03:** Controls stay **fully usable** while disconnected: no greying, no dimming. Values the user sets are kept. Only the indicator and readout change. This follows Phase 1's "GUI is the source of truth" (01-CONTEXT D-23).
- **D-04:** At app launch the indicator shows **disconnected until the first heartbeat arrives**. There is no third "Connecting…" state.

### Reconnect resync
- **D-05:** On every disconnected → connected transition, the GUI **automatically re-sends its full state**: BPM, current zone's EPIC value, volume, and play state. This includes the first connection after launch. The engine handlers are idempotent, so a duplicate of the launch-time `send_initial()` sends is harmless. Restarting `main.scd` therefore brings the engine back to what the window shows, Play included.
  - This is a conscious choice against research's warning about "silent auto-fix" (`.planning/research/FEATURES.md` anti-feature row). It only re-sends known GUI state; it does not retry connections or hide a dead engine, because the indicator still shows the truth.
- **D-06:** The resynced BPM reaches its target through the **normal ~2-bar glide** (the existing `~ppRampStepper`), with no special instant-jump path. A restarted engine boots at 120 and glides to the GUI's BPM.
- **D-07:** Resync is **silent**: no status note or toast. The indicator turning green and the live readout catching up are enough.

### Live engine readout (LINK-03)
- **D-08:** A **separate "Engine" readout line** sits next to the connection indicator. The existing controls keep showing what the user asked for; the readout shows what the engine is actually doing. Rough layout: `Engine: 131 BPM · EPIC 50 (Tempo)`.
- **D-09:** BPM shows the engine's **live tempo as a whole number**, with no decimals and no target arrow. It updates through a glide, so mid-ramp values are visible (131 → 132 → … → 140). The engine must report the instantaneous `~clock.tempo` and must only read it, never write it (`~ppRampStepper` stays the only tempo writer).
- **D-10:** EPIC shows the **target value only**, the one the engine last accepted (`~epic`). It does not show the smoothed or gliding bus value.
- **D-11:** EPIC is shown as **number plus zone name**, e.g. `EPIC 50 (Tempo)`. The GUI maps the reported value to a name via `config.EPIC_ZONES`, since the engine never knows zone names. If no zone matches, for example a value set through the CLI, show the number only.
- **D-12:** While disconnected, the readout shows **dashes** (e.g. `Engine: — BPM · EPIC —`) so stale numbers are never mistaken for live data.

### Soak test & logging (ENG-03)
- **D-13:** The user verifies the 60+ minute soak by riding a real Zwift session when time allows. It is **non-blocking**: it does not gate phase completion, verification, or further development. Record it as a deferred, non-blocking human-verification item, not a blocking UAT checkpoint.
- **D-14:** **No automated soak or leak proxy** is added for this phase. That means no extended headless leak check in `scripts/smoke_test.sh` and no long headless run. Normal smoke-test coverage for the new heartbeat/status code is still expected.
- **D-15:** Logging is an **organic part of the Python app**. Launching with **`--log`** prints log messages to **stdout**. Without `--log` the app stays quiet as it does today.
- **D-16:** Logging uses **levels**, with these meanings:
  - **TRACE (lowest):** per-heartbeat / per-status-message detail.
  - **DEBUG:** possibly critical points, including connect/disconnect transitions, resync, each control send (BPM/zone/volume/play), and a **periodic stats line about every 30 s**. The stats line carries engine BPM, EPIC, synth node count, and average/peak CPU.
  - **INFO:** main steps such as app start, the target and listen addresses, and shutdown.
  - **ERROR:** inside every `try/except` handler, such as a failed send or a malformed status message.
- **D-17:** The minimum displayed level is a **constant in the Python code** (e.g. `LOG_LEVEL` in `config.py`) that the user edits by hand. It is not a CLI option. The default is **DEBUG**, so `--log` shows stats and events out of the box.
  - The user described these levels from Java experience. Python's stdlib `logging` has DEBUG/INFO/WARNING/ERROR/CRITICAL and **no TRACE**, so add a custom TRACE level (e.g. numeric 5 via `logging.addLevelName`) with stdlib only, no new dependency.
- **D-18:** To make the stats line possible, the engine's status message must carry synth node count and average/peak CPU alongside BPM and EPIC.

### Claude's Discretion
- The heartbeat/status message design:
  - One combined status message versus separate heartbeat and status messages.
  - Address name under the `/pp/*` scheme (01-CONTEXT D-19).
  - Send rate: several per second to support the ~3 s timeout and visible mid-glide BPM, while staying light enough not to disturb Zwift.
  - Return port: research suggests 57121, loopback only.
  - How sclang knows where to send. Fixed loopback host/port versus learning it from incoming messages; it must work when the GUI starts before the engine.
- Python receive architecture: a background `python-osc` server thread plus a `queue.Queue` polled from Tk via `root.after()`. Never touch Tk widgets from the worker thread (research PITFALLS.md Pitfall 7). Bind to `127.0.0.1` only.
- Exact dot glyph/colors and the wording of indicator and readout strings, within D-01/D-08/D-12. Note that Tk 9 aqua renders some widget colors poorly (Phase 2/3 UI reviews), so pick a rendering that is actually visible.
- Where in the window the indicator and readout lines sit, keeping the window compact (01-CONTEXT D-12).
- Logger structure: module-level `logging.getLogger` names, the formatter (timestamps recommended for the soak), and where the 30 s stats timer lives.
- Whether the "Sending to …" address text survives as part of the indicator line or moves elsewhere.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope & requirements
- `.planning/ROADMAP.md` § "Phase 4: Live Feedback & Ride Endurance": goal and the 4 success criteria. Criterion 4 (60-min soak) is non-blocking per D-13.
- `.planning/REQUIREMENTS.md`: ENG-03, LINK-02, LINK-03.
- `.planning/PROJECT.md`: constraints (light enough for Zwift, loopback OSC, Python never manages sclang) and the Key Decisions table.

### Prior decisions that still bind
- `.planning/phases/01-tempo-link-skeleton/01-CONTEXT.md`:
  - D-19: namespaced `/pp/*` OSC addresses.
  - D-22: `config.py` holds host/port.
  - D-23: GUI is the source of truth and sends initial state at launch.
  - D-24: the receive path and heartbeat were deferred to this phase.
  - D-12: compact, always-on-top window.
- `.planning/STATE.md` § "Accumulated Context → Decisions": `~ppRampStepper` is the only writer of `~clock.tempo`, and loopback-only `srcID` applies on every OSCdef.

### Research guidance for the receive path
- `.planning/research/PITFALLS.md`:
  - Pitfall 7 (§ ~line 143): Tk is single-threaded, so use a worker thread, then a `queue.Queue`, then `root.after()` polling.
  - Pitfall 9 (§ ~line 192): heartbeat and connection indicator.
  - Security table: bind both ends to `127.0.0.1`.
  - Heartbeat-frequency note.
  - Soak-test notes on `s.numSynths`.
- `.planning/research/STACK.md` § "Stack Patterns by Variant" (line ~79): `python-osc` `BlockingOSCUDPServer`/`ThreadingOSCUDPServer` on a background thread, second port e.g. 57121.
- `.planning/research/FEATURES.md`: status indicator rationale, plus the "silent auto-fix" anti-feature that D-05 consciously departs from.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `python_app/osc_client.py` `OscClient`:
  - `send_bpm`, `send_play`, `send_epic` and `send_volume` each return `bool` and catch `(OSError, OverflowError, BuildError)`. Those except clauses are where the D-16 ERROR log lines go.
  - Resync (D-05) can reuse these send methods directly.
- `python_app/bpm_logic.py`:
  - `BpmController`, `PlayController`, `EpicController` and `VolumeController` are pure state classes with `send_initial()`. They already hold the current value, zone and play state that resync needs to re-send.
  - A new pure connection/status-state class fits the same sibling-controller pattern: no Tk coupling, unit-testable with an injected clock.
- `python_app/config.py`: `EPIC_ZONES` provides the value → zone-name mapping (D-11). It is also the natural home for the return port, the heartbeat timeout and `LOG_LEVEL`.
- `python_app/view.py` `BpmWindow`: the existing `status_label` ("Sending to …") is where the indicator and readout lines go (D-01, D-08).
- `python_app/main.py`: already uses `argparse` (`--port`, `--exit-after`). Add `--log` here, plus the receive-server startup and shutdown.
- `supercollider/main.scd`:
  - `~ppRampStepper` keeps `~bpm` equal to `~clock.tempo * 60` through glides, so it is a readable live-BPM source.
  - `~epic` is the accepted EPIC target.
  - `s.numSynths`, `s.avgCPU` and `s.peakCPU` provide stats for D-18.

### Established Patterns
- OSCdefs live inside `s.waitForBoot`, with a loopback-only `srcID: NetAddr("127.0.0.1", nil)`. They validate arguments and post a log line.
- The re-evaluation teardown block frees or stops every long-lived object before re-creating it. Any new heartbeat Routine, Task or SkipJack must be added to that teardown so re-evaluating doesn't leak duplicate senders.
- Tempo-related Routines play on `~clock` or use explicit timing. A heartbeat should be driven by wall-clock time, not by `~clock` beats, so its rate does not change with BPM. Planner's call.
- The GUI sends only on a real change or on release (PlayController/EpicController: notify then send). Resync is an intentional exception that sends unconditionally, like `send_initial()`.
- Tests:
  - pytest unit tests for pure logic.
  - Real-socket OSC round-trip tests in `test_osc_client.py`.
  - Tk widget smoke tests in `test_view_tk.py`.
  - Engine regression checks in `supercollider/smoke_test.scd` run via `scripts/smoke_test.sh` (isolated muted server on port 57140). New engine status code should get smoke checks there.

### Integration Points
- Engine → GUI: a new sclang sender, `NetAddr` to the GUI's loopback port.
- GUI receive: a new background `python-osc` server, a queue, and `root.after` polling in `main.py`/`view.py`.
- Resync hook: the connection-state transition calls the existing controllers' send paths.
- Logging: the `--log` flag in `main.py` configures the root logger. Modules use `logging.getLogger(__name__)`.

</code_context>

<specifics>
## Specific Ideas

- The user wants logging to feel like a normal part of the app ("launch the Python app with `--log` and log messages go to stdout"), not a separate soak tool.
- The user prefers a calm readout: whole-number BPM with no arrow, and the EPIC target rather than the gliding value. Avoid visually noisy, fast-changing decimals.
- The user may later adjust the log threshold by editing the constant in the script.

</specifics>

<deferred>
## Deferred Ideas

- **60+ minute real-ride soak (ENG-03 success criterion 4):** the user runs it during a real Zwift ride when time allows, using `--log` output to judge whether node count and CPU stay flat. It is non-blocking and must not hold up phase completion or later milestones.
- Discussed and rejected: an automated headless leak check and a long headless soak script (D-14). They could be revisited if a leak is ever suspected.

</deferred>

---

*Phase: 04-live-feedback-ride-endurance*
*Context gathered: 2026-10-10*
