// Headless palette meter (Phase 7, PAL-04, D-13, D-14, D-15).
//
// Measures every sound palette against classic on the real engine, before a
// palette file is frozen by its first commit: loudness, headroom at VO2, CPU,
// node count and the extreme notes of the pitched voices.
//
// Run via scripts/palette_level.sh (which sets the environment), or directly:
//   PP_METER=level PP_METER_STEMS="supersaw" \
//     /Applications/SuperCollider.app/Contents/MacOS/sclang -D supercollider/palette_meter.scd
//
//   PP_METER        "level" (or unset) is the only mode; anything else fails.
//   PP_METER_STEMS  space separated palette names; empty means every palette
//                   file on disk. classic is always measured first, as the
//                   reference, and only once.
//
// Do NOT set QT_QPA_PLATFORM=offscreen anywhere: verified to abort sclang
// 3.14.1 on macOS with exit 134. Plain `sclang -D` runs headless on its own.
//
// Line protocol (same style as the smoke test and the library check):
//   PedalPulse meter: level <stem> rms=<dBFS> gap=<dB>
//   PedalPulse meter: vo2 <stem> fxpeak=<x> outpeak=<y> cpu=<mean> cpupeak=<max> synths=<max>
//   CHECK OK: palette level|headroom|cpu|extreme notes <stem>
//   CHECK WARN: ...                       advice, never a failure
//   PALETTE PASS                          last line on success, exit 0
//   PALETTE FAIL: <name>: <detail>        first failure, exit 1
//   PALETTE FAIL: watchdog timeout        a hang, exit 1
//
// Isolation (never disturbs a running engine): this file boots its own muted
// server on port 57142 (the live engine uses 57110 / 57120, the smoke test
// 57140, the library check 57141) and never addresses any of them. Every OSC
// message it sends goes to NetAddr("127.0.0.1", NetAddr.langPort), its own
// interpreter.
//
// The metrics (the planner's choice for D-13):
//   level     post-FX RMS (the engine's ~ppFxBus: after the shared EPIC effects,
//             before the master volume and the limiter), averaged over exactly 4
//             bars that start on a bar line, after the palette has been playing
//             for 2 bars; 180 BPM, progression anthem, melody classic_lead_loud
//             (so the palette's bass, pad and lead are all heard), EPIC 50.
//             Gate: within 1.5 dB of classic. Authoring target: 0.75 dB, so the
//             gate still holds at other EPIC levels (RESEARCH Pitfall 2).
//   headroom  EPIC 100 and volume 100 (VO2): post-FX peak at most 0.80, output
//             (bus 0, after the limiter) at most 0.892 and above 0.1, at most 40
//             synths.
//   cpu       mean of s.avgCPU sampled every 0.25 s in that VO2 window: a
//             warning above 12 percent, a failure at 25 percent or more.
//   extreme   every pitched voice of a non-classic palette, alone, at MIDI -12
//             and 127: finite and a peak below 4.0.

(
var root, mode, wantStems;
var fail, checkOk, checkWarn, topFail;
var sendSel, waitFor, readCtl;
var replies, nextId = 0, runWindow, selectPalette;
var elapsed;

// Watchdog first, in case anything below hangs. 480 s leaves room for several
// palettes; scripts/palette_level.sh kills the run at 510 s.
SystemClock.sched(480, { "PALETTE FAIL: watchdog timeout".postln; 1.exit; nil });

// sclang reports a relative nowExecutingPath when given a relative path, so
// resolve to an absolute path first (before any wait).
root = File.realpath(thisProcess.nowExecutingPath).dirname.dirname;

// A mode check needs no server: refuse before booting anything.
mode = "PP_METER".getenv;
if (mode.isNil or: { mode == "" }) { mode = "level" };
if (mode != "level") {
	"PALETTE FAIL: mode: unknown mode %".format(mode).postln;
	1.exit;
};
wantStems = "PP_METER_STEMS".getenv;
wantStems = if (wantStems.isNil) { [] } { wantStems.split($ ).reject { |x| x.size < 1 } };

// Redirect to an isolated server before loading main.scd, so a live engine on
// 57110 / 57120 is never touched.
Server.default = s = Server(\ppMeter, NetAddr("127.0.0.1", 57142));

~ppReady = false;
// The load must see a fresh interpreter's nil transport state (D-15 autostart).
~ppPlaying = nil;

// Throws so a failing check aborts the rest immediately; the top-level `try`
// below prints "PALETTE FAIL: ..." and exits.
fail = { |name, detail|
	Error("%: %".format(name, detail)).throw;
};
checkOk = { |name|
	"CHECK OK: %".format(name).postln;
};
checkWarn = { |text|
	"CHECK WARN: %".format(text).postln;
};
// The text of a failure without the class prefix sclang puts in front of it.
topFail = { |err|
	var msg = err.errorString;
	if (msg.beginsWith("ERROR: ")) { msg = msg.copyToEnd(7) };
	"PALETTE FAIL: %".format(msg).postln;
};

// One OSC message to this interpreter's own language port, from loopback,
// exactly like the app does.
sendSel = { |address, value|
	NetAddr("127.0.0.1", NetAddr.langPort).sendMsg(address, value);
};

// Poll every 0.05 s until cond holds or timeoutSec passes. Call from a Routine.
waitFor = { |cond, timeoutSec|
	var t = 0;
	while { cond.value.not and: { t < timeoutSec } } {
		0.05.wait;
		t = t + 0.05;
	};
	cond.value
};

// One read of a control bus, or -1 when the server never answered.
readCtl = { |bus|
	var val = nil, t = 0;
	bus.get({ |v| val = v });
	while { val.isNil and: { t < 1 } } {
		0.02.wait;
		t = t + 0.02;
	};
	val ? -1
};

// Replies of the meter probe: replyID -> List of [time, meanSquare, peak, bad].
replies = IdentityDictionary.new;
OSCdef(\ppMeterReply, { |msg|
	var id = msg[2];
	if (replies[id].notNil) {
		replies[id].add([SystemClock.seconds, msg[3], msg[4], msg[5]]);
	};
}, '/pp/meter');

// Select a palette over OSC and wait until it is both selected and the one the
// memo says sounds (the next bar line).
selectPalette = { |stem|
	sendSel.('/pp/palette', stem);
	if (waitFor.({ (~ppSel[\palettes] == stem) and: { ~ppPalPlaying == stem } }, 6).not) {
		fail.("palette select", "% never became the palette that plays (selection %, playing %)".format(stem, ~ppSel[\palettes], ~ppPalPlaying));
	};
};

// runWindow.(bars, specs, sampleServer) -> (probes: Array of (rms:, peak:, bad:), cpu:, cpuPeak:, synths:)
// Starts on a bar line and runs for exactly `bars` bars of the clock. specs is an
// Array of (bus:, target:) probe placements; a probe is placed right after its
// target node. When sampleServer is true, s.avgCPU, s.peakCPU and s.numSynths are
// sampled every 0.25 s. The first 0.3 s of replies are dropped: the running sum
// of a fresh probe has not filled its 8192-sample window yet.
runWindow = { |bars, specs, sampleServer|
	var ids, probes, t0, dur, steps, cpu = List.new, cpuPeak = 0, synths = 0, out;
	(~clock.timeToNextBeat(4)).wait;
	ids = specs.collect { nextId = nextId + 1; nextId };
	ids.do { |id| replies[id] = List.new };
	probes = specs.collect { |sp, k| Synth.after(sp[\target], \ppMeterProbe, [\in, sp[\bus], \id, ids[k]]) };
	t0 = SystemClock.seconds;
	dur = ~clock.beatDur * 4 * bars;
	steps = (dur / 0.25).round.asInteger;
	steps.do {
		if (sampleServer) {
			cpu.add(s.avgCPU);
			cpuPeak = max(cpuPeak, s.peakCPU);
			synths = max(synths, s.numSynths);
		};
		0.25.wait;
	};
	probes.do { |p| p.free };
	0.1.wait;
	out = (
		probes: ids.collect { |id|
			var rs = replies[id].select { |r| r[0] >= (t0 + 0.3) };
			var ms = rs.collect { |r| r[1] };
			var res = (
				n: rs.size,
				rms: if (ms.size > 0) { (ms.sum / ms.size).sqrt } { 0 },
				peak: if (rs.size > 0) { rs.collect { |r| r[2] }.maxItem } { 0 },
				bad: rs.any { |r| r[3] > 0 }
			);
			replies.removeAt(id);
			res
		},
		cpu: if (cpu.size > 0) { cpu.sum / cpu.size } { 0 },
		cpuPeak: cpuPeak,
		synths: synths
	);
	out
};

fork({
	var stems, onDisk, level = (), classicDb, vo2 = (), extremes;

	s.boot;
	elapsed = 0;
	while ({ s.serverRunning.not and: { elapsed < 30 } }) {
		0.5.wait;
		elapsed = elapsed + 0.5;
	};
	if (s.serverRunning.not) {
		"PALETTE FAIL: isolated server never booted within 30s".postln;
		1.exit;
	};

	s.volume.mute;  // automated runs are inaudible; Volume amp synth runs at the root tail

	{
		// Test-only probe (never part of main.scd): the windowed mean square of
		// the louder-summed stereo signal, its running peak, and a flag that
		// becomes 1 once a NaN or an infinity has been seen on either channel.
		SynthDef(\ppMeterProbe, { |in = 0, id = 0|
			var sig, ms, pk, code, flag;
			sig = In.ar(in, 2);
			ms = RunningSum.ar(sig.squared.sum * 0.5, 8192) / 8192;
			// Never Peak.ar(sig).asArray.maxItem: compare the channels first.
			pk = Peak.ar(max(sig[0].abs, sig[1].abs));
			code = CheckBadValues.ar(sig, 0, 0);
			flag = Peak.ar(max(((code[0] > 0) * (code[0] < 3)), ((code[1] > 0) * (code[1] < 3))));
			SendReply.kr(Impulse.kr(20), '/pp/meter', [A2K.kr(ms), A2K.kr(pk), A2K.kr(flag)], id);
		}).add;
		s.sync;

		(root +/+ "supercollider/main.scd").load;

		elapsed = 0;
		while ({ ~ppReady.not and: { elapsed < 30 } }) {
			0.5.wait;
			elapsed = elapsed + 0.5;
		};
		if (~ppReady.not) {
			fail.("engine ready", "~ppReady never became true within 30s");
		};

		// Which palettes: the names asked for, or every valid palette file on disk.
		// classic is the reference: always first, listed once.
		onDisk = (~ppLibRoot +/+ "palettes" +/+ "*.scd").pathMatch.collect { |p| PathName(p).fileNameWithoutExtension };
		onDisk = onDisk.select { |n| ~ppStemValid.(n) }.sort;
		stems = if (wantStems.size > 0) { wantStems } { onDisk };
		stems.do { |n|
			if (~ppStemValid.(n).not or: { File.exists(~ppLibPath.(\palettes, n)).not }) {
				fail.("stems", "% is not a palette: a name is 1-64 characters from a-z, 0-9 and _, and needs palettes/%.scd".format(n, n));
			};
		};
		stems = ["classic"] ++ stems.reject { |n| n == "classic" }.asSet.asArray.sort;
		stems = stems.collect { |n| n.asSymbol };

		// --- Setup: 180 BPM, anthem, classic_lead_loud, EPIC 50 ---
		sendSel.('/pp/bpm', 180);
		if (waitFor.({ ((~clock.tempo * 60) - 180).abs < 0.01 }, 15).not) {
			fail.("setup", "the clock never reached 180 BPM (at % BPM)".format(~clock.tempo * 60));
		};
		sendSel.('/pp/progression', 'anthem');
		sendSel.('/pp/melody', 'classic_lead_loud');
		if (waitFor.({ (~ppSel[\progressions] == \anthem) and: { ~ppSel[\melodies] == \classic_lead_loud } }, 10).not) {
			fail.("setup", "anthem and classic_lead_loud were never selected (progression %, melody %)".format(~ppSel[\progressions], ~ppSel[\melodies]));
		};
		if (waitFor.({ ~ppHarmCycleLog.().last.notNil and: { ~ppHarmCycleLog.().last[\stem] == \anthem } }, 15).not) {
			fail.("setup", "the harmony never moved to anthem (cycle log %)".format(~ppHarmCycleLog.()));
		};
		sendSel.('/pp/epic', 50);
		if (waitFor.({ (readCtl.(~ppEpicSmoothBus) - 0.5).abs < 0.005 }, 8).not) {
			fail.("setup", "the smoothed EPIC bus never settled at 0.5");
		};

		// --- Level pass: post-FX RMS, 4 bars after 2 settling bars ---
		stems.do { |stem|
			var res, db, gap, name;
			selectPalette.(stem);
			(~clock.beatDur * 8).wait;
			res = runWindow.(4, [(bus: ~ppFxBus.index, target: ~ppFxGroup)], false)[\probes][0];
			if (res[\n] < 20) { fail.("palette level %".format(stem), "only % meter replies in 4 bars".format(res[\n])) };
			if (res[\bad]) { fail.("palette level %".format(stem), "NaN or infinity on the post-FX bus") };
			if ((res[\rms] > 0).not) { fail.("palette level %".format(stem), "no signal on the post-FX bus (rms %)".format(res[\rms])) };
			db = res[\rms].ampdb;
			if (stem == \classic) { classicDb = db };
			gap = db - classicDb;
			"PedalPulse meter: level % rms=% gap=%".format(stem, db.round(0.01), gap.round(0.01)).postln;
			level[stem] = gap;
			if (stem != \classic) {
				name = "palette level %".format(stem);
				if (gap.abs > 1.5) {
					fail.(name, "gap % dB is more than 1.5 dB from classic".format(gap.round(0.01)));
				};
				if (gap.abs > 0.75) {
					checkWarn.("palette level % gap % dB, aim for 0.75 or less".format(stem, gap.round(0.01)));
				};
				checkOk.(name);
			};
		};

		// --- VO2 pass: EPIC 100 and volume 100 ---
		sendSel.('/pp/epic', 100);
		sendSel.('/pp/volume', 100);
		if (waitFor.({ (readCtl.(~ppEpicSmoothBus) - 1.0).abs < 0.005 }, 8).not) {
			fail.("setup", "the smoothed EPIC bus never settled at 1.0");
		};
		0.5.wait;
		stems.do { |stem|
			var res, win, name;
			selectPalette.(stem);
			(~clock.beatDur * 8).wait;
			// One probe on the post-FX bus, one on bus 0 right after the master
			// group (before the root volume synth, so the mute does not hide it).
			win = runWindow.(4, [
				(bus: ~ppFxBus.index, target: ~ppFxGroup),
				(bus: 0, target: ~ppMasterGroup)
			], true);
			res = (fxpeak: win[\probes][0][\peak], outpeak: win[\probes][1][\peak]);
			"PedalPulse meter: vo2 % fxpeak=% outpeak=% cpu=% cpupeak=% synths=%".format(
				stem, res[\fxpeak].round(0.001), res[\outpeak].round(0.001),
				win[\cpu].round(0.01), win[\cpuPeak].round(0.01), win[\synths]).postln;
			name = "palette headroom %".format(stem);
			if (win[\probes][0][\bad] or: { win[\probes][1][\bad] }) {
				fail.(name, "NaN or infinity at EPIC 100 and volume 100");
			};
			if (res[\fxpeak] > 0.80) { fail.(name, "post-FX peak % is above 0.80 at EPIC 100".format(res[\fxpeak].round(0.001))) };
			if (res[\outpeak] > 0.892) { fail.(name, "output peak % is above the limiter ceiling plus tolerance 0.892".format(res[\outpeak].round(0.001))) };
			if (res[\outpeak] <= 0.1) { fail.(name, "output peak % is at or below the silence floor 0.1 -- no real audio flowing".format(res[\outpeak].round(0.001))) };
			if (win[\synths] > 40) { fail.(name, "% synths at once, more than 40".format(win[\synths])) };
			checkOk.(name);
			name = "palette cpu %".format(stem);
			if (win[\cpu] >= 25) { fail.(name, "server CPU average % percent is 25 or more".format(win[\cpu].round(0.01))) };
			if (win[\cpu] > 12) { checkWarn.("palette cpu % average % percent is above 12 percent".format(stem, win[\cpu].round(0.01))) };
			checkOk.(name);
		};

		// --- Extreme notes: every pitched voice of a non-classic palette, alone ---
		stems.do { |stem|
			var mod, insts, cases, prefix, ids, groups, buses, probes, name, problems;
			if (stem != \classic) {
				name = "palette extreme notes %".format(stem);
				prefix = "pp_%_".format(stem);
				mod = ~ppLib[\palettes][stem];
				insts = List.new;
				[\bass, \arp, \pad, \lead].do { |role|
					var entry = mod[\roles][role];
					if (entry.notNil and: { entry[\instrument].asString.beginsWith(prefix) }) {
						if (insts.includes(entry[\instrument]).not) { insts.add(entry[\instrument]) };
					};
				};
				cases = List.new;
				insts.do { |inst| [-12, 127].do { |note| cases.add([inst, note]) } };
				ids = cases.collect { nextId = nextId + 1; nextId };
				groups = cases.collect { Group.new(s) };
				buses = cases.collect { Bus.audio(s, 2) };
				ids.do { |id| replies[id] = List.new };
				s.sync;
				probes = cases.collect { |c, k| Synth.after(groups[k], \ppMeterProbe, [\in, buses[k].index, \id, ids[k]]) };
				cases.do { |c, k|
					Synth(c[0], [\out, buses[k].index, \amp, 0.1, \freq, c[1].midicps], groups[k]);
				};
				0.4.wait;
				groups.do { |g| g.set(\gate, 0) };
				2.0.wait;
				problems = List.new;
				cases.do { |c, k|
					var rs = replies[ids[k]];
					var pk = if (rs.size > 0) { rs.collect { |r| r[2] }.maxItem } { 0 };
					if (rs.size == 0) {
						problems.add("% at MIDI %: no meter replies".format(c[0], c[1]));
					};
					if (rs.any { |r| r[3] > 0 } or: { pk.isNaN } or: { pk >= 4.0 }) {
						problems.add("% at MIDI % gives a bad value or a peak of % (limit 4.0)".format(c[0], c[1], pk));
					};
				};
				probes.do { |p| p.free };
				groups.do { |g| g.free };
				buses.do { |b| b.free };
				ids.do { |id| replies.removeAt(id) };
				s.sync;
				if (problems.size > 0) { fail.(name, problems.join("; ")) };
				checkOk.(name);
			};
		};

		// Put the selections back, then finish.
		sendSel.('/pp/palette', 'classic');
		sendSel.('/pp/epic', 50);
		sendSel.('/pp/volume', 80);
		0.3.wait;
		// Stop the layers and let their last timestamped notes land before the
		// server quits (otherwise the server logs "Group not found" noise).
		~ppStop.value;
		0.6.wait;
		"PALETTE PASS".postln;
		s.quit(onComplete: { 0.exit });
	}.try({ |err|
		topFail.(err);
		s.quit(onComplete: { 1.exit });
	});
}, AppClock);
)
