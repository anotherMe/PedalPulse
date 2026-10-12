# Phase 6: Shared Harmony & Progressions - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-12
**Phase:** 06-shared-harmony-progressions
**Areas discussed:** Arp under new chords, Progression mood & pace, Auto behaviour, Bass & pad feel

---

## Arp under new chords

**Q: New progression, Melody still classic: what does the arp do?**

| Option | Description | Selected |
|--------|-------------|----------|
| Follow chords | Engine moves the classic arp shape onto each chord; identical under classic | ✓ |
| Keep old notes | Arp keeps A–C–E–C whatever the chords; clashes on some chords | |
| New arp file only | New melody file follows chords; classic melody stays fixed | |

**Q: Do classic_lead / classic_lead_loud follow too?**

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, same rule | Any A-minor arp/lead gets mapped onto the current chord | ✓ |
| Only the arp | Lead files keep fixed notes until Phase 8 | |

**Q: Change arp rhythm/pattern now, or only notes?**

| Option | Description | Selected |
|--------|-------------|----------|
| Notes only | Same 16th shape; new patterns in Phase 8 | ✓ |
| Add some variety now | Progressions bring their own arp shape | |

---

## Progression mood & pace

**Q: Mood mix**

| Option | Description | Selected |
|--------|-------------|----------|
| Broad trance mix | Mostly uplifting/driving plus one deep and one dark | ✓ |
| Mostly uplifting | Bright euphoric progressions | |
| Mostly dark/hypnotic | Melodic-techno, moodier | |

**Q: Chord pace**

| Option | Description | Selected |
|--------|-------------|----------|
| Mixed per file | Driving files every bar, deep ones every 2 bars | ✓ |
| Every bar | 4-bar cycles | |
| Every 2 bars | 8-bar cycles | |

**Q: Include an out-of-key progression (Drama, E major with G#)?**

| Option | Description | Selected |
|--------|-------------|----------|
| Not yet | Stay inside A minor; Drama later as a new file | |
| Yes, include Drama | Ship it now; Phase 8 lead needs per-chord scales | ✓ |

**Q: Key**

| Option | Description | Selected |
|--------|-------------|----------|
| All in A | Files key-relative, engine plays in A | ✓ |
| Files may choose a key | More variety, possible key jumps | |

---

## Auto behaviour

**Q: How long per progression on Auto?**

| Option | Description | Selected |
|--------|-------------|----------|
| About 2–3 minutes | A few cycles, switch at cycle end | ✓ |
| About 1 minute | More variety, less hypnotic | |
| About 5 minutes | One "track" per progression | |

**Q: Classic and Auto**

| Option | Description | Selected |
|--------|-------------|----------|
| Start classic, then rotate | Classic opens, stays in the rotation | ✓ |
| Never classic on Auto | Classic only when picked | |
| Random from the start | Any progression right away | |

**Q: Auto order**

| Option | Description | Selected |
|--------|-------------|----------|
| Shuffle, no quick repeats | Random, never current or last couple | ✓ |
| Fixed order | Same sequence each time | |
| Fully random | Repeats allowed | |

**Q: How the rider knows what's playing**

| Option | Description | Selected |
|--------|-------------|----------|
| Post-window line | Name + chords printed at each switch | ✓ |
| Not needed | No extra logging | |

---

## Bass & pad feel

**Q: Bass under new progressions**

| Option | Description | Selected |
|--------|-------------|----------|
| v1 rhythm on the chord root | Same offbeat eighths, following roots | ✓ |
| Each file sets its bass | Per-file bass rhythms | |

**Q: Bass pickup note**

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, toward next chord | Last eighth before a change leads to the next chord | ✓ |
| No, root only | Plain roots all bar | |

**Q: Pad behaviour**

| Option | Description | Selected |
|--------|-------------|----------|
| Hold each chord, smooth moves | Sustain for the chord's length, nearest voicing | ✓ |
| Re-strike every bar | Re-attack each bar | |

---

## Claude's Discretion

- Progression file data shape (chord data vs generators), handling of the frozen chord-less `classic.scd`
- The note-to-chord mapping rule for arp/lead, including passing tones
- Same-beat ordering spike; cycle-end switching mechanics and the auto/`~ppSelect` interaction
- File names and exact Auto timing/jitter

## Deferred Ideas

- Files choosing their own key (HARM-05 key lifts stay deferred)
- Per-progression arp shapes / bass rhythms (Phases 7–9)
