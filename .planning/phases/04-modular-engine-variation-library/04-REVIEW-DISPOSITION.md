---
phase: 04
review: 04-REVIEW.md
titles: json
findings:
  - id: WR-01
    severity: warning
    disposition: deferred
    title: "Row validation has no upper bounds (note range, legato, row count), so a \"valid\" bar can still disturb the engine"
  - id: WR-02
    severity: warning
    disposition: deferred
    title: "A refused (or fallen-back) palette leaves its SynthDefs behind, and the fallback to classic does not restore classic's voices"
  - id: WR-03
    severity: warning
    disposition: open
    title: "The immutability guard is bypassed by committing the edit, and it fails open when git errors"
  - id: WR-04
    severity: warning
    disposition: open
    title: "The documented `state` contract is wrong: arp and lead (and bass and pad) do not share a state"
  - id: WR-05
    severity: warning
    disposition: open
    title: "Startup tears the engine down before it knows classic can be loaded"
  - id: WR-06
    severity: warning
    disposition: open
    title: "A refused newer selection cancels a valid older one"
  - id: IN-01
    severity: info
    disposition: open
    title: "Unused declarations in `staticCheck`"
  - id: IN-02
    severity: info
    disposition: open
    title: "The forbidden-token lint is a substring match, so it false-positives and is easy to bypass"
  - id: IN-03
    severity: info
    disposition: open
    title: "The silent drum fallback plays the `\\default` SynthDef at amp 0"
  - id: IN-04
    severity: info
    disposition: open
    title: "The README hard-codes the current library contents and a naming rule that is not enforced"
  - id: IN-05
    severity: info
    disposition: open
    title: "Test and helper duplication; one 1573-line harness"
  - id: IN-06
    severity: info
    disposition: open
    title: "Minor shell and logging issues"
open: 10
total: 12
recorded: 2026-10-11T20:36:12.854Z
---

# Phase 04: Code Review Disposition

| Finding | Severity | Disposition | Source |
|---------|----------|-------------|--------|
| WR-01 | warning | deferred | Accepted by rider in 04-UAT test 5 (2026-10-12) as hardening for a later phase |
| WR-02 | warning | deferred | Accepted by rider in 04-UAT test 5 (2026-10-12) as hardening for a later phase |
| WR-03 | warning | open | - |
| WR-04 | warning | open | - |
| WR-05 | warning | open | - |
| WR-06 | warning | open | - |
| IN-01 | info | open | - |
| IN-02 | info | open | - |
| IN-03 | info | open | - |
| IN-04 | info | open | - |
| IN-05 | info | open | - |
| IN-06 | info | open | - |

Dispositions: `open` (recorded, not yet triaged), `fixed`, `skipped`, `deferred`.
Set `deferred` by hand and put the reason in the Source cell; both are preserved. A `|` in the reason is kept as prose and escaped on the next run.
