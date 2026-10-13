// Library palette: supersaw (a big detuned-saw sound).
//
// FINAL when first committed: committed library files are never edited
// (scripts/check.sh guards it). A different sound or level is a new file.
//
// Voices: a fat saw bass with a sub-octave sine, a wide five-saw arp, a seven-saw
// pad that opens like a wall of strings, and its own five-saw lead with a little
// vibrato (the lead is NOT the arp voice, so the melody's lead line stands apart
// from the arp). The drums are left out on purpose: they stay classic's.
//
// Nothing runs at load: the file's value is the Event below, and the SynthDefs
// are only added when the engine calls defs (inside a Routine, then s.sync).
//
// Level: each voice ends with one literal gain constant (the last multiplier
// before Out.ar). They were set with scripts/palette_level.sh supersaw so that
// the palette sits within 0.75 dB of classic in the full mix; the row amps
// (bass 0.1, arp 0.1, pad 0.06) are shared by every palette, so loudness is set
// only here.
(
desc: "Supersaw: huge detuned-saw pad and lead, bright saw arp, saw bass with a sub, classic drums",

defs: {
	SynthDef(\pp_supersaw_bass, { |out = 0, amp = 0.1, freq = 55, gate = 1|
		var env, saws, sub, sig;
		env = EnvGen.kr(Env.adsr(0.005, 0.12, 0.65, 0.08), gate, doneAction: 2);
		saws = Mix(Saw.ar(freq * [1, 1.007, 0.993])) * 0.4;  // three detuned saws
		sub = SinOsc.ar(freq * 0.5) * 0.6;                    // the sub, an octave down
		sig = RLPF.ar(saws, (freq * 10).min(1400), 0.5).tanh + sub;
		Out.ar(out, (sig * env * amp * 0.875) ! 2);
	}).add;

	SynthDef(\pp_supersaw_arp, { |out = 0, amp = 0.1, freq = 440, gate = 1|
		var env, sig;
		env = EnvGen.kr(Env.adsr(0.002, 0.08, 0.35, 0.12), gate, doneAction: 2);
		sig = Splay.ar(Saw.ar(freq * (1 + ([-0.012, -0.006, 0, 0.006, 0.012] * 0.8))), 0.8);  // five detuned saws, spread wide
		sig = RLPF.ar(sig, (freq * 6).min(12000), 0.4).tanh;
		Out.ar(out, sig * env * amp * 0.875);
	}).add;

	SynthDef(\pp_supersaw_pad, { |out = 0, amp = 0.06, freq = 220, gate = 1|
		var env, sig;
		env = EnvGen.kr(Env.adsr(0.5, 0.3, 0.8, 1.4), gate, doneAction: 2);  // slow in, long tail; gate lets Stop release it
		sig = Splay.ar(Saw.ar(freq * (1 + ([-0.014, -0.009, -0.004, 0, 0.004, 0.009, 0.014] * 0.8))), 1.0);  // seven detuned saws
		sig = LPF.ar(sig, 3200);
		Out.ar(out, sig * env * amp * 0.875);
	}).add;

	SynthDef(\pp_supersaw_lead, { |out = 0, amp = 0.1, freq = 440, gate = 1|
		var env, vib, sig;
		env = EnvGen.kr(Env.adsr(0.01, 0.1, 0.7, 0.25), gate, doneAction: 2);
		vib = SinOsc.kr(5.5, 0, 0.0025);                      // a little vibrato
		sig = Splay.ar(Saw.ar(freq * (1 + vib + ([-0.01, -0.005, 0, 0.005, 0.01] * 1.0))), 0.7);  // five detuned saws
		sig = RLPF.ar(sig, (freq * 5).min(12000), 0.5).tanh;
		Out.ar(out, sig * env * amp * 0.875);
	}).add;
},

// Role -> voice. The drums are left out: they play classic's.
roles: (
	bass: (instrument: \pp_supersaw_bass),
	arp: (instrument: \pp_supersaw_arp),
	pad: (instrument: \pp_supersaw_pad),
	lead: (instrument: \pp_supersaw_lead)
)
)
