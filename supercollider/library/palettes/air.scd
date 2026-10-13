// Library palette: air (glassy bells, shimmer and a pure sine bass).
//
// FINAL when first committed: committed library files are never edited
// (scripts/check.sh guards it). A different sound or level is a new file.
//
// Voices: a pure sine bass; a glassy two-operator FM bell arp; a soft shimmering pad
// made of a stack of sine waves that each swell at their own slow rate; and a
// longer, brighter FM bell for the lead (its own voice, not the arp's). The drums
// stay classic's, and the bass keeps classic's offbeat eighths.
//
// Nothing runs at load: the file's value is the Event below, and the SynthDefs
// are only added when the engine calls defs (inside a Routine, then s.sync).
//
// Level: each voice ends with one literal gain constant (the last multiplier
// before Out.ar). They were set with scripts/palette_level.sh air so that the
// palette sits within 0.75 dB of classic in the full mix; the row amps (bass 0.1,
// arp 0.1, pad 0.06) are shared by every palette, so loudness is set only here.
// Every partial that follows the note is clamped with .min(12000) so a very high
// note cannot fold back into a loud alias.
(
desc: "Air: glassy FM bell arp and lead, soft shimmering sine pad, pure sine bass, classic drums",

defs: {
	SynthDef(\pp_air_bass, { |out = 0, amp = 0.1, freq = 55, gate = 1|
		var env, sig;
		env = EnvGen.kr(Env.adsr(0.01, 0.1, 0.8, 0.12), gate, doneAction: 2);
		sig = SinOsc.ar(freq);                                            // a pure sine
		Out.ar(out, (sig * env * amp * 0.34) ! 2);
	}).add;

	SynthDef(\pp_air_arp, { |out = 0, amp = 0.1, freq = 440, gate = 1|
		var env, idx, mod, sig;
		env = EnvGen.kr(Env.adsr(0.001, 0.25, 0.15, 0.3), gate, doneAction: 2);
		idx = EnvGen.kr(Env.perc(0.001, 0.35)) * 2.2;                     // the bell's brightness dies away
		mod = SinOsc.ar((freq * 3.5).min(12000)) * idx;                   // a non-integer ratio: glassy, inharmonic
		sig = SinOsc.ar(freq * [1, 1.002], mod);                          // two carriers -> stereo
		Out.ar(out, sig * env * amp * 0.41);
	}).add;

	SynthDef(\pp_air_pad, { |out = 0, amp = 0.06, freq = 220, gate = 1|
		var env, partials, swell, sig;
		env = EnvGen.kr(Env.adsr(0.9, 0.3, 0.8, 1.4), gate, doneAction: 2);  // slow in, long tail; gate lets Stop release it
		partials = SinOsc.ar((freq * [1, 2, 3, 4.003, 6.005]).min(12000));
		swell = SinOsc.kr([0.11, 0.17, 0.23, 0.29, 0.37], [0, 1, 2, 3, 4], 0.35, 0.65);  // each partial breathes at its own pace: the shimmer
		sig = HPF.ar(Splay.ar(partials * swell), 150);
		Out.ar(out, sig * env * amp * 0.41);
	}).add;

	SynthDef(\pp_air_lead, { |out = 0, amp = 0.1, freq = 440, gate = 1|
		var env, idx, mod, sig;
		env = EnvGen.kr(Env.adsr(0.002, 0.3, 0.35, 0.4), gate, doneAction: 2);
		idx = EnvGen.kr(Env.perc(0.001, 0.6)) * 2.8;
		mod = SinOsc.ar((freq * 2.01).min(12000)) * idx;
		sig = SinOsc.ar(freq * [1, 1.003], mod);
		Out.ar(out, sig * env * amp * 0.45);
	}).add;
},

// Role -> voice. The drums are left out: they play classic's.
roles: (
	bass: (instrument: \pp_air_bass),
	arp: (instrument: \pp_air_arp),
	pad: (instrument: \pp_air_pad),
	lead: (instrument: \pp_air_lead)
)
)
