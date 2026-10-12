"""Send-only OSC client for the PedalPulse Python control app (D-24).

The engine owns clamping (TEMPO-03, D-08): this module sends BPM/EPIC values
unclamped and lets supercollider/main.scd's OSCdef(\\pp_bpm)/OSCdef(\\pp_epic)
decide what to do with them. This also doubles as the raw-send CLI used by
the smoke test and by manual D-08 engine-clamp verification, since it can
send any float (including out-of-range values, "nan", "inf") bypassing the
GUI entirely.

The client also sends /pp/play <int> (1 = start, 0 = stop) for the
transport, validated and applied by supercollider/main.scd's
OSCdef(\\pp_play), /pp/epic <float> (0-100, unclamped) for the EPIC
energy level (EPIC-01/EPIC-02), validated and applied by
OSCdef(\\pp_epic), and /pp/volume <float> (0-100, unclamped) for the
master volume (GUI-03), validated and applied by OSCdef(\\pp_volume).
Library selections go to /pp/palette, /pp/progression and /pp/melody as one
OSC string each (a library file stem or auto, GUI-06), validated by the
engine's ~ppSelect.
"""

from __future__ import annotations

import argparse
import sys

import config
from pythonosc.osc_message_builder import BuildError
from pythonosc.udp_client import SimpleUDPClient


class OscClient:
    """Thin wrapper around pythonosc's SimpleUDPClient for /pp/bpm, /pp/play, /pp/epic, /pp/volume and the
    /pp/palette, /pp/progression and /pp/melody sends."""

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
        socket-level failure). It can also raise OverflowError (a float
        beyond float32 range, e.g. 1e300, raised by python-osc's packer
        before any socket I/O) or python-osc's own BuildError (an argument
        that cannot be packed into its wire type, e.g. a huge int --
        Phase 2 review WR-01). Catch all three so a GUI never crashes when
        the engine is absent or the value is pathological; return False
        instead.
        """
        try:
            self._client.send_message(config.OSC_BPM_ADDRESS, float(bpm))
        except (OSError, OverflowError, BuildError) as exc:
            print(f"OscClient: failed to send /pp/bpm {bpm} to {self.target}: {exc}", file=sys.stderr)
            return False
        return True

    def send_play(self, playing: int) -> bool:
        """Send config.OSC_PLAY_ADDRESS with int(playing). 1 = start, 0 = stop.

        The int(...) coercion is load-bearing: python-osc encodes a Python
        bool as the OSC True/False type tag with no payload, which sclang's
        OSCdef(\\pp_play) would not see as a number. Sent raw -- the engine
        is the validator (same send-only, send-raw contract as send_bpm).
        Catches (OSError, OverflowError, BuildError) for the same reasons as
        send_bpm.
        """
        try:
            self._client.send_message(config.OSC_PLAY_ADDRESS, int(playing))
        except (OSError, OverflowError, BuildError) as exc:
            print(f"OscClient: failed to send /pp/play {playing} to {self.target}: {exc}", file=sys.stderr)
            return False
        return True

    def send_epic(self, epic: float) -> bool:
        """Send config.OSC_EPIC_ADDRESS with float(epic), unclamped.

        Sent raw -- the engine clamps 0-100 independently of the GUI
        (EPIC-01 boundary). Catches (OSError, OverflowError, BuildError) for
        the same reasons as send_bpm.
        """
        try:
            self._client.send_message(config.OSC_EPIC_ADDRESS, float(epic))
        except (OSError, OverflowError, BuildError) as exc:
            print(f"OscClient: failed to send /pp/epic {epic} to {self.target}: {exc}", file=sys.stderr)
            return False
        return True

    def send_volume(self, volume: float) -> bool:
        """Send config.OSC_VOLUME_ADDRESS with float(volume), unclamped.

        Sent raw -- the engine clamps 0-100 independently of the GUI
        (GUI-03 boundary). Catches (OSError, OverflowError, BuildError) for
        the same reasons as send_bpm.
        """
        try:
            self._client.send_message(config.OSC_VOLUME_ADDRESS, float(volume))
        except (OSError, OverflowError, BuildError) as exc:
            print(f"OscClient: failed to send /pp/volume {volume} to {self.target}: {exc}", file=sys.stderr)
            return False
        return True

    def send_selection(self, address: str, name: str) -> bool:
        """Send `address` with `name` as one OSC string (GUI-06).

        `name` is a library file stem or auto, sent raw -- the engine
        validates it (~ppSelect) and keeps playing the current file if it
        refuses. Catches (OSError, OverflowError, BuildError) for the same
        reasons as send_bpm.
        """
        try:
            self._client.send_message(address, str(name))
        except (OSError, OverflowError, BuildError) as exc:
            print(f"OscClient: failed to send {address} {name} to {self.target}: {exc}", file=sys.stderr)
            return False
        return True


def main(argv: list[str] | None = None) -> int:
    """Raw-send CLI: python python_app/osc_client.py [BPM ...] [--epic F] [--volume F] [--play 0|1] [--host H] [--port P].

    Sends BPM value(s) in order, raw and unclamped (floats including "nan"
    and "inf" are accepted on purpose -- this is the D-08 test script for
    verifying the engine clamps independently of the GUI), then /pp/epic if
    --epic was given, then /pp/volume if --volume was given, then /pp/play
    if --play was given. At least one BPM value, --epic, --volume or --play
    is required.
    """
    parser = argparse.ArgumentParser(
        description="Send raw /pp/bpm, /pp/epic, /pp/volume and/or /pp/play OSC messages to the PedalPulse engine."
    )
    parser.add_argument("bpm", nargs="*", type=float, help="BPM value(s) to send, in order")
    parser.add_argument(
        "--epic",
        type=float,
        metavar="0-100",
        default=None,
        help="send /pp/epic with this float after any BPM values; sent raw, the engine clamps 0-100",
    )
    parser.add_argument(
        "--volume",
        type=float,
        metavar="0-100",
        default=None,
        help="send /pp/volume with this float after --epic; sent raw, the engine clamps 0-100",
    )
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

    if not args.bpm and args.epic is None and args.volume is None and args.play is None:
        parser.error("give at least one BPM value, --epic, --volume or --play")

    client = OscClient(host=args.host, port=args.port)
    all_ok = True
    for value in args.bpm:
        ok = client.send_bpm(value)
        all_ok = all_ok and ok
        print(f"sent /pp/bpm {value} to {client.target}")

    if args.epic is not None:
        ok = client.send_epic(args.epic)
        all_ok = all_ok and ok
        print(f"sent /pp/epic {args.epic} to {client.target}")

    if args.volume is not None:
        ok = client.send_volume(args.volume)
        all_ok = all_ok and ok
        print(f"sent /pp/volume {args.volume} to {client.target}")

    if args.play is not None:
        ok = client.send_play(args.play)
        all_ok = all_ok and ok
        print(f"sent /pp/play {args.play} to {client.target}")

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
