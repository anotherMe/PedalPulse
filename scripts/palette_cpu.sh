#!/usr/bin/env bash
# One-command CPU check for the sound palettes (Phase 7, D-14, D-15).
#
# Run this once on the Mac where you ride, with Zwift open, to see whether the
# music engine leaves enough room for it:
#
#   1. Quit the PedalPulse engine first (close its SuperCollider window), so only
#      this check is making sound-engine load.
#   2. Open Zwift (no ride needed, the menu is enough).
#   3. Run:  bash scripts/palette_cpu.sh
#   4. Report the `mean` and `peak` numbers from the line that starts with
#      "PedalPulse meter: cpu <palette> mean=...". It passes when the mean is
#      under 25 percent (it prints CPU PASS).
#
# What it does: it boots its own muted second sound server on port 57142 (so it never
# touches a running engine), plays every palette for a few seconds at the hardest
# setting (EPIC 100, volume 100), picks the heaviest one, and holds that palette
# for one minute while it samples scsynth's own CPU load. The number is the sound
# server's load as it reports it, on this machine, at this moment: with Zwift open it
# includes whatever Zwift is taking from the same processor.
#
# Usage:
#   scripts/palette_cpu.sh            find the heaviest palette and measure it
#   scripts/palette_cpu.sh acid       measure one named palette only
#
# Takes about 2 to 3 minutes. Log: ${TMPDIR:-/tmp}/pedalpulse-cpu.log
#
# Override the sclang binary with: SCLANG=/path/to/sclang scripts/palette_cpu.sh

set -euo pipefail
cd "$(dirname "$0")/.."

# At most one palette name: 1-64 characters of a-z, 0-9 and _ (the engine's own
# rule). Refuse anything else here, before it reaches sclang.
if [ "$#" -gt 1 ]; then
	echo "usage: scripts/palette_cpu.sh [palette_name]   (names: 1-64 characters of a-z, 0-9 and _)" >&2
	exit 2
fi
for arg in "$@"; do
	if ! printf '%s' "$arg" | grep -Eq '^[a-z0-9_]{1,64}$'; then
		echo "usage: scripts/palette_cpu.sh [palette_name]   (names: 1-64 characters of a-z, 0-9 and _)" >&2
		exit 2
	fi
done

SCLANG="${SCLANG:-/Applications/SuperCollider.app/Contents/MacOS/sclang}"
if [ ! -x "$SCLANG" ]; then
	echo "palette cpu FAILED: sclang not found or not executable at $SCLANG (set SCLANG=... to override)" >&2
	exit 1
fi

# The offscreen Qt plugin is absent from the macOS SuperCollider 3.14.1
# bundle and aborts sclang with exit 134 -- plain `sclang -D` already runs
# headless on its own, so make sure nothing upstream left this set.
unset QT_QPA_PLATFORM

LOG="${TMPDIR:-/tmp}/pedalpulse-cpu.log"

TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
	TIMEOUT_CMD="timeout 510"
elif command -v gtimeout >/dev/null 2>&1; then
	TIMEOUT_CMD="gtimeout 510"
fi

rc=0
PP_METER=cpu PP_METER_STEMS="${1:-}" $TIMEOUT_CMD "$SCLANG" -D supercollider/palette_meter.scd > "$LOG" 2>&1 || rc=$?

cat "$LOG"

if [ "$rc" -eq 0 ] && grep -qx 'CPU PASS' "$LOG"; then
	exit 0
else
	echo "palette cpu FAILED (log: $LOG)" >&2
	exit 1
fi
