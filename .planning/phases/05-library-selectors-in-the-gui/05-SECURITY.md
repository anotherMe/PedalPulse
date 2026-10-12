---
phase: "05"
slug: "library-selectors-in-the-gui"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-12"
---

# Phase 05 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Library folder on disk -> GUI list | File names are untrusted input; they are listed in the dropdowns and sent to the engine. The folder can change at any time while the app runs | File names (low sensitivity) |
| GUI -> engine (UDP loopback) | The picked name crosses a process boundary as one OSC string; the engine re-validates it | OSC string on 127.0.0.1 (low) |
| Rider keyboard -> BPM control | The arrow keys must keep driving BPM; a dropdown that captured focus would take that control away mid-ride | Key events (none) |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-05-01 | Tampering | scan_library -> send_selection | low | mitigate | `_STEM_RE.fullmatch` + reserved `auto` in `python_app/library_logic.py:21,43`; engine re-validates with `~ppStemValid` | closed |
| T-05-02 | Spoofing | OscClient target for the new sends | low | mitigate | Reuses `config.OSC_HOST = "127.0.0.1"` (`python_app/config.py:9`); `/pp/palette`, `/pp/progression`, `/pp/melody` OSCdefs use `srcID: NetAddr("127.0.0.1", nil)` (`supercollider/main.scd:392-394`) | closed |
| T-05-03 | Denial of Service | send_selection while the engine is down | low | mitigate | `except (OSError, OverflowError, BuildError)` returns False (`python_app/osc_client.py:119-121`); `test_send_selection_returns_false_on_send_errors` | closed |
| T-05-04 | Tampering | scan_library hostile names | low | mitigate | `_STEM_RE.fullmatch` on `[a-z0-9][a-z0-9_]{0,63}`; `test_scan_filters_and_orders`, `test_scan_length_limit` | closed |
| T-05-05 | Denial of Service | scan_library on a missing/unreadable folder or non-file entry | medium | mitigate | `except OSError: return []` and per-entry skip (`python_app/library_logic.py:35-48`); `test_scan_missing_empty_or_file_path_lists_nothing`, `test_scan_unreadable_folder_lists_nothing` | closed |
| T-05-06 | Information Disclosure | Symlink in the library pointing outside it | low | accept | GUI never reads file contents; engine containment check `~ppLibContained` (`supercollider/core/loader.scd:60,78`) | closed |
| T-05-07 | Denial of Service | Menu post command raising | medium | mitigate | `postcommand` calls the idempotent `_refresh_library_menu` (`python_app/view.py:215`); `test_every_dropdown_rebuilds_on_open` covers deleted file and removed folder | closed |
| T-05-08 | Denial of Service | A selector capturing keyboard focus | medium | mitigate | `takefocus=0` on every dropdown (`python_app/view.py:208`), no key bindings on the column; `test_dropdowns_take_no_focus_and_add_no_key_bindings`, `test_arrow_keys_still_nudge_bpm_after_using_each_dropdown` | closed |
| T-05-09 | Tampering | The GUI changing a library file | low | mitigate | No write path in `library_logic.py` or `view.py`; `./scripts/check.sh --library-only` library guard passed (05-03) | closed |
| T-05-SC | Tampering | Package installs | low | accept | No dependency added in phase 5 (`python_app/requirements*.txt` unchanged since 44f4fa3) | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-05-01 | T-05-06 | The GUI only lists names; the engine refuses a symlinked file outside the library and keeps playing | Plan 05-02 threat model | 2026-10-12 |
| AR-05-02 | T-05-SC | No new dependency; a fresh `.venv` installs only the already-pinned python-osc==1.10.2 and pytest==8.4.2 | Plans 05-01..03 threat models | 2026-10-12 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-12 | 10 | 10 | 0 | secure-phase (L1 grep, orchestrator) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-12
