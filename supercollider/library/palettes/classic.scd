// Library palette: classic (the shipped v1.0 voices).
//
// FINAL when first committed: committed library files are never edited
// (scripts/check.sh guards it). A different sound is a new file.
//
// Nothing runs at load: the file's value is the Event below, and the SynthDefs
// are only added when the engine calls defs (inside a Routine, then s.sync).
(
desc: "Shipped voices: sine kick, noise hat and clap, saw bass, pulse arp, saw pad",

defs: {
	SynthDef(\ppKick, { |out = 0, amp = 0.5|
		var sig, env;
		env = EnvGen.kr(Env.perc(0.001, 0.35), doneAction: 2);
		sig = SinOsc.ar(XLine.kr(150, 50, 0.3)) * env * amp;
		Out.ar(out, sig ! 2);
	}).add;

	SynthDef(\ppHat, { |out = 0, amp = 0.15|
		var sig, env;
		env = EnvGen.kr(Env.perc(0.001, 0.12), doneAction: 2);
		sig = HPF.ar(WhiteNoise.ar(), 7000) * env * amp;
		Out.ar(out, sig ! 2);
	}).add;

	SynthDef(\ppBass, { |out = 0, amp = 0.25, freq = 55, gate = 1|
		var sig, env;
		env = EnvGen.kr(Env.adsr(0.005, 0.1, 0.6, 0.05), gate, doneAction: 2);
		sig = Saw.ar([freq, freq * 1.01]);  // detuned pair -> stereo
		sig = RLPF.ar(sig, 700, 0.6);
		Out.ar(out, sig * env * amp);
	}).add;

	SynthDef(\ppClap, { |out = 0, amp = 0.25|
		var sig, env;
		env = EnvGen.kr(Env.perc(0.005, 0.18), doneAction: 2);
		sig = BPF.ar(WhiteNoise.ar(), 1500, 0.6);
		Out.ar(out, (sig * env * amp) ! 2);
	}).add;

	SynthDef(\ppArp, { |out = 0, amp = 0.1, freq = 440, gate = 1|
		var sig, env;
		env = EnvGen.kr(Env.adsr(0.002, 0.05, 0.4, 0.08), gate, doneAction: 2);
		sig = Pulse.ar([freq, freq * 1.003], 0.3);  // two slightly detuned pulses -> stereo
		sig = LPF.ar(sig, freq * 4);
		Out.ar(out, sig * env * amp);
	}).add;

	SynthDef(\ppPad, { |out = 0, amp = 0.06, freq = 220, gate = 1|
		var sig, env;
		env = EnvGen.kr(Env.adsr(0.4, 0.3, 0.7, 1.2), gate, doneAction: 2);  // slow attack/release = pad character; gate lets Stop release it
		sig = Saw.ar([freq, freq * 1.005, freq * 0.997]);  // 3-voice detune for width
		sig = LPF.ar(sig, 1200);
		sig = Splay.ar(sig);
		Out.ar(out, sig * env * amp);
	}).add;
},

// Role -> voice. The lead reuses the arp voice (D-06).
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
