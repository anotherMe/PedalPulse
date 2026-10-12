---
phase: 05-library-selectors-in-the-gui
reviewed: 2026-10-12T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - python_app/main.py
  - supercollider/library/README.md
findings:
  critical: 0
  warning: 0
  info: 3
  total: 3
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-10-12
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Reviewed `python_app/main.py` and `supercollider/library/README.md` against diff base e21aeb2. The diff is small: a `--hidden` guard in `main.py` (WR-02 fix) and a README update for `classic_lead_loud` plus a `desc` sentence (WR-01 fix).

I read `config.py`, `library_logic.py` and `osc_client.py` for context and checked the README's claims against the repo. They hold:
- `classic_lead_loud.scd` exists.
- `scripts/check.sh --library-only` exists.
- The 3-failed-bars fallback to classic is in `supercollider/core/render.scd:120`.
- The dropdown ordering, the "already selected" behaviour and the retry-after-failed-send behaviour match `LibrarySelector` and `scan_library`.

I found no bugs and no security issues. The guard runs before the Tk gate and before any python-osc import, so the early exit stays cheap. `parser.error` exits with status 2 and the `--hidden` case is covered. The three remaining items are minor.

## Info

### IN-01: README says the `desc` line is "at the top" of every file, but it is not

**File:** `supercollider/library/README.md:19`
**Issue:** The new sentence reads "Every file also has a `desc` line at the top that says what it sounds like." In the library files, `desc:` is the first key inside the Event, after a comment header. It sits at lines 9-17 in the committed variations and line 28 or 40 in the templates. The file's top lines are comments. An author could reasonably look for `desc` on line 1. The sentence also sits in the paragraph about the dropdown and OSC names, which could suggest `desc` is shown in the app. It is not.
**Fix:** Reword to match the File contract section at line 115, for example: "Every file also has a `desc` entry (one plain sentence) that says what it sounds like. It is for authors; the app does not show it."

### IN-02: `--exit-after` with a negative value is silently ignored unless `--hidden` is given

**File:** `python_app/main.py:41-42, 90`
**Issue:** The new guard rejects `--hidden` with `--exit-after <= 0`, but `--exit-after -5` without `--hidden` is accepted. It is treated as "never", the same as 0, with no message. This is harmless and matches the help text only for 0. The help text says "0 = never", so a negative value is undocumented behaviour.
**Fix:** Optionally validate the value up front: `if args.exit_after < 0: parser.error("--exit-after must be >= 0")`.

### IN-03: README one-liners hard-code `.venv/bin/python` and port 57120

**File:** `supercollider/library/README.md:67, 74`
**Issue:** The copy-paste commands assume the venv is at `.venv` and sclang is on the default port. The app takes `--port`, so someone running on a non-default port would send these messages to nothing. UDP gives no error, so it fails silently. This is pre-existing and not part of the phase diff, but the README is in scope.
**Fix:** Add a short note: "If the engine listens on another port, change `57120` to match the `--port` you gave the app."

---

_Reviewed: 2026-10-12_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
