#!/usr/bin/env bash
# One-command palette meter (Phase 7, PAL-04, D-13, D-15).
#
# Usage:
#   scripts/palette_level.sh               measure every palette on disk against classic
#   scripts/palette_level.sh acid          measure acid against classic (the authoring loop:
#                                          tune a new palette BEFORE its first commit, because a
#                                          committed palette file is final)
#   scripts/palette_level.sh acid warm     measure several by name
#
# classic is always measured first, as the reference. About a minute for one
# palette. The meter boots its own muted server on port 57142, so it never
# disturbs a running engine. It checks, per palette: loudness within 1.5 dB of
# classic (aim for 0.75 dB), post-FX peak at most 0.80 and output at most 0.892 at
# EPIC 100 and volume 100, server CPU under 25 percent, at most 40 synths, and
# every pitched voice finite at MIDI -12 and 127.
#
# scripts/check.sh runs it with no argument as part of the library gate.
#
# Override the sclang binary with: SCLANG=/path/to/sclang scripts/palette_level.sh

set -euo pipefail
cd "$(dirname "$0")/.."

# A palette name is 1-64 characters of a-z, 0-9 and _ (the engine's own rule). Refuse
# anything else here, before it reaches sclang.
for arg in "$@"; do
	if ! printf '%s' "$arg" | grep -Eq '^[a-z0-9_]{1,64}$'; then
		echo "usage: scripts/palette_level.sh [palette_name ...]   (names: 1-64 characters of a-z, 0-9 and _)" >&2
		exit 2
	fi
done

SCLANG="${SCLANG:-/Applications/SuperCollider.app/Contents/MacOS/sclang}"
if [ ! -x "$SCLANG" ]; then
	echo "palette level FAILED: sclang not found or not executable at $SCLANG (set SCLANG=... to override)" >&2
	exit 1
fi

# The offscreen Qt plugin is absent from the macOS SuperCollider 3.14.1
# bundle and aborts sclang with exit 134 -- plain `sclang -D` already runs
# headless on its own, so make sure nothing upstream left this set.
unset QT_QPA_PLATFORM

LOG="${TMPDIR:-/tmp}/pedalpulse-palette.log"

TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
	TIMEOUT_CMD="timeout 510"
elif command -v gtimeout >/dev/null 2>&1; then
	TIMEOUT_CMD="gtimeout 510"
fi

rc=0
PP_METER=level PP_METER_STEMS="$*" $TIMEOUT_CMD "$SCLANG" -D supercollider/palette_meter.scd > "$LOG" 2>&1 || rc=$?

cat "$LOG"

if [ "$rc" -eq 0 ] && grep -qx 'PALETTE PASS' "$LOG"; then
	exit 0
else
	echo "palette level FAILED (log: $LOG)" >&2
	exit 1
fi
