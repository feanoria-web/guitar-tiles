class_name VocalsTrack
extends Control

## Rock Band style vocal pitch highway.
##
## Time runs right to left past a fixed "now" line; vertical position is pitch.
## The pitch axis auto-ranges to the phrase being sung rather than showing a
## fixed two octaves, because a chart that spans D3..D5 over a whole song
## usually only moves a fifth inside any one phrase, and a fixed axis wastes
## most of the height on silence.

const NOW_LINE_RATIO := 0.26        # where "now" sits across the width
const SECONDS_AHEAD := 3.2
const SECONDS_BEHIND := 1.1
const AXIS_PADDING_SEMITONES := 4.0
const AXIS_MIN_SPAN := 10.0
const AXIS_FOLLOW_SPEED := 3.0
const LYRIC_ROW_HEIGHT := 46.0

var notes: Array = []               # from MidiParser.vocal_parts["lead"]
var phrases: Array = []             # from MidiParser.vocal_phrases
var song_time_ms: float = 0.0
var detected_midi: float = -1.0     # live sung pitch, -1 when unvoiced
var detected_voiced: bool = false
## Per-note hit fraction, index-aligned with `notes`. Filled by scoring later.
var note_progress: PackedFloat32Array = PackedFloat32Array()

var _axis_low := 52.0
var _axis_high := 68.0
var _axis_ready := false


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_update_axis(delta)
	queue_redraw()


## Keeps the visible pitch range centred on what is actually being sung soon.
func _update_axis(delta: float) -> void:
	var low := INF
	var high := -INF
	var from_ms := song_time_ms - SECONDS_BEHIND * 1000.0
	var to_ms := song_time_ms + SECONDS_AHEAD * 1000.0
	for note in notes:
		if float(note["end_ms"]) < from_ms or float(note["time_ms"]) > to_ms:
			continue
		if bool(note["non_pitched"]):
			continue
		var pitch := float(note["midi_note"])
		low = minf(low, pitch)
		high = maxf(high, pitch)
	if low == INF:
		return
	low -= AXIS_PADDING_SEMITONES
	high += AXIS_PADDING_SEMITONES
	if high - low < AXIS_MIN_SPAN:
		var centre := (low + high) * 0.5
		low = centre - AXIS_MIN_SPAN * 0.5
		high = centre + AXIS_MIN_SPAN * 0.5
	if not _axis_ready:
		_axis_low = low
		_axis_high = high
		_axis_ready = true
		return
	# Ease rather than snap, or the whole board jumps between phrases.
	var follow := clampf(delta * AXIS_FOLLOW_SPEED, 0.0, 1.0)
	_axis_low = lerpf(_axis_low, low, follow)
	_axis_high = lerpf(_axis_high, high, follow)


func _time_to_x(time_ms: float) -> float:
	var now_x := size.x * NOW_LINE_RATIO
	var pixels_per_ms := (size.x - now_x) / (SECONDS_AHEAD * 1000.0)
	return now_x + (time_ms - song_time_ms) * pixels_per_ms


func _pitch_to_y(midi: float) -> float:
	var span := maxf(_axis_high - _axis_low, 1.0)
	var norm := clampf((midi - _axis_low) / span, -0.15, 1.15)
	var top := 24.0
	var usable := maxf(size.y - LYRIC_ROW_HEIGHT - top - 12.0, 40.0)
	return top + usable * (1.0 - norm)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var now_x := size.x * NOW_LINE_RATIO
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.055, 0.08))

	_draw_pitch_grid(font)
	_draw_phrase_bands()
	_draw_notes(font)
	_draw_now_line(now_x)
	_draw_singer_cursor(now_x)


func _draw_pitch_grid(font: Font) -> void:
	# One line per octave C, labelled. Enough to read the register without
	# turning the board into graph paper.
	var midi: float = ceil(_axis_low / 12.0) * 12.0
	while midi <= _axis_high:
		var y := _pitch_to_y(midi)
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.16, 0.17, 0.22), 1.0)
		draw_string(font, Vector2(6, y - 4), PitchDetector.midi_note_name(midi),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.34, 0.36, 0.44))
		midi += 12.0


func _draw_phrase_bands() -> void:
	var lyric_top := size.y - LYRIC_ROW_HEIGHT
	for phrase in phrases:
		var start_x := _time_to_x(float(phrase["start_ms"]))
		var end_x := _time_to_x(float(phrase["end_ms"]))
		if end_x < -40.0 or start_x > size.x + 40.0:
			continue
		var tint := (
			Color(0.35, 0.75, 1.0, 0.10) if bool(phrase["overdrive"])
			else Color(1.0, 1.0, 1.0, 0.028))
		draw_rect(Rect2(start_x, 8.0, end_x - start_x, lyric_top - 8.0), tint)
		draw_line(Vector2(start_x, 8.0), Vector2(start_x, lyric_top),
			Color(0.35, 0.38, 0.48, 0.5), 1.0)


func _draw_notes(font: Font) -> void:
	var lyric_y := size.y - LYRIC_ROW_HEIGHT + 30.0
	# Syllables sung close together would otherwise print on top of each other.
	var lyric_right_edge := -INF
	for index in range(notes.size()):
		var note: Dictionary = notes[index]
		var start_x := _time_to_x(float(note["time_ms"]))
		var end_x := _time_to_x(float(note["end_ms"]))
		if end_x < -60.0 or start_x > size.x + 60.0:
			continue
		var is_talkie := bool(note["non_pitched"])
		var tube_h := 13.0
		var y := _pitch_to_y(float(note["midi_note"]))
		var width := maxf(end_x - start_x, 4.0)
		var progress := 0.0
		if index < note_progress.size():
			progress = clampf(note_progress[index], 0.0, 1.0)

		if is_talkie:
			# Non-pitched: any pitch counts, so it is drawn as a band rather
			# than sitting at a height the singer is not being asked to hit.
			var band := Rect2(start_x, _pitch_to_y(_axis_high) + 6.0,
				width, _pitch_to_y(_axis_low) - _pitch_to_y(_axis_high) - 12.0)
			draw_rect(band, Color(0.55, 0.55, 0.62, 0.13))
			draw_rect(band, Color(0.7, 0.7, 0.8, 0.35), false, 1.0)
		else:
			var base := Color(0.30, 0.34, 0.44)
			draw_rect(Rect2(start_x, y - tube_h * 0.5, width, tube_h), base)
			if progress > 0.0:
				draw_rect(
					Rect2(start_x, y - tube_h * 0.5, width * progress, tube_h),
					Color(0.35, 0.95, 0.55))
			draw_rect(Rect2(start_x, y - tube_h * 0.5, width, tube_h),
				Color(0.62, 0.68, 0.82, 0.55), false, 1.0)

		# Slides carry the previous syllable's word, so they get no lyric of
		# their own; drawing one would show a stray empty box.
		var text := String(note["text"])
		if text == "" or bool(note["hidden"]):
			continue
		var text_width := font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		# Centre the syllable on its note. Anchoring to the note's left edge
		# made a long note's word reach the now line well before the note body
		# did, so the lyrics read as running ahead of the melody.
		var text_x := start_x + (maxf(end_x - start_x, 0.0) - text_width) * 0.5
		if text_x < lyric_right_edge:
			# Nudge right off the previous syllable; if that pushes it clear of
			# its own note it is a dense run, so drop it rather than mislead.
			text_x = lyric_right_edge
			if text_x > end_x + 14.0:
				continue
		draw_string(font, Vector2(text_x, lyric_y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.88, 0.90, 0.96))
		lyric_right_edge = text_x + text_width + 7.0


func _draw_now_line(now_x: float) -> void:
	draw_line(Vector2(now_x, 0.0), Vector2(now_x, size.y - LYRIC_ROW_HEIGHT),
		Color(1.0, 1.0, 1.0, 0.30), 2.0)


func _draw_singer_cursor(now_x: float) -> void:
	if not detected_voiced or detected_midi < 0.0:
		return
	# Fold the sung pitch into the displayed octave. A bass singing the line an
	# octave down should see the cursor on the notes, not off the bottom.
	var folded := detected_midi
	var centre := (_axis_low + _axis_high) * 0.5
	while folded < centre - 6.0:
		folded += 12.0
	while folded > centre + 6.0:
		folded -= 12.0
	var y := _pitch_to_y(folded)
	var arrow := PackedVector2Array([
		Vector2(now_x - 20.0, y - 9.0),
		Vector2(now_x - 2.0, y),
		Vector2(now_x - 20.0, y + 9.0)])
	draw_colored_polygon(arrow, Color(1.0, 0.85, 0.25))
	draw_line(Vector2(now_x - 20.0, y), Vector2(0.0, y),
		Color(1.0, 0.85, 0.25, 0.35), 2.0)
