---
phase: "03"
slug: "epic-zones-volume"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-09"
---

# Phase 03 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Network → sclang OSC port 57120 | `/pp/epic` and `/pp/volume` are new input surfaces on the language port; any local or LAN process can send UDP there | OSC float control values (no sensitive data) |
| FX chain / master gain → hardware output | EPIC drive, the FX synth and master volume must reach the speakers only through the master limiter (hearing safety) | Audio signal |
| Engine CPU → Zwift on the same Mac | An always-on reverb and filter run for the whole session | CPU time |
| User input → Tk view | Clicks, slider drags and key presses drive the EPIC, volume and BPM controllers | UI events |
| Python client → engine | Zone and volume values reach the engine as floats, validated and clamped engine-side | OSC float control values |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-03-01 | Tampering | `OSCdef(\pp_epic)` input (no arg, string, NaN, out of range) | medium | mitigate | `isNumber.not or: { raw.isNaN }` guard and `.asFloat.clip(0, 100)` (`supercollider/main.scd:389-392`); smoke "epic malformed ignored" + 7-entry clamp table | closed |
| T-03-02 | Spoofing | non-loopback sender on `/pp/epic` | medium | mitigate | `srcID: NetAddr("127.0.0.1", nil)` (`main.scd:397`); smoke B5 "loopback-only" extended to `/pp/epic` | closed |
| T-03-03 | Denial of Service | node/bus leak from persistent FX synths and buses on re-evaluation | medium | mitigate | Teardown frees `~ppFxGroup`, `~ppFxBus`, `~ppEpicBus`, `~ppEpicSmoothBus` (`main.scd:57-62`); smoke "fx re-evaluation" | closed |
| T-03-04 | Tampering | EPIC drive / FX output bypassing the limiter | medium | mitigate | `\ppFx` writes `~ppFxBus`, read only by `\ppMaster` (`main.scd:171,184`), which ends in `Limiter.ar` (`main.scd:119`); limiter checks run at EPIC 100 | closed |
| T-03-05 | Denial of Service | CPU competition with Zwift from the always-on FX | low | mitigate | One shared `\ppFx` with exactly one `FreeVerb2` (grep count 1); 60-minute soak deferred to Phase 4 (ENG-03) | closed |
| T-03-06 | Denial of Service | `osc_client.py` crash on extreme values (1e300, 10**20) | low | mitigate | All four `send_*` methods catch `(OSError, OverflowError, BuildError)` and return False (`python_app/osc_client.py:55,72,86,100`); unit tests | closed |
| T-03-07 | Tampering | `EpicController.select_zone` with a name outside the preset map | low | mitigate | Raises `ValueError` before any state change or send (`python_app/bpm_logic.py:279`); buttons built only from `zone_names`; unit tests | closed |
| T-03-08 | Denial of Service | arrow keys nudging BPM while the rider types (WR-01) | low | mitigate | Entry-scoped `"break"` bindings for Up/Down/Shift-Up/Shift-Down (`python_app/view.py:114-117`); Tk test `test_arrow_keys_do_not_nudge_while_entry_focused` | closed |
| T-03-09 | Tampering | zone values outside the engine's 0–100 range | low | accept | Preset constants within 0–100 (unit-tested); engine clamps independently (T-03-01) | closed |
| T-03-10 | Tampering | `OSCdef(\pp_volume)` input (no arg, string, NaN, out of range) | medium | mitigate | `isNumber.not or: { raw.isNaN }` guard and `.asFloat.clip(0, 100)` (`main.scd:405-408`); smoke "volume malformed ignored" + 6-entry clamp table | closed |
| T-03-11 | Spoofing | non-loopback sender on `/pp/volume` | medium | mitigate | `srcID: NetAddr("127.0.0.1", nil)` (`main.scd:413`); smoke B5 "loopback-only" extended to `/pp/volume` | closed |
| T-03-12 | Tampering | max EPIC + max volume exceeding the ceiling, or volume applied after the limiter (hearing safety) | high | mitigate | Volume multiplied inside `\ppMaster` before `Limiter.ar(sig, 0.891251, 0.01)` (`main.scd:117-119`); taper caps gain at 1.0; smoke "max epic max volume no clip" measured peak 0.5066 ≤ 0.892 through the real Python path | closed |
| T-03-13 | Denial of Service | volume bus leak on re-evaluation | low | mitigate | Teardown frees `~ppVolumeBus` (`main.scd:63`); smoke "volume re-evaluation" | closed |
| T-03-14 | Denial of Service | volume slider drags flooding the engine with OSC | low | mitigate | `VolumeController.slider_moved` never sends; one send per release; unit tests + Tk `test_volume_drag_then_release_sends_once` | closed |
| T-03-15 | Tampering | non-finite or out-of-range volume reaching the controller | low | mitigate | `clamp_volume` raises on non-finite and clamps 0–100 (`bpm_logic.py:291-301`); bounded `Scale`; engine clamps independently (T-03-10) | closed |
| T-03-16 | Tampering | app launch jumping the engine to full volume (hearing safety) | medium | mitigate | `VOLUME_DEFAULT = 80` < `VOLUME_MAX = 100` (`python_app/config.py:38-39`, unit-tested); limiter still holds the ceiling at 100 (T-03-12) | closed |
| T-03-SC | Tampering | package installs (supply chain) | low | accept | No packages or quarks added this phase (no `requirements*.txt` change, no `Quarks` use); all UGens stock SuperCollider; `tkinter.font` is stdlib | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-03-01 | T-03-09 | Zone presets are compile-time constants within 0–100, and the engine clamps every `/pp/epic` value independently | plan threat model (03-02) | 2026-10-09 |
| AR-03-02 | T-03-SC | Phase adds no third-party packages or quarks; only stock SuperCollider UGens and Python stdlib | plan threat models (03-01..03-04) | 2026-10-09 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-09 | 17 | 17 | 0 | secure-phase (L1 grep verification, orchestrator) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-09
