# Phase 5: Library Selectors in the GUI - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md. This log preserves the alternatives considered.

**Date:** 2026-10-12
**Phase:** 05-library-selectors-in-the-gui
**Areas discussed:** Selector style & placement, Startup selection, How names appear, Picking up new files

---

## Selector style & placement

| Option | Description | Selected |
|--------|-------------|----------|
| Dropdown menu | Labeled pop-up per category; compact, no focus | ✓ |
| Button rows | Like the EPIC zones; grows with every file | |
| You decide | Claude picks | |

| Option | Description | Selected |
|--------|-------------|----------|
| Below Volume | "Library" block under the riding controls | |
| Above BPM | Music choices at the top | |
| Side column | Second column to the right; wider instead of taller | ✓ |

| Option | Description | Selected |
|--------|-------------|----------|
| Palette, Progression, Melody | Roadmap order (GUI-05) | ✓ |
| Melody, Palette, Progression | Most-used first | |
| You decide | Claude picks | |

## Startup selection

| Option | Description | Selected |
|--------|-------------|----------|
| Auto, sent on launch | Shows Auto, sends `auto` at startup like BPM/EPIC/volume | ✓ |
| Auto, not sent | Display may disagree with the engine after a restart | |
| Remember last pick | Needs a settings file | |

## How names appear

| Option | Description | Selected |
|--------|-------------|----------|
| Exact file name | `classic_lead_loud`, same everywhere | ✓ |
| Tidied names | "Classic Lead Loud" | |

**User's choice:** Exact file name. The user first mentioned mapping names to descriptive labels via a settings file, then clarified: "Just keep the exact file name, I no longer want the descriptive name. This eliminates any need for a settings file."

| Option | Description | Selected |
|--------|-------------|----------|
| classic first, then A–Z | Safe baseline always second | ✓ |
| Plain A–Z | Strictly alphabetical | |
| Newest first | Shifting order | |

## Picking up new files

| Option | Description | Selected |
|--------|-------------|----------|
| Re-scan when opened | New files appear without relaunch | ✓ |
| Relaunch only | Roadmap minimum | |

## Claude's Discretion

- Which files count as entries (`.scd`, skip hidden and `_`-prefixed files, consider the engine's stem rule and the reserved `auto`)
- Behaviour when the selected file disappears from disk
- Module split (controller in `bpm_logic.py`-style logic, thin Tk wiring), focus handling and tests
- Verifying that the engine posts a confirmation of the received selection

## Deferred Ideas

- Descriptive labels via a settings file (dropped by the user)
- Remembering the last selection between launches (rejected)
