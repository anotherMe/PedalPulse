// Library progression: drama (Am Dm F E, a new chord every bar).
//
// FINAL when first committed: committed library files are never edited
// (scripts/check.sh guards it). A different progression is a new file.
//
// Chord data only. Each chord is a root plus a quality: root is the number of
// semitones above the key note (the engine supplies the key: A), quality is maj
// or min. The engine plays the bass, the pad, and moves the arp and lead onto each
// chord, so all four layers sit on the same chord every bar. No functions, no ~
// variables, no clocks, no server.
(
desc: "Dramatic: Am Dm F E, with a major E (G sharp) that pulls back to Am",

barsPerChord: 1,

chords: [
	(root: 0, quality: \min),   // Am
	(root: 5, quality: \min),   // Dm
	(root: 8, quality: \maj),   // F
	// E major on purpose (D-05): its G sharp is the leading note that pulls back to Am.
	(root: 7, quality: \maj)    // E
]
)
