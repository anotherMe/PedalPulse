---
phase: 05-library-selectors-in-the-gui
audited: 2026-10-12
auditor: gsd-ui-auditor (code-only audit; persisted by the execute-phase orchestrator, because the auditor returned its report without writing the file)
baseline: abstract 6-pillar standards plus 05-CONTEXT.md decisions D-01..D-09 (no UI-SPEC.md for this phase)
screenshots: none (Tkinter desktop app, no dev server)
interaction_capture: false
scores:
  copywriting: 3
  visuals: 3
  color: 3
  typography: 3
  spacing: 3
  experience_design: 2
overall: 17/24
---

# Phase 05: UI Review

**Audited:** 2026-10-12 (code-only audit)
**Baseline:** abstract 6-pillar standards plus 05-CONTEXT.md decisions D-01..D-09. No UI-SPEC.md exists for this phase.
**Screenshots:** not captured. This is a Tkinter desktop app with no dev server, so the visual pillars are scored from the code.
**Test run:** `.venv/bin/python -m pytest -q python_app/tests` gives 191 passed.

## Pillar Scores

| Pillar | Score | Key Finding |
|---|---|---|
| 1. Copywriting | 3/4 | Labels are the exact file names (D-06). "Auto" is never explained in the window. |
| 2. Visuals | 3/4 | The label-above-dropdown column is clean. The three dropdowns have no group heading, and names over 20 characters are cut off on the closed button. |
| 3. Color | 3/4 | No hardcoded colors; the native theme is used. When the selected file is deleted, the open menu shows no checked entry. |
| 4. Typography | 3/4 | The category labels use the same default font as the "BPM" and "Volume" captions, so the column has no heading level. |
| 5. Spacing | 3/4 | Padding reuses the existing 4/8/10/12 values. The fixed 20-character width cuts valid names of 21 to 64 characters. |
| 6. Experience Design | 2/4 | The window can show a selection the engine does not hold (after an engine restart, or a refused name), with no in-window signal. |

**Overall: 17/24**

## Orchestrator Verification of the Findings

The orchestrator checked the auditor's top fixes against the code after the WR-01/WR-02/WR-03 review fixes and against the project's recorded decisions.

| Note | Finding | Verified result |
|---|---|---|
| V1 | Fix 1: the GUI and the engine disagree after an engine restart | **Accurate, but already known and accepted.** This is milestone audit W2 in STATE.md ("no resync after an engine restart ... restarting the app resyncs"), accepted under the send-only design, with LINK-04 deferred in REQUIREMENTS.md. The auditor's BLOCKER label is its own; the project has accepted this. One real inaccuracy remains: D-04 in 05-CONTEXT.md says the startup send "keeps the GUI and the engine in agreement, even after an engine restart". The startup send runs only when the app launches, so the sentence holds only if the app is relaunched too. |
| V2 | Fix 2: failed sends are invisible; `LibrarySelector.select` discards the send result | **Premise out of date.** Since WR-01, `select()` keeps the send result (`_last_send_ok`) so a failed send can be retried by re-picking the same name. A send to a stopped engine does not fail at all: UDP is connectionless, so `send_selection` returns True with no listener (05-02 SUMMARY D4). The proposed "Not sent: engine not reachable" label would therefore never appear when the engine is down. "No feedback when the engine is not running" was accepted by design in the Phase 2 UI review (send-only app). |
| V3 | Fix 3: names over 20 characters are cut off on the closed dropdown | **Accurate, and a recorded design decision.** 05-01 SUMMARY: "Dropdown width fixed at 20 characters so the window never resizes; a longer stem is cut on the closed button, full in the open menu". The longest name on disk today is `classic_lead_loud` (17 characters). |
| V4 | Pillar 3: a deleted selected file leaves no checked entry in the open menu | **Accurate, and by design.** 05-03 SUMMARY: "The rebuild never sets the StringVar, so a selected name whose file was deleted stays shown on the closed dropdown". |

## Top 3 Priority Fixes (as reported by the auditor)

1. **Engine restart desyncs the GUI, and re-picking does nothing** (auditor: BLOCKER; see V1). If SuperCollider is restarted while the app keeps running, the engine falls back to `classic` but the dropdown still shows the old name. Picking that same name sends nothing (D-05), so the rider has to pick another name and then pick back, or relaunch the app. Suggested fix: either (a) correct the D-04 wording and add a README line "after restarting SuperCollider, quit and relaunch PedalPulse", or (b) add a re-sync action, which conflicts with the locked D-05 and needs the rider's decision.
2. **Failed sends are invisible in the window** (auditor: WARNING; see V2 for why the proposed fix would not fire). Suggested fix: show a short "Not sent" status when `send_selection` returns False.
3. **Valid long names are truncated on the closed dropdown** (auditor: WARNING; see V3). Suggested fix: size the width to the longest name on disk plus a margin, or show the full name in a tooltip.

## Detailed Findings

### Pillar 1: Copywriting (3/4)

- The labels "Palette", "Progression" and "Melody" (`python_app/config.py`) and the names shown in the menu follow D-06 exactly.
- "Auto" (`config.AUTO_LABEL`) is not explained in the window. A rider who has not read the README will not know it means the engine's default (`classic`). Minor.
- No copy covers the error case (see Fix 2 and V2).

### Pillar 2: Visuals (3/4)

- `_build_library_column` (`python_app/view.py`) puts a label above each dropdown. The column sits to the right of the unchanged controls, as D-02 requires.
- There is no column heading such as "Variations", so the three dropdowns read as loose items rather than one group. Minor.
- The fixed width cuts names over 20 characters on the closed button (see Fix 3 and V3).

### Pillar 3: Color (3/4)

- No hex or `rgb(` literals in `view.py`. The widgets use the native aqua theme.
- The selected item shows only through the native radio indicator in the open menu. When the selected file is deleted, the open menu has no checked entry while the closed button still shows the old name (see V4).

### Pillar 4: Typography (3/4)

- The category labels and dropdowns use the default font, the same as the existing "BPM" and "Volume" captions. The only emphasised text is the 16-point bold BPM entry.
- The column has no heading and no distinct weight. Minor.

### Pillar 5: Spacing (3/4)

- Label `pady=(0, 2)`, dropdown `pady=(0, 10)`, column `pady=10` and `padx=(0, 12)`. These reuse the existing values, so spacing is consistent.
- `LIBRARY_DROPDOWN_WIDTH = 20` is a fixed character count, not tied to the content (see V3).
- The window is not resizable, and a selection change never changes its width (covered by the fixed-width test).

### Pillar 6: Experience Design (2/4)

- Strengths: `takefocus=0` on every dropdown, no key bindings and no focus calls on the column, rescan on open through the menu `postcommand`, and a deleted selection keeps its label without crashing. All are covered by tests, and all 191 pass.
- Desync after an engine restart (Fix 1, V1).
- No in-window signal for a failed send (Fix 2, V2).
- Refused names: an unknown name is sent and the engine refuses it, but the window keeps showing it while the engine stays on the previous file. This is by design (the engine is the validator). The refusal shows only in the SuperCollider post window.
- Keyboard: the BPM arrow keys survive dropdown use (`test_arrow_keys_still_nudge_bpm_after_using_each_dropdown`). A real native click cannot be tested here and is a manual UAT step.

## Files Audited

- `python_app/view.py`
- `python_app/library_logic.py`
- `python_app/config.py`
- `python_app/main.py`
- `python_app/osc_client.py`
- `supercollider/library/README.md` (section "Pick a variation from the app")
- `.planning/phases/05-library-selectors-in-the-gui/05-CONTEXT.md`, `05-01/02/03-PLAN.md`, `05-01/02/03-SUMMARY.md`

## Recommendation Count

- Priority fixes: 3 (auditor labels: 1 BLOCKER, 2 WARNING). After verification: 1 accepted known limitation with a D-04 wording error (V1), 1 out-of-date premise (V2), 1 recorded design trade-off (V3).
- Minor recommendations: 3 (no column heading; "Auto" not explained in the window; no in-window feedback for a refused name).
