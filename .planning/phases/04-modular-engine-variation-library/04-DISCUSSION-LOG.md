# Phase 4: Modular Engine & Variation Library - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-11
**Phase:** 04-modular-engine-variation-library
**Areas discussed:** 'Sounds like v1.0' bar

(Areas offered but not selected: How 'reload' works, Broken-file fallback, Never-overwrite guard. Claude decides these; see CONTEXT.md.)

---

## 'Sounds like v1.0' bar

### How to prove parity

| Option | Description | Selected |
|--------|-------------|----------|
| Auto check + your ear (Recommended) | Note-level comparison against recorded v1.0 events, plus a short listening check | ✓ |
| Your ear only | Manual listening only | |
| Auto check only | No listening step | |

### The 7th lead layer in this phase

| Option | Description | Selected |
|--------|-------------|----------|
| Present but silent (Recommended) | Wired, plays nothing | |
| Not added yet | Keep 6 layers; Phase 8 adds it | |
| Quietly doubles the arp | Arp line an octave up, very low | ✓ |

### Where the doubling lead lives

| Option | Description | Selected |
|--------|-------------|----------|
| Separate melody file (Recommended) | `classic` stays pure v1.0 (silent lead); `classic_lead` adds the doubling | ✓ |
| Inside 'classic' | `classic` includes the faint lead | |

### Startup melody

| Option | Description | Selected |
|--------|-------------|----------|
| classic_lead at start | Lead audible right away | |
| classic at start (Recommended) | Startup sounds exactly like v1.0; pick classic_lead over OSC | ✓ |

### Lead level

| Option | Description | Selected |
|--------|-------------|----------|
| Faint, just adds shimmer (Recommended) | Well below the arp | ✓ |
| Clearly audible | About arp level | |
| You decide | Tune at listening check | |

**Notes:** The user chose an audible lead, then a separate file and `classic` at startup. Together these keep success criterion 1 intact (default startup is exactly v1.0) while giving the first non-classic file to test selecting by name.

---

## Claude's Discretion

- Reload semantics: re-select re-reads from disk; no separate reload address; changes apply on a bar boundary
- Broken-file fallback: keep the last good copy, else `classic`; the post-window error names the file
- Never-overwrite guard: the library check fails on a modified, git-committed library file
- Exact `classic_lead` level: tuned by ear

## Deferred Ideas

None.
