extends SceneTree

const CAPTURE_SIZE := Vector2i(1280, 720)

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
	size = Vector2(1280, 720)
	lane_count = 5
	lane_colors.assign(GUITAR_COLORS)
	_gh_mode = true
	_vfx_quality = "full"
	_adaptive_vfx_reduced = false
	_cached_approach_ms = 1400.0
	_countdown = -1.0
	is_loading = false
	combo = 345
	_combo_glow_color = Color(0.90, 0.20, 0.12, 0.70)
	_arena_combo_energy_display = _arena_combo_energy(combo)
	song_time_ms = 1000.0
	_frame_time_sec = 1.0
	_frame_time_msec = 1000.0
	_rock_meter_mode = "visual"
	_rock_meter_display = 0.88

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
		lane_pressed[lane] = false
		_lane_streak[lane] = 0.0
		held_sustain[lane] = -1
		_sustain_spark_timer[lane] = 0.0

	beat_times = PackedFloat64Array([
		750.0, 1000.0, 1250.0, 1500.0, 1750.0,
		2000.0, 2250.0, 2500.0, 2750.0, 3000.0])
	_beat_idx = 1
	_beat_pulse = 0.70
	notes = [
		{"time_ms": 1320.0, "lane": 0, "duration_ms": 0.0},
		{"time_ms": 1480.0, "lane": 1, "duration_ms": 620.0},
		{"time_ms": 1640.0, "lane": 2, "duration_ms": 0.0},
		{"time_ms": 1800.0, "lane": 3, "duration_ms": 0.0},
		{"time_ms": 1960.0, "lane": 4, "duration_ms": 0.0},
		{"time_ms": 2240.0, "lane": 2, "duration_ms": 0.0},
	]
	note_state = PackedByteArray()
	note_state.resize(notes.size())
	first_visible_idx = 0
	_stage_visible_roles.assign(["guitarist", "vocalist", "drummer", "bassist"])
	_stage_last_event_ms = {
		"guitarist": 980.0,
		"vocalist": 980.0,
		"drummer": 980.0,
		"bassist": 980.0,
	}
	_cache_render_geometry()
	queue_redraw()

func _process(delta: float) -> void:
	song_time_ms += delta * 1000.0
	_frame_time_sec += delta
	_frame_time_msec = _frame_time_sec * 1000.0
	queue_redraw()

func _draw() -> void:
	var vp := Vector2(1280, 720)
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


func _save_frame(path: String) -> void:
	var image := root.get_texture().get_image()
	assert(image != null and not image.is_empty())
	assert(image.get_size() == CAPTURE_SIZE)
	assert(image.save_png(path) == OK)


func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 10:
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path("res://tmp"))
		_save_frame("res://tmp/arena-loop-landscape-a.png")
	if frame_count < 40:
		return false
	_save_frame("res://tmp/arena-loop-landscape-b.png")
	assert(preview._arena_highway_scroll_phase(1000.0) \
		!= preview._arena_highway_scroll_phase(preview.song_time_ms))
	print("ARENA LANDSCAPE LOOP CAPTURE PASS: two song-synchronous frames")
	quit(0)
	return true
