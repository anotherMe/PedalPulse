"""Entry point for the PedalPulse control app.

The Tk compatibility gate runs BEFORE importing osc_client/bpm_logic/view,
so a broken interpreter never even imports python-osc (GUI-04, D-03, D-04).
All sends happen on the Tk main thread via a non-blocking UDP send; there is
no thread and no receive path (D-24). This app never starts, supervises or
stops sclang/scsynth.
"""

from __future__ import annotations

import argparse
import sys

import config
import tkcheck


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="PedalPulse control app")
    parser.add_argument(
        "--port",
        type=int,
        default=config.OSC_PORT,
        help="Target sclang OSC port (default: %(default)s)",
    )
    parser.add_argument(
        "--exit-after",
        type=int,
        default=0,
        help="Destroy the window after this many ms (0 = never; used by automated launch checks)",
    )
    args = parser.parse_args(argv)

    tkinter = tkcheck.check_tk_compatible()  # exits 1 before any python-osc import on a broken Tk

    from bpm_logic import BpmController
    from osc_client import OscClient
    from view import BpmWindow

    try:
        root = tkinter.Tk()
    except tkinter.TclError as exc:
        print(f"ERROR: Tcl/Tk failed to start: {exc}", file=sys.stderr)
        print(tkcheck.FIX_HINT, file=sys.stderr)
        return 1

    client = OscClient(port=args.port)
    controller = BpmController(send=client.send_bpm, schedule=root.after, cancel=root.after_cancel)
    BpmWindow(root, controller, status_text=f"Sending to {client.target}")
    controller.send_initial()

    if args.exit_after > 0:
        root.after(args.exit_after, root.destroy)

    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
