---
phase: "01"
slug: "tempo-link-skeleton"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-09"
---

# Phase 01 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> Register authored at plan time (`<threat_model>` blocks in 01-01, 01-02, 01-03 PLAN.md). Verified at ASVS L1 (grep-depth evidence against the implementation, plus the passing pytest suite and headless smoke test). No SUMMARY raised threat flags.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| UDP network → sclang language port | sclang listens on all interfaces (`*:57120`); any local process or LAN host can send `/pp/bpm` | OSC control messages (untrusted, low sensitivity) |
| OSC argument → engine clock | Untrusted argument type and value reach `~clock.tempo` | Numeric tempo value |
| Engine → speakers/headphones | Uncontrolled output level is a hearing-safety risk for a rider on headphones | Audio signal level |
| PyPI → `.venv` | Third-party code enters the project through pip | python-osc 1.10.2, pytest 8.4.2 (dev-only) |
| `run.sh` → host system | The launcher runs with the user's privileges | Filesystem writes (project-local `.venv` only) |
| GUI events → UDP sender | Slider drags, button clicks and held keys can produce bursts of sends | `/pp/bpm` floats to 127.0.0.1 |
| Keyboard text → BPM parser | Arbitrary typed text reaches the value sent to the engine | User-typed text |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-01-01 | Tampering / DoS | `OSCdef(\pp_bpm)` in `supercollider/main.scd` | high | mitigate | Non-numeric and NaN args rejected (`main.scd:113` `isNumber` / `isNaN`), then `.clip(60, 180)` before use (`main.scd:116`). Smoke checks `malformed ignored`, `clamp 300->180`, `clamp 10->60`, `clamp 59->60`, `clamp 181->180` | closed |
| T-01-02 | Spoofing | `OSCdef(\pp_bpm)` srcID | medium | mitigate | `srcID: NetAddr("127.0.0.1", nil)` (`main.scd:131`) accepts loopback senders only. Smoke check `loopback-only` passed as `CHECK OK` (not SKIP) on 2026-10-09: a send from the LAN address produced no apply | closed |
| T-01-03 | Denial of Service | tempo apply scheduling | medium | mitigate | Latest-wins single pending apply via `~ppApplyScheduled` (`main.scd:119-126`): a burst costs one scheduled apply per beat. Smoke check `latest wins` | closed |
| T-01-04 | Denial of Service (hearing safety) | master bus, `\ppMaster` | high | mitigate | Instruments write only to `~ppMixBus` (`main.scd:81,90,103`); `Limiter.ar(sig, 0.891251, 0.01)` is the last stage before `Out.ar` (`main.scd:61`). Smoke checks `limiter no bypass` (silence at preGain 0) and `limiter ceiling` (peak ≤ 0.90 at preGain 8); automated runs mute hardware (`smoke_test.scd:86` `s.volume.mute`) | closed |
| T-01-05 | Information Disclosure | posted port line (`main.scd:133`) | low | accept | Posts only the local UDP port number to the user's own post window; no secrets exist in this system. See accepted risks | closed |
| T-01-SC (01-01) | Tampering (supply chain) | pip install of `python-osc==1.10.2` | high | mitigate | Pinned in `python_app/requirements.txt`; audited **Approved** in `01-RESEARCH.md` Package Legitimacy Audit (automated SUS verdict independently refuted: repo `attwad/python-osc`, 12+ years, ~86k downloads/month) | closed |
| T-01-06 | Elevation of Privilege / Tampering | `run.sh` | medium | mitigate | Installs only through `.venv/bin/pip` (`run.sh:25,32`); no `sudo`, no `--user`, no package-manager invocation (`brew` appears only inside an `echo` fix hint, `run.sh:18`). Interpreter chosen by one variable, `PEDALPULSE_PYTHON` (default python3.13) | closed |
| T-01-07 | Denial of Service | slider and nudge send paths (`bpm_logic.py`) | medium | mitigate | Slider sends only on `<ButtonRelease-1>` (`view.py:51`); nudges go through the cancel-and-reschedule `Debouncer` (`bpm_logic.py:49`) at `NUDGE_DEBOUNCE_MS = 150` (`config.py:13`), wired to `root.after` / `root.after_cancel` (`main.py:49`); unchanged values at the bounds send nothing. Covered by `test_bpm_logic.py` | closed |
| T-01-08 | Denial of Service (availability) | `OscClient.send_bpm` | low | mitigate | `except OSError` → `return False` (`osc_client.py:41-43`); sends to an absent engine never raise. Covered by `test_osc_client.py` (`test_send_bpm_returns_false_on_oserror`, `test_send_bpm_to_unused_port_returns_true_without_raising`) | closed |
| T-01-09 | Spoofing (misdirected control) | `config.OSC_HOST` / `--port` | low | accept | Target is the loopback constant `OSC_HOST = "127.0.0.1"` (`config.py:7`) shown in the status line; `--port` is the user's own override on a single-user machine. See accepted risks | closed |
| T-01-SC (01-02) | Tampering (supply chain) | pip install of `pytest==8.4.2` | high | mitigate | Pinned in `python_app/requirements-dev.txt` (dev-only); blocking-human legitimacy checkpoint (01-02 Task 1) approved by the user on 2026-10-08 before any install, after the orchestrator confirmed name, source repo `github.com/pytest-dev/pytest` and the 8.4.2 release against the live PyPI API | closed |
| T-01-10 | Tampering | `parse_bpm_entry` (`bpm_logic.py`) | low | mitigate | Text parsed only with `float()` plus `math.isfinite` (`bpm_logic.py:23,44`) and `clamp_bpm`; no `eval`/`exec` anywhere in `python_app/`. Invalid input reverts without a send; the engine re-validates independently (T-01-01). Covered by `test_bpm_logic.py` | closed |
| T-01-11 | Denial of Service | arrow-key auto-repeat → `BpmController.nudge` | medium | mitigate | `<Up>`/`<Down>`/`<Shift-Up>`/`<Shift-Down>` (`view.py:109-112`) route through `handle_nudge_key` → `controller.nudge` (`view.py:138-140`), sharing the 150 ms debouncer, so a held key yields one send after release. Covered by `test_view_tk.py` | closed |
| T-01-SC (01-03) | Tampering (supply chain) | package installs | low | accept | Plan 01-03 installs no packages; pytest 8.4.2 and python-osc 1.10.2 were gated and pinned in Plans 01 and 02. See accepted risks | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-01-01 | T-01-05 | The posted line discloses only the local UDP port number, to the user's own SuperCollider post window. The system holds no secrets | Plan-time disposition (01-01 threat model) | 2026-10-08 |
| AR-01-02 | T-01-09 | The OSC target is a loopback constant; `--port` is an explicit override by the only user of a single-user machine | Plan-time disposition (01-02 threat model) | 2026-10-08 |
| AR-01-03 | T-01-SC (01-03) | Plan 01-03 installs nothing; the supply-chain exposure for this phase is fully covered by the pinned, gated installs in 01-01 and 01-02 | Plan-time disposition (01-03 threat model) | 2026-10-08 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-09 | 14 | 14 | 0 | secure-phase (orchestrator, ASVS L1 short-circuit — register authored at plan time, 0 open; auditor not required) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-09
