// Library melody: TEMPLATE (an example for writing a new melody style).
//
// This file can never be selected: the leading _ fails the name rule. Copy it
// to a NEW lowercase file name in this folder (for example my_lead.scd) and
// change the copy. Never edit a committed file: scripts/check.sh fails when one
// changes, and every variation stays selectable because it stays unchanged.
//
// The contract, in short:
//   - The file's value is ONE Event in parentheses. Nothing runs at load: no ~
//     variables, no Pdef or Pbindef, no clocks, no server, no files.
//   - desc is required: one plain sentence saying what it sounds like.
//   - Read and write Events with [\key], never dot syntax.
//   - A melody provides arp and/or lead, and may provide init. A missing arp
//     plays classic's arp; a missing lead is silent.
//   - init is { |state| } and runs once when this file starts playing, to set
//     up the state Event the generators share (here, a bar counter).
//   - A generator is { |plan, state| } and returns one bar as an Array of rows
//     [note, dur, amp, legato]. The durs of the rows add up to exactly 4 beats.
//     note is a MIDI number, a chord (an Array of MIDI numbers) or \rest. amp is
//     0 to 1. legato is the note length as a fraction of dur.
//   - plan has bar, songBar, phraseBar (songBar % 8) and role. Later phases only
//     ever ADD optional keys, so a file written today keeps working.
//   - rrand and choose are allowed: they are seeded per (song, bar, role), so a
//     restart plays the same bars.
//
// This template plays classic's arp and a lead that rests for the whole bar.
(
desc: "Template: the shipped arp with a silent lead, to copy and change",

init: { |state|
	state[\count] = 0;
},

arp: { |plan, state|
	// A3, C4, E4, C4 -- sixteen sixteenths fill the 4 beats.
	var notes = [57, 60, 64, 60];
	state[\count] = state[\count] + 1;
	Array.fill(16, { |i| [notes[i % 4], 0.25, 0.1, 0.6] })
},

lead: { |plan, state|
	// One rest that fills the whole bar. Replace it with notes to hear a lead.
	[[\rest, 4, 0, 1]]
}
)
