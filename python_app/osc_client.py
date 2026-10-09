"""Send-only OSC client for the PedalPulse Python control app (D-24).

The engine owns clamping (TEMPO-03, D-08): this module sends BPM values
unclamped and lets supercollider/main.scd's OSCdef(\\pp_bpm) decide what to
do with them. This also doubles as the raw-send CLI used by the smoke test
and by manual D-08 engine-clamp verification, since it can send any float
(including out-of-range values, "nan", "inf") bypassing the GUI entirely.

The client also sends /pp/play <int> (1 = start, 0 = stop) for the
transport, validated and applied by supercollider/main.scd's
OSCdef(\\pp_play).
"""

from __future__ import annotations

import argparse
import sys

import config
from pythonosc.udp_client import SimpleUDPClient


class OscClient:
    """Thin wrapper around pythonosc's SimpleUDPClient for /pp/bpm and /pp/play sends."""

    def __init__(self, host: str = config.OSC_HOST, port: int = config.OSC_PORT) -> None:
        self.host = host
        self.port = port
        self._client = SimpleUDPClient(host, port)

    @property
    def target(self) -> str:
        return f"{self.host}:{self.port}"

    def send_bpm(self, bpm: float) -> bool:
        """Send config.OSC_BPM_ADDRESS with float(bpm), unclamped.

        UDP is connectionless, so a missing listener does not raise -- but
        send_message can still raise OSError (e.g. no route to host, or a
        socket-level failure). Catch it so a GUI never crashes when the
        engine is absent; return False instead.
        """
        try:
            self._client.send_message(config.OSC_BPM_ADDRESS, float(bpm))
        except OSError as exc:
            print(f"OscClient: failed to send /pp/bpm {bpm} to {self.target}: {exc}", file=sys.stderr)
            return False
        return True

    def send_play(self, playing: int) -> bool:
        """Send config.OSC_PLAY_ADDRESS with int(playing). 1 = start, 0 = stop.

        The int(...) coercion is load-bearing: python-osc encodes a Python
        bool as the OSC True/False type tag with no payload, which sclang's
        OSCdef(\\pp_play) would not see as a number. Sent raw -- the engine
        is the validator (same send-only, send-raw contract as send_bpm).
        """
        try:
            self._client.send_message(config.OSC_PLAY_ADDRESS, int(playing))
        except OSError as exc:
            print(f"OscClient: failed to send /pp/play {playing} to {self.target}: {exc}", file=sys.stderr)
            return False
        return True


def main(argv: list[str] | None = None) -> int:
    """Raw-send CLI: python python_app/osc_client.py [BPM ...] [--play 0|1] [--host H] [--port P].

    Sends BPM value(s) in order, raw and unclamped (floats including "nan"
    and "inf" are accepted on purpose -- this is the D-08 test script for
    verifying the engine clamps independently of the GUI), then sends
    /pp/play if --play was given. At least one BPM value or --play is
    required.
    """
    parser = argparse.ArgumentParser(
        description="Send raw /pp/bpm and/or /pp/play OSC messages to the PedalPulse engine."
    )
    parser.add_argument("bpm", nargs="*", type=float, help="BPM value(s) to send, in order")
    parser.add_argument(
        "--play",
        type=int,
        metavar="0|1",
        default=None,
        help="send /pp/play with this int after any BPM values; 1 = start, 0 = stop; sent raw, the engine decides",
    )
    parser.add_argument("--host", default=config.OSC_HOST, help="Target host (default: %(default)s)")
    parser.add_argument("--port", type=int, default=config.OSC_PORT, help="Target port (default: %(default)s)")
    args = parser.parse_args(argv)

    if not args.bpm and args.play is None:
        parser.error("give at least one BPM value or --play")

    client = OscClient(host=args.host, port=args.port)
    all_ok = True
    for value in args.bpm:
        ok = client.send_bpm(value)
        all_ok = all_ok and ok
        print(f"sent /pp/bpm {value} to {client.target}")

    if args.play is not None:
        ok = client.send_play(args.play)
        all_ok = all_ok and ok
        print(f"sent /pp/play {args.play} to {client.target}")

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
