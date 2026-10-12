"""Tk widgets for the PedalPulse control app (GUI-01, GUI-02, GUI-03,
GUI-05, GUI-07, EPIC-03, D-06, D-12).

No OSC import here (D-24) -- this module only builds and wires Tk widgets
to a BpmController/PlayController/EpicController/VolumeController and to
the LibrarySelectors behind the Palette/Progression/Melody dropdown column;
it never talks to the network directly.
"""

from __future__ import annotations

import tkinter as tk
import tkinter.font as tkfont
from collections.abc import Sequence

import config
from bpm_logic import BpmController, EpicController, PlayController, VolumeController
from library_logic import LibrarySelector

# D-06 layout: −5 −1 [value] +1 +5. The minus sign is U+2212 MINUS SIGN,
# not an ASCII hyphen.
NUDGE_LABELS = {-5: "−5", -1: "−1", 1: "+1", 5: "+5"}

# GUI-02: the button's label always names the action a click will perform.
PLAY_LABELS = {True: "Stop", False: "Start"}


class BpmWindow:
    """Compact window: BPM slider, nudge row, zone row, transport row,
    volume row, status line, On top toggle, and to their right a column of
    library dropdowns (Palette, Progression, Melody)."""

    def __init__(
        self,
        root: tk.Tk,
        controller: BpmController,
        status_text: str,
        *,
        play_controller: PlayController,
        epic_controller: EpicController,
        volume_controller: VolumeController,
        selector_controllers: Sequence[LibrarySelector],
    ) -> None:
        self.root = root
        self.controller = controller
        self.play_controller = play_controller
        self.epic_controller = epic_controller
        self.volume_controller = volume_controller
        self.selector_controllers = list(selector_controllers)

        root.title("PedalPulse")
        root.resizable(False, False)

        container = tk.Frame(root, padx=12, pady=10)
        container.pack(side="left", anchor="n")

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

        # WR-01 (Phase 1 review): the entry gets its own bindings for the
        # four arrow sequences, returning "break" and doing nothing else.
        # Tk delivers key events to the focus widget and runs the entry's
        # own binding before the root-level nudge binding below, so arrow
        # keys typed into the entry neither nudge BPM nor overwrite the
        # typed text.
        self.entry.bind("<Up>", lambda _event: "break")
        self.entry.bind("<Down>", lambda _event: "break")
        self.entry.bind("<Shift-Up>", lambda _event: "break")
        self.entry.bind("<Shift-Down>", lambda _event: "break")

        for delta in (1, 5):
            button = tk.Button(
                self.nudge_row,
                text=NUDGE_LABELS[delta],
                takefocus=0,
                command=lambda d=delta: controller.nudge(d),
            )
            button.pack(side="left", padx=4)
            self.nudge_buttons[delta] = button

        self._build_zone_row(container, epic_controller)

        self.transport_row = tk.Frame(container, pady=8)
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

        self._build_volume_row(container, volume_controller)

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

        self._build_library_column(self.selector_controllers)

        # D-11: Up/Down +-1, Shift+Up/Down +-5, while keyboard focus is
        # anywhere except the BPM entry (WR-01 fix above gives the entry
        # its own "break" bindings so these root-level shortcuts never
        # fire while the rider is typing). Bound on root (not the Scale,
        # which keeps takefocus=0) so the shortcuts fire for every other
        # widget in the window, including right after a zone click (zone
        # buttons take no focus). Held keys auto-repeat into nudge(); the
        # controller's debounce coalesces them.
        self.root.bind("<Up>", lambda _event: self.handle_nudge_key(1))
        self.root.bind("<Down>", lambda _event: self.handle_nudge_key(-1))
        self.root.bind("<Shift-Up>", lambda _event: self.handle_nudge_key(5))
        self.root.bind("<Shift-Down>", lambda _event: self.handle_nudge_key(-5))

        controller.add_listener(self._on_bpm_changed)

    def _build_library_column(self, selectors: Sequence[LibrarySelector]) -> None:
        """Build the right-hand column of library dropdowns (GUI-05, D-01..D-03).

        One label and one tk.OptionMenu per selector, top to bottom in the
        given order. Tuple padding goes into pack() only; a widget
        constructor rejects it. takefocus=0 is set explicitly (GUI-07) so
        the root arrow-key shortcuts stay on BPM.

        The list is rebuilt in each menu's post command (D-08), which a
        real click reaches on aqua through tk::MbPost; there is no
        watcher, timer or thread. The real click is checked by hand in
        the end-of-phase UAT (RESEARCH A1, A3).
        """
        self.library_column = tk.Frame(self.root, pady=10)
        self.library_column.pack(side="left", anchor="n", padx=(0, 12))

        self.library_labels: dict[str, tk.Label] = {}
        self.library_vars: dict[str, tk.StringVar] = {}
        self.library_buttons: dict[str, tk.Menubutton] = {}
        self.library_menus: dict[str, tk.Menu] = {}
        for selector in selectors:
            label = tk.Label(self.library_column, text=selector.title, anchor="w")
            label.pack(fill="x", pady=(0, 2))

            var = tk.StringVar(value=selector.selected)
            button = tk.OptionMenu(self.library_column, var, selector.selected)
            button.configure(width=config.LIBRARY_DROPDOWN_WIDTH, anchor="w", takefocus=0)
            button.pack(fill="x", pady=(0, 10))
            menu = button["menu"]
            # D-08: rebuild this menu's list every time it opens. Default
            # arguments capture this iteration's selector, var and menu
            # (a plain closure would see only the last category).
            menu.configure(
                postcommand=lambda s=selector, v=var, m=menu: self._refresh_library_menu(s, v, m)
            )

            selector.add_listener(var.set)
            self._refresh_library_menu(selector, var, menu)

            self.library_labels[selector.title] = label
            self.library_vars[selector.title] = var
            self.library_buttons[selector.title] = button
            self.library_menus[selector.title] = menu

    def _refresh_library_menu(self, selector: LibrarySelector, var: tk.StringVar, menu: tk.Menu) -> None:
        """Rebuild the menu entries from the selector's folder (idempotent).

        Entry labels are the exact file stems (D-06); a pick calls
        selector.select(n). It never sets var itself: the selector's
        listener does that only when the choice really changed, so a
        selected name whose file was deleted stays shown on the button
        (GUI-06). The post command runs twice per open on this Tk, hence
        delete-then-add. It only calls selector.options() (never raises)
        and Tk menu methods, so the menu always posts.
        """
        menu.delete(0, "end")
        for name in selector.options():
            menu.add_radiobutton(
                label=name,
                variable=var,
                value=name,
                command=lambda n=name: selector.select(n),
            )

    def _build_zone_row(self, container: tk.Frame, epic_controller: EpicController) -> None:
        """Build the five EPIC zone buttons and the "Zone: <name>" caption (EPIC-03).

        Selected-zone highlight uses a bold font copy plus the caption,
        not relief alone -- this Mac's Tk 9.0.3 (aqua) largely ignores
        relief on native buttons (confirmed during planning), so relief is
        set too but the font + caption are what actually render the
        selection on this theme.
        """
        self.zone_font = tkfont.nametofont("TkDefaultFont").copy()
        self.zone_font_selected = tkfont.nametofont("TkDefaultFont").copy()
        self.zone_font_selected.configure(weight="bold")

        self.zone_row = tk.Frame(container, pady=8)
        self.zone_row.pack()

        self.zone_buttons: dict[str, tk.Button] = {}
        for name in epic_controller.zone_names:
            button = tk.Button(
                self.zone_row,
                text=name,
                takefocus=0,
                font=self.zone_font,
                command=lambda z=name: epic_controller.select_zone(z),
            )
            button.pack(side="left", padx=2)
            self.zone_buttons[name] = button

        self.zone_label = tk.Label(container)
        self.zone_label.pack()

        epic_controller.add_listener(self._on_zone_changed)
        self._on_zone_changed(epic_controller.zone)

    def _on_zone_changed(self, zone: str) -> None:
        for name, button in self.zone_buttons.items():
            if name == zone:
                button.configure(font=self.zone_font_selected, relief="sunken")
            else:
                button.configure(font=self.zone_font, relief="raised")
        self.zone_label["text"] = f"Zone: {zone}"

    def _build_volume_row(self, container: tk.Frame, volume_controller: VolumeController) -> None:
        """Build the master volume Scale (GUI-03).

        takefocus=0 keeps the root arrow-key shortcuts on BPM, and Scale's
        own arrow-key bindings could otherwise change the volume without a
        release send (same reasoning as the BPM Scale). There are no
        nudge buttons and no entry for volume -- GUI-03 asks only to
        adjust master volume from a slider.
        """
        self.volume_row = tk.Frame(container, pady=8)
        self.volume_row.pack()

        self.volume_var = tk.IntVar(value=volume_controller.value)

        self.volume_scale = tk.Scale(
            self.volume_row,
            from_=config.VOLUME_MIN,
            to=config.VOLUME_MAX,
            orient="horizontal",
            resolution=1,
            length=320,
            label="Volume",
            variable=self.volume_var,
            command=volume_controller.slider_moved,
            takefocus=0,
        )
        self.volume_scale.pack(fill="x")
        self.volume_scale.bind(
            "<ButtonRelease-1>", lambda _event: volume_controller.slider_released()
        )

        volume_controller.add_listener(self._on_volume_changed)

    def _on_volume_changed(self, value: int) -> None:
        self.volume_var.set(value)

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
