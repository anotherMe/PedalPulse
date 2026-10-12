---
phase: 05-library-selectors-in-the-gui
reviewed: 2026-10-12T00:00:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - python_app/library_logic.py
  - python_app/main.py
  - python_app/tests/test_library_logic.py
  - python_app/tests/test_main_launch.py
  - supercollider/library/README.md
findings:
  critical: 0
  warning: 2
  info: 4
  total: 6
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-10-12
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

I reviewed the library selector logic, the `main.py` wiring (including the new `--hidden` flag), the two test modules and the library README. I also read `config.py`, `osc_client.py`, the `view.py` dropdown code and the engine's `~ppStemValid` in `supercollider/core/loader.scd`, to check the cross-module claims.

The retry state machine in `LibrarySelector.select` holds up. I traced these cases:
- A failed send, then a re-pick.
- A listener that raises.
- A send that raises.
- A failed `send_initial`.
- A switch back to the previously selected name after a failed send.

In each case `_selected` and `_last_send_ok` stay consistent and D-05 is preserved. `_STEM_RE` with `fullmatch` matches the engine's rule exactly, including the 64-character limit, the leading `_` and the reserved `auto`. No security issues were found. The folder is fixed in config, no path is built from user input, and the engine validates every name.

The remaining problems are one stale piece of documentation, one footgun in the new `--hidden` flag, and some minor accuracy and test-robustness points.

## Warnings

### WR-01: README lists the library contents incorrectly

**File:** `supercollider/library/README.md:15-17`
**Issue:** The README says "Right now the library holds `progressions/classic`, `melodies/classic`, `melodies/classic_lead` ... and `palettes/classic`." The tree also contains `melodies/classic_lead_loud.scd`. `test_real_library_folders` asserts that file exists, so it is a committed fact. A rider reading the README will not know the third melody exists, and the dropdown will show a name the docs never mention. Because of the "never edit a committed file" rule, this README is the only record of what each variation is, so it needs to stay complete.
**Fix:** Add `melodies/classic_lead_loud` (with a one-line description of how it differs from `classic_lead`) to the sentence, or replace the hard-coded list with "see the `desc` line in each file". The second option avoids the list going stale again.

### WR-02: `--hidden` without `--exit-after` starts an app nobody can see or close

**File:** `python_app/main.py:85-91`
**Issue:** `--hidden` calls `root.withdraw()` and then `mainloop()`. If `--exit-after` is 0 (the default), nothing ever destroys the root. The result is an invisible Tk process with no Dock window to close, so the user must kill it from outside. The flag's help text says it is for automated checks, but nothing enforces pairing it with `--exit-after`. A negative `--exit-after` is also silently treated as "never", because only `> 0` is checked.
**Fix:** Reject the combination at parse time:
```python
args = parser.parse_args(argv)
if args.hidden and args.exit_after <= 0:
    parser.error("--hidden requires --exit-after > 0 (otherwise the window can never be closed)")
```
Alternatively, give `--exit-after` `type=` a validator that rejects negative values.

## Info

### IN-01: `scan_library` lists symlinks the engine will refuse

**File:** `python_app/library_logic.py:25-31, 45-50`
**Issue:** The docstring says only files "whose stem the engine would accept" are listed. `entry.is_file()` follows symlinks, but the engine's `~ppLibContained` (loader.scd:57-62) resolves the real path and rejects a symlink pointing outside the library. A symlink such as `evil.scd -> /elsewhere/x.scd` is therefore listed and selectable, and picking it only produces an engine ERROR line. This is harmless because the engine is the validator, but the docstring over-claims.
**Fix:** Either skip `entry.is_symlink()` entries, or soften the docstring to "whose stem the engine would accept; the engine also checks that the file stays inside the library".

### IN-02: Redundant checks in `scan_library`

**File:** `python_app/library_logic.py:40`
**Issue:** `name.startswith(".")` is fully covered by `_STEM_RE`, because the first character must be `[a-z0-9]`. A name that fails the `.scd` suffix check is already handled by the stem slice. The extra condition is dead weight and suggests the regex is not trusted.
**Fix:** Drop `or name.startswith(".")`, or add a comment saying the check is only there to skip files before the slice.

### IN-03: README sort-order wording is looser than the code

**File:** `supercollider/library/README.md:39-41`
**Issue:** The README says the rest are listed "from A to Z". The code uses code-point order, so digits sort before `_`, and `_` sorts before letters. `classic2` therefore comes before `classic_lead`, as the test asserts. This is unlikely to confuse anyone, but it is not strictly what the README says.
**Fix:** Say "in alphabetical order by file name (digits first)".

### IN-04: Launch test hard-codes default values and has fragile skip logic

**File:** `python_app/tests/test_main_launch.py:21-29, 34-43`
**Issue:**
- `EXPECTED` repeats the defaults `120.0`, `10.0` and `80.0`, and the `/pp/...` addresses, instead of deriving them from `config`. Changing a default in `config.py` will break this test with no hint of why. If the duplication is intentional, as an independent check of the wire format, a comment should say so.
- `_display_available` runs `subprocess.run(..., timeout=30)` without catching `TimeoutExpired`. A hung Tk probe errors the whole module instead of skipping.
- The probe also skips when `import tkinter` itself is broken, which hides the Tk-compatibility regression that `main.py`'s gate exists to catch.
- Nothing checks that `--hidden` really withdraws the window; the test only checks that the process exits cleanly.
**Fix:** Derive the numbers from `config.BPM_DEFAULT` and the like (or comment the duplication). Wrap the probe in `try/except subprocess.TimeoutExpired: return False`. Distinguish an import failure from a display failure in the probe.

---

_Reviewed: 2026-10-12_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
