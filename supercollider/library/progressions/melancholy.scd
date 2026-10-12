// Library progression: melancholy (Am Em F Dm, a new chord every bar).
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
desc: "Dark and melancholy: Am Em F Dm, a new chord every bar",

barsPerChord: 1,

chords: [
	(root: 0, quality: \min),   // Am
	(root: 7, quality: \min),   // Em
	(root: 8, quality: \maj),   // F
	(root: 5, quality: \min)    // Dm
]
)
