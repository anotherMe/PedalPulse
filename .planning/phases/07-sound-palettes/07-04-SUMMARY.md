---
phase: 07-sound-palettes
plan: 04
subsystem: audio-engine
tags: [supercollider, sound-palettes, auto-rotation, harmony-memo, prefetch, osc]

# Dependency graph
requires:
  - phase: 07-sound-palettes
    provides: "07-01 per-bar palette stage (~ppHarmPaletteFor, palette log, ~ppPalPlaying); 07-02 palette defs guard (~ppPaletteDefs) used by the scan; 07-03 bass styles and the palettes acid, dark"
  - phase: 06-shared-harmony-progressions
    provides: "progression Auto (~ppHarmAutoNext, ~ppAutoCandidates, seeded draws, history cap) mirrored here"
provides:
  - "palette Auto: random opening pick, hold 80-128 bars, change on a progression change, no quick repeats, seeded and replayable (~ppPalAutoNext, ~ppPalAutoCandidates, ~ppPalHoldBars, ~ppPalAutoPicks, run state palAuto)"
  - "generalised background prefetch ~ppAutoPrefetch.(cat) with a category queue, ~ppAutoBusy, ~ppAutoCaps (progressions 256, palettes 32)"
  - "post-window lines: 'rotates palettes on progression changes; the first pick is random' and, once per run, 'only one progression can play on Auto, so Auto palettes change at the end of its round'"
  - "ten palette Auto checks in the library check; watchdog 420 s, check.sh library timeout 450 s"
affects: [07-05 more palettes and CPU check, 07-06 exit gate, README and UAT script]

# Actuals (#2632)
actuals:
  tokens: 16000
  tasks: 2
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Palette Auto is a stage of the per-bar harmony memo: it sees cycleBar, the cycle length and progChanged of the same bar, so palette and chords change together by construction"
    - "One scan Routine drains a de-duplicated category queue; ~ppAutoBusy lets a caller wait for a scan without blocking a bar"
    - "Palette draws have their own counter and seed salt (15485863), so they never shift the replayable progression order"

key-files:
  created: []
  modified:
    - supercollider/core/harmony.scd
    - supercollider/core/loader.scd
    - supercollider/main.scd
    - supercollider/library_test.scd
    - scripts/check.sh

key-decisions:
  - "Exception 1 to D-06 (opening pick) and exception 2 (only one progression can play) are implemented exactly as approved and are shown to the rider in the post window"
  - "Auto picked after a named lock does not adopt the locked palette: it draws a different one at the next round start (RESEARCH Open Question 2 / A6 decided against adopting)"
  - "phraseLine = cycle start and (cycle at least 4 bars, or bar multiple of 8): classic's one-bar cycle changes palette only on multiples of 8"
  - "The scan Routine resets its flags in a protect handler, so a throw can never leave palette Auto waiting on a stuck scan"

patterns-established:
  - "Long Auto behaviour is proven with pure runs (~ppHarmonyFor.(base + i, i) from the test Routine, no clock) for replay and bounds, and with recorded runs for what is actually played"

requirements-completed: [PAL-02, PAL-03]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "Palette Auto opens on a random palette (never the one playing), then changes it only on a progression change (or at the end of a named progression's round, or of the only progression that can play), with no repeat of the playing palette or the last two, and every row of all seven layers uses its bar's palette"
    requirement: PAL-02
    verification:
      - kind: integration
        ref: "scripts/check.sh (library_test.scd) #CHECK OK: auto palette rotates"
        status: pass
      - kind: integration
        ref: "scripts/check.sh (library_test.scd) #CHECK OK: auto palette lands on a progression change"
        status: pass
      - kind: integration
        ref: "scripts/check.sh (library_test.scd) #CHECK OK: auto palette with a locked progression"
        status: pass
      - kind: unit
        ref: "scripts/check.sh (library_test.scd) #CHECK OK: auto palette with a single progression"
        status: pass
    human_judgment: false
  - id: D2
    description: "A named palette locks from the next bar whatever the progressions do, and picking Auto again draws a different palette at the next round start"
    requirement: PAL-03
    verification:
      - kind: integration
        ref: "scripts/check.sh (library_test.scd) #CHECK OK: named palette locks"
        status: pass
    human_judgment: false
  - id: D3
    description: "Auto replays from its seed without disturbing the progression order, starts fresh after Stop and Start, picks up a palette file added while running, skips broken palette files (reported once per change), and stays bounded over 1200 bars"
    requirement: PAL-02
    verification:
      - kind: unit
        ref: "scripts/check.sh (library_test.scd) #CHECK OK: auto palette replays from the seed"
        status: pass
      - kind: unit
        ref: "scripts/check.sh (library_test.scd) #CHECK OK: auto palette starts fresh after stop and start"
        status: pass
      - kind: unit
        ref: "scripts/check.sh (library_test.scd) #CHECK OK: auto palette stays bounded"
        status: pass
      - kind: integration
        ref: "scripts/check.sh (library_test.scd) #CHECK OK: auto adds a new palette file"
        status: pass
      - kind: integration
        ref: "scripts/check.sh (library_test.scd) #CHECK OK: auto skips a broken palette"
        status: pass
    human_judgment: false
  - id: D4
    description: "How often the sound changes feels right at the rider's real BPM (4.7-5.7 minutes per palette on average at 90-110 BPM with Progression on Auto)"
    requirement: PAL-02
    verification: []
    human_judgment: true
    rationale: "The tests prove the mechanics and the bar counts; whether the pace and the moment of change feel right on a real ride is a listening judgment for the Plan 06 UAT"

# Metrics
duration: 62min
completed: 2026-10-13
status: complete
commits: 3
plan_head_before: 7e8d2f3d5418803884d97e69e6def697e8a82233
plan_head_after: 7bc1c14687d1f87c0031b2b2f2425d9f1c48f269
---

# Phase 7 Plan 04: On Auto the sound changes by itself every few minutes, together with the chords; a name keeps it Summary

**Palette Auto: a random opening palette, a new one every 80-128 bars that always lands on a chord-set (progression) change, no quick repeats, replayable from a seed, new files joining by themselves, and a named pick that locks until Auto is chosen again**

## Performance

- **Duration:** about 62 min
- **Started:** about 2026-10-13T13:58:00Z
- **Completed:** 2026-10-13T15:02:00Z
- **Tasks:** 2 (3 task commits: one RED, one GREEN, one test-only)
- **Files modified:** 5 (no file created)

## How palette Auto behaves, in plain words

You do not need to do anything: the app starts every selector on Auto.

- **When the first palette is chosen.** Within a few seconds of the music starting (the engine first loads the other palette files in the background), at the next chord-set change or the next 8-bar line, Auto picks a random palette that is not the one playing. So the very first thing you hear on a fresh launch is classic for a few bars and then a different sound, not classic for minutes. After a Stop and Start the first bar already plays a freshly drawn palette (never the one you had just before).
- **How often it changes.** Each palette plays at least 80 to 128 bars, then waits for the next change of chord set. A bar is 4 beats, so minutes = bars x 4 / BPM: the hold alone is 2.9 to 5.7 minutes at 90 to 110 BPM (shorter at a higher BPM). With Progression on Auto the wait for the next chord-set change adds about 25 bars on average, so a palette plays about **4.7 to 5.7 minutes on average at 90 to 110 BPM**, anywhere from about 2.9 to 8.5 minutes. With a named progression the palette changes at the end of that progression's round, about 3 to 6 minutes.
- **What changes and when.** All seven layers (drums included) switch together on the bar line; notes already ringing finish by themselves. The post window prints `PedalPulse: palette <name>: <description>` for every change, so you can name what you heard.
- **No quick repeats.** Auto never picks the palette that is playing nor one of the last two it played. A palette file you add while the engine runs joins the rotation by itself; a broken file is skipped and reported once.
- **Special case.** If Progression on Auto has only one progression it can play, palettes change at the end of that progression's round and the post window says so once: `PedalPulse: only one progression can play on Auto, so Auto palettes change at the end of its round`.
- **To lock a palette** pick its name in the Palette dropdown. It takes over from the next bar and stays, whatever the progressions do. Without the app, with the engine running:

  ```
  .venv/bin/python -c "from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/palette', 'supersaw')"
  ```

- **To go back to Auto** pick Auto in the dropdown, or send `'auto'` instead of `'supersaw'` in the same one-liner. Auto then draws a different palette (it does not keep the locked one) at the next chord-set change or the next 8-bar line.

## Accomplishments

- **Palette Auto as a stage of the harmony memo.** `~ppPalAutoNext` runs once per (run, song bar) inside `~ppHarmPaletteFor`, with the bar's `cycleBar`, cycle length and `progChanged`. Engage (opening pick) is explicit exception 1 to D-06; rotation then lands only on a chapter with progression Auto (no bar-count fallback), on a chapter or a phrase line with a named progression, and on a phrase line when only one progression can play (exception 2, once-per-run note). History is capped at 8, draws are seeded with a salt different from the progression draws and counted in `~ppPalAutoPicks`.
- **Prefetch generalised.** `~ppAutoPrefetch.(cat)` queues a category (nil still means progressions, so every Phase 6 caller works), one Routine drains the queue (progressions first), `~ppAutoBusy.(cat)` tells whether a category is queued or being scanned, palettes are capped at 32 files per scan, and failed files are remembered by modification time so a broken palette is reported once per change. `/pp/palette auto` and the boot-time stored `auto` both queue a palette scan.
- **Ten library checks** prove rotation, landing, locking, replay, fresh start, new files, broken files and bounded state (see the coverage list), and `auto plays classic` now sends auto to melody and progression only.

## Task Commits

1. **Task 1 RED: failing palette Auto checks, watchdog 420, check.sh timeout 450** - `19650bf` (test)
2. **Task 1 GREEN: palette Auto, prefetch queue and busy flag, selection wording, boot prefetch** - `e7ad026` (feat)
3. **Task 2: replay, fresh start, bounded, new palette file, broken palette checks** - `7bc1c14` (test)

**Plan metadata:** the commit that adds this SUMMARY (docs: complete plan).

## Files Created/Modified

- `supercollider/core/harmony.scd` - `~ppPalHoldBars`, `~ppPalAutoPicks` (with the real-timing comment), `~ppPalAutoCandidates`, `~ppPalAutoNext`, the `\auto` branch of `~ppHarmPaletteFor`, run-state key `palAuto`
- `supercollider/core/loader.scd` - `~ppAutoPrefetch.(cat)`, `~ppAutoPending`, `~ppAutoScanning`, `~ppAutoCaps`, `~ppAutoBusy`, palette auto wording in `~ppSelect`
- `supercollider/main.scd` - boot-time palette prefetch when the stored palette selection is auto
- `supercollider/library_test.scd` - watchdog 420; ten palette Auto checks (selection tier and fallback tier); `auto plays classic` for melody and progression only
- `scripts/check.sh` - library timeout 450 (`timeout` and `gtimeout`)

## Decisions Made

Followed the plan's recorded decisions (see key-decisions in the frontmatter). Nothing new beyond them except the small choices listed under Deviations.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Test design] "auto adds a new palette file" uses a palette hold of [64, 64], not [4, 4]**
- **Found during:** Task 2
- **Issue:** with hold [4, 4] and a drawn fresh_pal at bar 16, Auto would rotate to classic at bar 24, contradicting the plan's own requirement that every pitched row from fresh_pal's first bar uses its voices for the rest of the 32 bars.
- **Fix:** the check sets `~ppPalHoldBars = [64, 64]` (restored afterwards). Rotation with short holds is covered by the other Auto checks.
- **Files modified:** `supercollider/library_test.scd`
- **Committed in:** `7bc1c14`

**2. [Rule 1 - Test design] "named palette locks" picks dark when Auto happens to play supersaw at bar 6.5**
- **Found during:** Task 1 (designing the check)
- **Issue:** a named pick equal to the palette already playing leaves no palette record, so "supersaw plays from a bar in 7..9" could not be observed.
- **Fix:** the check locks supersaw unless `~ppPalPlaying` is supersaw, then dark. Both exist on disk.
- **Committed in:** `19650bf`

**3. [Rule 2 - Robustness] run state without `palAuto` is repaired; scan flags are reset in a `protect` handler**
- **Issue:** a run state that started before a module re-evaluation could lack `palAuto`; a throw outside the scan's `try` would have left `~ppAutoPrefetching` true forever and blocked palette Auto's first pick.
- **Fix:** `~ppPalAutoNext` creates the key when it is missing; the scan Routine's body runs under `protect` and clears `~ppAutoScanning` and `~ppAutoPrefetching`.
- **Files modified:** `supercollider/core/harmony.scd`, `supercollider/core/loader.scd`
- **Committed in:** `e7ad026`

**4. [Rule 3 - Blocking, RED only] test waits tolerate a missing `~ppAutoBusy`**
- **Issue:** before the GREEN commit `~ppAutoBusy` does not exist, so the RED run would have died on a DoesNotUnderstand instead of reaching the real assertion.
- **Fix:** the two waits use `(~ppAutoBusy.isNil or: { ... })`; the checks themselves never accept a missing function after GREEN (the verify greps `~ppAutoBusy = ` in loader.scd).
- **Committed in:** `19650bf`

**5. [Minor] a duplicate `CHECK OK: auto palette with a locked progression` line was removed** (the check printed it before and after the pure single-progression run). Committed in `e7ad026`.

**Total deviations:** 5 (2 test design, 1 robustness, 1 RED-only blocking, 1 cosmetic). **Impact:** none on scope; Task 2's checks exposed no defect in harmony.scd or loader.scd, so Task 2 changed no engine file.

## TDD Gate Compliance

- **RED** `19650bf` (`test(07-04)`): `./scripts/check.sh --library-only` exited 1 and the library log ended `LIBRARY FAIL: ERROR: auto palette rotates: the first palette is classic, the palette that was playing before: [('bar': 0, 'stem': classic)]`. `gsd_run check tdd-red-evidence` has no adapter for SuperCollider's line protocol (and `workflow.tdd_mode` is off), so this is the semantic assessment: the target check ran (`CHECK OK: auto rotates progressions` etc. before it), recorded 64 real bars and failed on the planned assertion for the intended reason (palette Auto still played classic).
- **GREEN** `e7ad026` (`feat(07-04)`): `./scripts/check.sh --library-only` printed `CHECK OK: auto palette rotates`, `... lands on a progression change`, `... with a locked progression`, `... with a single progression`, `CHECK OK: named palette locks`, `CHECK OK: auto plays classic`, every progression Auto check, `CHECK OK: palette levels` and `CHECK PASS (library only)`.
- **REFACTOR:** none needed.
- Task 2 is not a `tdd` task: its five checks were added after the behaviour and passed on their first run (no engine change needed), so they carry no RED of their own.

## Issues Encountered

- **The audio device failed after the library tier of the first full run.** In the one run of `./scripts/check.sh` that executed the whole library tier with every Task 2 check (library log ends `LIBRARY PASS`, about 3.6 minutes against the new 420 s watchdog and 450 s timeout), the following palette-meter step failed once with `palette select: acid never became the palette that plays` and, from then on, every attempt to boot an audio server on this Mac failed with `AudioDeviceStart failed 35` (also a bare one-line SuperCollider boot script unrelated to the project; the output device list had lost the `Odyssey G50A` entry). The same core code had passed the meter in the `--library-only` run just before (`CHECK OK: palette levels`). The audio hardware recovered for one window, in which `./scripts/smoke_test.sh` printed `SMOKE PASS` on the final code, and then failed again for the remaining retries (about 14 runs over 30 minutes). I could not obtain a single uninterrupted `CHECK PASS` from `bash scripts/check.sh`; see the verification status below.
- The worktree has no `.venv`; a temporary symlink to the main checkout's `.venv` was used and removed before the final commit. The sandbox refuses compound shell lines that mix git with other commands, so commands were run one at a time.

## Verification status (what ran on the final code, HEAD `7bc1c14` before this SUMMARY)

| Gate | Result | Where |
|------|--------|-------|
| Library tier with all ten palette Auto checks, all Phase 6 Auto checks, parity, fallback tier | `LIBRARY PASS` (about 3.6 min) | `./scripts/check.sh` first full run |
| Palette meter (levels, headroom, CPU, nodes, extreme notes) | `CHECK OK: palette levels` on the same core code | `./scripts/check.sh --library-only` after the GREEN code; failed once later and then on audio start (environment) |
| Smoke suite | `SMOKE PASS` | `./scripts/smoke_test.sh`, in the one window where audio worked |
| Python suite | 191 passed; `git diff e2dc47e -- python_app` empty | `.venv/bin/python -m pytest -q python_app/tests` |

The orchestrator should run `./scripts/check.sh` once on the merged tree when the audio device is healthy; no change to engine code is expected to be needed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 05 adds more palettes: they join palette Auto by themselves (candidates are counted from disk, the checks never hardcode the number), and the meter measures them before their first commit.
- Plan 06 owns the README paragraph and the UAT script; the real timing numbers to quote are in the plain-words section above and in the `harmony.scd` comment next to `~ppPalHoldBars`. The UAT should ask for the rider's BPM.
- `~ppPalHoldBars` ([80, 128]) is the one number to change if the pace feels wrong; it is a tunable, not a file.

## Self-Check: PASSED

- Modified files exist: `supercollider/core/harmony.scd`, `supercollider/core/loader.scd`, `supercollider/main.scd`, `supercollider/library_test.scd`, `scripts/check.sh`.
- Commits `19650bf`, `e7ad026`, `7bc1c14` are ancestors of HEAD; `git rev-list --count 7e8d2f3..HEAD` was 3 before this SUMMARY.
- Acceptance greps hold: `~ppPalHoldBars = ~ppPalHoldBars ? [80, 128]`, `15485863`, `keep(-2)`, the single-progression note, `~ppAutoBusy = `, `palettes: 32`, `ppAutoPrefetch.(\palettes)` in main.scd, `SystemClock.sched(420`, `timeout 450` and `gtimeout 450`.
- The one gap is stated above: no single uninterrupted `CHECK PASS` of the full gate because of the audio device.

---
*Phase: 07-sound-palettes*
*Completed: 2026-10-13*
