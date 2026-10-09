---
phase: "03"
slug: "epic-zones-volume"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-10-09"
---

# Phase 03 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from `03-RESEARCH.md` § Validation Architecture. Paths below are the research-proposed layout. If the plans settle on a different layout, the plans are authoritative and validate-phase reconciles this file.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 8.x (Python side, already in `.venv`); headless sclang smoke-test harness (`scripts/smoke_test.sh` → `supercollider/smoke_test.scd`, isolated muted server on port 57140) |
| **Config file** | none — existing Phase 1/2 infrastructure covers it |
| **Quick run command** | `.venv/bin/pytest python_app/tests -x -q` |
| **Full suite command** | `.venv/bin/pytest python_app/tests -q && bash scripts/smoke_test.sh` |
| **Estimated runtime** | ~3–5 seconds (pytest), ~90–110 seconds (headless sclang boot + smoke test: the 36 Phase 2 checks measure ~75 s, plus new EPIC checks that must wait out the ~1.5 s EPIC lag and a multi-second peak measurement) |

Do not set `QT_QPA_PLATFORM=offscreen`. The offscreen Qt plugin is missing from the SuperCollider 3.14.1 macOS bundle and aborts sclang. `scripts/smoke_test.sh` already unsets it. If the new checks push the run past the current smoke watchdog (240 s) or `scripts/smoke_test.sh` timeout (270 s), raise them in the same task that adds the checks.

---

## Sampling Rate

- **After every task commit:** Run `.venv/bin/pytest python_app/tests -x -q` (engine tasks also run `bash scripts/smoke_test.sh`)
- **After every plan wave:** Run the full suite (pytest + extended headless sclang smoke test)
- **Before `/gsd-verify-work`:** Full suite must be green, and the manual listening checks below performed
- **Max feedback latency:** 60 seconds for the per-task quick run (pytest). The full engine smoke run is expected to exceed this (~90–110 s) because the EPIC glide and peak checks must wait out real lag windows; that is a sampling-cost note, not a coverage gap (same as Phase 2)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| _Populated once PLAN.md task IDs exist (validate-phase)_ | | | | | | | | | |

Requirement-level test map (from research, pending task assignment):

| Requirement | Behavior | Test Type | Automated Command | File Exists |
|-------------|----------|-----------|-------------------|-------------|
| EPIC-01 | `/pp/epic` 0 vs 100 produces a measurable change in the post-FX signal, not just an updated `~epic` / `~ppEpicBus` value | headless smoke test | `bash scripts/smoke_test.sh` (probe the FX output at EPIC=0 vs EPIC=100 with the existing `\ppPeakProbe` / `measurePeak` idiom, assert a measurable difference) | ❌ W0 — extend `supercollider/smoke_test.scd` |
| EPIC-02 | A new EPIC value glides (monotone convergence over the lag window), never jumps | headless smoke test | `bash scripts/smoke_test.sh` (send `/pp/epic 100` from rest, poll the smoothed EPIC bus at intervals, assert monotone convergence and no instant jump) | ❌ W0 |
| EPIC-03 | Each of the five zone names maps to its documented EPIC value and is sent once per real change | unit | `.venv/bin/pytest python_app/tests/test_epic_logic.py -x` | ❌ W0 — new file (same style as `test_play_logic.py`) |
| EPIC-03 (OSC wire format) | `send_epic` delivers a decodable `/pp/epic <float>` | unit | `.venv/bin/pytest python_app/tests/test_osc_client.py -x` | ✅ extend existing file |
| EPIC-01/02 (engine input) | `/pp/epic` and `/pp/volume` clamp to 0–100, ignore malformed args, and accept loopback senders only | headless smoke test | `bash scripts/smoke_test.sh` | ❌ W0 |
| GUI-03 (Python logic) | `VolumeController` sends `/pp/volume` on release (not every drag tick), clamps 0–100, sends the initial value once | unit | `.venv/bin/pytest python_app/tests/test_volume_logic.py -x` | ❌ W0 — new file (same style as `test_bpm_logic.py`) |
| GUI-03 (OSC wire format) | `send_volume` delivers a decodable `/pp/volume <float>` | unit | `.venv/bin/pytest python_app/tests/test_osc_client.py -x` | ✅ extend existing file |
| GUI-03 + SC4 (no clip) | At `/pp/epic 100` + `/pp/volume 100` (VO2 + max volume), the master output peak never exceeds the limiter ceiling (0.891251) plus a small tolerance | headless smoke test | `bash scripts/smoke_test.sh` (reuse `measurePeak` on bus 0 after both lag windows, assert `<= 0.892`) | ❌ W0 — extend the existing limiter-style check |
| EPIC-03 / GUI-03 (widgets) | Clicking a zone button highlights it and sends its EPIC value; the volume slider sends on release | Tk widget test | `.venv/bin/pytest python_app/tests/test_view_tk.py -x` | ✅ extend existing file |
| Carry-over WR-01 (Phase 1) | Up/Down arrow keys do not nudge BPM while the BPM entry (or another text widget) has focus | Tk widget test | `.venv/bin/pytest python_app/tests/test_view_tk.py -x` | ✅ extend existing file |
| Re-evaluation safety | Re-evaluating `main.scd` frees and rebuilds the new EPIC buses / FX group / smoother / FX synth without leaking nodes or buses | headless smoke test | `bash scripts/smoke_test.sh` (extend the existing "re-evaluation" check) | ❌ W0 |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `supercollider/smoke_test.scd` — extend with: EPIC-produces-measurable-change, EPIC-glides-not-jumps, `/pp/epic` and `/pp/volume` clamp/malformed/loopback checks, max-EPIC-max-volume-never-clips (reusing `measurePeak`), and re-evaluation teardown covering the new buses/groups/synths
- [ ] `python_app/tests/test_epic_logic.py` — new file covering the EPIC zone controller (EPIC-03)
- [ ] `python_app/tests/test_volume_logic.py` — new file covering the volume controller and its clamp (GUI-03)
- [ ] `python_app/tests/test_osc_client.py` — extend with `send_epic` / `send_volume` tests (same style as the existing `send_bpm` / `send_play` tests)
- [ ] `python_app/tests/test_view_tk.py` — extend with zone-button highlight/send, volume-slider send-on-release, and the WR-01 focus-guard tests
- [ ] `python_app/config.py` — add the `/pp/epic` and `/pp/volume` address constants plus the zone preset and volume range/default constants
- No new framework installs: pytest and the smoke-test harness already exist from Phase 1

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Moving up the zones sounds brighter and more energetic, with cutoff, drive, reverb/delay and richness moving together | EPIC-01 | No automated check can judge "brighter and more energetic" | Run `supercollider/main.scd`, launch `./run.sh`, click through all five zones ascending then descending, and listen at each step |
| Switching zones glides with no stepping, zipper noise or clicks | EPIC-02 | The smoke test proves the mechanism (monotone, converges), not how it sounds | Click between distant zones, then click several zones back to back before the previous glide finishes, and listen for steps, zipper noise or clicks |
| Volume changes loudness smoothly, and VO2 + maximum volume never audibly distorts or clips | GUI-03 | Smoothness and audible distortion are perceptual; the smoke test covers the peak ceiling | Drag the volume slider across its range, then select VO2, set volume to maximum and listen for at least one full 8-bar cycle |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
