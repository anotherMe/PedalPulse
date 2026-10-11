---
phase: "04"
slug: "modular-engine-variation-library"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-10-11"
---

# Phase 04 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from `04-RESEARCH.md` § Validation Architecture. Paths below are the research-proposed layout. If the plans settle on a different layout, the plans are authoritative and validate-phase reconciles this file.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Headless sclang scripts (`CHECK OK` / `SMOKE FAIL` / `LIBRARY FAIL` line protocol) wrapped by bash; existing `scripts/smoke_test.sh` → `supercollider/smoke_test.scd` (isolated muted server, port 57140); new `supercollider/library_test.scd` (own watchdog, isolated port 57141). pytest 8.x for the Python side (unchanged, 150 pass) |
| **Config file** | none — `scripts/smoke_test.sh` exists; Wave 0 adds `scripts/library_check.sh` and `scripts/check.sh` |
| **Quick run command** | `bash scripts/library_check.sh` (loader/library work) or `bash scripts/smoke_test.sh` (`main.scd` work) |
| **Full suite command** | `bash scripts/check.sh` (git guard → library check → existing smoke) and `.venv/bin/python -m pytest -q` |
| **Estimated runtime** | ~30–45 s (library check), ~144 s (smoke: 67 checks measured at 2:24 wall during research; STATE.md's "~75 s" is stale), ~3 min total for `check.sh`; pytest ~5 s |

Do not set `QT_QPA_PLATFORM=offscreen`. The offscreen Qt plugin is missing from the SuperCollider 3.14.1 macOS bundle and aborts sclang. `scripts/smoke_test.sh` already unsets it, and the new wrappers must do the same. The smoke in-test watchdog is 300 s (`smoke_test.scd:28`) and the shell timeout 330 s; keep heavy new work in `library_test.scd` and add only the ENG-05 block (~10 s) to the smoke file. Tests never address ports 57110/57120 explicitly, so a running user engine is never disturbed.

---

## Sampling Rate

- **After every task commit:** Run the relevant script only: `bash scripts/library_check.sh` for loader/library work, `bash scripts/smoke_test.sh` for `main.scd` work
- **After every plan wave:** Run `bash scripts/check.sh` (once it exists; before that, `bash scripts/smoke_test.sh`)
- **Before `/gsd-verify-work`:** `bash scripts/check.sh` green, pytest green, then the user listening check (D-01)
- **Max feedback latency:** ~45 s for the per-task library check. The full smoke run (~144 s) exceeds this because the existing glide and peak checks wait out real lag windows; that is a sampling-cost note, not a coverage gap (same as Phases 2–3)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

Requirement-level test map (from research, pending task assignment):

| Requirement | Behavior | Test Type | Automated Command | File Exists |
|-------------|----------|-----------|-------------------|-------------|
| LIB-01 | All-`classic` startup emits the v1.0 events (note-level parity against a golden recorded from the unmodified v1.0 `main.scd`); existing smoke checks stay green | parity + regression | `bash scripts/library_check.sh` (parity block); `bash scripts/smoke_test.sh` | ❌ W0 (golden, `library_test.scd`); smoke ✅ |
| LIB-02 | Every file known by its stem; `progressions/`, `melodies/`, `palettes/` exist, each with `classic.scd`; per-file `LIBCHECK OK` count matches the file count on disk | static | `bash scripts/library_check.sh` | ❌ W0/W1 |
| LIB-03 | Modifying or deleting a library file already committed in git fails the check (HEAD diff); new uncommitted files pass | shell + self-test | `bash scripts/library_check.sh` (git guard + guard self-test) | ❌ W0 |
| LIB-04 | Broken / invalid / unknown / hostile names (`../x`, empty, number, `auto`-reserved rules) are refused, the error names the file, music keeps playing (event counts keep rising) | integration | `bash scripts/library_check.sh` (selection/fallback block) | ❌ W3 |
| LIB-05 | A file added or changed while playing is selectable by name over OSC (or reloaded by re-sending its name), applied on a bar line, with no missing 16th across the switch | integration | `bash scripts/library_check.sh` (selection block) | ❌ W3 |
| LIB-06 | Every library file validates (loads, returns an Event, right shape, no side effects); palette voices write through the mix bus/limiter, obey gate and `doneAction: 2`; three negative controls fail as expected | static + server | `bash scripts/library_check.sh` | ❌ W1/W3 |
| ENG-05 | Three re-evaluations of `main.scd` plus a module re-evaluation leave identical counts (`Pdef.all.keys`, `TempoClock.all.size`, clock-queue `EventStreamPlayer`/`Routine` counts, `s.numGroups`, `s.numSynthDefs`, `OSCdef.all.size`); Stop empties the instrument group, including the lead under `classic_lead` | smoke | `bash scripts/smoke_test.sh` (new ENG-05 block) | ❌ W3 (extends existing file) |

---

## Wave 0 Requirements

- [ ] `supercollider/golden/v1_events.scd` — recorded from the **unmodified** v1.0 `main.scd` before any split edit (covers LIB-01); a re-record must give an identical md5
- [ ] `supercollider/library_test.scd` — recorder (`\ppRecord` Event type) and parity-compare helpers first; other blocks added per wave (LIB-01..06)
- [ ] `scripts/library_check.sh` — wrapper with the git never-overwrite guard and its self-test fixture (LIB-03), plus the `LIBCHECK OK` count cross-check
- [ ] `scripts/check.sh` — one command: guard → library check → existing smoke suite
- [ ] Framework install: none (SuperCollider 3.14.1, git, `timeout`, `.venv` python-osc all present)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Default startup sounds exactly like v1.0 | LIB-01 (D-01) | D-01 requires a short listening check by the user in addition to the automated note-level parity; perceived sound cannot be fully asserted headlessly | Start the engine from `main.scd` as before, play with the GUI (BPM glide, Start/Stop, EPIC zones, volume); confirm the groove is unchanged from v1.0 |
| `classic_lead` reads as faint shimmer, not a new part | LIB-05 (D-06) | The lead level is tuned by ear (start roughly −12 dB under the arp) | While playing, send `/pp/melody classic_lead` with the documented one-liner; listen for an octave-up doubling of the arp that thickens it without standing out; send `/pp/melody classic` and confirm the exact v1.0 sound returns |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s for the per-task library check (full smoke ~144 s noted above)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
