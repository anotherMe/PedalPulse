---
phase: "06"
slug: "shared-harmony-progressions"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-13"
---

# Phase 06 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Library files on disk -> sclang loader | A progression file is code run by String:load, then validated; its chord data drives the per-bar harmony path | Chord-data literals (low) |
| Loopback OSC -> ~ppSelect | `/pp/progression <name>` (including `auto`) from 127.0.0.1 only; name rule and containment unchanged from Phase 4 | OSC string on 127.0.0.1 (low) |
| Progressions folder -> Auto prefetch | Any file dropped into the folder is scanned and may be loaded while the music plays | File names and contents (low) |
| Test fixtures / smoke harness -> isolated engine | Hostile fixtures live only in a temporary root; the smoke suite drives its own muted server on port 57140 | Test data (none) |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-06-01 | Denial of service | chord validation / per-bar harmony path | medium | mitigate | Chord count and cycle capped at 16 (`core/validate.scd:57`, `:87`); harmony lookups run under `try` (`core/harmony.scd:285`, `:301`) with classic fallback | closed |
| T-06-02 | Denial of service | ~ppHarm memo over a long ride | medium | mitigate | `~ppHarmKeepBars` 64 and `~ppHarmLogCap` 256 (`core/harmony.scd:46-47`); no backfill past a gap (`core/harmony.scd:328`) | closed |
| T-06-03 | Tampering | ~ppSelect for /pp/progression | low | accept | Phase 4 controls unchanged: loopback srcID (`main.scd:342`), `~ppStemValid` (`core/loader.scd:43`), `~ppLibContained` (`core/loader.scd:63`) | closed |
| T-06-04 | Denial of service | validation against hostile chord data | medium | mitigate | Negative fixtures with exact reasons in `library_test.scd:780-782` and siblings | closed |
| T-06-05 | Tampering | test isolation | low | mitigate | Fixtures in the pedalpulse-statictest- temp root removed by `cleanupTmp` (`library_test.scd:214`) | closed |
| T-06-06 | Tampering | library/progressions/*.scd | low | mitigate | Static-tier forbidden-token lint (`library_test.scd:475`); library guard in `scripts/check.sh` | closed |
| T-06-07 | Tampering | ~ppAutoPrefetch folder scan | medium | mitigate | Name rule before any path, load only via `~ppLibEnsure`, 256-file cap (`core/loader.scd:176-201`) | closed |
| T-06-08 | Denial of service | Auto re-reading a broken file / log flood | medium | mitigate | `~ppAutoFailed` keyed by mtime, single-scan guard `~ppAutoPrefetching` (`core/loader.scd:182-199`); test "auto reports a broken file once" | closed |
| T-06-09 | Denial of service | progression failing under Auto | low | mitigate | Stem excluded after 3 render errors (`core/render.scd:136`); test "auto skips a failing progression" | closed |
| T-06-10 | Denial of service | Auto state over a long ride | low | mitigate | `~ppAutoHistoryCap` 8 (`core/harmony.scd:57`), prefetch on SystemClock (`core/loader.scd:219`); test "auto stays bounded" | closed |
| T-06-11 | Denial of service | Stop with a held multi-bar pad chord | medium | mitigate | Smoke check "progression stop and start" (`smoke_test.scd:2191`) | closed |
| T-06-12 | Denial of service | re-evaluation with non-classic/auto progression | medium | mitigate | Smoke check "progression re-evaluation" compares engine counts (`smoke_test.scd:2306`) | closed |
| T-06-SC | Tampering | package installs | low | accept | No pip, npm or quark installs in this phase | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-06-01 | T-06-03 | Selection path unchanged from Phase 4, whose controls were already verified; only log wording changed | planner (06-01-PLAN) | 2026-10-13 |
| AR-06-02 | T-06-SC | No packages installed; stock SuperCollider classes only | planner (06-0x-PLAN) | 2026-10-13 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-13 | 13 | 13 | 0 | gsd-secure-phase (L1 grep, orchestrator) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
