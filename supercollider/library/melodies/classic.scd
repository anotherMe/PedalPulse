// Library melody: classic (the shipped v1.0 arp).
//
// FINAL when first committed: committed library files are never edited
// (scripts/check.sh guards it). A different melody is a new file.
//
// Generator contract: { |plan, state| } returns one bar as an Array of
// [note, dur, amp, legato] rows; note is a Number, an Array of Numbers (a
// chord) or \rest, and the durs sum to 4.0. This file uses no ~ variables, no
// clocks and no server. There is no lead key: the lead layer plays rests under
// classic (D-05).
(
desc: "Shipped arp: A3 C4 E4 C4 sixteenths, silent lead",

arp: { |plan, state|
	// A3, C4, E4, C4 -- an octave+ above the A-minor bass root, 16 sixteenths a bar.
	var notes = [57, 60, 64, 60];
	Array.fill(16, { |i| [notes[i % 4], 0.25, 0.1, 0.6] })
}
)
