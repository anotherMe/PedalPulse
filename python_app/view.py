"""Tk widgets for the PedalPulse control app (GUI-01, GUI-02, D-06, D-12).

No OSC import here (D-24) -- this module only builds and wires Tk widgets
to a BpmController/PlayController; it never talks to the network directly.
"""

from __future__ import annotations

import tkinter as tk

import config
from bpm_logic import BpmController, PlayController

# D-06 layout: −5 −1 [value] +1 +5. The minus sign is U+2212 MINUS SIGN,
# not an ASCII hyphen.
NUDGE_LABELS = {-5: "−5", -1: "−1", 1: "+1", 5: "+5"}

# GUI-02: the button's label always names the action a click will perform.
PLAY_LABELS = {True: "Stop", False: "Start"}


class BpmWindow:
    """Compact window: BPM slider, nudge row, status line, On top toggle."""

    def __init__(
        self,
        root: tk.Tk,
        controller: BpmController,
        status_text: str,
        *,
        play_controller: PlayController,
    ) -> None:
        self.root = root
        self.controller = controller
        self.play_controller = play_controller

        root.title("PedalPulse")
        root.resizable(False, False)

        container = tk.Frame(root, padx=12, pady=10)
        container.pack()

        self.bpm_var = tk.IntVar(value=controller.value)

        self.scale = tk.Scale(
            container,
            from_=config.BPM_MIN,
            to=config.BPM_MAX,
            orient="horizontal",
            resolution=1,
            length=320,
            label="BPM",
            variable=self.bpm_var,
            command=controller.slider_moved,
            takefocus=0,
        )
        self.scale.pack(fill="x")
        # The Scale widget's own command= fires on every drag tick -- that's
        # the live display only (D-20). The actual OSC send is gated to
        # release; Scale's class-level arrow-key bindings are defused via
        # takefocus=0 above so they can't move the value without a release.
        self.scale.bind("<ButtonRelease-1>", lambda _event: controller.slider_released())

        self.nudge_row = tk.Frame(container, pady=8)
        self.nudge_row.pack()

        self.nudge_buttons: dict[int, tk.Button] = {}
        for delta in (-5, -1):
            button = tk.Button(
                self.nudge_row,
                text=NUDGE_LABELS[delta],
                takefocus=0,
                command=lambda d=delta: controller.nudge(d),
            )
            button.pack(side="left", padx=4)
            self.nudge_buttons[delta] = button

        # WR-01: reentrancy guard for commit_entry -- focus_set() below
        # triggers a synchronous <FocusOut> on the Entry, which would
        # otherwise re-enter commit_entry(force=False) from inside the
        # force=True call.
        self._committing = False

        self.entry_var = tk.StringVar(value=str(controller.value))
        self.entry = tk.Entry(
            self.nudge_row,
            textvariable=self.entry_var,
            width=5,
            justify="center",
            font=("TkDefaultFont", 16, "bold"),
        )
        self.entry.pack(side="left", padx=8)
        # D-10: Enter/KP_Enter always commits (force=True); focus-out commits
        # only a changed value (force=False), so Enter followed by a
        # focus-out never double-sends.
        self.entry.bind("<Return>", lambda _event: self.commit_entry(force=True))
        self.entry.bind("<KP_Enter>", lambda _event: self.commit_entry(force=True))
        self.entry.bind("<FocusOut>", lambda _event: self.commit_entry(force=False))

        for delta in (1, 5):
            button = tk.Button(
                self.nudge_row,
                text=NUDGE_LABELS[delta],
                takefocus=0,
                command=lambda d=delta: controller.nudge(d),
            )
            button.pack(side="left", padx=4)
            self.nudge_buttons[delta] = button

        self.transport_row = tk.Frame(container, pady=4)
        self.transport_row.pack()

        self.play_button = tk.Button(
            self.transport_row,
            text=PLAY_LABELS[play_controller.playing],
            width=8,
            takefocus=0,
            command=play_controller.toggle,
        )
        self.play_button.pack()

        play_controller.add_listener(self._on_playing_changed)

        self.status_label = tk.Label(container, text=status_text)
        self.status_label.pack(pady=(4, 0))

        self.on_top_var = tk.BooleanVar(value=False)
        self.on_top_check = tk.Checkbutton(
            container,
            text="On top",
            variable=self.on_top_var,
            command=self._toggle_on_top,
        )
        self.on_top_check.pack(pady=(4, 0))

        # D-11: Up/Down +-1, Shift+Up/Down +-5, while the window has focus.
        # Bound on root (not the Scale, which keeps takefocus=0) so the
        # shortcuts fire for every widget in the window. Held keys
        # auto-repeat into nudge(); the controller's debounce coalesces them.
        self.root.bind("<Up>", lambda _event: self.handle_nudge_key(1))
        self.root.bind("<Down>", lambda _event: self.handle_nudge_key(-1))
        self.root.bind("<Shift-Up>", lambda _event: self.handle_nudge_key(5))
        self.root.bind("<Shift-Down>", lambda _event: self.handle_nudge_key(-5))

        controller.add_listener(self._on_bpm_changed)

    def _toggle_on_top(self) -> None:
        self.root.attributes("-topmost", self.on_top_var.get())

    def _on_bpm_changed(self, new_value: int) -> None:
        self.bpm_var.set(new_value)
        self.entry_var.set(str(new_value))

    def _on_playing_changed(self, playing: bool) -> None:
        self.play_button["text"] = PLAY_LABELS[playing]

    def commit_entry(self, force: bool) -> str | None:
        """Apply the entry's current text (D-10).

        Bound to <Return>/<KP_Enter> (force=True, always commits and
        returns "break" so the entry's default newline/bell is suppressed)
        and <FocusOut> (force=False, commits only a changed value).
        After an Enter commit, focus moves to the root window so the
        arrow-key shortcuts immediately act on BPM again.

        Guarded against reentrancy (WR-01): moving focus below triggers a
        synchronous <FocusOut> on the Entry, which is also bound to this
        method with force=False -- without the guard, a single Enter
        keypress would invoke controller.apply_entry() twice.
        """
        if self._committing:
            return None
        self._committing = True
        try:
            self.controller.apply_entry(self.entry_var.get(), force=force)
            if force:
                self.root.focus_set()
                return "break"
            return None
        finally:
            self._committing = False

    def handle_nudge_key(self, delta: int) -> str:
        """Arrow-key shortcut handler (D-11): nudge by delta, suppress default."""
        self.controller.nudge(delta)
        return "break"
