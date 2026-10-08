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
	SynthDef(\ppKick, { |out = 0, amp = 0.5|
		var sig, env;
		env = EnvGen.kr(Env.perc(0.001, 0.35), doneAction: 2);
		sig = SinOsc.ar(XLine.kr(150, 50, 0.3)) * env * amp;
		Out.ar(out, sig ! 2);
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
