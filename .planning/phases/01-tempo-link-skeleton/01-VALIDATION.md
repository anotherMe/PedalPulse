---
phase: "01"
slug: "tempo-link-skeleton"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: validated
nyquist_compliant: true
wave_0_complete: true
created: "2026-10-08"
validated: "2026-10-09"
---

# Phase 01 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from `01-RESEARCH.md` § Validation Architecture, then reconciled by validate-phase against the executed plans (01-01, 01-02, 01-03), which are authoritative. The research-proposed `test_clamp.py` / `test_sync.py` were realized as `test_bpm_logic.py` / `test_view_tk.py`.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 8.4.2 (Python side, in `.venv`); headless sclang smoke test (SuperCollider side) |
| **Config file** | none — `python_app/tests/conftest.py` puts `python_app/` on `sys.path`; `./run.sh --setup` installs `python_app/requirements-dev.txt` into `.venv` |
| **Quick run command** | `.venv/bin/pytest python_app/tests/ -x -q` |
| **Full suite command** | `.venv/bin/pytest python_app/tests/ -q` plus `bash scripts/smoke_test.sh` (runs `/Applications/SuperCollider.app/Contents/MacOS/sclang -D supercollider/smoke_test.scd` headless on an isolated, muted server at port 57140; `QT_QPA_PLATFORM` is deliberately unset — the offscreen plugin aborts sclang 3.14.1 on macOS with exit 134) |
| **Estimated runtime** | ~3 seconds (pytest, 66 tests); ~30–60 seconds (headless sclang boot + 19-check smoke test) |

---

## Sampling Rate

- **After every task commit:** Run `.venv/bin/pytest python_app/tests/ -x -q`
- **After every plan wave:** Run the full suite (pytest + headless sclang smoke test)
- **Before `/gsd-verify-work`:** Full suite must be green, and the manual checks below performed
- **Max feedback latency:** 30 seconds (pytest); the sclang smoke test is a per-wave sample

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-T1 | 01-01 | 1 | ENG-04, LINK-01, TEMPO-03 | T-01-01, T-01-02, T-01-05 | `/pp/bpm` OSCdef accepts loopback senders only; posted port matches `NetAddr.langPort` | headless smoke (tracer) | `bash scripts/smoke_test.sh` (checks `boot ready`, `port posted`, `initial tempo 120`, `python tempo 140`) | ✅ | ✅ green |
| 01-01-T2 | 01-01 | 1 | ENG-02, ENG-04, TEMPO-03, LINK-01 | T-01-01, T-01-02, T-01-03, T-01-04 | Clamp 60–180, malformed messages ignored, latest-wins single apply per beat, node count bounded, limiter ceiling with no bypass | headless smoke (engine contract) | `bash scripts/smoke_test.sh && test "$(grep -c 'CHECK OK:' "${TMPDIR:-/tmp}/pedalpulse-smoke.log")" -ge 18` | ✅ | ✅ green (19/19) |
| 01-02-T1 | 01-02 | 2 | — (supply-chain gate) | — | pytest 8.4.2 confirmed genuine before install | checkpoint:human-verify (blocking-human) | — (human-approved 2026-10-08) | n/a | ✅ approved |
| 01-02-T2 | 01-02 | 2 | GUI-04 | T-01-06 | `run.sh` touches nothing outside the project (no sudo/brew/--user) | unit + CLI | `./run.sh --setup && .venv/bin/pytest python_app/tests -q`; `python3.12 python_app/tkcheck.py` exits 1 with the `./run.sh` fix hint | ✅ | ✅ green |
| 01-02-T3 | 01-02 | 2 | GUI-01, LINK-01, GUI-04 | T-01-07, T-01-08, T-01-09 | Release-only slider send, 150 ms nudge debounce, `send_bpm` never raises when nothing listens | unit (fake scheduler, real/mocked socket) + launch | `.venv/bin/pytest python_app/tests -q`; `timeout 30 ./run.sh --port 57199 --exit-after 800` | ✅ | ✅ green |
| 01-03-T1 | 01-03 | 3 | GUI-01, LINK-01 | T-01-10, T-01-01 | Entry text parsed, invalid input reverts, out-of-range snaps to 60/180, commit cancels a pending nudge send | unit (TDD) | `.venv/bin/pytest python_app/tests/test_bpm_logic.py -q` | ✅ | ✅ green |
| 01-03-T2 | 01-03 | 3 | GUI-01, LINK-01 | T-01-11 | Arrow-key auto-repeat routes through the debounced nudge path | Tk widget smoke (real Tk 9 widgets) + launch | `.venv/bin/pytest python_app/tests -q`; `timeout 30 ./run.sh --port 57199 --exit-after 800` | ✅ | ✅ green |

Requirement-level test map:

| Requirement | Behavior | Test Type | Automated Command | File Exists |
|-------------|----------|-----------|-------------------|-------------|
| ENG-02 | Master limiter holds peaks below the −1 dBFS ceiling under hot gain and is never bypassed | headless smoke | `bash scripts/smoke_test.sh` (`limiter no bypass`, `limiter ceiling`) | ✅ `supercollider/smoke_test.scd` |
| ENG-04 | `main.scd` waits for boot, posts the OSC port, autostarts the loop, re-evaluates idempotently | headless smoke | `bash scripts/smoke_test.sh` (`boot ready`, `port posted`, `initial tempo 120`, `re-evaluation`) | ✅ `supercollider/smoke_test.scd`, `scripts/smoke_test.sh` |
| TEMPO-03 | Engine clamps raw out-of-range `/pp/bpm` to 60–180 | headless smoke (raw sends via the `osc_client.py` CLI path) | `bash scripts/smoke_test.sh` (`clamp 300->180`, `clamp 10->60`, `clamp 59->60`, `clamp 181->180`, `clamp 60`, `clamp 180`, `float 150.5`) | ✅ `supercollider/smoke_test.scd` |
| GUI-01 / D-10 | Entry applies on Enter/focus-out; invalid text reverts; out-of-range snaps to 60/180; slider, entry, nudge buttons and arrow keys stay in sync | unit + Tk widget smoke | `.venv/bin/pytest python_app/tests/test_bpm_logic.py python_app/tests/test_view_tk.py -q` | ✅ `python_app/tests/test_bpm_logic.py`, `python_app/tests/test_view_tk.py` |
| GUI-04 | Tk compatibility check passes Tk 8.6/9.x and exits 1 with a clear fix message on missing `_tkinter` or Tk < 8.6 | unit (monkeypatched `TkVersion` / import) + real python3.12 subprocess | `.venv/bin/pytest python_app/tests/test_tkcheck.py -q` | ✅ `python_app/tests/test_tkcheck.py` |
| LINK-01 | Slider sends only on release; nudges/arrow keys debounce to one `/pp/bpm` after ~150 ms; messages reach sclang and retempo the clock; latest value wins | unit (fake scheduler, real/mocked socket) + headless smoke | `.venv/bin/pytest python_app/tests/test_bpm_logic.py python_app/tests/test_osc_client.py -q`; `bash scripts/smoke_test.sh` (`python tempo 140`, `whole-beat apply`, `latest wins`, `malformed ignored`, `loopback-only`) | ✅ `python_app/tests/test_osc_client.py`, `python_app/tests/test_bpm_logic.py` |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `python_app/tests/test_bpm_logic.py` — GUI-01 / D-10 (entry parsing, clamp to 60/180, revert on invalid) and LINK-01 (release-only send, debounce) — realizes the research-proposed `test_clamp.py`
- [x] `python_app/tests/test_view_tk.py` — GUI-01 (slider/entry/nudge/arrow keys stay in sync under real Tk 9 widgets) — realizes the research-proposed `test_sync.py`
- [x] `python_app/tests/test_osc_client.py` — LINK-01 (wire format over a real socket, mocked-socket destination, no raise on unused port, False on OSError)
- [x] `python_app/tests/test_tkcheck.py` — GUI-04 (compatibility gate logic)
- [x] `python_app/osc_client.py` CLI (`python_app/osc_client.py BPM [BPM ...] [--port P]`) — TEMPO-03 helper: sends raw out-of-range `/pp/bpm`, bypassing the GUI (D-08)
- [x] `supercollider/smoke_test.scd` + `scripts/smoke_test.sh` — ENG-04 / D-18 headless boot and engine-contract check (19 named checks)
- [x] pytest installed in `.venv` (dev-only, `python_app/requirements-dev.txt`, human-approved package legitimacy gate)

---

## Manual-Only Verifications

These are supplementary listening and window-manager judgments. Every requirement above also has automated coverage.

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Master limiter sounds clean (no audible clipping) under deliberately hot gain | ENG-02 | D-17: the ceiling is now asserted numerically by the smoke test; the audible judgment stays on the SC level meter | Raise `~preGain` in `main.scd`, re-evaluate, watch the SC meter peaks stay at the ceiling with no clipping |
| Loop audibly changes tempo when BPM is set from slider, entry, nudge buttons or arrow keys | GUI-01, LINK-01 | Audible musical result; tests cover logic and message delivery, not sound | Run `main.scd` in the SC IDE, launch `./run.sh`, change BPM with each control, listen for the tempo change on the next beat |
| Engine clamps out-of-range BPM in the live engine | TEMPO-03 | Confirms the automated clamp checks against the user's real running engine | Send `300` and `10` with `.venv/bin/python python_app/osc_client.py`; confirm the engine posts/plays at 180 and 60 |
| Window opens normally under Tk 9.0.3 and the "On top" toggle floats it over Zwift | GUI-04, D-12 | Real window-manager behavior over a full-screen app | Launch via `./run.sh`, toggle "On top", confirm it stays above a full-screen app |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (01-02-T1 is a human supply-chain gate, not a behavior)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s (pytest ~3 s)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** validated 2026-10-09 (validate-phase audit: 66/66 pytest, 19/19 smoke checks, `SMOKE PASS`)

## Validation Audit 2026-10-09

| Metric | Count |
|---|---|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |
