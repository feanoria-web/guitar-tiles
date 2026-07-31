extends Control

## On-screen readout for VocalInput. Walks the user through a short guided
## routine and draws what the detector is hearing, so pitch detection can be
## judged by eye and ear before any of it is wired into gameplay.

const TRACE_SECONDS := 6.0
const TRACE_MIDI_LOW := 36.0
const TRACE_MIDI_HIGH := 84.0

# label, seconds, wants_voice
const STEPS := [
	["Sessiz kal", 3.0, false],
	["Rahat bir notada uzun  A A A A", 6.0, true],
	["Sus", 2.5, false],
	["PES bir  A A A A", 6.0, true],
	["Sus", 2.5, false],
	["TIZ bir  A A A A", 6.0, true],
	["Sus", 2.5, false],
	["Pesten tize kaydir  A A A A", 6.0, true],
	["Bitti - tesekkurler", 3.0, false],
]

var vocal_input: VocalInput = null

var _step := 0
var _step_elapsed := 0.0
var _trace: Array = []          # [{t, midi}]
var _elapsed := 0.0
var _step_voiced := 0
var _step_frames := 0
# Per-step, so a step's numbers are not contaminated by the one before it.
var _step_midis: Array = []
var _step_level_sum := 0.0
var _step_level_peak := 0.0
var _results: Array = []        # per step: {label, voiced_pct, median_midi}
var _finished := false


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	if _finished:
		return
	var pitch := vocal_input.get_pitch()
	var voiced := bool(pitch["voiced"])
	var level := vocal_input.get_input_level()
	_step_frames += 1
	_step_level_sum += level
	_step_level_peak = maxf(_step_level_peak, level)
	if voiced:
		_step_voiced += 1
		_step_midis.append(float(pitch["midi"]))
		_trace.append({"t": _elapsed, "midi": float(pitch["midi"])})
	while _trace.size() > 0 and _elapsed - float(_trace[0]["t"]) > TRACE_SECONDS:
		_trace.pop_front()

	_step_elapsed += delta
	if _step_elapsed >= float(STEPS[_step][1]):
		_record_step()
		_step += 1
		_step_elapsed = 0.0
		_step_voiced = 0
		_step_frames = 0
		_step_midis.clear()
		_step_level_sum = 0.0
		_step_level_peak = 0.0
		if _step >= STEPS.size():
			_finished = true
			_print_summary()
	queue_redraw()


func _record_step() -> void:
	var pitches := _step_midis.duplicate()
	pitches.sort()
	var median := -1.0
	if pitches.size() > 0:
		median = float(pitches[pitches.size() / 2])
	# Spread tells a held note apart from the detector wandering.
	var spread := 0.0
	if pitches.size() >= 4:
		spread = float(pitches[int(pitches.size() * 0.9)]) \
			- float(pitches[int(pitches.size() * 0.1)])
	_results.append({
		"label": String(STEPS[_step][0]),
		"wants_voice": bool(STEPS[_step][2]),
		"voiced_pct": 100.0 * float(_step_voiced) / float(maxi(_step_frames, 1)),
		"median_midi": median,
		"spread": spread,
		"level_avg": _step_level_sum / float(maxi(_step_frames, 1)),
		"level_peak": _step_level_peak,
	})


func _print_summary() -> void:
	print("\n--- summary ---")
	print("%-32s %7s %8s %8s %7s %7s" % [
		"step", "voiced", "median", "spread", "lvl.avg", "lvl.pk"])
	for entry in _results:
		var median := float(entry["median_midi"])
		print("%-32s %6.1f%% %8s %7.1fst %7.4f %7.4f" % [
			entry["label"], float(entry["voiced_pct"]),
			PitchDetector.midi_note_name(median) if median > 0.0 else "--",
			float(entry["spread"]),
			float(entry["level_avg"]), float(entry["level_peak"])])
	print("---------------")


func is_finished() -> bool:
	return _finished


func _draw() -> void:
	var vp := size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.06, 0.06, 0.09))
	var font := ThemeDB.fallback_font
	var pitch := vocal_input.get_pitch()
	var voiced := bool(pitch["voiced"])
	var level := vocal_input.get_input_level()

	# --- Current instruction + countdown ---
	var step_label := "Bitti"
	var step_total := 1.0
	if _step < STEPS.size():
		step_label = String(STEPS[_step][0])
		step_total = float(STEPS[_step][1])
	# Live "am I doing this right" feedback. Without it there is no way to tell
	# a bad take from a bad detector until the run is already over.
	var wants_voice := _step < STEPS.size() and bool(STEPS[_step][2])
	if wants_voice:
		var border := Color(0.25, 0.85, 0.45) if voiced else Color(0.85, 0.35, 0.3)
		draw_rect(Rect2(Vector2.ZERO, vp), border, false, 6.0)
		draw_string(font, Vector2(24, 96),
			"algilaniyor" if voiced else "SES YOK - daha yuksek sesle",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, border)
	draw_string(font, Vector2(24, 46), step_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1))
	var remaining := maxf(0.0, step_total - _step_elapsed)
	draw_string(font, Vector2(vp.x - 90, 46), "%.0fs" % ceil(remaining),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.6, 0.65, 0.75))
	var bar_w := vp.x - 48
	draw_rect(Rect2(24, 60, bar_w, 6), Color(0.16, 0.17, 0.22))
	draw_rect(
		Rect2(24, 60, bar_w * clampf(_step_elapsed / step_total, 0.0, 1.0), 6),
		Color(0.35, 0.75, 1.0))

	# --- Big note readout ---
	var note_text := PitchDetector.midi_note_name(
		float(pitch["midi"])) if voiced else "--"
	var note_color := Color(0.4, 1.0, 0.6) if voiced else Color(0.35, 0.36, 0.42)
	draw_string(font, Vector2(24, 190), note_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 110, note_color)
	if voiced:
		draw_string(font, Vector2(24, 232),
			"%.1f Hz" % float(pitch["hz"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.7, 0.75, 0.85))

	# --- Meters. Level answers "did sound arrive", clarity answers "was it a
	# pitch". Keeping them apart is the whole point of this screen. ---
	_draw_meter(font, 268, "Mikrofon", clampf(level * 6.0, 0.0, 1.0),
		Color(0.95, 0.75, 0.25), "%.3f" % level)
	_draw_meter(font, 322, "Netlik", clampf(float(pitch["clarity"]), 0.0, 1.0),
		Color(0.45, 0.85, 1.0), "%.2f" % float(pitch["clarity"]))
	if level < 0.004:
		draw_string(font, Vector2(24, 380),
			"Mikrofona ses gelmiyor - Windows giris cihazini kontrol et",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1.0, 0.45, 0.4))

	# --- Pitch trace ---
	var graph_top := 410.0
	var graph_h := maxf(120.0, vp.y - graph_top - 40.0)
	draw_rect(Rect2(24, graph_top, bar_w, graph_h), Color(0.09, 0.09, 0.13))
	# Octave gridlines, labelled.
	var midi_value := TRACE_MIDI_LOW
	while midi_value <= TRACE_MIDI_HIGH:
		var line_y := graph_top + graph_h * (
			1.0 - (midi_value - TRACE_MIDI_LOW)
			/ (TRACE_MIDI_HIGH - TRACE_MIDI_LOW))
		draw_line(Vector2(24, line_y), Vector2(24 + bar_w, line_y),
			Color(0.2, 0.21, 0.27), 1.0)
		draw_string(font, Vector2(28, line_y - 4),
			PitchDetector.midi_note_name(midi_value),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.42, 0.5))
		midi_value += 12.0
	var previous := Vector2.INF
	for entry in _trace:
		var age := _elapsed - float(entry["t"])
		var x := 24.0 + bar_w * (1.0 - age / TRACE_SECONDS)
		var norm := clampf(
			(float(entry["midi"]) - TRACE_MIDI_LOW)
			/ (TRACE_MIDI_HIGH - TRACE_MIDI_LOW), 0.0, 1.0)
		var point := Vector2(x, graph_top + graph_h * (1.0 - norm))
		if previous != Vector2.INF and absf(point.x - previous.x) < 30.0:
			draw_line(previous, point, Color(0.4, 1.0, 0.6), 2.5, true)
		draw_circle(point, 2.0, Color(0.6, 1.0, 0.75))
		previous = point


func _draw_meter(font: Font, y: float, label: String, value: float,
		color: Color, readout: String) -> void:
	var bar_w := size.x - 48
	draw_string(font, Vector2(24, y - 6), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.65, 0.68, 0.78))
	draw_string(font, Vector2(24 + bar_w - 70, y - 6), readout,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.5, 0.53, 0.62))
	draw_rect(Rect2(24, y, bar_w, 22), Color(0.13, 0.14, 0.18))
	draw_rect(Rect2(24, y, bar_w * value, 22), color)
