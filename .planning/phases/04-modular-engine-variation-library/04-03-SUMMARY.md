---
phase: 04-modular-engine-variation-library
plan: 03
subsystem: audio-engine
tags: [supercollider, osc, library-selection, lead-layer, path-safety, latest-wins]

requires:
  - phase: 04-modular-engine-variation-library
    provides: loader, per-bar renderer and classic library files (plan 02); golden and library_test.scd (plan 01)
provides:
  - "/pp/progression, /pp/palette and /pp/melody (one string: auto or a file stem), loopback only"
  - "7th layer ppLead (role lead), silent under classic"
  - "supercollider/library/melodies/classic_lead.scd (arp plus a faint lead an octave up)"
  - "~ppStemValid, ~ppLibContained, ~ppSelReq, ~ppSelect, ~ppLogCount, ~ppRoleNotes"
  - "Selection tier in library_test.scd (8 checks)"
affects: [04-04, 04-05, 04-06, 05-gui]

actuals:
  tokens: 6430
  tasks: 2
  commits: 2

plan_head_before: e876f1062d376fa55ef421843f4ea5b9ab84b679
plan_head_after: 97a99b5f14a6ca892cb7e860e94da6413e3ab530

tech-stack:
  added: []
  patterns:
    - "OSC handler only validates and delegates; the file is read in a background Routine on SystemClock and ~ppSel is set only after a successful load"
    - "Per-category request number gives latest-wins; auto supersedes a load in flight"
    - "Name validation is a character loop on ascii codes (a regex $ anchor accepts a trailing newline); the path is built only from a fixed category folder, the validated stem and .scd, then checked with realpath containment"
    - "Log lines are counted with a monotonic ~ppLogCount because ~ppLogLines is capped at 100"

key-files:
  created:
    - supercollider/library/melodies/classic_lead.scd
  modified:
    - supercollider/main.scd
    - supercollider/core/loader.scd
    - supercollider/core/render.scd
    - supercollider/smoke_test.scd
    - supercollider/library_test.scd

key-decisions:
  - "Added ~ppLogCount (total lines ever logged) to ~ppLog so tests can count new log lines; the capped list size cannot do that once it holds 100 lines"
  - "~ppSelect wraps its Routine body in env.use (captured currentEnvironment), the same pattern the renderer uses, because a thread's environment is not guaranteed to be the interpreter's"
  - "A load error inside the selection Routine is caught, logged with the address and name, and treated as a refusal, so a bad file never kills the Routine silently"

patterns-established:
  - "A committed library file is final: classic_lead has one commit and any retune is a new file"
  - "Selection addresses are the frozen Phase 5 interface: three loopback addresses, one string each, no reply"

requirements-completed: [LIB-02, LIB-05]

coverage:
  - id: D1
    description: "/pp/melody classic_lead brings in a faint lead doubling the arp one octave up from a bar line, with no missing arp sixteenth; /pp/melody classic returns to the shipped sound"
    requirement: LIB-05
    verification:
      - kind: other
        ref: "bash scripts/check.sh --library-only (CHECK OK: select melody by name)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Re-sending a name re-reads its file from disk (rev goes up); the documented python-osc one-liner works; auto plays classic"
    requirement: LIB-05
    verification:
      - kind: other
        ref: "bash scripts/check.sh --library-only (CHECK OK: reselect reloads, python one-liner, auto plays classic, select palette and progression)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Invalid names (empty, number, uppercase, trailing newline, non-ASCII, space, ../x, leading _, 65 characters, ../../main) are ignored with a WARNING before any path is built; an unknown name logs an ERROR naming the file and changes nothing; back-to-back selections end on the second"
    requirement: LIB-02
    verification:
      - kind: other
        ref: "bash scripts/check.sh --library-only (CHECK OK: invalid names ignored, unknown name, latest wins)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Seven layers in the engine with the lead silent under classic: parity still 0 mismatches over 496 rows and the smoke suite passes unchanged (67 checks) with the 7th layer in the expected set"
    requirement: LIB-02
    verification:
      - kind: other
        ref: "bash scripts/check.sh (CHECK PASS; CHECK OK: parity; CHECK OK: all layers playing; 67 smoke CHECK OK lines)"
        status: pass
    human_judgment: false
  - id: D5
    description: "How classic_lead sounds: whether a 12 dB under octave-up double reads as shimmer and not as a new part"
    requirement: LIB-05
    verification: []
    human_judgment: true
    rationale: "Event-level tests prove the notes and the amp; whether the level sounds right is a listening judgment (end-of-phase listening check in Plan 06). A different level is a new file, never an edit"

duration: 45min
completed: 2026-10-11
status: complete
---

# Phase 4 Plan 03: Pick a variation by name while the music plays Summary

**Three loopback OSC addresses (/pp/progression, /pp/palette, /pp/melody) switch library files on the next bar line through a validated, background, latest-wins loader, plus a 7th lead layer and the first non-classic file classic_lead**

## Performance

- **Duration:** about 45 min
- **Tasks:** 2
- **Files:** 1 created, 5 modified

## Accomplishments
- `ppLead` is the 7th layer, playing on `~clock` into the mix bus inside the instrument group. Teardown, `~ppStart` and `~ppStop` already iterate `~ppLayers`, so Stop reaches it. Under classic it renders only rests: parity is still 496 rows and 0 mismatches against the unchanged golden.
- `classic_lead.scd`: the shipped arp plus a lead playing 69, 72, 76, 72 as sixteenths at amp 0.025 (about 12 dB under the arp's 0.1) on the arp voice.
- `~ppSelect` (loader): non-string arguments warn; `auto` is stored as `\auto` and supersedes any load in flight; invalid names warn before any path is built; valid names load in a Routine on SystemClock and `~ppSel` is set only after a successful load of the latest request. The OSC responders are one delegating line each and never wait or call `s.sync`.
- Name safety: `~ppStemValid` (1-64 characters from a-z, 0-9, _; no leading _; not `auto`; character loop, not a regex) and `~ppLibContained` (realpath containment, called from `~ppLibLoad` so a symlink pointing outside the category folder is refused).
- Boot re-loads a stored non-classic selection after the classic ensures, or falls back to classic with an ERROR line naming the file. The ready line reports the three selections and lists all seven addresses.
- Selection tier in `library_test.scd`, over real OSC to `NetAddr.langPort`: select melody by name, reselect reloads, python one-liner, auto plays classic, select palette and progression, invalid names ignored, unknown name, latest wins.

## Task Commits

1. **Task 1: select by name over OSC, 7th lead layer, classic_lead** - `44b36aa` (feat)
2. **Task 2: selection tier in the library test** - `97a99b5` (test)

**Plan metadata:** committed with this SUMMARY (docs)

## Files Created/Modified
- `supercollider/library/melodies/classic_lead.scd` - arp identical to classic, lead one octave up at amp 0.025
- `supercollider/core/loader.scd` - `~ppStemValid`, `~ppLibContained`, containment check in `~ppLibLoad`, `~ppSelReq`, `~ppSelect`, `~ppLogCount`
- `supercollider/core/render.scd` - `ppLead: \lead`, `~ppRoleNotes` counters
- `supercollider/main.scd` - 7 layers, boot re-load of stored selections, three OSCdefs, new ready line
- `supercollider/smoke_test.scd` - "all layers playing" expected set gains `\ppLead` (the "all layers sounding" SynthDef set is unchanged, D-03)
- `supercollider/library_test.scd` - helpers `sendSel`, `waitFor`, `venvPython`, `newLogs`, `barOf` and the eight selection checks

## Decisions Made
See key-decisions. No Python file changed (150 Python tests still pass).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Counter for new log lines**
- **Found during:** Task 2 ("invalid names ignored" asks for the number of new log lines)
- **Issue:** `~ppLogLines` is capped at 100, so snapshotting its size cannot count new lines once it is full.
- **Fix:** `~ppLog` also increments a monotonic `~ppLogCount`; the test counts new lines with it.
- **Files modified:** supercollider/core/loader.scd (in the Task 1 commit), supercollider/library_test.scd
- **Commit:** 44b36aa

**Total deviations:** 1 auto-fixed (1 blocking). **Impact:** none on behaviour; one added counter variable.

## Issues Encountered
- Nothing failed. Neither known smoke flake (`epic glide up`, `stop releases all`) appeared in the three full runs of this plan.
- In the "latest wins" run both Routines finished in order before the second handler ran, so the first request completed as a normal selection and was then overridden by the second. The end state (second selection wins, no missing sixteenth) is what the check asserts and it holds. The "loaded but superseded" log branch was therefore not exercised in that run.

## Known Stubs
None. The lead layer is intentionally silent under classic (D-05).

## Threat Flags
None beyond the plan's register. T-04-04 (7 loopback srcID guards in main.scd), T-04-05 (character-loop validation, no path built from an invalid name, realpath containment, test sends ../x, classic followed by a newline, _template, ../../main) and T-04-06 (responders only validate and start a Routine) are mitigated; T-04-07 is accepted as planned.

## Next Phase Readiness
Plan 04 can add more library files and the broken-file checks on top of `~ppSelect`, `~ppLibEnsure` and the containment check. Plan 06's Stop check can read `~ppRoleNotes`.

## Self-Check: PASSED
- Files exist: classic_lead.scd, loader.scd, render.scd, main.scd, smoke_test.scd, library_test.scd
- Commits `44b36aa` and `97a99b5` are ancestors of HEAD; `git rev-list --count e876f10..HEAD` is 2
- `bash scripts/check.sh` prints CHECK PASS (parity 496 rows, 0 mismatches; smoke 67 CHECK OK); `pytest python_app/tests` 150 passed

---
*Phase: 04-modular-engine-variation-library*
*Completed: 2026-10-11*
