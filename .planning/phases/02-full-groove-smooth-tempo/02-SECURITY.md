---
phase: "02"
slug: "full-groove-smooth-tempo"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-09"
---

# Phase 02 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> Register authored at plan time (`<threat_model>` blocks in 02-01, 02-02, 02-03, 02-04 PLAN.md). Verified at ASVS L1 (grep-depth evidence against the implementation, plus the passing pytest suite, 87/87, and headless smoke test, 36/36 `SMOKE PASS`). No SUMMARY raised threat flags. No threat is rated at or above the `high` block threshold.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| UDP loopback → sclang `OSCdef(\pp_play)` | Any local process can send `/pp/play` with any argument type to the language port | OSC transport command (untrusted, low sensitivity) |
| UDP loopback → sclang `OSCdef(\pp_bpm)` (mid-glide) | Any local process can send any value or type, at any rate, including while a glide is running | `/pp/bpm` numeric tempo target |
| CLI arguments → `osc_client.py` | Raw, unvalidated values are sent on purpose (test tool); the engine is the validator | CLI test input |
| Mouse clicks → UDP sender | Each Start/Stop click produces one OSC send to the engine | `/pp/play` ints to 127.0.0.1 |
| Python app → engine process | The app must stay a pure OSC client and never manage the engine's lifecycle | None (lifecycle boundary) |
| Stop command → server node tree | A Stop must reach synths that are already running, including notes in flight | Node control (`\gate, 0` broadcast) |
| OSC handler → TempoClock | Tempo writes come from one long-lived Routine; a crash or a stacked copy would freeze or distort the glide | Tempo value |
| Instrument SynthDefs → hardware output | Every voice must pass the master limiter before reaching the rider's headphones | Audio signal level |
| Engine CPU → Zwift on the same Mac | Added voices compete with the game for CPU | CPU time |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-02-01 | Tampering | `OSCdef(\pp_play)` argument handling | medium | mitigate | `raw.isNumber.not or: { raw.isNaN }` guard (`main.scd:289`) before `asInteger`; invalid input posts a warning and changes no state. Smoke check `play malformed ignored` (no argument, string, NaN) | closed |
| T-02-02 | Spoofing | `OSCdef(\pp_play)` sender | medium | mitigate | `srcID: NetAddr("127.0.0.1", nil)` (`main.scd:300`), same guard as `/pp/bpm` (`main.scd:281`). Smoke check `loopback-only` now also sends `/pp/play 0` from the LAN address and asserts the groove keeps playing | closed |
| T-02-03 | Denial of Service | repeated `/pp/play` (buggy retry loop) | low | mitigate | Idempotency guard `want == ~ppPlaying` (`main.scd:293`) makes repeats no-ops; `~ppTransportCount` (`main.scd:232,239`) proves it. Smoke check `play idempotent` | closed |
| T-02-04 | Denial of Service | `~ppStop` vs running synths | medium | mitigate | Immediate `~ppInstrGroup.set(\gate, 0)` (`main.scd:247`) plus a second guarded broadcast after `s.latency` (`main.scd:258-259`) for in-flight note-ons; `doneAction: 2` on all six instrument SynthDefs. Smoke checks `stop releases all`, `group gate broadcast` | closed |
| T-02-05 | Tampering | `OscClient.send_play` encoding | low | mitigate | `int(playing)` coercion (`osc_client.py:59`) so a Python bool never becomes the OSC True/False tag. `test_send_play_coerces_bool_to_int`, `test_send_play_delivers_int_osc_message_over_real_socket` | closed |
| T-02-06 | Denial of Service | rapid Start/Stop clicks → `PlayController` | low | accept | One small UDP datagram per click, bounded by human click rate; the engine's idempotent guard (T-02-03) makes repeated identical commands no-ops. See AR-02-01 | closed |
| T-02-07 | Elevation of Privilege | `python_app` process management | medium | mitigate | The button only calls `OscClient.send_play`; no `subprocess`, `os.system`, `os.kill`, `Popen`, `os.spawn*`, `os.exec*` or `signal` use anywhere in `python_app/*.py` (grep clean), per the PROJECT.md lifecycle constraint | closed |
| T-02-08 | Tampering | GUI/engine state drift (engine re-evaluated while the GUI shows "Start") | low | accept | Single-user local tool; the Python side is send-only until Phase 4 (LINK-02/03). A drift self-heals on the next click because the engine ignores a command that matches its state. See AR-02-02 | closed |
| T-02-09 | Tampering | `OSCdef(\pp_bpm)` argument handling mid-glide | medium | mitigate | Phase 1's `isNumber`/`isNaN` guard (`main.scd:274`) and the 60–180 clamp stay in front of the pending-target store (`main.scd:278`). Smoke check `malformed ignored` sends bad input mid-glide and asserts the target and apply count are unchanged and the glide still lands | closed |
| T-02-10 | Denial of Service | flood of `/pp/bpm` (e.g. a buggy sender) | low | mitigate | Latest wins: the handler only overwrites one pending value, `~ppRampPendingBpm` (`main.scd:278`), which the stepper engages at most once per 16th-note tick (`main.scd:130-135`); no scheduling per message. Smoke check `latest wins` | closed |
| T-02-11 | Denial of Service | `~ppRampStepper` vs re-evaluation | medium | mitigate | Teardown stops the old stepper (`main.scd:35`) and the old clock and resets the ramp state (`main.scd:45`). Smoke check `re-evaluation` asserts the next glide still takes 6–9 beats (a stacked stepper would halve it) | closed |
| T-02-12 | Tampering | tempo continuity (rider safety) | medium | mitigate | `~ppRampStepper` (`main.scd:122`) is the only writer of `~clock.tempo` (`main.scd:149,153`), with a per-tick step bound. Smoke checks `glide reaches target`, `glide upward`, `retarget mid-glide` assert no sampled step above two ramp steps | closed |
| T-02-13 | Tampering (hearing safety) | new layers bypassing the limiter | medium | mitigate | All six Pbindefs set `\out, ~ppMixBus` (6/6 by grep); `\ppMaster` keeps `Limiter.ar(sig, 0.891251, 0.01)` as the last stage (`main.scd:93-96`). Smoke checks `limiter no bypass` (now covering all six layers), `limiter ceiling`, `mix headroom` | closed |
| T-02-14 | Denial of Service | node growth from overlapping pad chords | medium | mitigate | `doneAction: 2` on all six instrument SynthDefs (grep count 6); gated arp/pad releases. Smoke check `node bound` stays at ≤ 20 synths at 180 BPM with the bound not raised | closed |
| T-02-15 | Denial of Service | CPU competition with Zwift | low | mitigate | At most three oscillators and one filter per voice (`main.scd:47-91`: pad 3×Saw + LPF, arp 2×Pulse + LPF, bass 2×Saw + RLPF, clap/hat noise + one filter, kick one SinOsc); no effect UGens (grep clean). Live Zwift observation is the optional 02-04 human-check step 6; the 60-minute soak is Phase 4 (ENG-03) | closed |
| T-02-16 | Denial of Service | Stop leaving a held or in-flight pad sounding | medium | mitigate | Plan 01's two broadcasts (T-02-04). Smoke checks `stop cuts held pad` and `stop catches in-flight notes` assert an empty instrument group within 2.0 s against a natural tail of about 3 s | closed |
| T-02-SC | Tampering | package installs (declared in all four plans) | low | accept | No plan in this phase adds or changes a dependency (`python_app/requirements*.txt` and `run.sh` unchanged since the phase plan commit); no quarks. See AR-02-03 | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-02-01 | T-02-06 | Rapid Start/Stop clicks send one small loopback datagram each, bounded by human click rate, and the engine's idempotent `/pp/play` guard turns repeated identical commands into no-ops, so no debounce is needed | Plan-time disposition (02-02 threat model) | 2026-10-09 |
| AR-02-02 | T-02-08 | GUI/engine state can drift only if the engine is re-evaluated while the GUI shows "Start"; on a single-user local tool this self-heals on the next click, and two-way state sync is scoped to Phase 4 (LINK-02/03) | Plan-time disposition (02-02 threat model) | 2026-10-09 |
| AR-02-03 | T-02-SC (02-01 to 02-04) | No plan in this phase installs or changes a dependency; python-osc 1.10.2 and pytest 8.4.2 were gated and pinned in Phase 1. Executors built throwaway, uncommitted worktree-local `.venv`s from those same pinned requirements files only to run the tests | Plan-time disposition (02-01 to 02-04 threat models) | 2026-10-09 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-09 | 17 | 17 | 0 | secure-phase (orchestrator, ASVS L1 short-circuit — register authored at plan time, 0 open; auditor not required) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-09
