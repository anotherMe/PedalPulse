// Library palette: warm (soft, round and analog).
//
// FINAL when first committed: committed library files are never edited
// (scripts/check.sh guards it). A different sound or level is a new file.
//
// Voices: a round triangle-and-sine bass closed down to about 500 Hz; a soft
// detuned-triangle arp; a pad of sine and triangle waves with a slow vibrato; and
// a mellow lead whose vibrato fades in after the note starts. The drums stay
// classic's, and the bass keeps classic's offbeat eighths.
//
// Nothing runs at load: the file's value is the Event below, and the SynthDefs
// are only added when the engine calls defs (inside a Routine, then s.sync).
//
// Level: each voice ends with one literal gain constant (the last multiplier
// before Out.ar). They were set with scripts/palette_level.sh warm so that the
// palette sits within 0.75 dB of classic in the full mix; the row amps (bass 0.1,
// arp 0.1, pad 0.06) are shared by every palette, so loudness is set only here.
// Every cutoff that follows the note is clamped with .min(12000).
(
desc: "Warm: soft round triangle-and-sine bass, mellow detuned triangle arp and lead, slow-vibrato pad, classic drums",

defs: {
	SynthDef(\pp_warm_bass, { |out = 0, amp = 0.1, freq = 55, gate = 1|
		var env, sig;
		env = EnvGen.kr(Env.adsr(0.01, 0.15, 0.7, 0.12), gate, doneAction: 2);
		sig = LFTri.ar(freq * [1, 1.003]) + (SinOsc.ar(freq) * 0.6);      // round: triangle plus a sine
		sig = LPF.ar(sig, 500);
		Out.ar(out, sig * env * amp * 0.3);
	}).add;

	SynthDef(\pp_warm_arp, { |out = 0, amp = 0.1, freq = 440, gate = 1|
		var env, sig;
		env = EnvGen.kr(Env.adsr(0.004, 0.08, 0.4, 0.15), gate, doneAction: 2);
		sig = LFTri.ar(freq * [1, 1.004]);                                // a detuned triangle pair -> stereo
		sig = LPF.ar(sig, (freq * 3).min(12000));
		Out.ar(out, sig * env * amp * 0.65);
	}).add;

	SynthDef(\pp_warm_pad, { |out = 0, amp = 0.06, freq = 220, gate = 1|
		var env, vib, sig;
		env = EnvGen.kr(Env.adsr(0.8, 0.3, 0.8, 1.4), gate, doneAction: 2);  // slow in, long tail; gate lets Stop release it
		vib = SinOsc.kr(0.45, 0, 0.004);                                  // a slow vibrato, about 7 cents either way
		sig = SinOsc.ar(freq * (1 + vib) * [1, 1.003]) + LFTri.ar(freq * (1 + vib) * [0.5, 0.997]);
		sig = Splay.ar(LPF.ar(sig, 1500));
		Out.ar(out, sig * env * amp * 0.27);
	}).add;

	SynthDef(\pp_warm_lead, { |out = 0, amp = 0.1, freq = 440, gate = 1|
		var env, vib, sig;
		env = EnvGen.kr(Env.adsr(0.02, 0.1, 0.7, 0.3), gate, doneAction: 2);
		vib = SinOsc.kr(5, 0, 0.005) * EnvGen.kr(Env([0, 0, 1], [0.15, 0.4]));  // vibrato that blooms after the attack
		sig = LFTri.ar(freq * (1 + vib) * [1, 1.003]) + (SinOsc.ar(freq * (1 + vib)) * 0.4);
		sig = LPF.ar(sig, (freq * 4).min(12000));
		Out.ar(out, sig * env * amp * 0.32);
	}).add;
},

// Role -> voice. The drums are left out: they play classic's.
roles: (
	bass: (instrument: \pp_warm_bass),
	arp: (instrument: \pp_warm_arp),
	pad: (instrument: \pp_warm_pad),
	lead: (instrument: \pp_warm_lead)
)
)
