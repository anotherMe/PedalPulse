"""Launch test for python_app/main.py (D-04, GUI-06).

Runs the real entry point in a subprocess, so its own Tk root never shares
this pytest process with the Tk roots of test_view_tk.py, and so the test
covers the real startup wiring. Every startup datagram is captured on a
bound loopback socket; nothing is ever sent to the engine's port 57120.
"""

from __future__ import annotations

import socket
import subprocess
import sys
from pathlib import Path

import pytest
from pythonosc.osc_message import OscMessage

REPO = Path(__file__).resolve().parents[2]

EXPECTED = [
    ("/pp/bpm", [120.0]),
    ("/pp/play", [1]),
    ("/pp/epic", [10.0]),
    ("/pp/volume", [80.0]),
    ("/pp/palette", ["auto"]),
    ("/pp/progression", ["auto"]),
    ("/pp/melody", ["auto"]),
]


def _display_available() -> bool:
    """True when a throwaway Tk root can be created (withdrawn, so nothing is shown)."""
    probe = subprocess.run(
        [
            sys.executable,
            "-c",
            "import tkinter; r = tkinter.Tk(); r.withdraw(); r.destroy()",
        ],
        capture_output=True,
        timeout=30,
    )
    return probe.returncode == 0


@pytest.fixture(scope="module", autouse=True)
def _need_display():
    # The probe is independent of main.py, so a real startup regression still
    # fails the test; only an environment with no usable Tk display skips.
    if not _display_available():
        pytest.skip("no Tk display available for the launch test")


def _launch_and_capture(sock: socket.socket) -> list[tuple[str, list]]:
    port = sock.getsockname()[1]
    result = subprocess.run(
        [sys.executable, str(REPO / "python_app" / "main.py"), "--port", str(port), "--exit-after", "300", "--hidden"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    assert "Traceback" not in result.stderr

    sock.settimeout(1.0)
    received: list[tuple[str, list]] = []
    while True:
        try:
            datagram, _addr = sock.recvfrom(4096)
        except socket.timeout:
            break
        message = OscMessage(datagram)
        received.append((message.address, list(message.params)))
    return received


def test_launch_sends_initial_values_then_auto_to_each_library_address():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.bind(("127.0.0.1", 0))
        first = _launch_and_capture(sock)
        assert first == EXPECTED
        # Nothing is remembered between launches: the same seven datagrams again.
        second = _launch_and_capture(sock)
        assert second == first
    finally:
        sock.close()
