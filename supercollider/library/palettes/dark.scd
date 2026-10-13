// Library palette: dark (deep, murky, gritty).
//
// FINAL when first committed: committed library files are never edited
// (scripts/check.sh guards it). A different sound or level is a new file.
//
// Voices: its own kick, deeper and longer than classic's with a short click on the
// attack; a gritty saw bass pushed into a soft clip and then low-passed, rolling
// in sixteenths (bassStyle: \sixteenths); a narrow-pulse arp squeezed through a
// band-pass; a murky low-passed pad; and a lead built from a folded sine. The
// hats and the clap stay classic's.
//
// Nothing runs at load: the file's value is the Event below, and the SynthDefs
// are only added when the engine calls defs (inside a Routine, then s.sync).
//
// Level: each voice ends with one literal gain constant (the last multiplier
// before Out.ar). They were set with scripts/palette_level.sh dark so that the
// palette sits within 0.75 dB of classic in the full mix; the row amps (kick 0.1,
// bass 0.1, arp 0.1, pad 0.06) are shared by every palette, so loudness is set
// only here. Every cutoff that follows the note is clamped with .min(12000).
(
desc: "Dark: deep long kick with a click, gritty low-passed bass rolling in sixteenths, narrow murky arp and pad, folded lead",

defs: {
	SynthDef(\pp_dark_kick, { |out = 0, amp = 0.5|
		var env, sweep, body, click, sig;
		env = EnvGen.kr(Env.perc(0.001, 0.55, 1, -4), doneAction: 2);   // about 0.55 s long
		sweep = XLine.kr(110, 38, 0.2);                                  // a deep drop, not classic's 150 to 50
		body = SinOsc.ar(sweep) * env;
		click = HPF.ar(WhiteNoise.ar(0.5), 2500) * EnvGen.kr(Env.perc(0.0005, 0.012));
		sig = body + click;
		Out.ar(out, (sig * amp * 0.47) ! 2);
	}).add;

	SynthDef(\pp_dark_bass, { |out = 0, amp = 0.1, freq = 55, gate = 1|
		var env, sig;
		env = EnvGen.kr(Env.adsr(0.003, 0.08, 0.7, 0.05), gate, doneAction: 2);
		sig = Saw.ar(freq * [1, 1.006]);                                 // two saws -> stereo
		sig = LPF.ar((sig * 2.5).tanh, 380);                             // grit first, then the dark filter
		Out.ar(out, sig * env * amp * 0.58);
	}).add;

	SynthDef(\pp_dark_arp, { |out = 0, amp = 0.1, freq = 440, gate = 1|
		var env, sig;
		env = EnvGen.kr(Env.adsr(0.002, 0.06, 0.4, 0.1), gate, doneAction: 2);
		sig = Pulse.ar(freq * [1, 1.003], 0.12);                         // a narrow pulse
		sig = BPF.ar(sig, (freq * 1.6).min(12000), 0.6) * 2;
		Out.ar(out, sig * env * amp * 0.7);
	}).add;

	SynthDef(\pp_dark_pad, { |out = 0, amp = 0.06, freq = 220, gate = 1|
		var env, sig;
		env = EnvGen.kr(Env.adsr(0.5, 0.3, 0.7, 1.4), gate, doneAction: 2);  // gate lets Stop release it
		sig = Saw.ar([freq, freq * 1.005, freq * 0.996]);                // three detuned saws
		sig = LPF.ar(sig, 700);                                          // murky
		sig = Splay.ar(sig);
		Out.ar(out, sig * env * amp * 0.7);
	}).add;

	SynthDef(\pp_dark_lead, { |out = 0, amp = 0.1, freq = 440, gate = 1|
		var env, sig;
		env = EnvGen.kr(Env.adsr(0.01, 0.1, 0.7, 0.2), gate, doneAction: 2);
		sig = (SinOsc.ar(freq * [1, 1.004]) * 2.4).fold2(1);             // a folded sine: hollow, buzzy
		sig = LPF.ar(sig, (freq * 4).min(12000));
		Out.ar(out, sig * env * amp * 0.7);
	}).add;
},

// How the bass moves (D-02): rolling sixteenths with a rest on each beat's first
// sixteenth, on the bar's chord, under every progression.
bassStyle: \sixteenths,

// Role -> voice. The hats and the clap are left out: they play classic's.
roles: (
	kick: (instrument: \pp_dark_kick),
	bass: (instrument: \pp_dark_bass),
	arp: (instrument: \pp_dark_arp),
	pad: (instrument: \pp_dark_pad),
	lead: (instrument: \pp_dark_lead)
)
)
