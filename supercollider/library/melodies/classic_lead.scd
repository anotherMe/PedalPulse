// Library melody: classic_lead (the shipped arp plus a faint lead).
//
// FINAL when first committed: committed library files are never edited
// (scripts/check.sh guards it). A different melody is a new file.
//
// The arp is identical to classic's. The lead doubles it one octave up
// (12 semitones: 69 72 76 72 against the arp's 57 60 64 60). 0.025 is about
// 12 dB under the arp's 0.1, so the lead reads as shimmer, not as a new part.
// If the level should change after listening, add a new file (for example
// classic_lead_soft.scd) and never edit this one. The lead's sound comes from
// the palette: the classic palette maps the lead role to the arp voice.
//
// Generator contract: { |plan, state| } returns one bar as an Array of
// [note, dur, amp, legato] rows; the durs sum to 4.0. No ~ variables, no
// clocks, no server.
(
desc: "Shipped arp plus a faint lead doubling it one octave up",

arp: { |plan, state|
	// A3, C4, E4, C4 -- identical to classic.
	var notes = [57, 60, 64, 60];
	Array.fill(16, { |i| [notes[i % 4], 0.25, 0.1, 0.6] })
},

lead: { |plan, state|
	// A4, C5, E5, C5 -- the arp's notes 12 semitones up, at amp 0.025.
	var notes = [69, 72, 76, 72];
	Array.fill(16, { |i| [notes[i % 4], 0.25, 0.025, 0.6] })
}
)
