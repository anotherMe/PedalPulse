---
phase: "07"
slug: "sound-palettes"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-20"
---

# Phase 07 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Library palette files -> scsynth | A palette's `defs` add SynthDefs that run on the server for every note; the static prefix rule and the `~ppPaletteDefs` guard decide what a file may define | SynthDef names and graphs (low) |
| Library files -> renderer | Generator rows from progression and melody files are played as events on the shared clock, bounded by `~ppRowsValid` | Row data (low) |
| Palette file key `bassStyle` -> core renderer | A data value selects which core function writes the bass rows | One Symbol from a fixed list (low) |
| Palettes folder -> Auto prefetch | Any file dropped into `supercollider/library/palettes/` is scanned and may be loaded while the music plays | File names and contents (low) |
| Loopback OSC -> `~ppSelect` | `/pp/palette <name>` (including `auto`) from 127.0.0.1 only; name rule and containment unchanged from Phase 4 | OSC string on 127.0.0.1 (low) |
| Meter, CPU script and smoke harness -> isolated engines | `palette_meter.scd` (via `palette_level.sh` / `palette_cpu.sh`) boots its own muted server on port 57142; the smoke suite uses 57140; each sends OSC only to its own language port | Test data (none) |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-07-01 | Denial of service | palette_meter.scd and palette_level.sh next to a live engine | medium | mitigate | Own server on port 57142 (`palette_meter.scd:100`), OSC only to its own `NetAddr.langPort` (`:127`), muted (`:284`); shell stem rule `^[a-z0-9_]{1,64}$` (`scripts/palette_level.sh:28`) and `~ppStemValid` in the meter (`palette_meter.scd:316`, `:319`) | closed |
| T-07-02 | Elevation of privilege (safety gate) | a palette voice writing to bus 0 or ignoring gate | high | mitigate | Voice tier probes bus 0 for every palette voice and refuses "writes to bus 0 (bypasses the limiter)" (`library_test.scd:1414`, `:1495`); meter VO2 output ceiling 0.892 (`palette_meter.scd:400`); forbidden-token lint over library files (`library_test.scd:558-565`, negative fixture `:812`) | closed |
| T-07-03 | Denial of service | a hot or unstable palette (level jump, clipping, NaN on the shared FX chain) | medium | mitigate | Meter gates: level gap at most 1.5 dB (`palette_meter.scd:364`), post-FX peak at most 0.80 (`:399`), at most 40 synths (`:402`), CPU under 25% (`:405`), extreme notes finite and below 4.0 (`:445`); `scripts/check.sh:254` runs the meter over every palette on disk | closed |
| T-07-04 | Denial of service | `~ppRowsValid` accepting huge magnitudes | high | mitigate | `~ppRowsValid` (`core/validate.scd:130`): at most 64 rows checked before the loop (`:137`), notes -12..127 (`:133`), chord at most 8 notes (`:171`), dur at least 1/32 and legato at most 8 (`:124`); test "rows validation" | closed |
| T-07-05 | Tampering | a palette redefining classic's or another palette's voice | high | mitigate | Static `pp_<stem>_` prefix rule (`core/validate.scd:257`) plus the SynthDescLib snapshot-diff guard `~ppPaletteDefs` (`core/loader.scd:147`, called at `:250`); test "palette defs stay in their prefix" | closed |
| T-07-06 | Denial of service | refused palettes leaving SynthDefs behind | medium | mitigate | The guard's `undo` calls `SynthDef.removeAt` for every added name and restores replaced voices (`core/loader.scd:203-206`); tests "refused palette leaves no voices", "refused reload restores the last good voices" | closed |
| T-07-07 | Tampering | `bassStyle` value in a palette file | low | mitigate | Only `~ppBassStyleNames` Symbols accepted (`core/validate.scd:41`, refusal at `:272`); `~ppBassStyleFor` falls back to eighths (`core/harmony.scd:809-815`); test "bass styles follow the chord" | closed |
| T-07-08 | Denial of service | acid and dark levels, peaks, CPU, extreme notes | medium | mitigate | Same meter gates as T-07-03; `CHECK OK: palette level/headroom/cpu/extreme notes` for acid and dark on 2026-10-20 | closed |
| T-07-09 | Tampering | `~ppAutoPrefetch` palette scan | medium | mitigate | `~ppStemValid` before any path is built (`core/harmony.scd:231`, `:347`); load only through `~ppLibEnsure` (`core/loader.scd:241`, used at `:354`); at most 32 palette files per scan (`core/loader.scd:322`) | closed |
| T-07-10 | Denial of service | Auto re-reading a broken palette (log flood, repeated defs) | medium | mitigate | `~ppAutoFailed` keyed by path and mtime (`core/loader.scd:318`, `:351-352`); test "auto skips a broken palette" | closed |
| T-07-11 | Denial of service | palette Auto state and SynthDefs over a long ride | low | mitigate | `~ppAutoHistoryCap` 8 (`core/harmony.scd:64`), `~ppHarmLogCap` 256 and `~ppHarmKeepBars` 64 (`:53-54`); scan Routine on SystemClock (`core/loader.scd:379`); test "auto palette stays bounded" | closed |
| T-07-12 | Denial of service | CPU load next to Zwift (the heaviest palette at VO2) | medium | mitigate | Meter fails at 25% average and warns above 12% (`palette_meter.scd:405-406`); `scripts/palette_cpu.sh` CPU PASS headless on 2026-10-20 (supersaw mean 7.57%, peak 15.03%); the rider's run next to Zwift passed (07-UAT.md test 3) | closed |
| T-07-13 | Denial of service | palette_cpu.sh disturbing a live engine | low | mitigate | Header tells the rider to quit the engine first and documents the isolated port 57142 (`scripts/palette_cpu.sh:7`, `:15`); argument rule in the shell (`:33`) and again with `~ppStemValid` (`palette_meter.scd:316-319`) | closed |
| T-07-14 | Denial of service | pluck, warm, air levels, peaks, extreme notes | medium | mitigate | Same meter gates as T-07-03; `CHECK OK` meter lines for pluck, warm and air on 2026-10-20 | closed |
| T-07-15 | Denial of service | Stop with a non-classic palette (long pad releases, a palette's own drums) | medium | mitigate | Smoke check "palette stop and start" (`smoke_test.scd:2482`): instrument group empty within 2.5 s after Stop for every palette on disk (`:2558`) | closed |
| T-07-16 | Elevation of privilege (safety gate) | a palette voice reaching the output without the limiter | high | mitigate | Same smoke check sets the master pre-gain to 0 under every palette and requires bus 0 below 0.001 (`smoke_test.scd:2535-2540`); plus the voice tier (T-07-02) and the meter ceiling | closed |
| T-07-17 | Denial of service | re-evaluation with Palette on Auto stacking routines, nodes or SynthDefs | medium | mitigate | Smoke check "palette re-evaluation" (`smoke_test.scd:2602`) compares engine counts after re-evaluation (`:2645-2649`) | closed |
| T-07-SC | Tampering | package installs | low | accept | No pip, npm or quark installs in this phase | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-07-01 | T-07-SC | No packages installed; stock SuperCollider classes only (RESEARCH Package Legitimacy Audit: none) | planner (07-0x-PLAN) | 2026-10-13 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-20 | 18 | 18 | 0 | gsd-secure-phase (L1 grep, orchestrator; register authored at plan time) |

Evidence run: the full `bash scripts/check.sh` on 2026-10-20 (CHECK PASS) printed `CHECK OK` for every check named above. It ran with the 2.5x master boost from quick task 261015-uez in place. That task's own register (T-261015-uez-01..03: boost applied before the -1 dBFS limiter, file constant only with no OSC path, smoke config range 2.0-3.0) is covered by `CHECK OK: master boost` and the unchanged limiter checks in the same run.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-20
