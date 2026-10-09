"""Tests for python_app/bpm_logic.py (GUI-01 slider/nudge half, LINK-01 send discipline)."""

from __future__ import annotations

import math

import pytest

import config
from bpm_logic import BpmController, Debouncer, clamp_bpm


class FakeScheduler:
    """Deterministic stand-in for Tk's root.after / root.after_cancel."""

    def __init__(self) -> None:
        self.current_time = 0
        self._next_id = 0
        self._pending: dict[int, tuple[int, object]] = {}

    def schedule(self, delay_ms, fn):
        self._next_id += 1
        token = self._next_id
        self._pending[token] = (self.current_time + delay_ms, fn)
        return token

    def cancel(self, token):
        self._pending.pop(token, None)

    def advance(self, ms):
        self.current_time += ms
        due_tokens = sorted(
            (token for token, (due_time, _fn) in self._pending.items() if due_time <= self.current_time),
            key=lambda token: self._pending[token][0],
        )
        for token in due_tokens:
            entry = self._pending.pop(token, None)
            if entry is not None:
                entry[1]()


# --- clamp_bpm -------------------------------------------------------------


@pytest.mark.parametrize(
    "value,expected",
    [
        (120, 120),
        (150.5, 151),  # half up
        (150.4, 150),
        (300, 180),
        (-5, 60),
        (59.5, 60),
    ],
)
def test_clamp_bpm_values(value, expected):
    assert clamp_bpm(value) == expected


@pytest.mark.parametrize("value", [float("nan"), float("inf"), float("-inf")])
def test_clamp_bpm_rejects_non_finite(value):
    with pytest.raises(ValueError):
        clamp_bpm(value)


# --- BpmController basics ---------------------------------------------------


def _make_controller(**overrides):
    sent = []
    scheduler = FakeScheduler()
    kwargs = dict(
        send=lambda bpm: sent.append(bpm),
        schedule=scheduler.schedule,
        cancel=scheduler.cancel,
    )
    kwargs.update(overrides)
    controller = BpmController(**kwargs)
    return controller, sent, scheduler


def test_controller_starts_at_120_and_sends_nothing_on_construction():
    controller, sent, _scheduler = _make_controller()
    assert controller.value == config.BPM_DEFAULT
    assert sent == []


def test_send_initial_sends_once():
    controller, sent, _scheduler = _make_controller()
    controller.send_initial()
    assert sent == [120.0]


def test_slider_moved_notifies_and_sends_nothing_then_release_sends_final():
    controller, sent, _scheduler = _make_controller()
    notified = []
    controller.add_listener(notified.append)

    for raw in ("121", "130", "150", "170"):
        controller.slider_moved(raw)

    assert notified == [121, 130, 150, 170]
    assert sent == []

    controller.slider_released()
    assert sent == [170.0]


def test_slider_moved_unchanged_value_does_not_notify():
    controller, _sent, _scheduler = _make_controller()
    notified = []
    controller.add_listener(notified.append)

    controller.slider_moved("120")  # same as initial

    assert notified == []


def test_two_releases_with_no_change_send_two_messages():
    controller, sent, _scheduler = _make_controller()

    controller.slider_released()
    controller.slider_released()

    assert sent == [120.0, 120.0]


# --- nudge + debounce -------------------------------------------------------


def test_nudge_three_times_updates_immediately_and_sends_once_after_window():
    controller, sent, scheduler = _make_controller()
    notified = []
    controller.add_listener(notified.append)

    controller.nudge(1)
    assert notified == [121]
    assert sent == []

    scheduler.advance(50)
    controller.nudge(1)
    assert notified == [121, 122]
    assert sent == []

    scheduler.advance(50)
    controller.nudge(1)
    assert notified == [121, 122, 123]
    assert sent == []

    # Still within the 150ms window since the last nudge.
    scheduler.advance(149)
    assert sent == []

    scheduler.advance(1)
    assert sent == [123.0]


def test_nudge_up_then_down_within_window_sends_one_net_value():
    controller, sent, scheduler = _make_controller()

    controller.nudge(1)
    controller.nudge(-1)
    assert controller.value == 120

    scheduler.advance(config.NUDGE_DEBOUNCE_MS)
    assert sent == [120.0]


def test_nudge_at_upper_bound_adjacency():
    controller, sent, scheduler = _make_controller(initial=178)
    notified = []
    controller.add_listener(notified.append)

    controller.nudge(5)
    assert controller.value == 180
    assert notified == [180]
    scheduler.advance(config.NUDGE_DEBOUNCE_MS)
    assert sent == [180.0]

    notified.clear()
    sent.clear()

    controller.nudge(1)
    controller.nudge(5)
    assert notified == []
    assert controller._debouncer.pending is False
    scheduler.advance(config.NUDGE_DEBOUNCE_MS)
    assert sent == []


def test_nudge_at_lower_bound_adjacency():
    controller, sent, scheduler = _make_controller(initial=60)
    notified = []
    controller.add_listener(notified.append)

    controller.nudge(-1)
    controller.nudge(-5)
    assert notified == []
    assert controller._debouncer.pending is False
    scheduler.advance(config.NUDGE_DEBOUNCE_MS)
    assert sent == []


def test_slider_release_before_debounce_window_cancels_pending_nudge_send():
    controller, sent, scheduler = _make_controller()

    controller.nudge(1)
    controller.slider_released()
    assert sent == [121.0]

    scheduler.advance(200)
    assert sent == [121.0]  # nothing more sent


# --- Debouncer in isolation --------------------------------------------------


def test_debouncer_pending_flag():
    scheduler = FakeScheduler()
    debouncer = Debouncer(scheduler.schedule, scheduler.cancel, delay_ms=150)
    assert debouncer.pending is False

    calls = []
    debouncer.trigger(lambda: calls.append(1))
    assert debouncer.pending is True

    scheduler.advance(150)
    assert calls == [1]
    assert debouncer.pending is False


def test_debouncer_cancel_prevents_fire():
    scheduler = FakeScheduler()
    debouncer = Debouncer(scheduler.schedule, scheduler.cancel, delay_ms=150)
    calls = []
    debouncer.trigger(lambda: calls.append(1))
    debouncer.cancel()
    scheduler.advance(150)
    assert calls == []
    assert debouncer.pending is False
