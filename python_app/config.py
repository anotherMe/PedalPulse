"""Shared constants for the PedalPulse Python control app.

Host/port target sclang's language port (NOT scsynth's server port 57110) --
see .claude/CLAUDE.md "What NOT to Use" and 01-RESEARCH.md Pitfall 1.
"""

OSC_HOST = "127.0.0.1"
OSC_PORT = 57120  # sclang language port (NOT scsynth 57110)
OSC_BPM_ADDRESS = "/pp/bpm"
OSC_PLAY_ADDRESS = "/pp/play"
OSC_EPIC_ADDRESS = "/pp/epic"
BPM_MIN = 60
BPM_MAX = 180
BPM_DEFAULT = 120
NUDGE_DEBOUNCE_MS = 150
