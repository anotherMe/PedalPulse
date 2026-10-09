"""Tk widgets for the PedalPulse control app (GUI-01, D-06, D-12).

No OSC import here (D-24) -- this module only builds and wires Tk widgets
to a BpmController; it never talks to the network directly.
"""

from __future__ import annotations

import tkinter as tk

import config
from bpm_logic import BpmController

# D-06 layout: −5 −1 [value] +1 +5. The minus sign is U+2212 MINUS SIGN,
# not an ASCII hyphen.
NUDGE_LABELS = {-5: "−5", -1: "−1", 1: "+1", 5: "+5"}


class BpmWindow:
    """Compact window: BPM slider, nudge row, status line, On top toggle."""

    def __init__(self, root: tk.Tk, controller: BpmController, status_text: str) -> None:
        self.root = root
        self.controller = controller

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

        self.value_label = tk.Label(
            self.nudge_row,
            textvariable=self.bpm_var,
            font=("TkDefaultFont", 16, "bold"),
            width=4,
        )
        self.value_label.pack(side="left", padx=8)

        for delta in (1, 5):
            button = tk.Button(
                self.nudge_row,
                text=NUDGE_LABELS[delta],
                takefocus=0,
                command=lambda d=delta: controller.nudge(d),
            )
            button.pack(side="left", padx=4)
            self.nudge_buttons[delta] = button

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

        controller.add_listener(self._on_bpm_changed)

    def _toggle_on_top(self) -> None:
        self.root.attributes("-topmost", self.on_top_var.get())

    def _on_bpm_changed(self, new_value: int) -> None:
        self.bpm_var.set(new_value)
