---
phase: 06-shared-harmony-progressions
verified: 2026-10-13T09:30:00Z
status: passed
score: 5/5 must-haves verified
covered_files:
  - ".planning/phases/06-shared-harmony-progressions/06-01-PLAN.md"
  - ".planning/phases/06-shared-harmony-progressions/06-01-SUMMARY.md"
  - ".planning/phases/06-shared-harmony-progressions/06-02-PLAN.md"
  - ".planning/phases/06-shared-harmony-progressions/06-02-SUMMARY.md"
  - ".planning/phases/06-shared-harmony-progressions/06-03-PLAN.md"
  - ".planning/phases/06-shared-harmony-progressions/06-03-SUMMARY.md"
  - ".planning/phases/06-shared-harmony-progressions/06-04-PLAN.md"
  - ".planning/phases/06-shared-harmony-progressions/06-04-SUMMARY.md"
  - ".planning/phases/06-shared-harmony-progressions/06-05-PLAN.md"
  - ".planning/phases/06-shared-harmony-progressions/06-05-SUMMARY.md"
  - "scripts/check.sh"
  - "scripts/smoke_test.sh"
  - "supercollider/core/harmony.scd"
  - "supercollider/core/loader.scd"
  - "supercollider/core/render.scd"
  - "supercollider/core/validate.scd"
  - "supercollider/library/README.md"
  - "supercollider/library/progressions/_template.scd"
  - "supercollider/library/progressions/anthem.scd"
  - "supercollider/library/progressions/deep.scd"
  - "supercollider/library/progressions/drama.scd"
  - "supercollider/library/progressions/lift.scd"
  - "supercollider/library/progressions/melancholy.scd"
  - "supercollider/library/progressions/return.scd"
  - "supercollider/library/progressions/rocker.scd"
  - "supercollider/library_test.scd"
  - "supercollider/main.scd"
  - "supercollider/smoke_test.scd"
covered_digest: "v3:sha256:feed8cd9361e5faaff9e35bc383ebd3deeb49e10c78c68f8c5ee1314a9075e62"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: human_needed
  previous_score: 5/5
  gaps_closed:
    - "All nine previous human_verification items (distinctness, clean changes, pad smoothness, cycle-end switching, glide + Stop/Start, Auto over ~6 min, Auto picked mid-ride, classic parity, planner decisions) passed in 06-UAT.md (10/10, 0 issues)"
    - "Review findings WR-01..WR-04 fixed (bff3168, 1e6d677, 78210e0, ff08acc) and re-checked in code and by a full gate run"
  gaps_remaining: []
  regressions: []
---

# Phase 6: Shared Harmony & Progressions Verification Report

**Phase Goal:** As a rider, I want the music to move through chord progressions that bass, arp and pad follow together, so that it stops sounding like the same few notes for an hour.
**Verified:** 2026-10-13
**Status:** passed
**Re-verification:** Yes. The earlier report (2026-10-12, `human_needed`) went stale when the code-review fixes WR-01..WR-04 changed covered source files. It is regenerated here against current HEAD (`963d163`); there are no uncommitted changes in `supercollider/`, `scripts/` or `python_app/`.

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria, the contract)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Bass, arp, pad (and lead) change chord together, no clashes, including BPM glides and after Stop/Start | VERIFIED | `render.scd:177` pulls one memoized `~ppHarmonyFor.(bar, songBar)` entry for every pitched layer, and `render.scd:240` maps arp/lead onto the chord with `~ppFollowRows`. My own run of `bash scripts/check.sh` on HEAD: `CHECK OK: chord follow` for anthem, deep, drama, lift, melancholy, return and rocker (recorded run with a tempo change, strict in-chord rule), `CHECK OK: harmony units`, `CHECK OK: progression stop and start`. By ear: UAT tests 2 and 5 pass. |
| 2 | Pad chords move to the nearest voicing of the next chord | VERIFIED | `~ppNearestVoicing` in `harmony.scd` (min summed movement, window MIDI 40-64); `CHECK OK: harmony units` passes. By ear: UAT test 3 pass. |
| 3 | Selector lists at least 6 named progressions plus `classic`; each distinct; Auto chooses on its own | VERIFIED | Library holds `classic` + 7 named (anthem, deep, drama, lift, melancholy, return, rocker) plus `_template`; `CHECK OK: shipped progressions`; Python dropdown uses the Phase 5 folder scan. Auto: `CHECK OK: auto rotates progressions`, `auto keeps the playing progression first`, `auto stays bounded`, `auto adds a new progression file`, `auto skips a failing progression`, `auto reports a broken file once`. By ear: UAT tests 1, 6, 7 pass. |
| 4 | A named pick switches at the end of the current cycle, never mid-cycle, and stays | VERIFIED | Decided on the previous cycle's last bar in `harmony.scd`; covered by the units/auto tiers (all `CHECK OK`). By ear: UAT test 4 pass. |
| 5 | Exit gate: Stop silences every layer, re-evaluation stacks nothing, smoke + library check pass with every progression file | VERIFIED | My run on HEAD: `CHECK OK: eng-05 no stacking`, `eng-05 module re-evaluation`, `stop silences every layer`, `progression stop and start`, `progression re-evaluation`, `LIBRARY PASS`, `SMOKE PASS`, `CHECK PASS`, exit 0. |

**Score:** 5/5 truths verified (0 behavior-unverified; every previous by-ear item is now confirmed by the rider in 06-UAT.md).

### Plan-level truths and review fixes (re-checked after WR-01..WR-04)

| Item | Status | Evidence |
|------|--------|----------|
| Classic note-for-note unchanged (06-01) | VERIFIED | `PedalPulse libtest: parity rows=496 mismatches=0`, `CHECK OK: parity`; UAT test 8 pass. |
| WR-01 reserved stems `parent`/`proto` | VERIFIED | `loader.scd:55`: `["auto", "parent", "proto"].includesEqual(str).not` (uses `includesEqual`, the correct String comparison); rule documented at `loader.scd:36`. |
| WR-02 Auto draw counter survives Stop/Start | VERIFIED | `harmony.scd:58` `~ppAutoPicks = ~ppAutoPicks ? 0`, used in the seed at `harmony.scd:235-236`, not part of per-run state. UAT test 10 (rider listened across Stop/Start) pass. |
| WR-03 prefetch flag survives loader reload | VERIFIED | `loader.scd:183` `~ppAutoPrefetching = ~ppAutoPrefetching ? false`. `progression re-evaluation` and `eng-05 module re-evaluation` pass. |
| WR-04 library guard measured against a stable base | VERIFIED | `scripts/check.sh:202-204` takes `LIBRARY_GUARD_BASE`, else merge-base with `origin/main`, else HEAD; `CHECK OK: library guard self-test` (includes the new committed-edit, bad-base and no-commits cases) and `CHECK OK: library guard`. |
| Memo bounded; Auto seed varies per launch | VERIFIED | `auto stays bounded`; seeds 874786 and 874925 in the two engines of this run. |
| Malformed chord data refused (06-02) | VERIFIED | `harmony units` plus library-check negative controls pass. |

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `supercollider/core/harmony.scd` (545 lines) | VERIFIED | Substantive, reset from `main.scd:90` and `main.scd:283`. |
| `supercollider/core/render.scd` | VERIFIED | `~ppHarmonyFor` (177) and `~ppFollowRows` (240) wired into rendering. |
| `supercollider/core/loader.scd`, `validate.scd` | VERIFIED | Stem rule, prefetch scanner, `~ppChordDataReasons` exercised by the library check. |
| 7 chord-data progression files + `_template.scd` | VERIFIED | All on disk and loaded by `LIBRARY PASS` (library file count OK). |
| `supercollider/library/README.md`, `smoke_test.scd`, `library_test.scd`, `scripts/check.sh` | VERIFIED | Present, executed in this run. |

### Key Link Verification

| From | To | Status |
|------|----|--------|
| `render.scd ~ppRenderBar` | `~ppHarmonyFor` | WIRED (line 177) |
| `main.scd ~ppStart` / teardown | `~ppHarmReset` | WIRED (lines 90, 283) |
| `loader.scd ~ppLibLoad` | `~ppChordDataReasons` | WIRED |
| `harmony.scd ~ppHarmDecide` Auto branch | `~ppAutoPrefetch` | WIRED |
| Python dropdown | progressions folder | WIRED via Phase 5 `scan_library`; Python app stays send-only |

### Data-Flow Trace (Level 4)

Chord data flows from `library/progressions/*.scd` through the harmony cycle and memo into the rendered rows of every layer; the recorded chord-follow runs assert real notes against the chord. FLOWING.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full gate on HEAD | `bash scripts/check.sh` | `LIBRARY PASS`, `SMOKE PASS`, `CHECK PASS`, exit 0 | PASS |
| Python suite | `.venv/bin/pytest -q` | 191 passed | PASS |

The smoke log shows `FAILURE IN SERVER /n_set Node ... not found` lines around Stop; these are releases of already-freed nodes and the checks around them pass.

### Probe Execution

SKIPPED: no `probe-*.sh` declared or present.

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|--------------|-------------|--------|----------|
| HARM-01 | 06-01, 06-02, 06-03, 06-05 | Layers play over the same chord, no clashes | SATISFIED | SC1; chord-follow checks; UAT 2, 5 |
| HARM-02 | 06-03, 06-04, 06-05 | At least 6 named progressions plus classic | SATISFIED | 7 named + classic, table check; UAT 1 |
| HARM-03 | 06-01, 06-02, 06-05 | Pad voice-leading | SATISFIED | SC2; UAT 3 |
| HARM-04 | 06-01, 06-04, 06-05 | Select Auto or named; effective at cycle end | SATISFIED | SC4 and Auto tier; UAT 4, 6, 7, 10 |

All four IDs are declared in PLAN frontmatter and exist in REQUIREMENTS.md; no orphaned IDs for Phase 6. Bookkeeping: REQUIREMENTS.md still lists HARM-01..04 as `[ ]` / "Pending" and ROADMAP lists Phase 6 as `[ ]`. These should be ticked on phase completion (not a code gap).

### Prohibitions

| Prohibition | Tier | Result |
|-------------|------|--------|
| Classic unchanged (06-01) | test | Held: golden parity 0 mismatches. |
| No edit of committed library files/golden (06-01, 06-03) | test | Held: library guard and self-test pass. |
| Do not weaken checks to make files pass (06-02) | judgment | NON-AUTHORITATIVE LLM verdict: held. `unverified-prohibition: human review recommended` for a stricter audit (low risk). |
| Listening check not marked done by the executor (06-05) | judgment | Held: it was closed later by the rider in 06-UAT.md. |
| No engine-to-app message for Auto (06-04) | test | Held: Python app unchanged and send-only. |

### Anti-Patterns Found

None blocking. No TBD/FIXME/XXX in any phase-modified source file. Code-review warnings WR-01..WR-04 are fixed. The 4 Info findings (IN-01..IN-04: doc drift on the 2-3 minute hold vs 32-64 bars, history cap not retunable, shared voicing array, gate timeout headroom) are left open by design and are cosmetic or future-proofing.

### Human Verification Required

None. All ten UAT items passed (06-UAT.md, 10/10, 0 issues, completed 2026-10-13). Security: 06-SECURITY.md, threats_open 0.

### Gaps Summary

No gaps. Every must-have is backed by code read and a gate re-run on current HEAD (CHECK PASS, SMOKE PASS, LIBRARY PASS, 191 pytest). The phase goal is achieved.

---

_Verified: 2026-10-13_
_Verifier: Claude (gsd-verifier)_
