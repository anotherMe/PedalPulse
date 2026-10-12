---
phase: "06"
slug: "shared-harmony-progressions"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-10-12"
---

# Phase 06 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Seeded from `06-RESEARCH.md` § Validation Architecture. Paths below are the research-proposed layout. If the plans settle on a different layout, the plans are authoritative and validate-phase reconciles this file.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Headless sclang 3.14.1 scripts with a `CHECK OK` / `LIBRARY PASS` / `SMOKE PASS` line protocol (`supercollider/library_test.scd`, `supercollider/smoke_test.scd`), driven by `scripts/check.sh`. pytest on the project `.venv` for the Python side, which this phase does not change |
| **Config file** | none (`scripts/check.sh`, `scripts/smoke_test.sh`) |
| **Quick run command** | `bash scripts/check.sh --library-only` |
| **Full suite command** | `bash scripts/check.sh` (library guard, library check, then the smoke suite) |
| **Estimated runtime** | ~68 s for the quick command at baseline (8 library files, `CHECK PASS (library only)`), longer once seven progression files and the chord-follow tier are added. The full suite adds the smoke run |

sclang is not on PATH: `scripts/check.sh` uses `/Applications/SuperCollider.app/Contents/MacOS/sclang` (override with `SCLANG=...`). The smoke suite contains a known flaky check (`epic glide up: PulseCount did not advance`, STATE.md). Rerun once before attributing a failure to Phase 6.

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/check.sh --library-only`
- **After every plan wave:** Run `bash scripts/check.sh`
- **Before `/gsd-verify-work`:** Full suite must be green, then the listening UAT of the seven files on Auto and by name
- **Max feedback latency:** ~90 s (quick command)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 06-01-T1 | 01 | 1 | HARM-01, HARM-03 | T-06-01, T-06-02 | malformed chord data refused at load; per-bar harmony under try | integration (recordBars) | `./scripts/check.sh --library-only` (CHECK OK: chord follow anthem, parity) | ❌ W0 created here | ⬜ pending |
| 06-01-T2 | 01 | 1 | HARM-04 | T-06-03 | unchanged loopback/name/containment controls | integration + smoke | `bash scripts/check.sh` (named progression switches at the cycle end) | ❌ W0 created here | ⬜ pending |
| 06-02-T1 | 02 | 2 | HARM-01, HARM-03 | — | — | unit (pure functions) | `./scripts/check.sh --library-only` (CHECK OK: harmony units) | ❌ W0 created here | ⬜ pending |
| 06-02-T2 | 02 | 2 | HARM-01, HARM-03 | T-06-04, T-06-05 | seven malformed fixtures refused with exact reasons | static + integration | `./scripts/check.sh --library-only` (static check catches bad files, chord follow <stem>) | ❌ W0 created here | ⬜ pending |
| 06-03-T1 | 03 | 3 | HARM-02, HARM-01 | T-06-06 | lint and side-effect checks on new files | static + integration | `./scripts/check.sh --library-only` (shipped progressions, 15 files) | ✅ after 06-02 | ⬜ pending |
| 06-03-T2 | 03 | 3 | HARM-02 | — | — | full gate + Python scan | `bash scripts/check.sh` and the scan_library one-liner | ✅ | ⬜ pending |
| 06-04-T1 | 04 | 4 | HARM-04, HARM-02 | T-06-07 | scan names pass ~ppStemValid, load only via ~ppLibEnsure | integration (TDD) | `./scripts/check.sh --library-only` (auto rotates progressions, auto adds a new progression file) | ❌ W0 created here | ⬜ pending |
| 06-04-T2 | 04 | 4 | HARM-04 | T-06-08, T-06-09, T-06-10 | broken file reported once; failing file excluded; bounded state | integration | `bash scripts/check.sh` (auto stays bounded, auto skips a failing progression, auto reports a broken file once) | ❌ W0 created here | ⬜ pending |
| 06-05-T1 | 05 | 5 | HARM-01 | T-06-11, T-06-12 | Stop releases held pads; re-evaluation stacks nothing | smoke | `bash scripts/check.sh` (progression stop and start, progression re-evaluation) | ❌ W0 created here | ⬜ pending |
| 06-05-T2 | 05 | 5 | HARM-01..04 | — | — | full gate + manual | `bash scripts/check.sh`, pytest; listening check in UAT | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

Requirement-level test map (from research, pending task assignment):

| Requirement | Behavior | Test Type | Automated Command | File Exists |
|-------------|----------|-----------|-------------------|-------------|
| HARM-01 | Every bass, arp, pad and lead pitch class is in its bar's chord, across a tempo glide and Stop/Start; classic stays byte-identical | integration (`recordBars`) | `bash scripts/check.sh --library-only` | ❌ W0: new chord-follow tier in `library_test.scd` |
| HARM-01 | All layers read the same harmony entry for a given bar (no mutable current chord) | unit/integration | `bash scripts/check.sh --library-only` | ❌ W0: pure `~ppHarmonyFor` tier |
| HARM-02 | Seven chord-data files plus `classic` validate, render valid rows and stay in chord | static | `bash scripts/check.sh --library-only` | ❌ W0: new static branch; files are new |
| HARM-03 | Pad voicing is the nearest to the previous chord (summed movement bounded) and is held for the whole chord | unit | `bash scripts/check.sh --library-only` | ❌ W0 |
| HARM-04 | A named pick lands only on a cycle boundary and stays; Auto starts on `classic`, rotates, avoids quick repeats and picks up a new file | integration | `bash scripts/check.sh --library-only` | ❌ W0 |
| Exit gate | Stop silences every layer; re-evaluation stacks nothing; smoke and library check pass with every progression file | smoke | `bash scripts/check.sh` | ✅ exists (extend) |
| Python untouched | The Progression dropdown lists the new stems | unit | `.venv/bin/python -m pytest -q python_app/tests/test_library_logic.py` | ✅ exists (no change expected) |

---

## Wave 0 Requirements

- [ ] `supercollider/core/harmony.scd` pure functions (chord expansion, chord follow, nearest voicing, bass pickup) with unit-style checks in `supercollider/library_test.scd`
- [ ] Chord-follow tier using `recordBars` plus the harmony entry for the expected chord per bar
- [ ] Negative controls for bad chord data (bad root, unknown quality, empty chords, too many chords, `bars` 0, cycle over the cap)
- [ ] Core module load lists updated in `supercollider/main.scd`, `supercollider/library_test.scd` and `supercollider/smoke_test.scd`
- [ ] Listening UAT script: a plain-language list of the seven progression names and what each should sound like

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Each named progression sounds clearly distinct from the others and from `classic` | HARM-02 | The headless suite cannot judge "sounds distinct"; Anthem, Rocker, Lift and Return share chord material | Pick each progression in the app, listen for at least two cycles, and name what you hear using the post-window line (`progression <name>: <chords>`) |
| Pad chord changes sound smooth (no jump) | HARM-03 | Smoothness is a listening judgement; the automated check only bounds voice movement | Listen to a 2-bar-chord progression and a 1-bar-chord progression; the pad should glide between chords, not leap |
| Auto rotates on its own every 2–3 minutes and always changes at a cycle end | HARM-04 | Real-time behaviour over minutes | Leave Progression on Auto for ~6 minutes and watch the post-window lines |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
