"""Tk compatibility gate for the PedalPulse Python control app (GUI-04, D-03, D-04).

Stdlib only -- NO module-level `import tkinter`, so this module can be
imported safely even on an interpreter where tkinter/_tkinter is broken.
`check_tk_compatible()` imports tkinter lazily, inside the function, and
reports a clear fix instead of letting an ImportError/traceback surface.

"Incompatible" (D-03) means either:
  - tkinter/_tkinter fails to import, or
  - tkinter.TkVersion < MIN_TK_VERSION

Tk 8.6 and 9.x both pass -- no exact build-pairing check (D-03). No GUI
dialog is attempted on failure, since Tk may not be loadable (D-04).
"""

from __future__ import annotations

import platform
import sys

MIN_TK_VERSION = 8.6

FIX_HINT = (
    "Fix: launch PedalPulse via ./run.sh, which builds ./.venv from "
    "Homebrew python3.13 (the interpreter on this Mac with a working "
    "Tcl/Tk; Tk 8.6 and 9.x are both fine). If python3.13 itself lacks "
    "Tk, install the Homebrew formula python-tk@3.13 to add it."
)


def check_tk_compatible():
    """Return the tkinter module if this interpreter has a compatible Tk.

    Exits the process with status 1 (after printing a clear stderr
    message plus FIX_HINT) if tkinter cannot be imported or its Tk
    version is below MIN_TK_VERSION.
    """
    try:
        import tkinter
    except ImportError as exc:
        print(
            f"ERROR: Tkinter is not available in this Python "
            f"({sys.executable}, {platform.python_version()}): {exc}",
            file=sys.stderr,
        )
        print(FIX_HINT, file=sys.stderr)
        sys.exit(1)

    if tkinter.TkVersion < MIN_TK_VERSION:
        print(
            f"ERROR: Tcl/Tk {tkinter.TkVersion} is too old — PedalPulse "
            f"needs Tk {MIN_TK_VERSION} or newer.",
            file=sys.stderr,
        )
        print(FIX_HINT, file=sys.stderr)
        sys.exit(1)

    return tkinter


if __name__ == "__main__":
    tkinter = check_tk_compatible()
    print(f"Tcl/Tk {tkinter.TkVersion} OK ({sys.executable})")
    sys.exit(0)
