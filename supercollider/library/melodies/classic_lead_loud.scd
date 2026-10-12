// Library melody: classic_lead_loud (the shipped arp plus a clearly audible lead).
//
// FINAL when first committed: committed library files are never edited
// (scripts/check.sh guards it). A different melody is a new file.
//
// Same as classic_lead, but the lead plays at the arp's own level (0.1)
// instead of 0.025. classic_lead's lead was too faint to hear in the mix, so
// this variation makes the switch audible: the arp gains a bright octave-up
// double. The lead's sound comes from the palette: the classic palette maps
// the lead role to the arp voice.
//
// Generator contract: { |plan, state| } returns one bar as an Array of
// [note, dur, amp, legato] rows; the durs sum to 4.0. No ~ variables, no
// clocks, no server.
(
desc: "Shipped arp plus a lead doubling it one octave up at the arp's level",

arp: { |plan, state|
	// A3, C4, E4, C4 -- identical to classic.
	var notes = [57, 60, 64, 60];
	Array.fill(16, { |i| [notes[i % 4], 0.25, 0.1, 0.6] })
},

lead: { |plan, state|
	// A4, C5, E5, C5 -- the arp's notes 12 semitones up, at the arp's amp 0.1.
	var notes = [69, 72, 76, 72];
	Array.fill(16, { |i| [notes[i % 4], 0.25, 0.1, 0.6] })
}
)
