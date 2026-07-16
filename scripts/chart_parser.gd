class_name ChartParser
extends RefCounted

const DIFFICULTIES := ["Easy", "Medium", "Hard", "Expert"]

var resolution: int = 480
var bpm_events: Array = []   # [{tick, bpm}]
var notes: Array = []        # [{time_ms, lane, duration_ms}]
var lyrics: Array = []       # [{time_ms, text}]
var lyric_phrases: Array = [] # [{start_ms, end_ms, text, syllables: [{time_ms, char_start, char_end}]}]

var _sections: Dictionary = {}

func parse_file(path: String, difficulty: String = "Expert") -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ChartParser: cannot open %s" % path)
		return false
	var text := file.get_as_text()
	file.close()
	return parse_text(text, difficulty)

func parse_text(text: String, difficulty: String = "Expert") -> bool:
	_sections = _split_sections(text)

	if _sections.has("Song"):
		_parse_song(_sections["Song"])

	if _sections.has("SyncTrack"):
		_parse_sync_track(_sections["SyncTrack"])
	else:
		push_error("ChartParser: no [SyncTrack] found")
		return false

	if bpm_events.is_empty():
		push_error("ChartParser: no BPM events found")
		return false

	var section_name := difficulty + "Single"
	if _sections.has(section_name):
		_parse_notes(_sections[section_name])
	else:
		push_error("ChartParser: no [%s] found" % section_name)
		return false

	if _sections.has("Events"):
		_parse_events(_sections["Events"])

	return true

func get_available_difficulties() -> Array[String]:
	var result: Array[String] = []
	for diff in DIFFICULTIES:
		if _sections.has(diff + "Single"):
			result.append(diff)
	return result

static func scan_difficulties_from_file(path: String) -> Array[String]:
	var parser := ChartParser.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var text := file.get_as_text()
	file.close()
	parser._sections = parser._split_sections(text)
	return parser.get_available_difficulties()

static func scan_difficulties_from_text(text: String) -> Array[String]:
	var parser := ChartParser.new()
	parser._sections = parser._split_sections(text)
	return parser.get_available_difficulties()

func _split_sections(text: String) -> Dictionary:
	var sections := {}
	var current_name := ""
	var current_lines: Array = []
	var inside := false

	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("[") and stripped.ends_with("]"):
			current_name = stripped.substr(1, stripped.length() - 2)
			current_lines = []
			inside = false
		elif stripped == "{":
			inside = true
		elif stripped == "}":
			inside = false
			sections[current_name] = current_lines
		elif inside:
			current_lines.append(stripped)

	return sections

func _parse_song(lines: Array) -> void:
	for line in lines:
		var parts := (line as String).split("=", true, 1)
		if parts.size() == 2:
			var key := parts[0].strip_edges()
			var val := parts[1].strip_edges()
			if key == "Resolution":
				resolution = int(val)

func _parse_sync_track(lines: Array) -> void:
	for line in lines:
		var parts := (line as String).split("=", true, 1)
		if parts.size() != 2:
			continue
		var tick := int(parts[0].strip_edges())
		var rest := parts[1].strip_edges()
		if rest.begins_with("B "):
			var bpm_val := float(rest.substr(2).strip_edges()) / 1000.0
			bpm_events.append({"tick": tick, "bpm": bpm_val})
	bpm_events.sort_custom(func(a, b): return a["tick"] < b["tick"])

func _tick_to_ms(tick: int) -> float:
	return tick_to_ms(tick, bpm_events, resolution)

static func tick_to_ms(tick: int, bpm_events_arr: Array, res: int) -> float:
	if bpm_events_arr.is_empty():
		return 0.0
	var ms := 0.0
	var prev_tick := 0
	var us_per_beat: float = 60000.0 / float(bpm_events_arr[0]["bpm"])

	for i in range(bpm_events_arr.size()):
		var ev_tick: int = bpm_events_arr[i]["tick"]
		if ev_tick >= tick:
			break
		var delta_ticks: int = ev_tick - prev_tick
		ms += (float(delta_ticks) / float(res)) * us_per_beat
		prev_tick = ev_tick
		us_per_beat = 60000.0 / float(bpm_events_arr[i]["bpm"])

	var delta_ticks: int = tick - prev_tick
	ms += (float(delta_ticks) / float(res)) * us_per_beat
	return ms

func _parse_notes(lines: Array) -> void:
	for line in lines:
		var parts := (line as String).split("=", true, 1)
		if parts.size() != 2:
			continue
		var tick := int(parts[0].strip_edges())
		var rest := parts[1].strip_edges()
		if not rest.begins_with("N "):
			continue
		var tokens := rest.split(" ")
		if tokens.size() < 3:
			continue
		var fret := int(tokens[1])
		var dur := int(tokens[2])
		if fret < 0 or fret > 4:
			continue
		var time_ms := _tick_to_ms(tick)
		var duration_ms := 0.0
		if dur > 0:
			duration_ms = _tick_to_ms(tick + dur) - time_ms
		notes.append({"time_ms": time_ms, "lane": fret, "duration_ms": duration_ms})

func _parse_events(lines: Array) -> void:
	var phrase_start_ms := -1.0
	var phrase_syllables: Array = []

	for line in lines:
		var parts := (line as String).split("=", true, 1)
		if parts.size() != 2:
			continue
		var tick := int(parts[0].strip_edges())
		var rest := parts[1].strip_edges()
		if not rest.begins_with("E "):
			continue
		var content := rest.substr(2).strip_edges()
		if content.begins_with("\"") and content.ends_with("\""):
			content = content.substr(1, content.length() - 2)

		if content == "phrase_start":
			phrase_start_ms = _tick_to_ms(tick)
			phrase_syllables.clear()
		elif content == "phrase_end":
			if phrase_syllables.size() > 0:
				var built := _build_phrase_with_positions(phrase_syllables)
				var end_ms := _tick_to_ms(tick)
				lyric_phrases.append({
					"start_ms": phrase_syllables[0]["time_ms"],
					"end_ms": end_ms,
					"text": built["text"],
					"syllables": built["syllables"],
				})
			phrase_start_ms = -1.0
			phrase_syllables.clear()
		elif content.begins_with("lyric "):
			var lyric_text := content.substr(6)
			var time_ms := _tick_to_ms(tick)
			lyrics.append({"time_ms": time_ms, "text": lyric_text})
			if phrase_start_ms >= 0:
				phrase_syllables.append({"time_ms": time_ms, "text": lyric_text})

func _build_phrase_with_positions(syllables: Array) -> Dictionary:
	var result := ""
	var positions: Array = []  # [{time_ms, char_start, char_end}]

	for syl in syllables:
		var txt: String = syl["text"]
		var t_ms: float = syl["time_ms"]

		if txt == "+":
			continue

		var clean := txt
		if txt.begins_with("+"):
			clean = txt.substr(1)
		elif result != "":
			if result.ends_with("-"):
				result = result.substr(0, result.length() - 1)
			else:
				result += " "

		# Strip trailing hyphen for display, re-add after position recording
		var has_hyphen := clean.ends_with("-")
		var display := clean.substr(0, clean.length() - 1) if has_hyphen else clean

		var char_start: int = result.length()
		result += display
		var char_end: int = result.length()
		positions.append({"time_ms": t_ms, "char_start": char_start, "char_end": char_end})

		if has_hyphen:
			result += "-"

	# Clean any trailing hyphen
	if result.ends_with("-"):
		result = result.substr(0, result.length() - 1)

	return {"text": result, "syllables": positions}

func print_summary() -> void:
	print("=== Chart Parser Summary ===")
	print("Resolution: %d" % resolution)
	print("BPM events: %d" % bpm_events.size())
	print("Total notes: %d" % notes.size())
	print("Total lyrics: %d" % lyrics.size())
	print("Lyric phrases: %d" % lyric_phrases.size())
