---
phase: "01"
slug: "tempo-link-skeleton"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-10-08"
---

# Phase 01 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from `01-RESEARCH.md` § Validation Architecture. Paths below are the research-proposed layout (`python_app/`, `supercollider/`); if the plans settle on a different layout, the plans are authoritative and validate-phase reconciles this file.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 8.x (Python side); headless sclang smoke test (SuperCollider side) |
| **Config file** | none — Wave 0 installs pytest into `.venv` |
| **Quick run command** | `.venv/bin/pytest python_app/tests/ -x -q` |
| **Full suite command** | `.venv/bin/pytest python_app/tests/ -q` plus `QT_QPA_PLATFORM=offscreen /Applications/SuperCollider.app/Contents/MacOS/sclang supercollider/smoke_test.scd` |
| **Estimated runtime** | ~5 seconds (pytest), ~20 seconds (headless sclang boot + smoke test) |

---

## Sampling Rate

- **After every task commit:** Run `.venv/bin/pytest python_app/tests/ -x -q`
- **After every plan wave:** Run the full suite (pytest + headless sclang smoke test)
- **Before `/gsd-verify-work`:** Full suite must be green, and both manual checks (D-17 limiter, end-to-end listening) performed
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| _Populated once PLAN.md task IDs exist (validate-phase)_ | | | | | | | | | |

Requirement-level test map (from research, pending task assignment):

| Requirement | Behavior | Test Type | Automated Command | File Exists |
|-------------|----------|-----------|-------------------|-------------|
| GUI-01 / D-10 | Entry applies on Enter/focus-out; invalid text reverts; out-of-range snaps to 60/180 | unit | `.venv/bin/pytest python_app/tests/test_clamp.py -x` | ❌ W0 |
| GUI-01 | Slider, entry and nudge buttons stay in sync | unit | `.venv/bin/pytest python_app/tests/test_sync.py -x` | ❌ W0 |
| LINK-01 | Slider sends only on release; nudge/arrow sends debounced to one `/pp/bpm` after ~150 ms | unit (mocked socket) | `.venv/bin/pytest python_app/tests/test_osc_client.py -x` | ❌ W0 |
| GUI-04 | Tk compatibility check exits non-zero with a clear message on incompatible Tk | unit (monkeypatched `TkVersion` / import) | `.venv/bin/pytest python_app/tests/test_tkcheck.py -x` | ❌ W0 |
| ENG-04 | `main.scd` waits for boot, posts the OSC port, autostarts the loop | headless smoke test | `QT_QPA_PLATFORM=offscreen /Applications/SuperCollider.app/Contents/MacOS/sclang supercollider/smoke_test.scd` | ❌ W0 |
| TEMPO-03 | Engine clamps raw out-of-range `/pp/bpm` to 60–180 | helper script + listening | `.venv/bin/python python_app/tests/send_raw_bpm.py 300` | ❌ W0 |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `python_app/tests/test_clamp.py` — GUI-01 / D-10 (entry parsing, clamp to 60/180, revert on invalid)
- [ ] `python_app/tests/test_sync.py` — GUI-01 (slider/entry/nudge stay in sync)
- [ ] `python_app/tests/test_osc_client.py` — LINK-01 (release-only send, debounce), mocked-socket pattern from `pythonosc/test/test_udp_client.py`
- [ ] `python_app/tests/test_tkcheck.py` — GUI-04 (compatibility gate logic)
- [ ] `python_app/tests/send_raw_bpm.py` — TEMPO-03 helper: sends raw out-of-range `/pp/bpm`, bypassing the GUI (D-08)
- [ ] `supercollider/smoke_test.scd` — ENG-04 / D-18 headless boot and compile check
- [ ] pytest installed in `.venv` (dev-only, e.g. `requirements-dev.txt`)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Master limiter holds peaks at the −1 dBFS ceiling under deliberately hot gain | ENG-02 | D-17: no automated limiter test required; judged on the SC level meter | Raise `~preGain` in `main.scd`, re-evaluate, watch the SC meter peaks stay at the ceiling with no clipping |
| Loop audibly changes tempo when BPM is set from slider, entry or nudge buttons | GUI-01, LINK-01 | Audible musical result; tests cover logic, not sound | Run `main.scd` in the SC IDE, launch `./run.sh`, change BPM with each control, listen for the tempo change on the next beat |
| Engine clamps out-of-range BPM | TEMPO-03 | Clamp is observed in the running engine's tempo/post window | Send `300` and `10` with `send_raw_bpm.py`; confirm the engine posts/plays at 180 and 60 |
| Window opens normally under Tk 9.0.3 and the "On top" toggle floats it over Zwift | GUI-04, D-12 | Real window-manager behavior | Launch via `./run.sh`, toggle "On top", confirm it stays above a full-screen app |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
