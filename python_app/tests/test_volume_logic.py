"""Tests for the master-volume half of python_app/bpm_logic.py (GUI-03).

clamp_volume mirrors clamp_bpm's half-up-then-clamp contract; VolumeController
mirrors BpmController's slider half (live drag, send-once-on-release). No
Tk import here -- this module stays unit-testable without a display.
"""

from __future__ import annotations

import pytest

import config
from bpm_logic import VolumeController, clamp_volume


# --- clamp_volume ------------------------------------------------------


@pytest.mark.parametrize(
    "value,expected",
    [
        (80, 80),
        (49.5, 50),  # half up
        (49.4, 49),
        (0.5, 1),
        (0.49, 0),
        (-3, 0),
        (100.4, 100),
        (100.5, 100),
        (150, 100),
    ],
)
def test_clamp_volume_values(value, expected):
    result = clamp_volume(value)
    assert result == expected
    assert type(result) is int


@pytest.mark.parametrize("value", [float("nan"), float("inf"), float("-inf")])
def test_clamp_volume_rejects_non_finite(value):
    with pytest.raises(ValueError):
        clamp_volume(value)


# --- config constants ---------------------------------------------------


def test_volume_config_constants():
    assert config.VOLUME_MIN == 0
    assert config.VOLUME_MAX == 100
    assert config.VOLUME_DEFAULT == 80
    assert config.VOLUME_MIN < config.VOLUME_DEFAULT < config.VOLUME_MAX


# --- VolumeController basics ---------------------------------------------


def test_controller_starts_at_80_and_sends_nothing_on_construction():
    sent = []
    controller = VolumeController(send=sent.append)
    assert controller.value == 80
    assert sent == []


def test_controller_clamps_initial_value():
    sent = []
    controller = VolumeController(send=sent.append, initial=150)
    assert controller.value == 100
    assert sent == []


def test_slider_moved_sets_notifies_and_never_sends():
    sent = []
    controller = VolumeController(send=sent.append)
    notified = []
    controller.add_listener(notified.append)

    controller.slider_moved("55")

    assert controller.value == 55
    assert notified == [55]
    assert sent == []


def test_slider_moved_unchanged_value_does_not_notify():
    sent = []
    controller = VolumeController(send=sent.append)
    notified = []
    controller.add_listener(notified.append)

    controller.slider_moved(80)  # same as default initial

    assert notified == []
    assert sent == []


def test_slider_moved_rounds_half_up():
    sent = []
    controller = VolumeController(send=sent.append)

    controller.slider_moved("55.6")

    assert controller.value == 56


def test_slider_moved_clamps_above_max():
    sent = []
    controller = VolumeController(send=sent.append)

    controller.slider_moved("120")

    assert controller.value == 100


def test_slider_released_sends_float_value():
    sent = []
    controller = VolumeController(send=sent.append)

    controller.slider_moved("55")
    controller.slider_released()

    assert sent == [55.0]
    assert type(sent[0]) is float


def test_slider_released_sends_even_when_unchanged():
    sent = []
    controller = VolumeController(send=sent.append)

    controller.slider_released()
    controller.slider_released()

    assert sent == [80.0, 80.0]


def test_several_drag_ticks_then_one_release_sends_exactly_once():
    sent = []
    controller = VolumeController(send=sent.append)

    for raw in ("10", "20", "30"):
        controller.slider_moved(raw)
    controller.slider_released()

    assert sent == [30.0]


def test_send_initial_sends_without_notifying():
    sent = []
    controller = VolumeController(send=sent.append)
    notified = []
    controller.add_listener(notified.append)

    controller.send_initial()

    assert sent == [80.0]
    assert notified == []

    controller.send_initial()
    assert sent == [80.0, 80.0]


def test_send_returning_false_does_not_change_value():
    controller = VolumeController(send=lambda _v: False)

    controller.slider_moved("55")

    assert controller.value == 55  # slider_moved itself still sets the value

    controller2 = VolumeController(send=lambda _v: False)
    controller2.slider_released()
    assert controller2.value == 80  # a falsy send return never rolls back the value
