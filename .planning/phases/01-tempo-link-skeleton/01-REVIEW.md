---
phase: 01-tempo-link-skeleton
reviewed: 2026-10-09T06:08:25Z
depth: standard
files_reviewed: 17
files_reviewed_list:
  - python_app/bpm_logic.py
  - python_app/config.py
  - python_app/main.py
  - python_app/osc_client.py
  - python_app/requirements-dev.txt
  - python_app/requirements.txt
  - python_app/tests/conftest.py
  - python_app/tests/test_bpm_logic.py
  - python_app/tests/test_osc_client.py
  - python_app/tests/test_tkcheck.py
  - python_app/tests/test_view_tk.py
  - python_app/tkcheck.py
  - python_app/view.py
  - run.sh
  - scripts/smoke_test.sh
  - supercollider/main.scd
  - supercollider/smoke_test.scd
findings:
  critical: 1
  warning: 2
  info: 2
  total: 5
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-10-09T06:08:25Z
**Depth:** standard
**Files Reviewed:** 17
**Status:** issues_found

## Summary

Reviewed the full Phase 01 tempo-link-skeleton scope: the Tk compatibility gate, the pure BPM
controller/debounce logic, the send-only OSC client, the Tk view, the launcher/smoke-test shell
scripts, and the SuperCollider engine + its headless smoke test. The Python-side logic
(`bpm_logic.py`, `osc_client.py`, `tkcheck.py`) is careful and well covered by tests — clamping,
debounce ordering, and the loopback/Tk-gate design all hold up under tracing. The main defect
found is in `scripts/smoke_test.sh`: a `set -e` + `cmd; rc=$?` pattern that silently defeats the
script's entire purpose (printing diagnostics on failure) exactly when the engine smoke test
fails. Two further warnings cover a subtle, currently-harmless-but-fragile double-commit path in
the Tk Entry widget, and a text-normalization gap in `BpmController.apply_entry` that contradicts
its own docstring. Two minor quality/maintainability notes round out the findings.

## Critical Issues

### CR-01: `set -e` silently defeats the smoke-test script's failure diagnostics

**File:** `scripts/smoke_test.sh:37-38`
**Issue:**
The script runs under `set -euo pipefail` (line 7) and never disables it before invoking sclang:

```bash
$TIMEOUT_CMD "$SCLANG" -D supercollider/smoke_test.scd > "$LOG" 2>&1
rc=$?
```

This is the classic `cmd; rc=$?` anti-pattern under `errexit`: a plain command (not the
condition of an `if`/`while`/`&&`/`||`, and not negated with `!`) that exits non-zero causes bash
to terminate the script *immediately at that line*, before `rc=$?` on the next line ever
executes. Since sclang's/engine's entire output was redirected into `$LOG` (`> "$LOG" 2>&1`), and
the subsequent `cat "$LOG"` plus the `"smoke test FAILED (log: $LOG)"` message are never reached,
the exact failure case this wrapper exists to make debuggable — the smoke test (or sclang
itself) exiting non-zero — produces **no visible output at all** on the terminal. The script's
own exit status still correctly propagates as non-zero (so CI/`&&` chains still detect failure),
but the stated purpose of the script ("One-command terminal runner... `cat "$LOG"`" per the file's
own header comment) is defeated precisely when it matters.

This also silently loses the `[ "$rc" -eq 0 ] && grep -q "SMOKE PASS" "$LOG"` double-check on
line 42 — that extra safety net (catching a `rc=0` process exit that nonetheless never printed
`SMOKE PASS`) can never run for a non-zero exit either, though that specific case was already
covered by the early-exit; the loss is purely the diagnostic log dump.

**Fix:**
```bash
set +e
$TIMEOUT_CMD "$SCLANG" -D supercollider/smoke_test.scd > "$LOG" 2>&1
rc=$?
set -e

cat "$LOG"

if [ "$rc" -eq 0 ] && grep -q "SMOKE PASS" "$LOG"; then
	exit 0
else
	echo "smoke test FAILED (log: $LOG)" >&2
	exit 1
fi
```
or equivalently, avoid the toggle entirely:
```bash
rc=0
$TIMEOUT_CMD "$SCLANG" -D supercollider/smoke_test.scd > "$LOG" 2>&1 || rc=$?
cat "$LOG"
...
```

## Warnings

### WR-01: Enter-commit's `focus_set()` triggers an implicit, untested second commit via `<FocusOut>`

**File:** `python_app/view.py:123-136` (see also the `<FocusOut>` binding at line 81)
**Issue:**
`commit_entry(force=True)` (fired by `<Return>`/`<KP_Enter>`) ends with:

```python
self.controller.apply_entry(self.entry_var.get(), force=force)
if force:
    self.root.focus_set()
    return "break"
```

When the Entry widget actually has keyboard focus (the real interactive path: user clicks into
the field, types, presses Enter), `self.root.focus_set()` moves focus away from the Entry, which
Tk resolves by generating a `<FocusOut>` event on the Entry — and that is bound to
`commit_entry(force=False)` (line 81). So a single Enter keypress ends up invoking
`controller.apply_entry()` **twice**: once with `force=True` from `<Return>`, and once more,
implicitly, with `force=False` from the resulting `<FocusOut>`.

Today this is harmless only because the first call already normalizes `entry_var` to match the
committed value (via `BpmController._notify()` → `_on_bpm_changed`), so the second,
force=False call always sees an unchanged value and is a no-op re-notify. But it is an
unintentional coupling: any future change to `apply_entry` that adds a side effect per invocation
(logging, an OSC "commit" event distinct from a value-change send, analytics, etc.) will silently
fire twice per Enter press. It is also untested: every test in `test_view_tk.py` that exercises
`commit_entry` calls it directly (`window.commit_entry(force=True)`), never via a real focus
transition into the Entry first, so the real-world double-invocation path is never exercised by
the suite.

**Fix:** Either guard against reentrancy explicitly, or avoid the focus churn:
```python
def commit_entry(self, force: bool) -> str | None:
    if force and self.root.focus_get() is self.entry:
        # unbind-and-rebind, or set a reentrancy flag, before moving focus
        ...
```
or simpler: don't rely on `focus_set()` incidentally triggering the existing `<FocusOut>` binding
— move the "commit on blur" logic into a private helper that `<FocusOut>` and `<Return>` both
call explicitly with the correct `force` value, and have `<Return>`'s focus transfer skip the
blur-commit for the widget it's intentionally leaving.

### WR-02: Forced-but-unchanged entry commit leaves the Entry text un-normalized

**File:** `python_app/bpm_logic.py:138-162`
**Issue:** `apply_entry`'s docstring states: "An unforced, unchanged commit (focus-out) only
re-notifies so the displayed text normalises (e.g. '150.0' -> '150')". The code only calls
`self._notify()` on the `else` branch (`force=False` and unchanged); on `force=True` with an
unchanged value, it calls `self._send_now()` and **never calls `_notify()`**:

```python
changed = self._set(parsed)
if force or changed:
    self._send_now()
else:
    self._notify()
```

Concretely: if the committed value is already 150 and the user types `"150.00"` then presses
Enter (`force=True`), `parsed == 150 == self._value`, so `changed` is `False`, but since
`force` is `True` the method takes the `send_now()` branch and skips notification entirely. The
Entry widget's text is left showing `"150.00"` rather than snapping to the normalized `"150"` —
inconsistent with the normalization behavior the module's own docstring describes, and with the
`<FocusOut>` (unforced) path, which does normalize in the equivalent situation. No existing test
asserts on `entry_var` content after a forced-but-unchanged commit, so this gap is not caught by
`test_apply_entry_force_true_same_value_sends_again` (which only checks `sent`).

**Fix:** Notify on every commit path, not just the no-op one:
```python
changed = self._set(parsed)
if force or changed:
    self._send_now()
if not changed:
    self._notify()
```
(`_set` already notifies once when `changed` is `True`, so this only adds the missing
notification for the `changed=False` case, regardless of `force`.)

## Info

### IN-01: `BpmWindow.__init__` is a single ~90-line method building the entire UI

**File:** `python_app/view.py:22-114`
**Issue:** The constructor builds the scale, nudge buttons, entry, status label, on-top
checkbutton, and all key bindings in one method (lines 22-114). This exceeds the ~50-line
code-smell threshold and mixes several independent widget-construction concerns in one place,
making future changes (e.g. adding an EPIC control for a later phase) more likely to require
touching a large, already-dense method.
**Fix:** Extract per-widget builder methods (e.g. `_build_scale`, `_build_nudge_row`,
`_build_entry`, `_build_status`, `_build_keybindings`) called from `__init__`, each taking the
parent container and returning/assigning the widget(s) it owns.

### IN-02: `run.sh --setup` prints "venv ready" before the compatibility check that can still fail

**File:** `run.sh:29-37`
**Issue:**
```bash
if [ "${1:-}" = "--setup" ]; then
  shift || true
  ...
  echo "PedalPulse venv ready: .venv"
  .venv/bin/python python_app/tkcheck.py
  exit 0
fi
```
`"PedalPulse venv ready: .venv"` is printed unconditionally before running `tkcheck.py`, which
can itself exit 1 (and print its own `ERROR: ...` + `FIX_HINT`) if Tk is incompatible. A user
skimming the output sees "ready" immediately followed by an error, which reads as contradictory.
**Fix:** Move the "ready" message after a successful `tkcheck.py` run, or reword it to something
scoped only to the venv/dependency step, e.g. `"PedalPulse venv dependencies installed: .venv"`,
printed before the Tk check, and print a separate confirmation only on tkcheck success.

---

_Reviewed: 2026-10-09T06:08:25Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
