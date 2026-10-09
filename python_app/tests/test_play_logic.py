"""Tests for PlayController in python_app/bpm_logic.py (GUI-02 transport half)."""

from __future__ import annotations

import pytest

from bpm_logic import PlayController


def _make_controller(**overrides):
    sent = []
    kwargs = dict(send=sent.append)
    kwargs.update(overrides)
    controller = PlayController(**kwargs)
    return controller, sent


# --- construction -------------------------------------------------------


def test_default_initial_state_is_playing():
    controller, sent = _make_controller()
    assert controller.playing is True
    assert sent == []


def test_initial_false_starts_stopped():
    controller, sent = _make_controller(initial=False)
    assert controller.playing is False
    assert sent == []


# --- toggle ---------------------------------------------------------------


def test_toggle_from_playing_stops_and_sends_zero_notifying_listeners():
    controller, sent = _make_controller()
    notified = []
    controller.add_listener(notified.append)

    controller.toggle()

    assert controller.playing is False
    assert sent == [0]
    assert notified == [False]


def test_toggle_twice_from_playing_sends_zero_then_one_with_no_debounce():
    controller, sent = _make_controller()

    controller.toggle()
    controller.toggle()

    assert sent == [0, 1]
    assert controller.playing is True


# --- set_playing idempotency ------------------------------------------------


def test_set_playing_same_state_sends_nothing_and_notifies_no_listener():
    controller, sent = _make_controller()
    notified = []
    controller.add_listener(notified.append)

    controller.set_playing(True)

    assert sent == []
    assert notified == []
    assert controller.playing is True


def test_set_playing_false_twice_sends_only_once():
    controller, sent = _make_controller()

    controller.set_playing(False)
    controller.set_playing(False)

    assert sent == [0]
    assert controller.playing is False


def test_set_playing_coerces_falsy_int_to_bool():
    controller, sent = _make_controller()

    controller.set_playing(0)

    assert controller.playing is False
    assert sent == [0]


# --- send value type --------------------------------------------------------


def test_send_value_is_always_a_real_int_never_a_bool():
    controller, sent = _make_controller()

    controller.toggle()
    controller.toggle()

    assert all(type(value) is int for value in sent)


# --- ordering: listeners before send ----------------------------------------


def test_listeners_notified_before_send_on_change():
    controller, _sent = _make_controller()
    events: list[tuple[str, object]] = []
    controller.add_listener(lambda playing: events.append(("listener", playing)))
    controller._send = lambda value: events.append(("send", value))  # type: ignore[method-assign]

    controller.toggle()

    assert events == [("listener", False), ("send", 0)]


# --- send_initial ------------------------------------------------------------


def test_send_initial_sends_current_state_unconditionally_default_playing():
    controller, sent = _make_controller()

    controller.send_initial()

    assert sent == [1]


def test_send_initial_sends_current_state_unconditionally_when_stopped():
    controller, sent = _make_controller(initial=False)

    controller.send_initial()

    assert sent == [0]


def test_send_initial_called_twice_sends_twice_and_notifies_no_listener():
    controller, sent = _make_controller()
    notified = []
    controller.add_listener(notified.append)

    controller.send_initial()
    controller.send_initial()

    assert sent == [1, 1]
    assert notified == []


# --- fire-and-forget send (no rollback on falsy return) ---------------------


def test_send_returning_false_does_not_roll_back_state():
    controller, _sent = _make_controller(send=lambda value: False)

    controller.toggle()

    assert controller.playing is False
