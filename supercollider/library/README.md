# The variation library

## What this folder is

The sound of PedalPulse is split into a small core and this library. The library
has three folders:

- `progressions/` holds the chords the whole band follows: the bass, the pad,
  the arp and the lead all play the same chord at the same time.
- `melodies/` holds the arpeggio and the lead.
- `palettes/` holds the sounds (which instrument plays which part).

Each `.scd` file in a folder is one named variation. Its file name without
`.scd` is its name everywhere: in the post window, over OSC, and in the app's
dropdowns. `classic.scd` in each folder is the original sound,
so picking `classic` always brings it back. Right now the library holds eight
progressions:

- `classic`: the original A-minor groove, one chord (Am) in every bar.
- `anthem`: Am F C G, a new chord every bar.
- `rocker`: Am G F G.
- `lift`: Am F G G.
- `return`: Am C G F.
- `deep`: Am Am F G, with two bars on each chord, so the changes are slower.
- `melancholy`: Am Em F Dm.
- `drama`: Am Dm F E, with a bright major E at the end that leads back to Am.

It also holds `melodies/classic`, `melodies/classic_lead` (the classic arp plus
a faint lead one octave up), `melodies/classic_lead_loud` (the same lead, but as
loud as the arp so it is easy to hear) and `palettes/classic`. Every file also
has a `desc` line at the top that says what it sounds like.

## The one rule

**Never edit, rename or delete a file after it has been committed. Add a new
file instead.** For example, if `classic_lead` is a little loud, do not change
it: add `classic_lead_soft.scd` next to it. That way every earlier variation
stays selectable and sounds exactly as it did. `bash scripts/check.sh` fails
when a committed file was changed.

A name is 1 to 64 characters from lowercase `a-z`, `0-9` and `_`. It does not
start with `_`, and `auto` is reserved (it means "let the engine choose"), as are
`parent` and `proto` (they are special slots of the SuperCollider Event that holds
the library). For
progressions, `auto` lets the engine rotate through the progressions by itself
(see "Progressions and Auto" below). For melodies and palettes it still plays
classic until their own phases arrive.

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

Picking a name sends it to the engine, which prints a line in the SuperCollider
post window. A melody or a palette switches at the next bar line. A progression
switches at the end of the progression that is playing (at most 8 bars with the
files that ship, about 15 seconds at 128 BPM) and then stays on the new one.
At every progression change the post window prints
`PedalPulse: progression <name>: <chords>`; use that name when you describe what
you heard.

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
- Any of the three with `'auto'` lets the engine choose: progressions rotate by
  themselves, melodies and palettes still play classic.

Sending the same name again re-reads the file from disk, so you can save a
change to a new file and hear it at the next bar line without restarting.

A broken file is refused. The post window shows
`PedalPulse ERROR: library file <path> ...` and the music keeps playing what it
was playing. If a file works on load but fails while playing, that bar plays the
classic part, and after 3 failed bars the category goes back to classic.

## Progressions and Auto

A progression is a list of chords that bass, pad, arp and lead all follow. It
always changes at the end of its own cycle (the whole list of chords), never in
the middle, so a pick can take a few seconds to be heard.

When Progression is on Auto:

- After a Start (or a fresh engine) Auto plays `classic` first.
- If you pick Auto in the middle of a ride, it keeps the progression that is
  playing at that moment, for one full stay, and only then starts rotating.
- It then changes progression every 2 to 3 minutes, always at the end of a cycle.
- It never picks the progression that is playing, and never one of the last two
  it played.
- A progression file you add while the engine runs joins the rotation by itself.
- The post window prints `PedalPulse: progression auto seed <n>` once when the
  engine starts. The same seed on a freshly started SuperCollider gives the same
  order, so a ride you liked can be replayed.
- Stop and then Start begins again on `classic`, then picks differently from the
  last run: the draws continue until SuperCollider is restarted.

You can always see what Auto chose in the post window: it prints
`PedalPulse: progression <name>: <chords>` at every change.

## Write a new progression

Copy `progressions/_template.scd` to a new name and change the copy. A
progression is only chord data:

- `chords` is a list of chords. Each chord has a `root` (semitones above A: A is
  0, C 3, D 5, E 7, F 8, G 10) and a `quality`, `\min` or `\maj`. For any other
  chord give `intervals` instead, such as `[0, 3, 7, 10]`.
- `bars` on a chord says how many bars it lasts, or `barsPerChord` on the whole
  file sets it for every chord.
- The whole cycle is at most 16 bars. 8 bars or less keeps a pick quick, because
  a new pick waits for the end of the cycle that is playing.
- The engine always plays in A, so a file only says which chord, never which key.
- Bass, pad, arp and lead follow the chords by themselves. If you want something
  special, `bass` and `pad` generators in the file replace the core's part.

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
- Progressions provide `chords` (chord data; the core plays the bass and the pad
  from it) or, like classic, `bass` and `pad` generators. Melodies provide
  `arp`, `lead` and an optional `init`. Palettes provide `defs` (optional) and
  `roles`.
- The engine moves a melody's notes onto the current chord: the classic arp's A,
  C, E become the root, third and fifth of each chord. A melody that works out
  its own notes from `plan[\chord]` sets `ownHarmony: true` in its Event, and
  then its notes are left as they are.
- A generator is `{ |plan, state| }` and returns one bar as an Array of
  `[note, dur, amp, legato]` rows. The durs add up to exactly 4 beats over the
  bar. `note` is a MIDI number, a chord (an Array of MIDI numbers) or `\rest`.
  `amp` is 0 to 1.
- `plan` has `bar`, `songBar`, `phraseBar` and `role`, and the harmony keys
  `progression`, `chord`, `nextChord`, `changesNext`, `chordBar`, `chordBars`,
  `cycleBar`, `cycleLen`, `voicing` and `scale`.
- Randomness is allowed (`rrand`, `choose`). It is seeded per (song, bar, role),
  so a restart plays the same bars.
- A missing role falls back to classic, and a missing lead is silent.
- The voice contract for a palette sound: controls `out`, `amp`, `freq` and
  `gate` (drums: `out` and `amp`), an envelope that ends the synth
  (`doneAction: 2`), `Out.ar(out, ...)` only (never bus 0), and a name that
  starts with `pp_<palette>_`.
- Later phases only add optional keys, so a committed file never needs an edit.
