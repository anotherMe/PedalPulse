// Library progression: return (Am C G F, a new chord every bar).
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
desc: "Bright return: Am C G F, a new chord every bar, rising then settling",

barsPerChord: 1,

chords: [
	(root: 0, quality: \min),   // Am
	(root: 3, quality: \maj),   // C
	(root: 10, quality: \maj),  // G
	(root: 8, quality: \maj)    // F
]
)
