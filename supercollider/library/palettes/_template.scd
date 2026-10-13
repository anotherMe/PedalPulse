// Library palette: TEMPLATE (an example for writing a new palette).
//
// This file can never be selected: the leading _ fails the name rule. Copy it
// to a NEW lowercase file name in this folder (for example warm.scd) and change
// the copy. Never edit a committed file: scripts/check.sh fails when one
// changes, and every variation stays selectable because it stays unchanged.
//
// The contract, in short:
//   - The file's value is ONE Event in parentheses. Nothing runs at load: the
//     SynthDefs are only added when the engine calls defs, not when the file is
//     read.
//   - desc is required: one plain sentence saying what it sounds like.
//   - Read and write Events with [\key], never dot syntax.
//   - defs (optional) is a Function that adds this palette's voices.
//   - roles maps a role (kick, hat, clap, bass, pad, arp, lead) to
//     (instrument: \voiceName). A role left out plays classic's voice.
//
// The voice contract (scripts/check.sh proves it for every voice on a bare
// server, so a voice that breaks it makes the check fail):
//   - controls: out, amp, and for the pitched roles (bass, pad, arp, lead) also
//     freq and gate;
//   - an envelope that ends the synth: EnvGen with doneAction: 2 (a gated
//     envelope for pitched voices, so Stop can release them with gate 0);
//   - Out.ar(out, ...) only: never bus 0, so every voice goes through the master
//     limiter;
//   - the name starts with pp_<palette>_ (for example pp_warm_arp), so voices of
//     different palettes never overwrite each other. This rule is enforced: a
//     palette file whose voice does not start with its own pp_<palette>_ is
//     refused (a role may still point at one of classic's six voices, for example
//     the drums).
//
// bassStyle (optional) is the rhythm of the bass under EVERY progression, the
// classic progression included. Three values:
//   \eighths     offbeat eighths, the classic bass groove (the default when the key
//                is left out);
//   \sixteenths  a rolling bass in sixteenths;
//   \octave      offbeat pops that jump between two octaves.
// Only the classic palette keeps a progression's own bass generator; every other
// palette plays its bassStyle on the chords of the bar.
//
// Keep voices short and tame: releases about 1.5 s at most, filter cutoffs that
// follow the note clamped with .min(12000), and no reverb or delay inside a voice
// (the engine's EPIC effects do that).
//
// The level loop. A new palette has to sit at the same loudness as classic. Before
// the file's first commit run
//
//   bash scripts/palette_level.sh <name>
//
// and change ONLY the gain numbers (the constant that multiplies each voice's
// output) until the gap to classic is 0.75 dB or less and every CHECK OK line
// appears. Then commit the file once: a committed palette file can never be edited,
// so a gain you got wrong would stay.
//
// An example voice, as it would sit inside defs (kept as a comment here so this
// template adds nothing):
//
//   SynthDef(\pp_warm_arp, { |out = 0, amp = 0.1, freq = 440, gate = 1|
//       var env = EnvGen.kr(Env.adsr(0.01, 0.1, 0.5, 0.2), gate, doneAction: 2);
//       var sig = LPF.ar(Saw.ar([freq, freq * 1.002]), (freq * 3).min(12000));
//       Out.ar(out, sig * env * amp);
//   }).add;
//
// This template adds no voices and maps all seven roles to the classic ones.
(
desc: "Template: the shipped voices under their classic names, to copy and change",

defs: {
},

// \eighths, \sixteenths or \octave: the bass rhythm under every progression.
bassStyle: \eighths,

roles: (
	kick: (instrument: \ppKick),
	hat: (instrument: \ppHat),
	clap: (instrument: \ppClap),
	bass: (instrument: \ppBass),
	arp: (instrument: \ppArp),
	pad: (instrument: \ppPad),
	lead: (instrument: \ppArp)
)
)
