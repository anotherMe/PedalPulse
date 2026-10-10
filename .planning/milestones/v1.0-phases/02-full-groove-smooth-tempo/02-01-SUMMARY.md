---
phase: 02-full-groove-smooth-tempo
plan: 01
subsystem: audio-engine
tags: [supercollider, oscdef, tempoclock, pbindef, python-osc, transport]

# Dependency graph
requires:
  - phase: 01-tempo-link-skeleton
    provides: "/pp/bpm OSC wire contract, loopback-only OSCdef guard pattern, s.waitForBoot teardown/rebuild skeleton, headless smoke_test.scd harness (19 checks)"
provides:
  - "/pp/play <int> transport: config.OSC_PLAY_ADDRESS, OscClient.send_play, --play CLI option"
  - "supercollider/main.scd: ~ppLayers (single source of truth for every layer), ~ppStart/~ppStop functions, OSCdef(\\pp_play) validated/loopback-only/idempotent"
  - "Clean stop: group-wide \\gate, 0 broadcast (immediate + guarded second broadcast after s.latency) releases every voice through its own release envelope, no hard free"
  - "Bar-synced restart: Start uses doReset: true so every layer re-enters in phase on the next quant:4 bar line"
  - "smoke_test.scd extended to 26 checks: python stop, python start, group gate broadcast (proves RESEARCH Assumption A3), play idempotent, stop releases all, start on bar, play malformed ignored, plus /pp/play coverage added to loopback-only and re-evaluation"
affects: [02-02-gui-start-stop-button, 02-03-tempo-glide, 02-04-full-groove-and-epic-fx]

# Actuals (#2632)
actuals:
  tokens: 5722
  tasks: 2
  commits: 2
plan_head_before: cddf8535dea188d5e4d3104913957e356a420091
plan_head_after: faefde88c8c168aea2e9043062427964a7d3ae0a

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "~ppLayers array as the single source of truth for 'every layer' (teardown, ~ppStart, ~ppStop, and smoke checks all iterate it; Plan 04 appends new layers here with no other code change)"
    - "Transport as two named functions (~ppStart/~ppStop) rather than inline OSCdef logic -- autostart on boot and the OSC handler both call the same function, so there is exactly one code path that starts or stops the groove"
    - "Clean stop via group-wide \\gate, 0 broadcast rather than node/group free -- preserves each synth's own release envelope (no pop), with a second time-guarded broadcast to catch note-ons already in flight as OSC bundles"
    - "doReset: true on Pbindef.play after a Stop -- resets every layer to its first event so a multi-step cycle (the bass's bar-end note change) re-enters in phase rather than resuming mid-cycle"

key-files:
  created: []
  modified:
    - python_app/config.py
    - python_app/osc_client.py
    - python_app/tests/test_osc_client.py
    - supercollider/main.scd
    - supercollider/smoke_test.scd

key-decisions:
  - "doReset: true on ~ppStart (planner deviation from RESEARCH default false, implemented as specified): without it a layer whose cycle spans more than one event resumes mid-cycle at the bar line, so the full groove would re-enter out of phase"
  - "Stop never frees nodes or the group; it only broadcasts \\gate, 0, so every voice (gated or not) ends through its own envelope -- verified by a positive-control /fail check before trusting an empty failMsgs collector"

patterns-established:
  - "Pattern: transport commands route through named ~ppStart/~ppStop functions, not inline in the OSCdef body, so autostart and OSC-triggered start/stop share one code path"
  - "Pattern: a group-wide control broadcast (\\gate, 0) is the 'stop all voices cleanly' primitive for this engine -- future transport-affecting features (EPIC changes, volume) should default to broadcasting instead of freeing nodes"

requirements-completed: [GUI-02]

coverage:
  - id: D1
    description: "End-to-end /pp/play transport tracer: real Python osc_client.py --play CLI sends /pp/play over UDP, OSCdef(\\pp_play) validates it, groove stops/restarts through ~ppStart/~ppStop"
    requirement: "GUI-02"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd#python stop / python start checks (scripts/smoke_test.sh)"
        status: pass
      - kind: unit
        ref: "python_app/tests/test_osc_client.py#test_send_play_delivers_int_osc_message_over_real_socket, test_send_play_coerces_bool_to_int, test_send_play_returns_false_on_oserror, test_cli_main_sends_play, test_cli_main_requires_bpm_or_play"
        status: pass
    human_judgment: false
  - id: D2
    description: "A Stop empties the instrument group within 2.5s and nothing new plays while stopped (no hanging notes)"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd#stop releases all check"
        status: pass
    human_judgment: false
  - id: D3
    description: "A \\gate, 0 group broadcast releases gated synths and is ignored by gate-less synths, with no server /fail -- RESEARCH Assumption A3, proven with a positive control before any Stop relies on it"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd#group gate broadcast check"
        status: pass
    human_judgment: false
  - id: D4
    description: "Stop ends every voice only through its own release envelope -- no hard node free, no audible pop"
    verification: []
    human_judgment: true
    rationale: "No-pop is an audible-quality judgment; the plan's own <verification> section defers the manual Stop/Start listening check to Plan 04's end-of-phase human check, once the full groove and GUI button exist. The automated proxy (group empties within 2.5s, no /fail on the gate broadcast) is covered by D2/D3."
  - id: D5
    description: "Start re-enters on the next quant:4 bar line (within 0.15 beat) with doReset: true so every layer restarts from its first event"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd#start on bar check"
        status: pass
    human_judgment: false
  - id: D6
    description: "Transport is idempotent (repeated /pp/play is a no-op), validated (missing/string/NaN argument posts a warning and changes nothing, then recovers), and loopback-only (rejects /pp/play from a LAN address)"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd#play idempotent, play malformed ignored, loopback-only checks"
        status: pass
    human_judgment: false
  - id: D7
    description: "Re-evaluating main.scd autostarts the groove again through the same ~ppStart path, and all Phase 1 checks plus the new /pp/play wire-format tests still pass"
    verification:
      - kind: integration
        ref: "supercollider/smoke_test.scd#re-evaluation check; scripts/smoke_test.sh full run (26 CHECK OK lines)"
        status: pass
      - kind: unit
        ref: "python_app/tests (71 passed)"
        status: pass
    human_judgment: false

duration: 45min
completed: 2026-10-09
status: complete
---

# Phase 2, Plan 01: Start/Stop transport, end to end (tracer) Summary

**`/pp/play <int>` transport wired end to end -- real Python CLI to `OSCdef(\pp_play)` to `~ppStart`/`~ppStop` -- with a clean group-wide gate-release stop, bar-synced `doReset` restart, and an idempotent, validated, loopback-only handler, raising the headless smoke harness from 19 to 26 checks.**

## Performance

- **Duration:** 45 min
- **Started:** 2026-10-09T12:30:00Z (approx.)
- **Completed:** 2026-10-09T13:15:00Z (approx.)
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Python `OscClient.send_play(playing)` and a `--play` CLI option send `/pp/play <int>` over UDP, always encoding an OSC int (never the bool True/False tag)
- `supercollider/main.scd` gained `~ppLayers`, `~ppStart`/`~ppStop` functions, and a validated, loopback-only, idempotent `OSCdef(\pp_play)`; autostart on boot now runs through `~ppStart.value`, the same path the OSC command uses
- Stop broadcasts `\gate, 0` to `~ppInstrGroup` immediately, plus a second guarded broadcast after `s.latency` for note-ons already in flight -- every voice ends through its own release envelope, confirmed empty within 2.5s
- Start restarts every layer with `doReset: true` on the next 4-beat bar line (within 0.15 beat), so the full groove re-enters in phase rather than resuming mid-cycle
- RESEARCH Assumption A3 (a gate broadcast is silently ignored by a synth with no gate control) proven with a positive `/fail` control before any Stop logic relies on it
- `scripts/smoke_test.sh` now runs 26 checks (Phase 1's 19 plus `python stop`, `python start`, `group gate broadcast`, `play idempotent`, `stop releases all`, `start on bar`, `play malformed ignored`, with `loopback-only` and `re-evaluation` extended to cover `/pp/play`)

## Task Commits

Each task was committed atomically:

1. **Task 1: End-to-end tracer (python osc_client.py --play -> /pp/play -> OSCdef -> groove stops and restarts)** - `635b732` (feat)
2. **Task 2: Stop releases every voice cleanly, Start lands on the bar, transport idempotent/validated/loopback-only** - `faefde8` (feat)

_Both tasks ran green on the first attempt; no retry commits were needed._

## Files Created/Modified
- `python_app/config.py` - added `OSC_PLAY_ADDRESS = "/pp/play"`
- `python_app/osc_client.py` - `OscClient.send_play`, `--play` CLI option, `bpm` positional changed to `nargs="*"`, requires at least one of bpm/--play
- `python_app/tests/test_osc_client.py` - wire-format, bool-coercion, OSError, and CLI tests for `/pp/play`
- `supercollider/main.scd` - `~ppLayers`, `~ppStart`/`~ppStop`, `OSCdef(\pp_play)`, gate-release Stop
- `supercollider/smoke_test.scd` - `waitForPlaying`, `sendPlay`, `instrChildCount` helpers; `\ppNoGateProbe` test SynthDef; 5 new named checks plus 2 extended ones

## Decisions Made
- `doReset: true` on `~ppStart`, per the plan's own stated deviation from the RESEARCH default (`false`): without it, the bass layer's bar-end note change would resume mid-cycle at a bar line, bringing the groove back out of phase. Reversible (one keyword argument).
- Stop never frees nodes or the instrument group -- only broadcasts `\gate, 0` -- so every voice (gated or not) ends through its own envelope. Verified empirically against a live `scsynth` before writing the check: a gate-less synth ignores `/n_set ... \gate, 0` with no `/fail` reply, and `/g_queryTree.reply`'s `msg[3]` (for an `OSCFunc`-received message) is the queried group's direct-child count -- both confirmed with throwaway probe scripts before committing to the smoke-test logic.

## Deviations from Plan

None - plan executed exactly as written. The two items that might look like deviations are actually scoped work the plan itself called for: the `doReset: true` departure from RESEARCH's default is specified directly in the plan's "Working decisions this plan implements" section, not something introduced during execution.

## Issues Encountered
None. Two small ambiguities in the plan's wire-format assumptions (`/g_queryTree.reply` field indices, `/fail` message shape) were resolved by writing short, throwaway `.scd` probe scripts against a live scsynth before implementing the corresponding smoke checks, rather than guessing from documentation -- both confirmed the plan's stated field indices were correct.

## User Setup Required
None - no external service configuration required. (Environment note: this worktree's `.venv` was created fresh via `python3.13 -m venv .venv && .venv/bin/pip install -r python_app/requirements-dev.txt` since worktrees do not share the main checkout's gitignored `.venv`; this is local test infrastructure, not a plan deliverable.)

## Next Phase Readiness
- GUI-02's engine contract (start/stop) is proven end to end through the real Python client and ready for Plan 02's GUI button -- GUI-02 remains engine-only complete; the button itself is Plan 02's deliverable.
- `~ppStart`/`~ppStop` and the group-wide gate-broadcast pattern are the foundation Plans 03 (tempo glide) and 04 (full groove + EPIC FX) build on.
- The manual Stop/Start listening check (confirming no audible pop, not just an empty node tree) is explicitly deferred to Plan 04's end-of-phase human check, per this plan's own `<verification>` section -- not a gap introduced here.

---
*Phase: 02-full-groove-smooth-tempo*
*Completed: 2026-10-09*

## Self-Check: PASSED

- FOUND: python_app/config.py
- FOUND: python_app/osc_client.py
- FOUND: python_app/tests/test_osc_client.py
- FOUND: supercollider/main.scd
- FOUND: supercollider/smoke_test.scd
- FOUND: 635b732 (ancestor of HEAD)
- FOUND: faefde8 (ancestor of HEAD)
- Acceptance criteria re-verified: `.venv/bin/pytest python_app/tests -q` exits 0 (71 passed); `bash scripts/smoke_test.sh` exits 0 with 26 `CHECK OK:` lines including all named Task 1/Task 2 checks
- Plan-level `<verification>` re-run: pytest green, smoke test SMOKE PASS with required named checks present
