---
phase: 05
review: 05-REVIEW.md
titles: json
findings:
  - id: WR-01
    severity: warning
    disposition: open
    title: "A lost send leaves the dropdown out of sync with the engine, and the same pick cannot be retried"
  - id: WR-02
    severity: warning
    disposition: open
    title: "A listener exception skips the send and leaves state half-applied"
  - id: WR-03
    severity: warning
    disposition: open
    title: "`test_main_launch` opens a real, visible window and steals focus (twice per run)"
  - id: IN-01
    severity: info
    disposition: open
    title: "Redundant `.startswith(\".\")` check in `scan_library`"
  - id: IN-02
    severity: info
    disposition: open
    title: "Duplicate helper in `test_view_tk.py`"
  - id: IN-03
    severity: info
    disposition: open
    title: "Fragile layout assertion"
  - id: IN-04
    severity: info
    disposition: open
    title: "README is stale and contradicts the no-edit rule"
open: 7
total: 7
recorded: 2026-10-12T12:20:46.000Z
---

# Phase 05: Code Review Disposition

| Finding | Severity | Disposition | Source |
|---------|----------|-------------|--------|
| WR-01 | warning | open | - |
| WR-02 | warning | open | - |
| WR-03 | warning | open | - |
| IN-01 | info | open | - |
| IN-02 | info | open | - |
| IN-03 | info | open | - |
| IN-04 | info | open | - |

Dispositions: `open` (recorded, not yet triaged), `fixed`, `skipped`, `deferred`.
Set `deferred` by hand and put the reason in the Source cell; both are preserved. A `|` in the reason is kept as prose and escaped on the next run.
