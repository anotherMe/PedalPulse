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

// Tempo-glide tuning (TEMPO-01/02): length of a glide in beats (8 = 2 bars
// of 4/4) and the stepper's tick granularity (0.25 = one 16th note).
~ppRampBeats = 8;
~ppRampStepBeats = 0.25;

// EPIC-02 glide tuning: the 60 dB lag time (in seconds) of the one shared
// EPIC smoother. Edit and re-evaluate the whole file to retune.
~ppEpicLagSecs = 1.5;

// GUI-03: maps the app's 0-100 volume to master gain with a squared taper
// (100 = unity, never a boost; 80 = 0.64; 50 = 0.25), so equal slider moves
// feel like roughly equal loudness steps; for a linear map, change only
// this line.
~ppVolumeAmp = { |v| (v / 100).squared };

s.options.numInputBusChannels = 0;  // no mic input: avoids the macOS mic permission prompt, saves CPU
s.options.numOutputBusChannels = 2;
// s.latency left at its default (Pitfall 3).

s.waitForBoot({
	// --- Idempotent re-evaluation (D-17 workflow: edit ~preGain, re-evaluate) ---
	// Replace, never stack: stop the previous patterns/clock and free the
	// previous nodes/bus before building anything new. The last BPM, EPIC,
	// volume and transport state (playing/stopped) survive re-evaluation.
	// Read the previous transport state BEFORE the teardown. nil (a fresh
	// interpreter, the first-ever evaluation) maps to true, which keeps the
	// D-15 autostart; false (the rider pressed Stop) keeps the engine
	// stopped so it matches the GUI's "Start" label (audit W1).
	~ppWasPlaying = ~ppPlaying ? true;
	// ~ppLayers is the single source of truth for "every layer" -- Plan 04
	// appends the new layers here and every stop/start loop below follows.
	// Every layer, including any future one, MUST play on ~clock and never
	// on its own TempoClock (RESEARCH anti-pattern) -- that is what keeps
	// every layer phase-locked through a glide and a bar-quantized restart.
	~ppLayers = [\ppKick, \ppHat, \ppClap, \ppBass, \ppArp, \ppPad];
	~ppLayers.do { |name| Pbindef(name).stop };
	if (~ppRampStepper.notNil) { ~ppRampStepper.stop };
	if (~clock.notNil) { ~clock.stop };
	// Wait out s.latency: a note-on just before .stop may already be sent as
	// a timestamped OSC bundle for the near future. Free too soon and that
	// bundle lands on an already-freed group ("Group N not found").
	0.3.wait;
	// Free in dependency order: synths that read a bus before the bus
	// itself, and before the group that contains them (EPIC-01/02 Pitfall 2).
	if (~ppMasterSynth.notNil) { ~ppMasterSynth.free };
	if (~ppFxSynth.notNil) { ~ppFxSynth.free };
	if (~ppEpicSmoother.notNil) { ~ppEpicSmoother.free };
	if (~ppMasterGroup.notNil) { ~ppMasterGroup.free };
	if (~ppFxGroup.notNil) { ~ppFxGroup.free };
	if (~ppInstrGroup.notNil) { ~ppInstrGroup.free };
	if (~ppMixBus.notNil) { ~ppMixBus.free };
	if (~ppFxBus.notNil) { ~ppFxBus.free };
	if (~ppEpicBus.notNil) { ~ppEpicBus.free };
	if (~ppEpicSmoothBus.notNil) { ~ppEpicSmoothBus.free };
	if (~ppVolumeBus.notNil) { ~ppVolumeBus.free };
	~ppRampPendingBpm = nil; ~ppRampRateBpm = 0;  // a pending target on a stopped clock can never wedge later messages

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

	SynthDef(\ppMaster, { |in, out = 0, preGain = 1, volumeBus = 0|
		// GUI-03: volume is applied before the limiter, never after (Pitfall
		// 1) -- it is a gain stage inside the master, exactly like preGain.
		// The 0.2s lag de-zippers a slider release and is deliberately
		// shorter than EPIC's musical glide (~ppEpicLagSecs).
		var volume = Lag.kr(In.kr(volumeBus), 0.2);
		var sig = In.ar(in, 2) * preGain * volume;
		Out.ar(out, Limiter.ar(sig, 0.891251, 0.01));  // D-16: -1 dBFS = 10^(-1/20) ~= 0.891251
	}).add;

	// These two SynthDefs are persistent for the whole session, not per-note
	// -- a deliberate exception to the doneAction: 2 rule (which applies to
	// per-note voices). They have no envelope and are freed explicitly by
	// the teardown block above, not by doneAction.
	SynthDef(\ppEpicSmoother, { |in = 0, out = 0, lag = 1.5|
		Out.kr(out, Lag.kr(In.kr(in), lag));
	}).add;

	SynthDef(\ppFx, { |in = 0, out = 0, epicBus = 0|
		var sig = In.ar(in, 2);
		// One read of the already-smoothed EPIC bus (0..1) drives every
		// parameter below -- this single-read-one-synth design is what
		// makes drive/filter/richness/reverb all move together (EPIC-01).
		var epic = In.kr(epicBus);
		var drive = epic.linlin(0, 1, 1.0, 3.5);
		var cutoff = epic.linexp(0, 1, 500, 9000);
		var wet = epic.linlin(0, 1, 0.08, 0.35);
		sig = (sig * drive).softclip;
		sig = RLPF.ar(sig, cutoff, 0.5);
		sig = sig + (HPF.ar(sig, 3500) * epic * 0.35);
		sig = FreeVerb2.ar(sig[0], sig[1], wet, 0.6, 0.3);
		Out.ar(out, sig);
	}).add;

	s.sync;

	~ppMixBus = Bus.audio(s, 2);
	~ppFxBus = Bus.audio(s, 2);
	~ppEpicBus = Bus.control(s, 1);
	~ppEpicSmoothBus = Bus.control(s, 1);
	~ppVolumeBus = Bus.control(s, 1);

	~ppInstrGroup = Group.new(s);
	~ppFxGroup = Group.after(~ppInstrGroup);
	~ppMasterGroup = Group.after(~ppFxGroup);

	// EPIC state: ~epic = ~epic ? 10 keeps the last value across a
	// re-evaluation (like ~bpm), defaulting to 10 (Recovery) on a fresh
	// boot. Set the raw bus BEFORE creating the smoother below: Lag starts
	// from its first input, so the smoothed value starts at the current
	// EPIC with no glide from 0 on boot or re-evaluation.
	~epic = ~epic ? 10;
	~ppEpicCount = 0;
	~ppEpicBus.set(~epic / 100);

	~ppEpicSmoother = Synth(\ppEpicSmoother, [\in, ~ppEpicBus.index, \out, ~ppEpicSmoothBus.index, \lag, ~ppEpicLagSecs], ~ppFxGroup, \addToHead);
	// \addToTail is required here: Synth's default addAction is
	// \addToHead, which would run the FX synth BEFORE the smoother within
	// the same control block, reading last block's stale value.
	~ppFxSynth = Synth(\ppFx, [\in, ~ppMixBus.index, \out, ~ppFxBus.index, \epicBus, ~ppEpicSmoothBus.index], ~ppFxGroup, \addToTail);

	// GUI-03: ~volume = ~volume ? 80 keeps the last value across a
	// re-evaluation (like ~bpm and ~epic), defaulting to 80 on a fresh
	// boot. Set the raw bus BEFORE creating the master synth below: Lag
	// starts from its first input, so the master's lag starts at the
	// current gain with no fade from 0 on boot or re-evaluation.
	~volume = ~volume ? 80;
	~ppVolumeCount = 0;
	~ppVolumeBus.set(~ppVolumeAmp.(~volume));

	// \ppMaster now reads ~ppFxBus (post-FX), not ~ppMixBus -- the FX chain
	// sits between the instruments and the limiter, never bypassing it.
	~ppMasterSynth = Synth(\ppMaster, [\in, ~ppFxBus.index, \out, 0, \preGain, ~preGain, \volumeBus, ~ppVolumeBus.index], ~ppMasterGroup);

	// --- Clock and loop ---
	~bpm = ~bpm ? 120;  // D-07: fresh session starts at 120; re-evaluation keeps the last applied tempo
	~clock = TempoClock.new(~bpm / 60).permanent_(true);
	~ppRampTargetBpm = ~bpm;
	~ppRampRateBpm = 0;
	~ppRampPendingBpm = nil;
	~ppTempoApplyCount = 0;
	~ppLastApplyBeat = nil;
	~ppRampStartBeat = nil;
	~ppRampLandBeat = nil;

	// Ramp stepper (TEMPO-01/02): the ONLY writer of ~clock.tempo. Plays on
	// ~clock itself and waits in beats, never SystemClock/AppClock or
	// seconds (Pitfall 1) -- so the glide's real-world duration naturally
	// tracks tempo, and every layer below (which also plays on ~clock)
	// never drifts from it. Started once per evaluation, right after the
	// clock.
	~ppRampStepper = Routine({
		loop {
			var beat, onBeat;
			beat = ~clock.beats;
			onBeat = (beat - beat.round).abs < 1e-6;
			// Engage the pending target: from rest only on a whole beat
			// (TEMPO-01, beat-synchronous start); mid-glide, on any tick
			// (TEMPO-02, immediate retarget -- no restart, no re-quantize).
			if (~ppRampPendingBpm.notNil and: { (~ppRampRateBpm > 0) or: { onBeat } }) {
				var nowBpm, fromRest;
				nowBpm = ~clock.tempo * 60;
				fromRest = (~ppRampRateBpm == 0);
				~ppRampTargetBpm = ~ppRampPendingBpm;
				~ppRampPendingBpm = nil;
				~ppRampRateBpm = (~ppRampTargetBpm - nowBpm).abs / ~ppRampBeats;
				~ppTempoApplyCount = ~ppTempoApplyCount + 1;
				~ppLastApplyBeat = beat;
				if (fromRest and: { ~ppRampRateBpm > 0 }) { ~ppRampStartBeat = beat };
			};
			// Step toward the target by at most one ramp step; land exactly
			// on it once within a step (no overshoot, no residual rate).
			if (~ppRampRateBpm > 0) {
				var nowBpm, diff, maxStep;
				nowBpm = ~clock.tempo * 60;
				diff = ~ppRampTargetBpm - nowBpm;
				maxStep = ~ppRampRateBpm * ~ppRampStepBeats;
				if (diff.abs <= (maxStep + 1e-9)) {
					~clock.tempo = ~ppRampTargetBpm / 60;
					~ppRampRateBpm = 0;
					~ppRampLandBeat = beat;
				} {
					~clock.tempo = (nowBpm + (diff.sign * maxStep)) / 60;
				};
			};
			~bpm = ~clock.tempo * 60;  // keep ~bpm current so a re-evaluation preserves the instantaneous tempo
			~ppRampStepBeats.wait;
		};
	}).play(~clock, quant: 1);

	Pbindef(\ppKick,
		\instrument, \ppKick,
		\dur, 1,
		\out, ~ppMixBus,
		\group, ~ppInstrGroup,
	);

	Pbindef(\ppHat,
		\instrument, \ppHat,
		\dur, 1,
		\timingOffset, 0.5,  // offbeat 8th: the "and" of each beat
		\out, ~ppMixBus,
		\group, ~ppInstrGroup,
	);

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

	// Pbindef sets no \amp key -> the pattern sends the default event
	// amplitude (0.1) to any synth with an amp control, overriding that
	// SynthDef's own \amp default; the kick/hat/bass layers above rely on
	// that default. These three new layers set \amp explicitly (matching
	// each SynthDef's own \amp default above) so the mix balance is the one
	// the voice was designed at, not the pattern-wide 0.1 fallback.
	Pbindef(\ppClap,
		\instrument, \ppClap,
		\dur, 2,  // beats 2 and 4
		\timingOffset, 1,
		\amp, 0.25,
		\out, ~ppMixBus,
		\group, ~ppInstrGroup,
	);

	Pbindef(\ppArp,
		\instrument, \ppArp,
		\dur, 0.25,  // 16th notes
		// A3, C4, E4, C4 -- an octave+ above Phase 1's A-minor bass root
		\midinote, Pseq([57, 60, 64, 60], inf),
		\legato, 0.6,
		\amp, 0.1,
		\out, ~ppMixBus,
		\group, ~ppInstrGroup,
	);

	Pbindef(\ppPad,
		\instrument, \ppPad,
		\dur, 4,  // one chord per bar
		// Am, then Am with a passing tone -- fixed two-bar loop
		\midinote, Pseq([[45, 48, 52], [45, 48, 53]], inf),
		\legato, 0.9,
		\amp, 0.06,
		\out, ~ppMixBus,
		\group, ~ppInstrGroup,
	);

	// --- Transport: ~ppStart / ~ppStop (GUI-02) ---
	// Both the OSC handler and D-15 autostart below go through this same
	// pair, so there is exactly one code path that starts or stops the
	// groove.
	~ppStart = {
		~ppLayers.do { |name| Pbindef(name).play(~clock, quant: 4, doReset: true) };
		~ppPlaying = true;
		~ppTransportCount = ~ppTransportCount + 1;
		"PedalPulse: started -- groove re-enters on the next bar".postln;
	};

	~ppStop = {
		~ppLayers.do { |name| Pbindef(name).stop };
		~ppPlaying = false;
		~ppTransportCount = ~ppTransportCount + 1;
		// Stopping a Pbindef only stops scheduling new events; it does not
		// reach synths already running on the server, so a sustaining gated
		// voice (e.g. ppBass) would otherwise ring until its own scheduled
		// release. Broadcast \gate, 0 now so every gated voice releases
		// through its own envelope (no hard free, no pop; gate-less voices
		// like kick/hat are short percussive envelopes that end on their
		// own regardless).
		~ppInstrGroup.set(\gate, 0);
		// A note emitted just before Stop may already be on its way as an
		// OSC bundle timestamped up to s.latency ahead (same race as the
		// re-evaluation teardown above), so it can start and sustain after
		// this broadcast. Schedule a second one after s.latency to catch
		// it; the ~ppPlaying guard skips it if Start already happened in
		// the meantime. This second broadcast can legitimately find that a
		// node it targets has already ended and been freed by its own
		// release envelope -- the server then logs "FAILURE IN SERVER
		// /n_set Node N not found" on the post window, which is expected
		// and harmless.
		SystemClock.sched((s.latency ? 0.2) + 0.05, {
			if (~ppPlaying.not) { ~ppInstrGroup.set(\gate, 0) };
			nil;
		});
		"PedalPulse: stopped".postln;
	};

	~ppPlaying = false;
	~ppTransportCount = 0;
	if (~ppWasPlaying) {
		~ppStart.value;  // D-15: autostart through the same path /pp/play uses
	} {
		// The teardown already stopped every Pbindef and freed the old
		// instrument group; ~ppStop here would only add a spurious count
		// increment and gate broadcast.
		"PedalPulse: was stopped before re-evaluation -- staying stopped (press Start in the app or send /pp/play 1)".postln;
	};

	// --- OSC control: /pp/bpm <float> ---
	// Loopback-only (T-01-02): a nil port matches any port from 127.0.0.1,
	// so the engine ignores anything that isn't sent from this machine.
	OSCdef(\pp_bpm, { |msg|
		var raw = msg[1];
		if (raw.isNumber.not or: { raw.isNaN }) {
			"PedalPulse WARNING: ignoring /pp/bpm with invalid argument %".format(raw).postln;
		} {
			var bpm = raw.asFloat.clip(60, 180);  // TEMPO-03, D-09
			~ppRampPendingBpm = bpm;
			"PedalPulse: /pp/bpm % -> % BPM (glide over % beats)".format(raw, bpm, ~ppRampBeats).postln;
		};
	}, '/pp/bpm', srcID: NetAddr("127.0.0.1", nil));

	// --- OSC control: /pp/play <int> (GUI-02 transport) ---
	// Loopback-only, same srcID guard as /pp/bpm. Non-zero = start, 0 =
	// stop; invalid input is ignored with a warning; repeats are no-ops
	// (idempotent), proven by ~ppTransportCount in the smoke test.
	OSCdef(\pp_play, { |msg|
		var raw = msg[1];
		if (raw.isNumber.not or: { raw.isNaN }) {
			"PedalPulse WARNING: ignoring /pp/play with invalid argument %".format(raw).postln;
		} {
			var want = raw.asInteger != 0;
			if (want == ~ppPlaying) {
				"PedalPulse: /pp/play % -> already %".format(raw, if (want) { "playing" } { "stopped" }).postln;
			} {
				"PedalPulse: /pp/play % -> %".format(raw, if (want) { "start" } { "stop" }).postln;
				if (want) { ~ppStart.value } { ~ppStop.value };
			};
		};
	}, '/pp/play', srcID: NetAddr("127.0.0.1", nil));

	// --- OSC control: /pp/epic <float 0-100> (EPIC-01/EPIC-02) ---
	// Loopback-only, same srcID guard as /pp/bpm and /pp/play. The handler
	// never touches the clock or its tempo -- EPIC is entirely orthogonal
	// to the tempo-glide mechanism.
	OSCdef(\pp_epic, { |msg|
		var raw = msg[1];
		if (raw.isNumber.not or: { raw.isNaN }) {
			"PedalPulse WARNING: ignoring /pp/epic with invalid argument %".format(raw).postln;
		} {
			~epic = raw.asFloat.clip(0, 100);
			~ppEpicCount = ~ppEpicCount + 1;
			~ppEpicBus.set(~epic / 100);
			"PedalPulse: /pp/epic % -> % (glide over % s)".format(raw, ~epic, ~ppEpicLagSecs).postln;
		};
	}, '/pp/epic', srcID: NetAddr("127.0.0.1", nil));

	// --- OSC control: /pp/volume <float 0-100> (GUI-03) ---
	// Loopback-only, same srcID guard as /pp/bpm, /pp/play and /pp/epic.
	// The handler never touches the clock -- volume is entirely orthogonal
	// to the tempo-glide mechanism.
	OSCdef(\pp_volume, { |msg|
		var raw = msg[1];
		if (raw.isNumber.not or: { raw.isNaN }) {
			"PedalPulse WARNING: ignoring /pp/volume with invalid argument %".format(raw).postln;
		} {
			~volume = raw.asFloat.clip(0, 100);
			~ppVolumeCount = ~ppVolumeCount + 1;
			~ppVolumeBus.set(~ppVolumeAmp.(~volume));
			"PedalPulse: /pp/volume % -> % (gain %)".format(raw, ~volume, ~ppVolumeAmp.(~volume).round(0.001)).postln;
		};
	}, '/pp/volume', srcID: NetAddr("127.0.0.1", nil));

	~ppOscPort = NetAddr.langPort;
	"PedalPulse: listening for OSC on port %".format(~ppOscPort).postln;
	if (~ppOscPort != 57120) {
		"PedalPulse WARNING: OSC port is % but python_app/config.py sends to 57120 -- quit other sclang instances or pass --port %".format(~ppOscPort, ~ppOscPort).postln;
	};
	"PedalPulse: ready -- groove % at % BPM, EPIC %, volume % (/pp/bpm, /pp/play, /pp/epic, /pp/volume)".format(if (~ppPlaying) { "playing" } { "stopped" }, ~bpm, ~epic, ~volume).postln;
	~ppReady = true;
});
