---
phase: 04-modular-engine-variation-library
plan: 01
subsystem: testing
tags: [supercollider, golden-recording, parity, git-guard, bash]

requires:
  - phase: 03-epic-volume
    provides: unmodified v1.0 engine (supercollider/main.scd) and the headless smoke suite
provides:
  - supercollider/golden/shipped_groove.scd (496-row frozen recording of the unmodified engine)
  - supercollider/library_test.scd (recorder, golden record mode, golden self-check and parity tiers)
  - scripts/check.sh (library guard + self-test, library check, smoke suite; --library-only fast loop)
affects: [04-02, 04-03, 04-04, 04-05, 04-06]

actuals:
  tokens: 13700
  tasks: 2
  commits: 2

plan_head_before: c977ab92fa48cbae8a35712605f2a836333af2d4
plan_head_after: b80b2be7f0dde0e234763d0a68228619541541d4

tech-stack:
  added: []
  patterns:
    - "Test-only Event type (\\ppRecord) records sounding events without touching the engine"
    - "Golden recorded once from the unmodified engine; record mode refuses to overwrite"
    - "git diff --name-status --no-renames HEAD guard with a temporary-repo self-test"

key-files:
  created:
    - supercollider/library_test.scd
    - supercollider/golden/shipped_groove.scd
    - scripts/check.sh
  modified: []

key-decisions:
  - "Recording clock starts at beat 0.5 (TempoClock(tempo, 0.5)) so the first bar line (beat 4) is never 'now'; a clock created at beat 0.0 made nextTimeOnGrid(4) return 0 and every start looked raced"
  - "Rows are sorted by onset rounded to 1e-6 then layer name, but the raw float beat is stored, so clock jitter cannot reorder simultaneous events"
  - "After recording, each Pbindef player's event is reset to Event.default so the engine's layers do not keep the recording event type"
  - "protoEvent works on Pbindef(n).play (also on a resumed player), so the EventStreamPlayer fallback in the plan was not needed"

patterns-established:
  - "scripts/check.sh is the one gate every later plan runs; --library-only is the fast loop"
  - "library_test.scd helpers fail, checkOk, recordBars.(nBars, tempo, during) -> (rows:, startBeat:)"

requirements-completed: [LIB-01, LIB-03, LIB-06]

coverage:
  - id: D1
    description: "Golden recorded from the unmodified engine: 496 rows, per-layer counts 64/64/32/64/256/16, effective amps 0.1/0.1/0.25/0.1/0.1/0.06"
    requirement: LIB-01
    verification:
      - kind: other
        ref: "bash scripts/check.sh --library-only (CHECK OK: golden self-check)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Note-level parity check passes on the unmodified engine with 0 mismatches in every column (recording is repeatable)"
    requirement: LIB-01
    verification:
      - kind: other
        ref: "bash scripts/check.sh --library-only (PedalPulse libtest: parity rows=496 mismatches=0)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Never-overwrite guard with self-test (modify, delete, rename, golden fail; new and re-saved files pass; non-git prints CHECK SKIP)"
    requirement: LIB-03
    verification:
      - kind: other
        ref: "bash scripts/check.sh (CHECK OK: library guard self-test)"
        status: pass
    human_judgment: false
  - id: D4
    description: "One command runs guard, library check and smoke suite (CHECK PASS)"
    requirement: LIB-06
    verification:
      - kind: other
        ref: "bash scripts/check.sh (CHECK PASS; smoke log 67 CHECK OK lines)"
        status: pass
    human_judgment: false

duration: 45min
completed: 2026-10-11
status: complete
---

# Phase 4 Plan 01: Freeze what the shipped engine plays, and one command that guards it Summary

**Frozen 496-row golden of the unmodified v1.0 engine, a ppRecord-event-type parity harness proven on that same engine (0 mismatches), and scripts/check.sh as the single guard + library + smoke gate**

## Performance

- **Duration:** about 45 min
- **Tasks:** 2
- **Files created:** 3 (no engine file touched)

## Accomplishments
- `supercollider/golden/shipped_groove.scd`: 16 bars at tempo 32, 496 rows (kick 64, hat 64, clap 32, bass 64, arp 256, pad 16), effective amps captured as they are (0.1 for kick, hat, bass, arp; 0.25 clap; 0.06 pad). Committed once (`c4c518b`), before any Phase 4 change to `main.scd`.
- `supercollider/library_test.scd`: isolated muted server on 57141, test-only `\ppRecord` event type, golden record mode (refuses to overwrite), "golden self-check" and "parity" tiers, 200 s watchdog. Compare mode against the unmodified engine prints `PedalPulse libtest: parity rows=496 mismatches=0` and `LIBRARY PASS`, run repeatedly (recording is repeatable).
- `scripts/check.sh`: guard over `supercollider/library/*/[a-z0-9]*.scd` and `supercollider/golden/*.scd` using `git diff --name-status --no-renames HEAD`, a temporary-repo self-test (clean, new untracked, new staged, byte-identical re-save, modify, delete, rename, golden modified, template modified, non-git skip), then the library check, then the smoke suite. `--library-only` skips the smoke suite; an unknown argument exits 2.
- Whole `bash scripts/check.sh` ends with `CHECK PASS`; the smoke log has 67 `CHECK OK:` lines; the 150 Python tests still pass.

## Task Commits

1. **Task 1: record shipped groove golden and parity check** - `c4c518b` (test)
2. **Task 2: scripts/check.sh** - `b80b2be` (feat)

## Files Created/Modified
- `supercollider/library_test.scd` - recorder, record mode, golden self-check, parity
- `supercollider/golden/shipped_groove.scd` - frozen parity reference (never edit)
- `scripts/check.sh` - one-command gate

## Decisions Made
See key-decisions. Plan 02 note: `Pbindef(n).play(clock, protoEvent: ..., quant: 4, doReset: true)` honors the protoEvent directly, so no EventStreamPlayer fallback is in use. `recordBars` retries (up to 5 times) if any layer's quantization could have slipped past the first bar line, and resets each player's event to `Event.default` after recording.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Recorder start-race check always failed on a fresh clock**
- **Found during:** Task 1 (first record run)
- **Issue:** `TempoClock(tempo)` starts at beat 0.0, where `nextTimeOnGrid(4)` returns 0.0, so the "all layers quantized before the first bar line" check failed on all 5 attempts.
- **Fix:** start the recording clock at beat 0.5 (`TempoClock(tempo, 0.5)`).
- **Files modified:** supercollider/library_test.scd
- **Verification:** record mode wrote 496 rows; compare mode shows 0 mismatches repeatedly.
- **Committed in:** c4c518b

---

**Total deviations:** 1 auto-fixed (1 bug). **Impact on plan:** none on scope; internal to the recorder.

## Issues Encountered
- The precondition run of `bash scripts/smoke_test.sh` on the unmodified engine failed once with `epic glide up: PulseCount did not advance between samples 0 and 1` (timing flake in an existing check, while no other load of mine was running). A rerun passed, and the full `bash scripts/check.sh` run passed. This is pre-existing and out of scope (no engine or smoke file changed); a rider-facing risk is none, but later plans should expect an occasional smoke flake and rerun.
- The worktree had no `.venv`; a worktree-local one was created (gitignored, not committed).

## Known Stubs
None.

## Threat Flags
None. T-04-02 (silent overwrite) is mitigated by the guard, its self-test and the record-mode refusal; T-04-03 (disturbing a running engine) by the isolated port 57141.

## Next Phase Readiness
Plan 02 can split the engine and gate it with `bash scripts/check.sh` (or `--library-only` for the fast loop); parity against the golden is the LIB-01 proof it must keep at 0 mismatches.

## Self-Check: PASSED

---
*Phase: 04-modular-engine-variation-library*
*Completed: 2026-10-11*
