# Walking Skeleton — PedalPulse

**Phase:** 1
**Generated:** 2026-10-08

## Capability Proven End-to-End

A rider runs `supercollider/main.scd`, launches `./run.sh`, and moving the BPM slider (or entry / nudge buttons / arrow keys) in the Tkinter window audibly changes the tempo of a kick/hat/bass loop. The loop plays on a dedicated TempoClock through a −1 dBFS master limiter, and the BPM travels Python → OSC/UDP → sclang `OSCdef` → `TempoClock`.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Audio engine | SuperCollider 3.14.1, one entry file `supercollider/main.scd`, everything inside `s.waitForBoot({...})` | Project constraint (SC already installed). Boot gating prevents dropped early messages (Pitfall 3). The engine is started separately by the user, from the SC IDE (D-15, D-18). |
| Engine state ("conductor") | Top-level `~` environment vars (`~bpm`, `~clock`, `~ppMixBus`, `~ppMasterSynth`, ...). OSCdefs are the only writers of control state. | ARCHITECTURE.md Pattern 1: the simplest correct single source of truth for one controller |
| Tempo authority | Dedicated `~clock = TempoClock.new(120/60)` (not `TempoClock.default`). In Phase 1 a BPM change applies at the next whole beat with latest-wins coalescing (one pending apply). | D-07, D-14. Phase 2 replaces only the apply step with a beat-synchronous ramp; the clock stays. |
| Audio topology | Instruments in `~ppInstrGroup` write only to the private stereo bus `~ppMixBus`. `\ppMaster` in `~ppMasterGroup` (after the instruments) applies `preGain` and then `Limiter.ar(sig, 0.891251, 0.01)` before writing to hardware out 0. | ENG-02 / D-16. Later phases insert FX/volume between the mix bus and the limiter, never around it. |
| Synth lifecycle | Every enveloped SynthDef (`\ppKick`, `\ppHat`, `\ppBass`) frees itself with `doneAction: 2` | Prevents node leaks before the Phase 4 soak test (Pitfall 4) |
| OSC contract | Namespaced `/pp/<name>`. Phase 1 uses `/pp/bpm <float>`. The engine validates the argument (numeric, not NaN) and clamps it to 60–180. The handler accepts loopback senders only (`srcID: NetAddr("127.0.0.1", nil)`). | D-19 (rated costly: later phases add `/pp/epic`, `/pp/play`, `/pp/volume` against this scheme). sclang listens on all interfaces (`*:57120`, verified 2026-10-08), so the engine filters out non-local senders. |
| Port discovery | The engine posts `NetAddr.langPort` on boot and warns when it is not 57120. Python keeps `OSC_HOST`/`OSC_PORT` in `python_app/config.py` (`--port` overrides) and shows "Sending to host:port" in the window. | ENG-04, D-22, Pitfall 1 |
| Control app | Python 3.13 (Homebrew) + Tkinter (Tk 9.0.3) + python-osc 1.10.2 `SimpleUDPClient`, send-only, main thread only | D-02, D-24, CLAUDE.md minimal dependencies |
| Python layout | `python_app/` flat modules: `config.py`, `osc_client.py` (client + raw-send CLI), `tkcheck.py`, `bpm_logic.py` (pure state/send policy, no Tk), `view.py` (Tk widgets only), `main.py` (wiring) | Model/view split per ARCHITECTURE.md, narrowed for the skeleton (Claude's discretion). `bpm_logic.py` is unit-testable without Tk. |
| Send policy | The GUI is the source of truth. The slider sends only on release, nudges and arrow keys are debounced (150 ms, cancel-and-reschedule), the entry sends on apply, and the app sends the current BPM once on launch. | D-20, D-21, D-23, LINK-01 |
| Environment / launch | Repo-root `./run.sh` creates `./.venv` from `python3.13` when it is missing, installs the requirements (dev requirements with `--setup`), and runs `python_app/main.py`. `tkcheck.py` gates on `_tkinter` importability and `TkVersion >= 8.6` before any other import. | D-01..D-05, GUI-04 |
| Tests | Python: pytest 8.4.2 (dev only, `python_app/tests/`, `conftest.py` puts `python_app/` on `sys.path`). Engine: `scripts/smoke_test.sh` runs `sclang -D supercollider/smoke_test.scd` headless on its own server port (57140) with hardware output muted. The smoke test drives raw `/pp/bpm` through `python_app/osc_client.py` (real Python → UDP → sclang path). | D-08, D-18. `QT_QPA_PLATFORM=offscreen` is NOT used: verified to abort sclang 3.14.1 on macOS (exit 134, only the `cocoa` Qt plugin is bundled). |
| Data layer / auth / deployment | None. Single-user, single-machine, in-memory state. "Deployment" is the documented local run: evaluate `main.scd` in the SC IDE, then `./run.sh`. | PROJECT.md: personal tool, no packaging, SC started separately |

## Stack Touched in Phase 1

- [ ] Project scaffold: `supercollider/`, `python_app/`, `scripts/`, `./run.sh`, `.venv`, pytest, headless sclang smoke test (Plans 01, 02)
- [ ] Routing: the OSC address `/pp/bpm` routed to `OSCdef(\pp_bpm)` (Plan 01)
- [ ] Database: N/A (no persistence). The stateful equivalent is a real engine-state write (`~clock.tempo` via OSC) and a read (the smoke test asserts it) (Plan 01)
- [ ] UI: slider release → `/pp/bpm` → audible tempo change (Plan 02); entry, nudges and keys in sync (Plan 03)
- [ ] Deployment: documented local full-stack run, `main.scd` in the SC IDE plus `./run.sh` (Plans 01, 02)

## Out of Scope (Deferred to Later Slices)

- Smooth beat-synchronous tempo glide and mid-ramp retargeting (Phase 2; it replaces the next-beat apply in `OSCdef(\pp_bpm)`)
- Full drums/bass/arp/pad groove and start/stop transport `/pp/play` (Phase 2; it reuses `\ppKick`, `\ppHat`, `\ppBass`)
- EPIC zones `/pp/epic` and master volume `/pp/volume` (Phase 3; inserted between `~ppMixBus` and the limiter)
- Python receive path, heartbeat, connection indicator, engine-reported BPM (Phase 4; D-24 keeps Phase 1 send-only)
- Python app launching or supervising sclang (out of scope for the whole project)

## Subsequent Slice Plan

Each later phase adds one vertical slice on top of this skeleton without changing its architectural decisions:

- Phase 2: the full trance groove (drums/bass/arp/pad) glides beat-synchronously to new BPMs and starts and stops from the GUI
- Phase 3: five EPIC zone buttons drive brightness/energy, plus master volume, and the limiter still guarantees no clipping
- Phase 4: the engine heartbeat drives a connection indicator, the GUI shows the engine's live BPM/EPIC, and a 60-minute soak test
