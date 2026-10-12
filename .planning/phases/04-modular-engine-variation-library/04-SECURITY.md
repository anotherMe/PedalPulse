---
phase: "04"
slug: "modular-engine-variation-library"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-12"
---

# Phase 04 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| OSC → sclang (port 57120) | `/pp/progression`, `/pp/palette`, `/pp/melody` select a library file by name | Short name strings; loopback-only (`srcID` 127.0.0.1) |
| Library files → engine | `.scd` files under `supercollider/library/` are executed by the loader | sclang code committed to this repo (by Claude); not a primary trust boundary |
| Test harness → audio | `library_test.scd` / `smoke_test.scd` run beside a possibly live engine | Isolated muted servers (57141 / 57140); never 57110 or 57120 |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-04-01 | Tampering | `~ppLibLoad` executing library files | medium | mitigate | Paths built from fixed `~ppLibCategories` + stem; loads in `try`; ERROR names the file (`core/loader.scd`) | closed |
| T-04-02 | Tampering | Silent overwrite of a committed library file or the golden | medium | mitigate | `scripts/check.sh` guard (`git diff --name-status --no-renames HEAD`) + temp-repo self-test; golden record mode refuses overwrite. Note: review WR-03 (bypass by committing, fail-open on git error) deferred as hardening | closed |
| T-04-03 | Denial of Service | Test runs disturbing the rider's engine | medium | mitigate | `library_test.scd` uses its own muted server on 57141; 57110/57120 appear only in comments | closed |
| T-04-04 | Spoofing | `\pp_progression`, `\pp_palette`, `\pp_melody` OSCdefs | medium | mitigate | 7 `srcID: NetAddr("127.0.0.1", nil)` guards in `main.scd` | closed |
| T-04-05 | Tampering / EoP | Path traversal via selection name | high | mitigate | `~ppStemValid` character loop, `~ppLibContained` realpath containment; test "invalid names ignored" sends `../x`, newline, `_template`, `../../main` | closed |
| T-04-06 | Denial of Service | Loading / `s.sync` inside the OSC responder | medium | mitigate | Responder validates and starts a Routine on SystemClock; latest-wins token | closed |
| T-04-07 | Denial of Service | Flood of selection messages | low | accept | Loopback only; small file reads; latest wins | closed |
| T-04-08 | Denial of Service | Broken/invalid library file stopping the music | high | mitigate | `try` around load/defs/init/generators; `~ppValidate`/`~ppValidateVoices` before registry put; per-bar classic fallback; revert after 3 errors; tested. Note: review WR-01/WR-02 (no upper bounds; refused palette leaves SynthDefs) deferred by rider in 04-UAT | closed |
| T-04-09 | Denial of Service | Generator that loops forever | medium | accept | Cannot be pre-empted in sclang; static tier calls every generator under a watchdog before a ride | closed |
| T-04-10 | Repudiation | Errors not naming the failing file | low | mitigate | Every refusal/fallback ERROR line carries the absolute path; tests assert it | closed |
| T-04-11 | Denial of Service | Unbounded log/error memory on a long ride | low | mitigate | `~ppLogLines` capped at 100; one `~ppRenderErrors` counter per file, reset on reload | closed |
| T-04-12 | Tampering | Library file with load-time side effects / shelling out | medium | mitigate | Static-tier lint (unixCmd, systemCmd, File, Pipe, Synth(, .play, ~) + no-new-keys check; negative controls `side_effect`, `forbidden_call` | closed |
| T-04-13 | Tampering (hearing safety) | Palette voice on bus 0 or ignoring gate/doneAction | high | mitigate | Voice tier on bare server; controls `\ppBadBus0`, `\ppBadNoDone`, `\ppBadNoGate` each caught | closed |
| T-04-14 | Repudiation | Library file silently skipped by the check | medium | mitigate | `check.sh` compares `LIBCHECK OK` count with `.scd` files on disk | closed |
| T-04-15 | Denial of Service | Re-evaluation stacking routines/players/nodes | medium | mitigate | `eng-05 no stacking` and `eng-05 module re-evaluation` pin counts | closed |
| T-04-16 | Denial of Service (hearing safety) | Stop failing to silence the lead | medium | mitigate | `stop silences every layer` with a lead playing | closed |
| T-04-SC | Tampering | Package installs | low | accept | No pip, npm or quark installs in this phase | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-04-01 | T-04-07 | Loopback-only OSC; each request is one small file read and stale loads are discarded | Plan 04-03 threat model | 2026-10-11 |
| AR-04-02 | T-04-09 | sclang cannot pre-empt a hung generator; library files are committed by Claude and checked by the static tier's watchdog before a ride | Plan 04-04 threat model | 2026-10-11 |
| AR-04-03 | T-04-SC | No packages installed in this phase | Plans 04-01..06 threat models | 2026-10-11 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-12 | 17 | 17 | 0 | /gsd-secure-phase (L1 grep-level, orchestrator) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-12
