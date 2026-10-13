---
phase: "07"
slug: "sound-palettes"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-10-13"
---

# Phase 07 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from `07-RESEARCH.md` § Validation Architecture. Check names below are the research's proposals. If the plans settle on different names or a different layout, the plans are authoritative and validate-phase reconciles this file.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Headless sclang 3.14.1 scripts with a `CHECK OK` / `LIBRARY PASS` / `SMOKE PASS` line protocol (`supercollider/library_test.scd`, `supercollider/smoke_test.scd`), driven by `scripts/check.sh`. pytest 8.4.2 on the project `.venv` for the Python side, which this phase does not change |
| **Config file** | none (`scripts/check.sh`, `scripts/smoke_test.sh`) |
| **Quick run command** | `bash scripts/check.sh --library-only` |
| **Full suite command** | `bash scripts/check.sh` (library guard, library check, then the smoke suite) |
| **Single-palette authoring loop** | proposed `PP_PALETTE=<stem>` environment filter for the real-time level/CPU tier, so one palette can be tuned without the whole run |
| **Estimated runtime** | Quick command ~140 s at baseline (15 library files, `CHECK PASS (library only)`, 2:18 wall), about 4–5 min once the level/headroom/CPU tier and six palettes are in. The full suite adds the smoke run (~190 s baseline, 3:10 wall) |

sclang is not on PATH: `scripts/check.sh` uses `/Applications/SuperCollider.app/Contents/MacOS/sclang` (override with `SCLANG=...`). The library watchdog (`SystemClock.sched(300` in `library_test.scd`, `timeout 330` / `gtimeout 330` in `check.sh`) must be raised together once the real-time tier lands (research suggests about 480 / 510). The smoke run once printed `SMOKE PASS` and then crashed at sclang shutdown (`libc++abi: mutex lock failed`), and it contains a known flaky check (`epic glide up: PulseCount did not advance`, STATE.md). Rerun once before attributing a failure to Phase 7; if the exit crash repeats, route it to `/gsd-debug`.

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/check.sh --library-only` (use `PP_PALETTE=<stem>` while authoring one palette, then the full library tier before the commit)
- **After every plan wave:** Run `bash scripts/check.sh`
- **Before `/gsd-verify-work`:** Full suite must be green, `.venv/bin/python -m pytest -q` green with `python_app/` untouched, then the manual listening and Zwift-side CPU checks below
- **Max feedback latency:** ~300 s (quick command once the real-time tier is in)

---

## Per-Task Verification Map

Task-level rows are filled in once the phase plans exist. Until then, this is the requirement-level map from research.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | — | — | PAL-01 | — | — | static + voice + count | `bash scripts/check.sh --library-only` (`LIBCHECK OK: palettes/<stem>`, `CHECK OK: voices <stem>`, `CHECK OK: library file count (21 files)`) | ❌ W0 (new palette files) | ⬜ pending |
| TBD | — | — | PAL-01 | — | — | static (new) | `bash scripts/check.sh --library-only` (`CHECK OK: palettes are distinct`) | ❌ W0 | ⬜ pending |
| TBD | — | — | PAL-02 | — | — | integration (`recordBars`, instrument per bar, cycle log) | `bash scripts/check.sh --library-only` (`CHECK OK: auto palette rotates`, `... lands on a progression change`, `... with a locked progression`, `... no quick repeats`) | ❌ W0 | ⬜ pending |
| TBD | — | — | PAL-02 | — | — | integration | `bash scripts/check.sh --library-only` (`CHECK OK: auto palette replays from the seed`, `CHECK OK: auto palette hold survives stop and start`) | ❌ W0 | ⬜ pending |
| TBD | — | — | PAL-02 | — | failing / broken palette skipped and reported once; registry and SynthDef count bounded | integration | `bash scripts/check.sh --library-only` (`CHECK OK: auto adds a new palette file`, `CHECK OK: auto skips a failing palette`, `CHECK OK: auto palette stays bounded`) | ❌ W0 | ⬜ pending |
| TBD | — | — | PAL-03 | — | — | integration | `bash scripts/check.sh --library-only` (`CHECK OK: named palette locks`, `CHECK OK: named palette plays from the next bar`) | ❌ W0 | ⬜ pending |
| TBD | — | — | PAL-03 | — | invalid names still ignored | integration (modified) | `bash scripts/check.sh --library-only` (`CHECK OK: auto plays classic` limited to melody + progression, `CHECK OK: select palette and progression`, `CHECK OK: invalid names ignored`, `CHECK OK: latest wins`) | ✅ (edit) | ⬜ pending |
| TBD | — | — | PAL-04 | — | — | real-time tier (new) | `bash scripts/check.sh --library-only` (`PedalPulse libtest: palette level <stem> gap=<x> dB`, `CHECK OK: palette level <stem>`) | ❌ W0 | ⬜ pending |
| TBD | — | — | PAL-04 | — | nothing bypasses the limiter; no clip at VO2 / volume 100 | real-time tier + smoke | `bash scripts/check.sh` (`CHECK OK: palette headroom <stem>`, smoke `CHECK OK: palette max epic max volume no clip`, existing `CHECK OK: limiter no bypass`) | ❌ W0 / ✅ (extend) | ⬜ pending |
| TBD | — | — | PAL-04 | — | — | real-time tier (optional) | `bash scripts/check.sh --library-only` (`CHECK OK: palette switch no jump`) | ❌ W0 | ⬜ pending |
| TBD | — | — | D-02 | — | unknown `bassStyle` refused by the validator | integration | `bash scripts/check.sh --library-only` (`CHECK OK: bass styles follow the chord`, `CHECK OK: classic bass unchanged under every palette`, `CHECK OK: parity`) | partly (extend) | ⬜ pending |
| TBD | — | — | D-16 / WR-01 | — | row magnitude bounds enforced | unit + negative cases | `bash scripts/check.sh --library-only` (`CHECK OK: rows validation`, `CHECK OK: shipped rows within bounds`) | ✅ (edit) | ⬜ pending |
| TBD | — | — | D-16 / WR-02 | — | foreign-voice redefinition refused; refused palette leaves no voices; classic voices restored | integration with fixtures | `bash scripts/check.sh --library-only` (`CHECK OK: palette defs stay in their prefix`, `CHECK OK: refused palette leaves no voices`) | ❌ W0 (new fixtures) | ⬜ pending |
| TBD | — | — | Exit gate | — | Stop silences every layer; no leaked routines, nodes or SynthDefs | smoke | `bash scripts/check.sh` (`CHECK OK: stop silences every layer`, `CHECK OK: eng-05 no stacking`, `CHECK OK: eng-05 module re-evaluation`, new `CHECK OK: palette stop and start`, `CHECK OK: palette rotation leaks nothing`) | ✅ (extend) | ⬜ pending |
| TBD | — | — | D-14 / D-15 | — | — | real-time tier + script | `bash scripts/check.sh --library-only` (`CHECK OK: palette cpu <stem>` or `CHECK WARN: palette cpu <stem> ...`); `scripts/palette_cpu.sh` prints mean/peak and exits 0 under 25% | ❌ W0 | ⬜ pending |
| TBD | — | — | Python untouched | — | — | regression | `.venv/bin/python -m pytest -q` and `git diff --stat -- python_app` empty | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Level / headroom / CPU real-time tier in `supercollider/library_test.scd` (RMS probe, per-palette loop, `PP_PALETTE` filter), with the library watchdog and the `check.sh` timeout raised together
- [ ] Auto palette test tier (rotation, landing on a progression change, locked progression, named lock, replay from the seed, bounded state, new file, failing file) with a small tunable palette hold
- [ ] WR-01 negative cases and WR-02 fixtures (a palette redefining a classic voice such as `\ppArp`; a palette whose `defs` throws after adding a voice) in `library_test.scd`
- [ ] `auto plays classic` updated to cover melody + progression only (palette `auto` no longer means classic)
- [ ] `supercollider/palette_cpu.scd` + `scripts/palette_cpu.sh` (one command, heaviest palette at VO2 for about 1 minute, prints mean and peak CPU)
- [ ] Smoke additions: Stop under a non-classic palette, rotation leak check, VO2 no-clip for the loudest palette
- [ ] `palettes/_template.scd` and `library/README.md` updates (`bassStyle`, the prefix rule, the level-tuning loop, Auto behaviour)
- [ ] A listening UAT script (plain-language palette names and what each should sound like), like Phase 6's

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| No palette jumps or hides when switching | PAL-04 (D-13) | The numeric RMS gate approximates perceived loudness; only the rider's ears confirm it | On Auto with the real GUI, then by name, switch between every palette at a low and a high EPIC and at the usual volume. Record in plain words which palette sounded louder or quieter |
| Each palette is recognisably different in the full mix | PAL-01 | The headless suite cannot judge "sounds different" (a faint, 12 dB-down change was inaudible in Phase 4) | Name each palette from the post-window line (`palette <name>: <desc>`) and say whether it can be told apart from the others |
| VO2 at volume 100 on the loudest palette sounds clean | PAL-04 | Listening confirmation of the numeric peak gate (no distortion or pumping) | Lock the loudest palette, set VO2 and volume 100, listen for a minute |
| Auto rotation feel | PAL-02 | Real-time behaviour over many minutes at the rider's own tempo | Ride or listen ~15 minutes on Auto at the usual BPM: changes land on a chord-chapter change, every few minutes, and the first palette after Start is not always `classic`. Note the BPM used |
| CPU next to Zwift | D-14 / D-15 | Needs Zwift running on the riding Mac | Run `scripts/palette_cpu.sh` once with Zwift open (no ride needed) and report mean and peak; pass if mean is under 25% |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 300s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
