# Phase 01 — UI Review

**Audited:** 2026-10-09
**Baseline:** Abstract 6-pillar standards (no UI-SPEC.md for Phase 01)
**Screenshots:** Not captured (Tkinter desktop app, no dev server — code-only audit)
**Interaction captures:** off (workflow.ui_interaction_capture is false)

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 3/4 | Clear labels on controls; entry field lacks visible label or tooltip |
| 2. Visuals | 2/4 | Minimal visual hierarchy; limited use of size/weight to signal importance |
| 3. Color | 2/4 | All default Tk colors; no contrast verification; no accessibility testing |
| 4. Typography | 2/4 | Only one font size used (TkDefaultFont); one bold exception (entry) creates jarring jump |
| 5. Spacing | 2/4 | Inconsistent spacing scale (padx 4, 8, 12; pady 0, 4, 8, 10); no unified system |
| 6. Experience Design | 3/4 | Controls interactive and responsive; no error visual feedback; no OSC failure indication |

**Overall: 14/24**

---

## Top 3 Priority Fixes

1. **Inconsistent spacing scale** — Visual incoherence — Define a spacing scale (4px units) and apply consistently across all padding/margin values. Replace padx=4, 8, 12 with a base unit: change `padx=12` → `padx=16` (4×4), `pady=10` → `pady=8`, `padx=8` → `padx=8`, `padx=4` → `padx=4`.

2. **Entry field has no visual label** — User confusion — Add a label widget above or to the left of the entry field with text "Enter BPM" or "BPM:" to signal the field is editable and what it accepts. Alternatively, add a tooltip via a simple hover binding or docstring-derived help text.

3. **No error visual feedback on send failure** — Hidden failures — When `OscClient.send_bpm()` returns False (OSError on send), the entry field or status label should show a red border or text like "Connection lost" for 2 seconds. Currently silent failures leave the user unaware the command didn't reach the engine.

---

## Detailed Findings

### Pillar 1: Copywriting (3/4)

**Strengths:**
- Window title "PedalPulse" is clear and branded (file: `python_app/view.py:26`).
- Scale label "BPM" is concise and correct (line 41).
- Nudge button labels use U+2212 MINUS SIGN for negative deltas: "−5", "−1", "+1", "+5" (line 16, NUDGE_LABELS dict), not ASCII hyphens — typographically correct.
- Status text "Sending to 127.0.0.1:57120" is informative and matches D-22 (line 50 in `main.py`, generated dynamically).
- Checkbox label "On top" is concise (line 99).
- Error messages in `tkcheck.py` are clear: "ERROR: Tkinter is not available in this Python..." (line 42) and "ERROR: Tcl/Tk X.X is too old" (line 51).

**Weaknesses:**
- **Entry field has no label.** The field appears as a text box between nudge buttons with no visible indication it is editable, what it accepts, or that it is the primary BPM input. A label like "BPM" or "Enter BPM" would clarify. *Issue type: UX clarity; severity: medium.*
- **No tooltip or help text.** Tkinter doesn't have built-in tooltips; adding a simple `bind("<Enter>")` show-hint pattern would help.
- **No validation feedback copy.** Invalid entry ("abc", "nan") silently reverts without a message. Users see the value change back but may not understand why. *Issue type: feedback; severity: low.*
- **Status text is machine-readable, not user-friendly.** "Sending to 127.0.0.1:57120" is correct but verbose for a compact window. Alternative: "Engine: ready" or "Offline" would be clearer.

**Evidence:**
- Grep for text labels: `grep -n "text=" python_app/view.py` shows labels on Scale ("BPM"), buttons (NUDGE_LABELS), status (status_text), checkbox ("On top"), but no label for the Entry widget (line 68).
- Entry field definition (lines 67–75) has no paired Label widget.
- No tooltip binding on entry or other widgets.

---

### Pillar 2: Visuals (2/4)

**Strengths:**
- **Clear focal point:** The entry field (TkDefaultFont 16 bold) is the visual center and draws attention (line 73).
- **Compact layout:** Window uses `resizable(False, False)` and tight padding (padx=12, pady=10), appropriate for floating over Zwift (line 27).
- **Visual separation:** Nudge row is visually distinct from the slider row (Frame with pady=8, line 53).
- **No clutter:** Minimal widgets; every element has a purpose.
- **Icon-free design:** No icons; labels only — appropriate for a technical control panel.

**Weaknesses:**
- **Minimal visual hierarchy.** Only one effective size distinction: entry field (16px bold) vs. everything else (default Tk size, ~11px). The slider label "BPM" is the same size as button text. No clear primary → secondary → tertiary visual order.
- **No active/inactive states.** Buttons have no visual feedback for hover or press states (Tkinter's default is very subtle; some platforms show no change at all).
- **No focus ring visibility.** When the entry field has focus, Tk's default focus indicator is platform-dependent and often hard to see. No custom focus styling.
- **Jarring size jump.** The entry field (16px) is significantly larger than everything else, which helps focus but breaks visual harmony. The slider and buttons feel cramped by comparison.
- **No disabled state styling.** If the entry were ever disabled (e.g., engine offline), there is no visual indication.

**Evidence:**
- Font definition (line 73): only one custom font size, `("TkDefaultFont", 16, "bold")` for the entry.
- All other widgets use default TkDefaultFont (no explicit font parameter).
- No -bg, -fg, or -activebackground colors defined for buttons.
- takefocus=0 on buttons/slider (line 44, 61, 88) is good for focus management but doesn't create visual hierarchy.

---

### Pillar 3: Color (2/4)

**Strengths:**
- **No hardcoded colors.** Grep returns no hex codes or rgb() values in the view or logic modules.
- **No accent overuse.** All widgets use default Tk colors; no single color dominates.
- **High inherent contrast.** Default Tk colors (black text on light background) meet basic WCAG AA contrast.

**Weaknesses:**
- **No accessibility testing.** No contrast ratio verification against WCAG standards. Default Tk colors on some platforms (e.g., Aqua on macOS) may have lower contrast than expected.
- **Monochrome design.** All text is black/gray on white/default background. No use of color to signal state (e.g., red for error, green for success).
- **No dark mode support.** The app always uses Tk's default light theme. Users on a dark system background get a jarring light window (though this is a Tkinter limitation, not a design choice).
- **No error color.** If OSC send fails, there is no red indicator or warning text to signal the failure.
- **No status color coding.** Status label text "Sending to..." is black for all states; could be green for ready, orange for pending, red for error.

**Evidence:**
- `grep -rn "#[0-9a-fA-F]\|rgb\|color\|Color\|bg=\|fg=" python_app/view.py` returns no color definitions — all default.
- tkcheck.py error messages (lines 42–51) are all printed to stderr; no GUI-level color feedback.
- main.py (lines 43–46) catches TclError but only prints to stderr; no GUI error dialog.

---

### Pillar 4: Typography (2/4)

**Strengths:**
- **Readable default font.** TkDefaultFont is designed for UI and is readable at 11–12px.
- **One bold emphasis.** Entry field is bold (line 73), which correctly emphasizes the primary input.
- **Appropriate for context.** A compact control window doesn't need elaborate typography; minimal hierarchy is acceptable.

**Weaknesses:**
- **Only one font size.** All labels, buttons, and status text use TkDefaultFont at the default size (~11–12px). The entry field is the only exception at 16px bold. No intermediate sizes (e.g., 13–14px for section headers or status label).
- **Limited hierarchy.** There is no visual distinction between:
  - The slider label "BPM" (control label) and button text "−5" (action label).
  - Status label "Sending to..." (informational) and checkbox label "On top" (toggle label).
  All appear the same size and weight except the entry field.
- **Jarring size jump.** The entry at 16px bold is ~33% larger than the default 12px, creating a visual disruption rather than a smooth hierarchy.
- **No secondary/tertiary sizes.** If status or checkbox text need de-emphasis, there is no smaller font size defined. All non-entry text is identical.

**Font size count:** Only 1 custom size (`("TkDefaultFont", 16, "bold")`) + default TkDefaultFont. Standard practice is 3–4 sizes minimum for a multi-section UI.

**Evidence:**
- `grep -n "font=" python_app/view.py` returns only one match (line 73).
- All other widgets (Scale, Button, Label, Checkbutton) rely on default TkDefaultFont.
- File: `python_app/view.py`, lines 34–103 show no font definitions for Scale label, button text, status label, or checkbox text.

---

### Pillar 5: Spacing (2/4)

**Strengths:**
- **Compact overall.** Window padding (padx=12, pady=10) and button spacing (padx=4) keep the UI dense, appropriate for floating over Zwift.
- **Intentional distinction.** Entry field has padx=8 (vs. button padx=4), signaling it as a special control. This is good but not labeled as such.
- **Vertical rhythm attempt.** nudge_row has pady=8; status and checkbox have pady=(4, 0). Some structure is present.

**Weaknesses:**
- **No unified spacing scale.** Padding values are: 12, 10 (container), 8 (nudge_row), 4 (button pack), 8 (entry pack), (4, 0) (status/checkbox pack). No clear base unit (4px, 8px, 16px grid) is followed.
- **Inconsistent gaps.**
  - Buttons and entry: padx=4, then padx=8, then padx=4 again (asymmetrical).
  - Vertical: pady=10, pady=8, pady=(4, 0), pady=(4, 0) — no pattern.
  - No explicit gap between the slider and nudge row (relies on widget default spacing).
- **Asymmetrical padding.** Status and checkbox use pady=(4, 0), meaning 4px top and 0px bottom. This tightens spacing at the bottom of the window, possibly squeezing the checkbox. Better: pady=4 (both) or pady=(4, 8).
- **Magic numbers.** No documented spacing scale or variable; e.g., `PADDING_UNIT = 4; SPACING_H = PADDING_UNIT * 3` would be clearer than `padx=12`.

**Spacing audit:**
```
Container: padx=12, pady=10         (12/10 — not a scale multiple)
Nudge row: pady=8                   (8 — base unit?)
Buttons:   padx=4, side="left"      (4 — smaller)
Entry:     padx=8, width=5          (8 — special treatment)
Status:    pady=(4, 0)              (asymmetrical; bottom cropped?)
Checkbox:  pady=(4, 0)              (asymmetrical)
```

**Evidence:**
- File: `python_app/view.py`, lines 29, 53, 64, 75, 94, 103 show the spacing values above.
- `grep -n "pad[xy]=" python_app/view.py | sort` shows no documented scale.

---

### Pillar 6: Experience Design (3/4)

**Strengths:**
- **Responsive interactions.**
  - Slider: live update on drag (no send), send on release (line 51, `<ButtonRelease-1>`) ✓
  - Nudges: immediate value update (line 136 in `bpm_logic.py`, `_set()` called before debounce), debounced send (150ms, line 136 `debouncer.trigger()`) ✓
  - Entry: returns on Enter (force=True, line 79), focus-out (force=False, line 81), reverts on invalid (line 154 in `bpm_logic.py`, `_notify()` with current value) ✓
  - Keyboard: Up/Down/Shift+Up/Shift+Down work (lines 109–112) ✓
- **No blocking I/O.** All sends are non-blocking UDP; no threads. App stays responsive.
- **Focus management.** After Enter in the entry, focus moves to root (line 134), allowing arrow keys to work immediately.
- **Toggle state.** "On top" checkbox correctly toggles window attributes (line 117, `root.attributes("-topmost", ...)`) ✓
- **Graceful input validation.** Invalid entry text reverts without crashing (line 154, `_notify()` restores current value).
- **Boundary handling.** Nudges at 60/180 do nothing and don't send (test: `test_bounds_adjacency_at_upper_bound_sends_nothing` passes). ✓

**Weaknesses:**
- **No error visual feedback.** If `OscClient.send_bpm()` returns False (OSError caught in `osc_client.py:send_bpm()`, line ~24), the user sees no indication. The entry and slider look normal; the user may think the command was sent when it failed. *Severity: high.*
- **No connection status.** Status label shows "Sending to 127.0.0.1:57120" but never changes to indicate engine is unreachable or offline.
- **No loading/pending state.** While the debouncer waits to send (150ms), there is no visual indication that a send is pending. A faint gray overlay or "pending..." text would clarify.
- **No disabled state.** If the engine is unreachable, the controls could be disabled (grayed out) to indicate they won't work. Currently, they always appear clickable.
- **Invalid entry has no error message.** Typing "abc" silently reverts the entry without saying why (no tooltip, no flash, no error text).
- **No confirmation for destructive actions.** (Not applicable here; no delete/reset action.)
- **No undo.** Sending 60 then immediately 180 can't be undone if the user changes their mind; this is acceptable for a control app, but worth noting.

**OSC failure handling:**
- `OscClient.send_bpm()` (line ~24 in `osc_client.py`) catches OSError and returns False.
- `BpmController._send_now()` (line 119–121 in `bpm_logic.py`) calls `self._send(float(self._value))` but does NOT check the return value.
- No listener or visual update if the send fails.
- Test `test_send_bpm_returns_false_on_oserror` (in `test_osc_client.py`) verifies the False return, but the view layer never checks it.

**Evidence:**
- File: `python_app/osc_client.py`, `send_bpm()` method catches OSError but the caller (`BpmController._send_now()`) ignores the return.
- File: `python_app/view.py`, no error status indicator.
- File: `python_app/bpm_logic.py`, `_send_now()` (line 119) does `self._send(float(self._value))` with no error handling.
- Tests verify behavior but don't test UI feedback on error: `test_send_bpm_returns_false_on_oserror` checks the return value but there is no test for how the view responds to False.

---

## Registry Safety Audit

No `components.json` found; this project uses custom Tkinter code, not shadcn or third-party UI component registries. Registry audit skipped.

---

## Files Audited

- `python_app/view.py` (142 lines) — Main UI widget code
- `python_app/main.py` (62 lines) — Entry point and Tk initialization
- `python_app/bpm_logic.py` (167 lines) — Pure logic, BPM state and debounce
- `python_app/tkcheck.py` (59 lines) — Tk compatibility gate
- `python_app/config.py` (14 lines) — Constants (OSC_HOST, OSC_PORT, BPM_MIN, BPM_MAX, etc.)
- `python_app/tests/test_view_tk.py` (204 lines) — Widget smoke test (8 tests, all pass)
- `python_app/tests/test_bpm_logic.py` (261 lines) — Logic tests (44 tests, all pass)
- `python_app/tests/test_tkcheck.py` (93 lines) — Gate tests (7 tests, all pass)

**Total tests:** 66 pass, 0 fail, 0 skip.

---

## Recommendations

### Blocking Issues: None

The UI is functional and all acceptance criteria from the phase plan are met. No issues prevent the app from running or fulfilling its core contract.

### High Priority (fix before Phase 02):

1. **Add visual error feedback for OSC send failure.** The `view.py` should check the return value of `apply_entry(force)` and `nudge()`, then briefly highlight the status label in red or add "Connection lost" text if the send fails. Requires: (a) `BpmController` to expose send status (new listener or property), (b) `view.py` to update status on failure, (c) optional: auto-clear after 2–3 seconds.

2. **Add label or tooltip to the entry field.** Either a `Label("BPM:")` widget to the left of the entry, or a tooltip that appears on hover. Requires: new widget or bind `<Enter>`/`<Leave>` with a temporary label.

3. **Define a unified spacing scale.** Replace magic paddings with a 4-unit grid: e.g., `PADDING = 4; container(padx=PADDING*3, pady=PADDING*2)`. Update all `padx` and `pady` values to multiples of 4. Takes 10 minutes; improves visual consistency significantly.

### Medium Priority (fix before Phase 02 if time permits):

4. **Add visual feedback for pending debounced sends.** While a nudge or key press is waiting to send (0–150ms), show a faint indicator (e.g., status text "Pending..." or a subtle background flash on the entry).

5. **Distinguish status label text by state.** Change the status label from static "Sending to 127.0.0.1:57120" to dynamic: "Ready" (green), "Pending..." (yellow), "Connection lost" (red). Requires `BpmController` to expose state.

### Low Priority (nice-to-have for Phase 02+):

6. **Improve typographic hierarchy.** Add a secondary font size (13–14px) for status/checkbox labels. Replace the jarring entry size (16px) with a more modest 13px bold, then use 12px for secondary elements.

7. **Add accessibility features.** Test contrast ratios against WCAG AA (7:1 for normal text). Consider adding a keyboard-only mode (everything navigable via Tab/arrows, no mouse required).

8. **Dark mode support.** Use `tk.appearance` (Tk 8.6.11+) or detect system theme and adjust colors accordingly. Low impact for an indoor-focused tool but improves usability at night.

---

## Conclusion

The Phase 01 UI is a **functional, minimalist control panel** that meets its core contract: let the rider adjust BPM via slider, entry, and buttons while floating over Zwift. All 66 tests pass, and the interactions (release-only slider send, debounced nudges/keys, instant entry revert on invalid input) work as designed.

**Audit score: 14/24 (58%).** The deduction reflects gaps in visual design (hierarchy, spacing, color coding) and missing error feedback. These are not blockers for Phase 01's acceptance (which is engine-focused), but they should be addressed before Phase 02 to ensure the UI scales gracefully as controls are added (glide toggle, EPIC dial, volume slider, etc.).

**Recommendation: PASS Phase 01 acceptance; address high-priority issues (OSC error feedback, spacing scale, entry label) in Phase 02 refinement before shipping.**

---

*Phase: 01-tempo-link-skeleton*
*Audited: 2026-10-09*
*Summary test result: 66/66 passing (no failures)*
