---
phase: "02"
slug: "full-groove-smooth-tempo"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-10-09"
---

# Phase 02 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from `02-RESEARCH.md` § Validation Architecture. Paths below are the research-proposed layout. If the plans settle on a different layout, the plans are authoritative and validate-phase reconciles this file.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 8.x (Python side, already in `.venv` from Phase 1); headless sclang smoke-test harness (`scripts/smoke_test.sh` → `supercollider/smoke_test.scd`, isolated muted server on port 57140) |
| **Config file** | none — existing Phase 1 infrastructure covers it |
| **Quick run command** | `.venv/bin/pytest python_app/tests -x -q` |
| **Full suite command** | `.venv/bin/pytest python_app/tests -q && bash scripts/smoke_test.sh` |
| **Estimated runtime** | ~5 seconds (pytest), ~30–60 seconds (headless sclang boot + smoke test, including the glide and Stop/Start timing checks) |

Do not set `QT_QPA_PLATFORM=offscreen`. The offscreen Qt plugin is missing from the SuperCollider 3.14.1 macOS bundle and aborts sclang. `scripts/smoke_test.sh` already unsets it.

---

## Sampling Rate

- **After every task commit:** Run `.venv/bin/pytest python_app/tests -x -q` (engine tasks also run `bash scripts/smoke_test.sh`)
- **After every plan wave:** Run the full suite (pytest + extended headless sclang smoke test)
- **Before `/gsd-verify-work`:** Full suite must be green, and the manual listening checks below performed
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| _Populated once PLAN.md task IDs exist (validate-phase)_ | | | | | | | | | |

Requirement-level test map (from research, pending task assignment):

| Requirement | Behavior | Test Type | Automated Command | File Exists |
|-------------|----------|-----------|-------------------|-------------|
| ENG-01 | All groove layers (kick, hat, clap, bass, arp, pad) play continuously on the one `~clock` | headless smoke test | `bash scripts/smoke_test.sh` (assert every layer's `Pbindef` reports `.isPlaying` after boot) | ❌ W0 — extend `supercollider/smoke_test.scd` |
| TEMPO-01 | A new BPM glides over ~1–2 bars, starts on a beat boundary, and lands on the target | headless smoke test | `bash scripts/smoke_test.sh` (poll `~clock.tempo`: monotone toward target, lands within ramp length ± tolerance, first change on a whole beat) | ❌ W0 |
| TEMPO-02 | A mid-glide retarget continues from the current tempo with no restart or jump | headless smoke test | `bash scripts/smoke_test.sh` (retarget mid-ramp, trajectory continuous within one step, converges on the new target) | ❌ W0 |
| GUI-02 (engine) | `/pp/play 0` stops all layers and leaves zero instrument synths after the release time; `/pp/play 1` restarts quantized to the bar; repeated Start/Stop is idempotent | headless smoke test | `bash scripts/smoke_test.sh` | ❌ W0 |
| GUI-02 (Assumption A3) | `\gate, 0` broadcast to the instrument group does not error on synths without a `gate` control | headless smoke test | `bash scripts/smoke_test.sh` | ❌ W0 |
| GUI-02 (Python logic) | Play/Stop controller sends only on a real state change, stays idempotent, and sends the initial state once | unit | `.venv/bin/pytest python_app/tests/test_play_logic.py -x` | ❌ W0 — new file |
| GUI-02 (OSC wire format) | `send_play` delivers a decodable `/pp/play <int>` | unit (real loopback socket / mocked socket, same as the existing `send_bpm` tests) | `.venv/bin/pytest python_app/tests/test_osc_client.py -x` | ✅ extend existing file |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `supercollider/smoke_test.scd` — extend with: all-layers-playing, glide reaches target on a monotone trajectory, beat-boundary start, mid-glide retarget continuity, Stop leaves zero instrument synths after release, Start is bar-quantized and idempotent, and the Group `\gate` broadcast does not error (Assumption A3)
- [ ] `python_app/tests/test_play_logic.py` — new file covering the Play/Stop controller (same style as `test_bpm_logic.py`)
- [ ] `python_app/tests/test_osc_client.py` — extend with `send_play` tests (same style as the existing `send_bpm` tests)
- [ ] `python_app/config.py` — add the `/pp/play` address constant
- No new framework installs: pytest and the smoke-test harness already exist from Phase 1

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| The groove sounds like melodic techno / progressive trance (drums, bass, arp and pad together) | ENG-01 | No automated check can judge musical quality | Run `supercollider/main.scd` in the SuperCollider IDE, launch `./run.sh`, and listen for at least one full 8-bar cycle |
| The glide sounds smooth, with no audible jolt and every layer in time | TEMPO-01, TEMPO-02 | The smoke test proves the mechanism (monotone, continuous, converges), not how it sounds | Move the BPM slider between distant values, then retarget quickly back and forth mid-glide, and listen for jumps, stutters or layers drifting apart |
| Stop is clean (no hanging pad or bass notes, no click) and Start brings the full groove back in time | GUI-02 | Click and tail quality is perceptual | Press Stop during a held pad chord and listen to the tail. Press Start and check that all layers re-enter together on the bar |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
