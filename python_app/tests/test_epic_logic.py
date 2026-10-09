"""Tests for EpicController and the zone preset map (EPIC-03)."""

from __future__ import annotations

import pytest

import config
from bpm_logic import EpicController


def _make_controller(**overrides):
    sent = []
    kwargs = dict(send=sent.append)
    kwargs.update(overrides)
    controller = EpicController(**kwargs)
    return controller, sent


# --- zone map -------------------------------------------------------------


def test_zone_map_has_expected_names_and_values():
    assert config.EPIC_ZONES == {
        "Recovery": 10,
        "Endurance": 30,
        "Tempo": 50,
        "Threshold": 75,
        "VO2": 100,
    }
    assert list(config.EPIC_ZONES) == ["Recovery", "Endurance", "Tempo", "Threshold", "VO2"]
    assert config.EPIC_DEFAULT_ZONE == "Recovery"


def test_zone_values_strictly_increasing_within_0_100_vo2_is_100():
    values = list(config.EPIC_ZONES.values())
    assert all(0 <= v <= 100 for v in values)
    assert values == sorted(set(values))
    assert len(values) == len(set(values))
    assert values[0] == 10
    assert values[-1] == 100


# --- construction -----------------------------------------------------------


def test_default_construction_starts_at_recovery_and_sends_nothing():
    controller, sent = _make_controller()

    assert controller.zone == "Recovery"
    assert controller.value == 10.0
    assert controller.zone_names == ("Recovery", "Endurance", "Tempo", "Threshold", "VO2")
    assert sent == []


# --- select_zone: real changes ----------------------------------------------


def test_select_zone_in_turn_sends_each_preset_as_float():
    controller, sent = _make_controller()

    for name in ("Endurance", "Tempo", "Threshold", "VO2"):
        controller.select_zone(name)

    assert sent == [30.0, 50.0, 75.0, 100.0]
    assert all(type(v) is float for v in sent)


def test_select_zone_same_zone_is_a_noop():
    controller, sent = _make_controller()
    notified = []
    controller.add_listener(notified.append)

    controller.select_zone("Recovery")

    assert sent == []
    assert notified == []
    assert controller.zone == "Recovery"


def test_select_zone_twice_sends_once():
    controller, sent = _make_controller()

    controller.select_zone("Tempo")
    controller.select_zone("Tempo")

    assert sent == [50.0]


def test_recovery_endurance_recovery_sends_exactly_two_values():
    controller, sent = _make_controller()

    controller.select_zone("Endurance")
    controller.select_zone("Recovery")

    assert sent == [30.0, 10.0]


# --- ordering: listeners before send ----------------------------------------


def test_listener_called_before_send_on_change():
    controller, _sent = _make_controller()
    events: list[tuple[str, object]] = []
    controller.add_listener(lambda zone: events.append(("listener", zone)))
    controller._send = lambda value: events.append(("send", value))  # type: ignore[method-assign]

    controller.select_zone("Tempo")

    assert events == [("listener", "Tempo"), ("send", 50.0)]


# --- invalid zone names ------------------------------------------------------


def test_select_zone_unknown_name_raises_value_error_and_leaves_state_untouched():
    controller, sent = _make_controller()
    notified = []
    controller.add_listener(notified.append)

    with pytest.raises(ValueError):
        controller.select_zone("Sprint")

    assert controller.zone == "Recovery"
    assert sent == []
    assert notified == []


def test_select_zone_empty_name_raises_value_error_and_leaves_state_untouched():
    controller, sent = _make_controller()
    notified = []
    controller.add_listener(notified.append)

    with pytest.raises(ValueError):
        controller.select_zone("")

    assert controller.zone == "Recovery"
    assert sent == []
    assert notified == []


def test_construction_with_empty_zone_map_raises_value_error():
    with pytest.raises(ValueError):
        EpicController(send=lambda v: None, zones={})


def test_construction_with_initial_zone_missing_from_map_raises_value_error():
    with pytest.raises(ValueError):
        EpicController(send=lambda v: None, initial_zone="Sprint")


# --- send_initial -------------------------------------------------------------


def test_send_initial_sends_current_zone_value_without_notifying():
    controller, sent = _make_controller()
    notified = []
    controller.add_listener(notified.append)

    controller.send_initial()

    assert sent == [10.0]
    assert notified == []


def test_send_initial_called_twice_sends_twice_unconditionally():
    controller, sent = _make_controller()

    controller.send_initial()
    controller.send_initial()

    assert sent == [10.0, 10.0]


# --- fire-and-forget send (no rollback on falsy return) ----------------------


def test_send_returning_false_does_not_roll_back_zone():
    controller, _sent = _make_controller(send=lambda value: False)

    controller.select_zone("Tempo")

    assert controller.zone == "Tempo"


# --- injected zone map --------------------------------------------------------


def test_injected_zone_map_works():
    controller, sent = _make_controller(zones={"Low": 0, "High": 100}, initial_zone="Low")

    controller.select_zone("High")

    assert sent == [100.0]
