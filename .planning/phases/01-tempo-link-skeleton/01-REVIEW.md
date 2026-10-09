---
phase: 01-tempo-link-skeleton
reviewed: 2026-10-09T08:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - python_app/bpm_logic.py
  - python_app/view.py
  - scripts/smoke_test.sh
findings:
  critical: 0
  warning: 1
  info: 1
  total: 2
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-10-09T08:00:00Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Re-review of the three files touched by the `01-REVIEW-FIX.md` pass that closed CR-01
(`scripts/smoke_test.sh`), WR-01, and WR-02 (both in `python_app/bpm_logic.py` /
`python_app/view.py`) from the prior `01-REVIEW.md`.

All three fixes were verified correct by tracing the actual code paths (not just reading the
diff): `scripts/smoke_test.sh` now captures `sclang`'s exit code via `|| rc=$?` instead of the
`cmd; rc=$?` anti-pattern, so a failing run reaches `cat "$LOG"` and the "smoke test FAILED"
diagnostic under `set -euo pipefail` (confirmed by inspection of the control flow; the script's
own non-sclang failure branches were also exercised). `view.py`'s `_committing` reentrancy guard
correctly short-circuits the synchronous `<FocusOut>` that `commit_entry(force=True)`'s
`focus_set()` triggers, verified against the full call sequence. `bpm_logic.py`'s
`apply_entry` now notifies on every `changed=False` path regardless of `force`, matching its own
docstring; traced both the `force=True`/unchanged and `force=False`/unchanged branches by hand
and confirmed exactly one notification fires per commit, with no duplicate or missing notify. The
full test suite (66 tests) passes.

One new, previously unflagged defect was found and reproduced by instrumenting a live
`BpmWindow`: the global `<Up>`/`<Down>`/`<Shift-Up>`/`<Shift-Down>` bindings in `view.py` are
registered on `root`, which (per Tk's bindtag resolution) also fires while the BPM `Entry` widget
itself has keyboard focus, since neither the `Entry` widget nor its `Entry` class binds those keys.
Pressing an arrow key while the user has clicked into the entry field and is mid-typing a new BPM
value silently discards whatever they had typed and replaces it with the nudged committed value.
This is a genuine, demonstrable bug (not previously flagged in the prior review of these files)
classified as a Warning — recoverable by retyping, but a real and silent loss of user input. One
previously-reported, still-unresolved Info item (`BpmWindow.__init__`'s size) is carried forward
since `view.py` is in scope for this review.

## Warnings

### WR-01: Global arrow-key bindings silently clobber in-progress text in the BPM Entry field

**File:** `python_app/view.py:115-118` (root-level bindings) interacting with `python_app/view.py:125-127` (`_on_bpm_changed`)
**Issue:**
```python
self.root.bind("<Up>", lambda _event: self.handle_nudge_key(1))
self.root.bind("<Down>", lambda _event: self.handle_nudge_key(-1))
self.root.bind("<Shift-Up>", lambda _event: self.handle_nudge_key(5))
self.root.bind("<Shift-Down>", lambda _event: self.handle_nudge_key(-5))
```
These are bound on `root`, which Tk resolves via the Entry widget's bindtag chain
(`('.!entry', 'Entry', '.', 'all')`) *after* the widget-specific and class-level bindings for
`Entry` — and neither of those binds `<Up>`/`<Down>` by default, so the root-level binding fires
even while the Entry widget has keyboard focus. `handle_nudge_key` calls
`controller.nudge(delta)`, which (if the value changes) notifies listeners, and
`_on_bpm_changed` unconditionally overwrites `self.entry_var` with the new committed value —
discarding any text the user had typed into the entry but not yet committed via Enter/focus-out.

Reproduced directly against the real `BpmWindow`/`BpmController` (headless Tk,
`QT_QPA_PLATFORM=offscreen`):
```python
win.entry.focus_set()
win.entry_var.set("17")       # user mid-typing, intending e.g. "170", not yet committed
root.event_generate("<Up>")   # single Up keypress while Entry has focus
# before: entry_var = "17",  controller.value = 120
# after:  entry_var = "121", controller.value = 121   <-- "17" is gone, no commit occurred
```
The user's draft input is silently replaced with no error, no "break", and no indication that a
nudge (rather than the keystroke they expected inside the text field) just happened. This path is
untested: `test_view_tk.py`'s `test_key_bindings_registered_and_handle_nudge_key_works` only
asserts the bindings exist and calls `handle_nudge_key` directly — it never generates a real key
event while the Entry has focus, so this interaction is not exercised by the suite.

**Fix:** Scope the nudge bindings away from the Entry widget, e.g. bind an Entry-specific no-op
(or re-dispatch) that stops propagation before it reaches the toplevel binding:
```python
for seq, delta in (("<Up>", 1), ("<Down>", -1), ("<Shift-Up>", 5), ("<Shift-Down>", -5)):
    self.entry.bind(seq, lambda _event: "break")
```
placed alongside the other `self.entry.bind(...)` calls, so Up/Down while the Entry has focus is
a no-op for nudging (consistent with the Scale widget's `takefocus=0` already excluding it from
this interaction) instead of silently discarding typed input. Alternatively, check
`self.root.focus_get() is not self.entry` inside `handle_nudge_key` before calling
`controller.nudge(delta)`.

## Info

### IN-01: `BpmWindow.__init__` is a single ~98-line method building the entire UI

**File:** `python_app/view.py:22-120`
**Issue:** Carried forward from the prior review (unchanged by this fix pass, but `view.py` is in
scope for this review). The constructor builds the scale, nudge buttons, entry
(including the new `_committing` guard setup), status label, on-top checkbutton, and all key
bindings in one method, now spanning lines 22-120. This exceeds the ~50-line code-smell threshold
and mixes several independent widget-construction concerns in one place.
**Fix:** Extract per-widget builder methods (e.g. `_build_scale`, `_build_nudge_row`,
`_build_entry`, `_build_status`, `_build_keybindings`) called from `__init__`, each taking the
parent container and returning/assigning the widget(s) it owns.

---

_Reviewed: 2026-10-09T08:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
