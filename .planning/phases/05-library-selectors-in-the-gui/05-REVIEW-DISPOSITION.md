---
phase: 05
review: 05-REVIEW.md
titles: json
findings:
  - id: IN-01
    severity: info
    disposition: open
    title: "README says the `desc` line is \"at the top\" of every file, but it is not"
  - id: IN-02
    severity: info
    disposition: open
    title: "`--exit-after` with a negative value is silently ignored unless `--hidden` is given"
  - id: IN-03
    severity: info
    disposition: open
    title: "README one-liners hard-code `.venv/bin/python` and port 57120"
  - id: WR-01
    severity: warning
    disposition: fixed
    title: "README lists the library contents incorrectly"
  - id: WR-02
    severity: warning
    disposition: fixed
    title: "`--hidden` without `--exit-after` starts an app nobody can see or close"
  - id: IN-04
    severity: info
    disposition: open
    title: "Launch test hard-codes default values and has fragile skip logic"
  - id: WR-03
    severity: warning
    disposition: fixed
    title: "`test_main_launch` opens a real, visible window and steals focus (twice per run)"
open: 4
total: 7
recorded: 2026-10-12T13:46:09.246Z
---

# Phase 05: Code Review Disposition

| Finding | Severity | Disposition | Source |
|---------|----------|-------------|--------|
| IN-01 | info | open | - |
| IN-02 | info | open | - |
| IN-03 | info | open | - |
| WR-01 | warning | fixed | 05-REVIEW-FIX.md (not in the current review) |
| WR-02 | warning | fixed | 05-REVIEW-FIX.md (not in the current review) |
| IN-04 | info | open | - (not in the current review) |
| WR-03 | warning | fixed | 05-REVIEW-FIX.md (not in the current review) |

Dispositions: `open` (recorded, not yet triaged), `fixed`, `skipped`, `deferred`.
Set `deferred` by hand and put the reason in the Source cell; both are preserved. A `|` in the reason is kept as prose and escaped on the next run.
Re-running the gate keeps every row it can. A row the current review no longer reports is kept and its Source cell flagged, so a finding does not leave this record silently. ONE exception: when a finding id is REUSED by a different finding, the earlier decision cannot keep a row — the id is taken — and it is dropped. A RECORDED decision (anything but `open`) is named on the console when that happens; a row still at `open` is replaced silently, because `open` records no decision to lose.
