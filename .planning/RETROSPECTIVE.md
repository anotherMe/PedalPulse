# Project Retrospective

*Updated after each milestone. Its lessons feed into planning the next one.*

## Milestone: v1.0 — Technical Proof

**Shipped:** 2026-10-10
**Phases:** 3 | **Plans:** 11 (+1 quick task) | **Sessions:** not tracked

### What Was Built
- The Python → OSC → sclang chain: `/pp/bpm`, `/pp/play`, `/pp/epic` and `/pp/volume`, all loopback-only, validated and clamped by the engine
- A six-layer fixed-loop trance groove (kick, hat, clap, bass, arp, pad) on one TempoClock, with 2-bar beat-synchronous tempo glides that can be retargeted mid-glide
- EPIC brightness and energy from a single lagged value driving one FX synth, plus master volume, both placed before a −1 dBFS limiter
- A Tkinter window with the BPM slider, entry, nudge buttons and arrow keys, Start/Stop, five zone buttons and a volume slider
- Two layers of tests: 150 pytest tests and a 67-check headless SuperCollider smoke suite (`scripts/smoke_test.sh`)

### What Worked
- **Vertical slices with a walking skeleton.** Every phase ended with something audible, and the end-to-end chain was proven in Phase 1.
- **The headless smoke harness.** It grew from 19 to 67 checks, and each phase extended it instead of replacing it. It made engine changes safe to make, including the late W1 fix, which was proven red then green.
- **Test-first controllers** (`BpmController`, `PlayController`, `EpicController`, `VolumeController`). They kept the Tk layer thin and testable without a display.
- **End-of-phase listening UATs.** They closed the perceptual checks that no automated test can cover: style, glide smoothness, clicks.
- **Cutting scope on purpose.** Dropping engine → GUI feedback (Phase 4) kept the app simple, and nothing broke.

### What Was Inefficient
- **Review records drifted.** A finding ID (WR-01) was reused across review passes, and dispositions stayed "open" after the fixes landed in later phases. As a result the milestone audit reported stale debt.
- **Phase 4 was planned and its context captured before it was dropped.** That effort was spent on scope that never shipped.
- **Verification digests go stale.** Any later edit to a shared file (`main.scd`, `smoke_test.scd`) invalidates every earlier phase's VERIFICATION.md digest. As a result, v1.0 closed as an override instead of a verified closeout.
- **Many open code-review warnings were never triaged** (fix, accept or defer) before the milestone closed.

### Patterns Established
- Every engine change ships with a headless smoke check. Behaviour fixes are proven red against the old code first.
- `~ppLayers` is the single list of layers. `~ppRampStepper` is the only code that writes the tempo. EPIC and volume always sit before the limiter.
- Re-evaluating `main.scd` is idempotent: everything is keyed and replaced, never stacked, and state is kept across re-evaluation with the `x = x ? default` pattern.
- The GUI sends on slider release and debounces nudges. The engine is idempotent, so repeated messages are harmless.

### Key Lessons
1. Triage code-review findings when the phase closes, and update the disposition when a later phase fixes them. Stale "open" records cost audit time.
2. Expect late fixes to shared engine files to make earlier verification reports stale. Either re-run verification before closing the milestone, or budget for an override closeout.
3. Put requirements that can only be checked by a manual test ride (like ENG-03) on a dated checklist, so they don't block a close indefinitely.
4. Decide on scope cuts before discussing a phase, not after.

### Cost Observations
- Model mix: not tracked. The configured profile uses opus for planning, sonnet for execution and verification, and haiku for checkers.
- Sessions: not tracked
- Notable: 129 commits over 3 days for 11 plans and 1 quick task

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | — | 3 | Vertical MVP slices with a growing headless smoke harness; Phase 4 dropped to keep the app send-only |

### Cumulative Quality

| Milestone | Tests | Coverage | Zero-Dep Additions |
|-----------|-------|----------|-------------------|
| v1.0 | 150 pytest + 67 smoke checks | not measured | python-osc is the only runtime dependency |

### Top Lessons (Verified Across Milestones)

1. (To be filled in once more than one milestone has shipped.)
