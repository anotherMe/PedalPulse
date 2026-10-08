// PedalPulse engine entry file.
//
// Evaluate this whole file in the SuperCollider IDE (or load it, as the
// headless smoke test does). Everything that touches the server runs
// inside s.waitForBoot so nothing races the boot (ENG-04, Pitfall 2).
//
// Never assign Server.default here -- the smoke test redirects `s` to its
// own isolated server on port 57140 before loading this file.

// D-17: debug pre-limiter gain. Raise this (e.g. to 8.0), re-evaluate the
// whole file, and watch the meter hold at the limiter ceiling instead of
// clipping. Reset to 1.0 afterwards.
~preGain = 1.0;

s.options.numInputBusChannels = 0;  // no mic input: avoids the macOS mic permission prompt, saves CPU
s.options.numOutputBusChannels = 2;
// s.latency left at its default (Pitfall 3).

s.waitForBoot({
	// --- Idempotent re-evaluation (D-17 workflow: edit ~preGain, re-evaluate) ---
	// Replace, never stack: stop the previous patterns/clock and free the
	// previous nodes/bus before building anything new.
	Pbindef(\ppKick).stop;
	Pbindef(\ppHat).stop;
	Pbindef(\ppBass).stop;
	if (~clock.notNil) { ~clock.stop };
	// Wait out s.latency: a note-on just before .stop may already be sent as
	// a timestamped OSC bundle for the near future. Free too soon and that
	// bundle lands on an already-freed group ("Group N not found").
	0.3.wait;
	if (~ppMasterSynth.notNil) { ~ppMasterSynth.free };
	if (~ppMasterGroup.notNil) { ~ppMasterGroup.free };
	if (~ppInstrGroup.notNil) { ~ppInstrGroup.free };
	if (~ppMixBus.notNil) { ~ppMixBus.free };
	~ppApplyScheduled = false;  // a pending apply on the stopped clock can never wedge later messages

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

	SynthDef(\ppMaster, { |in, out = 0, preGain = 1|
		var sig = In.ar(in, 2) * preGain;
		Out.ar(out, Limiter.ar(sig, 0.891251, 0.01));  // D-16: -1 dBFS = 10^(-1/20) ~= 0.891251
	}).add;

	s.sync;

	~ppMixBus = Bus.audio(s, 2);
	~ppInstrGroup = Group.new(s);
	~ppMasterGroup = Group.after(~ppInstrGroup);
	~ppMasterSynth = Synth(\ppMaster, [\in, ~ppMixBus, \out, 0, \preGain, ~preGain], ~ppMasterGroup);

	// --- Clock and loop ---
	~bpm = ~bpm ? 120;  // D-07: fresh session starts at 120; re-evaluation keeps the last applied tempo
	~clock = TempoClock.new(~bpm / 60).permanent_(true);
	~ppApplyScheduled = false;
	~ppTempoApplyCount = 0;
	~ppLastApplyBeat = nil;

	Pbindef(\ppKick,
		\instrument, \ppKick,
		\dur, 1,
		\out, ~ppMixBus,
		\group, ~ppInstrGroup,
	);
	Pbindef(\ppKick).play(~clock, quant: 4);  // D-15: autostarted, four on the floor

	Pbindef(\ppHat,
		\instrument, \ppHat,
		\dur, 1,
		\timingOffset, 0.5,  // offbeat 8th: the "and" of each beat
		\out, ~ppMixBus,
		\group, ~ppInstrGroup,
	);
	Pbindef(\ppHat).play(~clock, quant: 4);

	Pbindef(\ppBass,
		\instrument, \ppBass,
		\dur, 0.5,  // 8th-note grid
		// A minor root (MIDI 33 = A1) on the offbeat 8th of beats 1-3;
		// MIDI 36 (C2) on the offbeat 8th of beat 4 -- the note change at
		// the bar end. Downbeat 8ths rest.
		\midinote, Pseq([\rest, 33, \rest, 33, \rest, 33, \rest, 36], inf),
		\legato, 0.8,
		\out, ~ppMixBus,
		\group, ~ppInstrGroup,
	);
	Pbindef(\ppBass).play(~clock, quant: 4);

	// --- OSC control: /pp/bpm <float> ---
	// Loopback-only (T-01-02): a nil port matches any port from 127.0.0.1,
	// so the engine ignores anything that isn't sent from this machine.
	OSCdef(\pp_bpm, { |msg|
		var raw = msg[1];
		if (raw.isNumber.not or: { raw.isNaN }) {
			"PedalPulse WARNING: ignoring /pp/bpm with invalid argument %".format(raw).postln;
		} {
			var bpm = raw.asFloat.clip(60, 180);  // TEMPO-03, D-09
			~ppPendingBpm = bpm;
			"PedalPulse: /pp/bpm % -> % BPM at next beat".format(raw, bpm).postln;
			if (~ppApplyScheduled.not) {
				~ppApplyScheduled = true;
				~clock.schedAbs(~clock.nextTimeOnGrid(1), {
					~clock.tempo = ~ppPendingBpm / 60;
					~bpm = ~ppPendingBpm;
					~ppLastApplyBeat = ~clock.beats;
					~ppTempoApplyCount = ~ppTempoApplyCount + 1;
					~ppApplyScheduled = false;
					nil;
				});
			};
		};
	}, '/pp/bpm', srcID: NetAddr("127.0.0.1", nil));

	~ppOscPort = NetAddr.langPort;
	"PedalPulse: listening for OSC on port %".format(~ppOscPort).postln;
	if (~ppOscPort != 57120) {
		"PedalPulse WARNING: OSC port is % but python_app/config.py sends to 57120 -- quit other sclang instances or pass --port %".format(~ppOscPort, ~ppOscPort).postln;
	};
	"PedalPulse: ready -- loop playing at % BPM".format(~bpm).postln;
	~ppReady = true;
});
