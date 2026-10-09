#!/usr/bin/env bash
# PedalPulse launcher (D-05): creates ./.venv from python3.13 if missing,
# installs python_app/requirements.txt (and requirements-dev.txt with
# --setup), then launches python_app/main.py with the venv interpreter.
#
# This script touches nothing outside the project directory: no package
# manager, no privileged command, no global or user-site pip install. The
# interpreter is overridable with PEDALPULSE_PYTHON (default python3.13)
# as the one-line reversibility point for D-02.
set -euo pipefail
cd "$(dirname "$0")"

PYTHON="${PEDALPULSE_PYTHON:-python3.13}"

if [ ! -x .venv/bin/python ]; then
  if ! command -v "$PYTHON" >/dev/null 2>&1; then
    echo "ERROR: $PYTHON not found on PATH." >&2
    echo "Fix: install it via Homebrew: brew install python@3.13 python-tk@3.13" >&2
    exit 1
  fi
  "$PYTHON" -m venv .venv
fi

if [ ! -f .venv/.pp-requirements.stamp ] || [ python_app/requirements.txt -nt .venv/.pp-requirements.stamp ]; then
  .venv/bin/pip install -q -r python_app/requirements.txt
  touch .venv/.pp-requirements.stamp
fi

if [ "${1:-}" = "--setup" ]; then
  shift || true
  if [ ! -f .venv/.pp-dev-requirements.stamp ] || [ python_app/requirements-dev.txt -nt .venv/.pp-dev-requirements.stamp ]; then
    .venv/bin/pip install -q -r python_app/requirements-dev.txt
    touch .venv/.pp-dev-requirements.stamp
  fi
  echo "PedalPulse venv ready: .venv"
  .venv/bin/python python_app/tkcheck.py
  exit 0
fi

exec .venv/bin/python python_app/main.py "$@"
