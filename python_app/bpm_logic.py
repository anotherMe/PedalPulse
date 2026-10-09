"""Pure BPM state + send policy for the PedalPulse control app (GUI-01, LINK-01).

No tkinter import -- this module stays unit-testable without a display and
is driven by injected schedule/cancel callables (Tk's root.after /
root.after_cancel in the app, a fake scheduler in tests).
"""

from __future__ import annotations

import math
from typing import Callable

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
    """RED stub -- real implementation added in GREEN."""
    return None


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

    def _set(self, new_value: int) -> bool:
        """Update the value and notify listeners only on an actual change."""
        if new_value == self._value:
            return False
        self._value = new_value
        for listener in self._listeners:
            listener(new_value)
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
        """RED stub -- real implementation added in GREEN."""
        return False

    def send_initial(self) -> None:
        """Send the current value once, unconditionally (D-23)."""
        self._send_now()
