"""Tests for python_app/osc_client.py (send-only OscClient + raw-send CLI, D-24)."""

from __future__ import annotations

import socket
from unittest.mock import patch

import pytest
from pythonosc.osc_message import OscMessage

import osc_client
from osc_client import OscClient


def _bound_udp_socket():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0))
    sock.settimeout(2)
    return sock


def test_send_bpm_delivers_decodable_osc_message_over_real_socket():
    sock = _bound_udp_socket()
    try:
        port = sock.getsockname()[1]
        client = OscClient(host="127.0.0.1", port=port)

        assert client.send_bpm(133) is True
        datagram, _addr = sock.recvfrom(4096)
        message = OscMessage(datagram)
        assert message.address == "/pp/bpm"
        assert list(message.params) == [133.0]
    finally:
        sock.close()


def test_send_bpm_delivers_unclamped_value():
    sock = _bound_udp_socket()
    try:
        port = sock.getsockname()[1]
        client = OscClient(host="127.0.0.1", port=port)

        assert client.send_bpm(300) is True
        datagram, _addr = sock.recvfrom(4096)
        message = OscMessage(datagram)
        assert list(message.params) == [300.0]
    finally:
        sock.close()


def test_send_bpm_calls_sendto_once_with_correct_destination():
    with patch("socket.socket") as mock_socket_cls:
        mock_socket = mock_socket_cls.return_value
        client = OscClient(host="127.0.0.1", port=57120)
        client.send_bpm(140)

    mock_socket.sendto.assert_called_once()
    _data, destination = mock_socket.sendto.call_args[0]
    assert destination == ("127.0.0.1", 57120)


def test_send_bpm_to_unused_port_returns_true_without_raising():
    # Nothing listens on this ephemeral port once we close it, but UDP send
    # does not require a listener (connectionless).
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    probe.bind(("127.0.0.1", 0))
    unused_port = probe.getsockname()[1]
    probe.close()

    client = OscClient(host="127.0.0.1", port=unused_port)
    assert client.send_bpm(120) is True


def test_send_bpm_returns_false_on_oserror(capsys):
    client = OscClient(host="127.0.0.1", port=57120)
    with patch.object(client._client, "send_message", side_effect=OSError("boom")):
        assert client.send_bpm(120) is False
    err = capsys.readouterr().err
    assert err.count("\n") == 1
    assert "boom" in err


def test_cli_main_sends_and_prints(capsys):
    sock = _bound_udp_socket()
    try:
        port = sock.getsockname()[1]
        rc = osc_client.main(["150", "--port", str(port)])
        assert rc == 0
        out = capsys.readouterr().out
        assert f"sent /pp/bpm 150.0 to 127.0.0.1:{port}" in out

        datagram, _addr = sock.recvfrom(4096)
        message = OscMessage(datagram)
        assert list(message.params) == [150.0]
    finally:
        sock.close()


def test_cli_main_delivers_nan():
    sock = _bound_udp_socket()
    try:
        port = sock.getsockname()[1]
        rc = osc_client.main(["nan", "--port", str(port)])
        assert rc == 0

        datagram, _addr = sock.recvfrom(4096)
        message = OscMessage(datagram)
        import math

        assert math.isnan(message.params[0])
    finally:
        sock.close()


def test_send_play_delivers_int_osc_message_over_real_socket():
    sock = _bound_udp_socket()
    try:
        port = sock.getsockname()[1]
        client = OscClient(host="127.0.0.1", port=port)

        assert client.send_play(1) is True
        datagram, _addr = sock.recvfrom(4096)
        message = OscMessage(datagram)
        assert message.address == "/pp/play"
        assert list(message.params) == [1]
        assert isinstance(message.params[0], int)

        assert client.send_play(0) is True
        datagram, _addr = sock.recvfrom(4096)
        message = OscMessage(datagram)
        assert message.address == "/pp/play"
        assert list(message.params) == [0]
        assert isinstance(message.params[0], int)
    finally:
        sock.close()


def test_send_play_coerces_bool_to_int():
    sock = _bound_udp_socket()
    try:
        port = sock.getsockname()[1]
        client = OscClient(host="127.0.0.1", port=port)

        assert client.send_play(True) is True
        datagram, _addr = sock.recvfrom(4096)
        message = OscMessage(datagram)
        assert list(message.params) == [1]
        assert isinstance(message.params[0], int)
    finally:
        sock.close()


def test_send_play_returns_false_on_oserror(capsys):
    client = OscClient(host="127.0.0.1", port=57120)
    with patch.object(client._client, "send_message", side_effect=OSError("boom")):
        assert client.send_play(0) is False
    err = capsys.readouterr().err
    assert err.count("\n") == 1
    assert "boom" in err


def test_cli_main_sends_play(capsys):
    sock = _bound_udp_socket()
    try:
        port = sock.getsockname()[1]
        rc = osc_client.main(["--play", "0", "--port", str(port)])
        assert rc == 0
        out = capsys.readouterr().out
        assert f"sent /pp/play 0 to 127.0.0.1:{port}" in out

        datagram, _addr = sock.recvfrom(4096)
        message = OscMessage(datagram)
        assert message.address == "/pp/play"
        assert list(message.params) == [0]
    finally:
        sock.close()


def test_cli_main_requires_bpm_or_play():
    with pytest.raises(SystemExit) as exc_info:
        osc_client.main(["--port", "57199"])
    assert exc_info.value.code == 2
