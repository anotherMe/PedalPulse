---
phase: "02"
slug: "full-groove-smooth-tempo"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: validated
nyquist_compliant: true
wave_0_complete: true
created: "2026-10-09"
validated: "2026-10-09"
---

# Phase 02 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from `02-RESEARCH.md` § Validation Architecture, then reconciled by validate-phase against the executed plans (02-01 to 02-04) and their SUMMARYs. The plans are authoritative.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | pytest 8.x (Python side, already in `.venv` from Phase 1); headless sclang smoke-test harness (`scripts/smoke_test.sh` → `supercollider/smoke_test.scd`, isolated muted server on port 57140) |
| **Config file** | none — existing Phase 1 infrastructure covers it |
| **Quick run command** | `.venv/bin/pytest python_app/tests -x -q` |
| **Full suite command** | `.venv/bin/pytest python_app/tests -q && bash scripts/smoke_test.sh` |
| **Measured runtime** | ~3 seconds (pytest, 87 tests), ~75 seconds (headless sclang boot + 36-check smoke test, including the glide and Stop/Start timing checks). Smoke watchdog 240 s, `scripts/smoke_test.sh` timeout 270 s (raised by 02-03 for the glide checks) |

Do not set `QT_QPA_PLATFORM=offscreen`. The offscreen Qt plugin is missing from the SuperCollider 3.14.1 macOS bundle and aborts sclang. `scripts/smoke_test.sh` already unsets it.

---

## Sampling Rate

- **After every task commit:** Run `.venv/bin/pytest python_app/tests -x -q` (engine tasks also run `bash scripts/smoke_test.sh`)
- **After every plan wave:** Run the full suite (pytest + extended headless sclang smoke test)
- **Before `/gsd-verify-work`:** Full suite must be green, and the manual listening checks below performed
- **Max feedback latency:** 60 seconds (pytest meets it at ~3 s; the full engine smoke run measures ~75 s, see Sign-Off)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 02-01-T1 | 02-01 | 1 | GUI-02 | T-02-05 | `send_play` always encodes an OSC int (type tag `i`), never a float or the OSC True/False tag, even for a Python bool | headless smoke (tracer) + unit (real loopback socket) | `.venv/bin/pytest python_app/tests -q && bash scripts/smoke_test.sh` (checks `python stop`, `python start`) | ✅ | ✅ green |
| 02-01-T2 | 02-01 | 1 | GUI-02 | T-02-01, T-02-02, T-02-03, T-02-04 | `/pp/play` validated (malformed ignored), loopback-only, idempotent; Stop releases every voice via a group-wide `\gate, 0` broadcast (no hard free); Start lands on the bar | headless smoke (engine contract) | `bash scripts/smoke_test.sh` (checks `group gate broadcast`, `play idempotent`, `stop releases all`, `start on bar`, `play malformed ignored`, `loopback-only`, `re-evaluation`); `.venv/bin/pytest python_app/tests -q` | ✅ | ✅ green |
| 02-02-T1 | 02-02 | 2 | GUI-02 | T-02-06 (accept) | `PlayController` sends only on a real state change, always an int, listeners notified before send, no debounce, initial state sent once | unit (TDD, RED→GREEN) | `.venv/bin/pytest python_app/tests/test_play_logic.py -q && .venv/bin/pytest python_app/tests -q` | ✅ | ✅ green (13 tests) |
| 02-02-T2 | 02-02 | 2 | GUI-02 | T-02-07, T-02-08 (accept) | Start/Stop button toggles with one send per click, label follows controller state, takes no focus; the app manages no processes | Tk widget smoke (real Tk 9 widgets) + launch | `.venv/bin/pytest python_app/tests -q -rs`; `timeout 30 ./run.sh --port 57199 --exit-after 800` | ✅ | ✅ green (3 widget tests) |
| 02-03-T1 | 02-03 | 2 | TEMPO-01 | T-02-09, T-02-10, T-02-11 | `/pp/bpm` only records the latest clamped target; one long-lived `~ppRampStepper` is the sole tempo writer and survives re-evaluation; malformed input ignored mid-glide | headless smoke (engine contract, glide-adapted) | `bash scripts/smoke_test.sh` (checks `glide starts on beat`, `python tempo 140`, `clamp table settle`, `latest wins`, `malformed ignored`, `re-evaluation`) | ✅ | ✅ green |
| 02-03-T2 | 02-03 | 2 | TEMPO-01, TEMPO-02 | T-02-12 | Glide trajectory monotone toward the target over 2 bars, up and down; same-BPM send is a no-op; mid-glide retarget bends from the current tempo with no restart or jump | headless smoke (trajectory) | `bash scripts/smoke_test.sh` (checks `glide reaches target`, `glide upward`, `same bpm no-op`, `retarget mid-glide`); `.venv/bin/pytest python_app/tests -q` | ✅ | ✅ green |
| 02-04-T1 | 02-04 | 3 | ENG-01 | T-02-13, T-02-14, T-02-15 | All six layers (kick, hat, clap, bass, arp, pad) play and sound on one `~clock` through the limiter; node count bounded; mix keeps headroom; ≤3 oscillators + 1 filter per voice, no effect UGens | headless smoke (pattern + server level) | `bash scripts/smoke_test.sh` (checks `all layers playing`, `all layers sounding`, `mix headroom`, `node bound`, `limiter no bypass`, `limiter ceiling`) | ✅ | ✅ green |
| 02-04-T2 | 02-04 | 3 | ENG-01, GUI-02 | T-02-16 | Stop empties a held pad chord and in-flight notes within 2 s, while a natural tail would last ~3 s (discriminating check) | headless smoke (transport timing) + manual listening (human-check) | `bash scripts/smoke_test.sh` (checks `stop cuts held pad`, `stop catches in-flight notes`, ≥34 `CHECK OK:`); `.venv/bin/pytest python_app/tests -q` | ✅ | ✅ green (automated); listening check → Manual-Only |

Requirement-level test map:

| Requirement | Behavior | Test Type | Automated Command | File Exists |
|-------------|----------|-----------|-------------------|-------------|
| ENG-01 | All groove layers (kick, hat, clap, bass, arp, pad) play continuously on the one `~clock` | headless smoke test | `bash scripts/smoke_test.sh` (`all layers playing`, `all layers sounding`, `mix headroom`, `node bound`) | ✅ `supercollider/smoke_test.scd` |
| TEMPO-01 | A new BPM glides over ~1–2 bars, starts on a beat boundary, and lands on the target | headless smoke test | `bash scripts/smoke_test.sh` (`glide starts on beat`, `glide reaches target`, `glide upward`, `same bpm no-op`) | ✅ |
| TEMPO-02 | A mid-glide retarget continues from the current tempo with no restart or jump | headless smoke test | `bash scripts/smoke_test.sh` (`retarget mid-glide`) | ✅ |
| GUI-02 (engine) | `/pp/play 0` stops all layers and leaves zero instrument synths after the release time; `/pp/play 1` restarts quantized to the bar; repeated Start/Stop is idempotent | headless smoke test | `bash scripts/smoke_test.sh` (`python stop`, `python start`, `stop releases all`, `start on bar`, `play idempotent`, `play malformed ignored`, `stop cuts held pad`, `stop catches in-flight notes`) | ✅ |
| GUI-02 (Assumption A3) | `\gate, 0` broadcast to the instrument group does not error on synths without a `gate` control | headless smoke test | `bash scripts/smoke_test.sh` (`group gate broadcast`, with a positive `/fail` control) | ✅ |
| GUI-02 (Python logic) | Play/Stop controller sends only on a real state change, stays idempotent, and sends the initial state once | unit | `.venv/bin/pytest python_app/tests/test_play_logic.py -x` | ✅ `python_app/tests/test_play_logic.py` (13 tests) |
| GUI-02 (OSC wire format) | `send_play` delivers a decodable `/pp/play <int>` | unit (real loopback socket / mocked socket, same as the existing `send_bpm` tests) | `.venv/bin/pytest python_app/tests/test_osc_client.py -x` | ✅ extended (5 tests) |
| GUI-02 (GUI button) | Start/Stop button toggles with one send per click, follows controller state, takes no focus | Tk widget smoke (real Tk 9) | `.venv/bin/pytest python_app/tests/test_view_tk.py -x` | ✅ extended (3 tests) |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `supercollider/smoke_test.scd` — extend with: all-layers-playing, glide reaches target on a monotone trajectory, beat-boundary start, mid-glide retarget continuity, Stop leaves zero instrument synths after release, Start is bar-quantized and idempotent, and the Group `\gate` broadcast does not error (Assumption A3) — done across 02-01, 02-03 and 02-04 (19 → 36 checks)
- [x] `python_app/tests/test_play_logic.py` — new file covering the Play/Stop controller (same style as `test_bpm_logic.py`) — 02-02
- [x] `python_app/tests/test_osc_client.py` — extend with `send_play` tests (same style as the existing `send_bpm` tests) — 02-01
- [x] `python_app/config.py` — add the `/pp/play` address constant — 02-01 (`OSC_PLAY_ADDRESS`)
- No new framework installs: pytest and the smoke-test harness already exist from Phase 1

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| The groove sounds like melodic techno / progressive trance (drums, bass, arp and pad together) | ENG-01 | No automated check can judge musical quality | Run `supercollider/main.scd` in the SuperCollider IDE, launch `./run.sh`, and listen for at least one full 8-bar cycle (02-04 human-check step 1) |
| The glide sounds smooth, with no audible jolt and every layer in time | TEMPO-01, TEMPO-02 | The smoke test proves the mechanism (monotone, continuous, converges), not how it sounds | Move the BPM slider between distant values, then retarget quickly back and forth mid-glide, and listen for jumps, stutters or layers drifting apart (02-04 human-check steps 2–3) |
| Stop is clean (no hanging pad or bass notes, no click) and Start brings the full groove back in time | GUI-02 | Click and tail quality is perceptual | Press Stop during a held pad chord and listen to the tail. Press Start and check that all layers re-enter together on the bar (02-04 human-check steps 4–5) |
| Optional: the groove coexists with Zwift (no dropouts, modest CPU) | ENG-01 (CPU budget) | Live coexistence with Zwift cannot be simulated headlessly; the 60-minute soak is Phase 4 (ENG-03) | Repeat the steps above with Zwift running and watch the IDE's CPU readout (02-04 human-check step 6) |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (all 8 tasks carry `<automated>` commands)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency: per-task quick run (pytest) ~3 s, inside the 60 s target. Note: the full engine smoke run measures ~75 s, 15 s over the target, because the glide checks must wait for 2-bar glides to land. This is a sampling-cost note, not a coverage gap
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** validated 2026-10-09 (validate-phase audit: 87/87 pytest, 36/36 smoke checks, `SMOKE PASS`; 0 coverage gaps; 4 perceptual behaviours remain manual-only for end-of-phase UAT)

## Validation Audit 2026-10-09

| Metric | Count |
|---|---|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |
