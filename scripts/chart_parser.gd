class_name ChartParser
extends RefCounted

const DIFFICULTIES := ["Easy", "Medium", "Hard", "Expert"]

# Instrument -> chart section suffix mapping
const INSTRUMENT_SUFFIXES := {
	"guitar": "Single",
	"bass": "DoubleBass",
	"keys": "Keyboard",
	"drums": "Drums",
}
const INSTRUMENT_DISPLAY := {
	"guitar": "Gitar",
	"bass": "Bas",
	"keys": "Klavye",
	"drums": "Davul",
}

var resolution: int = 480
var audio_offset_sec: float = 0.0  # from [Song] Offset field (seconds)
var bpm_events: Array = []   # [{tick, bpm}]
var notes: Array = []        # [{time_ms, lane, duration_ms}]
var lyrics: Array = []       # [{time_ms, text}]
var lyric_phrases: Array = [] # [{start_ms, end_ms, text, syllables: [{time_ms, char_start, char_end}]}]
var overdrive_phrases: Array = [] # [{start_ms, end_ms}]
var solo_sections: Array = [] # [{start_ms, end_ms}]

var _sections: Dictionary = {}

func parse_file(path: String, difficulty: String = "Expert", instrument: String = "guitar") -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ChartParser: cannot open %s" % path)
		return false
	var text := file.get_as_text()
	file.close()
	return parse_text(text, difficulty, instrument)

func parse_text(text: String, difficulty: String = "Expert", instrument: String = "guitar") -> bool:
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

	var suffix: String = INSTRUMENT_SUFFIXES.get(instrument, "Single")
	var section_name: String = difficulty + suffix
	if _sections.has(section_name):
		_parse_notes(_sections[section_name])
	else:
		push_error("ChartParser: no [%s] found" % section_name)
		return false

	if _sections.has("Events"):
		_parse_events(_sections["Events"])

	return true

func get_available_difficulties(instrument: String = "guitar") -> Array[String]:
	var suffix: String = INSTRUMENT_SUFFIXES.get(instrument, "Single")
	var result: Array[String] = []
	for diff in DIFFICULTIES:
		if _sections.has(diff + suffix):
			result.append(diff)
	return result

## Returns {instrument_key: [difficulties]} for all instruments that have notes.
## e.g. {"guitar": ["Easy","Hard","Expert"], "bass": ["Expert"]}
func get_available_instruments() -> Dictionary:
	var result := {}
	for inst_key in INSTRUMENT_SUFFIXES:
		var suffix: String = INSTRUMENT_SUFFIXES[inst_key]
		var diffs: Array[String] = []
		for diff in DIFFICULTIES:
			var section_name: String = diff + suffix
			if _sections.has(section_name):
				# Check section actually has note lines (N events)
				var lines: Array = _sections[section_name]
				var has_notes := false
				for line in lines:
					if (line as String).strip_edges().find("= N ") >= 0:
						has_notes = true
						break
				if has_notes:
					diffs.append(diff)
		if diffs.size() > 0:
			result[inst_key] = diffs
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

## Returns {instrument_key: [difficulties]} scanning from file path.
static func scan_instruments_from_file(path: String) -> Dictionary:
	var parser := ChartParser.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	parser._sections = parser._split_sections(text)
	return parser.get_available_instruments()

## Returns {instrument_key: [difficulties]} scanning from text.
static func scan_instruments_from_text(text: String) -> Dictionary:
	var parser := ChartParser.new()
	parser._sections = parser._split_sections(text)
	return parser.get_available_instruments()

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
			elif key == "Offset":
				audio_offset_sec = float(val)
				print("ChartParser: Offset = %.3f sec" % audio_offset_sec)

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
	var solo_start_tick := -1
	var last_event_tick := 0
	for line in lines:
		var parts := (line as String).split("=", true, 1)
		if parts.size() != 2:
			continue
		var tick := int(parts[0].strip_edges())
		var rest := parts[1].strip_edges()
		last_event_tick = maxi(last_event_tick, tick)
		if rest.begins_with("S "):
			var special_tokens := rest.split(" ", false)
			if special_tokens.size() >= 3 and int(special_tokens[1]) == 2:
				var special_dur := maxi(0, int(special_tokens[2]))
				overdrive_phrases.append({
					"start_ms": _tick_to_ms(tick),
					"end_ms": _tick_to_ms(tick + special_dur),
				})
			continue
		if rest.begins_with("E "):
			var marker := rest.substr(2).strip_edges().trim_prefix("\"").trim_suffix("\"").to_lower()
			if marker in ["solo", "solo_on", "solo_start"]:
				solo_start_tick = tick
			elif marker in ["soloend", "solo_off", "solo_end"] and solo_start_tick >= 0:
				solo_sections.append({
					"start_ms": _tick_to_ms(solo_start_tick),
					"end_ms": _tick_to_ms(tick),
				})
				solo_start_tick = -1
			continue
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
		last_event_tick = maxi(last_event_tick, tick + dur)

	if solo_start_tick >= 0 and last_event_tick > solo_start_tick:
		solo_sections.append({
			"start_ms": _tick_to_ms(solo_start_tick),
			"end_ms": _tick_to_ms(last_event_tick),
		})

func _parse_events(lines: Array) -> void:
	var phrase_start_ms := -1.0
	var phrase_syllables: Array = []
	var has_phrase_markers := false
	var orphan_lyrics: Array = []  # lyrics outside phrase boundaries
	var italic_depth := 0  # <i> nesting carried across syllables

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
			has_phrase_markers = true
			# Flush previous phrase if it had lyrics (handles missing phrase_end)
			if phrase_syllables.size() > 0:
				var built := _build_phrase_with_positions(phrase_syllables)
				var end_ms := _tick_to_ms(tick)
				lyric_phrases.append({
					"start_ms": phrase_syllables[0]["time_ms"],
					"end_ms": end_ms,
					"text": built["text"],
					"syllables": built["syllables"],
					"italic_ranges": built["italic_ranges"],
				})
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
					"italic_ranges": built["italic_ranges"],
				})
			phrase_start_ms = -1.0
			phrase_syllables.clear()
		elif content.begins_with("lyric "):
			var lyric_text := content.substr(6)
			# Skip section/mood tags like [idle], [intense], etc.
			if lyric_text.begins_with("[") and lyric_text.ends_with("]"):
				continue
			# Strip rich-text tags (<i> etc.), keep italic = background vocal flag
			var tag_res := strip_rich_tags(lyric_text, italic_depth)
			italic_depth = tag_res["depth"]
			# Clean Clone Hero lyric markers
			lyric_text = _clean_lyric_text(tag_res["text"])
			if lyric_text == "" or lyric_text == "#":
				continue
			var time_ms := _tick_to_ms(tick)
			var is_italic: bool = tag_res["italic"]
			lyrics.append({"time_ms": time_ms, "text": lyric_text})
			if phrase_start_ms >= 0:
				phrase_syllables.append({"time_ms": time_ms, "text": lyric_text, "italic": is_italic})
			else:
				orphan_lyrics.append({"time_ms": time_ms, "text": lyric_text, "italic": is_italic})

	# Flush any unclosed phrase
	if phrase_syllables.size() > 0:
		var built := _build_phrase_with_positions(phrase_syllables)
		lyric_phrases.append({
			"start_ms": phrase_syllables[0]["time_ms"],
			"end_ms": float(phrase_syllables[phrase_syllables.size() - 1]["time_ms"]) + 3000.0,
			"text": built["text"],
			"syllables": built["syllables"],
			"italic_ranges": built["italic_ranges"],
		})

	# If no phrase markers existed, group all lyrics by gap (like MIDI parser)
	if not has_phrase_markers and orphan_lyrics.size() > 0:
		_build_phrases_from_gap(orphan_lyrics)
	elif orphan_lyrics.size() > 0 and lyric_phrases.is_empty():
		# Phrase markers existed but all lyrics fell outside them
		_build_phrases_from_gap(orphan_lyrics)

func _build_phrases_from_gap(raw_lyrics: Array) -> void:
	var phrase_syllables: Array = []
	var phrase_gap_ms := 2000.0
	for lyr in raw_lyrics:
		if phrase_syllables.size() > 0:
			var last_time: float = phrase_syllables[phrase_syllables.size() - 1]["time_ms"]
			if float(lyr["time_ms"]) - last_time > phrase_gap_ms:
				_finalize_gap_phrase(phrase_syllables)
				phrase_syllables.clear()
		phrase_syllables.append(lyr)
	if phrase_syllables.size() > 0:
		_finalize_gap_phrase(phrase_syllables)

func _finalize_gap_phrase(syllables: Array) -> void:
	if syllables.is_empty():
		return
	var built := _build_phrase_with_positions(syllables)
	lyric_phrases.append({
		"start_ms": float(syllables[0]["time_ms"]),
		"end_ms": float(syllables[syllables.size() - 1]["time_ms"]) + 3000.0,
		"text": built["text"],
		"syllables": built["syllables"],
		"italic_ranges": built["italic_ranges"],
	})

# Strips TextMeshPro rich-text tags (<i>, </i>, <b>, <color=...> etc.) that
# Clone Hero charts embed in lyrics. <i>...</i> conventionally marks spoken /
# background vocals, so the italic state is tracked and returned — the game
# renders those spans faint. `depth` carries italic nesting across syllables.
# Returns {text, italic, depth}.
static func strip_rich_tags(text: String, depth: int) -> Dictionary:
	if text.find("<") < 0 and depth == 0:
		return {"text": text, "italic": false, "depth": depth}
	# Syllable counts as italic if ANY part of it was inside <i>...</i>
	# (covers tags fully enclosed within one syllable, e.g. "<i>Whoa</i>")
	var saw_italic := depth > 0
	var out := ""
	var i := 0
	while i < text.length():
		if text[i] == "<":
			var close := text.find(">", i)
			if close > i:
				var tag := text.substr(i + 1, close - i - 1).to_lower().strip_edges()
				if tag == "i":
					depth += 1
					saw_italic = true
				elif tag == "/i":
					depth = maxi(0, depth - 1)
				# All other tags (b, color=..., size=...) are just stripped
				i = close + 1
				continue
		out += text[i]
		i += 1
	return {"text": out, "italic": saw_italic, "depth": depth}

func _clean_lyric_text(text: String) -> String:
	# Strip Clone Hero markers: ^=pitch shift, #=breath, various punctuation markers
	text = text.strip_edges()
	# Remove leading markers
	while text.length() > 0 and text[0] in ["^", "#", "§", "=", "$"]:
		text = text.substr(1)
	# Remove trailing markers (but keep hyphens — they indicate syllable continuation)
	while text.length() > 0 and text[text.length() - 1] in ["^", "#", "§", "=", "$"]:
		text = text.substr(0, text.length() - 1)
	return text.strip_edges()

func _build_phrase_with_positions(syllables: Array) -> Dictionary:
	var result := ""
	var positions: Array = []  # [{time_ms, char_start, char_end}]
	var italic_ranges: Array = []  # [[char_start, char_end], ...] — background vocals

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
		if syl.get("italic", false) and char_end > char_start:
			italic_ranges.append([char_start, char_end])

		if has_hyphen:
			result += "-"

	# Clean any trailing hyphen
	if result.ends_with("-"):
		result = result.substr(0, result.length() - 1)

	return {"text": result, "syllables": positions, "italic_ranges": italic_ranges}

func print_summary() -> void:
	print("=== Chart Parser Summary ===")
	print("Resolution: %d" % resolution)
	print("BPM events: %d" % bpm_events.size())
	print("Total notes: %d" % notes.size())
	print("Total lyrics: %d" % lyrics.size())
	print("Lyric phrases: %d" % lyric_phrases.size())
