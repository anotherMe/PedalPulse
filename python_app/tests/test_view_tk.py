"""Tk 9 widget smoke test for python_app/view.py (D-02, GUI-01).

Runs under the real project venv's Tk 9.0.3 build with REAL Scale/Entry/
Button widgets and a REAL root.after/root.after_cancel scheduler -- only
the OSC send is faked, by passing BpmController(send=sent.append, ...).
This is the one layer Plan 02/03's pure-logic tests cannot exercise: does
the actual widget wiring (textvariable, command=, bind()) behave the way
bpm_logic.py's contract assumes under this project's real Tk build.
"""

from __future__ import annotations

import time
import tkinter as tk
import tkinter.font as tkfont
import types

import pytest

import config
from bpm_logic import BpmController, EpicController, PlayController
from view import BpmWindow


def pump(root: tk.Tk, ms: int) -> None:
    """Drive the real Tk event loop for at least `ms` milliseconds.

    Repeatedly calls root.update() with short sleeps so scheduled
    root.after() callbacks (the controller's debounce) actually fire --
    the same mechanic a running mainloop provides, without blocking the
    test on mainloop() itself.
    """
    deadline = time.monotonic() + ms / 1000.0
    while time.monotonic() < deadline:
        root.update()
        time.sleep(0.01)
    root.update()


@pytest.fixture
def tk_root():
    # No try/except here: if Tk cannot initialise, this fixture setup
    # must FAIL the test, never silently skip it.
    #
    # NOTE (D-02 finding): under this project's real Tk 9.0.3 build, a
    # withdrawn (unmapped) window suppresses the Scale widget's -command
    # callback even on a programmatic .set() -- empirically confirmed
    # (scale.set() on a withdrawn root never invokes -command; the exact
    # same call on an off-screen-but-mapped root does). Positioning the
    # window off-screen keeps it mapped -- so Scale/Entry/Button commands
    # behave exactly as they do in the real running app -- while staying
    # invisible during an automated test run.
    root = tk.Tk()
    root.geometry("+2000+2000")
    yield root
    # A second (or later) Tk() instance created later in the same pytest
    # process hung inside root.update() the first time it packed a widget,
    # under this build -- empirically traced to teardown, not setup: a
    # final root.update() here (flushing any pending Tk event before
    # destroy()) made every subsequent Tk() instantiation in this process
    # behave normally again.
    root.update()
    root.destroy()


def _build_all(root: tk.Tk, status_text: str = "Sending to test:1"):
    sent: list[float] = []
    controller = BpmController(send=sent.append, schedule=root.after, cancel=root.after_cancel)
    play_sent: list[int] = []
    play = PlayController(send=play_sent.append)
    epic_sent: list[float] = []
    epic = EpicController(send=epic_sent.append)
    window = BpmWindow(root, controller, status_text, play_controller=play, epic_controller=epic)
    return types.SimpleNamespace(
        window=window,
        controller=controller,
        sent=sent,
        play=play,
        play_sent=play_sent,
        epic=epic,
        epic_sent=epic_sent,
    )


def _build_window(root: tk.Tk, status_text: str):
    all_ = _build_all(root, status_text)
    return all_.window, all_.controller, all_.sent, all_.play, all_.play_sent


def _make_window(root: tk.Tk, status_text: str = "Sending to test:1"):
    window, controller, sent, _play, _play_sent = _build_window(root, status_text)
    return window, controller, sent


def _make_window_with_play(root: tk.Tk, status_text: str = "Sending to test:1"):
    window, _controller, _sent, play, play_sent = _build_window(root, status_text)
    return window, play, play_sent


# --- 1. Build -----------------------------------------------------------


def test_build_shows_initial_state(tk_root):
    window, _controller, _sent = _make_window(tk_root)

    assert tk_root.title() == "PedalPulse"
    assert float(window.scale["from"]) == 60
    assert float(window.scale["to"]) == 180
    assert window.entry_var.get() == "120"
    assert window.status_label["text"] == "Sending to test:1"
    assert window.on_top_var.get() is False


# --- 2. Slider: live update, release-only send --------------------------


def test_slider_live_update_then_release_sends(tk_root):
    window, controller, sent = _make_window(tk_root)

    window.scale.set(150)
    pump(tk_root, 20)
    assert controller.value == 150
    assert window.entry_var.get() == "150"
    assert sent == []

    window.scale.event_generate("<ButtonRelease-1>")
    pump(tk_root, 20)
    assert sent == [150.0]


# --- 3. Nudges: immediate display, debounced single send ---------------


def test_nudges_update_immediately_and_debounce_to_one_send(tk_root):
    window, controller, sent = _make_window(tk_root)

    for _ in range(3):
        window.nudge_buttons[1].invoke()

    assert window.entry_var.get() == "123"
    assert window.scale.get() == 123

    pump(tk_root, 50)
    assert sent == []

    pump(tk_root, 300)
    assert sent == [123.0]


# --- 4. Bounds: adjacency at 180 sends nothing --------------------------


def test_bounds_adjacency_at_upper_bound_sends_nothing(tk_root):
    window, controller, sent = _make_window(tk_root)

    window.entry_var.set("180")
    window.commit_entry(force=True)
    sent.clear()

    window.nudge_buttons[5].invoke()
    pump(tk_root, 300)

    assert sent == []
    assert controller.value == 180


# --- 5. Entry: commit, revert on invalid, unchanged focus-out -----------


def test_entry_commit_revert_and_unchanged_focusout(tk_root):
    window, _controller, sent = _make_window(tk_root)

    window.entry_var.set("150")
    window.commit_entry(force=True)
    assert sent == [150.0]

    window.entry_var.set("abc")
    window.commit_entry(force=True)
    assert window.entry_var.get() == "150"
    assert sent == [150.0]  # no new send from the revert

    window.commit_entry(force=False)
    assert sent == [150.0]  # unchanged value, unforced -> no new send


# --- 6. Ordering: an entry commit cancels a pending nudge send ---------


def test_entry_commit_cancels_pending_nudge_send(tk_root):
    window, controller, sent = _make_window(tk_root)

    window.nudge_buttons[1].invoke()
    window.entry_var.set("140")
    window.commit_entry(force=True)

    pump(tk_root, 300)

    assert sent == [140.0]
    assert controller.value == 140


# --- 7. Keys: bindings registered, handle_nudge_key works ---------------


def test_key_bindings_registered_and_handle_nudge_key_works(tk_root):
    window, controller, sent = _make_window(tk_root)

    for seq in ("<Up>", "<Down>", "<Shift-Up>", "<Shift-Down>"):
        assert tk_root.bind(seq) != ""
    for seq in ("<Return>", "<KP_Enter>", "<FocusOut>"):
        assert window.entry.bind(seq) != ""

    before = controller.value
    window.handle_nudge_key(5)
    pump(tk_root, 300)

    assert controller.value == before + 5
    assert sent == [float(before + 5)]


# --- 8. On top toggle -----------------------------------------------------


def test_on_top_toggle(tk_root):
    window, _controller, _sent = _make_window(tk_root)

    window.on_top_check.invoke()
    assert bool(tk_root.attributes("-topmost")) is True

    window.on_top_check.invoke()
    assert bool(tk_root.attributes("-topmost")) is False


# --- 9. Start/Stop button (GUI-02) ------------------------------------------


def test_play_button_toggles_with_one_send_per_click(tk_root):
    window, play, play_sent = _make_window_with_play(tk_root)

    assert window.play_button["text"] == "Stop"
    assert play_sent == []

    window.play_button.invoke()
    assert window.play_button["text"] == "Start"
    assert play_sent == [0]

    window.play_button.invoke()
    assert window.play_button["text"] == "Stop"
    assert play_sent == [0, 1]


def test_play_button_follows_controller_state(tk_root):
    window, play, play_sent = _make_window_with_play(tk_root)

    play.set_playing(False)
    assert window.play_button["text"] == "Start"
    assert play_sent == [0]

    play.set_playing(False)
    assert play_sent == [0]


def test_play_button_takes_no_focus(tk_root):
    window, controller, sent, play, _play_sent = _build_window(tk_root, "Sending to test:1")

    assert str(window.play_button["takefocus"]) == "0"

    window.play_button.invoke()

    before = controller.value
    window.handle_nudge_key(1)
    pump(tk_root, 300)

    assert controller.value == before + 1
    assert sent == [float(before + 1)]


# --- 10. Zone buttons (EPIC-03) and WR-01 arrow-key entry guard -------------


def test_zone_row_builds_in_order_with_recovery_selected(tk_root):
    all_ = _build_all(tk_root)
    window = all_.window

    assert list(window.zone_buttons) == list(config.EPIC_ZONES)
    assert list(window.zone_row.pack_slaves()) == [
        window.zone_buttons[name] for name in config.EPIC_ZONES
    ]
    for button in window.zone_buttons.values():
        assert str(button["takefocus"]) == "0"

    recovery = window.zone_buttons["Recovery"]
    recovery_weight = tkfont.Font(root=tk_root, font=recovery.cget("font")).actual("weight")
    assert recovery_weight == "bold"
    assert recovery["relief"] == "sunken"

    for name, button in window.zone_buttons.items():
        if name == "Recovery":
            continue
        weight = tkfont.Font(root=tk_root, font=button.cget("font")).actual("weight")
        assert weight == "normal"
        assert button["relief"] == "raised"

    assert window.zone_label["text"] == "Zone: Recovery"
    assert all_.epic_sent == []


def test_zone_click_highlights_and_sends_once(tk_root):
    all_ = _build_all(tk_root)
    window = all_.window

    window.zone_buttons["Tempo"].invoke()

    assert all_.epic_sent == [50.0]
    tempo_weight = tkfont.Font(root=tk_root, font=window.zone_buttons["Tempo"].cget("font")).actual(
        "weight"
    )
    assert tempo_weight == "bold"
    assert window.zone_buttons["Tempo"]["relief"] == "sunken"
    recovery_weight = tkfont.Font(
        root=tk_root, font=window.zone_buttons["Recovery"].cget("font")
    ).actual("weight")
    assert recovery_weight == "normal"
    assert window.zone_buttons["Recovery"]["relief"] == "raised"
    assert window.zone_label["text"] == "Zone: Tempo"

    window.zone_buttons["Tempo"].invoke()
    assert all_.epic_sent == [50.0]

    window.zone_buttons["VO2"].invoke()
    assert all_.epic_sent == [50.0, 100.0]


def test_each_zone_button_sends_its_preset(tk_root):
    all_ = _build_all(tk_root)
    window = all_.window

    for name in ("Endurance", "Tempo", "Threshold", "VO2"):
        window.zone_buttons[name].invoke()

    assert all_.epic_sent == [30.0, 50.0, 75.0, 100.0]


def test_arrow_keys_do_not_nudge_while_entry_focused(tk_root):
    all_ = _build_all(tk_root)
    window = all_.window
    controller = all_.controller
    sent = all_.sent

    window.entry.focus_force()
    pump(tk_root, 100)
    assert tk_root.focus_get() is window.entry

    window.entry_var.set("17")
    tk_root.event_generate("<Up>")
    tk_root.event_generate("<Shift-Down>")
    pump(tk_root, 300)

    assert controller.value == 120
    assert window.entry_var.get() == "17"
    assert sent == []

    # Positive control: move focus away from the entry (committing an
    # unchanged, unsent value) and confirm the same key now nudges BPM.
    window.entry_var.set("120")
    tk_root.focus_force()
    pump(tk_root, 100)
    tk_root.event_generate("<Up>")
    pump(tk_root, 300)

    assert controller.value == 121
    assert sent == [121.0]


def test_zone_click_keeps_arrow_shortcuts_on_bpm(tk_root):
    all_ = _build_all(tk_root)
    window = all_.window
    controller = all_.controller

    window.zone_buttons["Threshold"].invoke()
    tk_root.focus_force()
    pump(tk_root, 100)
    tk_root.event_generate("<Up>")
    pump(tk_root, 300)

    assert controller.value == 121
    assert all_.sent == [121.0]
    assert all_.epic_sent == [75.0]
