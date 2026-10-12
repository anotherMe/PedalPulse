# Phase 5: Library Selectors in the GUI - Research

**Researched:** 2026-10-12
**Domain:** Tkinter dropdown selectors (Tk 9.0.3 aqua) driving a send-only python-osc client; pure-Python folder scan and send-on-change controller
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Selector style & placement**
- **D-01:** Each selector is a **dropdown menu**, one per category, preferably Tk `OptionMenu` or another widget that never takes keyboard focus. Button rows were rejected because the window would grow with every new library file.
- **D-02:** The three dropdowns sit in a **side column to the right of the existing controls**. The window grows wider, not taller. The current column (BPM slider, nudges, EPIC zones, Start/Stop, Volume, status, On top) stays exactly as it is.
- **D-03:** Top-to-bottom order in the side column is **Palette, Progression, Melody**, matching GUI-05. Each dropdown has a plain text label naming its category.

**Startup selection**
- **D-04:** At launch, all three dropdowns show **Auto** and the app **sends `auto` to each of the three addresses on startup**, the same way BPM, play, EPIC and volume already send their initial values in `python_app/main.py`. This keeps the GUI and the engine in agreement, even after an engine restart. No last-choice memory and no settings file.
- **D-05:** After startup, a selection is sent **only when the choice actually changes**, as the roadmap success criterion requires. Picking the item that is already selected sends nothing.

**How names appear**
- **D-06:** Entries show the **exact file name stem** (e.g. `classic_lead_loud`), the same identity the engine and its post window use. There are **no descriptive labels, no name mapping and no settings file**. The user considered descriptive labels and explicitly rejected them.
- **D-07:** The list order is **`Auto`, then `classic` (if present), then every other stem A–Z**. The GUI shows the label `Auto` and sends the engine the lowercase string `auto`.

**Picking up new files**
- **D-08:** Each dropdown **re-scans its library folder every time it is opened**, so a file added while the app runs appears without a relaunch. The startup scan still happens too, so relaunching also picks up new files. Re-scanning is a plain folder listing with no file watcher and no background thread.
- **D-09:** An empty or missing folder shows only `Auto` and must never raise an exception (GUI-05, success criterion 1).

### Claude's Discretion
- **Which files count as entries:** `.scd` files only. Skip hidden files (leading `.`) and files whose stem starts with `_` (e.g. `_template.scd`). Planning should also consider skipping stems the engine would reject anyway (the Phase 4 stem rule `^[a-z0-9_]+$`, and the reserved name `auto`), so the GUI never offers a name the engine refuses.
- **The selected file disappears from disk:** the current selection stays shown until the user picks something else. The engine already ignores unknown names with a warning (GUI-06), and the GUI must never crash.
- **Where the logic lives:** follow the existing split. Pure logic (folder scan, sorting, send-on-change state) goes in a testable module or controller like `EpicController` in `python_app/bpm_logic.py`, plus thin Tk wiring in `python_app/view.py`. New `send_*` methods on `OscClient` follow the existing error-swallowing pattern. New addresses and the library path go in `python_app/config.py`. The library root is resolved relative to the repo, not the current working directory.
- **Focus and keyboard:** the dropdowns must not take keyboard focus (`takefocus=0` or equivalent), and Up/Down, Shift-Up and Shift-Down must keep nudging BPM after any selector has been used (GUI-07). Add a Tk test in the style of `python_app/tests/test_view_tk.py` for this.
- **Engine confirmation:** success criterion 2 says the post window confirms the received selection. Planning should verify that the existing `~ppSelect` already posts it, and add only a minimal post line if it doesn't.

### Deferred Ideas (OUT OF SCOPE)
- Descriptive labels mapped from file names via a settings file: briefly raised, then explicitly dropped by the user. Not to be revisited unless the user asks.
- Remembering the last selection between launches: rejected in favour of always starting on Auto.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GUI-05 | The GUI has palette, progression and melody-style selectors, each offering Auto plus every item found in the library folder on disk | `scan_library()` + `OptionMenu` rebuilt on open (Patterns 1, 3); stem filter mirrors the engine rule (Pattern 1); fixed-width menubutton keeps the window from resizing |
| GUI-06 | A selection reaches the engine over send-only OSC by name. Unknown names are ignored by the engine with a warning, and the GUI never crashes | `OscClient.send_selection()` with the existing `(OSError, OverflowError, BuildError)` swallow (Pattern 2); engine side already refuses unknown names with a logged line (Engine Contract section); controller sends any non-empty string, the engine is the validator |
| GUI-07 | The selectors don't interfere with the existing BPM keyboard shortcuts | Menubutton class default `takefocus` is `0` on this Tk (verified); set `takefocus=0` explicitly anyway; no new key bindings; Tk test modelled on `test_volume_slider_keeps_arrow_shortcuts_on_bpm` (Validation Architecture) |
</phase_requirements>

## Summary

This is a small, GUI-and-Python-only phase. The engine side is finished: `~ppSelect` accepts `auto` or a stem on three frozen addresses, posts a confirmation line for every outcome (selected, auto, refused, invalid), and Phase 4's `library_test.scd` already covers unknown names and a real Python round trip. **No engine change is needed**, so the "minimal post line" contingency in CONTEXT.md does not trigger. The plan can stay inside `python_app/`.

The recommended build is one new pure-logic module (`library_logic.py`: `scan_library()` and a `LibrarySelector` controller shaped like `EpicController`), one new `OscClient.send_selection(address, name)` method, a few constants in `config.py`, and a second pack column in `view.py` holding three `tk.OptionMenu` widgets whose menus are rebuilt from a fresh folder scan in the menu's `postcommand`. I probed all the risky Tk behaviours on this Mac's real Tk 9.0.3 (aqua): the Menubutton class default `takefocus` is already `0`, invoking a menu entry does not move focus, `postcommand` fires on the real post path (`tk::MbPost`), and a fixed `width=` keeps the window from resizing when the label text changes.

Three things deserve the planner's attention: (1) `postcommand` fired **twice** per post in the probe, so the rebuild must be idempotent; (2) the existing `test_window_layout_order` pins `window.scale.master.pack_slaves()`, so the existing `container` frame must stay a frame holding exactly the current widgets and the new column must be a **sibling** packed into `root`; (3) D-05 (send only on change) means re-picking the current name does not re-send, which removes the "re-send to reload the file" trick the Phase 4 README describes. That trade-off was chosen by the user and should be documented, not worked around.

**Primary recommendation:** Add `python_app/library_logic.py` (scan + `LibrarySelector`), `OscClient.send_selection`, and a right-hand `OptionMenu` column in `BpmWindow` that rebuilds each menu in `postcommand`; send `auto` x3 at launch via `send_initial()`; test the scan with `tmp_path`, the controller with a list-append fake send, and GUI-07 with a Tk test that invokes menu entries and then fires `<Up>`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Listing library variations (folder scan, filter, sort) | Python app (pure logic module) | -- | The disk listing is the source of truth for the dropdown contents; no engine query allowed (app is send-only) |
| Send-on-change selection state | Python app (controller) | -- | Same pattern as `EpicController`; state lives in the GUI process |
| Rendering dropdowns, rebuilding on open | Python app (Tk view) | -- | Thin wiring only; no OSC import in `view.py` (D-24 in its docstring) |
| Sending the name over OSC | Python app (`OscClient`) | -- | Existing send-only client; swallow transport errors |
| Validating a name, loading the file, bar-line switch, warnings | SuperCollider engine (`~ppSelect`) | -- | Already built in Phase 4; the engine is the validator, the GUI never trusts itself to be in sync |
| Confirming the selection to the rider | SuperCollider post window | -- | `~ppLog` prints it; no engine -> GUI channel (out of scope) |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| tkinter `OptionMenu` (stdlib) | Tk 9.0.3 / Python 3.13 in `.venv` [VERIFIED: `.venv/bin/python -c "import tkinter; print(tkinter.TkVersion, tkinter.TclVersion)"` printed `9.0 9.0`; Tk 9.0.3 per STATE.md Phase 1 decision] | Dropdown whose popup is a native macOS menu | Already the D-01 preference; zero new dependency |
| python-osc | 1.10.2 [VERIFIED: `python_app/requirements.txt` line 1 `python-osc==1.10.2`] | `SimpleUDPClient.send_message(address, "name")` | Already in use; a `str` argument goes out as an OSC string [VERIFIED: probe round trip returned `['classic_lead'] [<class 'str'>]`] |
| `pathlib` / `re` (stdlib) | Python 3.13 | Folder scan and stem validation | No dependency; mirrors the engine's character-loop rule |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| pytest | 8.4.2 [VERIFIED: `python_app/requirements-dev.txt` `pytest==8.4.2`] | Tests (`tmp_path` for folder scans) | All new tests; baseline is 150 passing in about 5 s [VERIFIED: ran `.venv/bin/pytest python_app/tests -q` this session, `150 passed in 5.42s`] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `tk.OptionMenu` | `ttk.Combobox` | **Rejected.** It takes keyboard focus, and its class bindings for Up/Down would run before the root-level BPM nudge bindings, breaking GUI-07. Its `postcommand` is nice, but the focus behaviour is disqualifying |
| `tk.OptionMenu` | A raw `tk.Menubutton` + `tk.Menu` | Equivalent underneath (OptionMenu is a Menubutton with a menu). Use OptionMenu: less code, and its textvariable label already follows a `StringVar` |
| `postcommand` rebuild | Binding `<ButtonPress-1>` on the OptionMenu to rescan | Backup only. An instance binding runs before the class binding that posts the menu, so it also works, but `postcommand` is the documented hook and also covers any other way the menu gets posted |

**Installation:** none. No new packages are introduced.

**Version verification:** nothing to look up; every library is already pinned in `python_app/requirements*.txt` and in the project venv.

## Package Legitimacy Audit

No external packages are installed by this phase (stdlib `tkinter`, `pathlib`, `re`; python-osc and pytest are already pinned and installed). Audit not applicable.

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
 Launch (main.py)
   |
   +--> build 3 LibrarySelector(title, folder, address, send=client.send_selection)
   |         |
   |         +--> BpmWindow(... selector_controllers=[palette, progression, melody])
   |                   |
   |                   +--> per selector: OptionMenu + StringVar("Auto"), menu rebuilt once now
   |
   +--> selector.send_initial() x3  ------------------> OSC "auto" to /pp/palette, /pp/progression, /pp/melody

 Rider opens a dropdown
   |
   v
 Menubutton click --> tk::MbPost --> menu "post" --> postcommand (fires, possibly twice)
   |                                                     |
   |                                                     v
   |                              LibrarySelector.options() --> scan_library(folder)
   |                                                     |      (OSError -> [], filter, sort)
   |                                                     v
   |                              menu.delete(0,"end"); add_radiobutton per name
   v
 Rider picks an entry (menu entry command)
   |
   v
 LibrarySelector.select(label)
   |-- same as current? --> return (no notify, no send)
   |-- else: store, notify listeners (StringVar.set), send(wire_name)
                                              |
                                              v
                              OscClient.send_selection(address, name)
                                  | swallows OSError/OverflowError/BuildError
                                  v
                              UDP 127.0.0.1:57120 (engine may be down: dropped)
                                              |
                                              v
                              sclang OSCdef -> ~ppSelect
                                  auto / invalid name / missing file / success
                                  --> ~ppLog post-window line, music keeps playing

 Up/Down/Shift-Up/Shift-Down: bound on root, untouched; dropdowns never hold focus
```

### Recommended Project Structure
```
python_app/
├── config.py            # + LIBRARY_ROOT, LIBRARY_CATEGORIES, AUTO_LABEL/AUTO_NAME, stem pattern
├── library_logic.py     # NEW: scan_library(), LibrarySelector  (no tkinter import)
├── osc_client.py        # + send_selection(address, name)
├── view.py              # + right-hand selector column, menu rebuild
├── main.py              # + build selectors, pass to window, send_initial() x3
└── tests/
    ├── test_library_logic.py   # NEW: scan + controller
    ├── test_osc_client.py      # + send_selection tests
    └── test_view_tk.py         # + selector layout / focus / GUI-07 tests; _build_all gets selectors
```

### Pattern 1: Folder scan that cannot raise and never offers a name the engine refuses

**What:** A pure function returning the ordered stems for one folder.
**When to use:** At startup, and in every menu `postcommand`.

The engine's stem rule is [VERIFIED: supercollider/core/loader.scd:35-54] `// A selectable name: 1-64 characters, each a-z, 0-9 or _; not starting with _` and `ok = (str[0].ascii != 95) and: { str != "auto" };`. It deliberately avoids a regex because `$` accepts a trailing newline. In Python use `re.fullmatch` (no trailing-newline hole) and never `re.match(...$)`.

```python
# python_app/library_logic.py  (sketch; names are recommendations)
from __future__ import annotations
import re
from pathlib import Path
import config

# Mirrors ~ppStemValid (loader.scd:40-55): 1-64 chars of a-z 0-9 _, first char not _,
# and the reserved word "auto" is excluded separately.
_STEM_RE = re.compile(r"[a-z0-9][a-z0-9_]{0,63}")

def scan_library(folder: Path) -> list[str]:
    """Stems of selectable .scd files in `folder`: classic first, then A-Z.

    Never raises: a missing/unreadable folder (or a folder that is a file) is [].
    Skips hidden files, _template.scd and any stem the engine would refuse.
    """
    try:
        entries = list(folder.iterdir())
    except OSError:
        return []
    stems = set()
    for entry in entries:
        name = entry.name
        if name.startswith(".") or not name.endswith(".scd"):
            continue
        stem = name[: -len(".scd")]
        if stem == config.AUTO_NAME or _STEM_RE.fullmatch(stem) is None:
            continue
        try:
            if not entry.is_file():
                continue
        except OSError:
            continue
        stems.add(stem)
    first = [config.LIBRARY_FIRST_STEM] if config.LIBRARY_FIRST_STEM in stems else []
    return first + sorted(stems - set(first))
```

Notes: `._foo.scd` (macOS AppleDouble files) are dropped by the hidden-file rule and would also fail the regex. A directory named `x.scd` is dropped by `is_file()`. `sorted()` on lowercase ASCII is plain A-Z with digits and `_` sorting around it, which is fine for D-07. What the GUI **cannot** replicate: the engine's symlink containment check (`~ppLibContained`, loader.scd:60-65) and file content validation. A symlink pointing outside the library or a syntactically broken file still shows up in the list; the engine then refuses it with an ERROR line and keeps playing (that is the designed LIB-04 path, not a GUI bug).

### Pattern 2: `LibrarySelector` mirrors `EpicController`

**What:** Track the selected label, notify listeners on a real change, send once, expose `send_initial()`.
**Why this shape:** the existing controllers [VERIFIED: python_app/bpm_logic.py:223-288] store state, `_notify()` listeners, then `self._send(...)`, and `send_initial()` sends unconditionally without notifying.

```python
class LibrarySelector:
    def __init__(self, title, folder, send, *, scan=scan_library):
        self.title = title            # "Palette" label text
        self._folder = folder
        self._send = send             # Callable[[str], object]; engine-facing string
        self._scan = scan
        self._label = config.AUTO_LABEL
        self._listeners = []

    @property
    def selected(self): return self._label

    def options(self) -> list[str]:
        """Rescan every call (D-08). 'Auto' always first (D-07)."""
        return [config.AUTO_LABEL, *self._scan(self._folder)]

    def add_listener(self, fn): self._listeners.append(fn)

    def select(self, label: str) -> None:
        if not isinstance(label, str) or not label or label == self._label:
            return                                  # D-05: no change, no send
        self._label = label
        for fn in self._listeners: fn(label)        # listeners first, like EpicController
        self._send(self._wire(label))

    def send_initial(self) -> None:                 # D-04
        self._send(self._wire(self._label))

    @staticmethod
    def _wire(label): return config.AUTO_NAME if label == config.AUTO_LABEL else label
```

Design points:
- **Do not** validate `label` against the current scan inside `select()`. The engine is the validator (GUI-06), and a file may vanish between listing and picking. `EpicController` raises on unknown zones, but that is because zones are a closed set; library names are an open set.
- `OscClient.send_selection(address, name)` takes the address; the controller needs it bound at construction: `send=functools.partial(client.send_selection, address)` or a small lambda in `main.py`. Either is fine; keep `view.py` free of OSC imports.
- `send_initial()` must send the **wire** form (`auto`), not the label (`Auto`).

### Pattern 3: Dropdown with a menu rebuilt in `postcommand`

**What:** `tk.OptionMenu` + one `StringVar` per dropdown; replace the menu entries from a fresh scan each time the menu is about to post.

```python
# view.py (sketch)
def _build_library_column(self, selectors):
    self.library_column = tk.Frame(self.root, pady=10)
    self.library_column.pack(side="left", anchor="n", padx=(0, 12))   # tuple padx goes in pack(), see Pitfall 3
    self.library_vars, self.library_menus, self.library_buttons = {}, {}, {}
    for sel in selectors:
        tk.Label(self.library_column, text=sel.title, anchor="w").pack(fill="x", pady=(0, 2))
        var = tk.StringVar(value=sel.selected)
        button = tk.OptionMenu(self.library_column, var, sel.selected)   # needs >= 1 value
        button.configure(width=config.LIBRARY_DROPDOWN_WIDTH, anchor="w", takefocus=0)
        button.pack(fill="x", pady=(0, 10))
        menu = button["menu"]                                           # tk.Menu (OptionMenu overrides __getitem__)
        menu.configure(postcommand=lambda s=sel, v=var, m=menu: self._refresh_library_menu(s, v, m))
        sel.add_listener(var.set)
        self._refresh_library_menu(sel, var, menu)                      # startup scan
        ...

def _refresh_library_menu(self, sel, var, menu):
    menu.delete(0, "end")
    for name in sel.options():
        menu.add_radiobutton(label=name, variable=var, value=name,
                             command=lambda n=name: sel.select(n))
```

[VERIFIED: probe on this Mac, Tk 9.0.3 aqua] `OptionMenu` menubutton `takefocus` default is `'0'`; `button["menu"]` returns a `tkinter.Menu`; after `menu.delete(0,"end")` and `add_radiobutton(...)`, `menu.invoke(2)` set the variable and ran the command; `root.focus_get()` was unchanged (`.`); `tk::MbPost` on aqua does not call `focus $menu` (the `focus` call is inside `if {$tearoff != 0 && [tk windowingsystem] ne "aqua"}`). [VERIFIED: probe] `postcommand` fires when the menubutton posts via `tk::MbPost` (it printed `POSTCOMMAND FIRED` **twice** for one post), and the menubutton's real click path is `<Button-1>` -> `tk::MbPost $tk::Priv(inMenubutton) %X %Y` [VERIFIED: probe printed that class binding]. Synthetic `event_generate("<ButtonPress-1>")` does **not** reach `MbPost` because `inMenubutton` is only set by a real `<Enter>`; test the rebuild by calling the postcommand directly, not by synthetic clicks.

Using `add_radiobutton(variable=var, value=name)` gives the native checkmark on the current item. The `command=` then calls `sel.select(name)`; `var` is already set by the radiobutton, and the listener sets it again to the same value (harmless). If a selected file later vanishes, it simply is not in the menu, the button label (the `StringVar`) keeps showing it, and no checkmark is drawn (matches the CONTEXT.md discretion note: the label stays until the rider picks something else).

### Pattern 4: Two-column layout without disturbing the existing column

Keep `container = tk.Frame(root, padx=12, pady=10)` and its children exactly as they are, but pack it `side="left", anchor="n"`; pack the new column into `root` as a sibling (Pattern 3). `window.scale.master` stays `container`, so the existing `test_window_layout_order` assertion [VERIFIED: python_app/tests/test_view_tk.py:457-471] `container_children = window.scale.master.pack_slaves()` still passes unchanged. [VERIFIED: probe] A fixed `width=20` on the OptionMenu keeps `root.winfo_reqwidth()` identical (582 vs 582) when the label changes from `Auto` to a 46-character name, so the window never jumps. The longest stem the engine accepts is 64 characters; those get clipped in the button (acceptable, rare). The column is far shorter than `container` (about 3 x 70 px vs roughly 400 px), so top-aligning with `anchor="n"` has no visible effect on the existing column.

### Pattern 5: `main.py` wiring

Follow the existing block [VERIFIED: python_app/main.py:49-65]: build controllers, pass to `BpmWindow(...)`, then call each `send_initial()`. Add the three selectors to that block and call `send_initial()` on each after `volume.send_initial()`. Update the module docstring (`The app sends /pp/bpm, /pp/play, /pp/epic and /pp/volume`) to list the three new addresses.

### Anti-Patterns to Avoid
- **`ttk.Combobox` or any focusable widget:** breaks GUI-07 (class Up/Down bindings run before root's).
- **Padx/pady tuples in a widget constructor:** `tk.Frame(root, padx=(0, 12))` raises `TclError: expected screen distance but got "0 12"` [VERIFIED: hit in probe]. Tuples are valid only in `pack()`/`grid()`.
- **Raising from the scan or the postcommand:** an error inside `postcommand` aborts the menu post ("If an error returns while executing the command, then the error is returned without posting the menu" [CITED: https://www.tcl-lang.org/man/tcl9.0/TkCmd/menu.html]), so the rider would get a dead dropdown. `scan_library` must swallow `OSError`.
- **Starting a watcher/thread/timer to refresh:** explicitly rejected by D-08.
- **Persisting the selection or a name map:** rejected (Deferred Ideas).
- **Adding an engine -> GUI confirmation:** out of scope; the post window is the confirmation.

## Engine Contract (already built, verified by reading source)

- Addresses [VERIFIED: supercollider/main.scd:392-394]:
  `OSCdef(\pp_progression, { |msg| ~ppSelect.(\progressions, msg[1], '/pp/progression') }, '/pp/progression', srcID: NetAddr("127.0.0.1", nil));`
  `OSCdef(\pp_palette, ... '/pp/palette' ...)` and `OSCdef(\pp_melody, ... '/pp/melody' ...)`.
  The comment at lines 390-391 says: `These three addresses and the auto-or-stem argument are the frozen interface Phase 5's GUI uses.` The `srcID` is the loopback address, so the GUI must keep sending from the same machine to `127.0.0.1` (it does: `config.OSC_HOST = "127.0.0.1"`).
- Mapping category -> folder -> address: `\progressions`/`/pp/progression`, `\palettes`/`/pp/palette`, `\melodies`/`/pp/melody`. GUI titles per D-03: Palette, Progression, Melody (in that order).
- Post-window confirmations in `~ppSelect` [VERIFIED: supercollider/core/loader.scd:180-224], quoted verbatim:
  - success: `"PedalPulse: % % -> selected (rev %), plays from the next bar"`
  - auto: `"PedalPulse: % auto -> auto (resolves to classic)"`
  - invalid name: `"PedalPulse WARNING: ignoring % \"%\": a name is 1-64 characters from a-z, 0-9 and _, not starting with _, and not auto"`
  - invalid argument type: `"PedalPulse WARNING: ignoring % with invalid argument %"`
  - well-formed name, no file: `ERROR: library file % does not exist` (loader.scd:75) followed by `"PedalPulse: % % refused -- still playing %"` (loader.scd:217)
  - So success criteria 2 and 3 are satisfied by the engine as-is. **No engine edit is required**; the Phase 4 library check already covers a nonexistent name (library_test.scd:1107 comment `// 7. unknown name: a well-formed name with no file is refused loudly.`, sending `'nope'` at line 1114) and a real Python OSC round trip (library_test.scd:1027).
- OSC strings arrive in sclang as Symbols (loader.scd comment, line 175) and `~ppSelect` accepts Symbol or String (loader.scd:182). python-osc sends a Python `str` as an OSC string (probe), which is exactly what the README's Python one-liner does [VERIFIED: supercollider/library/README.md:40].
- Re-sending the **current** name reloads its file engine-side (main.scd:389 `Re-sending the current name reloads its file.`; README line 56). D-05 means the GUI will not do this; see Pitfall 6.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Dropdown widget | A custom popup / listbox / button row | `tk.OptionMenu` | Native aqua popup, label follows a `StringVar`, never focus-bound |
| OSC string encoding | Manual byte packing | `SimpleUDPClient.send_message(addr, "name")` | Already in the project; verified string round trip |
| Folder watching | `watchdog`, polling `after()` loop | Rescan in `postcommand` | D-08; one `iterdir()` of at most a few dozen files per open |
| Trailing-newline-safe stem match | `re.match(r"^...$")` | `re.fullmatch` on the stem | `$` accepts `"classic\n"` (the engine comments on exactly this pitfall at loader.scd:35-39) |
| Engine -> GUI confirmation | A reply channel | The SuperCollider post window | Out of scope; app stays send-only |

**Key insight:** every hard part (name validation, atomic bar-line switching, fallback, warnings) already lives in the engine. The GUI only has to list files honestly and send a string when the choice changes.

## Runtime State Inventory

Not a rename/refactor/migration phase. Omitted.

## Common Pitfalls

### Pitfall 1: `postcommand` runs more than once per open
**What goes wrong:** A rebuild that is not idempotent (e.g. `add_radiobutton` without a preceding `delete`) doubles the entries.
**Why it happens:** Observed twice per `tk::MbPost` in the probe; the Tk man page notes that on Macintosh/Windows "all post-commands in a system of menus are executed before any of those menus are posted" [CITED: https://www.tcl-lang.org/man/tcl9.0/TkCmd/menu.html].
**How to avoid:** Always `menu.delete(0, "end")` first, then add. The rebuild is cheap.
**Warning signs:** Duplicate entries after opening the menu twice (assert menu entry count after calling the postcommand twice).

### Pitfall 2: Arrow keys stop nudging BPM (GUI-07)
**What goes wrong:** A focusable selector captures Up/Down.
**Why it happens:** Widget and class bindings run before the root binding; only the BPM entry is special-cased with `"break"`.
**How to avoid:** `OptionMenu` (Menubutton class default `takefocus` is `'0'` on this Tk, verified) plus an explicit `takefocus=0` so a future Tk default cannot change it. Add no `<Up>`/`<Down>` bindings and no `focus_set()` calls. Test: invoke an entry, `focus_force()` on root, `event_generate("<Up>")`, assert BPM changed (existing pattern at test_view_tk.py:435-454).
**Warning signs:** `root.focus_get()` returns a selector widget after an invoke.

### Pitfall 3: Tuple padding in a widget constructor
**What goes wrong:** `TclError: expected screen distance but got "0 12"`.
**How to avoid:** `pack(padx=(0, 12))`, never `tk.Frame(..., padx=(0, 12))` [VERIFIED: reproduced in probe].

### Pitfall 4: Window changes width when the selection changes
**What goes wrong:** `root.resizable(False, False)` does not stop geometry propagation; a longer label widens the button and the window.
**How to avoid:** Set a fixed `width=` (characters) on each OptionMenu. [VERIFIED: probe, request width stayed 582 with a 46-character label.]

### Pitfall 5: Closure capture in menu-entry commands
**What goes wrong:** Every entry selects the last name.
**How to avoid:** `lambda n=name: sel.select(n)` (the file already uses this idiom with `lambda d=delta`, `lambda z=name`).

### Pitfall 6: D-05 removes "re-send to reload"
**What goes wrong:** Phase 4's README tells the rider that re-sending the current name reloads the file from disk. With send-on-change only, picking the already-selected name does nothing, so editing a not-yet-committed variation and re-picking it will not reload it.
**How to avoid:** Do not change D-05 (it is locked and matches the success criterion). Document the workaround in the plan/UAT notes: pick a different item and then back, or use the README one-liner. Because the project rule is "new file per variation", this should rarely matter.

### Pitfall 7: Synthetic clicks do not exercise the real post path
**What goes wrong:** A Tk test that `event_generate`s `<Button-1>` on the OptionMenu never reaches `tk::MbPost` (the class binding needs `tk::Priv(inMenubutton)` from a real `<Enter>`), so it proves nothing; the real path would open a modal native menu.
**How to avoid:** In tests call the menu's postcommand directly (`tk_root.tk.eval(menu.cget("postcommand"))`, which runs the registered Tcl command) and use `menu.invoke(i)` to pick entries. Leave the real click for manual UAT.

### Pitfall 8: `_build_all` in `test_view_tk.py` constructs `BpmWindow` positionally/by keyword
**What goes wrong:** Adding a required `selector_controllers` keyword breaks every existing Tk test until `_build_all` is updated.
**How to avoid:** Make it a required keyword (consistent with the other three controllers) and update `_build_all` in the same task (build three `LibrarySelector`s on `tmp_path` folders with an append-list fake send, and return them in the `SimpleNamespace`). `test_window_layout_order` must still pass unmodified.

## Code Examples

### OscClient method (follows the existing swallow pattern)
```python
# Source: pattern from python_app/osc_client.py:40-58 (send_bpm) -- same exception tuple
def send_selection(self, address: str, name: str) -> bool:
    """Send `name` (a library stem or 'auto') to `address` as an OSC string.
    Sent raw -- the engine validates it. Catches (OSError, OverflowError, BuildError)
    for the same reasons as send_bpm."""
    try:
        self._client.send_message(address, str(name))
    except (OSError, OverflowError, BuildError) as exc:
        print(f"OscClient: failed to send {address} {name} to {self.target}: {exc}", file=sys.stderr)
        return False
    return True
```

### config.py additions (values are recommendations except the addresses, which the engine fixes)
```python
from pathlib import Path

OSC_PALETTE_ADDRESS = "/pp/palette"
OSC_PROGRESSION_ADDRESS = "/pp/progression"
OSC_MELODY_ADDRESS = "/pp/melody"

# Library root is resolved from this file, never from the current directory.
LIBRARY_ROOT = Path(__file__).resolve().parents[1] / "supercollider" / "library"
# (title shown in the GUI, folder name, OSC address) in side-column order (D-03).
LIBRARY_CATEGORIES = (
    ("Palette", "palettes", OSC_PALETTE_ADDRESS),
    ("Progression", "progressions", OSC_PROGRESSION_ADDRESS),
    ("Melody", "melodies", OSC_MELODY_ADDRESS),
)
AUTO_LABEL = "Auto"      # shown in the GUI
AUTO_NAME = "auto"       # sent to the engine (reserved word there)
LIBRARY_FIRST_STEM = "classic"
LIBRARY_DROPDOWN_WIDTH = 20
```
(`config.py` currently has no imports [VERIFIED: python_app/config.py:1-40], so adding `from pathlib import Path` at the top is the only structural change.)

### Scan test using `tmp_path`
```python
def test_scan_filters_and_orders(tmp_path):
    for name in ["classic.scd", "zeta.scd", "alpha.scd", "_template.scd", ".hidden.scd",
                 "._alpha.scd", "Upper.scd", "auto.scd", "bad name.scd", "notes.txt", "alpha.scd.bak"]:
        (tmp_path / name).write_text("()")
    (tmp_path / "dir.scd").mkdir()
    assert scan_library(tmp_path) == ["classic", "alpha", "zeta"]

def test_scan_missing_or_file_folder_is_empty(tmp_path):
    assert scan_library(tmp_path / "nope") == []
    f = tmp_path / "f"; f.write_text("x")
    assert scan_library(f) == []
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Tk 8.6 (CLAUDE.md recommends 8.6) | This project runs Tk 9.0.3 via `./run.sh` | Phase 1 decision (STATE.md) | Verified here: OptionMenu / Menu / MbPost behave as needed; Tk gate accepts 8.6 and 9.x |

**Deprecated/outdated:** nothing relevant. Note CLAUDE.md's Tk 8.6 guidance is superseded by the Phase 1 decision recorded in STATE.md; the probes above ran on the real 9.0 build.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A real mouse click on the OptionMenu on aqua reaches `tk::MbPost` and therefore `postcommand` (I verified the class binding text and a direct `tk::MbPost` call, but could not generate a real hardware click) | Pattern 3 | The dropdown would not rescan on open. Mitigation: manual UAT step 2 below; fallback is an instance `<ButtonPress-1>` binding calling the same refresh function |
| A2 | Native macOS popup shows a checkmark next to the radiobutton entry bound to the current variable value | Pattern 3 | Cosmetic only (no checkmark); selection behaviour is unaffected |
| A3 | Rebuilding menu entries inside `postcommand` is reflected in the native menu that appears (the Tk man page does not discuss modifying entries there; the post-commands run before posting) | Pattern 3 | New files would appear one open late. Same mitigation as A1 |

## Open Questions

1. **Should a `LibrarySelector` accept a name not in the current scan?**
   - What we know: the engine is the validator and the file can vanish; CONTEXT.md says the label stays and the GUI must not crash.
   - Recommendation: yes, accept any non-empty string in `select()`. The menu itself only offers scanned names, so this path is only reachable programmatically/in tests.

2. **Should `osc_client.py`'s raw-send CLI get `--palette/--progression/--melody` flags?**
   - What we know: the library README already gives a Python one-liner that can send an unknown name for success criterion 3; the user prefers minimal scope.
   - Recommendation: skip. Optional only.

3. **Documentation touch-up.** `supercollider/library/README.md` says the app's selectors arrive in Phase 5; a one-line update after the phase ships is nice to have but not required (the README is not a committed-never-edit library file; the guard only covers `library/*/[a-z0-9]*.scd`, see scripts/check.sh).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `.venv` Python | all tests and the app | yes | 3.13 (`.venv/bin/python`) | -- |
| Tk (real display session) | Tk widget tests | yes | 9.0.3 aqua (probes ran) | -- |
| pytest | tests | yes | 8.4.2 | -- |
| python-osc | OscClient | yes | 1.10.2 | -- |
| SuperCollider sclang | manual UAT of the post-window confirmation only | yes | `/Applications/SuperCollider.app/Contents/MacOS/sclang` exists | UAT can read the engine post window only with the engine running |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | pytest 8.4.2 (real Tk 9.0.3 for view tests, mocked/real loopback sockets for OSC) |
| Config file | none; `python_app/tests/conftest.py` puts `python_app/` on `sys.path` |
| Quick run command | `.venv/bin/pytest python_app/tests/test_library_logic.py python_app/tests/test_osc_client.py python_app/tests/test_view_tk.py -q` |
| Full suite command | `.venv/bin/pytest python_app/tests -q` (150 tests, about 5 s at baseline) |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GUI-05 | Scan: `.scd` only, skips hidden, `_template`, `auto`, invalid stems, directories; `classic` first then A-Z; missing/empty/file folder gives `[]` | unit | `.venv/bin/pytest python_app/tests/test_library_logic.py -q` | Wave 0 |
| GUI-05 | `options()` is `Auto` + scan and rescans each call (add a file, call again, it appears) | unit | same | Wave 0 |
| GUI-05 | Window shows three titled dropdowns in order Palette, Progression, Melody, each starting on `Auto`; menu entries equal `options()`; postcommand rebuild is idempotent and picks up a new file | Tk | `.venv/bin/pytest python_app/tests/test_view_tk.py -q` | extend |
| GUI-05 | Real library folders list `classic` (+ `classic_lead`, `classic_lead_loud` for melodies) and no `_template` | unit | `.venv/bin/pytest python_app/tests/test_library_logic.py -q` | Wave 0 |
| GUI-06 | `send_selection` delivers the address plus an OSC string over a real loopback socket; returns False on `OSError` and `BuildError`/`OverflowError` without raising | unit | `.venv/bin/pytest python_app/tests/test_osc_client.py -q` | extend |
| GUI-06 | Controller: change sends once with wire form (`Auto` -> `auto`); same pick sends nothing and notifies nothing; `send_initial` sends `auto` unconditionally without notifying; a falsy/raising-free send never rolls state back; unknown/vanished name is still sent | unit | `.venv/bin/pytest python_app/tests/test_library_logic.py -q` | Wave 0 |
| GUI-06 | Engine ignores unknown names with a warning, music keeps playing | already covered engine-side | `bash scripts/check.sh --library-only` (existing `unknown name` tier) | exists |
| GUI-07 | After invoking a menu entry on each dropdown, `focus_get()` is not a selector, each `takefocus` is `"0"`, and `<Up>` still nudges BPM by 1 (and `<Shift-Down>` by 5) | Tk | `.venv/bin/pytest python_app/tests/test_view_tk.py -q` | extend |
| GUI-07 | Existing layout test still passes (`window.scale.master.pack_slaves()` unchanged) | Tk | same | exists |

### Sampling Rate
- **Per task commit:** the quick run command for the touched test files
- **Per wave merge:** `.venv/bin/pytest python_app/tests -q`
- **Phase gate:** full pytest suite green, plus the manual UAT below, before `/gsd-verify-work`. The engine suites (`scripts/check.sh`) are not affected by this phase; there is a known flaky smoke check (`epic glide up`, STATE.md) unrelated to this work, so do not use the smoke suite as this phase's gate.

### Wave 0 Gaps
- [ ] `python_app/tests/test_library_logic.py` -- scan and controller (GUI-05, GUI-06)
- [ ] Update `_build_all` in `python_app/tests/test_view_tk.py` to pass `selector_controllers` and return them
- No framework install needed.

### Manual UAT (cannot be automated: native popup, real engine)
1. Launch via `./run.sh` with the engine running. The post window shows three lines `PedalPulse: /pp/palette auto -> auto (resolves to classic)` (and the same for progression and melody) from the startup sends.
2. Open the Melody dropdown: list is `Auto, classic, classic_lead, classic_lead_loud`. In another terminal copy a melody file to a new name (for example `cp supercollider/library/melodies/_template.scd supercollider/library/melodies/zz_try.scd`, then delete it afterwards) and open the dropdown again without relaunching: the new name appears (covers A1/A3).
3. Pick `classic_lead_loud`: post window shows `... /pp/melody classic_lead_loud -> selected (rev N), plays from the next bar`; pick it again: nothing new is posted.
4. Press Up, Down, Shift-Up, Shift-Down right after using a dropdown: BPM changes exactly as before.
5. Stop the engine, pick items: the app does not crash or freeze. Remove the new file while it is selected, then send that name with the README one-liner: post window shows the ERROR/`refused -- still playing` lines and music keeps playing.

## Security Domain

`security_enforcement` is enabled in `.planning/config.json` (ASVS level 1).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Localhost-only, single-user |
| V3 Session Management | no | No sessions |
| V4 Access Control | no | Engine accepts only loopback sources (`srcID: NetAddr("127.0.0.1", nil)`, main.scd:392-394) |
| V5 Input Validation | yes | Scan filters filenames with `re.fullmatch` on the stem; engine re-validates every name (`~ppStemValid`) and builds no path from an invalid one |
| V6 Cryptography | no | None |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Hostile or odd filename in the library folder reaching the OSC send (newline, spaces, unicode, `..`) | Tampering | Strict stem regex in `scan_library`; engine rejects the same set (library_test.scd:1078-1089 covers `"classic\n"`, `"../x"`, `"my lead"`) |
| Symlink in the library pointing outside it | Elevation / Info disclosure | Engine-side containment check (`~ppLibContained`); the GUI only sends a name and never reads file contents |
| GUI crash from a vanished/unreadable folder | Denial of service | `scan_library` swallows `OSError` and returns `[]` |
| Engine not running | Availability | UDP send; `OscClient` swallows transport errors |

## Sources

### Primary (HIGH confidence)
- `supercollider/core/loader.scd` lines 1-226 (read this session): stem rule, `~ppLibLoad`, `~ppSelect`, all post-window messages
- `supercollider/main.scd` lines 388-396 (read): the three `OSCdef`s and the "frozen interface" comment
- `supercollider/library/README.md` (read in full): naming rules, one-liner, reload semantics
- `python_app/view.py`, `bpm_logic.py`, `osc_client.py`, `config.py`, `main.py`, `tests/test_view_tk.py`, `test_epic_logic.py`, `test_osc_client.py`, `conftest.py` (all read in full)
- Live probes on the project's `.venv` (Python 3.13, Tk 9.0.3, aqua): OptionMenu `takefocus`, `menu.invoke`, `focus_get`, `postcommand` firing via `tk::MbPost` (twice), Menubutton class bindings, fixed-width layout stability, tuple-padx `TclError`, python-osc string round trip, 150-test baseline
- Tk menu man page https://www.tcl-lang.org/man/tcl9.0/TkCmd/menu.html (`-postcommand`, post-command ordering note)
- Tk optionMenu man page https://www.tcl-lang.org/man/tcl9.0/TkCmd/optionMenu.html (menubutton plus associated menu; variable shown as label)

### Secondary (MEDIUM confidence)
- none

### Tertiary (LOW confidence)
- none

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - nothing new; all components already in the repo and probed on the real Tk build
- Architecture: HIGH - direct analogue (`EpicController`) and an unchanged engine contract read from source
- Pitfalls: HIGH - most reproduced in probes; the only unverified parts are a real hardware click and native-menu redraw after rebuild (A1, A3), covered by manual UAT with a ready fallback

**Research date:** 2026-10-12
**Valid until:** 2026-11-11 (stable; revisit only if Tk or the engine selection contract changes)
