extends SceneTree

# Builds a synthetic PART VOCALS / PART HARM2 MIDI in memory and runs it through
# MidiParser, so the karaoke chart layer can be verified without shipping a
# copyrighted song.

const TICKS := 480


func _push_var_len(out: PackedByteArray, value: int) -> void:
	var buffer: Array[int] = [value & 0x7F]
	value >>= 7
	while value > 0:
		buffer.push_front((value & 0x7F) | 0x80)
		value >>= 7
	for byte in buffer:
		out.append(byte)


func _meta_text(out: PackedByteArray, delta: int, meta_type: int, text: String) -> void:
	_push_var_len(out, delta)
	out.append(0xFF)
	out.append(meta_type)
	var raw := text.to_utf8_buffer()
	_push_var_len(out, raw.size())
	out.append_array(raw)


func _note(out: PackedByteArray, delta: int, on: bool, note: int) -> void:
	_push_var_len(out, delta)
	out.append(0x90 if on else 0x80)
	out.append(note)
	out.append(100 if on else 0)


func _track(events: PackedByteArray) -> PackedByteArray:
	var body := events.duplicate()
	# End of track
	_push_var_len(body, 0)
	body.append(0xFF)
	body.append(0x2F)
	body.append(0x00)
	var out := PackedByteArray()
	out.append_array("MTrk".to_utf8_buffer())
	for shift in [24, 16, 8, 0]:
		out.append((body.size() >> shift) & 0xFF)
	out.append_array(body)
	return out


func _build_midi() -> PackedByteArray:
	var midi := PackedByteArray()
	midi.append_array("MThd".to_utf8_buffer())
	for byte in [0, 0, 0, 6, 0, 1, 0, 3]:
		midi.append(byte)
	midi.append((TICKS >> 8) & 0xFF)
	midi.append(TICKS & 0xFF)

	# Track 0: tempo map at 120 BPM.
	var tempo := PackedByteArray()
	_meta_text(tempo, 0, 0x03, "tempo")
	_push_var_len(tempo, 0)
	tempo.append(0xFF)
	tempo.append(0x51)
	tempo.append(0x03)
	for byte in [0x07, 0xA1, 0x20]:
		tempo.append(byte)
	midi.append_array(_track(tempo))

	# Track 1: PART VOCALS. One phrase (note 105) covering four syllables, the
	# third non-pitched and the fourth a hyphenated word continuation. Plus an
	# overdrive marker and a percussion hit.
	var vox := PackedByteArray()
	_meta_text(vox, 0, 0x03, "PART VOCALS")
	_note(vox, 0, true, 105)          # phrase opens
	_note(vox, 0, true, 116)          # overdrive spans the phrase
	_meta_text(vox, 0, 0x05, "Hel-")
	_note(vox, 0, true, 60)
	_note(vox, TICKS, false, 60)
	_meta_text(vox, 0, 0x05, "lo")
	_note(vox, 0, true, 62)
	_note(vox, TICKS, false, 62)
	_meta_text(vox, 0, 0x05, "there#")
	_note(vox, 0, true, 64)
	_note(vox, TICKS, false, 64)
	_meta_text(vox, 0, 0x05, "friend")
	_note(vox, 0, true, 67)
	_note(vox, TICKS, false, 67)
	_note(vox, 0, false, 116)
	_note(vox, 0, false, 105)         # phrase closes
	_note(vox, TICKS, true, 96)       # percussion hit
	_note(vox, 10, false, 96)
	midi.append_array(_track(vox))

	# Track 2: PART HARM2 — two notes a third above, one marked hidden.
	var harm := PackedByteArray()
	_meta_text(harm, 0, 0x03, "PART HARM2")
	_meta_text(harm, 0, 0x05, "Hel-")
	_note(harm, 0, true, 64)
	_note(harm, TICKS, false, 64)
	_meta_text(harm, 0, 0x05, "lo$")
	_note(harm, 0, true, 65)
	_note(harm, TICKS, false, 65)
	midi.append_array(_track(harm))
	return midi


func _initialize() -> void:
	var marker := MidiParser.parse_vocal_syllable("Hel-")
	assert(marker["text"] == "Hel")
	assert(marker["word_continues"])
	assert(not marker["non_pitched"])
	marker = MidiParser.parse_vocal_syllable("there#")
	assert(marker["text"] == "there")
	assert(marker["non_pitched"])
	marker = MidiParser.parse_vocal_syllable("+")
	assert(marker["slide"] and marker["text"] == "")
	marker = MidiParser.parse_vocal_syllable("lo$")
	assert(marker["text"] == "lo" and marker["hidden"])

	var midi_path := "user://_test_vocals.mid"
	var file := FileAccess.open(midi_path, FileAccess.WRITE)
	assert(file != null)
	file.store_buffer(_build_midi())
	file.close()

	var parser = MidiParser.new()
	# The synthetic file has no playable instrument track; vocals extraction
	# must still run, so the return value is deliberately not asserted.
	parser.parse_file(midi_path, "Expert", "guitar")

	# --- Lead part ---
	assert(parser.vocal_parts.has("lead"))
	var lead: Array = parser.vocal_parts["lead"]
	assert(lead.size() == 4)
	assert(int(lead[0]["midi_note"]) == 60)
	assert(String(lead[0]["text"]) == "Hel")
	assert(bool(lead[0]["word_continues"]))
	assert(String(lead[1]["text"]) == "lo")
	assert(not bool(lead[1]["word_continues"]))
	# Marker notes must never leak into the sung notes.
	for note in lead:
		var pitch := int(note["midi_note"])
		assert(pitch >= parser.VOCAL_PITCH_MIN and pitch <= parser.VOCAL_PITCH_MAX)
		assert(float(note["end_ms"]) > float(note["time_ms"]))
	# Non-pitched syllable is flagged but keeps its text and its timing.
	assert(bool(lead[2]["non_pitched"]))
	assert(String(lead[2]["text"]) == "there")
	# 120 BPM, 480 ticks per beat -> 500ms per syllable.
	assert(abs(float(lead[0]["end_ms"]) - float(lead[0]["time_ms"]) - 500.0) < 1.0)
	assert(abs(float(lead[1]["time_ms"]) - 500.0) < 1.0)

	# --- Harmony ---
	assert(parser.vocal_parts.has("harm2"))
	var harm2: Array = parser.vocal_parts["harm2"]
	assert(harm2.size() == 2)
	assert(int(harm2[0]["midi_note"]) == 64)
	assert(bool(harm2[1]["hidden"]))

	# --- Phrases, overdrive, percussion ---
	assert(parser.vocal_phrases.size() == 1)
	var phrase: Dictionary = parser.vocal_phrases[0]
	assert(bool(phrase["overdrive"]))
	assert(abs(float(phrase["start_ms"])) < 1.0)
	assert(abs(float(phrase["end_ms"]) - 2000.0) < 1.0)
	# Every sung syllable falls inside the phrase it belongs to.
	for note in lead:
		assert(float(note["time_ms"]) >= float(phrase["start_ms"]) - 1.0)
		assert(float(note["time_ms"]) < float(phrase["end_ms"]) + 1.0)
	assert(parser.vocal_percussion.size() == 1)

	# The existing lyric strip must be untouched by any of this.
	assert(parser.lyric_phrases.size() >= 1)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(midi_path))
	print("Vocals parser tests passed: %d lead, %d harm2, %d phrases, %d percussion" % [
		lead.size(), harm2.size(),
		parser.vocal_phrases.size(), parser.vocal_percussion.size()])
	quit(0)
