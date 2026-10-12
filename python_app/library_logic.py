"""Pure logic for the library selectors (GUI-05, GUI-06).

No tkinter and no OSC import here: this module scans a library folder and
holds the current choice of one dropdown. The send is an injected callable,
so tests need no socket. The engine is the validator of every name
(supercollider/core/loader.scd ~ppSelect); the app sends what the rider
picked and never second-guesses it.
"""

from __future__ import annotations

from pathlib import Path
from typing import Callable

import config


def scan_library(folder: Path) -> list[str]:
    """Return the file stems of the .scd files in `folder` (GUI-05).

    `classic` comes first when present, the rest follow in A-Z order. Names
    starting with "." or "_" are skipped (the _template file is not a
    variation). A missing, unreadable or non-folder path gives []; this
    function never raises.
    """
    try:
        entries = [entry.name for entry in Path(folder).iterdir()]
    except OSError:
        return []
    stems = set()
    for name in entries:
        if name.endswith(".scd") and not name.startswith((".", "_")):
            stems.add(name[: -len(".scd")])
    first = [config.LIBRARY_FIRST_STEM] if config.LIBRARY_FIRST_STEM in stems else []
    rest = sorted(stems - set(first))
    return first + rest


def to_wire(label: str) -> str:
    """Map a dropdown label to the word sent to the engine (D-07)."""
    return config.AUTO_NAME if label == config.AUTO_LABEL else label


class LibrarySelector:
    """Current choice of one library dropdown (Palette, Progression, Melody).

    Shaped like EpicController: listeners are told about a change, then the
    name is sent once, fire-and-forget. Unlike EpicController it never
    raises on an unknown label: library names are an open set and the
    engine validates.
    """

    def __init__(
        self,
        title: str,
        folder: Path,
        send: Callable[[str], object],
        *,
        scan: Callable[[Path], list[str]] = scan_library,
    ) -> None:
        self.title = title
        self._folder = folder
        self._send = send
        self._scan = scan
        self._selected = config.AUTO_LABEL
        self._listeners: list[Callable[[str], None]] = []

    @property
    def selected(self) -> str:
        return self._selected

    @property
    def folder(self) -> Path:
        return self._folder

    def options(self) -> list[str]:
        """Auto plus the stems on disk, scanned afresh on every call (D-08)."""
        return [config.AUTO_LABEL, *self._scan(self._folder)]

    def add_listener(self, fn: Callable[[str], None]) -> None:
        self._listeners.append(fn)

    def select(self, label: str) -> None:
        """Pick `label`: notify listeners, then send it once (D-05).

        Does nothing for a non-string, an empty label or the label already
        selected. The label is not checked against the folder: a file can
        vanish between listing and picking, and the engine validates.
        """
        if not isinstance(label, str) or not label or label == self._selected:
            return
        self._selected = label
        for fn in self._listeners:
            fn(label)
        self._send(to_wire(label))

    def send_initial(self) -> None:
        """Send the current choice once, without notifying (D-04)."""
        self._send(to_wire(self._selected))
