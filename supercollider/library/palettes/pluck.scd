// Library palette: pluck (bright digital plucks and pops).
//
// FINAL when first committed: committed library files are never edited
// (scripts/check.sh guards it). A different sound or level is a new file.
//
// Voices: its own crisp, very short hi-hat; a pulse bass with a fast filter pop that
// jumps an octave (bassStyle: \octave: root, root an octave up, root, then the
// pickup); a bright plucked-string arp (a noise burst through a tuned delay line);
// a pulse-width-modulated pad that shimmers; and a two-operator FM pluck lead. The
// kick and the clap stay classic's.
//
// Nothing runs at load: the file's value is the Event below, and the SynthDefs
// are only added when the engine calls defs (inside a Routine, then s.sync).
//
// Level: each voice ends with one literal gain constant (the last multiplier
// before Out.ar). They were set with scripts/palette_level.sh pluck so that the
// palette sits within 0.75 dB of classic in the full mix; the row amps (hat 0.15,
// bass 0.1, arp 0.1, pad 0.06) are shared by every palette, so loudness is set
// only here. Every cutoff that follows the note is clamped with .min(12000) and
// the resonant filter sits behind .tanh.
(
desc: "Pluck: bright digital plucked arp and FM pluck lead, octave-popping pulse bass, shimmering pulse-width pad, crisp short hi-hat",

defs: {
	SynthDef(\pp_pluck_hat, { |out = 0, amp = 0.15|
		var env, sig;
		env = EnvGen.kr(Env.perc(0.0005, 0.04, 1, -6), doneAction: 2);   // a tick, 40 ms: much shorter than classic's 120 ms
		sig = HPF.ar(WhiteNoise.ar(), 9500) * env * amp;                  // and brighter than classic's 7000 Hz
		Out.ar(out, (sig * 1.3) ! 2);
	}).add;

	SynthDef(\pp_pluck_bass, { |out = 0, amp = 0.1, freq = 55, gate = 1|
		var env, fenv, sig;
		env = EnvGen.kr(Env.adsr(0.002, 0.1, 0.5, 0.05), gate, doneAction: 2);
		fenv = EnvGen.kr(Env.perc(0.002, 0.12));                          // the filter pops open, then closes
		sig = Pulse.ar(freq * [1, 1.004], 0.45);                          // two pulses -> stereo
		sig = RLPF.ar(sig, ((freq * 2) + (fenv * freq * 9)).min(6000), 0.35).tanh;
		Out.ar(out, sig * env * amp * 0.85);
	}).add;

	SynthDef(\pp_pluck_arp, { |out = 0, amp = 0.1, freq = 440, gate = 1|
		var env, sig;
		env = EnvGen.kr(Env.adsr(0.001, 0.15, 0.25, 0.08), gate, doneAction: 2);
		// A noise burst fed into a delay line tuned to the note (a plucked string);
		// two slightly detuned strings -> stereo. The delay is clamped so a very low
		// note still fits the line.
		sig = Pluck.ar(WhiteNoise.ar(0.5), 1, 0.05, (freq * [1, 1.003]).max(20).reciprocal, 1.2, 0.3);
		Out.ar(out, sig * env * amp * 2.5);
	}).add;

	SynthDef(\pp_pluck_pad, { |out = 0, amp = 0.06, freq = 220, gate = 1|
		var env, width, sig;
		env = EnvGen.kr(Env.adsr(0.35, 0.3, 0.7, 1.2), gate, doneAction: 2);  // gate lets Stop release it
		width = SinOsc.kr([0.19, 0.27, 0.33], 0, 0.3, 0.5);               // three pulse widths drifting between 0.2 and 0.8
		sig = Pulse.ar(freq * [1, 1.005, 0.996], width);
		sig = Splay.ar(LPF.ar(sig, 3000));
		Out.ar(out, sig * env * amp * 0.55);
	}).add;

	SynthDef(\pp_pluck_lead, { |out = 0, amp = 0.1, freq = 440, gate = 1|
		var env, idx, mod, sig;
		env = EnvGen.kr(Env.adsr(0.003, 0.12, 0.5, 0.15), gate, doneAction: 2);
		idx = EnvGen.kr(Env.perc(0.001, 0.18));                           // the FM brightness falls fast: a pluck
		mod = SinOsc.ar(freq * 2) * freq * 3 * idx;
		sig = SinOsc.ar((freq * [1, 1.003]) + mod);
		Out.ar(out, sig * env * amp * 0.5);
	}).add;
},

// How the bass moves (D-02): offbeat eighths, root, root an octave up, root, then
// the pickup, on the bar's chord, under every progression.
bassStyle: \octave,

// Role -> voice. The kick and the clap are left out: they play classic's.
roles: (
	hat: (instrument: \pp_pluck_hat),
	bass: (instrument: \pp_pluck_bass),
	arp: (instrument: \pp_pluck_arp),
	pad: (instrument: \pp_pluck_pad),
	lead: (instrument: \pp_pluck_lead)
)
)
