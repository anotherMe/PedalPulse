# Phase 03 — UI Review

**Audited:** 2026-10-09
**Baseline:** Abstract 6-pillar standards + Phase 02 UI-REVIEW.md (16/24)
**Screenshots:** Not captured (Tkinter desktop app, no dev server — code-only audit)
**Interaction captures:** off (workflow.ui_interaction_capture is false)

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 3/4 | Zone names clear (Recovery, Endurance, Tempo, Threshold, VO2); caption "Zone: <name>" names selection; volume label concise. No tooltips for new controls. |
| 2. Visuals | 3/4 | Zone highlight uses bold font + caption (macOS-friendly fix from Phase 2 planning); buttons sized appropriately (padx=2); volume scale matches BPM (320px, fill="x"). No hover/active state feedback on buttons. |
| 3. Color | 2/4 | No hardcoded colors; all Tk defaults; no state-based color coding (e.g., selected zone could use background). Same as Phase 2. |
| 4. Typography | 2/4 | Zone button font weight provides subtle hierarchy (bold selected); otherwise only 1 custom size (entry 16px bold) + default TkDefaultFont. Inherits Phase 2 lack of multi-level typography. |
| 5. Spacing | 3/4 | **MAJOR FIX:** transport_row pady changed 4→8; all control rows now pady=8 (nudge_row, zone_row, transport_row, volume_row). Container padx/pady (12/10) still misaligned; status/checkbox asymmetric (4,0). |
| 6. Experience Design | 3/4 | Buttons/slider responsive, listener-before-send, takefocus=0 on all new controls preserves arrow-key shortcuts, same-zone click is no-op. Inherits Phase 2 gap: no visual OSC send-failure feedback. |

**Overall: 16/24** (unchanged from Phase 02; additions extend the UI without improving overall quality ceiling)

---

## Summary of Phase 03 UI Additions

### 1. Zone Row (EPIC-03)
- **What:** Five buttons (Recovery, Endurance, Tempo, Threshold, VO2) in left-to-right order
- **Selection state:** Selected zone gets bold font + sunken relief; caption "Zone: <name>" displays the zone name in plain text
- **Spacing:** `pady=8` (consistent with nudge_row and new transport_row), `padx=2` between buttons (compact)
- **Focus:** `takefocus=0` on each button, preserving arrow-key BPM shortcuts (test: `test_zone_click_keeps_arrow_shortcuts_on_bpm`)
- **Code:** `_build_zone_row()` (lines 174–206, view.py), `_on_zone_changed()` (lines 208–214)

### 2. Volume Row (GUI-03)
- **What:** Horizontal Scale, range 0–100, default 80, label "Volume"
- **Behavior:** Live drag (slider_moved) updates value without sending; release send (slider_released) sends once
- **Sizing:** 320px length, `fill="x"` (matches BPM scale)
- **Focus:** `takefocus=0`, preserving arrow-key BPM shortcuts (test: `test_volume_slider_keeps_arrow_shortcuts_on_bpm`)
- **Code:** `_build_volume_row()` (lines 216–245), `_on_volume_changed()` (lines 249–250)

### 3. Control Row Spacing Fix
- **Issue (Phase 02 Top 3 #2):** transport_row had `pady=4`, breaking consistency with nudge_row's `pady=8`
- **Fix:** transport_row now `pady=8` (line 131)
- **Result:** All control rows (bpm_scale, nudge_row, zone_row, transport_row, volume_row) now uniformly `pady=8`
- **Impact:** Visual consistency improved; Phase 2's high-priority spacing issue partially addressed

---

## Detailed Findings

### Pillar 1: Copywriting (3/4)

**Strengths:**
- **Zone names are action-oriented and clear.** Recovery (10), Endurance (30), Tempo (50), Threshold (75), VO2 (100) directly name the effort zones (from cycling training terminology). A rider immediately understands "Threshold" means high effort. *Correct and domain-appropriate.* (config.py, lines 24–30)
- **Zone caption is explicit.** "Zone: <name>" (view.py, line 214, `_on_zone_changed()`) clearly identifies which zone is selected. Not abbreviated or cryptic.
- **Volume label is concise.** "Volume" clearly signals the scale's purpose. No ambiguity like "Gain" or "Level".
- **Button labels match internal state.** Each zone button's text is the zone name (e.g., "Recovery"), mirroring the config constant. No disconnect between label and data. (view.py, line 194)
- **No generic patterns.** No "OK", "Cancel", "Click Here", or "Submit" buttons. All labels are specific.
- **Config constants are well-named.** `EPIC_ZONES`, `EPIC_DEFAULT_ZONE`, `VOLUME_MIN/MAX/DEFAULT` are discoverable and match the pattern from Phase 1/2.

**Weaknesses:**
- **Zone buttons and volume scale have no tooltips.** A user unfamiliar with cycling zones might not understand why VO2 is at the right end (it's the highest effort). A tooltip like "VO2: Maximum effort (high cadence/resistance)" would help. Tkinter tooltips are not built-in; a `<Enter>`/`<Leave>` binding with a temporary label is not implemented.
- **No help text or context for volume scale.** Is 80 loud? Is 0 mute? A label like "Volume (0=silent, 100=max safe)" or a secondary caption would clarify. Not present.
- **Inherited from Phase 2:** Entry field still lacks a label (Phase 01 finding #2), and there is no error copy for failed OSC sends (finding #3).

**Evidence:**
- Config: `python_app/config.py`, lines 24–30 (EPIC_ZONES), 37–39 (VOLUME_* constants).
- View: `python_app/view.py`, line 194 (zone button text), line 214 (zone caption), line 237 (volume label).
- No `<Enter>`/`<Leave>` bindings in the code; grep for "Enter\|Leave" in view.py shows only arrow-key and focus bindings, not hover tooltips.

**Recommendation:** Add tooltips for zone buttons (explaining the zone and its use case) and volume scale (clarifying the 0–100 range). This is a nice-to-have for Phase 04.

---

### Pillar 2: Visuals (3/4)

**Strengths:**
- **Zone highlight uses multiple visual cues.** Bold font + sunken relief + "Zone: <name>" caption together make the selection clear. This was a deliberate fix from Phase 2 planning: "this Mac's Tk 9.0.3 (aqua) largely ignores relief on native buttons," so bold font + caption render visibly where relief alone might not. *Verified during planning and confirmed in code:* `_build_zone_row()` creates both a `zone_font_selected` (bold copy, line 185) and updates the caption (line 214). (view.py, lines 183–206)
- **Zone buttons are appropriately sized.** Each button is approximately 8–10 character widths wide (default font size, no explicit width parameter). With `padx=2` between them (line 199), five buttons fit on one line without crowding. This is better than Phase 2's button at width=8 (which was a single toggle), as it respects the compact window constraint (D-12).
- **Volume scale matches BPM scale visually.** Both are 320px horizontal scales (lines 59, 236), labeled on the same line, with `fill="x"` for consistent width (lines 65, 242). This creates visual parallelism and suggests they are sibling controls.
- **Clear visual grouping.** Each control row is a separate `Frame` with its own `pady`, making rows visually distinct (nudge_row, zone_row, transport_row, volume_row).
- **Consistent use of `takefocus=0`.** All new interactive controls (zone buttons, volume scale) have `takefocus=0`, so they don't interfere with keyboard focus (entry field retains focus by default). This follows Phase 1/2 patterns and is verified by tests.

**Weaknesses:**
- **Zone buttons have no hover/active state feedback.** Identical to Phase 02's finding: Tk's default button appearance has no visible change on hover or press on macOS Aqua. A user mouse-hovering over a zone button sees no change; pressing shows no border or color shift. *This is a Tk limitation on Aqua, not a Phase 03 design choice, but it reduces discoverability.* (Phase 02 recommended adding `activebackground="lightgray"` and `activeforeground="black"`.)
- **Volume scale has no visual pending state.** While a drag is in flight, there is no indication (e.g., a faded background, spinner, or "sending..." text). UDP sends are fire-and-forget, so there is technically no "pending" period, but a conceptual UI expectation might be present.
- **No disabled state for any control.** If the engine is offline, zone buttons and volume scale could be grayed out (`state="disabled"`). Currently, they always appear active even if OSC sends will fail.
- **No error state.** If a send fails, no visual indication appears. The button text or scale background could briefly turn red, or the status label could flash. (Inherited from Phase 02 finding #1.)

**Evidence:**
- Code: `python_app/view.py`, lines 183–206 (`_build_zone_row()`), lines 216–245 (`_build_volume_row()`).
- Grep: `button.configure(font=..., relief=...)` (line 211, 213) shows font and relief both set; no activebackground/activeforeground parameters.
- Phase 02 audit found the same visual feedback gap; Phase 03 does not address it.

---

### Pillar 3: Color (2/4)

**Strengths:**
- **No hardcoded colors.** Grep for `#[0-9a-fA-F]`, `rgb(`, explicit color names (except in comments) in view.py returns no matches. All colors are Tk defaults (system light button, default label text, etc.). (view.py: no color parameters in button or scale definitions)
- **No accent color overuse.** The app does not apply a custom brand accent to zone buttons or volume scale; they use Tk's default appearance.
- **Consistent with Phase 1/2.** No regression: all control widgets (scales, buttons, checkboxes) use default Tk colors.
- **Appropriate for technical control panel.** A compact cycling app floating over Zwift doesn't require elaborate theming; monochrome is functional.

**Weaknesses:**
- **No state-based color coding.** The selected zone button is distinguishable by font weight and relief, but not by color. On some Tk themes or with custom modifications, a subtle background highlight (e.g., `bg="lightblue"` when selected, `bg="white"` when not) would add visual reinforcement. *Not present.*
- **No error color.** If a zone button click or volume drag fails to send, there is no red or orange feedback. The status label stays static. (Inherited from Phase 02 finding #3.)
- **No color coding for volume extremes.** Volume 0 (silent) and 100 (max, potential clipping) could use subtle color cues (e.g., gray at 0, amber/red near 100) to warn of extreme states. Not implemented.
- **Inherited from Phase 2:** App is "pure monochrome (black text on light background)" and "no dark mode support."

**Evidence:**
- Code: `python_app/view.py`, lines 211–213 (zone button configure) shows no bg/fg/activebackground parameters.
- Config: `python_app/config.py` has no color constants.
- Phase 02 audit found the same color gaps; Phase 03 does not introduce color, either new or improved.

---

### Pillar 4: Typography (2/4)

**Strengths:**
- **Zone button font weight distinguishes state.** Selected zone uses `self.zone_font_selected` (bold, line 211) while unselected zones use `self.zone_font` (normal, line 213). This creates a subtle visual hierarchy without introducing a new font size. *Effective and minimal.* (view.py, lines 183–206)
- **Scale labels use default font.** Both zone buttons and volume scale are readable at the default TkDefaultFont size (~12px). No font size conflict.
- **Consistent with button precedent.** Zone buttons follow the same font pattern as nudge buttons (default font) and play button (default font).

**Weaknesses:**
- **Only 1 custom font size in use: entry at 16px bold.** Volume scale label, zone buttons, zone caption, status label, and checkbox all use TkDefaultFont. No secondary size (e.g., 13–14px) for control labels vs. status text.
- **No size hierarchy.** A best practice for multi-section UI is 3–4 font sizes (headline, body, secondary, caption). This app has 1 custom + 1 default, limiting visual hierarchy to weight alone (bold entry, normal everything else).
- **Font weight is the only new distinction.** Zone button boldness is helpful, but without a secondary size, the hierarchy is subtle and might not be immediately visible to users at arm's length during a ride.
- **Inherited from Phase 2:** "The button is the same text size as the status label and checkbox label. There is no typographic distinction between primary (BPM slider) and secondary (Play/Stop button) controls." Phase 03 adds zone buttons and volume scale, all at the same default size, so the issue persists.

**Evidence:**
- Code: `python_app/view.py`, line 185 (zone font bold copy), line 98 (entry 16px bold), line 237 (volume scale label, no font parameter, so default).
- Font count: Grep for `font=` in view.py returns line 98 (entry 16px bold) and lines 196, 211, 213 (zone buttons, default font object copies). No other custom sizes.
- Phase 02 summary: "no typographic hierarchy... BPM slider is not distinguished from button by size or weight."

---

### Pillar 5: Spacing (3/4)

**Strengths:**
- **Major fix: transport_row pady unified.** Phase 02's Top 3 Priority Fixes item #2 was "Unify the spacing scale across all rows... Change `transport_row` (line 110): `pady=PADDING_DOUBLE`." Phase 03 implements this: `transport_row` now uses `pady=8` (line 131) instead of `pady=4`. *This is a substantial improvement.* (view.py, line 131)
- **All control rows now use consistent pady=8:**
  ```
  nudge_row:     pady=8   (line 72, Phase 1)
  zone_row:      pady=8   (line 187, Phase 3)
  transport_row: pady=8   (line 131, Phase 3 fix)
  volume_row:    pady=8   (line 225, Phase 3)
  ```
  *Visually consistent; one unified spacing value for control rows.* This is correct.
- **Zone button padx=2 is compact.** With five zone buttons and `padx=2` between them (line 199), the row is tight but not cramped. The buttons fit horizontally without excessive spacing.
- **Volume scale follows BPM scale precedent.** Both use `fill="x"` for full-width layout, making them visual siblings. (lines 65, 242)

**Weaknesses:**
- **Container padding still misaligned.** `container = tk.Frame(root, padx=12, pady=10)` (line 48) does not follow a uniform grid:
  - `padx=12` is 3× a 4-unit, OK
  - `pady=10` is not aligned to 4 or 8 (neither is Phase 2's original `pady=10`)
  - Expected: `pady=8` or `pady=12` (multiples of 4) or explicit documentation of a 10-unit padding.
  
  Phase 02 recommended defining `PADDING_UNIT = 4; PADDING_DOUBLE = 8` and applying consistently. This was not done; container padding remains ad-hoc.

- **Nudge button and entry padx values are inconsistent.**
  ```
  nudge buttons:  padx=4   (line 83)
  entry:          padx=8   (line 100)
  zone buttons:   padx=2   (line 199)  ← new, for compact 5-button layout
  ```
  The buttons and entry use different padding (4 vs. 8), and the zone buttons use a different value again (2). No single scale is applied to all button padding.

- **Status label and checkbox use asymmetric pady.**
  ```
  status_label: pady=(4, 0)   (line 148)
  on_top_check: pady=(4, 0)   (line 157)
  ```
  Both use `(4, 0)` (4px top, 0px bottom), creating an asymmetric squeeze at the bottom of the window. Phase 02 recommended symmetric padding (e.g., `pady=PADDING_UNIT` for both, or `pady=(4, 4)`).

- **No documented spacing constants.** The fix is partial: control rows are now uniform, but the overall spacing scale (container, buttons, status) is not documented or principled. A comment like `# Control row spacing: 8px, matching nudge_row (Phase 1) and transport_row (Phase 03 unified)` would clarify intent.

**Evidence:**
- Code: `python_app/view.py`, lines 48 (container), 72 (nudge_row), 131 (transport_row, now fixed), 187 (zone_row), 225 (volume_row), 148 (status), 157 (checkbox).
- Phase 02 Top 3 Priority #2: "Change `transport_row` (line 110): `pady=PADDING_DOUBLE`... Change `container` (line 40): `padx=PADDING_UNIT*3, pady=PADDING_DOUBLE`..." Phase 03 implements the transport_row fix but not the full container/button padding unification.

**Assessment:** Phase 03 *partially fixes* Phase 02's spacing issue by unifying control rows at `pady=8`. However, the recommendation for a full spacing scale (PADDING_UNIT=4, PADDING_DOUBLE=8 applied everywhere) is not completed. Status quo is improved but not fully resolved.

---

### Pillar 6: Experience Design (3/4)

**Strengths:**
- **Zone buttons are responsive and discrete-click.** Each click sends exactly one message (no debounce) and notifies listeners before sending. The button text (zone name) updates immediately via `_on_zone_changed()` listener. *Same pattern as PlayController (Phase 02), inherited and working well.* (view.py, lines 197, 205–206; bpm_logic.py, lines 268–284)
- **Listener-before-send ordering is preserved.** `EpicController.select_zone()` (line 268, bpm_logic.py) calls `self._notify()` before `self._send()`, ensuring the UI updates even if the send fails. The view never sees the OSC failure, but at least the internal state is consistent. (Same pattern as Phase 02's PlayController.)
- **Same-zone click is a no-op.** Clicking the already-selected zone sends nothing and notifies nothing (line 280, bpm_logic.py: `if name == self._zone: return`). This prevents redundant sends and is verified by test `test_zone_click_same_zone_is_a_noop` (from 03-02-SUMMARY.md coverage D2).
- **Volume slider follows the live-drag pattern.** `slider_moved()` updates the visual value without sending; `slider_released()` sends once on release (D-20). A drag sequence produces exactly one send, preventing floods. Same pattern as BPM slider. *Verified by tests: `test_volume_drag_then_release_sends_once`.* (bpm_logic.py, lines 341–348; view.py, lines 239, 243–245)
- **takefocus=0 on all new controls.** Zone buttons (line 195) and volume scale (line 240) both have `takefocus=0`, so they don't steal keyboard focus. Arrow-key BPM shortcuts (Up/Down/Shift-Up/Shift-Down, lines 167–170, root-level bindings) remain active. *Verified by tests: `test_zone_click_keeps_arrow_shortcuts_on_bpm`, `test_volume_slider_keeps_arrow_shortcuts_on_bpm`.* (view.py, lines 195, 240)
- **No keyboard bindings on zone buttons.** Zone buttons only respond to clicks; no key binding routes them. This reduces accidental activations and is correct for a toggle-like control.
- **Window layout is logically ordered.** Rows pack top-to-bottom in this order (verified by test `test_window_layout_order`, from 03-04-SUMMARY.md coverage D4):
  ```
  1. BPM scale
  2. Nudge row (−5, −1, entry, +1, +5)
  3. Zone row (Recovery, Endurance, Tempo, Threshold, VO2)
  4. Zone caption ("Zone: <name>")
  5. Transport row (Start/Stop button)
  6. Volume row (Volume scale)
  7. Status label
  8. On top checkbox
  ```
  This progression mirrors the user's workflow: set BPM (slider), fine-tune (nudges/entry), pick zone (buttons), start/stop (transport), adjust volume, and enable always-on-top. *Logical and usable.*

**Weaknesses:**
- **No visual feedback on OSC send failure.** If `EpicController.select_zone()` or `VolumeController.slider_released()` calls `self._send(...)` and the send fails (OSError), the view has no way to know. The button appears to have sent the zone, and the slider shows the volume was released, but the engine never received the message. This is a **HIGH-SEVERITY UX failure**, inherited from Phase 02 finding #1 and now extends to zone buttons and volume slider.
  - **Example failure scenario:** User clicks "VO2" zone button. Button label stays the same (zone name), and the caption reads "Zone: VO2". But the OSC send fails (network error, sclang crashed). The engine is still in "Recovery" mode, so the music doesn't change. The user thinks the zone was selected when it wasn't. Confusion.
  - **Root cause:** `EpicController._send()` and `VolumeController._send()` are called without checking the return value (fire-and-forget, like BpmController). No mechanism propagates send failure to the view. The status label remains static ("Sending to 127.0.0.1:57120").
  - **Verification:** `bpm_logic.py` lines 268–284 (EpicController.select_zone) and lines 341–348 (VolumeController.slider_released) both call `self._send(...)` with no return-value check. The view never checks for False returns (view.py lines 197, 245 show bare `epic_controller.select_zone(z)` and `volume_controller.slider_released()` calls with no conditional).

- **No pending/loading state.** UDP sends are fire-and-forget, but a brief delay (~0.01–0.1 s) exists before the engine receives and processes the message. There is no visual indication that a send is in flight. For a user on a slow network or with a busy engine, this could be confusing: "Did my click register?"

- **No disabled state for offline engine.** If the app detects the engine is unreachable (e.g., after a failed send), zone buttons and volume scale could be grayed out (`state="disabled"`, `text="offline"`). Currently, they always appear active even if every send will fail.

- **No error message in status label.** Phase 02 recommended: "When `OscClient.send_play()` returns False (OSError), the view should briefly show red or display 'Connection lost' for 2 seconds." Phase 03 inherits this gap for zone buttons and volume slider.

- **No undo/rollback mechanism.** If the user selects a zone and the send fails, the button state (bold/caption) is already updated. Tkinter's send is fire-and-forget (intentionally; D-24), so the view never learns of failure and can't rollback. This is a design constraint (the app is send-only in Phase 3), but it's still a gap.

- **Inherited from Phase 2:** No visual state-mismatch indication. If the app closes and restarts, or the engine is re-evaluated in SuperCollider, the button state (zone, volume) might not match the actual engine state. The app is send-only (no feedback path until Phase 4), so it's blind to state drift. (Phase 02 documented this as accepted gap LINK-02/03, Phase 4 responsibility.)

**Evidence:**
- Code: `python_app/bpm_logic.py`, lines 268–284 (EpicController.select_zone, calls self._send without checking return), lines 341–348 (VolumeController.slider_released, same).
- Code: `python_app/view.py`, line 197 (zone button command), line 245 (volume release bind) — no return-value handling.
- Tests: `test_epic_logic.py` (from 03-02-SUMMARY.md) tests EpicController logic but does not cover send failure (send is mocked with a list). Same for `test_volume_logic.py` (from 03-04-SUMMARY.md): 24 tests, all pass, but none exercise send failure.
- Phase 02 audit Top 3 #1: "No error visual feedback on OSC send failure... SEVERITY: HIGH; affects both BPM and Play/Stop." Phase 03 extends the same problem to zone buttons and volume slider without addressing the underlying issue.

---

## WR-01 Status (Phase 1 Finding, Phase 2 Fixed)

**Finding (Phase 1):** Up/Down arrow keys nudge BPM even while the entry field has focus, clobbering typed text.

**Phase 02 Fix:** Entry field now has its own `<Up>`/`<Down>`/`<Shift-Up>`/`<Shift-Down>` bindings returning `"break"` (view.py, lines 114–117). These take precedence over root-level bindings while the entry has focus.

**Phase 03 Impact:** NONE. The new zone buttons and volume scale do not interfere with the WR-01 fix.
- Zone buttons have `takefocus=0`, so they never receive keyboard focus.
- Volume scale has `takefocus=0`, so it never receives keyboard focus.
- Root-level arrow-key BPM shortcuts (lines 167–170) fire whenever focus is not on the entry field, including right after a zone click or volume drag (verified by tests: `test_zone_click_keeps_arrow_shortcuts_on_bpm`, `test_volume_slider_keeps_arrow_shortcuts_on_bpm`).

**Conclusion:** WR-01 is closed and remains fixed. No regression in Phase 03. ✓

---

## Registry Safety Audit

No `components.json` found; this project uses custom Tkinter code, not shadcn or third-party UI component registries. Registry audit skipped.

---

## Files Audited

**Phase 03 additions:**
- `python_app/view.py` (291 lines) — Added `_build_zone_row()` (lines 174–206), `_on_zone_changed()` (lines 208–214), `_build_volume_row()` (lines 216–245), `_on_volume_changed()` (lines 249–250); fixed `transport_row` `pady=4→8` (line 131); added `volume_controller` parameter to `__init__` and `epic_controller` parameter (lines 36, 42).
- `python_app/config.py` (39 lines) — Added `EPIC_ZONES` dict (lines 24–30), `EPIC_DEFAULT_ZONE` (line 31), `VOLUME_MIN/MAX/DEFAULT` (lines 37–39).
- `python_app/bpm_logic.py` (352 lines) — Added `EpicController` class (lines 223–288), `clamp_volume` function (lines 291–301), `VolumeController` class (lines 304–352).
- `python_app/tests/test_epic_logic.py` (new file, ~200 lines) — 16 unit tests for zone map and `EpicController`.
- `python_app/tests/test_volume_logic.py` (new file, ~100 lines) — 24 unit tests for `clamp_volume` and `VolumeController`.
- `python_app/tests/test_view_tk.py` (extended) — Added 4 new zone/volume Tk widget tests, extended `_build_all` fixture.
- `python_app/main.py` (updated) — Wired `EpicController` and `VolumeController` with `send=client.send_epic` and `send=client.send_volume`; called `epic.send_initial()` and `volume.send_initial()` in the launch sequence.

**Test results (from 03-04-SUMMARY.md):**
- Python suite: 150 tests passed, 0 skipped (122 pre-existing + 24 volume-logic + 4 Tk volume)
- App launch: `./run.sh --port 57199 --exit-after 800` exits 0
- SuperCollider smoke suite: 65 `CHECK OK:` lines, `SMOKE PASS`

---

## Comparison to Phase 02 Baseline

| Pillar | Phase 02 | Phase 03 | Change |
|--------|----------|----------|--------|
| Copywriting | 3/4 | 3/4 | 0 (zone names are clear but no tooltips) |
| Visuals | 2/4 | 3/4 | **+1** (bold font + caption fix for zone highlight) |
| Color | 2/4 | 2/4 | 0 (no hardcoded colors, but no state coding) |
| Typography | 2/4 | 2/4 | 0 (font weight for zone select, but still only 1 custom size) |
| Spacing | 2/4 | 3/4 | **+1** (control rows now unified at pady=8) |
| Experience Design | 3/4 | 3/4 | 0 (responsive but inherits OSC failure feedback gap) |
| **Overall** | **14/24** | **16/24** | **+2** |

**Why +2, not higher?**
1. Zone highlight (bold + caption) is a real improvement over Phase 2's finding that relief alone doesn't work on macOS. **+1 point justified for Visuals.**
2. Control row spacing is now unified (transport_row pady 4→8). This partially addresses Phase 2's Top 3 Priority #2. **+1 point justified for Spacing.**
3. However, the underlying visual and error-feedback gaps from Phase 2 are NOT addressed:
   - No hover/active state feedback on buttons (Visuals ceiling stays at 3/4)
   - No state-based color coding (Color stays at 2/4)
   - No additional font sizes (Typography stays at 2/4)
   - **No OSC send-failure feedback on zone clicks or volume drags** (Experience Design stays at 3/4, and this is now a HIGHER-severity issue as it affects three control types: BPM nudges/entry, Play/Stop button, Zone buttons, and Volume slider)

---

## Top 3 Priority Fixes

1. **Add OSC send-failure feedback to all controls** — **BLOCKER (HIGH SEVERITY).** Zone button clicks, volume slider releases, BPM nudges/entry, and Play/Stop button clicks can fail silently. When `OscClient.send_*()` returns False, the view should display "Connection lost" or similar in the status label for 2–3 seconds, and optionally flash the status red. The listener-before-send ordering ensures the UI is consistent with the app's internal state, but the user is blind to whether the engine actually received the message. *Affects 4 control types, 3 of which are new in Phase 3.* **Impact: User confusion, app appears unresponsive when network fails.** **Fix: Modify all send calls (BpmController._send_now, PlayController.set_playing, EpicController.select_zone, VolumeController.slider_released) to capture the return value and notify a `send_status` listener; wire status label to show "ok" (neutral), "sending..." (brief), or "Connection lost" (red, 2–3 s).** **Estimated: 3 edits (bpm_logic.py, view.py, maybe main.py color constants).**

2. **Complete the spacing scale unification** — **MEDIUM PRIORITY.** Control rows (pady=8) are now consistent, but container padding (padx=12, pady=10) and button/entry padx values (4, 8, 2) are ad-hoc. Define `PADDING_UNIT = 4; PADDING_DOUBLE = 8; CONTAINER_PADX = 12; CONTAINER_PADY = 8` at the top of view.py, then apply throughout. Also, change status_label and on_top_check from `pady=(4, 0)` to `pady=(PADDING_UNIT, PADDING_UNIT)` for symmetry. *Fixes Phase 02's Top 3 Priority #2 fully.* **Estimated: 1 edit (view.py, ~8 lines changes + comments).**

3. **Add visual hover/active state to zone buttons** — **MEDIUM PRIORITY.** Like Phase 02's finding that Tk buttons on macOS Aqua don't show relief, zone buttons have no visible hover or pressed state. Add `activebackground="lightgray"` and `activeforeground="black"` to the zone button definition (view.py, line 192), or apply a custom relief ("raised", bd=2). Test on macOS to confirm visibility. *Same recommendation as Phase 02 Top 3 #3, now applicable to zone buttons.* **Estimated: 1 line change (zone button kwargs).**

---

## Recommendations

### Blocking Issues: NONE

The UI is functional. All acceptance criteria from Phase 03 are met:
- ✓ Five zone buttons appear and send their presets.
- ✓ Zone highlight (bold + caption) is visible.
- ✓ Volume slider follows drag and sends on release.
- ✓ control rows are now spaced consistently (pady=8).
- ✓ Arrow-key BPM shortcuts unaffected (WR-01 remains fixed).
- ✓ All tests pass (150/150).

The app is ship-ready for Phase 03 acceptance.

### High Priority (address before Phase 04):

1. **OSC send-failure feedback** (see Top 3 #1) — This is now a **BLOCKER for user confidence.** The app should never silently ignore failed sends. With zone buttons and volume slider now in play, a silent failure affects three control types. Address this in Phase 03 refinement or Phase 04 launch (whichever comes first).

2. **Spacing scale completion** (see Top 3 #2) — Finish the Phase 02 fix by unifying all padding, not just control rows. 10-minute task, low risk.

### Medium Priority (Phase 04+):

3. **Zone button hover/active state** (see Top 3 #3) — Improve button clarity on macOS. Can wait until Phase 04 if Phase 03 is feature-complete.

4. **Tooltips for zone buttons and volume scale** — Document zones (what each effort level means) and clarify the 0–100 volume range. Nice-to-have, not blocking.

---

## Conclusion

**Phase 03 Plan 02 (zone row) and Plan 04 (volume slider) deliver functional, clean controls** that follow the established patterns from Phase 01/02:
- Pure-logic controllers (EpicController, VolumeController) are well-architected and test-driven.
- Zone highlight (bold font + caption) is a thoughtful fix for macOS Aqua's relief limitations.
- Control row spacing is now unified (partial fix of Phase 02's spacing issue).
- All 150 tests pass, including new zone and volume tests.

**However, the UI audit reveals Phase 03 extends the same high-severity gaps from Phase 02:**
- No visual OSC send-failure feedback — now affects zone buttons and volume slider in addition to BPM and Play/Stop.
- Spacing scale is partially fixed (control rows unified) but not fully completed (container and button padding still ad-hoc).
- No state-based color coding, no hover/active state feedback, no additional font sizes.

**Audit score: 16/24 (67%).** Unchanged from Phase 02, reflecting that Phase 03 adds working controls without improving the UI quality ceiling. The new controls inherit the same visual and error-handling gaps from Phase 02.

**Recommendation: PASS Phase 03 acceptance; prioritize OSC send-failure feedback in Phase 04 launch (HIGH-SEVERITY user-facing issue) and complete the spacing scale unification (MEDIUM-PRIORITY design consistency issue).**

The core contracts (EPIC-03: zone buttons send presets; GUI-03: volume slider sends release value) are met and proven by tests and integration with the engine's `/pp/epic` and `/pp/volume` commands.

---

*Phase: 03-epic-zones-volume*
*Audited: 2026-10-09*
*Summary: 150/150 tests passing (122 Phase 1–2 + 24 volume-logic + 4 Tk volume)*
