# Phase 5: Library Selectors in the GUI - Context

**Gathered:** 2026-10-12
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase adds three selectors (Palette, Progression, Melody) to the existing Tkinter PedalPulse window. Each one lists `Auto` followed by every variation file in its `supercollider/library/<category>/` folder and sends the chosen name to the engine over the existing send-only OSC client (`/pp/palette`, `/pp/progression`, `/pp/melody`). The engine side (selection addresses, unknown-name warnings, bar-line switching, fallback) already exists from Phase 4. This phase is GUI and Python only, unless planning finds that a small engine-side post-window confirmation is missing. Requirements covered: GUI-05, GUI-06, GUI-07.

</domain>

<decisions>
## Implementation Decisions

### Selector style & placement
- **D-01:** Each selector is a **dropdown menu**, one per category, preferably Tk `OptionMenu` or another widget that never takes keyboard focus. Button rows were rejected because the window would grow with every new library file.
- **D-02:** The three dropdowns sit in a **side column to the right of the existing controls**. The window grows wider, not taller. The current column (BPM slider, nudges, EPIC zones, Start/Stop, Volume, status, On top) stays exactly as it is.
- **D-03:** Top-to-bottom order in the side column is **Palette, Progression, Melody**, matching GUI-05. Each dropdown has a plain text label naming its category.

### Startup selection
- **D-04:** At launch, all three dropdowns show **Auto** and the app **sends `auto` to each of the three addresses on startup**, the same way BPM, play, EPIC and volume already send their initial values in `python_app/main.py`. This keeps the GUI and the engine in agreement, even after an engine restart. No last-choice memory and no settings file.
- **D-05:** After startup, a selection is sent **only when the choice actually changes**, as the roadmap success criterion requires. Picking the item that is already selected sends nothing.

### How names appear
- **D-06:** Entries show the **exact file name stem** (e.g. `classic_lead_loud`), the same identity the engine and its post window use. There are **no descriptive labels, no name mapping and no settings file**. The user considered descriptive labels and explicitly rejected them.
- **D-07:** The list order is **`Auto`, then `classic` (if present), then every other stem A–Z**. The GUI shows the label `Auto` and sends the engine the lowercase string `auto`.

### Picking up new files
- **D-08:** Each dropdown **re-scans its library folder every time it is opened**, so a file added while the app runs appears without a relaunch. The startup scan still happens too, so relaunching also picks up new files. Re-scanning is a plain folder listing with no file watcher and no background thread.
- **D-09:** An empty or missing folder shows only `Auto` and must never raise an exception (GUI-05, success criterion 1).

### Claude's Discretion
- **Which files count as entries:** `.scd` files only. Skip hidden files (leading `.`) and files whose stem starts with `_` (e.g. `_template.scd`). Planning should also consider skipping stems the engine would reject anyway (the Phase 4 stem rule `^[a-z0-9_]+$`, and the reserved name `auto`), so the GUI never offers a name the engine refuses.
- **The selected file disappears from disk:** the current selection stays shown until the user picks something else. The engine already ignores unknown names with a warning (GUI-06), and the GUI must never crash.
- **Where the logic lives:** follow the existing split. Pure logic (folder scan, sorting, send-on-change state) goes in a testable module or controller like `EpicController` in `python_app/bpm_logic.py`, plus thin Tk wiring in `python_app/view.py`. New `send_*` methods on `OscClient` follow the existing error-swallowing pattern. New addresses and the library path go in `python_app/config.py`. The library root is resolved relative to the repo, not the current working directory.
- **Focus and keyboard:** the dropdowns must not take keyboard focus (`takefocus=0` or equivalent), and Up/Down, Shift-Up and Shift-Down must keep nudging BPM after any selector has been used (GUI-07). Add a Tk test in the style of `python_app/tests/test_view_tk.py` for this.
- **Engine confirmation:** success criterion 2 says the post window confirms the received selection. Planning should verify that the existing `~ppSelect` already posts it, and add only a minimal post line if it doesn't.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope & requirements
- `.planning/ROADMAP.md` §"Phase 5: Library Selectors in the GUI": goal and the 4 success criteria
- `.planning/REQUIREMENTS.md`: GUI-05, GUI-06, GUI-07
- `.planning/PROJECT.md`: core value and constraints (send-only, minimal dependencies)

### Engine selection contract (Phase 4)
- `.planning/phases/04-modular-engine-variation-library/04-CONTEXT.md`: D-07 (startup on `classic`; the `/pp/melody` one-liner) and the Claude's Discretion notes on reload semantics, stem rules (`^[a-z0-9_]+$`, `auto` reserved) and unknown-name warnings
- `supercollider/main.scd` lines ~392–394: `OSCdef(\pp_progression|\pp_palette|\pp_melody)` → `~ppSelect`
- `supercollider/library/README.md`: library folder conventions (file name = identity, `_template.scd`, never overwrite)

### Existing GUI code
- `python_app/view.py`: `BpmWindow` layout, `takefocus=0` pattern, root-level arrow key bindings
- `python_app/bpm_logic.py`: `EpicController` (select + send-on-change + `send_initial`) is the closest analog for a selector controller
- `python_app/osc_client.py`: `send_*` methods with the error-swallowing pattern
- `python_app/config.py`: OSC addresses and constants
- `python_app/main.py`: wiring and the startup `send_initial()` calls

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `EpicController` (`python_app/bpm_logic.py`): the named-choice state, listeners, `select_*` with send-on-change and `send_initial` all map directly onto a `LibrarySelector`-style controller.
- `OscClient` (`python_app/osc_client.py`): add one generic or three specific selection sends. UDP send failures are already swallowed, so the app keeps working when the engine is down.
- `python_app/tests/test_view_tk.py`, `test_epic_logic.py`, `test_osc_client.py`: test patterns for the Tk view, the controller logic and the mocked-socket OSC send.

### Established Patterns
- Every control in the window uses `takefocus=0`. Arrow-key nudges are bound on `root`, and the entry overrides them with `"break"`. The new selectors must not break this.
- `main.py` sends every control's initial value on launch (`send_initial`). The selectors follow the same pattern (D-04).
- The layout uses `pack` inside a `container` Frame. The side column (D-02) needs a two-column arrangement, either an outer frame holding the existing container plus a new column, or a switch to `grid` at the top level.

### Integration Points
- `supercollider/library/{palettes,progressions,melodies}/`: what the GUI scans. Current entries are `classic` in each folder, plus `classic_lead` and `classic_lead_loud` in melodies. Each folder also holds `_template.scd`, which must be skipped.
- The engine's `~ppSelect` accepts `auto` or a stem and warns on unknown names.

</code_context>

<specifics>
## Specific Ideas

- The names in the GUI must match the names the user uses when giving feedback and the names the engine prints, so the exact file stem is shown with no prettifying (D-06).
- The main use is auditioning: Claude writes a new library file, the user opens the dropdown, and the new file is there to pick right away (D-08).
- Keep it simple, per the user's standing preference: no settings file, no persisted state, no engine → GUI feedback.

</specifics>

<deferred>
## Deferred Ideas

- Descriptive labels mapped from file names via a settings file: briefly raised, then explicitly dropped by the user. Not to be revisited unless the user asks.
- Remembering the last selection between launches: rejected in favour of always starting on Auto.

</deferred>

---

*Phase: 05-library-selectors-in-the-gui*
*Context gathered: 2026-10-12*
