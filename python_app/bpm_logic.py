"""Pure BPM, transport (play/stop) and EPIC zone state + send policy for the
PedalPulse control app (GUI-01, GUI-02, EPIC-03, LINK-01).

No tkinter import -- this module stays unit-testable without a display and
is driven by injected schedule/cancel callables (Tk's root.after /
root.after_cancel in the app, a fake scheduler in tests).
"""

from __future__ import annotations

import math
from typing import Callable, Mapping

import config


def clamp_bpm(value: float) -> int:
    """Round half up to the nearest int, then clamp to [BPM_MIN, BPM_MAX].

    Raises ValueError if value is not finite (NaN or +/-inf). Python's
    built-in round() is half-to-even, so this uses an explicit
    floor(value + 0.5) contract for half-up rounding.
    """
    if not math.isfinite(value):
        raise ValueError(f"clamp_bpm: value must be finite, got {value!r}")
    rounded = int(math.floor(value + 0.5))
    return max(config.BPM_MIN, min(config.BPM_MAX, rounded))


def parse_bpm_entry(text: str) -> int | None:
    """Parse a user-typed BPM string (D-09, D-10).

    Returns None for empty/whitespace-only, non-numeric, or non-finite
    (nan/inf) text. Otherwise returns clamp_bpm(float(text)) -- the same
    half-up rounding and 60..180 snapping used by the slider, so entry
    and slider follow one shared rule.
    """
    stripped = text.strip()
    if not stripped:
        return None
    try:
        value = float(stripped)
    except ValueError:
        return None
    if not math.isfinite(value):
        return None
    return clamp_bpm(value)


class Debouncer:
    """Cancel-and-reschedule debounce wrapper around injected schedule/cancel."""

    def __init__(
        self,
        schedule: Callable[[int, Callable[[], None]], object],
        cancel: Callable[[object], None],
        delay_ms: int,
    ) -> None:
        self._schedule = schedule
        self._cancel = cancel
        self._delay_ms = delay_ms
        self._pending_token: object | None = None

    def trigger(self, fn: Callable[[], None]) -> None:
        """Cancel any pending call, then schedule fn after delay_ms."""
        self.cancel()

        def _fire() -> None:
            self._pending_token = None
            fn()

        self._pending_token = self._schedule(self._delay_ms, _fire)

    def cancel(self) -> None:
        if self._pending_token is not None:
            self._cancel(self._pending_token)
            self._pending_token = None

    @property
    def pending(self) -> bool:
        return self._pending_token is not None


class BpmController:
    """Tracks the current BPM value and decides when to send it over OSC."""

    def __init__(
        self,
        send: Callable[[float], object],
        schedule: Callable[[int, Callable[[], None]], object],
        cancel: Callable[[object], None],
        initial: int = config.BPM_DEFAULT,
        debounce_ms: int = config.NUDGE_DEBOUNCE_MS,
    ) -> None:
        self._send = send
        self._value = clamp_bpm(initial)
        self._listeners: list[Callable[[int], None]] = []
        self._debouncer = Debouncer(schedule, cancel, debounce_ms)

    @property
    def value(self) -> int:
        return self._value

    def add_listener(self, fn: Callable[[int], None]) -> None:
        self._listeners.append(fn)

    def _notify(self) -> None:
        """Call every listener with the current value (no change required)."""
        for listener in self._listeners:
            listener(self._value)

    def _set(self, new_value: int) -> bool:
        """Update the value and notify listeners only on an actual change."""
        if new_value == self._value:
            return False
        self._value = new_value
        self._notify()
        return True

    def _send_now(self) -> None:
        self._debouncer.cancel()
        self._send(float(self._value))

    def slider_moved(self, raw: str | float) -> None:
        """Live update while dragging. Never sends (D-20)."""
        new_value = clamp_bpm(float(raw))
        self._set(new_value)

    def slider_released(self) -> None:
        """Send the current value now, cancelling any pending debounce (D-20)."""
        self._send_now()

    def nudge(self, delta: int) -> None:
        """Change the value by delta; debounce-send only if it actually changed (D-21)."""
        new_value = clamp_bpm(self._value + delta)
        if self._set(new_value):
            self._debouncer.trigger(self._send_now)

    def apply_entry(self, text: str, *, force: bool) -> bool:
        """Commit a typed entry value (D-10, D-21).

        Invalid text (parse_bpm_entry returns None) reverts: listeners are
        notified with the CURRENT value (so the view's entry text snaps
        back), nothing is sent, and this returns False.

        Valid text always updates/clamps the value. A commit sends now
        (which also cancels any pending debounced nudge send -- the
        ordering guarantee) when the value actually changed, or when
        force=True (Enter always commits, even at an unchanged value).
        An unforced, unchanged commit (focus-out) only re-notifies so the
        displayed text normalises (e.g. "150.0" -> "150"), without a send.
        """
        parsed = parse_bpm_entry(text)
        if parsed is None:
            self._notify()
            return False

        changed = self._set(parsed)
        if force or changed:
            self._send_now()
        if not changed:
            self._notify()
        return True

    def send_initial(self) -> None:
        """Send the current value once, unconditionally (D-23)."""
        self._send_now()


class PlayController:
    """Tracks play/stop intent and decides when to send /pp/play (GUI-02).

    Mirrors BpmController._set/_notify's shape: track value, notify
    listeners on an actual change, let the caller (toggle/set_playing)
    decide send timing. Unlike BpmController there is no debounce --
    every discrete click is one send.
    """

    def __init__(
        self,
        send: Callable[[int], object],
        initial: bool = True,
    ) -> None:
        self._send = send
        self._playing = bool(initial)
        self._listeners: list[Callable[[bool], None]] = []

    @property
    def playing(self) -> bool:
        return self._playing

    def add_listener(self, fn: Callable[[bool], None]) -> None:
        self._listeners.append(fn)

    def _notify(self) -> None:
        for listener in self._listeners:
            listener(self._playing)

    def set_playing(self, playing: bool) -> None:
        """Update playing state; notify and send only on an actual change.

        Listeners are called (if the state changed) before send -- send is
        fire-and-forget (its return value is ignored, same as BpmController):
        a falsy return never rolls the state back.
        """
        new_state = bool(playing)
        if new_state == self._playing:
            return
        self._playing = new_state
        self._notify()
        self._send(1 if new_state else 0)

    def toggle(self) -> None:
        """Flip the current state. One discrete send per call, no debounce."""
        self.set_playing(not self._playing)

    def send_initial(self) -> None:
        """Send the current state once, unconditionally, without notifying (D-23)."""
        self._send(1 if self._playing else 0)


class EpicController:
    """Tracks the selected EPIC zone and decides when to send its preset (EPIC-03).

    Mirrors PlayController's track-value/notify-on-change/no-debounce shape:
    track the current zone, notify listeners on an actual change, let
    select_zone decide send timing. The engine never learns zone names --
    it only receives the preset's numeric value over /pp/epic (RESEARCH
    Pattern 3).
    """

    def __init__(
        self,
        send: Callable[[float], object],
        zones: Mapping[str, float] = config.EPIC_ZONES,
        initial_zone: str = config.EPIC_DEFAULT_ZONE,
    ) -> None:
        zones = dict(zones)
        if not zones:
            raise ValueError("EpicController: zones must not be empty")
        if initial_zone not in zones:
            raise ValueError(f"EpicController: initial_zone {initial_zone!r} not in zones")
        self._send = send
        self._zones = zones
        self._zone = initial_zone
        self._listeners: list[Callable[[str], None]] = []

    @property
    def zone(self) -> str:
        return self._zone

    @property
    def value(self) -> float:
        return float(self._zones[self._zone])

    @property
    def zone_names(self) -> tuple[str, ...]:
        return tuple(self._zones)

    def add_listener(self, fn: Callable[[str], None]) -> None:
        self._listeners.append(fn)

    def _notify(self) -> None:
        for listener in self._listeners:
            listener(self._zone)

    def select_zone(self, name: str) -> None:
        """Select a zone by name; notify and send only on an actual change.

        Raises ValueError before any state change if name is not a known
        zone. Returns without notifying or sending if name equals the
        current zone. Otherwise stores the new zone, calls every listener
        with the zone name, then sends once -- send is fire-and-forget
        (its return value is ignored, same as PlayController): a falsy
        return never rolls the zone back.
        """
        if name not in self._zones:
            raise ValueError(f"unknown EPIC zone {name!r}")
        if name == self._zone:
            return
        self._zone = name
        self._notify()
        self._send(float(self._zones[name]))

    def send_initial(self) -> None:
        """Send the current zone's value once, unconditionally, without notifying (D-23)."""
        self._send(float(self._zones[self._zone]))
