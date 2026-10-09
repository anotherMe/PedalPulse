---
phase: 01
review: 01-REVIEW.md
titles: json
findings:
  - id: WR-01
    severity: warning
    disposition: open
    title: "Global arrow-key bindings silently clobber in-progress text in the BPM Entry field"
  - id: IN-01
    severity: info
    disposition: open
    title: "`BpmWindow.__init__` is a single ~98-line method building the entire UI"
  - id: CR-01
    severity: critical
    disposition: fixed
    title: "`set -e` silently defeats the smoke-test script's failure diagnostics"
  - id: WR-02
    severity: warning
    disposition: fixed
    title: "Forced-but-unchanged entry commit leaves the Entry text un-normalized"
  - id: IN-02
    severity: info
    disposition: open
    title: "`run.sh --setup` prints \"venv ready\" before the compatibility check that can still fail"
open: 3
total: 5
recorded: 2026-10-09T07:41:14.520Z
---

# Phase 01: Code Review Disposition

| Finding | Severity | Disposition | Source |
|---------|----------|-------------|--------|
| WR-01 | warning | open | - |
| IN-01 | info | open | - |
| CR-01 | critical | fixed | 01-REVIEW-FIX.md (not in the current review) |
| WR-02 | warning | fixed | 01-REVIEW-FIX.md (not in the current review) |
| IN-02 | info | open | - (not in the current review) |

Dispositions: `open` (recorded, not yet triaged), `fixed`, `skipped`, `deferred`.
Set `deferred` by hand and put the reason in the Source cell; both are preserved. A `|` in the reason is kept as prose and escaped on the next run.
Re-running the gate keeps every row it can. A row the current review no longer reports is kept and its Source cell flagged, so a finding does not leave this record silently. ONE exception: when a finding id is REUSED by a different finding, the earlier decision cannot keep a row — the id is taken — and it is dropped. A RECORDED decision (anything but `open`) is named on the console when that happens; a row still at `open` is replaced silently, because `open` records no decision to lose.
