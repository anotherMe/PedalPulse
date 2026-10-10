---
phase: 03-epic-zones-volume
reviewed: 2026-10-09T00:00:00Z
depth: standard
files_reviewed: 12
files_reviewed_list:
  - python_app/bpm_logic.py
  - python_app/config.py
  - python_app/main.py
  - python_app/osc_client.py
  - python_app/tests/test_epic_logic.py
  - python_app/tests/test_osc_client.py
  - python_app/tests/test_view_tk.py
  - python_app/tests/test_volume_logic.py
  - python_app/view.py
  - scripts/smoke_test.sh
  - supercollider/main.scd
  - supercollider/smoke_test.scd
findings:
  critical: 0
  warning: 2
  info: 2
  total: 4
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-10-09T00:00:00Z
**Depth:** standard
**Files Reviewed:** 12
**Status:** issues_found

## Summary

Reviewed the Phase 3 (EPIC zones + master volume) deliverables: `bpm_logic.py` (EpicController/VolumeController/clamp_volume plus the pre-existing BpmController/Debouncer they sit beside), `config.py`, `main.py`, `osc_client.py`, `view.py`, the SuperCollider engine (`main.scd`) and its headless smoke test, and all four pytest suites.

Traced every state-change path (slider drag/release, nudge, entry commit, zone-button click, play/stop toggle) through the Python controllers into the OSC client and into `main.scd`'s `OSCdef`s, and checked the engine's teardown/re-evaluation, clamp, loopback-guard, and gain-staging logic (EPIC smoother → FX → master volume → limiter) for correctness. No security vulnerabilities, crashes, or data-loss risks were found — the loopback-only `srcID` guard, NaN/non-number rejection, and clamp-before-use discipline are consistently applied on both the Python and SuperCollider sides, and the new `VolumeController`/`EpicController` mirror the existing `BpmController` contracts faithfully (verified against their own test suites).

Two Warnings and two Info-level findings were identified — none of them block the core "move a control → audible change" path, but they are real defects/code smells worth fixing. See below.

## Warnings

### WR-01: `Debouncer.trigger()` can corrupt its own pending-token tracking if `schedule()` ever fires synchronously

**File:** `python_app/bpm_logic.py:65-73`
**Issue:** `trigger()` assigns `self._pending_token` to the *return value* of `self._schedule(...)` **after** that call completes:
```python
def trigger(self, fn: Callable[[], None]) -> None:
    self.cancel()

    def _fire() -> None:
        self._pending_token = None
        fn()

    self._pending_token = self._schedule(self._delay_ms, _fire)
```
If `self._schedule` ever invokes `_fire` *synchronously* before returning (e.g. a zero-delay or test fake that calls the callback immediately rather than queuing it), `_fire()` sets `self._pending_token = None` and runs `fn()` — but then the outer assignment on the last line unconditionally overwrites that `None` with whatever `self._schedule(...)` returns. `self.pending` then incorrectly reports `True` for a callback that has already fired, and a later `cancel()` call will invoke `self._cancel()` with a stale/already-consumed token. This doesn't currently manifest because `root.after` (the only scheduler wired in via `BpmController`/`main.py`) is always asynchronous, but the class is written to accept an injected scheduler ("a fake scheduler in tests" per its own docstring) and nothing guards against a synchronous one.
**Fix:**
```python
def trigger(self, fn: Callable[[], None]) -> None:
    self.cancel()
    fired = False

    def _fire() -> None:
        nonlocal fired
        fired = True
        self._pending_token = None
        fn()

    token = self._schedule(self._delay_ms, _fire)
    if not fired:
        self._pending_token = token
```

### WR-02: `osc_client.py` CLI prints "sent" even when the send failed

**File:** `python_app/osc_client.py:150-168`
**Issue:** In `main()`, each of the four send loops ignores the boolean result of `client.send_bpm/send_epic/send_volume/send_play` for the purposes of the printed message:
```python
for value in args.bpm:
    ok = client.send_bpm(value)
    all_ok = all_ok and ok
    print(f"sent /pp/bpm {value} to {client.target}")
```
`ok` is tracked only to compute the final exit code — the `print("sent ...")` line always runs, even when `send_bpm` returned `False` (and already wrote an `OscClient: failed to send ...` line to stderr). A human running this CLI manually (its stated purpose is exactly that: "manual D-08 engine-clamp verification") sees a misleading stdout "sent" confirmation alongside the stderr failure, which can mask a real failure when stdout/stderr are viewed separately or redirected to different logs. The same pattern repeats for `--epic`, `--volume`, and `--play`.
**Fix:**
```python
for value in args.bpm:
    ok = client.send_bpm(value)
    all_ok = all_ok and ok
    status = "sent" if ok else "FAILED to send"
    print(f"{status} /pp/bpm {value} to {client.target}")
```
(repeat for the `--epic`/`--volume`/`--play` blocks)

## Info

### IN-01: `EpicController` binds its zone map to a mutable module-level default argument

**File:** `python_app/bpm_logic.py:233-247`
**Issue:**
```python
def __init__(
    self,
    send: Callable[[float], object],
    zones: Mapping[str, float] = config.EPIC_ZONES,
    initial_zone: str = config.EPIC_DEFAULT_ZONE,
) -> None:
```
`config.EPIC_ZONES` is evaluated once, at `bpm_logic` module import time, and bound as the default value. Today this is safe because `__init__` immediately does `zones = dict(zones)` before storing it, so instance state never aliases the module dict. But the default is still a reference to a live, mutable global rather than a frozen snapshot: if any future code path reassigns `config.EPIC_ZONES = {...}` (as opposed to mutating it in place), every `EpicController()` constructed without an explicit `zones=` argument after that point will keep using the *original* dict object the default was bound to at import time — a classic, hard-to-spot "mutable default argument" footgun.
**Fix:** Use a sentinel default and resolve inside `__init__`, e.g. `zones: Mapping[str, float] | None = None` then `zones = dict(zones if zones is not None else config.EPIC_ZONES)`, so the live `config.EPIC_ZONES` value is read at call time, not at function-definition time.

### IN-02: `BpmController.apply_entry()` sends before notifying on a forced, unchanged commit — inconsistent with the rest of the module's "notify before send" contract

**File:** `python_app/bpm_logic.py:140-164`
**Issue:** Every other state-changing path in this module (`BpmController._set`, `PlayController.set_playing`, `EpicController.select_zone`) notifies listeners *before* calling `send`. `apply_entry` follows that order too when the value actually changes (via `_set`'s own notify-then-return). But for the `force=True` + value-unchanged case (pressing Enter twice without editing the text), the order flips:
```python
changed = self._set(parsed)       # no-op, no notify (value unchanged)
if force or changed:
    self._send_now()              # <- send happens first
if not changed:
    self._notify()                # <- notify happens after
return True
```
This is currently harmless (Tk is single-threaded and the OSC send is fire-and-forget), but it's a latent inconsistency in an otherwise carefully documented "listener-before-send" invariant, and it is not exercised by any test in `test_view_tk.py` or elsewhere (all entry-commit tests use either a genuinely-changed value or `force=False`).
**Fix:** Reorder so the unforced/forced-unchanged branch also notifies before sending, matching the rest of the module:
```python
changed = self._set(parsed)
if not changed:
    self._notify()
if force or changed:
    self._send_now()
return True
```

---

_Reviewed: 2026-10-09T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
