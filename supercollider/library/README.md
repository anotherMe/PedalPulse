# The variation library

## What this folder is

The sound of PedalPulse is split into a small core and this library. The library
has three folders:

- `progressions/` holds the chords and the bass line.
- `melodies/` holds the arpeggio and the lead.
- `palettes/` holds the sounds (which instrument plays which part).

Each `.scd` file in a folder is one named variation. Its file name without
`.scd` is its name everywhere: in the post window, over OSC, and in the app's
dropdowns. `classic.scd` in each folder is the original sound,
so picking `classic` always brings it back. Right now the library holds
`progressions/classic`, `melodies/classic`, `melodies/classic_lead` (the classic
arp plus a faint lead one octave up) and `palettes/classic`.

## The one rule

**Never edit, rename or delete a file after it has been committed. Add a new
file instead.** For example, if `classic_lead` is a little loud, do not change
it: add `classic_lead_soft.scd` next to it. That way every earlier variation
stays selectable and sounds exactly as it did. `bash scripts/check.sh` fails
when a committed file was changed.

A name is 1 to 64 characters from lowercase `a-z`, `0-9` and `_`. It does not
start with `_`, and `auto` is reserved (it means "let the engine choose", which
plays classic for now).

The `_template.scd` file in each folder is an example for writing a new file.
Copy it to a new name and change the copy. A `_template.scd` can never be
selected.

## Pick a variation from the app

The PedalPulse window has a column on the right with three dropdowns: Palette,
Progression and Melody. Each one starts on Auto. When you open a dropdown it
lists Auto, then `classic`, then every other file in its folder from A to Z,
by file name without `.scd`. Files whose names start with `_` (such as
`_template`) never appear.

A name longer than 20 characters is cut short on the closed dropdown, but it
always shows in full when the dropdown is open.

Opening a dropdown reads the folder again, so a file you just added is there to
pick with no restart. A file you removed is gone from the list the next time
you open it.

Picking a name sends it to the engine. The engine switches at the next bar line
and prints a line in the SuperCollider post window.

Picking the name that is already selected does nothing, unless the last send of
it failed: then picking it again sends it again. To hear a file again
after you changed it, pick another name and then pick it back, or use the
one-liner below.

The app always starts on Auto; it does not remember what you picked last time.

## Try a variation while the music plays

Open a terminal in the PedalPulse folder, with the engine running, and paste:

```
.venv/bin/python -c "from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/melody', 'classic_lead')"
```

That switches the melody to `classic_lead` at the next bar line, without
stopping the music. To go back, send the same line with `'classic'`:

```
.venv/bin/python -c "from pythonosc.udp_client import SimpleUDPClient as C; C('127.0.0.1', 57120).send_message('/pp/melody', 'classic')"
```

The other two categories work the same way, with their own address:

- Progression: `send_message('/pp/progression', 'classic')`
- Palette: `send_message('/pp/palette', 'classic')`
- Any of the three with `'auto'` lets the engine choose (it plays classic for now).

Sending the same name again re-reads the file from disk, so you can save a
change to a new file and hear it at the next bar line without restarting.

A broken file is refused. The post window shows
`PedalPulse ERROR: library file <path> ...` and the music keeps playing what it
was playing. If a file works on load but fails while playing, that bar plays the
classic part, and after 3 failed bars the category goes back to classic.

## Check everything

```
bash scripts/check.sh
```

This runs the library check and then the full smoke test. For the faster part
that only covers the library, while you are adding a variation:

```
bash scripts/check.sh --library-only
```

The library check opens every `.scd` file here, the `_template.scd` files
included, and prints one `LIBCHECK OK: <folder>/<name>` line for each. It also
checks that every committed file is unchanged, and that every palette sound
stays on its own bus (so it always goes through the master limiter), lets go
when the gate closes, and frees itself.

## File contract (for authors)

- One Event per file (everything inside one pair of parentheses). Nothing runs
  at load: no `~` variables, no `Pdef` or `Pbindef`, no clocks, no server, no
  files, no `Synth`. The check lints for these and fails the file.
- `desc` is required: one plain sentence saying what it sounds like.
- Read and write Events with `[\key]`, never dot syntax.
- Progressions provide `bass` and `pad`. Melodies provide `arp`, `lead` and an
  optional `init`. Palettes provide `defs` (optional) and `roles`.
- A generator is `{ |plan, state| }` and returns one bar as an Array of
  `[note, dur, amp, legato]` rows. The durs add up to exactly 4 beats over the
  bar. `note` is a MIDI number, a chord (an Array of MIDI numbers) or `\rest`.
  `amp` is 0 to 1.
- `plan` has `bar`, `songBar`, `phraseBar` and `role`.
- Randomness is allowed (`rrand`, `choose`). It is seeded per (song, bar, role),
  so a restart plays the same bars.
- A missing role falls back to classic, and a missing lead is silent.
- The voice contract for a palette sound: controls `out`, `amp`, `freq` and
  `gate` (drums: `out` and `amp`), an envelope that ends the synth
  (`doneAction: 2`), `Out.ar(out, ...)` only (never bus 0), and a name that
  starts with `pp_<palette>_`.
- Later phases only add optional keys, so a committed file never needs an edit.
