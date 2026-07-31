extends SceneTree

# Verifies pitch detection against synthetic tones of known frequency, including
# the harmonic-rich cases that make naive autocorrelation drop an octave.

const RATE := 16000.0
const WINDOW := 1024


func _tone(hz: float, harmonics: Array = [1.0], noise := 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(WINDOW)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in range(WINDOW):
		var t := float(i) / RATE
		var value := 0.0
		for h in range(harmonics.size()):
			value += float(harmonics[h]) * sin(TAU * hz * float(h + 1) * t)
		if noise > 0.0:
			value += rng.randfn(0.0, noise)
		out[i] = value * 0.3
	return out


func _cents_error(detected: float, expected: float) -> float:
	return abs(1200.0 * (log(detected / expected) / log(2.0)))


func _initialize() -> void:
	# --- Pure tones across the sung range ---
	for hz in [82.41, 110.0, 146.83, 220.0, 329.63, 440.0, 659.26, 880.0]:
		var result := PitchDetector.detect(_tone(hz), RATE)
		assert(result["voiced"])
		var error := _cents_error(float(result["hz"]), hz)
		assert(error < 15.0)

	# --- Harmonic-rich, i.e. what a voice actually is. This is the case that
	# makes plain autocorrelation report hz/2. ---
	var vowel := [1.0, 0.7, 0.5, 0.35, 0.2, 0.12]
	for hz in [98.0, 155.56, 246.94, 392.0, 523.25]:
		var result := PitchDetector.detect(_tone(hz, vowel), RATE)
		assert(result["voiced"])
		var error := _cents_error(float(result["hz"]), hz)
		assert(error < 25.0)
		# Explicitly reject the octave-below failure mode.
		assert(_cents_error(float(result["hz"]), hz * 0.5) > 200.0)

	# --- A missing fundamental must still resolve to the fundamental ---
	var missing_root := PitchDetector.detect(
		_tone(220.0, [0.0, 1.0, 0.8, 0.6]), RATE)
	assert(missing_root["voiced"])
	assert(_cents_error(float(missing_root["hz"]), 220.0) < 40.0)

	# --- Noise tolerance ---
	var noisy := PitchDetector.detect(_tone(196.0, vowel, 0.08), RATE)
	assert(noisy["voiced"])
	assert(_cents_error(float(noisy["hz"]), 196.0) < 35.0)

	# --- Unvoiced input must not report a pitch ---
	var silence := PackedFloat32Array()
	silence.resize(WINDOW)
	assert(not PitchDetector.detect(silence, RATE)["voiced"])
	var hiss := _tone(0.0, [0.0], 0.5)
	var hiss_result := PitchDetector.detect(hiss, RATE)
	if hiss_result["voiced"]:
		assert(float(hiss_result["clarity"]) < 0.95)
	assert(not PitchDetector.detect(PackedFloat32Array(), RATE)["voiced"])

	# --- Note naming and octave-agnostic distance ---
	assert(PitchDetector.midi_note_name(69.0) == "A4")
	assert(PitchDetector.midi_note_name(60.0) == "C4")
	assert(abs(PitchDetector.hz_to_midi(440.0) - 69.0) < 0.001)
	# Same pitch class an octave apart must read as a perfect match, which is
	# what lets any voice sing any line.
	assert(PitchDetector.pitch_class_distance(69.0, 57.0) < 0.001)
	assert(abs(PitchDetector.pitch_class_distance(60.0, 61.0) - 1.0) < 0.001)
	assert(abs(PitchDetector.pitch_class_distance(60.0, 66.0) - 6.0) < 0.001)
	# Distance is symmetric and never exceeds a tritone.
	assert(abs(PitchDetector.pitch_class_distance(71.0, 60.0) - 1.0) < 0.001)

	# --- Downsampling keeps the pitch intact ---
	var wide := PackedFloat32Array()
	wide.resize(WINDOW * 3)
	for i in range(WINDOW * 3):
		wide[i] = 0.3 * sin(TAU * 220.0 * float(i) / 48000.0)
	var decimated := PitchDetector.downsample(wide, 3)
	assert(decimated.size() == WINDOW)
	var decimated_result := PitchDetector.detect(decimated, 16000.0)
	assert(decimated_result["voiced"])
	assert(_cents_error(float(decimated_result["hz"]), 220.0) < 20.0)

	# --- Cost budget: this runs on a worker thread, but it still has to keep
	# up with roughly 20 analyses a second. ---
	var bench := _tone(196.0, vowel)
	var started := Time.get_ticks_usec()
	for _i in range(20):
		PitchDetector.detect(bench, RATE)
	var per_call_ms := float(Time.get_ticks_usec() - started) / 20.0 / 1000.0
	print("Pitch detector: %.1f ms per analysis (%d samples @ %d Hz)" % [
		per_call_ms, WINDOW, int(RATE)])
	assert(per_call_ms < 50.0)

	print("Pitch detector tests passed: pure tones, harmonic voices, missing fundamental, noise, unvoiced, octave-agnostic matching")
	quit(0)
