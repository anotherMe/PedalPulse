# Phase 5: Library Selectors in the GUI - Pattern Map

**Mapped:** 2026-10-12
**Files analyzed:** 8 (1 new module, 1 new test file, 6 modified)
**Analogs found:** 8 / 8
All analog paths below are git-tracked (checked with `git ls-files`).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `python_app/library_logic.py` (new) | controller + utility (scan) | event-driven, request-response (send-on-change) | `python_app/bpm_logic.py` `EpicController` (L223-288) | exact (controller); scan has no analog, use RESEARCH Pattern 1 |
| `python_app/osc_client.py` (+`send_selection`) | service | request-response (send-only UDP) | `OscClient.send_bpm` / `send_play` (L40-70+) | exact |
| `python_app/config.py` (+constants) | config | n/a | existing constants L7-39 | exact |
| `python_app/view.py` (+side column) | component | event-driven | `BpmWindow._build_zone_row` / `_build_volume_row` (L174-250) | role-match |
| `python_app/main.py` (wiring) | config/entry | request-response | main.py L49-65 | exact |
| `python_app/tests/test_library_logic.py` (new) | test | n/a | `python_app/tests/test_epic_logic.py` | exact |
| `python_app/tests/test_osc_client.py` (+tests) | test | n/a | same file L70-80 (`test_send_bpm_returns_false_on_oserror`) | exact |
| `python_app/tests/test_view_tk.py` (+tests, update `_build_all`) | test | n/a | same file L66-93 `_build_all`, L435-454 `test_volume_slider_keeps_arrow_shortcuts_on_bpm` | exact |

## Pattern Assignments

### `python_app/library_logic.py` (controller, send-on-change)

**Analog:** `python_app/bpm_logic.py` `EpicController` (lines 223-288)

**Shape to copy** (L233-288): `__init__(send, ...)` stores `self._send`, state, `self._listeners: list[Callable[[str], None]] = []`; `add_listener`; `_notify`; a `select_*` that early-returns on same value, stores, notifies listeners, then sends (fire-and-forget, return ignored); `send_initial()` sends unconditionally and does not notify.
```python
def select_zone(self, name):
    if name not in self._zones:
        raise ValueError(f"unknown EPIC zone {name!r}")
    if name == self._zone:
        return
    self._zone = name
    self._notify()
    self._send(float(self._zones[name]))

def send_initial(self) -> None:
    """Send the current zone's value once, unconditionally, without notifying (D-23)."""
    self._send(float(self._zones[self._zone]))
```
Differences: do NOT raise on unknown names (open set, engine validates; RESEARCH Pattern 2). Send the wire form (`Auto` -> `auto`), also in `send_initial`. Module header uses `from __future__ import annotations` and `import config` (bpm_logic style, no tkinter import).

**Scan function:** no codebase analog. Use RESEARCH.md Pattern 1 verbatim (`re.fullmatch(r"[a-z0-9][a-z0-9_]{0,63}")`, skip hidden, non-`.scd`, `auto`, non-files; swallow `OSError`; `classic` first then sorted). Engine rule source: `supercollider/core/loader.scd:35-65`.

---

### `python_app/osc_client.py` (service, send-only)

**Analog:** `send_bpm` (lines 40-58)
```python
try:
    self._client.send_message(config.OSC_BPM_ADDRESS, float(bpm))
except (OSError, OverflowError, BuildError) as exc:
    print(f"OscClient: failed to send /pp/bpm {bpm} to {self.target}: {exc}", file=sys.stderr)
    return False
return True
```
New `send_selection(self, address: str, name: str) -> bool` uses the same exception tuple (BuildError already imported, L24) and `str(name)`. Update class docstring (L29) and module docstring (L10-15) to list the three new addresses. In main.py bind the address with `functools.partial(client.send_selection, address)` or a lambda.

---

### `python_app/config.py` (config)

**Analog:** L7-12 (addresses as plain string constants), L24-31 (commented constant blocks). Currently no imports; add `from pathlib import Path` after the docstring. Add `OSC_PALETTE_ADDRESS`, `OSC_PROGRESSION_ADDRESS`, `OSC_MELODY_ADDRESS`, `LIBRARY_ROOT = Path(__file__).resolve().parents[1] / "supercollider" / "library"`, `LIBRARY_CATEGORIES` as (title, folder, address) in order Palette/palettes, Progression/progressions, Melody/melodies, `AUTO_LABEL="Auto"`, `AUTO_NAME="auto"`, `LIBRARY_FIRST_STEM="classic"`, `LIBRARY_DROPDOWN_WIDTH=20`. Comment each block with its requirement id like the existing ones.

---

### `python_app/view.py` (component, event-driven)

**Analog:** `_build_zone_row` / `_build_volume_row` (L174-250), plus constructor L22-50.

**Constructor** (L29-50): keyword-only controllers, root is configured, then `container = tk.Frame(root, padx=12, pady=10); container.pack()`.
Change: add required keyword `selector_controllers`; change to `container.pack(side="left", anchor="n")`; build the new column as a SIBLING frame packed into `root` (so `window.scale.master.pack_slaves()` in `test_window_layout_order` stays unchanged). Update module docstring (mentions controllers, "No OSC import here (D-24)") and the class docstring.

**Focus pattern:** every control passes `takefocus=0` (e.g. L63, L80, L123, L138, L195, L240). Root-level nudges bound at L167-170 (`self.root.bind("<Up>", ...)`); add no key bindings or `focus_set()`.

**Closure idiom:** loop lambdas use default-arg capture (`lambda d=delta`, `lambda z=name`); use `lambda n=name: sel.select(n)`.

**Core new code:** RESEARCH.md Pattern 3 (`tk.OptionMenu`, `configure(width=config.LIBRARY_DROPDOWN_WIDTH, anchor="w", takefocus=0)`, `menu.configure(postcommand=...)`, refresh does `menu.delete(0, "end")` first, then `add_radiobutton`; `sel.add_listener(var.set)`; one refresh at build). Tuple padding only in `pack()`, never in constructors. Keep widget attributes public for tests (`library_column`, `library_vars`, `library_menus`, `library_buttons`), like `zone_buttons`/`zone_row`.

---

### `python_app/main.py` (entry/wiring)

**Analog:** lines 38-65.
```python
from bpm_logic import BpmController, EpicController, PlayController, VolumeController
...
volume = VolumeController(send=client.send_volume)
BpmWindow(root, controller, status_text=..., play_controller=play, epic_controller=epic, volume_controller=volume)
controller.send_initial(); play.send_initial(); epic.send_initial(); volume.send_initial()
```
Add: import `LibrarySelector` inside `main()` (after the Tk gate, same place as the other imports); build three selectors from `config.LIBRARY_CATEGORIES` with `config.LIBRARY_ROOT / folder`; pass `selector_controllers=[...]`; call each `send_initial()` after `volume.send_initial()`. Update docstring L5-8 (lists /pp/bpm, /pp/play, /pp/epic, /pp/volume).

---

### `python_app/tests/test_library_logic.py` (test, new)

**Analog:** `python_app/tests/test_epic_logic.py` L1-22: `from __future__ import annotations`, `import config`, a `_make_controller(**overrides)` helper returning `(controller, sent)` with `send=sent.append`. Add `tmp_path` scan tests (RESEARCH "Scan test using tmp_path"), a real-library test (`classic` in each folder, melodies also `classic_lead`, `classic_lead_loud`, no `_template`), and controller tests: change sends once in wire form; same pick sends nothing and notifies nothing; `send_initial` sends `auto` and doesn't notify; vanished/unknown name still sent; `options()` rescans on each call.

### `python_app/tests/test_osc_client.py` (test, extend)

**Analog:** L70-80: `patch.object(client._client, "send_message", side_effect=OSError("boom"))`, assert `is False` and one stderr line. Real round-trip pattern at L82-95 using `_bound_udp_socket()` + `OscMessage(datagram).params`; use it for the string payload. Also add BuildError/OverflowError cases.

### `python_app/tests/test_view_tk.py` (test, extend)

**`_build_all` (L66-93):** builds controllers with list-append fakes and returns a `types.SimpleNamespace`. Add three `LibrarySelector`s on `tmp_path` folders (or take `tmp_path`), pass `selector_controllers=`, and return them plus their sent lists. `_build_window` etc. wrap `_build_all`, so they keep working.

**GUI-07 test model** (L435-454, `test_volume_slider_keeps_arrow_shortcuts_on_bpm`):
```python
tk_root.focus_force()
pump(tk_root, 100)
tk_root.event_generate("<Up>")
pump(tk_root, 300)
assert controller.value == 121
```
Invoke menu entries with `menu.invoke(i)`, assert `focus_get()` is not a selector widget and `str(button["takefocus"]) == "0"` (same assertion style as L301), then fire `<Up>`/`<Shift-Down>`. Test rebuild by running the postcommand directly (`tk_root.tk.eval(menu.cget("postcommand"))`), twice, to prove idempotence; do not synthesize clicks (RESEARCH Pitfall 7). `test_window_layout_order` (L457-471) must pass unmodified.

## Shared Patterns

### Fire-and-forget send, engine is the validator
**Source:** `bpm_logic.py` L268-284 and `osc_client.py` L53-58. Controllers ignore the send return value; OscClient swallows `(OSError, OverflowError, BuildError)`. Apply to `LibrarySelector` and `send_selection`.

### Send-initial on launch, no notify
**Source:** `bpm_logic.py` L286-288 and `main.py` L62-65. Apply to all three selectors (D-04).

### takefocus=0 and root-level key bindings
**Source:** `view.py` L63/L80/L123/L138/L195/L240 and L167-170. Apply to every new widget (GUI-07).

### View has no OSC import
**Source:** `view.py` docstring L3-6. Selectors get a pre-bound `send` from `main.py`.

## No Analog Found

| File/Part | Role | Data Flow | Reason |
|---|---|---|---|
| `scan_library()` in `library_logic.py` | utility | file-I/O | No folder-scanning code exists; use RESEARCH Pattern 1 and mirror `supercollider/core/loader.scd:35-65` |
| `tk.OptionMenu` with `postcommand` rebuild | component | event-driven | No dropdown exists in `view.py`; use RESEARCH Pattern 3 (probed on Tk 9.0.3) |

## Notes for the planner
- Engine needs no change (`~ppSelect` already posts confirmations; RESEARCH Engine Contract).
- Pitfalls to carry into plans: `postcommand` fires twice (delete before add); tuple padx only in `pack()`; fixed `width=` so window does not resize; D-05 means re-picking does not reload the file (document it).

## Metadata

**Analog search scope:** `python_app/` (all modules and tests), `supercollider/library/`
**Files scanned:** about 12 (git-tracked list reviewed in full)
**Pattern extraction date:** 2026-10-12
