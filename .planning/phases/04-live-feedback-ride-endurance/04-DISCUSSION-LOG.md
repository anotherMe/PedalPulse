# Phase 4: Live Feedback & Ride Endurance - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-10
**Phase:** 4-live-feedback-ride-endurance
**Areas discussed:** Connection indicator, Reconnect resync, Live engine readout, Soak test procedure

---

## Connection indicator

| Option | Description | Selected |
|--------|-------------|----------|
| Colored dot + word | Green/grey dot with "Engine connected" / "Engine not responding" | ✓ |
| Text only | Status line wording changes only | |
| Whole status line colored | Status line background green/red | |

| Option (timeout) | Description | Selected |
|--------|-------------|----------|
| ~3 seconds | Tolerates brief sclang stalls | ✓ |
| ~1 second | Very responsive, may flicker | |
| ~5–10 seconds | Never flickers, slow to notice | |
| You decide | Claude picks | |

| Option (controls while disconnected) | Description | Selected |
|--------|-------------|----------|
| Stay fully usable | Only indicator changes | ✓ |
| Grey out controls | Disabled until connected | |
| Usable but dimmed | Visual hint only | |

| Option (launch state) | Description | Selected |
|--------|-------------|----------|
| Disconnected until first beat | Simple, never lies | ✓ |
| "Connecting…" for ~3 s | Neutral third state | |

**User's choice:** All recommended options.

---

## Reconnect resync

| Option | Description | Selected |
|--------|-------------|----------|
| Auto re-send everything | BPM, zone, volume, play on every reconnect | ✓ |
| Re-send all except Play | Engine stays stopped until Start | |
| No resync, show mismatch | User fixes by hand | |

| Option (BPM on resync) | Description | Selected |
|--------|-------------|----------|
| Normal ~2-bar glide | Reuse existing ramp | ✓ |
| Jump instantly | Needs a no-glide engine path | |

| Option (visibility) | Description | Selected |
|--------|-------------|----------|
| Silent | Indicator + readout only | ✓ |
| Brief note | "Engine reconnected — settings re-sent" | |

**User's choice:** All recommended options.

---

## Live engine readout

| Option (placement) | Description | Selected |
|--------|-------------|----------|
| Separate "Engine" readout line | Dedicated line next to the dot | ✓ |
| Inline next to each control | Grey actual values beside controls | |
| Big BPM display | Large actual-BPM number | |

| Option (EPIC value) | Description | Selected |
|--------|-------------|----------|
| Gliding value + target | "EPIC 38 → 50" | |
| Gliding value only | Live smoothed number | |
| Target value only | Engine's accepted target | ✓ |

| Option (BPM format) | Description | Selected |
|--------|-------------|----------|
| Live value, 1 decimal, + target | "131.4 → 140 BPM" | |
| Live value, 1 decimal only | "131.4 BPM" | |
| Live value, whole numbers | "131 BPM" | ✓ |

| Option (zone name) | Description | Selected |
|--------|-------------|----------|
| Number + zone name | "EPIC 50 (Tempo)", number only if no match | ✓ |
| Number only | "EPIC 50" | |

| Option (disconnected) | Description | Selected |
|--------|-------------|----------|
| Dashes | Never show stale numbers | ✓ |
| Last known, greyed | Keep last values greyed | |

**User's choice:** Separate line; target-only EPIC and whole-number BPM (calmer than the recommended options); zone name; dashes.

---

## Soak test procedure

| Option (how to run) | Description | Selected |
|--------|-------------|----------|
| Real Zwift ride + logger | Real session, logger records stats | |
| Scripted run + logger | Scripted changes for 60 min | |
| Both | Scripted first, then real ride | |

**User's choice (free text):** "I will ride the real 60+ min Zwift session but don't want this to block further developments, so we will not consider this test as blocking. I will do the test when I have time."

| Option (automated proxy) | Description | Selected |
|--------|-------------|----------|
| Short headless leak check | Few-minute node-count check in smoke_test.sh | |
| Nothing automated | Existing smoke tests + eventual real ride | ✓ |
| Long headless run (opt-in) | Separate 60-min headless script | |

| Option (logger) | Description | Selected |
|--------|-------------|----------|
| Yes, simple logger | Logs node count/CPU every ~30 s | |
| No, watch the SC IDE | Nothing to build | |

**User's choice (free text):** "Yes, I would rely on a simple logger but the logging should be an organic part of the application (eg: if I launch the Python app with the --log option, log messages should be sent to std out)."

| Option (log content) | Description | Selected |
|--------|-------------|----------|
| Periodic stats + events | ~30 s stats + one line per event | |
| Periodic stats only | Stats line only | |
| Everything, every heartbeat | One line per heartbeat | |

**User's choice (free text):** "Include lower level messages (like Periodic stats + events) but, in the Python script there will be a parameter setting the lower TRACE messages currently showed (I will modify the script when I need to). Generic INFO messages should be included at main execution point, DEBUG at the possible critical execution points and ERROR in try-catch clauses."

| Option (stats level) | Description | Selected |
|--------|-------------|----------|
| Stats at DEBUG | Default threshold DEBUG | ✓ |
| Stats at INFO | Visible at INFO threshold | |

**Notes:** The user said the level names came from their Java experience and they weren't sure what Python's levels are. Claude noted that stdlib `logging` has no TRACE level, so a custom one is needed.

---

## Claude's Discretion

- Heartbeat/status message design (address, rate, combined vs separate, return port, how sclang learns the destination)
- Python receive architecture (background thread + queue + `root.after`)
- Indicator/readout glyphs, colors, wording, window placement
- Logger structure and formatter; where the 30 s stats timer lives

## Deferred Ideas

- 60+ minute real-ride soak: non-blocking, the user runs it when time allows
- Automated headless leak check / long headless soak: rejected for now
