"""Tests for python_app/tkcheck.py (GUI-04 compatibility gate, D-03, D-04)."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

import tkcheck


def test_check_tk_compatible_returns_tkinter_module_under_project_venv():
    tkinter_module = tkcheck.check_tk_compatible()
    assert tkinter_module.__name__ == "tkinter"
    assert tkinter_module.TkVersion >= tkcheck.MIN_TK_VERSION


def test_missing_tkinter_exits_1_with_clear_message(monkeypatch, capsys):
    monkeypatch.setitem(sys.modules, "tkinter", None)
    with pytest.raises(SystemExit) as exc_info:
        tkcheck.check_tk_compatible()
    assert exc_info.value.code == 1
    err = capsys.readouterr().err
    assert "Tkinter is not available" in err
    assert "./run.sh" in err
    assert "python3.13" in err


def test_tk_version_8_5_exits_1_with_version_message(monkeypatch, capsys):
    import tkinter

    monkeypatch.setattr(tkinter, "TkVersion", 8.5)
    with pytest.raises(SystemExit) as exc_info:
        tkcheck.check_tk_compatible()
    assert exc_info.value.code == 1
    err = capsys.readouterr().err
    assert "8.5" in err
    assert "8.6" in err


@pytest.mark.parametrize("version", [8.6, 9.0])
def test_tk_version_8_6_and_9_0_both_pass(monkeypatch, version):
    import tkinter

    monkeypatch.setattr(tkinter, "TkVersion", version)
    tkinter_module = tkcheck.check_tk_compatible()
    assert tkinter_module.__name__ == "tkinter"


def test_importing_tkcheck_does_not_import_tkinter():
    # tkcheck is already imported at module scope above; verify it did not
    # pull tkinter in as a side effect of that import by checking the
    # module source has no module-level tkinter import statement.
    source = Path(tkcheck.__file__).read_text()
    for line in source.splitlines():
        stripped = line.strip()
        if stripped.startswith("import tkinter") or stripped.startswith("from tkinter"):
            pytest.fail(f"Found module-level tkinter import: {line!r}")


def test_python312_without_tkinter_exits_1_with_fix_hint():
    python312 = shutil.which("python3.12")
    if not python312:
        pytest.skip("python3.12 not found on PATH")

    tkcheck_path = Path(__file__).resolve().parents[1] / "tkcheck.py"
    result = subprocess.run(
        [python312, str(tkcheck_path)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 1
    assert "./run.sh" in result.stderr
