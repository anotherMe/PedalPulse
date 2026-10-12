"""Tests for library_logic: scan_library and LibrarySelector (GUI-05, GUI-06).

Every fixture lives in tmp_path: nothing here writes into the real
supercollider/library folders.
"""

from __future__ import annotations

import importlib
import os
from pathlib import Path

import pytest

import config
from library_logic import LibrarySelector, scan_library


def _touch(folder: Path, name: str) -> None:
    (folder / name).write_text("()")


# --- scan rule (GUI-05; mirrors ~ppStemValid in supercollider/core/loader.scd) ----


def test_scan_filters_and_orders(tmp_path):
    for name in (
        "classic.scd",
        "zeta.scd",
        "alpha.scd",
        "classic2.scd",
        "classic_lead.scd",
        "_template.scd",
        ".hidden.scd",
        "._alpha.scd",
        "Upper.scd",
        "auto.scd",
        "bad name.scd",
        "café.scd",
        "a.b.scd",
        "bad\n.scd",
        "notes.txt",
        "alpha.scd.bak",
    ):
        _touch(tmp_path, name)
    (tmp_path / "dir.scd").mkdir()

    assert scan_library(tmp_path) == ["classic", "alpha", "classic2", "classic_lead", "zeta"]


def test_scan_length_limit(tmp_path):
    _touch(tmp_path, "a" * 64 + ".scd")
    _touch(tmp_path, "a" * 65 + ".scd")

    assert scan_library(tmp_path) == ["a" * 64]


def test_scan_missing_empty_or_file_path_lists_nothing(tmp_path):
    empty = tmp_path / "empty"
    empty.mkdir()
    a_file = tmp_path / "plain.txt"
    a_file.write_text("x")

    assert scan_library(tmp_path / "nope") == []
    assert scan_library(empty) == []
    assert scan_library(a_file) == []


def test_scan_unreadable_folder_lists_nothing(tmp_path):
    if os.geteuid() == 0:
        pytest.skip("root can read any folder")
    folder = tmp_path / "locked"
    folder.mkdir()
    _touch(folder, "classic.scd")
    folder.chmod(0o000)
    try:
        assert scan_library(folder) == []
    finally:
        folder.chmod(0o755)


def test_scan_single_classic(tmp_path):
    _touch(tmp_path, "classic.scd")

    assert scan_library(tmp_path) == ["classic"]
    assert LibrarySelector("Melody", tmp_path, send=[].append).options() == ["Auto", "classic"]


def test_scan_order_does_not_depend_on_listing_order(tmp_path, monkeypatch):
    for stem in ("zeta", "classic", "classic_lead", "alpha", "classic2"):
        _touch(tmp_path, stem + ".scd")
    expected = ["classic", "alpha", "classic2", "classic_lead", "zeta"]
    original = type(tmp_path).iterdir

    for reverse in (True, False):

        def ordered(self, reverse=reverse):
            return iter(sorted(original(self), key=lambda p: p.name, reverse=reverse))

        monkeypatch.setattr(type(tmp_path), "iterdir", ordered)
        assert scan_library(tmp_path) == expected


# --- the real library -----------------------------------------------------------


def test_real_library_folders():
    for _title, folder, _address in config.LIBRARY_CATEGORIES:
        stems = scan_library(config.LIBRARY_ROOT / folder)
        assert stems[0] == "classic"
        assert "_template" not in stems

    melodies = scan_library(config.LIBRARY_ROOT / "melodies")
    assert {"classic", "classic_lead", "classic_lead_loud"} <= set(melodies)


def test_library_root_is_independent_of_cwd(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    try:
        importlib.reload(config)
        expected = Path(__file__).resolve().parents[2] / "supercollider" / "library"
        assert config.LIBRARY_ROOT == expected
        assert config.LIBRARY_ROOT.is_dir()
    finally:
        monkeypatch.undo()
        importlib.reload(config)
