"""Make python_app/ importable as top-level modules (config, osc_client, ...)
when pytest is invoked from the repo root as `.venv/bin/pytest python_app/tests`.
"""

from __future__ import annotations

import sys
from pathlib import Path

_PYTHON_APP_DIR = Path(__file__).resolve().parents[1]
if str(_PYTHON_APP_DIR) not in sys.path:
    sys.path.insert(0, str(_PYTHON_APP_DIR))
