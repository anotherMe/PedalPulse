// Library palette: acid (squelchy 303-style resonant sounds).
//
// FINAL when first committed: committed library files are never edited
// (scripts/check.sh guards it). A different sound or level is a new file.
//
// Voices: a resonant saw bass whose filter snaps open and closes on every note
// (the 303 squelch), rolling in sixteenths (bassStyle: \sixteenths); a bright
// resonant pulse arp; a sharp acid lead, a saw through a resonant filter that
// sweeps down on each note (its own voice, not the arp's); and a thin pulse pad
// with a slowly moving width. The drums are left out on purpose: they stay
// classic's.
//
// Nothing runs at load: the file's value is the Event below, and the SynthDefs
// are only added when the engine calls defs (inside a Routine, then s.sync).
//
// Level: each voice ends with one literal gain constant (the last multiplier
// before Out.ar). They were set with scripts/palette_level.sh acid so that the
// palette sits within 0.75 dB of classic in the full mix; the row amps (bass 0.1,
// arp 0.1, pad 0.06) are shared by every palette, so loudness is set only here.
// Every resonant filter sits behind .tanh and every cutoff is clamped with
// .min(12000), so no note can blow up the engine.
(
desc: "Acid: squelchy 303-style resonant bass rolling in sixteenths, bright resonant pulse arp, sharp acid lead, thin pulse pad, classic drums",

defs: {
	SynthDef(\pp_acid_bass, { |out = 0, amp = 0.1, freq = 55, gate = 1|
		var env, fenv, sig;
		env = EnvGen.kr(Env.adsr(0.002, 0.08, 0.5, 0.04), gate, doneAction: 2);
		fenv = EnvGen.kr(Env.perc(0.002, 0.18));              // the cutoff snaps open, then falls
		sig = Saw.ar(freq);
		sig = RLPF.ar(sig, ((freq * 2) + (fenv * freq * 14)).min(12000), 0.2).tanh;  // low rq: the squelch
		Out.ar(out, (sig * env * amp * 0.88) ! 2);
	}).add;

	SynthDef(\pp_acid_arp, { |out = 0, amp = 0.1, freq = 440, gate = 1|
		var env, fenv, sig;
		env = EnvGen.kr(Env.adsr(0.002, 0.06, 0.35, 0.08), gate, doneAction: 2);
		fenv = EnvGen.kr(Env.perc(0.002, 0.12));
		sig = Pulse.ar(freq * [1, 1.004], 0.35);              // two pulses -> stereo
		sig = RLPF.ar(sig, ((freq * 3) + (fenv * freq * 5)).min(12000), 0.25).tanh;
		Out.ar(out, sig * env * amp * 0.88);
	}).add;

	SynthDef(\pp_acid_pad, { |out = 0, amp = 0.06, freq = 220, gate = 1|
		var env, width, sig;
		env = EnvGen.kr(Env.adsr(0.3, 0.3, 0.7, 1.2), gate, doneAction: 2);  // gate lets Stop release it
		width = 0.3 + SinOsc.kr([0.17, 0.23], 0, 0.12);       // a slowly moving pulse width
		sig = Pulse.ar(freq * [1, 1.006], width);
		sig = HPF.ar(LPF.ar(sig, 2200), 180);                 // thin: no low end, no top
		Out.ar(out, sig * env * amp * 0.88);
	}).add;

	SynthDef(\pp_acid_lead, { |out = 0, amp = 0.1, freq = 440, gate = 1|
		var env, fenv, sig;
		env = EnvGen.kr(Env.adsr(0.005, 0.1, 0.6, 0.15), gate, doneAction: 2);
		fenv = EnvGen.kr(Env.perc(0.005, 0.25));              // the sweep down on every note
		sig = Saw.ar(freq);
		sig = RLPF.ar(sig, ((freq * 3) + (fenv * freq * 8)).min(12000), 0.15).tanh;
		Out.ar(out, (sig * env * amp * 0.88) ! 2);
	}).add;
},

// How the bass moves (D-02): rolling sixteenths with a rest on each beat's first
// sixteenth, on the bar's chord, under every progression.
bassStyle: \sixteenths,

// Role -> voice. The drums are left out: they play classic's.
roles: (
	bass: (instrument: \pp_acid_bass),
	arp: (instrument: \pp_acid_arp),
	pad: (instrument: \pp_acid_pad),
	lead: (instrument: \pp_acid_lead)
)
)
