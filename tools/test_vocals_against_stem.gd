extends SceneTree

## Offline accuracy harness: runs PitchDetector over a real isolated vocal
## recording and scores it against the chart's own MIDI notes.
##
## This is a far stronger check than singing into a microphone. It is
## reproducible, it covers a whole song rather than a few seconds, and the
## correct answer is already written down in the chart. It also needs no
## microphone at all, which matters when one is not available.
##
##   ffmpeg -i vocals.opus -ac 1 -ar 16000 -c:a pcm_s16le tmp/vocals16k.wav
##   godot --headless --path . --script res://tools/test_vocals_against_stem.gd
##
## Both inputs live in tmp/ and are gitignored: they are copyrighted audio.

const WAV_PATH := "res://tmp/vocals16k.wav"
const MIDI_PATH := "res://tmp/notes.mid"
const RATE := 16000.0
const WINDOW := 1024
const HOP := 320                  # 20ms
# A note has to be long enough to actually hold before it is fair to grade.
const MIN_NOTE_MS := 120.0
# Ignore the attack, where the voice is still sliding into the note.
const NOTE_HEAD_SKIP := 0.30


func _read_wav_mono(path: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var data := file.get_buffer(file.get_length())
	file.close()
	# Walk RIFF chunks to find 'data' rather than assuming a 44 byte header.
	var pos := 12
	while pos + 8 <= data.size():
		var chunk_id := data.slice(pos, pos + 4).get_string_from_ascii()
		var chunk_size := (
			data[pos + 4] | (data[pos + 5] << 8)
			| (data[pos + 6] << 16) | (data[pos + 7] << 24))
		if chunk_id == "data":
			var sample_count := chunk_size / 2
			out.resize(sample_count)
			var base := pos + 8
			for i in range(sample_count):
				var lo := data[base + i * 2]
				var hi := data[base + i * 2 + 1]
				var value := lo | (hi << 8)
				if value >= 32768:
					value -= 65536
				out[i] = float(value) / 32768.0
			return out
		pos += 8 + chunk_size + (chunk_size & 1)
	return out


func _initialize() -> void:
	if not FileAccess.file_exists(WAV_PATH) or not FileAccess.file_exists(MIDI_PATH):
		print("Missing tmp/vocals16k.wav or tmp/notes.mid - see header for setup.")
		quit(0)
		return

	var samples := _read_wav_mono(WAV_PATH)
	if samples.is_empty():
		print("Could not read WAV data")
		quit(1)
		return
	print("stem: %.1f s at %d Hz" % [samples.size() / RATE, int(RATE)])

	var midi_file := FileAccess.open(MIDI_PATH, FileAccess.READ)
	var parser = MidiParser.new()
	parser.parse_data(midi_file.get_buffer(midi_file.get_length()), "Expert", "guitar")
	midi_file.close()
	var lead: Array = parser.vocal_parts.get("lead", [])
	if lead.is_empty():
		print("Chart has no lead vocal part")
		quit(1)
		return

	# --- Analyse the whole stem once ---
	var times := PackedFloat32Array()
	var midis := PackedFloat32Array()
	var window := PackedFloat32Array()
	window.resize(WINDOW)
	var offset := 0
	var analysed := 0
	var started := Time.get_ticks_msec()
	while offset + WINDOW < samples.size():
		for i in range(WINDOW):
			window[i] = samples[offset + i]
		var result := PitchDetector.detect(window, RATE)
		analysed += 1
		if bool(result["voiced"]):
			times.append(float(offset + WINDOW / 2) / RATE * 1000.0)
			midis.append(float(result["midi"]))
		offset += HOP
	print("analysed %d windows in %.1f s, %d voiced (%.0f%%)" % [
		analysed, (Time.get_ticks_msec() - started) / 1000.0, times.size(),
		100.0 * float(times.size()) / float(maxi(analysed, 1))])

	# --- Grade each charted note against the detected pitch inside it ---
	var graded := 0
	var within_half := 0
	var within_one := 0
	var within_two := 0
	var octave_errors := 0
	var errors: Array = []
	var search := 0
	for note in lead:
		if bool(note["non_pitched"]):
			continue
		var start_ms := float(note["time_ms"])
		var end_ms := float(note["end_ms"])
		if end_ms - start_ms < MIN_NOTE_MS:
			continue
		var from_ms := start_ms + (end_ms - start_ms) * NOTE_HEAD_SKIP
		while search < times.size() and float(times[search]) < from_ms:
			search += 1
		var inside: Array = []
		var scan := search
		while scan < times.size() and float(times[scan]) <= end_ms:
			inside.append(float(midis[scan]))
			scan += 1
		if inside.size() < 3:
			continue
		inside.sort()
		var median := float(inside[inside.size() / 2])
		var target := float(note["midi_note"])
		# Octave-agnostic, which is how vocals are scored.
		var distance := PitchDetector.pitch_class_distance(median, target)
		graded += 1
		errors.append(distance)
		if distance <= 0.5:
			within_half += 1
		if distance <= 1.0:
			within_one += 1
		if distance <= 2.0:
			within_two += 1
		# Right pitch class but wrong register is fine; genuinely wrong is not.
		if absf(median - target) > 6.0 and distance <= 1.0:
			octave_errors += 1

	if graded == 0:
		print("No gradeable notes - stem and chart may not be aligned")
		quit(1)
		return
	errors.sort()
	var median_error := float(errors[errors.size() / 2])
	var pct_half := 100.0 * float(within_half) / float(graded)
	var pct_one := 100.0 * float(within_one) / float(graded)
	var pct_two := 100.0 * float(within_two) / float(graded)
	print("\ngraded %d of %d charted notes" % [graded, lead.size()])
	print("  within 0.5 semitone : %5.1f%%" % pct_half)
	print("  within 1.0 semitone : %5.1f%%" % pct_one)
	print("  within 2.0 semitones: %5.1f%%" % pct_two)
	print("  median error        : %5.2f semitones" % median_error)
	print("  octave-shifted but right pitch class: %d" % octave_errors)

	# A detector good enough to score singing has to agree with the chart on
	# the clear majority of held notes.
	assert(pct_one > 60.0)
	assert(median_error < 1.5)
	print("\nStem accuracy test passed")
	quit(0)
