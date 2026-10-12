// Library progression: deep (Am Am F G, a new chord every 2 bars).
//
// FINAL when first committed: committed library files are never edited
// (scripts/check.sh guards it). A different progression is a new file.
//
// Chord data only. Each chord is a root plus a quality: root is the number of
// semitones above the key note (the engine supplies the key: A), quality is maj
// or min. The engine plays the bass, the pad, and moves the arp and lead onto each
// chord, so all four layers sit on the same chord every two bars. No functions,
// no ~ variables, no clocks, no server.
(
desc: "Deep and hypnotic: Am held for four bars, then F and G for two bars each",

// Two bars per chord: an 8-bar cycle, with Am (listed twice) held for 4 bars.
barsPerChord: 2,

chords: [
	(root: 0, quality: \min),   // Am
	(root: 0, quality: \min),   // Am again: Am is held for four bars
	(root: 8, quality: \maj),   // F
	(root: 10, quality: \maj)   // G
]
)
