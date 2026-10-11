// Library progression: TEMPLATE (an example for writing a new progression).
//
// This file can never be selected: the leading _ fails the name rule. Copy it
// to a NEW lowercase file name in this folder (for example my_groove.scd) and
// change the copy. Never edit a committed file: scripts/check.sh fails when one
// changes, and every variation stays selectable because it stays unchanged.
//
// The contract, in short:
//   - The file's value is ONE Event in parentheses. Nothing runs at load: no ~
//     variables, no Pdef or Pbindef, no clocks, no server, no files.
//   - desc is required: one plain sentence saying what it sounds like.
//   - Read and write Events with [\key], never dot syntax.
//   - A progression provides bass and pad (either one is enough; a missing one
//     plays classic's part).
//   - A generator is { |plan, state| } and returns one bar as an Array of rows
//     [note, dur, amp, legato]. The durs of the rows add up to exactly 4 beats.
//     note is a MIDI number, a chord (an Array of MIDI numbers) or \rest. amp is
//     0 to 1. legato is the note length as a fraction of dur.
//   - plan has bar, songBar, phraseBar (songBar % 8) and role. Later phases only
//     ever ADD optional keys, so a file written today keeps working.
//   - state is an empty Event that lives as long as this file is selected. A
//     generator may keep notes in it between bars.
//   - rrand and choose are allowed: they are seeded per (song, bar, role), so a
//     restart plays the same bars.
//
// This template reproduces classic's rows.
(
desc: "Template: the shipped A-minor groove, to copy and change",

bass: { |plan, state|
	// Offbeat eighths: A1 (MIDI 33) on the "and" of beats 1-3, C2 (MIDI 36) on
	// the "and" of beat 4. Eight rows of half a beat fill the 4 beats.
	[
		[\rest, 0.5, 0.1, 0.8],
		[33, 0.5, 0.1, 0.8],
		[\rest, 0.5, 0.1, 0.8],
		[33, 0.5, 0.1, 0.8],
		[\rest, 0.5, 0.1, 0.8],
		[33, 0.5, 0.1, 0.8],
		[\rest, 0.5, 0.1, 0.8],
		[36, 0.5, 0.1, 0.8]
	]
},

pad: { |plan, state|
	// One chord for the whole bar: Am, then Am with a passing F on odd bars.
	var chord = if (plan[\songBar].even) { [45, 48, 52] } { [45, 48, 53] };
	[[chord, 4, 0.06, 0.9]]
}
)
