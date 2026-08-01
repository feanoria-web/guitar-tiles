extends SceneTree

const CAPTURE_SIZE := Vector2i(540, 960)

var preview
var frame_count := 0


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(CAPTURE_SIZE)
	root.content_scale_size = CAPTURE_SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = CAPTURE_SIZE

	var preview_script := GDScript.new()
	preview_script.source_code = """
extends "res://scripts/game.gd"

func _ready() -> void:
	size = Vector2(540, 960)
	lane_count = 5
	lane_colors.assign(GUITAR_COLORS)
	_gh_mode = true
	_vfx_quality = "full"
	_adaptive_vfx_reduced = false
	_cached_approach_ms = 1400.0
	_countdown = -1.0
	is_loading = false
	combo = 200
	_combo_glow_color = Color(1.0, 0.55, 0.05, 0.65)
	_arena_combo_energy_display = _arena_combo_energy(combo)
	song_time_ms = 1000.0
	_frame_time_sec = 1.35
	_frame_time_msec = 1350.0
	_rock_meter_mode = "visual"
	_rock_meter_display = 0.88
	_overdrive_active = false

	var old_presentation := Settings.guitar_presentation_mode
	Settings.guitar_presentation_mode = "arena"
	Settings.pixel_stage_enabled = true
	_configure_guitar_visuals()
	Settings.guitar_presentation_mode = old_presentation

	lane_pressed.resize(lane_count)
	_lane_streak.resize(lane_count)
	held_sustain.resize(lane_count)
	_sustain_spark_timer.resize(lane_count)
	for lane in range(lane_count):
		lane_pressed[lane] = lane == 2
		_lane_streak[lane] = 0.72 if lane == 2 else 0.0
		held_sustain[lane] = -1
		_sustain_spark_timer[lane] = 0.0

	beat_times = PackedFloat64Array([0.0, 250.0, 500.0, 750.0, 1000.0, 1250.0, 1500.0, 1750.0, 2000.0, 2250.0])
	_beat_idx = 4
	_beat_pulse = 0.82
	notes = [
		{"time_ms": 1110.0, "lane": 0, "duration_ms": 0.0},
		{"time_ms": 1230.0, "lane": 1, "duration_ms": 640.0},
		{"time_ms": 1360.0, "lane": 2, "duration_ms": 0.0},
		{"time_ms": 1490.0, "lane": 3, "duration_ms": 0.0},
		{"time_ms": 1630.0, "lane": 4, "duration_ms": 780.0},
		{"time_ms": 1810.0, "lane": 2, "duration_ms": 0.0},
		{"time_ms": 2050.0, "lane": 0, "duration_ms": 0.0},
	]
	note_state = PackedByteArray()
	note_state.resize(notes.size())
	for note_index in range(notes.size()):
		note_state[note_index] = 0
	first_visible_idx = 0

	_stage_visible_roles.assign(["guitarist", "vocalist", "drummer", "bassist"])
	_stage_last_event_ms = {
		"guitarist": 960.0,
		"vocalist": 960.0,
		"drummer": 960.0,
		"bassist": 960.0,
	}
	lyric_phrases = [{
		"start_ms": 750.0,
		"end_ms": 1800.0,
		"syllables": [{"time_ms": 760.0}, {"time_ms": 1040.0}, {"time_ms": 1320.0}],
	}]
	current_phrase_idx = 0
	_cache_render_geometry()
	queue_redraw()

func _process(delta: float) -> void:
	_frame_time_sec += delta
	_frame_time_msec = _frame_time_sec * 1000.0
	song_time_ms += delta * 1000.0
	queue_redraw()

func _draw() -> void:
	var vp := Vector2(540, 960)
	draw_polygon(_background_points, _background_colors)
	_draw_starfield(vp)
	_draw_pixel_stage(vp)
	_draw_gh_highway(vp)
"""
	assert(preview_script.reload() == OK)
	preview = preview_script.new()
	preview.position = Vector2.ZERO
	preview.size = Vector2(CAPTURE_SIZE)
	root.add_child(preview)


func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count < 18:
		return false
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Arena capture viewport image is unavailable")
		quit(1)
		return true
	assert(image.get_size() == CAPTURE_SIZE)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://tmp"))
	var output_path := "res://tmp/arena-mode-mobile.png"
	assert(image.save_png(output_path) == OK)
	print("ARENA MODE CAPTURE PASS: ", output_path, " ", image.get_size())
	quit(0)
	return true
