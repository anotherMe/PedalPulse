// Library progression: TEMPLATE (an example for writing a new progression).
//
// This file can never be selected: the leading _ fails the name rule. Copy it
// to a NEW lowercase file name in this folder (for example my_groove.scd) and
// change the copy. Never edit a committed file: scripts/check.sh fails when one
// changes, and every variation stays selectable because it stays unchanged.
//
// The contract, in short:
//   - The file's value is ONE Event in parentheses. Nothing runs at load: no ~
//     variables, no Pdef or Pbindef, no clocks, no server, no files.
//   - desc is required: one plain sentence saying what it sounds like.
//   - Read and write Events with [\key], never dot syntax.
//   - A progression is chord data: chords is an Array of 1 to 16 chords. Each
//     chord is either (root: 0-11, quality: \maj or \min) or
//     (root: 0-11, intervals: [0, 3, 7]) for any 3- or 4-note chord (the
//     intervals are semitones above the chord's root; they win over quality).
//   - Pace: bars: 1-8 on a chord says how many bars that chord lasts, or
//     barsPerChord: 1-8 on the whole file sets it for every chord. The cycle (all
//     chords added up) is at most 16 bars; 8 or less keeps a pick quick to hear,
//     because a new pick waits for the end of the current cycle.
//   - root is the number of semitones above the key note A (A 0, C 3, D 5, E 7,
//     F 8, G 10). The engine always plays in A and supplies the key, so a file
//     only says "which chord", never "which key". Listing the same chord twice in
//     a row holds it for the sum of their bars (see deep.scd).
//   - The core plays the bass (offbeat eighths on the chord's root, with a leading
//     note before each chord change) and the pad (the nearest voicing, held for
//     the chord). The arp and the lead follow the chord automatically.
//   - A file may still add bass and/or pad generators { |plan, state| } to replace
//     the core's part. A generator returns one bar as an Array of rows
//     [note, dur, amp, legato] whose durs add up to exactly 4 beats; note is a MIDI
//     number, a chord (an Array of MIDI numbers) or \rest. plan then also has
//     chord, nextChord, changesNext, chordBar, chordBars, cycleBar, cycleLen,
//     voicing, scale and progression, next to bar, songBar, phraseBar and role.
//     Every note a generator plays must be in its bar's chord (the check enforces
//     it).
//   - desc stays required; nothing runs at load.
//
// This template plays Am F C G, one chord per bar.
(
desc: "Template: Am F C G, a new chord every bar, to copy and change",

barsPerChord: 1,

chords: [
	(root: 0, quality: \min),   // Am
	(root: 8, quality: \maj),   // F
	(root: 3, quality: \maj),   // C
	(root: 10, quality: \maj)   // G
]
)
