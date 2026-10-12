---
phase: 06-shared-harmony-progressions
verified: 2026-10-12T22:30:00Z
status: human_needed
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
covered_digest: "v3:sha256:2f097590e27f761f0cefd89b773e3889ec658d7fea1210658ba60ae907b65b16"
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Distinctness: pick each of anthem, rocker, lift, return, deep, melancholy, drama in turn (melody classic_lead_loud) and listen to at least two rounds each; write one plain sentence per progression and say if two sound too alike"
    expected: "Each progression is recognisably different from the others and from classic (ROADMAP SC3 'each one sounds distinct')"
    why_human: "'Sounds distinct' is a listening judgement. Automation only proves the chord tables differ (shipped progressions table check)."
  - test: "Clean changes: listen at every chord change on each progression, and on drama's E major (G sharp) chord"
    expected: "Bass, pad, arp and lead change chord together, with no sour or clashing note at the changes"
    why_human: "The static and recorded checks prove every note is a tone of its bar's chord. Whether the pad's 1.2 s release tail under the next chord (gate closes 1 beat early) sounds like a smeared wash is a by-ear call."
  - test: "Pad smoothness: pick deep, then anthem, and listen to the pad"
    expected: "The pad moves smoothly to a nearby voicing instead of jumping, and the old chord is already fading as the new one enters"
    why_human: "Voicing distance is proven numerically (nearest voicing, window 40-64); how it sounds is not."
  - test: "Cycle-end switching: while anthem plays, pick drama at a random moment"
    expected: "The change lands when anthem is back at Am, never in the middle of its four chords, and drama then stays"
    why_human: "The cycle-end rule is proven by the cycle log; hearing it at a real ride tempo is the rider's confirmation."
  - test: "Tempo glide and Stop/Start by ear: on drama press Up/Down so the tempo glides, then Stop and Start"
    expected: "Chords keep changing together during the glide; after Start the music begins on drama's first chord"
    why_human: "Recorded with a tempo change and covered by the smoke Stop/Start check, but the absence of audible clashes is by ear."
  - test: "Auto over about 6 minutes (melody classic_lead_loud)"
    expected: "Classic first, then a new 'PedalPulse: progression <name>' line every 2-3 minutes at the start of a round, never mid-round, never an immediate repeat. Note: the hold is 32-64 bars, so about 1-2 minutes at 128 BPM and 2-3 minutes at ~90 BPM (review IN-01)"
    why_human: "Pace feel at ride tempo; the 2-3 minute claim in the roadmap/README depends on BPM."
  - test: "Auto picked mid-ride: pick anthem, wait for its line, then pick Auto"
    expected: "Anthem keeps playing for a full hold before Auto rotates (planner decision, not yet confirmed by the rider)"
    why_human: "Planner decision made in yolo mode; the rider has to say whether adopt-then-hold feels right (06-05-SUMMARY, planner decision 3)."
  - test: "Classic parity by ear: pick classic in Progression and Melody"
    expected: "The original groove, unchanged"
    why_human: "Automated parity (496 rows, 0 mismatches against the golden) already proves it; listed only because the plan's listening check includes it."
  - test: "Planner decisions to confirm: ownHarmony opt-out, pad gate one beat early (~ppPadGapBeats = 1), Auto adopt-then-hold"
    expected: "Rider accepts or asks for a change"
    why_human: "Decisions recorded as unconfirmed in 06-05-SUMMARY; prohibition 06-05 (never mark the listening check done) is respected."
---

# Phase 6: Shared Harmony & Progressions Verification Report

**Phase Goal:** As a rider, I want the music to move through chord progressions that bass, arp and pad follow together, so that it stops sounding like the same few notes for an hour.
**Verified:** 2026-10-12
**Status:** human_needed
**Re-verification:** No, initial verification

All automated evidence passes and the code does what the phase claims. Status is `human_needed` only because the rider's by-ear listening check (distinct, clean, smooth, cycle-end, Auto pace) is recorded PENDING and cannot be verified by code. No truth FAILED.

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria, the contract)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Bass, arp, pad (and lead) change chord together, no clashes, incl. BPM glides and after Stop/Start | VERIFIED (by-ear part pending) | `harmony.scd:324-389` `~ppHarmonyFor` is a memoized per-(run, songBar) entry; every pitched layer pulls it in `render.scd:175-178`, so all layers see one chord by construction. Arp/lead mapped onto the chord by `~ppFollowRows` (`render.scd:237-246`); bass/pad from core defaults (`harmony.scd:501-537`). My run of `bash scripts/check.sh`: `CHECK OK: chord follow` for all 7 chord-data progressions (recorded run with tempo change, strict in-chord rule), `CHECK OK: harmony units`, `CHECK OK: progression stop and start`, `CHECK PASS`. |
| 2 | Pad chords move to the nearest voicing of the next chord | VERIFIED (sound pending) | `~ppNearestVoicing` (`harmony.scd:131-158`): minimum summed movement over all close inversions/octaves inside MIDI 40-64, tie-break to home mean then lower. Hand-checked anthem: Am 45 48 52, F 45 48 53, C 43 48 52, G 43 47 50 (matches plan). `harmony units` check passes. |
| 3 | Progression selector lists at least 6 named progressions plus classic; each distinct; Auto chooses on its own | VERIFIED (distinctness by ear pending) | Library has `classic` + 7 named (anthem, deep, drama, lift, melancholy, return, rocker) with different chord tables and descs; `CHECK OK: shipped progressions`. Python dropdown scans the folder (`python_app/library_logic.py:24 scan_library`), python_app unchanged since 3066535 and 191 pytest pass (I re-ran). Auto: `~ppHarmAutoNext` (`harmony.scd:223-266`) classic first, seeded no-quick-repeat picks at cycle ends; `CHECK OK: auto rotates progressions / adds a new progression file / skips a failing progression / reports a broken file once / stays bounded`. |
| 4 | Named pick switches at end of the current cycle, never mid-cycle, and stays | VERIFIED | `~ppHarmDecide` reads `~ppSel` and captures the module only at cycle boundaries; the next cycle is decided on the previous cycle's last bar (`harmony.scd:373-379`), so a late pick waits one more cycle. A named pick is not overwritten (`harmony.scd:288-293`). Post-window wording says "switches at the end of the current progression cycle" (`loader.scd:272`). Covered by units/auto tiers (all `CHECK OK`). |
| 5 | Exit gate: Stop silences every layer, re-evaluation stacks nothing, smoke + library check pass with every progression file | VERIFIED | My own run: `CHECK OK: eng-05 no stacking`, `eng-05 module re-evaluation`, `stop silences every layer`, `progression stop and start`, `progression re-evaluation`, `LIBRARY PASS` (all 15 files LIBCHECK OK incl. all 8 progressions), `SMOKE PASS`, `CHECK PASS`, exit 0. |

**Score:** 5/5 truths verified programmatically (0 behavior-unverified; by-ear aspects routed to human verification)

### PLAN-level truths spot-checked

| Truth (plan) | Status | Evidence |
|--------------|--------|----------|
| Classic note-for-note unchanged (06-01) | VERIFIED | `parity rows=496 mismatches=0`, `CHECK OK: parity`; `git diff 3066535..HEAD` shows no change to classic.scd, melody/palette classics or the golden (only additions plus the `_template.scd` rewrite). |
| Memo bounded, no mutable current-chord (06-01/06-04) | VERIFIED | `~ppHarmKeepBars = 64`, `~ppHarmLogCap = 256`, history cap 8; `auto stays bounded` passes. |
| Malformed chord data refused (06-02) | VERIFIED | `harmony units` / negative controls in check output pass (`~ppChordDataReasons` in validate.scd). |
| Auto seed posted, differs per launch (06-04) | VERIFIED | `PedalPulse: progression auto seed 835997` then `836136` in the two engines of my run. |
| Listening check never marked done (06-05 prohibition) | VERIFIED | 06-05-SUMMARY records it PENDING; planner decisions listed as unconfirmed. |

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `supercollider/core/harmony.scd` (539 lines) | VERIFIED | Substantive, loaded by `main.scd:38`, reset at `main.scd:90` and `283`. |
| `supercollider/core/render.scd` | VERIFIED | `~ppHarmonyFor.(` pulled at line 177; `~ppFollowRows` at 240. |
| `supercollider/core/validate.scd` / `loader.scd` | VERIFIED | `~ppChordDataReasons`, `~ppAutoPrefetch` present and exercised. |
| 7 chord-data progression files + `_template.scd` | VERIFIED | Chord data match the plan tables (e.g. drama has `root: 7, quality: \maj`; deep `barsPerChord: 2`). |
| `README.md`, melody `_template.scd`, smoke/library tests | VERIFIED | Present; smoke has the two new checks. |

### Key Link Verification

| From | To | Status |
|------|----|--------|
| `render.scd ~ppRenderBar` | `~ppHarmonyFor` | WIRED (line 177) |
| `main.scd ~ppStart` / teardown | `~ppHarmReset` | WIRED (lines 90, 283) |
| `loader.scd ~ppLibLoad` | `~ppChordDataReasons` | WIRED (library check refuses malformed data) |
| `harmony.scd ~ppHarmDecide` auto branch | `~ppAutoPrefetch` | WIRED (`harmony.scd:246,262`) |
| Python dropdown | progressions folder | WIRED via existing Phase 5 `scan_library`, no Python change needed |

### Data-Flow Trace (Level 4)

Chord data flows from `library/progressions/*.scd` through `~ppHarmCycle` -> `~ppHarmEntry` -> memo -> layers' rendered rows; confirmed by the recorded chord-follow runs against real notes. FLOWING.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full gate | `bash scripts/check.sh` | `LIBRARY PASS`, `SMOKE PASS`, `CHECK PASS`, exit 0 | PASS |
| Python suite | `.venv/bin/python -m pytest -q` | 191 passed | PASS |

Noted: the smoke log shows `FAILURE IN SERVER /n_set Node ... not found` lines around the Stop check; the check itself passed (these are the existing releases of already-freed nodes at Stop), not a verification failure.

### Probe Execution

SKIPPED: no `probe-*.sh` declared or present.

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|--------------|-------------|--------|----------|
| HARM-01 | 06-01, 06-02, 06-03, 06-05 | Layers play over the same chord, no clashes | SATISFIED (sound pending) | SC1 evidence |
| HARM-02 | 06-03, 06-04, 06-05 | At least 6 named progressions plus classic | SATISFIED (distinctness pending) | 7 named + classic on disk, table check passes |
| HARM-03 | 06-01, 06-02, 06-05 | Pad voice-leading | SATISFIED (sound pending) | SC2 evidence |
| HARM-04 | 06-01, 06-04, 06-05 | Select Auto or named, takes effect at cycle end | SATISFIED | SC4 + auto tier |

All four IDs appear in PLAN frontmatter and in REQUIREMENTS.md; no orphaned requirement IDs for Phase 6. Bookkeeping note: REQUIREMENTS.md still shows HARM-01..04 as unchecked / "Pending" and ROADMAP lists Phase 6 as `[ ]`; update after the listening check is closed.

### Prohibitions

| Prohibition | Tier | Result |
|-------------|------|--------|
| Classic unchanged (06-01) | test | Enforcement wired: golden parity 0 mismatches. Held. |
| No edit of committed library files/golden (06-01, 06-03) | test | Enforcement wired (`library_guard`, passes; self-test passes). `git diff` since 3066535 shows additions only. Held. Caveat WR-04 below. |
| Do not weaken checks to make files pass (06-02) | judgment | NON-AUTHORITATIVE LLM verdict: held. The only allowance is classic's implicit `extraPcs: [5]` (`harmony.scd:81`); chord-data files are checked strictly. `unverified-prohibition: human review recommended` for a stricter audit. |
| Listening check not performed/approved by executor (06-05) | judgment | Held (SUMMARY says PENDING). |
| No engine-to-app message for Auto (06-04) | test | Held: python_app byte-identical to pre-phase commit; messages go only to the post window. |

### Anti-Patterns Found

No TBD/FIXME/XXX in phase files. Open code-review findings (0 critical, all non-blocking, none refute a truth):

| Finding | Severity | Impact |
|---------|----------|--------|
| WR-01 stems `parent` / `proto` mishandled by the Event-based registry | Warning | A progression file named `parent.scd`/`proto.scd` is misbehaving but contained (classic fallback). Fix: reject reserved names. |
| WR-02 every Start replays the identical Auto order within one sclang session | Warning | Variety between Stop/Start rides is lower than the README implies; across engine launches the seed differs (verified). |
| WR-03 `~ppAutoPrefetching` reset on every load of loader.scd | Warning | Possible duplicate scanner after a mid-ride re-evaluation. Re-evaluation smoke check passes. |
| WR-04 library guard compares only the working tree to HEAD | Warning | A committed edit to a frozen library file would pass the guard; the golden still protects classic. I confirmed no such edit exists in this phase. |
| IN-01..IN-04 doc drift (2-3 minutes vs 32-64 bars), history cap not retunable, shared voicing array, gate timeout headroom | Info | Cosmetic or future-proofing. |

### Human Verification Required

See the `human_verification` list in the frontmatter. In short: the rider must listen for distinctness, sour notes at changes, pad smoothness and the 1-beat release overlap, cycle-end switching, glide and Stop/Start, Auto pace over about 6 minutes, Auto-picked-mid-ride behavior, and confirm the three unconfirmed planner decisions. I have not and cannot mark any of these as done.

### Gaps Summary

No gaps. Every must-have is backed by code I read and a gate I re-ran (CHECK PASS, 191 pytest). The phase is waiting only on the rider's listening check, so the status is `human_needed`, not `passed`. Recommended (optional) follow-ups from the review: WR-01 reserved-name rejection, WR-02 picks counter surviving Start, WR-04 guard base.

---

_Verified: 2026-10-12_
_Verifier: Claude (gsd-verifier)_
