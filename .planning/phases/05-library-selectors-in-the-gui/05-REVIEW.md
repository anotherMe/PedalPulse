---
phase: 05-library-selectors-in-the-gui
reviewed: 2026-10-12T00:00:00Z
depth: standard
files_reviewed: 10
files_reviewed_list:
  - python_app/config.py
  - python_app/library_logic.py
  - python_app/main.py
  - python_app/osc_client.py
  - python_app/tests/test_library_logic.py
  - python_app/tests/test_main_launch.py
  - python_app/tests/test_osc_client.py
  - python_app/tests/test_view_tk.py
  - python_app/view.py
  - supercollider/library/README.md
findings:
  critical: 0
  warning: 3
  info: 4
  total: 7
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-10-12
**Depth:** standard
**Files Reviewed:** 10
**Status:** issues_found

## Summary

The phase adds `scan_library`, `LibrarySelector`, `OscClient.send_selection`, the three-dropdown column in `view.py` and the rebuild-on-open post command, plus tests. I found no security vulnerabilities and no crash-level defects.

Checks that held up:
- `scan_library` uses `fullmatch`, so a trailing newline is rejected.
- The scan filter mirrors the engine's `~ppStemValid`, so no path outside the folder can be built from a name.
- Menu rebuild goes through `Menu.delete`, which also frees the old Tcl commands.
- The default-argument lambda captures are correct.
- 50 tests in `test_library_logic.py` and `test_osc_client.py` pass (I did not run the Tk tests).

The real concerns are about state divergence between the GUI and the engine when a send is lost, and a few fragile or duplicated spots.

## Warnings

### WR-01: A lost send leaves the dropdown out of sync with the engine, and the same pick cannot be retried

**File:** `python_app/library_logic.py:107-112`
**Issue:** `select()` sets `self._selected` and notifies listeners (the Tk var) before sending, and discards the send's return value. `OscClient.send_selection` returns `False` on `OSError`, `OverflowError` or `BuildError`, but nothing reads it. Two cases follow.
- Failed send: the button shows `classic_lead` while the engine never received it. The D-05 guard (`label == self._selected`) then makes re-picking that name a silent no-op, so the rider can only recover by picking a different name and then picking it back.
- Engine restart: the project's lifecycle has the user starting SuperCollider separately. The engine boots on `auto`, but the app's dropdown and `_selected` keep the old choice. Re-picking the visible name does nothing.

`test_failed_send_keeps_the_selection` pins the first case as intended, but it only asserts the state, not that recovery is possible. The README documents the "pick another and back" workaround, so this is a known trade-off, but it makes the dropdown a lie after any dropped send.
**Fix:** Either make `send` report failure and revert, or allow a re-pick to retry after a failed send:
```python
def select(self, label):
    if not isinstance(label, str) or not label:
        return
    if label == self._selected and self._last_send_ok:
        return
    self._selected = label
    for fn in self._listeners:
        fn(label)
    self._last_send_ok = self._send(to_wire(label)) is not False
```
At minimum, add a README line about re-syncing after an engine restart.

### WR-02: A listener exception skips the send and leaves state half-applied

**File:** `python_app/library_logic.py:109-112`
**Issue:** `_selected` is assigned, then listeners run, then the send happens. The listener in `view.py` is `var.set`, which can raise `tkinter.TclError` (for example if the window is being torn down during a pick). The exception escapes `select()` before `self._send(...)`. `_selected` has already changed, so the selection is recorded but never sent, and WR-01's no-op-on-repeat guard then hides it. `EpicController` has the same listener-then-send shape, but there the wire value is the more important output.
**Fix:** Send first and then notify (the spec D-05 order may be the reason for listener-first; if so, wrap the listeners):
```python
self._selected = label
try:
    for fn in self._listeners:
        fn(label)
finally:
    self._send(to_wire(label))
```

### WR-03: `test_main_launch` opens a real, visible window and steals focus (twice per run)

**File:** `python_app/tests/test_main_launch.py:33-38`
**Issue:** The test runs the real `main.py` in a subprocess, which builds an on-screen Tk root on the user's display. `test_view_tk.py` deliberately places its roots off-screen (`geometry("+2000+2000")`) and documents why, but this subprocess does not. Each run flashes a window for about 300 ms, twice, and can steal keyboard focus from whatever the developer is typing in. On a headless or CI box it fails with a `TclError`, and that failure is indistinguishable from a regression because the assertion is `returncode == 0`. There is also no skip when no display is available.
**Fix:** Add a skip guard for display-less runs, or support an env/flag in `main.py` to start withdrawn or off-screen. Hiding the window needs a `--exit-after`-style switch such as `--geometry +2000+2000`. Alternatively, skip when Tk cannot initialise:
```python
@pytest.fixture(scope="module", autouse=True)
def _need_display():
    try:
        tk.Tk().destroy()
    except tk.TclError:
        pytest.skip("no display for the Tk launch test")
```

## Info

### IN-01: Redundant `.startswith(".")` check in `scan_library`

**File:** `python_app/library_logic.py:40`
**Issue:** `_STEM_RE` requires the first character to be `[a-z0-9]`, so any name starting with `.` already fails `fullmatch` at line 43. The docstring says hidden files are skipped, but the regex does that. The extra check is dead logic.
**Fix:** Drop `or name.startswith(".")`, or keep it with a comment saying it is a fast path.

### IN-02: Duplicate helper in `test_view_tk.py`

**File:** `python_app/tests/test_view_tk.py:506-507` and `659-660`
**Issue:** `_menu_labels` and `_labels` are identical. Both also raise `TypeError` on an empty menu, because `menu.index("end")` returns `None`; this is currently masked since "Auto" is always present.
**Fix:** Keep one helper and use `(menu.index("end") or -1) + 1`, or handle `None`.

### IN-03: Fragile layout assertion

**File:** `python_app/tests/test_view_tk.py:589`
**Issue:** `tk_root.winfo_reqheight() == old_column.winfo_reqheight()` holds only while the library column stays shorter than the controls column. This depends on fonts and theme, and a taller font on another Mac could break it. Equality is the wrong shape for "the column adds width, not height".
**Fix:** Assert `<=` on the library column's height against the old column's, which states the intent directly.

### IN-04: README is stale and contradicts the no-edit rule

**File:** `supercollider/library/README.md:15-17, 53-55`
**Issue:** This phase touched the README, but the "Right now the library holds" list still omits `melodies/classic_lead_loud`. That file is committed in `bd04c46`, and `test_real_library_folders` asserts it appears in the dropdown. Lines 53-55 also say "To hear a file again after you changed it, pick another name and then pick it back", while "The one rule" (line 21) says never to edit a committed file. The sentence is only valid for uncommitted work, which the README doesn't say.
**Fix:** Add `classic_lead_loud` to the list. Reword line 54 to "a file you are still working on (not yet committed)".

---

_Reviewed: 2026-10-12_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
