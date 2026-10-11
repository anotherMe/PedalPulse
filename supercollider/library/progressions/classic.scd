// Library progression: classic (the shipped v1.0 A-minor groove).
//
// FINAL when first committed: committed library files are never edited
// (scripts/check.sh guards it). A different progression is a new file.
//
// Generator contract: { |plan, state| } returns one bar as an Array of
// [note, dur, amp, legato] rows; note is a Number, an Array of Numbers (a
// chord) or \rest, and the durs sum to 4.0. No ~ variables, no clocks, no
// server.
(
desc: "Shipped A-minor groove: offbeat A1 bass with C2 at the bar end, Am pad alternating with Am plus a passing F",

bass: { |plan, state|
	// Offbeat eighths: A1 (MIDI 33) on the "and" of beats 1-3, C2 (MIDI 36) on
	// the "and" of beat 4 (the note change at the bar end). Downbeat eighths rest.
	// amp 0.1 is the default event amp the shipped bass pattern relied on (it set
	// no \amp, so the SynthDef's own default of 0.25 never applied): reproduce
	// it, never "fix" it (D-02).
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
	// Am, then Am with a passing tone (F), one chord per bar.
	var chord = if (plan[\songBar].even) { [45, 48, 52] } { [45, 48, 53] };
	[[chord, 4, 0.06, 0.9]]
}
)
