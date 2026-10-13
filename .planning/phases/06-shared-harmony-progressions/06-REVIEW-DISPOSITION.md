---
phase: 06
review: 06-REVIEW.md
titles: json
findings:
  - id: WR-01
    severity: warning
    disposition: fixed
    title: "Registry Events treat the stems `parent` and `proto` as prototypes, not entries"
  - id: WR-02
    severity: warning
    disposition: fixed
    title: "Every Start replays the identical Auto order"
  - id: WR-03
    severity: warning
    disposition: fixed
    title: "`~ppAutoPrefetching` is reset on every load of loader.scd"
  - id: WR-04
    severity: warning
    disposition: fixed
    title: "The library guard only compares the working tree with HEAD"
  - id: IN-01
    severity: info
    disposition: open
    title: "Doc/code drift in the README and the progression template"
  - id: IN-02
    severity: info
    disposition: open
    title: "`~ppAutoHistoryCap` is not retunable"
  - id: IN-03
    severity: info
    disposition: open
    title: "The voicing Array is shared by reference"
  - id: IN-04
    severity: info
    disposition: open
    title: "Test and gate timing"
open: 4
total: 8
recorded: 2026-10-13T06:35:06.552Z
---

# Phase 06: Code Review Disposition

| Finding | Severity | Disposition | Source |
|---------|----------|-------------|--------|
| WR-01 | warning | fixed | 06-REVIEW-FIX.md |
| WR-02 | warning | fixed | 06-REVIEW-FIX.md |
| WR-03 | warning | fixed | 06-REVIEW-FIX.md |
| WR-04 | warning | fixed | 06-REVIEW-FIX.md |
| IN-01 | info | open | - |
| IN-02 | info | open | - |
| IN-03 | info | open | - |
| IN-04 | info | open | - |

Dispositions: `open` (recorded, not yet triaged), `fixed`, `skipped`, `deferred`.
Set `deferred` by hand and put the reason in the Source cell; both are preserved. A `|` in the reason is kept as prose and escaped on the next run.
Re-running the gate keeps every row it can. A row the current review no longer reports is kept and its Source cell flagged, so a finding does not leave this record silently. ONE exception: when a finding id is REUSED by a different finding, the earlier decision cannot keep a row — the id is taken — and it is dropped. A RECORDED decision (anything but `open`) is named on the console when that happens; a row still at `open` is replaced silently, because `open` records no decision to lose.
