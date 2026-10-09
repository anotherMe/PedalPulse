#!/usr/bin/env bash
# One-command terminal runner for the headless PedalPulse smoke test (D-18).
#
# Usage: scripts/smoke_test.sh
# Override the sclang binary with: SCLANG=/path/to/sclang scripts/smoke_test.sh

set -euo pipefail
cd "$(dirname "$0")/.."

SCLANG="${SCLANG:-/Applications/SuperCollider.app/Contents/MacOS/sclang}"
if [ ! -x "$SCLANG" ]; then
	echo "smoke test FAILED: sclang not found or not executable at $SCLANG (set SCLANG=... to override)" >&2
	exit 1
fi

if [ ! -x .venv/bin/python ]; then
	echo "smoke test FAILED: .venv/bin/python is missing." >&2
	echo "Fix: ./run.sh --setup, or python3.13 -m venv .venv && .venv/bin/pip install -r python_app/requirements.txt" >&2
	exit 1
fi

# The offscreen Qt plugin is absent from the macOS SuperCollider 3.14.1
# bundle and aborts sclang with exit 134 (verified 2026-10-08) -- plain
# `sclang -D` already runs headless on its own, so make sure nothing
# upstream left this set.
unset QT_QPA_PLATFORM

LOG="${TMPDIR:-/tmp}/pedalpulse-smoke.log"

TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
	TIMEOUT_CMD="timeout 330"
elif command -v gtimeout >/dev/null 2>&1; then
	TIMEOUT_CMD="gtimeout 330"
fi

rc=0
$TIMEOUT_CMD "$SCLANG" -D supercollider/smoke_test.scd > "$LOG" 2>&1 || rc=$?

cat "$LOG"

if [ "$rc" -eq 0 ] && grep -q "SMOKE PASS" "$LOG"; then
	exit 0
else
	echo "smoke test FAILED (log: $LOG)" >&2
	exit 1
fi
