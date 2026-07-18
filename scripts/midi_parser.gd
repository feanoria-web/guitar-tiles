class_name MidiParser
extends RefCounted

# Lightweight MIDI parser for Clone Hero / Rock Band .mid files.
# Output format is identical to ChartParser: notes[], lyric_phrases[], bpm_events[], resolution.

const ChartParserScript = preload("res://scripts/chart_parser.gd")

const DIFFICULTIES := ["Easy", "Medium", "Hard", "Expert"]

# MIDI note ranges per difficulty (Clone Hero / Rock Band standard)
const DIFF_RANGES := {
	"Expert": {"base": 96, "count": 5},
	"Hard":   {"base": 84, "count": 5},
	"Medium": {"base": 72, "count": 5},
	"Easy":   {"base": 60, "count": 5},
}

# Instrument -> MIDI track name mapping
const INSTRUMENT_TRACKS := {
	"guitar": "PART GUITAR",
	"bass": "PART BASS",
	"keys": "PART KEYS",
	"drums": "PART DRUMS",
}
const INSTRUMENT_DISPLAY := {
	"guitar": "Gitar",
	"bass": "Bas",
	"keys": "Klavye",
	"drums": "Davul",
}

# Chord tick tolerance — notes within this range are treated as same beat
const CHORD_TICK_TOLERANCE := 10

var resolution: int = 480
var bpm_events: Array = []    # [{tick, bpm}]
var notes: Array = []         # [{time_ms, lane, duration_ms}]
var lyrics: Array = []        # [{time_ms, text}]
var lyric_phrases: Array = [] # [{start_ms, end_ms, text, syllables}]

func parse_file(path: String, difficulty: String = "Expert", instrument: String = "guitar") -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MidiParser: cannot open %s" % path)
		return false
	var data := file.get_buffer(file.get_length())
	file.close()
	return parse_data(data, difficulty, instrument)

func parse_data(data: PackedByteArray, difficulty: String = "Expert", instrument: String = "guitar") -> bool:
	if data.size() < 14:
		push_error("MidiParser: file too small")
		return false

	var pos := 0

	# --- Header chunk ---
	var header_id := _read_ascii(data, pos, 4)
	pos += 4
	if header_id != "MThd":
		push_error("MidiParser: not a MIDI file (got '%s')" % header_id)
		return false

	var header_len := _read_u32_be(data, pos); pos += 4
	var format := _read_u16_be(data, pos); pos += 2
	var num_tracks := _read_u16_be(data, pos); pos += 2
	resolution = _read_u16_be(data, pos); pos += 2

	if resolution & 0x8000:
		push_error("MidiParser: SMPTE time division not supported")
		return false

	print("MidiParser: format=%d tracks=%d resolution=%d" % [format, num_tracks, resolution])

	# --- Parse all tracks ---
	var tracks: Array = []  # [{name, events}]
	for _t in range(num_tracks):
		if pos + 8 > data.size():
			break
		var track_id := _read_ascii(data, pos, 4); pos += 4
		var track_len := _read_u32_be(data, pos); pos += 4
		if track_id != "MTrk":
			pos += track_len
			continue
		var track_end := pos + track_len
		var track := _parse_track(data, pos, track_end)
		tracks.append(track)
		pos = track_end

	# --- Extract tempo map from all tracks (usually track 0) ---
	for track in tracks:
		for ev in track["events"]:
			if ev["type"] == "tempo":
				var bpm := 60000000.0 / float(ev["value"])
				bpm_events.append({"tick": ev["tick"], "bpm": bpm})

	bpm_events.sort_custom(func(a, b): return a["tick"] < b["tick"])
	if bpm_events.is_empty():
		push_error("MidiParser: no tempo events found, defaulting to 120 BPM")
		bpm_events.append({"tick": 0, "bpm": 120.0})

	# --- Find note track for requested instrument ---
	var note_track = null
	var target_track_name: String = INSTRUMENT_TRACKS.get(instrument, "PART GUITAR")

	# Try exact match first
	for track in tracks:
		if track["name"].to_upper() == target_track_name:
			note_track = track
			break

	# Fallback: try priority order
	if note_track == null:
		var track_priority := ["PART GUITAR", "PART BASS", "PART KEYS", "PART DRUMS"]
		for pname in track_priority:
			for track in tracks:
				if track["name"].to_upper() == pname:
					note_track = track
					break
			if note_track:
				break

	if note_track == null:
		# Fallback: first track with note events in the expected range
		for track in tracks:
			for ev in track["events"]:
				if ev["type"] == "note_on" and ev["note"] >= 60 and ev["note"] <= 100:
					note_track = track
					break
			if note_track:
				break

	if note_track == null:
		push_error("MidiParser: no suitable note track found")
		return false

	print("MidiParser: using track '%s' for instrument '%s'" % [note_track["name"], instrument])

	# --- Extract notes for requested difficulty ---
	_extract_notes(note_track, difficulty)

	# --- Extract lyrics from PART VOCALS ---
	for track in tracks:
		if track["name"].to_upper() == "PART VOCALS":
			_extract_lyrics(track)
			break

	print("MidiParser: %d notes, %d lyric phrases" % [notes.size(), lyric_phrases.size()])
	return true

func get_available_difficulties() -> Array[String]:
	return DIFFICULTIES.duplicate()

static func scan_difficulties_from_data(data: PackedByteArray) -> Array[String]:
	var parser := MidiParser.new()
	if not parser.parse_data(data, "Expert"):
		return []
	var result: Array[String] = []
	for diff in DIFFICULTIES:
		result.append(diff)
	return result

## Returns {instrument_key: [difficulties]} for all instruments with notes.
## Parses track headers to find PART GUITAR/BASS/KEYS/DRUMS, then checks
## which difficulty ranges actually contain note events.
static func scan_instruments_from_data(data: PackedByteArray) -> Dictionary:
	if data.size() < 14:
		return {}
	var parser := MidiParser.new()
	var pos := 0
	var header_id := parser._read_ascii(data, pos, 4); pos += 4
	if header_id != "MThd":
		return {}
	pos += 4  # header_len
	pos += 2  # format
	var num_tracks := parser._read_u16_be(data, pos); pos += 2
	parser.resolution = parser._read_u16_be(data, pos); pos += 2
	if parser.resolution & 0x8000:
		return {}

	var tracks: Array = []
	for _t in range(num_tracks):
		if pos + 8 > data.size():
			break
		var track_id := parser._read_ascii(data, pos, 4); pos += 4
		var track_len := parser._read_u32_be(data, pos); pos += 4
		if track_id != "MTrk":
			pos += track_len
			continue
		var track_end := pos + track_len
		var track := parser._parse_track(data, pos, track_end)
		tracks.append(track)
		pos = track_end

	# Extract tempo map
	for track in tracks:
		for ev in track["events"]:
			if ev["type"] == "tempo":
				var bpm := 60000000.0 / float(ev["value"])
				parser.bpm_events.append({"tick": ev["tick"], "bpm": bpm})
	parser.bpm_events.sort_custom(func(a, b): return a["tick"] < b["tick"])
	if parser.bpm_events.is_empty():
		parser.bpm_events.append({"tick": 0, "bpm": 120.0})

	var result := {}
	for inst_key in INSTRUMENT_TRACKS:
		var track_name: String = INSTRUMENT_TRACKS[inst_key]
		var inst_track = null
		for track in tracks:
			if track["name"].to_upper() == track_name:
				inst_track = track
				break
		if inst_track == null:
			continue
		# Check which difficulties have notes
		var diffs: Array[String] = []
		for diff in DIFFICULTIES:
			var diff_base: int = DIFF_RANGES[diff]["base"]
			var diff_max: int = diff_base + DIFF_RANGES[diff]["count"] - 1
			var has_notes := false
			for ev in inst_track["events"]:
				if ev["type"] == "note_on" and ev["note"] >= diff_base and ev["note"] <= diff_max:
					has_notes = true
					break
			if has_notes:
				diffs.append(diff)
		if diffs.size() > 0:
			result[inst_key] = diffs
	return result

# --- Track parsing ---

func _parse_track(data: PackedByteArray, start: int, end_pos: int) -> Dictionary:
	var events: Array = []
	var track_name := ""
	var pos := start
	var abs_tick := 0
	var running_status := 0

	while pos < end_pos:
		# Read delta time (variable length)
		var delta_result := _read_var_len(data, pos)
		var delta: int = delta_result[0]
		pos = delta_result[1]
		abs_tick += delta

		if pos >= end_pos:
			break

		var status_byte: int = data[pos]

		# Meta event
		if status_byte == 0xFF:
			pos += 1
			if pos >= end_pos:
				break
			var meta_type: int = data[pos]; pos += 1
			var len_result := _read_var_len(data, pos)
			var meta_len: int = len_result[0]
			pos = len_result[1]

			if meta_type == 0x51:  # Set Tempo
				if meta_len >= 3 and pos + 3 <= end_pos:
					var us_per_qn := (data[pos] << 16) | (data[pos + 1] << 8) | data[pos + 2]
					events.append({"type": "tempo", "tick": abs_tick, "value": us_per_qn})
			elif meta_type == 0x03:  # Track Name
				if pos + meta_len <= end_pos:
					track_name = data.slice(pos, pos + meta_len).get_string_from_utf8()
			elif meta_type == 0x05:  # Lyric
				if pos + meta_len <= end_pos:
					var text := data.slice(pos, pos + meta_len).get_string_from_utf8()
					events.append({"type": "lyric", "tick": abs_tick, "text": text})
			elif meta_type == 0x01:  # Text event
				if pos + meta_len <= end_pos:
					var text := data.slice(pos, pos + meta_len).get_string_from_utf8()
					events.append({"type": "text", "tick": abs_tick, "text": text})
			elif meta_type == 0x2F:  # End of Track
				pos += meta_len
				break

			pos += meta_len
			continue

		# SysEx event
		if status_byte == 0xF0 or status_byte == 0xF7:
			pos += 1
			var len_result := _read_var_len(data, pos)
			pos = len_result[1] + len_result[0]
			continue

		# Channel event
		if status_byte & 0x80:
			running_status = status_byte
			pos += 1
		else:
			# Running status — reuse previous status byte
			status_byte = running_status

		var msg_type := status_byte & 0xF0

		if msg_type == 0x90:  # Note On
			if pos + 1 < end_pos:
				var note: int = data[pos]; pos += 1
				var vel: int = data[pos]; pos += 1
				if vel > 0:
					events.append({"type": "note_on", "tick": abs_tick, "note": note, "velocity": vel})
				else:
					events.append({"type": "note_off", "tick": abs_tick, "note": note})
			else:
				pos = end_pos
		elif msg_type == 0x80:  # Note Off
			if pos + 1 < end_pos:
				var note: int = data[pos]; pos += 1
				var _vel: int = data[pos]; pos += 1
				events.append({"type": "note_off", "tick": abs_tick, "note": note})
			else:
				pos = end_pos
		elif msg_type == 0xA0 or msg_type == 0xB0 or msg_type == 0xE0:
			pos += 2  # 2 data bytes
		elif msg_type == 0xC0 or msg_type == 0xD0:
			pos += 1  # 1 data byte
		else:
			pos += 1  # Unknown — skip 1 byte

	return {"name": track_name, "events": events}

# --- Note extraction ---

func _extract_notes(track: Dictionary, difficulty: String) -> void:
	if not DIFF_RANGES.has(difficulty):
		difficulty = "Expert"

	var diff_base: int = DIFF_RANGES[difficulty]["base"]
	var diff_count: int = DIFF_RANGES[difficulty]["count"]
	var diff_max: int = diff_base + diff_count - 1

	# Collect note_on/off pairs
	var active_notes := {}  # note_number -> {tick, velocity}
	var raw_notes: Array = []  # [{tick, lane, duration_ticks}]

	for ev in track["events"]:
		if ev["type"] == "note_on":
			var note: int = ev["note"]
			if note >= diff_base and note <= diff_max:
				active_notes[note] = {"tick": ev["tick"], "velocity": ev["velocity"]}
		elif ev["type"] == "note_off":
			var note: int = ev["note"]
			if active_notes.has(note):
				var start_tick: int = active_notes[note]["tick"]
				var dur_ticks: int = ev["tick"] - start_tick
				var lane: int = note - diff_base
				raw_notes.append({"tick": start_tick, "lane": lane, "duration_ticks": dur_ticks})
				active_notes.erase(note)

	# Sort by tick
	raw_notes.sort_custom(func(a, b): return a["tick"] < b["tick"])

	# Apply chord tolerance: snap notes within CHORD_TICK_TOLERANCE to the same tick
	if raw_notes.size() > 1:
		var base_tick: int = raw_notes[0]["tick"]
		for i in range(1, raw_notes.size()):
			var t: int = raw_notes[i]["tick"]
			if absi(t - base_tick) <= CHORD_TICK_TOLERANCE:
				raw_notes[i]["tick"] = base_tick
			else:
				base_tick = t

	# Convert to time_ms
	for rn in raw_notes:
		var tick: int = rn["tick"]
		var time_ms := ChartParserScript.tick_to_ms(tick, bpm_events, resolution)
		var duration_ms := 0.0
		var dur_ticks: int = rn["duration_ticks"]
		if dur_ticks > resolution:  # Longer than a quarter note = sustain
			duration_ms = ChartParserScript.tick_to_ms(tick + dur_ticks, bpm_events, resolution) - time_ms
		notes.append({"time_ms": time_ms, "lane": rn["lane"], "duration_ms": duration_ms})

# --- Lyric extraction ---

func _extract_lyrics(track: Dictionary) -> void:
	# Collect raw lyrics
	var raw_lyrics: Array = []  # [{time_ms, text}]
	for ev in track["events"]:
		if ev["type"] != "lyric" and ev["type"] != "text":
			continue
		var text: String = ev["text"].strip_edges()
		if text == "" or text == "+" or text == "#":
			continue
		# Skip section/mood tags like [idle], [intense], [mellow], [play], etc.
		if text.begins_with("[") and text.ends_with("]"):
			continue
		# Remove leading/trailing Clone Hero markers: # ^ § = $
		while text.length() > 0 and text[0] in ["#", "^", "§", "=", "$"]:
			text = text.substr(1)
		while text.length() > 0 and text[text.length() - 1] in ["#", "^", "§", "=", "$"]:
			text = text.substr(0, text.length() - 1)
		text = text.strip_edges()
		if text == "":
			continue
		var time_ms := ChartParserScript.tick_to_ms(ev["tick"], bpm_events, resolution)
		raw_lyrics.append({"time_ms": time_ms, "text": text})

	if raw_lyrics.is_empty():
		return

	# Collect phrase boundaries from note 105 (Rock Band phrase marker)
	var phrase_ranges: Array = []  # [{start_ms, end_ms}]
	var phrase_start_ticks: Array = []
	for ev in track["events"]:
		if ev["type"] == "note_on" and ev["note"] == 105:
			phrase_start_ticks.append(ev["tick"])
		elif ev["type"] == "note_off" and ev["note"] == 105:
			if phrase_start_ticks.size() > 0:
				var start_tick: int = phrase_start_ticks[phrase_start_ticks.size() - 1]
				phrase_start_ticks.pop_back()
				var start_ms := ChartParserScript.tick_to_ms(start_tick, bpm_events, resolution)
				var end_ms := ChartParserScript.tick_to_ms(ev["tick"], bpm_events, resolution)
				phrase_ranges.append({"start_ms": start_ms, "end_ms": end_ms})

	if phrase_ranges.size() > 0:
		# Use note 105 phrase boundaries
		phrase_ranges.sort_custom(func(a, b): return a["start_ms"] < b["start_ms"])
		for pr in phrase_ranges:
			var syllables: Array = []
			for lyr in raw_lyrics:
				var t: float = lyr["time_ms"]
				if t >= pr["start_ms"] - 10 and t <= pr["end_ms"] + 10:
					syllables.append(lyr)
			if syllables.size() > 0:
				_finalize_phrase_with_end(syllables, pr["end_ms"])
		# Catch orphan lyrics outside any phrase range
		var orphans: Array = []
		for lyr in raw_lyrics:
			var t: float = lyr["time_ms"]
			var in_phrase := false
			for pr in phrase_ranges:
				if t >= pr["start_ms"] - 10 and t <= pr["end_ms"] + 10:
					in_phrase = true
					break
			if not in_phrase:
				orphans.append(lyr)
		if orphans.size() > 0:
			_build_phrases_by_gap(orphans)
	else:
		# Fallback: group lyrics by gap > 2 seconds
		_build_phrases_by_gap(raw_lyrics)

func _build_phrases_by_gap(raw_lyrics: Array) -> void:
	var phrase_syllables: Array = []
	var phrase_gap_ms := 2000.0
	for lyr in raw_lyrics:
		if phrase_syllables.size() > 0:
			var last_time: float = phrase_syllables[phrase_syllables.size() - 1]["time_ms"]
			if float(lyr["time_ms"]) - last_time > phrase_gap_ms:
				_finalize_phrase(phrase_syllables)
				phrase_syllables.clear()
		phrase_syllables.append(lyr)
	if phrase_syllables.size() > 0:
		_finalize_phrase(phrase_syllables)

func _finalize_phrase_with_end(syllables: Array, end_ms: float) -> void:
	if syllables.is_empty():
		return
	var full_text := ""
	var positions: Array = []
	for syl in syllables:
		var txt: String = syl["text"]
		var t_ms: float = syl["time_ms"]
		var has_hyphen := txt.ends_with("-")
		var display := txt.substr(0, txt.length() - 1) if has_hyphen else txt
		if full_text != "" and not full_text.ends_with("-"):
			full_text += " "
		if full_text.ends_with("-"):
			full_text = full_text.substr(0, full_text.length() - 1)
		var char_start: int = full_text.length()
		full_text += display
		var char_end: int = full_text.length()
		positions.append({"time_ms": t_ms, "char_start": char_start, "char_end": char_end})
		if has_hyphen:
			full_text += "-"
	if full_text.ends_with("-"):
		full_text = full_text.substr(0, full_text.length() - 1)
	lyric_phrases.append({
		"start_ms": float(syllables[0]["time_ms"]),
		"end_ms": end_ms,
		"text": full_text,
		"syllables": positions,
	})

func _finalize_phrase(syllables: Array) -> void:
	if syllables.is_empty():
		return

	var full_text := ""
	var positions: Array = []

	for syl in syllables:
		var txt: String = syl["text"]
		var t_ms: float = syl["time_ms"]

		# Handle hyphenated syllables (word continuations)
		var has_hyphen := txt.ends_with("-")
		var display := txt.substr(0, txt.length() - 1) if has_hyphen else txt

		if full_text != "" and not full_text.ends_with("-"):
			full_text += " "

		if full_text.ends_with("-"):
			full_text = full_text.substr(0, full_text.length() - 1)

		var char_start: int = full_text.length()
		full_text += display
		var char_end: int = full_text.length()
		positions.append({"time_ms": t_ms, "char_start": char_start, "char_end": char_end})

		if has_hyphen:
			full_text += "-"

	# Clean trailing hyphen
	if full_text.ends_with("-"):
		full_text = full_text.substr(0, full_text.length() - 1)

	var start_ms: float = syllables[0]["time_ms"]
	var end_ms: float = syllables[syllables.size() - 1]["time_ms"] + 3000.0  # estimate phrase end

	lyric_phrases.append({
		"start_ms": start_ms,
		"end_ms": end_ms,
		"text": full_text,
		"syllables": positions,
	})

# --- Binary reading helpers (big-endian) ---

func _read_ascii(data: PackedByteArray, pos: int, length: int) -> String:
	if pos + length > data.size():
		return ""
	return data.slice(pos, pos + length).get_string_from_ascii()

func _read_u32_be(data: PackedByteArray, pos: int) -> int:
	if pos + 4 > data.size():
		return 0
	return (data[pos] << 24) | (data[pos + 1] << 16) | (data[pos + 2] << 8) | data[pos + 3]

func _read_u16_be(data: PackedByteArray, pos: int) -> int:
	if pos + 2 > data.size():
		return 0
	return (data[pos] << 8) | data[pos + 1]

func _read_var_len(data: PackedByteArray, pos: int) -> Array:
	# Returns [value, new_pos]
	var value := 0
	var p := pos
	while p < data.size():
		var b: int = data[p]
		value = (value << 7) | (b & 0x7F)
		p += 1
		if not (b & 0x80):
			break
	return [value, p]

func print_summary() -> void:
	print("=== MIDI Parser Summary ===")
	print("Resolution: %d" % resolution)
	print("BPM events: %d" % bpm_events.size())
	if bpm_events.size() > 0:
		print("Initial BPM: %.1f" % float(bpm_events[0]["bpm"]))
	print("Total notes: %d" % notes.size())
	print("Lyric phrases: %d" % lyric_phrases.size())
