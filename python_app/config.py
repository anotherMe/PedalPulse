"""Shared constants for the PedalPulse Python control app.

Host/port target sclang's language port (NOT scsynth's server port 57110) --
see .claude/CLAUDE.md "What NOT to Use" and 01-RESEARCH.md Pitfall 1.
"""

from pathlib import Path

OSC_HOST = "127.0.0.1"
OSC_PORT = 57120  # sclang language port (NOT scsynth 57110)
OSC_BPM_ADDRESS = "/pp/bpm"
OSC_PLAY_ADDRESS = "/pp/play"
OSC_EPIC_ADDRESS = "/pp/epic"
OSC_VOLUME_ADDRESS = "/pp/volume"
# GUI-05/GUI-06: the library selection addresses. Fixed by the engine's
# OSCdef(\pp_palette), OSCdef(\pp_progression) and OSCdef(\pp_melody) in
# supercollider/main.scd (frozen Phase 4 interface).
OSC_PALETTE_ADDRESS = "/pp/palette"
OSC_PROGRESSION_ADDRESS = "/pp/progression"
OSC_MELODY_ADDRESS = "/pp/melody"
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

# GUI-03: the app's master volume scale. The engine maps this 0-100 range
# to gain and clamps it independently (supercollider/main.scd
# ~ppVolumeAmp). The default is deliberately below the maximum, so
# launching the app never jumps the engine to full volume.
VOLUME_MIN = 0
VOLUME_MAX = 100
VOLUME_DEFAULT = 80

# GUI-05: library selectors. The library folders are resolved from this
# file, never from the current directory.
LIBRARY_ROOT = Path(__file__).resolve().parents[1] / "supercollider" / "library"
# One dropdown per entry: (title shown, folder under LIBRARY_ROOT, OSC
# address), in side-column order top to bottom (D-03).
LIBRARY_CATEGORIES = (
    ("Palette", "palettes", OSC_PALETTE_ADDRESS),
    ("Progression", "progressions", OSC_PROGRESSION_ADDRESS),
    ("Melody", "melodies", OSC_MELODY_ADDRESS),
)
# D-07: the label shown in the GUI, and the word sent to the engine (where
# "auto" is a reserved word, not a file stem).
AUTO_LABEL = "Auto"
AUTO_NAME = "auto"
# D-07: the stem listed right after Auto.
LIBRARY_FIRST_STEM = "classic"
# Fixed width in characters, so a long name never changes the window width.
# Accepted trade-off: a stem longer than 20 characters is cut on the closed
# button but is shown in full in the open menu.
LIBRARY_DROPDOWN_WIDTH = 20
