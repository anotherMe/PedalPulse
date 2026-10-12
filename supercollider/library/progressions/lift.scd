// Library progression: lift (Am F G G, G held for two bars).
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
desc: "Lifting: Am and F, then G held for two bars to build back up",

barsPerChord: 1,

chords: [
	(root: 0, quality: \min),   // Am
	(root: 8, quality: \maj),   // F
	(root: 10, quality: \maj),  // G
	(root: 10, quality: \maj)   // G again: G is held for two bars
]
)
