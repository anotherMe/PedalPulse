---
phase: quick-261010-hyl
plan: 01
subsystem: supercollider-engine
tags: [supercollider, transport, smoke-test, GUI-02, audit-W1]
requires: []
provides:
  - "Transport state (playing/stopped) survives main.scd re-evaluation"
affects: [supercollider/main.scd, supercollider/smoke_test.scd]
tech-stack:
  added: []
  patterns: ["~x = ~x ? default persistence idiom, applied to transport state"]
key-files:
  created: []
  modified:
    - supercollider/main.scd
    - supercollider/smoke_test.scd
decisions:
  - "Capture ~ppWasPlaying = ~ppPlaying ? true as the first waitForBoot statement; nil (first eval) keeps the D-15 autostart"
  - "Stopped re-evaluation does not call ~ppStop (teardown already stopped everything)"
metrics:
  duration: ~25min
  completed: 2026-10-10
status: complete
actuals:
  tokens: 6000
  tasks: 2
  commits: 2
plan_head_before: 787fd259074b88cca02343c81ea561c1e3f92345
plan_head_after: 5fac0bd
---

# Phase quick-261010-hyl Plan 01: Fix W1 Summary

Transport state now persists across main.scd re-evaluation: a re-evaluation after Stop stays stopped (and the next /pp/play 1 starts the groove), while the first-ever evaluation and re-evaluation while playing still autostart/keep playing.

## What changed

- `supercollider/main.scd`: `~ppWasPlaying = ~ppPlaying ? true;` is the first statement inside `s.waitForBoot`, before the teardown. The former unconditional `~ppStart.value` is now `if (~ppWasPlaying) { ~ppStart.value } { post "staying stopped" }`. The ready line reports `groove playing|stopped`. Header comment updated. `~ppPlaying = false; ~ppTransportCount = 0;` unchanged.
- `supercollider/smoke_test.scd`: new check "re-evaluation stays stopped" (Stop, reload, assert stopped + count 0 + silent after a bar, then /pp/play 1 starts via ~ppStart exactly once); new check "autostart" with `~ppPlaying = nil;` before the first load; B8 "re-evaluation" hardened (playing precondition, `~ppTransportCount == 1`, clearer messages).

## Red run evidence

New check added first, run against unfixed main.scd: 65 CHECK OK, then
`SMOKE FAIL: ERROR: re-evaluation stays stopped: ~ppPlaying is true after reload (expected false: a stopped engine must stay stopped)`, exit 1 (the "ERROR: " prefix comes from sclang's errorString; the check name matched as planned).

## Green run

`scripts/smoke_test.sh` after the fix: rc 0, `SMOKE PASS`, 66 CHECK OK after Task 1, 67 CHECK OK after Task 2 (65 + "autostart" + "re-evaluation stays stopped"), no SKIP. Wall time about 144 s (2:23.7), well inside the 300 s watchdog, so the watchdog contingency was not triggered and scripts/smoke_test.sh was not touched. Log contains `PedalPulse: was stopped before re-evaluation -- staying stopped ...` and `ready -- groove stopped at 128.0 BPM ...`.

## Deviations from Plan

**[Rule 3 - Blocking] Missing .venv in the worktree.** `.venv` is gitignored, so the fresh worktree had none and scripts/smoke_test.sh exited 1 on its precondition. Worked around it by temporarily symlinking the main checkout's `.venv` into the worktree (no package install), then removing the symlink after the final run. Nothing was committed for it. No port conflicts with running SuperCollider instances occurred.

Otherwise the plan was executed as written. Commits: Task 1 combined the red check and the fix in a single commit (the red run was done on the working tree before the fix, per plan).

## Known Stubs

None.

## Threat Flags

None.

## Self-Check: PASSED

- supercollider/main.scd and supercollider/smoke_test.scd modified and committed (d3dd072, 5fac0bd).
- `git rev-list --count 787fd25..HEAD` = 2.
