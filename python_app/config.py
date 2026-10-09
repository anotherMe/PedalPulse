"""Shared constants for the PedalPulse Python control app.

Host/port target sclang's language port (NOT scsynth's server port 57110) --
see .claude/CLAUDE.md "What NOT to Use" and 01-RESEARCH.md Pitfall 1.
"""

OSC_HOST = "127.0.0.1"
OSC_PORT = 57120  # sclang language port (NOT scsynth 57110)
OSC_BPM_ADDRESS = "/pp/bpm"
OSC_PLAY_ADDRESS = "/pp/play"
OSC_EPIC_ADDRESS = "/pp/epic"
OSC_VOLUME_ADDRESS = "/pp/volume"
BPM_MIN = 60
BPM_MAX = 180
BPM_DEFAULT = 120
NUDGE_DEBOUNCE_MS = 150

# EPIC-03: zone preset buttons. Insertion order is the left-to-right button
# order in the GUI. Values are EPIC 0-100 and strictly increasing; VO2 sits
# at 100 so the maximum-EPIC, no-clip state is reachable from a real
# button. Recovery's 10 matches the engine's boot default
# (supercollider/main.scd ~epic = 10). The engine never sees these zone
# names -- it only receives the numeric value over /pp/epic.
EPIC_ZONES = {
    "Recovery": 10,
    "Endurance": 30,
    "Tempo": 50,
    "Threshold": 75,
    "VO2": 100,
}
EPIC_DEFAULT_ZONE = "Recovery"
