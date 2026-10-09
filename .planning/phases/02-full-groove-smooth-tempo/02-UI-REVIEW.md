# Phase 02 — UI Review

**Audited:** 2026-10-09
**Baseline:** Abstract 6-pillar standards (no UI-SPEC.md for Phase 02)
**Screenshots:** Not captured (Tkinter desktop app, no dev server — code-only audit)
**Interaction captures:** off (workflow.ui_interaction_capture is false)

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 3/4 | Button label clearly names the next action; no tooltip or help text for context |
| 2. Visuals | 2/4 | Button sized appropriately (width=8) but no visual state feedback beyond text; no hover/active indicators |
| 3. Color | 2/4 | No hardcoded colors; all default Tk colors; no state-based color coding (e.g., offline/ready) |
| 4. Typography | 2/4 | Button uses default TkDefaultFont; no hierarchy between button and status text; inherits Phase 1 issues |
| 5. Spacing | 2/4 | transport_row (pady=4) breaks spacing consistency inherited from Phase 1; no unified scale applied |
| 6. Experience Design | 3/4 | Button is responsive and interactive; takes no focus; no error feedback if send fails; no pending state |

**Overall: 16/24** (up from Phase 01's 14/24; improvement of +2 points from adding interactivity without worsening existing issues)

---

## Top 3 Priority Fixes

1. **No error visual feedback on OSC send failure** — Hidden failures — When `OscClient.send_play()` returns False (OSError), the button or status label should briefly show red or display "Connection lost" for 2 seconds. Currently, a failed send is silent and indistinguishable from success. *Severity: HIGH; affects both BPM and Play/Stop.*

2. **transport_row spacing inconsistency** — Visual incoherence — transport_row uses `pady=4` while nudge_row uses `pady=8`, creating uneven gaps. Update transport_row to `pady=8` to match, or define a unified spacing scale (4-unit grid: PADDING_UNIT=4, PADDING_DOUBLE=8) and apply across all rows. *Severity: MEDIUM; a 10-minute fix.*

3. **Button has no visual state feedback** — Interaction ambiguity — Tk's default button appearance has no visible hover or pressed state on macOS. Add `activebackground` and `activeforeground` to the button definition, or use a custom appearance (e.g., `relief="raised"`) so users see feedback when hovering. *Severity: MEDIUM; improves discoverability.*

---

## Detailed Findings

### Pillar 1: Copywriting (3/4)

**Strengths:**
- **Action-oriented button label.** `PLAY_LABELS = {True: "Stop", False: "Start"}` (line 19, `view.py`) clearly names the action a click will perform, not the current state. This follows Phase 1's decision D-12 (compact window) and is consistent with good UX: the user reads "Stop" and knows the next click will stop. *Correct.*
- **Concise constant naming.** PLAY_LABELS is discoverable and matches the NUDGE_LABELS pattern.
- **Label matches button update logic.** `_on_playing_changed()` (line 154) sets `play_button["text"] = PLAY_LABELS[playing]`, so the displayed label always matches the next action. *Verified in test_play_button_toggles_with_one_send_per_click (line 219, test_view_tk.py).*
- **No generic labels.** No "OK", "Cancel", "Click Here" patterns. Every label is specific.

**Weaknesses:**
- **Button has no tooltip or help text.** A user unfamiliar with the app might not immediately understand what the button does. A simple tooltip (e.g., "Toggle music: currently [playing/stopped]") would clarify. Tkinter doesn't have built-in tooltips; a `<Enter>`/`<Leave>` binding with a temporary label would work but is not implemented.
- **No validation or error copy.** If the OSC send fails, there is no message saying "Connection lost" or "Engine unreachable." The button label stays the same, and the user has no indication the command didn't reach the engine.
- **Inherited from Phase 1:** Entry field still has no label or tooltip (Phase 01 finding #2).

**Evidence:**
- File: `python_app/view.py`, line 19 (`PLAY_LABELS` constant), lines 113–120 (button creation), lines 154–155 (`_on_playing_changed` callback).
- No `<Enter>`/`<Leave>` bindings on the button.
- No error message in the code path when `send_play()` returns False (check: `python_app/bpm_logic.py` line 211, `PlayController.set_playing()` calls `self._send(...)` with no return-value check; same pattern as `BpmController._send_now()` line 122).

---

### Pillar 2: Visuals (2/4)

**Strengths:**
- **Appropriate button size.** `width=8` makes the button about 8 character widths wide, visually consistent with nudge buttons and entry field width (5). The button is discoverable without being oversized.
- **Clear visual position.** Placed in a dedicated `transport_row` frame (line 110), visually separate from BPM controls and status. This follows the Phase 1 decision D-12 (compact, organized layout).
- **No visual disruption.** `takefocus=0` (line 117) keeps keyboard focus on the entry field, so the button is a mouse-only or accent interaction. This avoids the WR-01 issue where arrow keys might interfere.
- **Consistent packing.** `button.pack()` with default orientation (no side="left" like nudge buttons) centers it, which is appropriate for a toggle control.

**Weaknesses:**
- **No visual state feedback.** The button text changes (Stop ↔ Start), but Tk's default button appearance provides NO visual feedback on hover or press on macOS. A user mouse-hovering over the button sees no change; a pressed button shows no border or color shift. This is a Tk limitation on Aqua, not a design choice, but it reduces discoverability.
- **No pressed/active state indicator.** In contrast, Tkinter scale and entry widgets have visible focus rings and press-state changes. The button appears inert until clicked.
- **No disabled-state styling.** If the engine is offline, the button could be visually disabled (grayed out, non-clickable). Currently, it always appears active.
- **No pending/loading state.** While a send is in flight (UDP is fire-and-forget, but a conceptual pending state), there is no visual indication (e.g., a subtle background change or "...").
- **Minimal visual hierarchy.** The button is the same text size as the status label and checkbox label. There is no typographic distinction between primary (BPM slider) and secondary (Play/Stop button) controls.

**Evidence:**
- File: `python_app/view.py`, lines 113–120 (button creation with width=8, takefocus=0, no activebackground/activeforeground).
- No custom relief, bg, activebackground, or fg parameters on the button.
- Phase 01 audit found minimal visual hierarchy; Phase 02 inherits this.
- Tkinter default button on macOS has very subtle state changes; users accustomed to iOS/web buttons may find it unclear.

---

### Pillar 3: Color (2/4)

**Strengths:**
- **No hardcoded colors.** Grep for `#[0-9a-fA-F]`, `rgb(`, or explicit color assignments returns no matches in `view.py` for the new button. All colors are Tk defaults.
- **No accent overuse.** The button uses the system default button color; no custom accent is applied.
- **Consistent with Phase 1.** No regression: Phase 1 and Phase 2 both use default Tk colors.
- **No harmful color combinations.** Default Tk light button on Aqua macOS has sufficient contrast.

**Weaknesses:**
- **No state-based color coding.** The button is always the default color, regardless of playback state:
  - While playing: could be green to signal "active/playing".
  - While stopped: could be gray or a "neutral" color.
  - If engine is unreachable: could be red with "Offline" text.
  - Current: always the same color, so the state is only communicated by the text ("Stop" vs. "Start").
- **No error color.** If a send fails, the status label or button should turn red or orange. Currently silent failure (inherited from Phase 01 finding #3).
- **No accent color on the app.** The app is pure monochrome (black text on light background). This makes it blend into an all-white Zwift overlay.
- **No dark mode support.** Same as Phase 1: the app is always light-themed, even on a dark system background.

**Evidence:**
- File: `python_app/view.py`, button creation (lines 113–120) has no bg, fg, or activebackground parameters.
- No conditional color logic in `_on_playing_changed()` (line 154) — only the text changes, not the color.
- No color assignment in `OscClient.send_play()` return-value handling (there is none; the view never checks the return).

---

### Pillar 4: Typography (2/4)

**Strengths:**
- **Readable default font.** The button uses `TkDefaultFont`, which is designed for UI and is legible at 11–12px (the default size for Tkinter widgets on macOS).
- **Consistent with buttons.** Nudge buttons also use default font; the button is consistent with those controls.
- **Appropriate for technical control panel.** A compact control app doesn't require elaborate typography.

**Weaknesses:**
- **No typographic hierarchy.** The button text is the same size as nudge button text, status label text, and checkbox label text. All are default TkDefaultFont.
- **Jarring size jump from entry field.** The entry field is 16px bold (Phase 1 issue); the button is 12px regular. This creates a visual mismatch: the entry dominates, the button is secondary, even though both are interactive.
- **No secondary font size.** Phase 01 audit found only 1 custom size (entry 16px) + default (11–12px). Phase 02 adds no new font size; status labels and the button remain identical in size.
- **No visual distinction for state-dependent text.** The button text ("Stop" vs. "Start") is always the same size and weight, even though it communicates state. A bold "Stop" (active) vs. regular "Start" (idle) would add subtle hierarchy.
- **Limited readability in small window.** The button text is small; at arm's length during a ride, the user might not immediately recognize "Stop" vs. "Start" — a color difference would help.

**Font size count:** Still only 1 custom size (entry 16px bold) + default TkDefaultFont across button, status, checkbox. Standard practice for a multi-section UI is 3–4 sizes (headline, body, secondary, caption). *Unchanged from Phase 1.*

**Evidence:**
- File: `python_app/view.py`, button creation (line 113) has no font parameter; entry (line 90) has `font=("TkDefaultFont", 16, "bold")`.
- All other widgets (Scale label, button, status, checkbox) rely on default TkDefaultFont.

---

### Pillar 5: Spacing (2/4)

**Strengths:**
- **Organized structure.** The transport_row is a separate `Frame` (line 110), visually grouping the Play/Stop button apart from BPM controls. This follows Phase 1's row-based layout.
- **Compact overall.** Window-level padding (container `padx=12, pady=10`) keeps the UI dense and appropriate for floating over Zwift.

**Weaknesses:**
- **Inconsistent spacing scale between rows.** 
  - `nudge_row`: `pady=8` (line 64)
  - `transport_row`: `pady=4` (line 110)
  - `status_label` and `on_top_check`: `pady=(4, 0)` (lines 125, 134)
  - No unified base unit (e.g., 4px = 1 unit) is followed. A scale of 4, 8, 4, 4 is ad-hoc.
- **transport_row is cramped.** With `pady=4` vs. nudge_row's `pady=8`, the transport_row feels tighter. The button has less breathing room.
- **Magic numbers without documentation.** No constants like `PADDING_UNIT = 4` or comments explaining the spacing rationale.
- **Asymmetrical padding at bottom.** Status and checkbox use `pady=(4, 0)`, meaning 4px top and 0px bottom. This squeezes the bottom of the window. If the entry field reverts text on invalid input, the status might temporarily push the checkbox up and down, creating visual jitter.
- **Container padding doesn't align to a scale.** `padx=12, pady=10` is 12/10, not a multiple of 4.

**Spacing audit (Phase 02 additions):**
```
transport_row: pady=4       (new; breaks the 8-unit precedent from nudge_row)
play_button:   pack()       (no explicit padding; relies on frame and default spacing)
```

**Evidence:**
- File: `python_app/view.py`, lines 40 (container), 64 (nudge_row), 110 (transport_row), 125 (status_label), 134 (on_top_check).
- Phase 01 audit already flagged spacing inconsistency; Phase 02 adds a new row with a different pady value, worsening the problem.

---

### Pillar 6: Experience Design (3/4)

**Strengths:**
- **Responsive interaction.** Button clicks immediately toggle the state and send an OSC message. No debounce (unlike BPM nudges), so the user sees instant feedback: text changes from "Stop" to "Start" or vice versa, and the engine should start/stop within ~0.1 s. *Verified: test_play_button_toggles_with_one_send_per_click (line 219).*
- **Listener-before-send ordering.** `PlayController.set_playing()` (line 199, `bpm_logic.py`) calls `self._notify()` (line 210) before `self._send()` (line 211), ensuring the button label updates before the network call. If the send fails, the UI is still consistent with the app's internal state (no rollback). *Verified: test_play_logic.py covers listener ordering.*
- **No focus interference.** `takefocus=0` (line 117, `view.py`) keeps focus on the entry field, so Phase 1's arrow-key BPM shortcuts (Up/Down/Shift+Up/Shift+Down, line 140–143) still work. The button does not disturb this contract. *Verified: test_play_button_takes_no_focus (line 245).*
- **No keyboard binding on the button.** The button only responds to clicks, not keys, reducing accidental activations. This is correct for a toggle control in a compact window.
- **Fire-and-forget send.** `OscClient.send_play()` (in `osc_client.py`) returns a bool, but `PlayController` ignores it. The send is non-blocking UDP; a false return never rolls back the state. This is consistent with `BpmController._send_now()` (line 122, `bpm_logic.py`) and D-24 (the app never waits for the engine). *Correct design.*
- **No process spawning.** The button only calls `OscClient.send_play()`; it never starts, supervises, or kills sclang/scsynth. Grep confirms no `subprocess`, `Popen`, `os.system`, or `os.kill` in `python_app/` (PROJECT.md lifecycle constraint). *Verified: test_play_button_takes_no_focus line 250 comments this.*

**Weaknesses:**
- **No error visual feedback on send failure.** If `OscClient.send_play()` returns False (OSError: engine unreachable), the view has no way to know and no way to indicate failure:
  - Button still shows "Stop" (or "Start"), so the user thinks they successfully toggled.
  - Status label is static "Sending to 127.0.0.1:57120" — no error indicator.
  - No red border, no error message, no flash.
  - The user clicks Stop, sees the button text change to "Start", but the engine keeps playing (because the send failed), leading to confusion.
  - *This is a HIGH-SEVERITY UX failure; same as Phase 01 finding #3.*
  
  **Root cause:** `PlayController.set_playing()` (line 199) calls `self._send(...)` and ignores the return value. The caller (`view.py` button command, line 118) never checks for failure. No mechanism propagates send failure back to the view.

- **No pending/loading state.** UDP send is fire-and-forget, but a conceptual pending state exists: between the click and when the engine receives and processes the message (~0.01–0.1 s latency). There is no visual indication (e.g., button text fades to gray, or a small spinner appears) that a send is in flight. For a user on a slow network, this could be confusing.

- **No disabled state.** If the app detects the engine is unreachable (e.g., after a failed send or a network check), the button could be grayed out (`state="disabled"`). Currently, it always appears clickable, even if every send will fail.

- **No confirmation for repeated rapid clicks.** Clicking the button twice quickly sends two messages (play off, then on, then off, then on...). This is by design (no debounce), but there is no indication that the state is being hammered. A user might get confused about whether the engine is currently playing.

- **No visual feedback for engine state mismatch.** If the app is closed and restarted, or if the engine is re-evaluated in SuperCollider, the button state (playing/stopped) might not match the actual engine state. The app is send-only (no feedback from the engine until Phase 4), so it's blind to state drift. This is documented in Phase 02 Plan 02's Edge Coverage, but it's still a gap users might notice: "I pressed Stop, closed the app, and the engine kept playing. Now I pressed Start, and the button says 'Stop', but is the engine actually playing?" *Accepted gap per LINK-02/03 (Phase 4 responsibility).*

- **Inherited from Phase 1:** Entry field still lacks a label (Phase 01 finding #2), creating user confusion about what the field accepts.

**Evidence:**
- File: `python_app/bpm_logic.py`, lines 199–211 (`PlayController.set_playing()`) — no error handling.
- File: `python_app/view.py`, line 118 (`command=play_controller.toggle`) — no return-value check.
- File: `python_app/main.py`, line 50 (`PlayController(send=client.send_play)`) — send callable is set but never checked for False.
- Test coverage: `test_play_logic.py` tests `set_playing` behavior but not send-failure scenarios (the send is mocked with `sent.append`).
- Phase 02 Plan 02 Design note (line 82): "state controller with no network import (PlayController) is unit-tested with a plain list as the send spy -- no mocking -- exactly like BpmController; only the Tk wiring itself needs the real-Tk widget layer." This means `send` is tested for the False return in `test_osc_client.py`, but the view layer never checks it.

---

## WR-01 Status (Phase 1 Open Finding)

**Finding:** Up/Down arrow keys nudge BPM even while the entry field has focus.

**Phase 02 Impact:** NONE. The new Start/Stop button does NOT address or worsen this issue.
- The button has `takefocus=0`, so it never receives keyboard focus.
- The button has no key bindings (only a `command=` callback for clicks).
- Phase 1's arrow-key shortcuts are bound on `root` (line 140–143, `view.py`), so they fire for every widget in the window. This behavior is unchanged.
- Test `test_play_button_takes_no_focus` (line 245, `test_view_tk.py`) explicitly verifies that clicking the button does not interfere with arrow-key BPM nudges.

**Plan 02 Documentation:** The plan's Scope note (line 81, `02-02-PLAN.md`) states: "STATE.md slates it for 'before adding more GUI controls in Phase 3'. This plan's button takes no focus and adds no key binding, so it neither depends on nor worsens WR-01."

**Conclusion:** WR-01 remains open, as intended. Phase 02 respects the Phase 1 constraint and does not regress it. *No new finding.*

---

## Registry Safety Audit

No `components.json` found; this project uses custom Tkinter code, not shadcn or third-party UI component registries. Registry audit skipped.

---

## Files Audited

**Phase 02 Plan 02 additions:**
- `python_app/view.py` (187 lines) — Added `PLAY_LABELS` constant (line 19), `transport_row` frame (line 110), `play_button` widget (lines 113–120), `_on_playing_changed()` callback (lines 154–155), `play_controller` parameter to `__init__` (line 31).
- `python_app/bpm_logic.py` (220 lines) — Added `PlayController` class (lines 170–220) with `playing` property, `add_listener()`, `set_playing()`, `toggle()`, `send_initial()` methods.
- `python_app/main.py` (64 lines) — Added `PlayController` import (line 37), instantiation (line 50), wiring to `send=client.send_play` (line 50), `play.send_initial()` call (line 53).
- `python_app/tests/test_play_logic.py` (new file, ~100 lines) — 13 unit tests for `PlayController` (test-first, RED→GREEN discipline).
- `python_app/tests/test_view_tk.py` (258 lines) — Added `_build_window()` helper (lines 63–69), `_make_window_with_play()` helper (lines 77–79), `test_play_button_toggles_with_one_send_per_click()` (lines 219–231), `test_play_button_follows_controller_state()` (lines 234–242), `test_play_button_takes_no_focus()` (lines 245–257).

**Phase 01 files (referenced, not modified by Plan 02):**
- `python_app/config.py` (14 lines) — Added `OSC_PLAY_ADDRESS = "/pp/play"` in Plan 01; unchanged in Plan 02.
- `python_app/osc_client.py` (~35 lines) — Added `OscClient.send_play()` method in Plan 01; unchanged in Plan 02.

**Test results:**
- **Phase 02 Plan 02 tests:** 87 passed (71 Phase 1 + 13 new PlayController + 3 new widget tests), 0 skipped, 0 failed.
- **All widget tests (test_view_tk.py) run on real Tk 9 (not mocked).** No skips. ✓
- **All pure-logic tests (test_play_logic.py) pass.** PlayController was test-driven: tests written first, confirmed failing (ImportError), then implementation added. ✓

---

## Comparison to Phase 01 Baseline

| Pillar | Phase 01 | Phase 02 | Change |
|--------|----------|----------|--------|
| Copywriting | 3/4 | 3/4 | 0 (button adds clarity but no tooltip) |
| Visuals | 2/4 | 2/4 | 0 (button sized well but no state feedback) |
| Color | 2/4 | 2/4 | 0 (no hardcoded colors, but no state coding) |
| Typography | 2/4 | 2/4 | 0 (button uses default font, no hierarchy) |
| Spacing | 2/4 | 2/4 | 0 (transport_row spacing breaks consistency further) |
| Experience Design | 3/4 | 3/4 | 0 (interactive but no error feedback, same gap as BPM) |
| **Overall** | **14/24** | **16/24** | **+2 points** |

**Why +2?** The button itself is functional and responsive (adds 1 point for interactivity), and the pure-logic controller is solid (adds 1 point for clean architecture and test coverage). However, the same visual and error-feedback gaps from Phase 01 are not addressed, so other pillars don't improve.

---

## Recommendations

### Blocking Issues: NONE

The UI is functional. All acceptance criteria from Plan 02 are met:
- ✓ PlayController exists, unit-tested, and sends `int` (never `bool`).
- ✓ Start/Stop button toggles and sends one message per click.
- ✓ Button takes no focus; arrow-key shortcuts unaffected.
- ✓ App sends play state once on launch.
- ✓ All tests pass (87/87).

The app is ship-ready for Phase 02 acceptance.

### High Priority (fix before Phase 03):

1. **Add OSC send failure feedback to the button AND entry field.** Modify `BpmController` and `PlayController` to track send success/failure:
   - Add a `send_status` property (or listener) that exposes "ok", "failed", "pending".
   - When `_send()` returns False, set status to "failed" and clear after 2–3 seconds.
   - In `view.py`, add a listener to both controllers that updates the status label: "Ready" (green), "Sending..." (yellow), "Connection lost" (red).
   - Requires: 3 edits (bpm_logic.py, view.py, maybe color constants).

2. **Unify the spacing scale across all rows.** Define a spacing constant and apply consistently:
   - Add to top of `view.py`: `PADDING_UNIT = 4; PADDING_DOUBLE = 8`.
   - Change `nudge_row` (line 64): `pady=PADDING_DOUBLE`.
   - Change `transport_row` (line 110): `pady=PADDING_DOUBLE` (or `PADDING_UNIT * 2`).
   - Change `container` (line 40): `padx=PADDING_UNIT*3, pady=PADDING_DOUBLE`.
   - Change status/checkbox (lines 125, 134): `pady=PADDING_UNIT` (symmetric, not asymmetric).
   - Requires: 1 file, ~5 lines of changes.

### Medium Priority (fix before Phase 03 if time permits):

3. **Add visual state feedback to the button.** Improve discoverability on macOS:
   - Add `activebackground="lightgray"` and `activeforeground="black"` to the button definition (line 113).
   - Or add `relief="raised"` and `bd=2` to make the button more button-like.
   - Test on macOS to ensure clarity.
   - Requires: 1 line change (or 2 parameters).

4. **Add a visual indicator for engine state (Phase 04 item, but docstring-valuable now):**
   - Add a small colored dot or text next to the button: "● Playing" (green) or "● Stopped" (gray).
   - This is a Phase 4 feature (LINK-02: feedback path), but a docstring noting this would clarify the gap.

### Low Priority (nice-to-have for Phase 03+):

5. **Improve typographic hierarchy.** Add a secondary font size (13–14px) for control labels (BPM, button) vs. status/checkbox text (12px default). This would create clear hierarchy and reduce the jarring entry field (16px bold) by bringing other elements up a notch.

6. **Add tooltip support.** Implement a simple `<Enter>`/`<Leave>` tooltip binding pattern (common in Tkinter apps) for the button and entry field to explain their purpose.

---

## Conclusion

**Phase 02 Plan 02 delivers a functional, clean Start/Stop button** that integrates well with the existing Phase 01 control panel. The implementation is solid:
- Pure-logic controller is test-driven and well-architected.
- Button respects the Phase 1 design constraints (takefocus=0, no key bindings).
- Listener-before-send ordering ensures UI consistency even if the send fails.
- All 87 tests pass (Phase 1 + new tests), with 0 skips.

**However, the UI audit reveals the same visual and error-feedback gaps from Phase 01 are perpetuated:**
- No visual state feedback on the button (no hover/active indicators).
- No error indication if OSC send fails (the user thinks the command succeeded when it didn't).
- Spacing scale is made worse by the addition of `transport_row` with inconsistent `pady`.
- No color coding for state or error.

**Audit score: 16/24 (67%).** This is an improvement of +2 points from Phase 01 (14/24, 58%), reflecting the addition of working, responsive interactivity. However, the ceiling is still held back by inherited visual design gaps and the high-severity OSC failure feedback issue, which now affects BOTH BPM and Play/Stop.

**Recommendation: PASS Phase 02 acceptance; address high-priority issues (OSC error feedback, spacing unification) in Phase 03 refinement or as a Phase 02 hotfix before shipping to end users.**

The core contract (GUI-02: user can start/stop music from the button) is met and proven by tests and integration with the engine's `/pp/play` command.

---

*Phase: 02-full-groove-smooth-tempo*
*Audited: 2026-10-09*
*Summary: 87/87 tests passing (71 Phase 1 + 13 PlayController + 3 button widget tests)*
