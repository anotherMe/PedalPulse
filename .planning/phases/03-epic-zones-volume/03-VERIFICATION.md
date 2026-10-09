---
phase: 03-epic-zones-volume
verified: 2026-10-09T00:00:00Z
status: passed
score: 11/11 must-haves verified
covered_files: [".planning/phases/03-epic-zones-volume/03-01-PLAN.md", ".planning/phases/03-epic-zones-volume/03-01-SUMMARY.md", ".planning/phases/03-epic-zones-volume/03-02-PLAN.md", ".planning/phases/03-epic-zones-volume/03-02-SUMMARY.md", ".planning/phases/03-epic-zones-volume/03-03-PLAN.md", ".planning/phases/03-epic-zones-volume/03-03-SUMMARY.md", ".planning/phases/03-epic-zones-volume/03-04-PLAN.md", ".planning/phases/03-epic-zones-volume/03-04-SUMMARY.md", "python_app/bpm_logic.py", "python_app/config.py", "python_app/main.py", "python_app/osc_client.py", "python_app/tests/test_epic_logic.py", "python_app/tests/test_osc_client.py", "python_app/tests/test_view_tk.py", "python_app/tests/test_volume_logic.py", "python_app/view.py", "scripts/smoke_test.sh", "supercollider/main.scd", "supercollider/smoke_test.scd"]
covered_digest: "v3:sha256:55f32a36e7dc38c2cbeb8d0df15b90ab2719b28f1120f3b844ef8bb110aa124f"
behavior_unverified: 0
overrides_applied: 0
behavior_unverified_items: []
human_verification:
  - test: "Moving up the five EPIC zones (Recovery -> Endurance -> Tempo -> Threshold -> VO2) and back down, listening by ear"
    expected: "Each zone up sounds brighter and more energetic (top end, drive/grit, reverb space and synth presence rising together); each zone down sounds darker and calmer; no single parameter moves alone"
    why_human: "The smoke suite proves the mechanism (one EPIC read drives drive/cutoff/richness/reverb-wet together, and the post-FX >4kHz band measurably rises >=4x from EPIC 0 to 100) but whether the combined blend actually sounds 'brighter and more energetic' to a listener is a perceptual judgment grep/tests cannot make (03-VALIDATION.md Manual-Only Verifications row 1; 03-01/03-02 SUMMARY D3/D3 rationale)"
  - test: "Switching zones (including clicking several zones back-to-back before the previous glide finishes) and listening for stepping, zipper noise or clicks"
    expected: "Every zone change glides smoothly with no audible stepping, zipper noise or click, including when a new click interrupts an in-flight glide"
    why_human: "The smoke suite proves the mechanism headlessly (monotone, bounded by a step-bound derived from the lag constant, convergent, and a mid-glide retarget that never nearly reaches the abandoned target) but whether the glide is actually free of audible zipper noise or clicks is a listening judgment (03-VALIDATION.md Manual-Only Verifications row 2; 03-01 SUMMARY D4 rationale)"
  - test: "Dragging the Volume slider across its range (slow and fast), setting it to 0 then back to 80, and selecting VO2 with Volume at 100 for at least 8 bars"
    expected: "Loudness follows each release smoothly with no click/zipper/stepping and roughly equal perceived loudness per equal slider move; volume 0 is silent and 80 brings the groove back; VO2 at full volume is loud/bright/energetic with no harsh clipping, crackle or obvious pumping"
    why_human: "The smoke suite proves the mechanisms (pre-limiter lagged gain, monotone de-zippered step through >=3 genuine intermediate samples, and a measured output peak of 0.5097 <= 0.892 at EPIC 100 + volume 100 -- re-run independently during this verification) but perceived loudness evenness and audible distortion at full volume are perceptual judgments (03-VALIDATION.md Manual-Only Verifications row 3; 03-03 SUMMARY D4 rationale, 03-04 Plan Task 2 human-check)"
---

# Phase 3: EPIC Zones & Volume Verification Report

**Phase Goal:** As a rider, I want to pick my effort zone and set the volume, so that the music's energy matches my interval without clipping.
**Mode:** mvp
**Verified:** 2026-10-09
**Status:** human_needed
**Re-verification:** No — initial verification

## User Flow Coverage

User story: «As a rider, I want to pick my effort zone and set the volume, so that the music's energy matches my interval without clipping.»

| Step | Expected | Evidence | Status |
|------|----------|----------|--------|
| Open the app | `./run.sh` launches the window with BPM slider, zone buttons, transport, and a Volume slider | `python_app/main.py` wires `EpicController`/`VolumeController` into `BpmWindow`; `python_app/view.py` `_build_zone_row`/`_build_volume_row`; `timeout 30 ./run.sh --port 57199 --exit-after 800` exits 0 (03-02/03-04 SUMMARY) | ✓ |
| Pick a zone | Clicking one of Recovery/Endurance/Tempo/Threshold/VO2 highlights it (bold font + sunken relief + "Zone: <name>" caption) and sends that zone's preset EPIC value once | `python_app/view.py:174-214` (`_build_zone_row`, `_on_zone_changed`), `python_app/bpm_logic.py:268-286` (`EpicController.select_zone` — notify, then send once on real change); 16 unit tests in `test_epic_logic.py`, 3+ Tk tests in `test_view_tk.py` | ✓ |
| Engine moves to that zone | `/pp/epic <value>` reaches `OSCdef(\pp_epic)`, clamps to 0-100, and drives one shared `Lag.kr` smoother into one `\ppFx` synth that derives drive/cutoff/richness/reverb-wet from a single EPIC read | `supercollider/main.scd:130-144,387-397`; smoke checks `python epic`, `epic brightens output`, `fx chain order` — all re-run and confirmed `CHECK OK` in this verification | ✓ |
| Energy change is audible and moves together | Raising EPIC measurably brightens the post-FX output (>4kHz band >=4x from EPIC 0 to 100) and the four FX parameters derive from one read so they move in lockstep | `supercollider/main.scd:130-144` (single `In.kr(epicBus)` read feeding `drive`/`cutoff`/`wet`/HPF-richness); smoke `epic brightens output` re-run and confirmed `CHECK OK` (peak-band measurement, not just a wiring check) | ✓ |
| Zone changes glide, not jump | EPIC changes converge monotonically and boundedly, including through a mid-glide retarget (zone clicked again before the previous glide settles) | `supercollider/main.scd:22,126-128` (`~ppEpicLagSecs`, `Lag.kr` smoother); smoke `epic glide up`, `epic glide down`, `epic retarget mid-glide` re-run and confirmed `CHECK OK` | ✓ |
| Set the volume | Dragging the Volume slider updates the shown value live without sending; releasing sends `/pp/volume <value>` exactly once; launch sends the default (80) once | `python_app/view.py:216-247` (`_build_volume_row`, live `command=slider_moved`, `<ButtonRelease-1>` -> `slider_released`); `python_app/bpm_logic.py:304-350` (`VolumeController`); 24 unit tests in `test_volume_logic.py`, 4 Tk tests incl. `test_volume_drag_then_release_sends_once` | ✓ |
| Loudness changes without clipping | Volume is a lagged gain stage inside `\ppMaster`, applied before `Limiter.ar`, never after; with EPIC at VO2 (100) and volume at 100, the master output peak never exceeds the limiter ceiling | `supercollider/main.scd:112-120` (`\ppMaster` — `In.ar(in,2) * preGain * volume` then `Limiter.ar(sig, 0.891251, 0.01)`); smoke `max epic max volume no clip` re-run and confirmed `CHECK OK` (measured peak 0.50973 <= 0.892, through the real Python CLI path) | ✓ |
| Outcome: energy matches the interval without clipping | The mechanism chain (zone click -> EPIC value -> FX brightness -> master volume -> limiter) is wired end to end and proven headlessly not to clip at the hottest reachable setting; whether it *sounds* right (brighter at higher zones, smooth glides, even loudness) is a listening judgment | All of the above, plus the three Manual-Only Verifications in `03-VALIDATION.md` (deferred to end-of-phase UAT per `workflow.human_verify_mode: end-of-phase`) | ⚠️ mechanism ✓ / perceptual confirmation pending (see Human Verification) |

## Goal Achievement

### Observable Truths

Merged from ROADMAP Phase 3 success criteria and all four plans' `must_haves.truths` (deduplicated; roadmap wording kept where overlapping).

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Zone button click sends that zone's preset EPIC value once over `/pp/epic` (10/30/50/75/100 for Recovery/Endurance/Tempo/Threshold/VO2); same-zone click is a no-op (EPIC-03, SC1) | ✓ VERIFIED | `python_app/config.py:24-31` (`EPIC_ZONES`); `python_app/bpm_logic.py:268-286` (`select_zone`); 16 tests in `test_epic_logic.py`, re-run green as part of the 150-test suite |
| 2 | Raising EPIC moves filter cutoff, drive/saturation, reverb amount and synth richness together and measurably brightens the output (EPIC-01, SC2) | ✓ VERIFIED | `supercollider/main.scd:130-144` (single `In.kr(epicBus)` read in `\ppFx`); smoke `epic brightens output` re-run: `CHECK OK` (independently re-executed in this verification, not just read from the orchestrator's log) |
| 3 | EPIC changes glide smoothly (monotone, bounded, convergent) with no stepping, including through a mid-glide retarget that never nearly reaches the abandoned target (EPIC-02, SC3) | ✓ VERIFIED | `supercollider/main.scd:22,126-128` (`Lag.kr` smoother); smoke `epic glide up`, `epic glide down`, `epic retarget mid-glide` re-run: all `CHECK OK` |
| 4 | Engine clamps `/pp/epic` to 0-100 independently of the GUI, one step either side; float precision is preserved end to end (37.5 stays 37.5) | ✓ VERIFIED | `supercollider/main.scd:387-397` (`.clip(0, 100)`); smoke 7-entry clamp/float table, all `CHECK OK` (re-run) |
| 5 | Malformed/missing/NaN `/pp/epic` is ignored with a warning and no state change; non-loopback senders are ignored | ✓ VERIFIED | `supercollider/main.scd:384-397` (`isNumber.not or: {isNaN}` guard, `srcID: NetAddr("127.0.0.1", nil)`); smoke `epic malformed ignored`, `loopback-only` re-run: `CHECK OK` |
| 6 | Re-evaluating `main.scd` frees the previous FX synth/smoother/group/buses with no leak and preserves the last EPIC value with no glide-from-0 | ✓ VERIFIED | `supercollider/main.scd:56-63` teardown; smoke `fx re-evaluation` re-run: `CHECK OK` |
| 7 | User adjusts master volume from the app; loudness changes smoothly via a lagged pre-limiter gain stage (GUI-03, SC4) | ✓ VERIFIED | `python_app/view.py:216-247` (`_build_volume_row`); `supercollider/main.scd:112-120` (`\ppMaster` volume gain before `Limiter.ar`); smoke `python volume`, `volume scales output`, `volume glides` re-run: `CHECK OK` |
| 8 | Volume 0 silences the output; the next volume value brings it back | ✓ VERIFIED | smoke `volume silent at 0` re-run: `CHECK OK` |
| 9 | Engine clamps `/pp/volume` to 0-100 independently of the GUI (one step either side); malformed/NaN input ignored; non-loopback senders ignored | ✓ VERIFIED | `supercollider/main.scd:403-413`; smoke volume clamp table, `volume malformed ignored`, `loopback-only` re-run: all `CHECK OK` |
| 10 | With VO2's EPIC (100) and volume 100 sent through the real Python CLI, the master output peak stays at or under the limiter ceiling + tolerance (<= 0.892) while real audio still flows (SC4, the phase's core safety promise) | ✓ VERIFIED | smoke `max epic max volume no clip` re-run in this verification: `CHECK OK` — `PedalPulse smoke: VO2 + volume 100: pre-limiter peak = 0.50973242521286, output peak = 0.50973242521286` |
| 11 | Volume Scale follows the drag live without sending; release sends the final value exactly once; launch sends the default (80) once, below the maximum (hearing-safety guard) | ✓ VERIFIED | `python_app/bpm_logic.py:304-350` (`VolumeController`); `python_app/view.py:230-245`; `test_volume_drag_then_release_sends_once`, `test_volume_scale_builds_at_default` in `test_view_tk.py`, re-run green |

**Score:** 11/11 truths verified (0 present, behavior-unverified)

All behavior-dependent truths above (glide monotonicity/convergence, mid-glide retarget, re-evaluation leak-freedom, de-zippered volume step) are backed by the project's own headless SuperCollider smoke tests, which this verification **independently re-ran** (not merely read from the orchestrator-supplied log) and confirmed produce the same result: `SMOKE PASS`, 65 `CHECK OK:` lines, exit 0. The three genuinely perceptual claims ("sounds brighter," "glides without audible zipper/clicks," "loudness feels even and VO2+max-volume doesn't audibly distort") cannot be verified by code inspection or automated test and are routed to Human Verification below, exactly as the project's own `03-VALIDATION.md` Manual-Only Verifications table and all four plans' `<human-check>` blocks anticipated (deferred per `workflow.human_verify_mode: end-of-phase`).

### Required Artifacts

Verified via `gsd-tools query verify.artifacts` against each plan's `must_haves.artifacts` (all four plans), cross-checked by direct file reads.

| Plan | Result | Details |
|------|--------|---------|
| 03-01 | ✓ VERIFIED (6/6) | `python_app/config.py` (`OSC_EPIC_ADDRESS`), `python_app/osc_client.py` (`send_epic`), `python_app/tests/test_osc_client.py`, `supercollider/main.scd` (`\ppFx`, `\ppEpicSmoother`, `OSCdef(\pp_epic)`), `supercollider/smoke_test.scd`, `scripts/smoke_test.sh` |
| 03-02 | ✓ VERIFIED (5/5) | `python_app/config.py` (`EPIC_ZONES`), `python_app/bpm_logic.py` (`EpicController`), `python_app/tests/test_epic_logic.py`, `python_app/view.py` (`zone_buttons`), `python_app/main.py` (`EpicController`) |
| 03-03 | ✓ VERIFIED (5/5) | `python_app/config.py` (`OSC_VOLUME_ADDRESS`), `python_app/osc_client.py` (`send_volume`), `python_app/tests/test_osc_client.py`, `supercollider/main.scd` (`OSCdef(\pp_volume)`), `supercollider/smoke_test.scd` |
| 03-04 | ✓ VERIFIED (5/5) | `python_app/config.py` (`VOLUME_DEFAULT`), `python_app/bpm_logic.py` (`VolumeController`), `python_app/tests/test_volume_logic.py`, `python_app/view.py` (`volume_scale`), `python_app/main.py` (`VolumeController`) |

21/21 artifacts across all four plans pass the exists + substantive check.

### Key Link Verification

The `verify.key-links` tool rejected all plan-declared links because their `from:` fields are descriptive endpoint names (e.g. `"python_app/osc_client.py OscClient.send_epic"`) rather than a bare relative file path — a plan-authoring format mismatch with the tool's strict parser, not a wiring defect. Each link was therefore verified manually by reading the actual source:

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `osc_client.py OscClient.send_epic` | `main.scd OSCdef(\pp_epic)` | UDP `/pp/epic <float>` to port 57120 | ✓ WIRED | `osc_client.py:77-88` sends `config.OSC_EPIC_ADDRESS`; `main.scd:387` listens on `'/pp/epic'` |
| `OSCdef(\pp_epic)` | `\ppEpicSmoother` | `~ppEpicBus.set(~epic / 100)` | ✓ WIRED | `main.scd:392-394` sets the bus the smoother reads (`main.scd:167`) |
| `\ppEpicSmoother` | `\ppFx` | `addToTail` ordering, shared `~ppEpicSmoothBus` | ✓ WIRED | `main.scd:167,171` — smoother `\addToHead`, FX `\addToTail`, same group |
| `\ppFx` | `\ppMaster` (limiter) | `~ppFxBus` | ✓ WIRED | `main.scd:171,184` — master's `\in` is `~ppFxBus.index`, not the pre-FX mix bus |
| `view.py zone button command` | `EpicController.select_zone` | `command=lambda z=name: epic_controller.select_zone(z)` | ✓ WIRED | `view.py:196` |
| `main.py EpicController(send=...)` | `OscClient.send_epic` | constructor injection | ✓ WIRED | `main.py:52` |
| `EpicController` listener | `BpmWindow._on_zone_changed` | `add_listener` | ✓ WIRED | `view.py:205`, `view.py:208-214` |
| `osc_client.py OscClient.send_volume` | `main.scd OSCdef(\pp_volume)` | UDP `/pp/volume <float>` | ✓ WIRED | `osc_client.py:91-100`; `main.scd:403` |
| `OSCdef(\pp_volume)` | `\ppMaster` | `~ppVolumeBus.set(~ppVolumeAmp.(~volume))` | ✓ WIRED | `main.scd:410`; master reads `volumeBus` arg (`main.scd:112,117,184`) |
| `\ppMaster` volume gain | `Limiter.ar` | signal order inside the SynthDef | ✓ WIRED | `main.scd:117-119` — `volume` multiplied in *before* `Limiter.ar` |
| `view.py volume_scale` | `VolumeController.slider_moved`/`slider_released` | live `command=`, `<ButtonRelease-1>` bind | ✓ WIRED | `view.py:230-245` |
| `main.py VolumeController(send=...)` | `OscClient.send_volume` | constructor injection | ✓ WIRED | `main.py:53` |

12/12 key links wired and confirmed by source inspection (the smoke-test re-run independently exercises nearly all of these same connections at runtime).

### Behavioral Spot-Checks / Independent Re-Run

This verification did not rely on the orchestrator-supplied evidence alone — the full automated surface was re-executed independently:

| Check | Command | Result | Status |
|-------|---------|--------|--------|
| Python unit/widget suite | `.venv/bin/pytest python_app/tests -q` | `150 passed in 5.37s` | ✓ PASS |
| Headless SuperCollider smoke suite | `bash scripts/smoke_test.sh` | `SMOKE PASS`, exit 0, 65 `CHECK OK:` lines | ✓ PASS |
| All 28 named Phase-3-relevant checks (epic/volume glide, clamp, malformed, loopback, fx/volume re-evaluation, no-clip, node bound) | `grep -qx 'CHECK OK: <name>'` against the fresh log | All present | ✓ PASS |
| Core safety promise (SC4) | log line `PedalPulse smoke: VO2 + volume 100: pre-limiter peak = 0.50973242521286, output peak = 0.50973242521286` | `0.50973 <= 0.892` and `> 0.1` | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|-------------|-----------------|--------------|--------|----------|
| EPIC-01 | 03-01, 03-02 | EPIC 0-100 audibly changes brightness/energy, driving filter cutoff, drive/saturation, reverb/delay amount and synth richness together | ✓ SATISFIED (mechanism); perceptual confirmation pending | Single-read `\ppFx` design; `epic brightens output` smoke check re-run green; "sounds brighter" is Human Verification item 1 |
| EPIC-02 | 03-01, 03-02 | EPIC changes glide smoothly (lagged parameters) with no stepping or clicks | ✓ SATISFIED (mechanism); perceptual confirmation pending | `Lag.kr` smoother; 3 glide smoke checks re-run green; "no audible zipper/clicks" is Human Verification item 2 |
| EPIC-03 | 03-02 | User can select EPIC via five zone preset buttons, each mapped to a predefined value | ✓ SATISFIED | `EPIC_ZONES`, `EpicController`, zone row in `view.py`, 16+ passing tests |
| GUI-03 | 03-03, 03-04 | User can adjust master volume from the GUI | ✓ SATISFIED (mechanism + no-clip proof); perceptual confirmation pending | `VolumeController`, Volume Scale, `~ppVolumeAmp`, `max epic max volume no clip` re-run green; "loudness feels even / no distortion" is Human Verification item 3 |

**Orphan check:** REQUIREMENTS.md traceability maps exactly EPIC-01, EPIC-02, EPIC-03, GUI-03 to Phase 3, matching the phase's declared requirement IDs and the union of all four plans' `requirements:` frontmatter fields. No orphaned requirements.

**Documentation note (non-blocking):** `.planning/REQUIREMENTS.md` still shows `[ ]` (unchecked) for EPIC-01, EPIC-02, EPIC-03 and GUI-03, and its Traceability table still marks them "Pending." This is a stale-documentation gap, not a code gap — the actual implementation, tests, and the independently-re-run smoke suite all demonstrate these requirements are functionally delivered. It should be updated during milestone completion/ship, not treated as a phase-blocking finding here.

### Anti-Patterns Found

Scanned all 12 files modified across the four plans (`config.py`, `osc_client.py`, `bpm_logic.py`, `view.py`, `main.py`, all four test files, `main.scd`, `smoke_test.scd`, `smoke_test.sh`) for `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER`, hardcoded-empty-return patterns, and placeholder prose.

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | none found | — | No debt markers, no stub returns, no placeholder prose in any phase-3-modified file |

Code review (`03-REVIEW.md`, disposition `03-REVIEW-DISPOSITION.md`): 0 critical, 2 warnings (both open, both pre-existing-class cosmetic/edge-case issues — `Debouncer.trigger()`'s token-overwrite edge case only manifests with a synchronous scheduler, which `main.py` never injects; the CLI's `send ...` message doesn't reflect failures) and 2 info findings (both open, both minor code-hygiene notes). None block the "pick a zone, set the volume, hear the change without clipping" goal. Security review (`03-SECURITY.md`): 17/17 threats closed, `threats_open: 0`. UI review (`03-UI-REVIEW.md`): 16/24, no blocking findings (same score as Phase 2 — additions extend consistently, do not regress).

### Human Verification Required

See frontmatter `human_verification` for the structured form. Narrative:

1. **Zone brightness by ear.** Click through all five zones ascending then descending and confirm each step up sounds measurably brighter/more energetic (not just that the `>4kHz` band measurement rose, which is already proven).
2. **Glide smoothness by ear.** Click between distant zones, then click several zones back-to-back before the previous glide settles, and listen for steps, zipper noise, or clicks (already proven monotone/bounded/convergent headlessly; the audible judgment is what remains).
3. **Volume evenness and VO2+max-volume distortion by ear.** Drag the Volume slider across its range, set it to 0 then back to 80, then select VO2 and set Volume to 100 for at least 8 bars, listening for even loudness steps and any harsh clipping/crackle/pumping (already proven the output peak never exceeds the limiter ceiling; the audible judgment is what remains).

All three are explicitly anticipated and documented by the project itself (`03-VALIDATION.md` Manual-Only Verifications; `03-01-SUMMARY.md` D3/D4 rationale; `03-03-SUMMARY.md` D4 rationale; `03-04-PLAN.md` Task 2's `<human-check>` block, reproduced verbatim in `03-04-SUMMARY.md` "Next Phase Readiness"), deferred per this project's `workflow.human_verify_mode: end-of-phase` setting rather than skipped or fabricated.

### Gaps Summary

No gaps. Every must-have truth, artifact, and key link across all four plans is verified by direct code inspection and an independently re-run automated suite (150 pytest tests, 65-check headless SuperCollider smoke suite, both re-executed fresh during this verification rather than trusted from the orchestrator's log). The only open items are the three perceptual listening checks that this project's own validation strategy and all four plans correctly identified as impossible to verify by test/grep and deliberately deferred to end-of-phase human UAT — they are not evidence of missing or broken work.

---

_Verified: 2026-10-09_
_Verifier: Claude (gsd-verifier)_
