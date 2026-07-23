extends Control

const ChartParserScript = preload("res://scripts/chart_parser.gd")
const MidiParserScript = preload("res://scripts/midi_parser.gd")
const SngLoaderScript = preload("res://scripts/sng_loader.gd")
const PlayabilityScript = preload("res://scripts/playability.gd")
const StfsParserScript = preload("res://scripts/stfs_parser.gd")
const MoggHandlerScript = preload("res://scripts/mogg_handler.gd")

# --- Config ---
const HIT_WINDOW_MS := 200.0
const HIT_LINGER_MS := 1200.0
const ASSIST_CLUSTER_MIN_MS := 260.0
const ASSIST_CLUSTER_MAX_MS := 420.0
const ASSIST_HIT_WINDOW_MS := 260.0
const ASSIST_GOOD_ZONE_SCALE := 1.18

# Spatial touch judgment. The visible colored button is Perfect; the nearby
# area in the same lane is Good. Touches farther away do not hit the note.
const FLAT_GOOD_ZONE_HALF_HEIGHT_RATIO := 0.90
const GH_GOOD_ZONE_HALF_HEIGHT_RATIO := 1.05
const FLAT_GOOD_EDGE_PADDING_RATIO := 0.14
const GH_GOOD_EDGE_PADDING_RATIO := 0.24
const FLAT_HIT_ZONE_HEIGHT_RATIO := 1.05
const FLAT_HIT_ZONE_MARGIN_RATIO := 0.02
const FLAT_NOTE_MARGIN_RATIO := 0.03
const PERFECT_SCORE_FACTOR := 1.0
const GOOD_SCORE_FACTOR := 0.5
const BASE_HIT_SCORE := 50.0
const BASE_SUSTAIN_SCORE := 25.0

# Rock Meter balance. Values are normalized (0.0 = failed, 1.0 = full).
# Miss damage is per note, so it stays moderate for multi-note chords.
const ROCK_METER_START := 0.75
const ROCK_METER_GREEN_THRESHOLD := 0.55
const ROCK_METER_DANGER_THRESHOLD := 0.25
const ROCK_METER_PERFECT_GAIN := 0.012
const ROCK_METER_GOOD_GAIN := 0.006
const ROCK_METER_SUSTAIN_GAIN := 0.008
const ROCK_METER_MISS_LOSS := 0.022
const ROCK_METER_WRONG_TAP_LOSS := 0.010
const ROCK_METER_EARLY_RELEASE_LOSS := 0.012
# Android touch-up can arrive while song_time_ms still reflects the previous
# audio frame. A generous tail grace keeps visually completed holds successful.
const ROCK_METER_SUSTAIN_END_GRACE_MS := 280.0

# Overdrive: a full meter lasts 20 seconds. Half a meter is enough to start,
# matching the familiar rhythm-game risk/reward rhythm without a tilt gesture.
const OVERDRIVE_ACTIVATION_MIN := 0.50
const OVERDRIVE_DRAIN_PER_SEC := 0.05
const OVERDRIVE_PHRASE_GAIN := 0.25
const OVERDRIVE_SCORE_MULTIPLIER := 2.0
const ENDING_CROWD_LEAD_SEC := 8.0
const ENDING_STRONG_THRESHOLD := 0.72
const CROWD_REACTION_COOLDOWN_SEC := 10.0
const CROWD_MISTAKES_BEFORE_BOO := 6
const CROWD_PERFECTS_PER_MISTAKE_RECOVERY := 5
const CROWD_CHEER_REACTION_DB := 2.0
const CROWD_BOO_REACTION_DB := -7.0
const CROWD_BURST_LAYER_DB := -10.0
const CROWD_REACTION_FADE_IN_SEC := 0.30
const CROWD_REACTION_FADE_OUT_SEC := 0.70
const CROWD_REACTION_FADE_RANGE_DB := 24.0
const MUSIC_BUS_GAIN_DB := 4.0
const MISS_SFX_MUSIC_DUCK_DB := 6.0
const MISS_SFX_DUCK_HOLD_SEC := 0.10
const MISS_SFX_DUCK_RECOVERY_SEC := 0.55
const CROWD_BUS_GAIN_DB := -5.0
const SFX_BUS_GAIN_DB := -2.0
const CROWD_AMBIENCE_PATHS := [
	"res://assets/audio/crowd/crowd_ambience.mp3",
	"res://assets/audio/crowd/crowd_ambience_3.mp3",
]
const CROWD_CHEER_PATHS := [
	"res://assets/audio/crowd/crowd_cheer.mp3",
	"res://assets/audio/crowd/crowd_cheer_2.mp3",
]
const CROWD_BOO_PATHS := [
	"res://assets/audio/crowd/crowd_boo.mp3",
	"res://assets/audio/crowd/crowd_boo_2.mp3",
	"res://assets/audio/crowd/crowd_boo_3.mp3",
]
const CROWD_APPLAUSE_STRONG_PATH := "res://assets/audio/crowd/crowd_applause_strong.mp3"
const CROWD_APPLAUSE_LIGHT_PATH := "res://assets/audio/crowd/crowd_applause_light.mp3"
const MISS_SFX_PATH := "res://assets/audio/sfx/guitar_miss.mp3"

# Portrait-only gameplay layout.
const LAYOUT := {
	"highway_ratio": 1.0,
	"hit_line_ratio": 0.82,
	"note_h_ratio": 0.65,
	"approach_default": 1.4,
}

const GUITAR_COLORS: Array[Color] = [
	Color(0.18, 0.85, 0.18),  Color(0.9, 0.15, 0.15),
	Color(0.9, 0.85, 0.1),    Color(0.25, 0.5, 1.0),
	Color(1.0, 0.55, 0.05),
]
const PIANO_COLORS: Array[Color] = [
	Color(0.18, 0.85, 0.18),  Color(0.9, 0.15, 0.15),
	Color(0.9, 0.85, 0.1),    Color(0.35, 0.55, 1.0),
]
const BG_COLOR := UITheme.BG_BOTTOM
const BG_COLOR_TOP := UITheme.BG_TOP
const LANE_BG := Color(0.10, 0.09, 0.17, 0.45)
const LANE_BORDER := Color(0.35, 0.30, 0.60, 0.30)
const HIT_LINE_COLOR := Color(UITheme.NEON_CYAN.r, UITheme.NEON_CYAN.g, UITheme.NEON_CYAN.b, 0.75)


# Note states: 0=active, 1=hit(darkened,scrolling), 2=missed, 3=sustain_holding
var notes: Array = []
var lyric_phrases: Array = []
var overdrive_phrases: Array = []
var solo_sections: Array = []
var note_state: PackedByteArray = PackedByteArray()
var _assist_clusters: Dictionary = {} # cluster id -> Array[int]
var score: int = 0
var combo: int = 0
var max_combo: int = 0
var audio_offset_ms: float = 0.0
var song_started: bool = false
var song_time_ms: float = 0.0
var first_visible_idx: int = 0
var current_phrase_idx: int = 0
var lane_count: int = 5
var lane_colors: Array[Color] = []
var _start_ticks: int = 0
var _first_hit_logged: bool = false
var _play_call_time_ms: int = 0
var _hit_log_count: int = 0
var _chart_offset_ms: float = 0.0

var _countdown: float = -1.0

# Pause state
var _paused: bool = false
var _pause_layer: CanvasLayer = null

# --- GH pseudo-3D highway ---
var _gh_mode: bool = true
const GH_TOP_SCALE := 0.36          # highway width at horizon relative to bottom
const GH_VANISH_Y_RATIO := -0.10    # vanishing point (relative to viewport height, above top)
const GH_NOTE_FRET_RADIUS_RATIO := 0.42
const GH_HIT_FRET_RADIUS_RATIO := 0.50
const GH_HIT_PAD_HEIGHT_RATIO := 0.82
const GH_HIT_PAD_MARGIN_RATIO := 0.04

# Beat lines (from tempo map)
var beat_times: PackedFloat64Array = PackedFloat64Array()
var _beat_idx: int = 0
var _beat_pulse: float = 0.0

# Hit particles [{pos, vel, color, life, max_life, size}]
var _particles: Array = []

# Lane press streak alphas (0..1 per lane, fades after release)
var _lane_streak: Array = []

# Sustain hold spark timers (per lane, spawns sparks while holding)
var _sustain_spark_timer: Array = []

# Sprite FX one-shots: [{name, pos, h, mod, t, rot}]
var _sprite_fx: Array = []

# Procedural lightning bolts: [{pts, life, max_life, col}]
var _bolts: Array = []
var _ambient_bolt_timer: float = 0.0
var _vfx_quality: String = "balanced"
var _adaptive_vfx_reduced: bool = false
var _low_fps_time: float = 0.0
var _fps_recovery_time: float = 0.0
var _frame_time_sec: float = 0.0
var _frame_time_msec: float = 0.0
var _frame_viewport_size: Vector2 = Vector2.ZERO

# Static viewport geometry used by CanvasItem drawing. Rebuilt only when the
# portrait viewport changes instead of allocating packed arrays every frame.
var _background_points := PackedVector2Array()
var _background_colors := PackedColorArray([BG_COLOR_TOP, BG_COLOR_TOP, BG_COLOR, BG_COLOR])
var _vignette_left_points := PackedVector2Array()
var _vignette_right_points := PackedVector2Array()
var _vignette_left_colors := PackedColorArray()
var _vignette_right_colors := PackedColorArray()
var _spawn_fade_points := PackedVector2Array()
var _spawn_fade_colors := PackedColorArray()
var _cached_lane_width: float = 0.0
var _cached_lanes_start_x: float = 0.0
var _cached_hit_line_y: float = 0.0
var _cached_note_height: float = 0.0
var _cached_gh_vanish_y: float = 0.0
var _cached_approach_ms: float = 1400.0
var _gh_surface_points := PackedVector2Array()
var _gh_surface_colors := PackedColorArray([
	Color(0.045, 0.04, 0.10, 0.92), Color(0.045, 0.04, 0.10, 0.92),
	Color(0.085, 0.075, 0.16, 0.96), Color(0.085, 0.075, 0.16, 0.96)])
var _gh_combo_left_points := PackedVector2Array()
var _gh_combo_right_points := PackedVector2Array()

# Per-lane note skin textures (flat mode tiles)
var note_tex: Array = []

# Starfield uses packed numeric arrays rather than per-star Dictionaries in the
# render loop.
var _star_x := PackedFloat32Array()
var _star_y := PackedFloat32Array()
var _star_size := PackedFloat32Array()
var _star_speed := PackedFloat32Array()
var _star_phase := PackedFloat32Array()

# Pre-mix cache directory
const MIX_CACHE_DIR := "user://cache"

# Sustain hold tracking
var lane_pressed: Array = []   # bool per lane
var held_sustain: Array = []   # note index per lane (-1 = none)

# Hit flash effects
var hit_effects: Array = []
# Hit ring animations [{lane, radius, alpha, max_radius}]
var hit_rings: Array = []
# Miss flash (red edge flash)
var _miss_flash_alpha: float = 0.0
# Miss/wrong-tap lane flashes: [{lane, alpha}]
var _miss_lane_flashes: Array = []
# Combo milestone popup
var _milestone_text: String = ""
var _milestone_alpha: float = 0.0
var _milestone_scale: float = 1.0

# Combo multiplier + glow tiers: [min_combo, multiplier, glow_color, label]
const COMBO_TIERS := [
	[500, 20.0, Color(1.0, 0.2, 0.9, 0.7),  "20x"],   # magenta
	[300, 15.0, Color(1.0, 0.3, 0.15, 0.7),  "15x"],   # orange-red
	[200, 12.0, Color(1.0, 0.55, 0.05, 0.65), "12x"],   # orange
	[100, 10.0, Color(1.0, 0.85, 0.1, 0.6),  "10x"],   # gold
	[50,  5.0,  Color(0.3, 0.9, 1.0, 0.5),   "5x"],    # cyan
	[25,  2.5,  Color(1.0, 1.0, 1.0, 0.4),   "2.5x"],  # white
]
var _combo_glow_color := Color.TRANSPARENT
var _combo_multiplier := 1.0

# Rock Meter state
var _rock_meter_mode: String = "visual"
var _rock_meter_value: float = ROCK_METER_START
var _rock_meter_display: float = ROCK_METER_START
var _song_failed: bool = false

# Overdrive / solo state
var _overdrive_energy: float = 0.0
var _overdrive_active: bool = false
var _overdrive_states: Array = []
var _solo_states: Array = []
var _active_solo_idx: int = -1
var _solo_result_scores: Array[float] = []
var _solo_label_tw: Tween = null
var _perfect_streak: int = 0

# Crowd audio is kept outside audio_players so song synchronization and the
# master playback clock can never be affected by reactions.
var _crowd_ambience: AudioStreamPlayer = null
var _crowd_reaction: AudioStreamPlayer = null
var _crowd_reaction_fade_tween: Tween = null
var _crowd_cheer_stream: AudioStream = null
var _crowd_boo_stream: AudioStream = null
var _crowd_applause_strong_stream: AudioStream = null
var _crowd_applause_light_stream: AudioStream = null
var _crowd_ambience_streams: Array[AudioStream] = []
var _crowd_cheer_streams: Array[AudioStream] = []
var _crowd_boo_streams: Array[AudioStream] = []
var _crowd_last_cheer_idx: int = -1
var _crowd_last_boo_idx: int = -1
var _crowd_reaction_cooldown: float = 0.0
var _crowd_ambience_boost_timer: float = 0.0
var _crowd_zone: int = 2
var _crowd_mistake_count: int = 0
var _crowd_mistake_threshold: int = CROWD_MISTAKES_BEFORE_BOO
var _crowd_recovery_perfects: int = 0
var _crowd_last_mistake_song_ms: float = -1000.0
var _crowd_pending_boo: bool = false
var _crowd_burst_players: Array[AudioStreamPlayer] = []
var _crowd_performance_started: bool = false
var _ending_crowd_triggered: bool = false
static var _last_crowd_ambience_path: String = ""

# A short wrong-note guitar cue. It has its own player and setting, so disabling
# crowd ambience does not disable gameplay feedback (or vice versa).
var _miss_sfx_player: AudioStreamPlayer = null
var _last_miss_sfx_song_ms: float = -1000.0
var _music_duck_tween: Tween = null

# Stats for result screen
var total_notes: int = 0
var hit_count: int = 0
var miss_count: int = 0

# Loading
var is_loading: bool = false
var loading_status: String = ""
var loading_progress: float = 0.0

# Nodes
var audio_players: Array[AudioStreamPlayer] = []
var master_player: AudioStreamPlayer = null
var hud_layer: CanvasLayer
var score_label: Label
var fps_label: Label
var _fps_timer: float = 0.0
var _hud_slow_timer: float = 0.0
var _hud_last_score: int = -1
var _hud_last_multiplier: float = -1.0
var mult_label: Label
var combo_label: Label
var _combo_popup_tw: Tween = null
var judgment_label: Label
var _judgment_tw: Tween = null
var lyric_panel: PanelContainer
var lyric_rtl: RichTextLabel
var _lyrics_center_y_ratio: float = 0.0
var _ui_scale: float = 1.0
var _lyric_font_size: int = 24
var _lyric_next_font_size: int = 15
var warning_label: Label
var progress_bar: ProgressBar
var offset_slider: HSlider
var offset_label: Label
var milestone_label: Label
var rest_timer_label: Label
var rock_meter_panel: PanelContainer
var rock_meter_track: Control
var rock_meter_fill: ColorRect
var rock_meter_needle: ColorRect
var rock_meter_status_label: Label
var overdrive_button: Button
var overdrive_bar: ProgressBar
var _overdrive_ui_state: int = -1
var solo_label: Label
var _rock_meter_ui_zone: int = -1

# Loading screen
var loading_layer: CanvasLayer
var loading_status_label: Label
var loading_bar: ProgressBar
var loading_song_label: Label
var loading_artist_label: Label
var loading_info_label: Label
var loading_dots_timer: float = 0.0
var _pending_cached_path: String = ""
var _decode_plugin = null

# Note style caches
var note_styles: Array[StyleBoxFlat] = []
var note_styles_hit: Array[StyleBoxFlat] = []
var sustain_styles: Array[StyleBoxFlat] = []
var sustain_styles_hit: Array[StyleBoxFlat] = []
var sustain_styles_hold: Array[StyleBoxFlat] = []

static var song_source: String = ""
static var song_difficulty: String = "Expert"
static var song_mode: String = "guitar"
static var song_preset: String = "Tiles"
static var song_instrument: String = "guitar"
static var debug_infinite_overdrive: bool = false

func _ready() -> void:
	Settings.load_settings()
	_vfx_quality = Settings.vfx_quality
	_rock_meter_mode = Settings.rock_meter_mode
	_frame_time_msec = float(Time.get_ticks_msec())
	_frame_time_sec = _frame_time_msec / 1000.0
	_ui_scale = _detect_ui_scale()
	_lyric_font_size = _fs(26)
	_lyric_next_font_size = _fs(17)
	print("Game UI: portrait scale=%.2f dpi=%d viewport=%s" % [
		_ui_scale, DisplayServer.screen_get_dpi(), str(get_viewport_rect().size)])

	if OS.has_feature("android"):
		if Engine.has_singleton("NativeAudioDecoder"):
			print("AUDIO: NativeAudioDecoder plugin OK")
		else:
			push_error("AUDIO: NativeAudioDecoder plugin NOT found!")

	if song_mode == "piano":
		lane_count = 4
		lane_colors.assign(PIANO_COLORS)
	else:
		lane_count = 5
		lane_colors.assign(GUITAR_COLORS)

	_gh_mode = Settings.highway_style == "gh"
	_cached_approach_ms = Settings.get_approach_ms()
	_cache_render_geometry()
	get_viewport().size_changed.connect(_cache_render_geometry)

	lane_pressed.resize(lane_count)
	held_sustain.resize(lane_count)
	_lane_streak.resize(lane_count)
	_sustain_spark_timer.resize(lane_count)
	for i in range(lane_count):
		lane_pressed[i] = false
		held_sustain[i] = -1
		_lane_streak[i] = 0.0
		_sustain_spark_timer[i] = 0.0

	# Starfield
	var star_rng := RandomNumberGenerator.new()
	star_rng.seed = 42
	for i in range(32):
		_star_x.append(star_rng.randf())
		_star_y.append(star_rng.randf())
		_star_size.append(star_rng.randf_range(1.0, 2.3))
		_star_speed.append(star_rng.randf_range(0.004, 0.016))
		_star_phase.append(star_rng.randf_range(0.0, TAU))

	# Note skin textures — lane-colored tiles in Flat mode.
	var tile_names := ["tile_green", "tile_red", "tile_yellow", "tile_blue", "tile_orange"]
	note_tex.clear()
	for i in range(lane_count):
		note_tex.append(VFX.tex(tile_names[i]))

	_build_note_styles()
	_build_ui()
	_setup_crowd_audio()
	_setup_miss_sfx()
	is_loading = true
	loading_status = I18n.t("loading_effects")
	call_deferred("_begin_game_load")

func _begin_game_load() -> void:
	# Paint the game's own loading screen before touching the large sprite
	# sheets, then make sure their first use cannot hitch a live note.
	await get_tree().process_frame
	VFX.preload_effects(_vfx_quality != "performance")
	await get_tree().process_frame
	_load_song()

# --- StyleBoxFlat caches ---

func _build_note_styles() -> void:
	note_styles.clear()
	note_styles_hit.clear()
	sustain_styles.clear()
	sustain_styles_hit.clear()
	sustain_styles_hold.clear()
	for c in lane_colors:
		# Active note — neon glow via stylebox shadow
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(8)
		sb.border_color = c.lightened(0.45)
		sb.set_border_width_all(2)
		sb.shadow_color = Color(c.r, c.g, c.b, 0.5)
		sb.shadow_size = 7
		note_styles.append(sb)

		# Hit note (darkened)
		var sh := StyleBoxFlat.new()
		sh.bg_color = c.darkened(0.45)
		sh.set_corner_radius_all(6)
		sh.border_color = c.darkened(0.25)
		sh.set_border_width_all(1)
		note_styles_hit.append(sh)

		# Sustain tail (active)
		var ss := StyleBoxFlat.new()
		ss.bg_color = c * Color(1, 1, 1, 0.4)
		ss.set_corner_radius_all(3)
		sustain_styles.append(ss)

		# Sustain tail (hit/released)
		var ssh := StyleBoxFlat.new()
		ssh.bg_color = c.darkened(0.45) * Color(1, 1, 1, 0.35)
		ssh.set_corner_radius_all(3)
		sustain_styles_hit.append(ssh)

		# Sustain tail (being held — brighter)
		var sshold := StyleBoxFlat.new()
		sshold.bg_color = c * Color(1, 1, 1, 0.65)
		sshold.set_corner_radius_all(3)
		sshold.border_color = c.lightened(0.2)
		sshold.set_border_width_all(1)
		sustain_styles_hold.append(sshold)

# --- UI ---

func _detect_ui_scale() -> float:
	var dpi := float(DisplayServer.screen_get_dpi())
	var density_scale := clampf(dpi / 220.0, 1.0, 1.85) if dpi > 0.0 else 1.0
	if OS.has_feature("android") and dpi <= 160.0:
		density_scale = 1.25
	var short_edge := minf(get_viewport_rect().size.x, get_viewport_rect().size.y)
	var viewport_cap := clampf(short_edge / 480.0, 1.0, 1.70)
	return minf(density_scale, viewport_cap)

func _u(value: float) -> float:
	return roundf(value * _ui_scale)

func _fs(value: float) -> int:
	return maxi(1, int(roundf(value * _ui_scale)))

func _build_ui() -> void:
	var theme := _create_theme()
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)

	var hud_root := Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.theme = theme
	# Apply safe area insets so HUD avoids notch/rounded corners
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if screen.x > 0 and screen.y > 0:
		var vp := get_viewport_rect().size
		var scale_x := vp.x / float(screen.x)
		var scale_y := vp.y / float(screen.y)
		var inset_left := safe.position.x * scale_x
		var inset_top := safe.position.y * scale_y
		var inset_right := (screen.x - safe.end.x) * scale_x
		var inset_bottom := (screen.y - safe.end.y) * scale_y
		hud_root.offset_left = inset_left
		hud_root.offset_top = inset_top
		hud_root.offset_right = -inset_right
		hud_root.offset_bottom = -inset_bottom
		if inset_left + inset_top + inset_right + inset_bottom > 0:
			print("UI: safe area insets L=%.0f T=%.0f R=%.0f B=%.0f" % [inset_left, inset_top, inset_right, inset_bottom])
	hud_layer.add_child(hud_root)

	# Score — top center, bold with soft glow
	score_label = Label.new()
	score_label.text = "0"
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.anchor_left = 0.0; score_label.anchor_right = 1.0
	score_label.anchor_top = 0.0; score_label.offset_top = _u(12)
	score_label.add_theme_font_size_override("font_size", _fs(34))
	score_label.add_theme_color_override("font_color", UITheme.TEXT_BRIGHT)
	score_label.add_theme_color_override("font_shadow_color", Color(UITheme.NEON_CYAN.r, UITheme.NEON_CYAN.g, UITheme.NEON_CYAN.b, 0.35))
	score_label.add_theme_constant_override("shadow_offset_x", 0)
	score_label.add_theme_constant_override("shadow_offset_y", 0)
	score_label.add_theme_constant_override("shadow_outline_size", int(_u(8)))
	if UITheme.font_bold():
		score_label.add_theme_font_override("font", UITheme.font_bold())
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(score_label)

	# Multiplier badge — under score, visible only when a combo tier is active
	mult_label = Label.new()
	mult_label.text = ""
	mult_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mult_label.anchor_left = 0.0; mult_label.anchor_right = 1.0
	mult_label.anchor_top = 0.0; mult_label.offset_top = _u(54)
	mult_label.add_theme_font_size_override("font_size", _fs(21))
	if UITheme.font_bold():
		mult_label.add_theme_font_override("font", UITheme.font_bold())
	mult_label.add_theme_constant_override("shadow_offset_x", 0)
	mult_label.add_theme_constant_override("shadow_offset_y", 0)
	mult_label.add_theme_constant_override("shadow_outline_size", int(_u(8)))
	mult_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mult_label.visible = false
	hud_root.add_child(mult_label)

	# Progress bar — thin neon strip, top
	progress_bar = ProgressBar.new()
	progress_bar.show_percentage = false
	progress_bar.anchor_left = 0.0; progress_bar.anchor_right = 1.0
	progress_bar.anchor_top = 0.0; progress_bar.offset_top = 0
	progress_bar.offset_bottom = _u(5)
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pb_bg := UITheme.flat_style(Color(1, 1, 1, 0.06), 0)
	progress_bar.add_theme_stylebox_override("background", pb_bg)
	var pb_fill := UITheme.flat_style(UITheme.NEON_CYAN, 0)
	progress_bar.add_theme_stylebox_override("fill", pb_fill)
	hud_root.add_child(progress_bar)

	# FPS counter — top right, subtle
	fps_label = Label.new()
	fps_label.text = ""
	fps_label.anchor_left = 1.0; fps_label.anchor_right = 1.0
	fps_label.offset_left = -_u(92); fps_label.offset_right = -_u(10); fps_label.offset_top = _u(12)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.add_theme_font_size_override("font_size", _fs(14))
	fps_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8, 0.55))
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(fps_label)

	# Pause button — top left
	var pause_btn := Button.new()
	pause_btn.text = "II"
	UITheme.style_ghost_button(pause_btn, _fs(19))
	pause_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	pause_btn.offset_left = _u(10); pause_btn.offset_top = _u(10)
	pause_btn.custom_minimum_size = Vector2(_u(68), _u(56))
	pause_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_btn.pressed.connect(_toggle_pause)
	hud_root.add_child(pause_btn)

	# Combo — big, positioned above hit line
	combo_label = Label.new()
	combo_label.text = ""
	combo_label.add_theme_font_size_override("font_size", _fs(52))
	combo_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	combo_label.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.25))
	combo_label.add_theme_constant_override("shadow_offset_x", 0)
	combo_label.add_theme_constant_override("shadow_offset_y", 0)
	combo_label.add_theme_constant_override("shadow_outline_size", int(_u(10)))
	if UITheme.font_bold():
		combo_label.add_theme_font_override("font", UITheme.font_bold())
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.anchor_left = 0.0; combo_label.anchor_right = 1.0
	var hlr2: float = _lp()["hit_line_ratio"]
	combo_label.anchor_top = hlr2 - 0.12; combo_label.anchor_bottom = hlr2 - 0.02
	combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# pivot_offset set after layout so scale animation centers properly
	combo_label.resized.connect(func(): combo_label.pivot_offset = combo_label.size / 2.0)
	hud_root.add_child(combo_label)

	# Judgment feedback — briefly confirms whether the touch landed inside
	# the colored button (Perfect) or in its nearby tolerance area (Good).
	judgment_label = Label.new()
	judgment_label.text = ""
	judgment_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	judgment_label.anchor_left = 0.0; judgment_label.anchor_right = 1.0
	judgment_label.anchor_top = hlr2 - 0.18; judgment_label.anchor_bottom = hlr2 - 0.13
	judgment_label.add_theme_font_size_override("font_size", _fs(25))
	judgment_label.add_theme_constant_override("shadow_offset_x", 0)
	judgment_label.add_theme_constant_override("shadow_offset_y", 0)
	judgment_label.add_theme_constant_override("shadow_outline_size", int(_u(8)))
	if UITheme.font_bold():
		judgment_label.add_theme_font_override("font", UITheme.font_bold())
	judgment_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	judgment_label.modulate.a = 0.0
	judgment_label.resized.connect(func(): judgment_label.pivot_offset = judgment_label.size / 2.0)
	hud_root.add_child(judgment_label)

	# Lyrics box — keep the original, center-screen reading position. Its size
	# adapts to the text, but it grows around this point instead of drifting.
	lyric_panel = PanelContainer.new()
	var lyric_style := StyleBoxFlat.new()
	lyric_style.bg_color = Color(0.04, 0.035, 0.09, 0.76)
	lyric_style.set_corner_radius_all(_fs(12))
	lyric_style.border_color = Color(UITheme.NEON_PURPLE.r, UITheme.NEON_PURPLE.g, UITheme.NEON_PURPLE.b, 0.20)
	lyric_style.set_border_width_all(maxi(1, int(_u(1.5))))
	lyric_style.content_margin_left = _u(16); lyric_style.content_margin_right = _u(16)
	lyric_style.content_margin_top = _u(9); lyric_style.content_margin_bottom = _u(9)
	lyric_panel.add_theme_stylebox_override("panel", lyric_style)
	# Use pixel positioning instead of Control's automatic grow behaviour.
	# That lets the box resize while its exact visual center stays locked.
	_lyrics_center_y_ratio = hlr2 - 0.24
	lyric_panel.anchor_left = 0.0; lyric_panel.anchor_right = 0.0
	lyric_panel.anchor_top = 0.0; lyric_panel.anchor_bottom = 0.0
	lyric_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lyric_panel.visible = false
	hud_root.add_child(lyric_panel)

	lyric_rtl = RichTextLabel.new()
	lyric_rtl.bbcode_enabled = true
	lyric_rtl.fit_content = true
	lyric_rtl.scroll_active = false
	lyric_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lyric_rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lyric_rtl.add_theme_font_size_override("normal_font_size", _lyric_font_size)
	lyric_rtl.add_theme_color_override("default_color", UITheme.TEXT_BRIGHT)
	lyric_panel.add_child(lyric_rtl)
	lyric_panel.resized.connect(func(): _center_lyrics_panel())
	lyric_rtl.resized.connect(func(): call_deferred("_center_lyrics_panel"))
	get_viewport().size_changed.connect(func(): call_deferred("_center_lyrics_panel"))
	call_deferred("_center_lyrics_panel")

	offset_label = Label.new()
	offset_label.text = I18n.t("offset_label", [0])
	offset_label.add_theme_font_size_override("font_size", _fs(14))
	offset_label.anchor_left = 1.0; offset_label.anchor_right = 1.0; offset_label.anchor_top = 1.0
	offset_label.offset_left = -_u(190); offset_label.offset_top = -_u(72)
	hud_root.add_child(offset_label)

	offset_slider = HSlider.new()
	offset_slider.min_value = -200; offset_slider.max_value = 200; offset_slider.step = 5; offset_slider.value = 0
	offset_slider.anchor_left = 1.0; offset_slider.anchor_right = 1.0; offset_slider.anchor_top = 1.0
	offset_slider.offset_left = -_u(190); offset_slider.offset_top = -_u(44)
	offset_slider.size = Vector2(_u(174), _u(28))
	offset_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	offset_slider.value_changed.connect(_on_offset_changed)
	hud_root.add_child(offset_slider)

	# Loading screen (separate CanvasLayer, above everything)
	_build_loading_screen()

	# Combo milestone popup
	milestone_label = Label.new()
	milestone_label.text = ""
	milestone_label.add_theme_font_size_override("font_size", _fs(60))
	milestone_label.add_theme_color_override("font_color", UITheme.NEON_GOLD)
	milestone_label.add_theme_color_override("font_shadow_color", Color(UITheme.NEON_GOLD.r, UITheme.NEON_GOLD.g, UITheme.NEON_GOLD.b, 0.5))
	milestone_label.add_theme_constant_override("shadow_offset_x", 0)
	milestone_label.add_theme_constant_override("shadow_offset_y", 0)
	milestone_label.add_theme_constant_override("shadow_outline_size", int(_u(14)))
	if UITheme.font_bold():
		milestone_label.add_theme_font_override("font", UITheme.font_bold())
	milestone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	milestone_label.anchor_left = 0.0; milestone_label.anchor_right = 1.0
	milestone_label.anchor_top = 0.35; milestone_label.anchor_bottom = 0.5
	milestone_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	milestone_label.modulate.a = 0.0
	milestone_label.resized.connect(func(): milestone_label.pivot_offset = milestone_label.size / 2.0)
	hud_root.add_child(milestone_label)

	# Rest timer — shows countdown when next note is far away
	rest_timer_label = Label.new()
	rest_timer_label.text = ""
	rest_timer_label.add_theme_font_size_override("font_size", _fs(40))
	rest_timer_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9, 0.8))
	rest_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rest_timer_label.anchor_left = 0.0; rest_timer_label.anchor_right = 1.0
	var hlr3: float = _lp()["hit_line_ratio"]
	rest_timer_label.anchor_top = hlr3 + 0.04
	rest_timer_label.anchor_bottom = hlr3 + 0.12
	rest_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rest_timer_label.visible = false
	hud_root.add_child(rest_timer_label)

	warning_label = Label.new()
	warning_label.text = ""
	warning_label.add_theme_font_size_override("font_size", _fs(22))
	warning_label.add_theme_color_override("font_color", Color(1, 0.3, 0.2))
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	warning_label.size = Vector2(minf(_u(600), get_viewport_rect().size.x - _u(32)), _u(48))
	warning_label.offset_left = -warning_label.size.x * 0.5; warning_label.offset_top = _u(72)
	warning_label.visible = false
	hud_root.add_child(warning_label)

	_build_overdrive_ui(hud_root)
	_build_rock_meter(hud_root)

func _build_overdrive_ui(parent: Control) -> void:
	var panel := PanelContainer.new()
	# Keep Overdrive below the playable lanes. Anchoring to the safe area's
	# bottom edge prevents it from covering notes on phones and tablets.
	panel.anchor_left = 0.34; panel.anchor_right = 0.66
	panel.anchor_top = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = 0.0; panel.offset_right = 0.0
	panel.offset_top = -_u(50); panel.offset_bottom = -_u(4)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.02, 0.06, 0.86)
	panel_style.border_color = Color(UITheme.NEON_CYAN.r, UITheme.NEON_CYAN.g, UITheme.NEON_CYAN.b, 0.28)
	panel_style.set_border_width_all(maxi(1, int(_u(1.0))))
	panel_style.set_corner_radius_all(int(_u(8)))
	panel_style.content_margin_left = _u(4); panel_style.content_margin_right = _u(4)
	panel_style.content_margin_top = _u(3); panel_style.content_margin_bottom = _u(3)
	panel.add_theme_stylebox_override("panel", panel_style)
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(_u(2)))
	panel.add_child(vbox)
	overdrive_button = Button.new()
	overdrive_button.text = I18n.t("overdrive")
	overdrive_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overdrive_button.custom_minimum_size = Vector2(0, _u(28))
	UITheme.style_chip_button(overdrive_button, false, UITheme.NEON_CYAN)
	overdrive_button.add_theme_font_size_override("font_size", _fs(13))
	overdrive_button.pressed.connect(_activate_overdrive)
	vbox.add_child(overdrive_button)

	overdrive_bar = ProgressBar.new()
	overdrive_bar.show_percentage = false
	overdrive_bar.min_value = 0.0; overdrive_bar.max_value = 1.0
	overdrive_bar.custom_minimum_size = Vector2(0, _u(5))
	overdrive_bar.add_theme_stylebox_override("background", UITheme.flat_style(Color(1, 1, 1, 0.08), _fs(7)))
	overdrive_bar.add_theme_stylebox_override("fill", UITheme.flat_style(UITheme.NEON_CYAN, _fs(7)))
	vbox.add_child(overdrive_bar)

	solo_label = Label.new()
	solo_label.text = ""
	solo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	solo_label.anchor_left = 0.0; solo_label.anchor_right = 1.0
	solo_label.anchor_top = 0.28; solo_label.anchor_bottom = 0.34
	solo_label.add_theme_font_size_override("font_size", _fs(30))
	solo_label.add_theme_color_override("font_color", UITheme.NEON_MAGENTA.lightened(0.25))
	solo_label.add_theme_color_override("font_shadow_color", Color(UITheme.NEON_MAGENTA.r, UITheme.NEON_MAGENTA.g, UITheme.NEON_MAGENTA.b, 0.50))
	solo_label.add_theme_constant_override("shadow_offset_x", 0)
	solo_label.add_theme_constant_override("shadow_offset_y", 0)
	solo_label.add_theme_constant_override("shadow_outline_size", int(_u(10)))
	if UITheme.font_bold():
		solo_label.add_theme_font_override("font", UITheme.font_bold())
	solo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	solo_label.visible = false
	parent.add_child(solo_label)
	_update_overdrive_ui()

func _build_rock_meter(parent: Control) -> void:
	if _rock_meter_mode == "off":
		return

	rock_meter_panel = PanelContainer.new()
	rock_meter_panel.anchor_left = 1.0; rock_meter_panel.anchor_right = 1.0
	rock_meter_panel.anchor_top = 0.18; rock_meter_panel.anchor_bottom = 0.18
	rock_meter_panel.offset_left = -_u(72); rock_meter_panel.offset_right = -_u(8)
	rock_meter_panel.offset_top = 0.0
	rock_meter_panel.offset_bottom = minf(_u(286), get_viewport_rect().size.y * 0.31)
	rock_meter_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var meter_panel_style := StyleBoxFlat.new()
	meter_panel_style.bg_color = Color(0.025, 0.02, 0.06, 0.84)
	meter_panel_style.border_color = Color(1, 1, 1, 0.20)
	meter_panel_style.set_border_width_all(maxi(1, int(_u(1.0))))
	meter_panel_style.set_corner_radius_all(int(_u(10)))
	meter_panel_style.content_margin_left = _u(7); meter_panel_style.content_margin_right = _u(7)
	meter_panel_style.content_margin_top = _u(7); meter_panel_style.content_margin_bottom = _u(7)
	rock_meter_panel.add_theme_stylebox_override("panel", meter_panel_style)
	parent.add_child(rock_meter_panel)

	var meter_vbox := VBoxContainer.new()
	meter_vbox.add_theme_constant_override("separation", int(_u(4)))
	rock_meter_panel.add_child(meter_vbox)

	var meter_title := Label.new()
	meter_title.text = "ROCK"
	meter_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meter_title.add_theme_font_size_override("font_size", _fs(11))
	meter_title.add_theme_color_override("font_color", UITheme.TEXT_BRIGHT)
	if UITheme.font_bold():
		meter_title.add_theme_font_override("font", UITheme.font_bold())
	meter_vbox.add_child(meter_title)

	rock_meter_track = Control.new()
	rock_meter_track.custom_minimum_size = Vector2(_u(38), _u(184))
	rock_meter_track.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rock_meter_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rock_meter_track.clip_contents = true
	meter_vbox.add_child(rock_meter_track)

	var green_zone := ColorRect.new()
	green_zone.color = Color(0.12, 0.88, 0.30, 0.32)
	green_zone.anchor_right = 1.0; green_zone.anchor_bottom = 1.0 - ROCK_METER_GREEN_THRESHOLD
	green_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rock_meter_track.add_child(green_zone)

	var yellow_zone := ColorRect.new()
	yellow_zone.color = Color(1.0, 0.78, 0.08, 0.34)
	yellow_zone.anchor_top = 1.0 - ROCK_METER_GREEN_THRESHOLD
	yellow_zone.anchor_right = 1.0
	yellow_zone.anchor_bottom = 1.0 - ROCK_METER_DANGER_THRESHOLD
	yellow_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rock_meter_track.add_child(yellow_zone)

	var red_zone := ColorRect.new()
	red_zone.color = Color(1.0, 0.10, 0.08, 0.38)
	red_zone.anchor_top = 1.0 - ROCK_METER_DANGER_THRESHOLD
	red_zone.anchor_right = 1.0; red_zone.anchor_bottom = 1.0
	red_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rock_meter_track.add_child(red_zone)

	# A translucent fill shows the current amount while all three classic
	# red/yellow/green performance zones remain readable behind it.
	rock_meter_fill = ColorRect.new()
	rock_meter_fill.anchor_right = 1.0; rock_meter_fill.anchor_bottom = 1.0
	rock_meter_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rock_meter_track.add_child(rock_meter_fill)

	for threshold in [ROCK_METER_GREEN_THRESHOLD, ROCK_METER_DANGER_THRESHOLD]:
		var threshold_line := ColorRect.new()
		threshold_line.color = Color(1, 1, 1, 0.48)
		threshold_line.anchor_top = 1.0 - threshold
		threshold_line.anchor_right = 1.0
		threshold_line.anchor_bottom = 1.0 - threshold
		threshold_line.offset_top = -_u(1); threshold_line.offset_bottom = _u(1)
		threshold_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rock_meter_track.add_child(threshold_line)

	rock_meter_needle = ColorRect.new()
	rock_meter_needle.anchor_right = 1.0
	rock_meter_needle.color = Color.WHITE
	rock_meter_needle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rock_meter_track.add_child(rock_meter_needle)

	rock_meter_status_label = Label.new()
	rock_meter_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rock_meter_status_label.add_theme_font_size_override("font_size", _fs(10))
	if UITheme.font_bold():
		rock_meter_status_label.add_theme_font_override("font", UITheme.font_bold())
	meter_vbox.add_child(rock_meter_status_label)
	_update_rock_meter_controls()

func _rock_meter_color(value: float) -> Color:
	if value >= ROCK_METER_GREEN_THRESHOLD:
		return UITheme.NEON_GREEN
	if value >= ROCK_METER_DANGER_THRESHOLD:
		return UITheme.NEON_GOLD
	return Color(1.0, 0.12, 0.08)

func _update_rock_meter_controls() -> void:
	if rock_meter_panel == null:
		return
	var shown := clampf(_rock_meter_display, 0.0, 1.0)
	rock_meter_fill.anchor_top = 1.0 - shown
	rock_meter_needle.anchor_top = 1.0 - shown
	rock_meter_needle.anchor_bottom = 1.0 - shown
	var zone := 2 if shown >= ROCK_METER_GREEN_THRESHOLD else (1 if shown >= ROCK_METER_DANGER_THRESHOLD else 0)
	if zone == _rock_meter_ui_zone:
		return
	_rock_meter_ui_zone = zone
	var meter_color := _rock_meter_color(shown)
	rock_meter_fill.color = Color(meter_color.r, meter_color.g, meter_color.b, 0.30)
	rock_meter_needle.offset_top = -_u(2)
	rock_meter_needle.offset_bottom = _u(2)
	rock_meter_needle.color = meter_color.lightened(0.34)
	rock_meter_status_label.add_theme_color_override("font_color", meter_color.lightened(0.20))
	if zone == 2:
		rock_meter_status_label.text = I18n.t("rock_great")
	elif zone == 1:
		rock_meter_status_label.text = I18n.t("rock_ok")
	else:
		rock_meter_status_label.text = I18n.t("rock_danger")

func _create_theme() -> Theme:
	return UITheme.create_theme()

# --- Pause ---

func _toggle_pause() -> void:
	if is_loading or _countdown > 0 or not song_started:
		return
	if _paused:
		_resume_game()
	else:
		_pause_game()

func _pause_game() -> void:
	_paused = true
	for p in audio_players:
		p.stream_paused = true
	if _crowd_ambience: _crowd_ambience.stream_paused = true
	if _crowd_reaction: _crowd_reaction.stream_paused = true
	for player in _crowd_burst_players:
		if is_instance_valid(player): player.stream_paused = true

	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 18
	add_child(_pause_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.05, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.theme = _create_theme()
	_pause_layer.add_child(dim)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var pause_w := minf(_u(390), get_viewport_rect().size.x - _u(48))
	vbox.offset_left = -pause_w * 0.5; vbox.offset_right = pause_w * 0.5
	vbox.offset_top = -_u(210); vbox.offset_bottom = _u(210)
	vbox.add_theme_constant_override("separation", int(_u(16)))
	dim.add_child(vbox)

	var title := Label.new()
	title.text = I18n.t("paused")
	title.add_theme_font_size_override("font_size", _fs(38))
	title.add_theme_color_override("font_color", UITheme.NEON_CYAN.lightened(0.3))
	title.add_theme_color_override("font_shadow_color", Color(UITheme.NEON_CYAN.r, UITheme.NEON_CYAN.g, UITheme.NEON_CYAN.b, 0.5))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_constant_override("shadow_outline_size", int(_u(12)))
	if UITheme.font_bold():
		title.add_theme_font_override("font", UITheme.font_bold())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, _u(14))
	vbox.add_child(spacer)

	var resume_btn := Button.new()
	resume_btn.text = I18n.t("resume")
	UITheme.style_primary_button(resume_btn, UITheme.NEON_GREEN, _fs(23))
	resume_btn.custom_minimum_size = Vector2(0, _u(68))
	resume_btn.pressed.connect(_resume_game)
	vbox.add_child(resume_btn)

	var restart_btn := Button.new()
	restart_btn.text = I18n.t("restart")
	UITheme.style_ghost_button(restart_btn, _fs(20))
	restart_btn.custom_minimum_size = Vector2(0, _u(62))
	restart_btn.pressed.connect(func(): get_tree().reload_current_scene())
	vbox.add_child(restart_btn)

	var quit_btn := Button.new()
	quit_btn.text = I18n.t("quit_song")
	UITheme.style_danger_button(quit_btn, _fs(20))
	quit_btn.custom_minimum_size = Vector2(0, _u(62))
	quit_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	vbox.add_child(quit_btn)

func _resume_game() -> void:
	_paused = false
	if _pause_layer:
		_pause_layer.queue_free()
		_pause_layer = null
	for p in audio_players:
		p.stream_paused = false
	if _crowd_ambience: _crowd_ambience.stream_paused = false
	if _crowd_reaction: _crowd_reaction.stream_paused = false
	for player in _crowd_burst_players:
		if is_instance_valid(player): player.stream_paused = false

func _build_loading_screen() -> void:
	loading_layer = CanvasLayer.new()
	loading_layer.layer = 15
	add_child(loading_layer)

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	loading_layer.add_child(bg)

	var theme := _create_theme()

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = theme
	loading_layer.add_child(root)
	UITheme.add_neon_background(root, 2)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var loading_w := minf(_u(440), get_viewport_rect().size.x - _u(48))
	vbox.offset_left = -loading_w * 0.5; vbox.offset_right = loading_w * 0.5
	vbox.offset_top = -_u(230); vbox.offset_bottom = _u(230)
	vbox.add_theme_constant_override("separation", 10)
	root.add_child(vbox)

	# Album art
	var art_texture := _load_album_art_for_loading()
	if art_texture:
		var art_rect := TextureRect.new()
		art_rect.texture = art_texture
		art_rect.custom_minimum_size = Vector2(_u(150), _u(150))
		art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(art_rect)
	else:
		var art_panel := PanelContainer.new()
		var art_style := StyleBoxFlat.new()
		art_style.bg_color = Color(0.12, 0.12, 0.16)
		art_style.set_corner_radius_all(14)
		art_panel.add_theme_stylebox_override("panel", art_style)
		art_panel.custom_minimum_size = Vector2(_u(150), _u(150))
		art_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(art_panel)
		var art_icon := Label.new()
		art_icon.text = "♪"
		art_icon.add_theme_font_size_override("font_size", _fs(56))
		art_icon.add_theme_color_override("font_color", Color(0.35, 0.35, 0.45))
		art_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		art_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		art_panel.add_child(art_icon)

	# Song title
	var parsed := _parse_loading_song_name()
	loading_song_label = Label.new()
	loading_song_label.text = parsed["title"]
	loading_song_label.add_theme_font_size_override("font_size", _fs(31))
	loading_song_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	loading_song_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_song_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	var font_bold := load("res://fonts/Inter-Bold.ttf") as Font
	if font_bold:
		loading_song_label.add_theme_font_override("font", font_bold)
	vbox.add_child(loading_song_label)

	# Artist
	loading_artist_label = Label.new()
	loading_artist_label.text = parsed["artist"]
	loading_artist_label.add_theme_font_size_override("font_size", _fs(21))
	loading_artist_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	loading_artist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_artist_label.visible = parsed["artist"] != ""
	vbox.add_child(loading_artist_label)

	# Info line: instrument + difficulty + preset
	loading_info_label = Label.new()
	loading_info_label.text = "%s  •  %s  •  %s" % [
		I18n.instrument_name(song_instrument), I18n.difficulty_name(song_difficulty), I18n.preset_name(song_preset)]
	loading_info_label.add_theme_font_size_override("font_size", _fs(18))
	loading_info_label.add_theme_color_override("font_color", UITheme.NEON_CYAN.darkened(0.15))
	loading_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(loading_info_label)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, _u(18))
	vbox.add_child(spacer)

	# Status text
	loading_status_label = Label.new()
	loading_status_label.text = ""
	loading_status_label.add_theme_font_size_override("font_size", _fs(22))
	loading_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	loading_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(loading_status_label)

	# Progress bar — neon
	loading_bar = ProgressBar.new()
	loading_bar.show_percentage = false
	loading_bar.max_value = 100
	loading_bar.custom_minimum_size = Vector2(0, _u(10))
	loading_bar.visible = false

	var bar_style := UITheme.flat_style(Color(0.12, 0.11, 0.20), 4)
	loading_bar.add_theme_stylebox_override("background", bar_style)
	var bar_fill := UITheme.flat_style(UITheme.NEON_CYAN, 4)
	loading_bar.add_theme_stylebox_override("fill", bar_fill)
	vbox.add_child(loading_bar)

	# Back button on loading screen
	var loading_back := Button.new()
	loading_back.text = "‹  " + I18n.t("back")
	UITheme.style_ghost_button(loading_back, 16)
	loading_back.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	loading_back.offset_left = _u(12); loading_back.offset_top = _u(10)
	loading_back.custom_minimum_size = Vector2(_u(68), _u(54))
	loading_back.add_theme_font_size_override("font_size", _fs(18))
	loading_back.pressed.connect(_on_loading_back)
	root.add_child(loading_back)

func _on_loading_back() -> void:
	# Cancel any in-progress decode
	if OS.has_feature("android") and Engine.has_singleton("NativeAudioDecoder"):
		var plugin = Engine.get_singleton("NativeAudioDecoder")
		plugin.call("cancelDecode")
	is_loading = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _parse_loading_song_name() -> Dictionary:
	var name := song_source.get_file()
	for ext in [".sng", ".chart", ".mid"]:
		if name.to_lower().ends_with(ext):
			name = name.substr(0, name.length() - ext.length())
	var paren := name.rfind("(")
	if paren > 0:
		name = name.substr(0, paren).strip_edges()
	var sep := name.find(" - ")
	if sep > 0:
		return {"artist": name.substr(0, sep).strip_edges(), "title": name.substr(sep + 3).strip_edges()}
	return {"artist": "", "title": name}

func _load_album_art_for_loading() -> ImageTexture:
	var source := song_source
	if source.ends_with(".sng"):
		var loader = SngLoaderScript.new()
		if loader.load_sng(source):
			var art_data := loader.get_album_art_data()
			if art_data.size() > 0:
				return _image_from_bytes(art_data)
	else:
		var dir_path := source.get_base_dir()
		for fname in ["album.jpg", "album.png", "cover.jpg", "cover.png"]:
			var art_path := dir_path.path_join(fname)
			if FileAccess.file_exists(art_path):
				var f := FileAccess.open(art_path, FileAccess.READ)
				if f:
					var data := f.get_buffer(f.get_length())
					f.close()
					return _image_from_bytes(data)
	return null

func _image_from_bytes(data: PackedByteArray) -> ImageTexture:
	if data.size() < 4:
		return null
	# Skip Xbox DXT textures (png_xbox) — not standard PNG/JPEG
	var is_jpeg := (data[0] == 0xFF and data[1] == 0xD8)
	var is_png := (data[0] == 0x89 and data[1] == 0x50 and data[2] == 0x4E and data[3] == 0x47)
	if not is_jpeg and not is_png:
		return null
	var img := Image.new()
	if is_jpeg:
		if img.load_jpg_from_buffer(data) != OK:
			return null
	else:
		if img.load_png_from_buffer(data) != OK:
			return null
	if img.get_width() > 256 or img.get_height() > 256:
		img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _hide_loading_screen() -> void:
	if loading_layer:
		var tw := create_tween()
		tw.tween_property(loading_layer, "layer", 15, 0.0)  # keep layer during fade
		# Fade out the first child (ColorRect bg)
		var bg := loading_layer.get_child(0)
		var root := loading_layer.get_child(1)
		tw.tween_property(bg, "modulate:a", 0.0, 0.3)
		tw.parallel().tween_property(root, "modulate:a", 0.0, 0.3)
		tw.tween_callback(func():
			if loading_layer:
				loading_layer.queue_free()
				loading_layer = null
		)

# --- Song loading ---

func _load_song() -> void:
	is_loading = true
	loading_status = I18n.t("loading_chart")
	var source := song_source if song_source != "" else "res://notes.chart"
	var difficulty := song_difficulty if song_difficulty != "" else "Expert"
	var sng_loader: RefCounted = null
	var parse_ok := false
	var parsed_notes: Array = []
	var parsed_lyrics: Array = []
	var parsed_overdrive: Array = []
	var parsed_solos: Array = []
	var parsed_resolution: int = 480
	var parsed_bpm: Array = []

	var chart_offset_sec := 0.0

	if source.ends_with(".sng"):
		sng_loader = SngLoaderScript.new()
		if not sng_loader.load_sng(source):
			push_error("Game: failed to load .sng"); return

		# Priority: .chart first, then .mid
		if sng_loader.has_chart():
			var parser = ChartParserScript.new()
			var chart_text: String = sng_loader.get_chart_text()
			parse_ok = parser.parse_text(chart_text, difficulty, song_instrument)
			if parse_ok:
				parsed_notes = parser.notes
				parsed_lyrics = parser.lyric_phrases
				parsed_overdrive = parser.overdrive_phrases
				parsed_solos = parser.solo_sections
				parsed_resolution = parser.resolution
				parsed_bpm = parser.bpm_events
				chart_offset_sec = parser.audio_offset_sec
				print("Game: parsed .chart from .sng (instrument=%s)" % song_instrument)
		if not parse_ok and sng_loader.has_midi():
			var midi_parser = MidiParserScript.new()
			var midi_data: PackedByteArray = sng_loader.get_midi_data()
			parse_ok = midi_parser.parse_data(midi_data, difficulty, song_instrument)
			if parse_ok:
				parsed_notes = midi_parser.notes
				parsed_lyrics = midi_parser.lyric_phrases
				parsed_overdrive = midi_parser.overdrive_phrases
				parsed_solos = midi_parser.solo_sections
				parsed_resolution = midi_parser.resolution
				parsed_bpm = midi_parser.bpm_events
				print("Game: parsed .mid from .sng (instrument=%s)" % song_instrument)
		if not parse_ok:
			push_error("Game: no chart or midi in .sng"); return

	elif source.ends_with(".chart"):
		var parser = ChartParserScript.new()
		parse_ok = parser.parse_file(source, difficulty, song_instrument)
		if not parse_ok:
			push_error("Game: failed to parse .chart"); return
		parsed_notes = parser.notes
		parsed_lyrics = parser.lyric_phrases
		parsed_overdrive = parser.overdrive_phrases
		parsed_solos = parser.solo_sections
		parsed_resolution = parser.resolution
		parsed_bpm = parser.bpm_events
		chart_offset_sec = parser.audio_offset_sec

	elif source.ends_with(".mid"):
		var midi_parser = MidiParserScript.new()
		parse_ok = midi_parser.parse_file(source, difficulty, song_instrument)
		if not parse_ok:
			push_error("Game: failed to parse .mid"); return
		parsed_notes = midi_parser.notes
		parsed_lyrics = midi_parser.lyric_phrases
		parsed_overdrive = midi_parser.overdrive_phrases
		parsed_solos = midi_parser.solo_sections
		parsed_resolution = midi_parser.resolution
		parsed_bpm = midi_parser.bpm_events

	elif _is_stfs_source(source):
		# CON/LIVE: parse MIDI from container, use pre-imported audio
		var stfs := StfsParserScript.new()
		if not stfs.load_stfs(source):
			push_error("Game: failed to parse CON/LIVE"); return
		var midi_data := stfs.get_midi_data()
		if midi_data.is_empty():
			push_error("Game: no MIDI in CON"); return
		var midi_parser = MidiParserScript.new()
		parse_ok = midi_parser.parse_data(midi_data, difficulty, song_instrument)
		if not parse_ok:
			push_error("Game: failed to parse MIDI from CON"); return
		parsed_notes = midi_parser.notes
		parsed_lyrics = midi_parser.lyric_phrases
		parsed_overdrive = midi_parser.overdrive_phrases
		parsed_solos = midi_parser.solo_sections
		parsed_resolution = midi_parser.resolution
		parsed_bpm = midi_parser.bpm_events
		# Use pre-imported audio from user://songs/ (MOGG decrypt is too slow for main thread)
		# Extract only unencrypted MOGGs on-the-fly; encrypted ones must be imported first
		var mogg_data := stfs.get_mogg_data()
		if mogg_data.size() > 0:
			var tmp_dir := "user://sng_temp"
			_clear_dir(tmp_dir)
			DirAccess.make_dir_recursive_absolute(tmp_dir)
			var version := mogg_data.decode_u32(0)
			if version == 0x0A:
				# Unencrypted — fast, safe to do on main thread
				var mogg := MoggHandlerScript.new()
				mogg.save_ogg_to_file(mogg_data, tmp_dir.path_join("song.ogg"))
			else:
				# Encrypted — cannot decrypt on main thread (would freeze)
				push_error("Game: encrypted MOGG — song must be imported first")
				return
			# Also save album art if available
			var art := stfs.get_album_art_data()
			if art.size() >= 4:
				var is_jpeg := (art[0] == 0xFF and art[1] == 0xD8)
				var is_png := (art[0] == 0x89 and art[1] == 0x50 and art[2] == 0x4E and art[3] == 0x47)
				if is_jpeg or is_png:
					var art_ext := ".jpg" if is_jpeg else ".png"
					var af := FileAccess.open(tmp_dir.path_join("album" + art_ext), FileAccess.WRITE)
					if af:
						af.store_buffer(art)
						af.close()

	else:
		push_error("Game: unknown file type: %s" % source); return

	_chart_offset_ms = chart_offset_sec * 1000.0
	if absf(_chart_offset_ms) > 0.1:
		print("Game: chart offset = %.1f ms" % _chart_offset_ms)

	notes = parsed_notes
	lyric_phrases = parsed_lyrics
	overdrive_phrases = parsed_overdrive
	solo_sections = parsed_solos

	# Piano mode: fold lane 4 (orange) into the 4 lanes BEFORE playability,
	# so the same-lane spacing rules see the final lane layout.
	if song_mode == "piano":
		_merge_piano_lanes()

	# Apply playability processing
	var playability = PlayabilityScript.new()
	playability.apply_preset(song_preset)
	notes = playability.process(notes, parsed_resolution, lane_count)

	if song_mode == "piano":
		# Tiles mode: ensure no simultaneous notes after processing
		if song_preset == "Tiles":
			_dedup_simultaneous()
		# Safety net: never leave two same-lane notes closer than the min gap
		if not PlayabilityScript.is_assisted_preset(song_preset):
			_fix_piano_adjacent()

	_build_assist_clusters()

	_prepare_gameplay_sections()

	_build_beat_times(parsed_bpm, parsed_resolution)

	note_state.resize(notes.size())
	note_state.fill(0)
	first_visible_idx = 0
	current_phrase_idx = 0
	total_notes = notes.size()
	hit_count = 0
	miss_count = 0

	print("Game: [%s][%s][%s] %d notes, %d lyrics, %d OD, %d solos" % [
		song_instrument, song_mode, difficulty, notes.size(), lyric_phrases.size(),
		overdrive_phrases.size(), solo_sections.size()])

	is_loading = true
	loading_status = I18n.t("loading_audio_prep")
	if _is_stfs_source(source):
		# CON: audio already extracted to user://sng_temp
		_prepare_audio("user://sng_temp")
	elif sng_loader:
		var tmp_dir := "user://sng_temp"
		_clear_dir(tmp_dir)
		sng_loader.extract_to_dir(tmp_dir)
		_prepare_audio(tmp_dir)
	else:
		var audio_dir := source.get_base_dir()
		# On Android, res:// files are inside APK — copy to user:// for MediaCodec access.
		if OS.has_feature("android") and audio_dir.begins_with("res://"):
			var tmp_dir := "user://sng_temp"
			_clear_dir(tmp_dir)
			DirAccess.make_dir_recursive_absolute(tmp_dir)
			var dir := DirAccess.open(audio_dir)
			if dir:
				dir.list_dir_begin()
				var fname := dir.get_next()
				while fname != "":
					if not dir.current_is_dir():
						var fl := fname.to_lower()
						if fl.ends_with(".opus") or fl.ends_with(".ogg") or fl.ends_with(".mp3") or fl.ends_with(".wav"):
							var src_file := FileAccess.open(audio_dir.path_join(fname), FileAccess.READ)
							if src_file:
								var dst_file := FileAccess.open(tmp_dir.path_join(fname), FileAccess.WRITE)
								if dst_file:
									dst_file.store_buffer(src_file.get_buffer(src_file.get_length()))
									dst_file.close()
								src_file.close()
					fname = dir.get_next()
				dir.list_dir_end()
			_prepare_audio(tmp_dir)
		else:
			_prepare_audio(audio_dir)

# Precompute beat timestamps (ms) from the tempo map for scrolling beat lines.
func _build_beat_times(bpm_events: Array, res: int) -> void:
	beat_times = PackedFloat64Array()
	_beat_idx = 0
	if bpm_events.is_empty() or notes.is_empty() or res <= 0:
		return
	var last_ms: float = float(notes[notes.size() - 1]["time_ms"]) + 4000.0
	var tick := 0
	while true:
		var ms := ChartParserScript.tick_to_ms(tick, bpm_events, res)
		if ms > last_ms or beat_times.size() > 20000:
			break
		beat_times.append(ms)
		tick += res
	print("Game: %d beat lines built" % beat_times.size())

func _merge_piano_lanes() -> void:
	# Build occupied set: time_key -> set of occupied lanes (chord collision)
	var occupied := {}  # "time_key" -> Dictionary{lane: true}
	for n in notes:
		if int(n["lane"]) <= 3:
			var key := "%.1f" % float(n["time_ms"])
			if not occupied.has(key):
				occupied[key] = {}
			occupied[key][int(n["lane"])] = true

	# Place lane-4 (orange) notes gap-aware: avoid lanes that just had a note,
	# otherwise merged notes stack back-to-back in the same lane (blue-blue bug).
	var last_time := {}  # lane -> last note time_ms (built in time order)
	var merged: Array = []
	for n in notes:
		var t: float = n["time_ms"]
		if int(n["lane"]) == 4:
			var key := "%.1f" % t
			if not occupied.has(key):
				occupied[key] = {}
			# Prefer lane 3, but only if it has a comfortable time gap;
			# otherwise pick the free lane with the largest gap.
			var best_lane := -1
			var best_gap := -1.0
			for try_lane in [3, 2, 1, 0]:
				if occupied[key].has(try_lane):
					continue
				var gap := t - float(last_time.get(try_lane, -1e9))
				if gap >= 250.0:
					best_lane = try_lane
					break
				if gap > best_gap:
					best_gap = gap
					best_lane = try_lane
			if best_lane < 0:
				continue  # all 4 lanes occupied at this timestamp — drop note
			n["lane"] = best_lane
			occupied[key][best_lane] = true
		last_time[int(n["lane"])] = t
		merged.append(n)
	notes = merged

# Final guard for piano mode: no two notes in the same lane closer than the
# preset's same-lane gap — relocate the later note to the best other lane.
func _fix_piano_adjacent() -> void:
	var preset_cfg: Dictionary = PlayabilityScript.PRESETS.get(song_preset, {})
	var min_gap: float = float(preset_cfg.get("same_lane_min_ms", 150.0))

	var last_time := {}  # lane -> last note time_ms
	var result: Array = []
	var moved := 0
	var dropped := 0
	for n in notes:
		var lane: int = n["lane"]
		var t: float = n["time_ms"]
		if last_time.has(lane) and t - float(last_time[lane]) < min_gap:
			# Too close — find the lane with the largest time gap
			var cur_gap := t - float(last_time[lane])
			var best_lane := -1
			var best_gap := -1.0
			for try_lane in range(lane_count):
				if try_lane == lane:
					continue
				var gap := t - float(last_time.get(try_lane, -1e9))
				if gap > best_gap:
					best_gap = gap
					best_lane = try_lane
			if best_lane >= 0 and best_gap >= min_gap:
				n["lane"] = best_lane
				lane = best_lane
				moved += 1
			elif best_lane >= 0 and best_gap >= 60.0 and best_gap > cur_gap:
				# No lane is comfortable — take the least-bad one (but never
				# stack onto a simultaneous/near-simultaneous note)
				n["lane"] = best_lane
				lane = best_lane
				moved += 1
			else:
				dropped += 1
				continue
		last_time[lane] = t
		result.append(n)
	notes = result
	if moved > 0 or dropped > 0:
		print("Piano: adjacency fix — %d moved, %d dropped (min gap %.0f ms)" % [moved, dropped, min_gap])

func _dedup_simultaneous() -> void:
	# Keep only one note per timestamp (Tiles mode — no chords)
	var result: Array = []
	var last_time := -1.0
	for n in notes:
		var t: float = n["time_ms"]
		if absf(t - last_time) < 1.0:
			continue  # skip simultaneous
		result.append(n)
		last_time = t
	var removed := notes.size() - result.size()
	if removed > 0:
		print("Tiles: dedup removed %d simultaneous notes" % removed)
	notes = result

func _build_assist_clusters() -> void:
	_assist_clusters.clear()
	if not PlayabilityScript.is_assisted_preset(song_preset):
		return
	var cluster_window_ms := _assist_cluster_window_ms()
	var open_by_lane := {}
	for idx in range(notes.size()):
		var note: Dictionary = notes[idx]
		var lane := int(note["lane"])
		var note_time := float(note["time_ms"])
		if not open_by_lane.has(lane):
			open_by_lane[lane] = {"start_ms": note_time, "indices": [idx]}
			continue
		var open_group: Dictionary = open_by_lane[lane]
		if note_time - float(open_group["start_ms"]) <= cluster_window_ms:
			var group_indices: Array = open_group["indices"]
			group_indices.append(idx)
		else:
			_finalize_assist_cluster(open_group["indices"] as Array)
			open_by_lane[lane] = {"start_ms": note_time, "indices": [idx]}
	for lane in open_by_lane:
		var open_group: Dictionary = open_by_lane[lane]
		_finalize_assist_cluster(open_group["indices"] as Array)
	if not _assist_clusters.is_empty():
		print("Akici: %d impossible burst groups merged (<= %.0f ms)" % [
			_assist_clusters.size(), cluster_window_ms])

func _assist_cluster_window_ms() -> float:
	# At slow approach speeds, two notes can visibly overlap even when their time
	# gap looks reasonable in milliseconds. Derive a non-overlap gap from the
	# actual note size and travel distance, then keep a mobile comfort floor.
	if not is_inside_tree():
		return ASSIST_CLUSTER_MIN_MS
	var lane_width := _lane_width()
	var note_extent := lane_width * (GH_NOTE_FRET_RADIUS_RATIO * 2.0 if _gh_mode \
		else float(_lp()["note_h_ratio"]))
	var visual_gap_ms := _approach_time_ms() * note_extent / maxf(_hit_line_y(), 1.0) * 1.18
	return clampf(maxf(ASSIST_CLUSTER_MIN_MS, visual_gap_ms),
		ASSIST_CLUSTER_MIN_MS, ASSIST_CLUSTER_MAX_MS)

func _finalize_assist_cluster(indices: Array) -> void:
	if indices.size() <= 1:
		return
	var cluster_id := _assist_clusters.size()
	var members: Array[int] = []
	for value in indices:
		members.append(int(value))
	_assist_clusters[cluster_id] = members
	var leader_idx := members[0]
	var leader_time := float(notes[leader_idx]["time_ms"])
	var latest_sustain_end := leader_time + float(notes[leader_idx]["duration_ms"])
	for idx in members:
		latest_sustain_end = maxf(latest_sustain_end,
			float(notes[idx]["time_ms"]) + float(notes[idx]["duration_ms"]))
		notes[idx]["assist_cluster_id"] = cluster_id
		notes[idx]["assist_cluster_size"] = members.size()
		notes[idx]["assist_cluster_leader"] = idx == leader_idx
		if idx != leader_idx:
			notes[idx]["duration_ms"] = 0.0
	# One visible leader carries the longest authored tail; hidden members still
	# count toward score, accuracy, phrases and solos when the cluster is hit.
	notes[leader_idx]["duration_ms"] = maxf(0.0, latest_sustain_end - leader_time)

func _active_assist_cluster_indices(note_idx: int) -> Array[int]:
	var active: Array[int] = []
	var cluster_id := int(notes[note_idx].get("assist_cluster_id", -1))
	var members: Array = _assist_clusters.get(cluster_id, [note_idx])
	for value in members:
		var idx := int(value)
		if idx >= 0 and idx < note_state.size() and note_state[idx] == 0:
			active.append(idx)
	return active

# --- Audio decode pipeline ---

func _prepare_audio(dir_path: String) -> void:
	print("Audio: scanning stems in %s" % dir_path)

	# Check cache first
	var cache_key := song_source.md5_text()
	var cache_ext := "_mixed.wav" if OS.has_feature("android") else "_mixed.ogg"
	var cached_path := MIX_CACHE_DIR.path_join(cache_key + cache_ext)
	if FileAccess.file_exists(cached_path):
		print("Audio: found cached mix — %s" % cached_path)
		var stream := _load_cached(cached_path)
		if stream:
			_setup_single_player(stream)
			return
		push_error("Audio: cached file failed to load, re-processing")

	# List all audio files
	var all_audio: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir():
				var fl := fname.to_lower()
				if fl.ends_with(".opus") or fl.ends_with(".ogg") or fl.ends_with(".mp3") or fl.ends_with(".wav"):
					all_audio.append(fname)
			fname = dir.get_next()
		dir.list_dir_end()
	print("Audio: found files: %s" % str(all_audio))

	# Categorize: song.*, preview.*, stems — skip preview
	var all_playable: Array[String] = []
	for af: String in all_audio:
		var base := af.get_basename().to_lower()
		if base != "preview":
			all_playable.append(af)

	if all_playable.is_empty() and all_audio.size() > 0:
		all_playable.append(all_audio[0])

	if all_playable.is_empty():
		_show_audio_error(I18n.t("err_no_audio"))
		is_loading = false
		return

	# Build full paths
	var mix_paths: Array[String] = []
	for af in all_playable:
		mix_paths.append(dir_path.path_join(af))

	print("Audio: MIX — %d file(s): %s" % [all_playable.size(), str(all_playable)])

	DirAccess.make_dir_recursive_absolute(MIX_CACHE_DIR)

	# Build OS-level paths for native tools
	var os_inputs: Array[String] = []
	for sp in mix_paths:
		os_inputs.append(ProjectSettings.globalize_path(sp))
	var os_output := ProjectSettings.globalize_path(cached_path)

	loading_status = I18n.t("loading_audio_prep")
	print("Audio: processing %d file(s) → %s" % [mix_paths.size(), cached_path])

	if OS.has_feature("android"):
		# Async path — signals will handle completion
		_pending_cached_path = cached_path
		_decode_android_async(os_inputs, os_output)
	else:
		# Sync path — ffmpeg on desktop
		var success := _ffmpeg_desktop(os_inputs, os_output)
		if not success or not FileAccess.file_exists(cached_path):
			if FileAccess.file_exists(cached_path):
				DirAccess.remove_absolute(cached_path)
			_show_audio_error(I18n.t("err_audio_process"))
			is_loading = false
			return
		print("Audio: processing complete — %s" % cached_path)
		loading_status = I18n.t("loading_audio")
		var stream := _load_cached(cached_path)
		if stream == null:
			_show_audio_error(I18n.t("err_audio_load"))
			is_loading = false
			return
		_setup_single_player(stream)

func _load_cached(path: String) -> AudioStream:
	if path.ends_with(".wav"):
		return _load_wav_file(path)
	return AudioStreamOggVorbis.load_from_file(path)

func _setup_single_player(stream: AudioStream) -> void:
	_ensure_music_audio_bus()
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "Music"
	add_child(player)
	audio_players.append(player)
	master_player = player
	print("Audio: 1 player ready")
	is_loading = false
	_countdown = 3.0


func _decode_android_async(inputs: Array[String], output: String) -> void:
	if not Engine.has_singleton("NativeAudioDecoder"):
		push_error("Audio: NativeAudioDecoder singleton not found!")
		_show_audio_error(I18n.t("err_no_decoder"))
		is_loading = false
		return
	_decode_plugin = Engine.get_singleton("NativeAudioDecoder")
	_pending_cached_path = output

	# Connect signals (one-shot)
	if not _decode_plugin.is_connected("decode_progress", _on_decode_progress):
		_decode_plugin.connect("decode_progress", _on_decode_progress)
	if not _decode_plugin.is_connected("decode_done", _on_decode_done):
		_decode_plugin.connect("decode_done", _on_decode_done)
	if not _decode_plugin.is_connected("decode_failed", _on_decode_failed):
		_decode_plugin.connect("decode_failed", _on_decode_failed)

	_decode_plugin.call("decodeAndMix", inputs, output)

func _on_decode_progress(pct: int, stage: String) -> void:
	loading_progress = pct
	loading_status = stage

func _on_decode_done(wav_path: String) -> void:
	print("Audio: decode_done — %s" % wav_path)
	# Convert globalized path back to user:// path
	var cached_path := _pending_cached_path
	if not FileAccess.file_exists(cached_path):
		# Try the raw path
		cached_path = wav_path
	loading_status = I18n.t("loading_audio")
	loading_progress = 95
	var stream := _load_cached(cached_path)
	if stream == null:
		_show_audio_error(I18n.t("err_audio_load"))
		is_loading = false
		return
	_setup_single_player(stream)

func _on_decode_failed(error: String) -> void:
	push_error("Audio: NativeAudioDecoder failed — %s" % error)
	if error == "Cancelled":
		return  # User navigated away, don't show error
	_show_audio_error(I18n.t("err_audio_process"))
	is_loading = false

func _ffmpeg_desktop(inputs: Array[String], output: String) -> bool:
	var args: Array = ["-hide_banner"]
	for inp in inputs:
		args.append("-i")
		args.append(inp)
	if inputs.size() == 1:
		var ch_count := _ffprobe_channel_count(inputs[0])
		if ch_count > 2:
			# Multi-channel (MOGG): explicit pan filter mixing even→L, odd→R
			var left := ""
			var right := ""
			var scale := "%.4f" % (1.0 / ((ch_count + 1) / 2))
			for c in range(ch_count):
				var term := "%s*c%d" % [scale, c]
				if c % 2 == 0:
					left += ("+" if left != "" else "") + term
				else:
					right += ("+" if right != "" else "") + term
			if right == "":
				right = left
			var pan_filter := "pan=stereo|c0=%s|c1=%s" % [left, right]
			print("Audio: pan filter = %s" % pan_filter)
			args.append_array(["-af", pan_filter, "-c:a", "libvorbis", "-q:a", "6"])
		else:
			args.append_array(["-ac", "2", "-c:a", "libvorbis", "-q:a", "6"])
	else:
		args.append_array(["-filter_complex",
			"amix=inputs=%d:duration=longest:normalize=0" % inputs.size(),
			"-ac", "2", "-c:a", "libvorbis", "-q:a", "6"])
	args.append_array(["-y", output])

	print("Audio: ffmpeg %s" % str(args))
	var cmd_output: Array = []
	var code := OS.execute("ffmpeg", args, cmd_output, true)
	if code != 0:
		print("Audio: ffmpeg failed (exit %d)" % code)
		for line in cmd_output:
			print("  ffmpeg: %s" % str(line))
		return false
	return true

func _ffprobe_channel_count(path: String) -> int:
	var probe_output: Array = []
	var code := OS.execute("ffprobe", [
		"-v", "error", "-select_streams", "a:0",
		"-show_entries", "stream=channels",
		"-of", "csv=p=0", path
	], probe_output, true)
	if code != 0 or probe_output.is_empty():
		return 2
	var text: String = probe_output[0] if probe_output.size() > 0 else "2"
	var count := int(text.strip_edges())
	print("Audio: ffprobe found %d channels in %s" % [count, path.get_file()])
	return maxi(count, 1)

func _is_stfs_source(path: String) -> bool:
	var fl := path.to_lower()
	if fl.ends_with(".con") or fl.ends_with(".live"):
		return true
	# Check magic bytes for extensionless files (rb3con etc.)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 4:
		if f: f.close()
		return false
	var magic := f.get_buffer(4).get_string_from_ascii()
	f.close()
	return magic == "CON " or magic == "LIVE" or magic == "PIRS"

func _clear_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			dir.remove(fname)
		fname = dir.get_next()
	dir.list_dir_end()

func _load_wav_file(path: String) -> AudioStream:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Audio: cannot open WAV: %s" % path)
		return null
	var data := f.get_buffer(f.get_length())
	f.close()
	if data.size() < 44:
		push_error("Audio: WAV too small: %s" % path)
		return null
	var channels := data.decode_u16(22)
	var sample_rate := data.decode_u32(24)
	var bits := data.decode_u16(34)
	var data_offset := 44
	for i in range(36, mini(data.size() - 8, 200)):
		if data[i] == 0x64 and data[i+1] == 0x61 and data[i+2] == 0x74 and data[i+3] == 0x61:
			data_offset = i + 8
			break
	var pcm_data := data.slice(data_offset)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = sample_rate
	wav.stereo = (channels == 2)
	wav.data = pcm_data
	print("Audio: WAV loaded — %d ch, %d Hz, %d bytes" % [channels, sample_rate, pcm_data.size()])
	return wav

func _show_audio_error(msg: String) -> void:
	if loading_status_label:
		loading_status_label.text = msg
		loading_status_label.add_theme_color_override("font_color", Color(1, 0.3, 0.2))
	if loading_bar:
		loading_bar.visible = false
	if warning_label:
		warning_label.text = msg
		warning_label.visible = true

# --- Overdrive, solos and crowd ---

func _prepare_gameplay_sections() -> void:
	_overdrive_states.clear()
	_solo_states.clear()
	_solo_result_scores.clear()
	_active_solo_idx = -1
	_perfect_streak = 0
	_crowd_mistake_count = 0
	_crowd_mistake_threshold = CROWD_MISTAKES_BEFORE_BOO
	_crowd_recovery_perfects = 0
	_crowd_last_mistake_song_ms = -1000.0
	_last_miss_sfx_song_ms = -1000.0
	_crowd_pending_boo = false
	_crowd_performance_started = false
	_ending_crowd_triggered = false
	_crowd_ambience_boost_timer = 0.0
	_overdrive_energy = 0.0
	_overdrive_active = false
	if debug_infinite_overdrive and OS.is_debug_build():
		_overdrive_energy = 1.0

	# Plain MIDI files and older .chart files often omit authored Overdrive.
	# Create sparse eight-note phrases so the mechanic still exists, while
	# preferring authored ranges whenever they are present.
	if overdrive_phrases.is_empty() and notes.size() >= 48:
		var start_idx := 16
		while start_idx + 7 < notes.size() - 8:
			var end_idx := mini(start_idx + 7, notes.size() - 1)
			overdrive_phrases.append({
				"start_ms": float(notes[start_idx]["time_ms"]) - 5.0,
				"end_ms": float(notes[end_idx]["time_ms"]) + 5.0,
			})
			start_idx += 32

	for phrase_idx in range(overdrive_phrases.size()):
		var phrase: Dictionary = overdrive_phrases[phrase_idx]
		var state := {"total": 0, "hit": 0, "failed": false, "awarded": false}
		for note_idx in range(notes.size()):
			var note_time := float(notes[note_idx]["time_ms"])
			if note_time >= float(phrase["start_ms"]) - 10.0 and note_time <= float(phrase["end_ms"]) + 10.0:
				notes[note_idx]["overdrive_phrase"] = phrase_idx
				state["total"] = int(state["total"]) + 1
		_overdrive_states.append(state)

	for solo_idx in range(solo_sections.size()):
		var section: Dictionary = solo_sections[solo_idx]
		var state := {"total": 0, "hit": 0, "perfect": 0, "good": 0, "miss": 0, "completed": false}
		for note_idx in range(notes.size()):
			var note_time := float(notes[note_idx]["time_ms"])
			if note_time >= float(section["start_ms"]) - 10.0 and note_time <= float(section["end_ms"]) + 10.0:
				notes[note_idx]["solo_section"] = solo_idx
				state["total"] = int(state["total"]) + 1
		_solo_states.append(state)
	_update_overdrive_ui()

func _register_gameplay_hit(note_idx: int, judgment: String) -> void:
	_crowd_performance_started = true
	if judgment == "perfect":
		_register_crowd_perfect()
	else:
		# Recovery requires consecutive Perfect judgments; Good keeps the old
		# mistake debt but starts the five-Perfect recovery group over.
		_crowd_recovery_perfects = 0
	var note: Dictionary = notes[note_idx]
	var phrase_idx := int(note.get("overdrive_phrase", -1))
	if phrase_idx >= 0 and phrase_idx < _overdrive_states.size():
		var phrase_state: Dictionary = _overdrive_states[phrase_idx]
		phrase_state["hit"] = int(phrase_state["hit"]) + 1
		if not bool(phrase_state["failed"]) and not bool(phrase_state["awarded"]) \
				and int(phrase_state["total"]) > 0 and int(phrase_state["hit"]) >= int(phrase_state["total"]):
			phrase_state["awarded"] = true
			_overdrive_energy = minf(1.0, _overdrive_energy + OVERDRIVE_PHRASE_GAIN)
			_show_milestone(I18n.t("overdrive_phrase"))
			_update_overdrive_ui()

	var solo_idx := int(note.get("solo_section", -1))
	if solo_idx >= 0 and solo_idx < _solo_states.size():
		var solo_state: Dictionary = _solo_states[solo_idx]
		solo_state["hit"] = int(solo_state["hit"]) + 1
		solo_state[judgment] = int(solo_state[judgment]) + 1

func _register_gameplay_miss(note_idx: int) -> void:
	var note: Dictionary = notes[note_idx]
	var phrase_idx := int(note.get("overdrive_phrase", -1))
	if phrase_idx >= 0 and phrase_idx < _overdrive_states.size():
		_overdrive_states[phrase_idx]["failed"] = true
	var solo_idx := int(note.get("solo_section", -1))
	if solo_idx >= 0 and solo_idx < _solo_states.size():
		_solo_states[solo_idx]["miss"] = int(_solo_states[solo_idx]["miss"]) + 1

func _activate_overdrive() -> void:
	if not song_started or _paused:
		return
	if _overdrive_active:
		if debug_infinite_overdrive and OS.is_debug_build():
			_overdrive_active = false
			_update_overdrive_ui()
		return
	if _overdrive_energy < OVERDRIVE_ACTIVATION_MIN:
		return
	_overdrive_active = true
	_show_milestone(I18n.t("overdrive_active"))
	_play_crowd_reaction(_crowd_cheer_stream, true)
	if OS.has_feature("android"):
		Input.vibrate_handheld(45)
	_update_overdrive_ui()

func _score_multiplier() -> float:
	return _combo_multiplier * (OVERDRIVE_SCORE_MULTIPLIER if _overdrive_active else 1.0)

func _update_overdrive_ui() -> void:
	if overdrive_bar:
		overdrive_bar.value = _overdrive_energy
	if overdrive_button:
		var infinite_debug := debug_infinite_overdrive and OS.is_debug_build()
		var new_state := 3 if _overdrive_active and infinite_debug else \
			(2 if _overdrive_active else (1 if _overdrive_energy >= OVERDRIVE_ACTIVATION_MIN else 0))
		if new_state == _overdrive_ui_state:
			return
		_overdrive_ui_state = new_state
		overdrive_button.disabled = new_state == 2 or new_state == 0
		if new_state >= 2:
			overdrive_button.text = I18n.t("overdrive_stop") if infinite_debug else I18n.t("overdrive_active")
			overdrive_button.modulate = Color(1.0, 0.72, 1.0)
		elif new_state == 1:
			overdrive_button.text = I18n.t("overdrive_ready")
			overdrive_button.modulate = Color.WHITE
		else:
			overdrive_button.text = I18n.t("overdrive")
			overdrive_button.modulate = Color(0.68, 0.72, 0.82)

func _update_gameplay_sections(delta: float) -> void:
	if _overdrive_active:
		if not (debug_infinite_overdrive and OS.is_debug_build()):
			_overdrive_energy = maxf(0.0, _overdrive_energy - OVERDRIVE_DRAIN_PER_SEC * delta)
		if _overdrive_energy <= 0.0:
			_overdrive_active = false
		_update_overdrive_ui()
	elif debug_infinite_overdrive and OS.is_debug_build() and _overdrive_energy < 1.0:
		_overdrive_energy = 1.0
		_update_overdrive_ui()

	var new_solo_idx := -1
	for idx in range(solo_sections.size()):
		var section: Dictionary = solo_sections[idx]
		if song_time_ms >= float(section["start_ms"]) and song_time_ms <= float(section["end_ms"]):
			new_solo_idx = idx
			break
	if new_solo_idx != _active_solo_idx:
		if _active_solo_idx >= 0:
			_finish_solo(_active_solo_idx)
		_active_solo_idx = new_solo_idx
		if _active_solo_idx >= 0:
			_start_solo(_active_solo_idx)
	if _active_solo_idx >= 0 and solo_label:
		var active_state: Dictionary = _solo_states[_active_solo_idx]
		solo_label.text = "%s  %d/%d" % [I18n.t("solo"), int(active_state["hit"]), int(active_state["total"])]

	_update_crowd_audio(delta)

func _auto_perfect_overdrive_notes() -> void:
	if not _overdrive_active:
		return
	# Trigger at the hit line (with one-frame tolerance) so Overdrive genuinely
	# protects the streak instead of merely widening the normal hit window.
	var due_notes: Array[int] = []
	for idx in range(first_visible_idx, notes.size()):
		var note_time := float(notes[idx]["time_ms"])
		if note_time > song_time_ms + 16.0:
			break
		if note_state[idx] == 0 and note_time <= song_time_ms + 16.0:
			due_notes.append(idx)
	for idx in due_notes:
		if note_state[idx] != 0:
			continue
		notes[idx]["overdrive_auto_hit"] = true
		_try_hit(int(notes[idx]["lane"]), "perfect")

func _start_solo(_idx: int) -> void:
	if _solo_label_tw and _solo_label_tw.is_valid():
		_solo_label_tw.kill()
	if solo_label:
		solo_label.modulate.a = 1.0
		solo_label.visible = true

func _finish_solo(idx: int) -> void:
	if idx < 0 or idx >= _solo_states.size():
		return
	var state: Dictionary = _solo_states[idx]
	if bool(state["completed"]):
		return
	state["completed"] = true
	var total := maxi(1, int(state["total"]))
	var percent := clampf((float(state["perfect"]) + float(state["good"]) * 0.5) / float(total) * 100.0, 0.0, 100.0)
	_solo_result_scores.append(percent)
	var bonus := 0
	if percent >= 100.0: bonus = 5000
	elif percent >= 95.0: bonus = 3000
	elif percent >= 90.0: bonus = 2000
	elif percent >= 80.0: bonus = 1000
	score += bonus
	if solo_label:
		solo_label.text = I18n.t("solo_result", [int(roundf(percent))])
		if bonus > 0:
			solo_label.text += "  " + I18n.t("solo_bonus", [bonus])
		solo_label.visible = true
		solo_label.modulate.a = 1.0
		_solo_label_tw = create_tween()
		_solo_label_tw.tween_interval(1.5)
		_solo_label_tw.tween_property(solo_label, "modulate:a", 0.0, 0.35)
		_solo_label_tw.tween_callback(func(): solo_label.visible = false)
	var flawless := int(state["total"]) > 0 and int(state["miss"]) == 0 \
		and int(state["hit"]) >= int(state["total"])
	if flawless:
		_play_flawless_solo_cheers()
	elif percent >= 90.0:
		_play_crowd_reaction(_crowd_cheer_stream, true)

func _setup_crowd_audio() -> void:
	if not Settings.crowd_audio_enabled:
		return
	_crowd_ambience_streams = _load_crowd_stream_pool("crowd_ambience")
	_crowd_cheer_streams = _load_crowd_stream_pool("crowd_cheer")
	_crowd_boo_streams = _load_crowd_stream_pool("crowd_boo")
	if _crowd_ambience_streams.is_empty() or _crowd_cheer_streams.is_empty() \
			or _crowd_boo_streams.is_empty() or not ResourceLoader.exists(CROWD_APPLAUSE_STRONG_PATH) \
			or not ResourceLoader.exists(CROWD_APPLAUSE_LIGHT_PATH):
		push_warning("Crowd audio assets are unavailable; continuing without crowd audio")
		return
	var ambience_stream := _pick_crowd_ambience_stream()
	_crowd_cheer_stream = _crowd_cheer_streams[0]
	_crowd_boo_stream = _crowd_boo_streams[0]
	_crowd_applause_strong_stream = ResourceLoader.load(CROWD_APPLAUSE_STRONG_PATH) as AudioStream
	_crowd_applause_light_stream = ResourceLoader.load(CROWD_APPLAUSE_LIGHT_PATH) as AudioStream
	_ensure_crowd_audio_bus()
	if ambience_stream is AudioStreamMP3:
		(ambience_stream as AudioStreamMP3).loop = true
	_crowd_ambience = AudioStreamPlayer.new()
	_crowd_ambience.stream = ambience_stream
	_crowd_ambience.volume_db = -36.0
	_crowd_ambience.bus = "Crowd"
	add_child(_crowd_ambience)
	_crowd_reaction = AudioStreamPlayer.new()
	_crowd_reaction.volume_db = -8.0
	_crowd_reaction.bus = "Crowd"
	add_child(_crowd_reaction)
	print("Crowd audio: %d ambience, %d cheer, %d boo variants" % [
		_crowd_ambience_streams.size(), _crowd_cheer_streams.size(), _crowd_boo_streams.size()])

func _load_crowd_stream_pool(prefix: String) -> Array[AudioStream]:
	var pool: Array[AudioStream] = []
	var paths: Array
	match prefix:
		"crowd_ambience":
			paths = CROWD_AMBIENCE_PATHS
		"crowd_cheer":
			paths = CROWD_CHEER_PATHS
		"crowd_boo":
			paths = CROWD_BOO_PATHS
		_:
			push_warning("Unknown crowd audio pool: %s" % prefix)
			return pool
	# Exported projects expose imported audio as .import entries to DirAccess.
	# Explicit ResourceLoader paths work in both the editor and Android APKs.
	for path in paths:
		if ResourceLoader.exists(path):
			var loaded := ResourceLoader.load(path) as AudioStream
			if loaded:
				pool.append(loaded)
		else:
			push_warning("Crowd audio resource is missing: %s" % path)
	return pool

func _pick_nonrepeating_index(pool_size: int, previous_idx: int) -> int:
	if pool_size <= 1:
		return 0
	if previous_idx < 0 or previous_idx >= pool_size:
		return randi_range(0, pool_size - 1)
	var picked := randi_range(0, pool_size - 2)
	if picked >= previous_idx:
		picked += 1
	return picked

func _pick_crowd_ambience_stream() -> AudioStream:
	var candidates: Array[int] = []
	for idx in range(_crowd_ambience_streams.size()):
		if _crowd_ambience_streams[idx].resource_path != _last_crowd_ambience_path:
			candidates.append(idx)
	if candidates.is_empty():
		candidates.append(0)
	var picked_idx: int = candidates[randi_range(0, candidates.size() - 1)]
	var picked := _crowd_ambience_streams[picked_idx]
	_last_crowd_ambience_path = picked.resource_path
	return picked

func _resolve_crowd_reaction_stream(requested: AudioStream) -> AudioStream:
	if requested == _crowd_cheer_stream and not _crowd_cheer_streams.is_empty():
		_crowd_last_cheer_idx = _pick_nonrepeating_index(
			_crowd_cheer_streams.size(), _crowd_last_cheer_idx)
		return _crowd_cheer_streams[_crowd_last_cheer_idx]
	if requested == _crowd_boo_stream and not _crowd_boo_streams.is_empty():
		_crowd_last_boo_idx = _pick_nonrepeating_index(
			_crowd_boo_streams.size(), _crowd_last_boo_idx)
		return _crowd_boo_streams[_crowd_last_boo_idx]
	return requested

func _ensure_crowd_audio_bus() -> void:
	var bus_idx := AudioServer.get_bus_index("Crowd")
	if bus_idx < 0:
		AudioServer.add_bus()
		bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_idx, "Crowd")
	AudioServer.set_bus_send(bus_idx, "Master")
	AudioServer.set_bus_volume_db(bus_idx, CROWD_BUS_GAIN_DB)
	# A shared, subtle room tail makes the independently sourced ambience,
	# cheers, boos and applause sound like the same venue.
	var has_reverb := false
	for effect_idx in range(AudioServer.get_bus_effect_count(bus_idx)):
		if AudioServer.get_bus_effect(bus_idx, effect_idx) is AudioEffectReverb:
			has_reverb = true
			break
	if not has_reverb:
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.58
		reverb.damping = 0.72
		reverb.spread = 0.82
		reverb.dry = 0.93
		reverb.wet = 0.16
		AudioServer.add_bus_effect(bus_idx, reverb)
	# Reactions are intentionally louder than the ambience bed. Catch occasional
	# source-recording peaks so the extra presence never turns into a harsh spike.
	var has_limiter := false
	for effect_idx in range(AudioServer.get_bus_effect_count(bus_idx)):
		if AudioServer.get_bus_effect(bus_idx, effect_idx) is AudioEffectLimiter:
			has_limiter = true
			break
	if not has_limiter:
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		limiter.threshold_db = -3.0
		limiter.soft_clip_db = 2.0
		limiter.soft_clip_ratio = 8.0
		AudioServer.add_bus_effect(bus_idx, limiter)

func _ensure_music_audio_bus() -> void:
	var bus_idx := AudioServer.get_bus_index("Music")
	if bus_idx < 0:
		AudioServer.add_bus()
		bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_idx, "Music")
	AudioServer.set_bus_send(bus_idx, "Master")
	AudioServer.set_bus_volume_db(bus_idx, MUSIC_BUS_GAIN_DB)
	# Some community charts are mastered much quieter than others. The bus gain
	# keeps them in front of the venue while this limiter catches loud peaks.
	var has_limiter := false
	for effect_idx in range(AudioServer.get_bus_effect_count(bus_idx)):
		if AudioServer.get_bus_effect(bus_idx, effect_idx) is AudioEffectLimiter:
			has_limiter = true
			break
	if not has_limiter:
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -0.5
		limiter.threshold_db = -3.0
		limiter.soft_clip_db = 2.0
		limiter.soft_clip_ratio = 8.0
		AudioServer.add_bus_effect(bus_idx, limiter)

func _ensure_sfx_audio_bus() -> void:
	var bus_idx := AudioServer.get_bus_index("SFX")
	if bus_idx < 0:
		AudioServer.add_bus()
		bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_idx, "SFX")
	AudioServer.set_bus_send(bus_idx, "Master")
	AudioServer.set_bus_volume_db(bus_idx, SFX_BUS_GAIN_DB)

func _setup_miss_sfx() -> void:
	if not Settings.miss_sfx_enabled or not ResourceLoader.exists(MISS_SFX_PATH):
		return
	_ensure_sfx_audio_bus()
	_miss_sfx_player = AudioStreamPlayer.new()
	_miss_sfx_player.stream = load(MISS_SFX_PATH)
	_miss_sfx_player.bus = "SFX"
	_miss_sfx_player.volume_db = -7.0
	add_child(_miss_sfx_player)

func _play_miss_sfx() -> void:
	if _miss_sfx_player == null or not Settings.miss_sfx_enabled:
		return
	# A chord can produce several misses in one frame. One guitar error is enough.
	if song_time_ms - _last_miss_sfx_song_ms < 140.0:
		return
	_last_miss_sfx_song_ms = song_time_ms
	_miss_sfx_player.stop()
	_miss_sfx_player.pitch_scale = randf_range(0.97, 1.03)
	_miss_sfx_player.play()
	_duck_music_for_miss_sfx()

func _duck_music_for_miss_sfx() -> void:
	# Duck only belongs to the optional guitar miss cue. If the cue is disabled,
	# _play_miss_sfx exits before reaching this function and music is untouched.
	var music_bus_idx := AudioServer.get_bus_index("Music")
	if music_bus_idx < 0:
		return
	if _music_duck_tween and _music_duck_tween.is_valid():
		_music_duck_tween.kill()
	var ducked_db := MUSIC_BUS_GAIN_DB - MISS_SFX_MUSIC_DUCK_DB
	AudioServer.set_bus_volume_db(music_bus_idx, ducked_db)
	_music_duck_tween = create_tween()
	_music_duck_tween.tween_interval(MISS_SFX_DUCK_HOLD_SEC)
	_music_duck_tween.tween_method(
		func(volume_db: float): AudioServer.set_bus_volume_db(music_bus_idx, volume_db),
		ducked_db, MUSIC_BUS_GAIN_DB, MISS_SFX_DUCK_RECOVERY_SEC
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _play_crowd_reaction(stream: AudioStream, _urgent: bool = false, volume_db: float = -8.0) -> bool:
	if _crowd_reaction == null or stream == null:
		return false
	if _ending_crowd_triggered:
		return false
	# No applause during an intro/rest before the player's first playable note.
	if stream == _crowd_cheer_stream and not _crowd_performance_started:
		return false
	# A boo earned by mistakes or the red Rock Meter owns the next available
	# reaction slot, so frequent combo/solo cheers cannot starve it forever.
	if stream == _crowd_cheer_stream and _crowd_pending_boo:
		return false
	# All reactions share one gate. An overdrive, solo, combo or danger event can
	# no longer interrupt this ten-second breathing room with an "urgent" call.
	if _crowd_reaction_cooldown > 0.0:
		return false
	var chosen_stream := _resolve_crowd_reaction_stream(stream)
	# Keep the ambience bed untouched and raise only event reactions. The Crowd
	# bus limiter catches peaks, while these caps prevent future call sites from
	# accidentally making a reaction uncomfortably loud.
	if stream == _crowd_boo_stream:
		volume_db = clampf(volume_db, CROWD_BOO_REACTION_DB, -5.0)
	elif stream == _crowd_cheer_stream:
		volume_db = clampf(volume_db, CROWD_CHEER_REACTION_DB, 3.0)
	if _crowd_reaction_fade_tween and _crowd_reaction_fade_tween.is_valid():
		_crowd_reaction_fade_tween.kill()
	_crowd_reaction.stop()
	_crowd_reaction.stream = chosen_stream
	if stream == _crowd_cheer_stream or stream == _crowd_boo_stream:
		_crowd_reaction_fade_tween = _play_crowd_reaction_with_fade(_crowd_reaction, volume_db)
	else:
		_crowd_reaction.volume_db = volume_db
		_crowd_reaction.play()
	_crowd_reaction_cooldown = CROWD_REACTION_COOLDOWN_SEC
	if _crowd_ambience:
		_crowd_ambience_boost_timer = maxf(_crowd_ambience_boost_timer,
			clampf(chosen_stream.get_length(), 2.5, 6.0))
	return true

func _play_crowd_reaction_with_fade(player: AudioStreamPlayer, target_db: float) -> Tween:
	var playback_duration := 0.0
	if player.stream:
		playback_duration = player.stream.get_length() / maxf(player.pitch_scale, 0.01)
	var fade_in := minf(CROWD_REACTION_FADE_IN_SEC, playback_duration * 0.25)
	var fade_out := minf(CROWD_REACTION_FADE_OUT_SEC, playback_duration * 0.35)
	var steady_duration := maxf(0.0, playback_duration - fade_in - fade_out)
	var quiet_db := target_db - CROWD_REACTION_FADE_RANGE_DB
	player.volume_db = quiet_db
	player.play()
	var fade_tween := create_tween().bind_node(player)
	fade_tween.tween_property(player, "volume_db", target_db, fade_in) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if steady_duration > 0.0:
		fade_tween.tween_interval(steady_duration)
	fade_tween.tween_property(player, "volume_db", quiet_db, fade_out) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	return fade_tween

func _request_crowd_boo(urgent: bool = false, volume_db: float = -8.0) -> bool:
	var started := _play_crowd_reaction(_crowd_boo_stream, urgent, volume_db)
	if started:
		_crowd_pending_boo = false
	elif _crowd_boo_stream != null and not _ending_crowd_triggered:
		# Keep the ten-second gate strict, but retain the earned reaction until
		# the gate opens instead of silently discarding it.
		_crowd_pending_boo = true
	return started

func _register_crowd_mistake() -> void:
	# Chords can miss several notes on the same frame; the audience should hear
	# that as one mistake, not three instant strikes against the player.
	if song_time_ms - _crowd_last_mistake_song_ms < 140.0:
		return
	_crowd_last_mistake_song_ms = song_time_ms
	_crowd_recovery_perfects = 0
	_crowd_mistake_count += 1
	if _crowd_mistake_count >= _crowd_mistake_threshold:
		_crowd_mistake_count = 0
		_crowd_mistake_threshold = CROWD_MISTAKES_BEFORE_BOO
		_request_crowd_boo(true)

func _register_crowd_perfect() -> void:
	if _crowd_mistake_count <= 0:
		_crowd_recovery_perfects = 0
		return
	_crowd_recovery_perfects += 1
	if _crowd_recovery_perfects >= CROWD_PERFECTS_PER_MISTAKE_RECOVERY:
		_crowd_recovery_perfects = 0
		_crowd_mistake_count = maxi(0, _crowd_mistake_count - 1)

func _register_solo_fault() -> void:
	if _active_solo_idx < 0 or _active_solo_idx >= _solo_states.size():
		return
	_solo_states[_active_solo_idx]["miss"] = int(_solo_states[_active_solo_idx]["miss"]) + 1

func _play_flawless_solo_cheers() -> void:
	if _crowd_cheer_stream == null or not Settings.crowd_audio_enabled \
			or _crowd_reaction_cooldown > 0.0 or _ending_crowd_triggered \
			or _crowd_pending_boo:
		return
	_crowd_reaction_cooldown = CROWD_REACTION_COOLDOWN_SEC
	_crowd_ambience_boost_timer = maxf(_crowd_ambience_boost_timer, 6.0)
	var burst_stream := _resolve_crowd_reaction_stream(_crowd_cheer_stream)
	var layer_count := randi_range(5, 6)
	for layer_idx in range(layer_count):
		if layer_idx == 0:
			_spawn_crowd_cheer_layer(layer_idx, burst_stream)
		else:
			var timer := get_tree().create_timer(float(layer_idx) * 0.14)
			timer.timeout.connect(_spawn_crowd_cheer_layer.bind(layer_idx, burst_stream))

func _spawn_crowd_cheer_layer(layer_idx: int, cheer_stream: AudioStream) -> void:
	if cheer_stream == null or not is_inside_tree():
		return
	var player := AudioStreamPlayer.new()
	player.stream = cheer_stream
	player.volume_db = CROWD_BURST_LAYER_DB + randf_range(-1.0, 0.8)
	player.pitch_scale = clampf(0.94 + float(layer_idx) * 0.018 + randf_range(-0.012, 0.012), 0.90, 1.08)
	player.bus = "Crowd"
	add_child(player)
	_crowd_burst_players.append(player)
	player.finished.connect(_on_crowd_burst_finished.bind(player))
	_play_crowd_reaction_with_fade(player, player.volume_db)

func _on_crowd_burst_finished(player: AudioStreamPlayer) -> void:
	_crowd_burst_players.erase(player)
	if is_instance_valid(player):
		player.queue_free()

func _stop_crowd_burst_players() -> void:
	for player in _crowd_burst_players:
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	_crowd_burst_players.clear()

func _update_crowd_audio(delta: float) -> void:
	_crowd_reaction_cooldown = maxf(0.0, _crowd_reaction_cooldown - delta)
	_crowd_ambience_boost_timer = maxf(0.0, _crowd_ambience_boost_timer - delta)
	var new_zone := 2 if _rock_meter_value >= ROCK_METER_GREEN_THRESHOLD else (1 if _rock_meter_value >= ROCK_METER_DANGER_THRESHOLD else 0)
	if new_zone == 0 and _crowd_zone > 0:
		# Entering the red Rock Meter zone is an immediate crowd event. This is
		# separate from the accumulated 5–6 mistake patience counter below.
		_request_crowd_boo()
	_crowd_zone = new_zone
	if _crowd_pending_boo and _crowd_reaction_cooldown <= 0.0 \
			and not _ending_crowd_triggered:
		_request_crowd_boo()
	if _crowd_ambience:
		# Neutral stadium murmur only: energetic reactions remain event-driven.
		var target_db := -29.0 if new_zone == 2 else (-34.0 if new_zone == 1 else -40.0)
		if _overdrive_active:
			target_db = -25.0
		if _crowd_ambience_boost_timer > 0.0:
			# Lift the neutral bed under reactions instead of playing a dry,
			# disconnected sample over near-silence.
			target_db = maxf(target_db, -26.0)
		_crowd_ambience.volume_db = lerpf(_crowd_ambience.volume_db, target_db, 1.0 - exp(-delta * 1.6))

func _update_ending_crowd() -> void:
	if _ending_crowd_triggered or master_player == null or master_player.stream == null \
			or not master_player.playing:
		return
	var song_length_sec := master_player.stream.get_length()
	if song_length_sec <= ENDING_CROWD_LEAD_SEC + 2.0:
		return
	var remaining_sec := song_length_sec - master_player.get_playback_position()
	if remaining_sec > ENDING_CROWD_LEAD_SEC:
		return
	# Match the reaction to the meter the player can actually see. More
	# importantly, a stale boo queued earlier in the song must never jump ahead
	# of a positive green/yellow finale when its ten-second gate opens.
	var ending_meter := _rock_meter_display if _rock_meter_mode != "off" else _rock_meter_value
	if ending_meter >= ROCK_METER_DANGER_THRESHOLD:
		_crowd_pending_boo = false
	var reaction_started := false
	if ending_meter >= ENDING_STRONG_THRESHOLD:
		reaction_started = _play_crowd_reaction(_crowd_applause_strong_stream, true, -5.0)
	elif ending_meter >= ROCK_METER_DANGER_THRESHOLD:
		reaction_started = _play_crowd_reaction(_crowd_applause_light_stream, true, -13.0)
	else:
		reaction_started = _play_crowd_reaction(_crowd_boo_stream, true, -7.0)
	# Lock normal combo/solo reactions so they cannot cut the finale short.
	# If the shared cooldown is active, retry during the remaining outro instead
	# of silently marking an unheard finale as completed.
	if reaction_started:
		_ending_crowd_triggered = true

# --- Playback ---

func _start_playback() -> void:
	song_started = true
	_first_hit_logged = false
	_hit_log_count = 0
	_start_ticks = Time.get_ticks_msec()
	_play_call_time_ms = _start_ticks
	for player in audio_players:
		player.play()
	if _crowd_ambience:
		var ambience_length := _crowd_ambience.stream.get_length()
		var ambience_start := randf_range(0.0, maxf(0.0, ambience_length - 1.0))
		_crowd_ambience.play(ambience_start)
	print("Sync: play() at ticks=%d, %d players, chart_offset=%.1fms" % [
		_play_call_time_ms, audio_players.size(), _chart_offset_ms])

func _get_song_time_ms() -> float:
	if not master_player:
		return 0.0
	if not master_player.playing:
		return song_time_ms
	var t := master_player.get_playback_position()
	t += AudioServer.get_time_since_last_mix()
	t -= AudioServer.get_output_latency()
	return t * 1000.0 + _chart_offset_ms + audio_offset_ms

# --- Main loop ---

func _effective_vfx_quality() -> String:
	return "performance" if _vfx_quality == "balanced" and _adaptive_vfx_reduced else _vfx_quality

func _vfx_sprite_cap() -> int:
	match _effective_vfx_quality():
		"full": return 14
		"performance": return 5
		_: return 10

func _vfx_particle_cap() -> int:
	match _effective_vfx_quality():
		"full": return 64
		"performance": return 28
		_: return 48

func _vfx_hit_particle_count() -> int:
	match _effective_vfx_quality():
		"full": return 7
		"performance": return 3
		_: return 5

func _vfx_special_stride() -> int:
	match _effective_vfx_quality():
		"full": return 8
		"performance": return 0
		_: return 12

func _vfx_heavy_enabled() -> bool:
	return _effective_vfx_quality() != "performance"

func _change_rock_meter(amount: float) -> void:
	if _rock_meter_mode == "off" or _song_failed:
		return
	if amount < 0.0 and _overdrive_active:
		return
	if amount > 0.0:
		# A sustained streak recovers the crowd a little faster, capped at +40%.
		var streak_bonus := 1.0 + minf(float(combo), 100.0) / 250.0
		amount *= streak_bonus
	_rock_meter_value = clampf(_rock_meter_value + amount, 0.0, 1.0)
	if _rock_meter_value <= 0.0 and _rock_meter_mode == "fail":
		_song_failed = true
		_rock_meter_display = 0.0
		_update_rock_meter_controls()
		call_deferred("_fail_song")

func _fail_song() -> void:
	if not _song_failed:
		return
	song_started = false
	_paused = false
	for player in audio_players:
		if is_instance_valid(player):
			player.stop()
	if _crowd_ambience: _crowd_ambience.stop()
	if _crowd_reaction: _crowd_reaction.stop()
	_stop_crowd_burst_players()
	total_notes = notes.size()
	_show_result_screen(false, true)

func _update_adaptive_vfx(delta: float) -> void:
	if _vfx_quality != "balanced":
		_adaptive_vfx_reduced = false
		return
	var fps := Engine.get_frames_per_second()
	if fps > 0.0 and fps < 55.0:
		_low_fps_time += delta
		_fps_recovery_time = 0.0
		if _low_fps_time >= 0.9 and not _adaptive_vfx_reduced:
			_adaptive_vfx_reduced = true
			print("VFX: FPS dusuk, gecici performans modu etkin")
	elif fps >= 58.0:
		_low_fps_time = 0.0
		if _adaptive_vfx_reduced:
			_fps_recovery_time += delta
			if _fps_recovery_time >= 6.0:
				_adaptive_vfx_reduced = false
				_fps_recovery_time = 0.0
				print("VFX: FPS toparlandi, dengeli moda donuldu")

func _process(delta: float) -> void:
	_frame_time_msec = float(Time.get_ticks_msec())
	_frame_time_sec = _frame_time_msec / 1000.0
	if is_loading:
		if loading_status_label:
			# Animated dots
			loading_dots_timer += delta
			var dots := ".".repeat(int(loading_dots_timer * 2.0) % 4)
			loading_status_label.text = loading_status + dots
		if loading_bar:
			loading_bar.visible = loading_progress > 0
			loading_bar.value = loading_progress
		queue_redraw()
		return

	# State: countdown before play — giant neon number
	if _countdown > 0:
		_countdown -= delta
		if loading_status_label:
			loading_status_label.text = str(ceili(_countdown))
			loading_status_label.add_theme_font_size_override("font_size", 104)
			loading_status_label.add_theme_color_override("font_color", UITheme.NEON_CYAN.lightened(0.25))
			loading_status_label.add_theme_color_override("font_shadow_color", Color(UITheme.NEON_CYAN.r, UITheme.NEON_CYAN.g, UITheme.NEON_CYAN.b, 0.55))
			loading_status_label.add_theme_constant_override("shadow_offset_x", 0)
			loading_status_label.add_theme_constant_override("shadow_offset_y", 0)
			loading_status_label.add_theme_constant_override("shadow_outline_size", 18)
			if UITheme.font_bold():
				loading_status_label.add_theme_font_override("font", UITheme.font_bold())
		if loading_bar:
			loading_bar.visible = false
		queue_redraw()
		if _countdown <= 0:
			_hide_loading_screen()
			_start_playback()
		return

	if not song_started or _paused:
		return
	if _rock_meter_mode != "off":
		var meter_blend := 1.0 - exp(-delta * 10.0)
		_rock_meter_display = lerpf(_rock_meter_display, _rock_meter_value, meter_blend)
		_update_rock_meter_controls()
	_update_adaptive_vfx(delta)

	song_time_ms = _get_song_time_ms()
	# Finale owns the next available crowd-reaction slot. Process it before the
	# normal pending-boo queue so an old reaction cannot steal the song ending.
	_update_ending_crowd()
	_update_gameplay_sections(delta)
	_auto_perfect_overdrive_notes()

	# Mark active notes past hit window as missed
	var hit_window := _hit_window_ms()
	for idx in range(first_visible_idx, notes.size()):
		var t: float = notes[idx]["time_ms"]
		if t > song_time_ms + hit_window:
			break
		if note_state[idx] == 0 and song_time_ms - t > hit_window:
			var missed_indices := _active_assist_cluster_indices(idx)
			if missed_indices.is_empty():
				continue
			for missed_idx in missed_indices:
				note_state[missed_idx] = 2
				_register_gameplay_miss(missed_idx)
			_play_miss_sfx()
			_register_crowd_mistake()
			_perfect_streak = 0
			_change_rock_meter(-ROCK_METER_MISS_LOSS)
			var broken_combo := combo
			combo = 0
			_update_combo_tier()
			miss_count += missed_indices.size()
			_miss_flash_alpha = 1.0
			var miss_lane := int(notes[idx]["lane"])
			_miss_lane_flashes.append({"lane": miss_lane, "alpha": 1.0})
			if broken_combo >= 25:
				_spawn_combo_break_fx(miss_lane, broken_combo)
			# Smoke puff on the missed lane
			if miss_lane < lane_count:
				_spawn_sprite_fx("puff",
					Vector2(_lanes_start_x() + (miss_lane + 0.5) * _lane_width(), _hit_line_y()),
					_lane_width() * 1.1)
			# Hide any in-flight combo popup — the streak is over
			if _combo_popup_tw and _combo_popup_tw.is_valid():
				_combo_popup_tw.kill()
			combo_label.modulate.a = 0.0

	# Advance first_visible_idx past notes way off-screen
	while first_visible_idx < notes.size():
		var t: float = notes[first_visible_idx]["time_ms"]
		if song_time_ms - t < _approach_time_ms() + HIT_LINGER_MS:
			break
		first_visible_idx += 1

	# Update sustain holds
	_update_sustains()

	# Decay hit flash effects
	var i := 0
	while i < hit_effects.size():
		hit_effects[i]["alpha"] -= 0.045
		if float(hit_effects[i]["alpha"]) <= 0:
			hit_effects.remove_at(i)
		else:
			i += 1

	# Decay hit rings
	i = 0
	while i < hit_rings.size():
		hit_rings[i]["radius"] = float(hit_rings[i]["radius"]) + delta * 300.0
		hit_rings[i]["alpha"] = float(hit_rings[i]["alpha"]) - delta * 2.5
		if float(hit_rings[i]["alpha"]) <= 0:
			hit_rings.remove_at(i)
		else:
			i += 1

	# Decay miss flash
	if _miss_flash_alpha > 0:
		_miss_flash_alpha = maxf(0, _miss_flash_alpha - delta * 3.0)

	# Decay miss lane flashes
	var i_mlf := 0
	while i_mlf < _miss_lane_flashes.size():
		_miss_lane_flashes[i_mlf]["alpha"] -= delta * 3.0
		if _miss_lane_flashes[i_mlf]["alpha"] <= 0:
			_miss_lane_flashes.remove_at(i_mlf)
		else:
			i_mlf += 1

	# Beat pulse — advance past played beats, pulse the highway
	while _beat_idx < beat_times.size() and beat_times[_beat_idx] <= song_time_ms:
		_beat_idx += 1
		_beat_pulse = 1.0
	_beat_pulse = maxf(0.0, _beat_pulse - delta * 4.5)

	# Hit particles — gravity + lifetime
	var i_p := 0
	while i_p < _particles.size():
		var pt: Dictionary = _particles[i_p]
		pt["life"] = float(pt["life"]) - delta
		if float(pt["life"]) <= 0.0:
			_particles.remove_at(i_p)
			continue
		pt["vel"] = (pt["vel"] as Vector2) + Vector2(0, 1400.0 * delta)
		pt["pos"] = (pt["pos"] as Vector2) + (pt["vel"] as Vector2) * delta
		i_p += 1

	# Lane press streaks — rise fast, fade after release
	for li in range(lane_count):
		if lane_pressed[li]:
			_lane_streak[li] = minf(1.0, float(_lane_streak[li]) + delta * 10.0)
		else:
			_lane_streak[li] = maxf(0.0, float(_lane_streak[li]) - delta * 5.0)

	# Age sprite FX one-shots
	var i_fx := 0
	while i_fx < _sprite_fx.size():
		var fx: Dictionary = _sprite_fx[i_fx]
		fx["t"] = float(fx["t"]) + delta
		if float(fx["t"]) * VFX.fps(fx["name"]) >= VFX.frame_count(fx["name"]):
			_sprite_fx.remove_at(i_fx)
		else:
			i_fx += 1

	# Decay lightning bolts
	var i_b := 0
	while i_b < _bolts.size():
		_bolts[i_b]["life"] = float(_bolts[i_b]["life"]) - delta
		if float(_bolts[i_b]["life"]) <= 0.0:
			_bolts.remove_at(i_b)
		else:
			i_b += 1

	# Ambient lightning at 300+ combo — random faint strikes down a lane
	if combo >= 300 and _vfx_heavy_enabled():
		_ambient_bolt_timer -= delta
		if _ambient_bolt_timer <= 0.0:
			_ambient_bolt_timer = randf_range(0.7, 1.4)
			var bl := randi_range(0, lane_count - 1)
			var bx := _lanes_start_x() + (bl + 0.5) * _lane_width()
			var top_y := _gh_horizon_y() if _gh_mode else 0.0
			_spawn_lightning(Vector2(bx + randf_range(-30, 30), top_y),
				Vector2(bx, _hit_line_y()), Color(BOLT_COLOR.r, BOLT_COLOR.g, BOLT_COLOR.b, 0.6), 0.22)

	# Sustain hold sparks — continuous glitter while a long note is held
	for li in range(lane_count):
		if int(held_sustain[li]) >= 0:
			_sustain_spark_timer[li] = float(_sustain_spark_timer[li]) - delta
			var sustain_spark_count := 2 if _effective_vfx_quality() == "full" else 1
			var sustain_spark_interval := 0.07 if _effective_vfx_quality() == "full" else (0.15 if _effective_vfx_quality() == "performance" else 0.10)
			if float(_sustain_spark_timer[li]) <= 0.0 and _particles.size() <= _vfx_particle_cap() - sustain_spark_count:
				_sustain_spark_timer[li] = sustain_spark_interval
				var lw_s := _lane_width()
				var ox := _lanes_start_x() + (li + 0.5) * lw_s
				var sc: Color = lane_colors[li]
				for k in range(sustain_spark_count):
					var life := randf_range(0.25, 0.45)
					_particles.append({
						"pos": Vector2(ox + randf_range(-lw_s * 0.25, lw_s * 0.25), _hit_line_y() + randf_range(-6.0, 6.0)),
						"vel": Vector2(randf_range(-40.0, 40.0), randf_range(-260.0, -120.0)),
						"color": sc.lightened(randf_range(0.1, 0.5)),
						"life": life,
						"max_life": life,
						"size": randf_range(1.5, 3.0),
					})
		else:
			_sustain_spark_timer[li] = 0.0

	_update_lyrics()
	_update_hud()

	# End of song detection
	if master_player and not master_player.playing and song_time_ms > 1000:
		_on_song_finished()
		return

	queue_redraw()

func _update_sustains() -> void:
	for lane in range(lane_count):
		var idx: int = held_sustain[lane]
		if idx < 0:
			continue
		var n = notes[idx]
		var end_time: float = float(n["time_ms"]) + float(n["duration_ms"])

		if song_time_ms >= end_time - ROCK_METER_SUSTAIN_END_GRACE_MS:
			# Sustain completed
			note_state[idx] = 1
			held_sustain[lane] = -1
			var sustain_factor := float(n.get("hit_score_factor", PERFECT_SCORE_FACTOR))
			score += int(BASE_SUSTAIN_SCORE * sustain_factor * _score_multiplier())
			_change_rock_meter(ROCK_METER_SUSTAIN_GAIN * sustain_factor)
		elif not lane_pressed[lane]:
			if bool(n.get("overdrive_auto_hit", false)):
				continue
			# Released early — becomes hit (darkened, scrolling)
			note_state[idx] = 1
			held_sustain[lane] = -1
			_change_rock_meter(-ROCK_METER_EARLY_RELEASE_LOSS)
			# An imprecise sustain release can affect scoring/Rock Meter, but it is
			# never audience-boo debt. Boo patience only counts missed notes and
			# clearly wrong taps.
			_register_solo_fault()
			_perfect_streak = 0

# =====================================================================
#  LYRICS
#  Current line: sung part gold, unsung bright. Backing vocals — text in
#  (parentheses) — always rendered faint. Next phrase previewed dim below.
# =====================================================================

# The RichTextLabel's intrinsic size changes whenever a new lyric line appears.
# Keep the PanelContainer's center at the original lyric location after every
# such resize instead of relying on Control grow-direction heuristics.
func _center_lyrics_panel() -> void:
	if lyric_panel == null:
		return
	var available_size := get_viewport_rect().size
	var parent_control := lyric_panel.get_parent() as Control
	if parent_control != null and parent_control.size.x > 0.0 and parent_control.size.y > 0.0:
		available_size = parent_control.size
	var center := Vector2(available_size.x * 0.5, available_size.y * _lyrics_center_y_ratio)
	lyric_panel.position = center - lyric_panel.size * 0.5

func _update_lyrics() -> void:
	if lyric_phrases.is_empty():
		lyric_panel.visible = false; return
	while current_phrase_idx < lyric_phrases.size():
		if float(lyric_phrases[current_phrase_idx]["end_ms"]) >= song_time_ms:
			break
		current_phrase_idx += 1
	if current_phrase_idx >= lyric_phrases.size():
		lyric_panel.visible = false; return

	var phrase = lyric_phrases[current_phrase_idx]
	var start: float = phrase["start_ms"]
	var end: float = phrase["end_ms"]

	# Next phrase preview (only if it follows within a reasonable gap)
	var next_text := ""
	if current_phrase_idx + 1 < lyric_phrases.size():
		var np = lyric_phrases[current_phrase_idx + 1]
		if float(np["start_ms"]) - end < 8000.0:
			next_text = np["text"]

	var active_now := song_time_ms >= start - 300 and song_time_ms <= end
	var visible_now := active_now or start - song_time_ms <= 1800.0
	lyric_panel.visible = visible_now
	if visible_now:
		var sung_end := -1
		if active_now:
			sung_end = 0
			for syllable in phrase["syllables"]:
				if float(syllable["time_ms"]) <= song_time_ms:
					sung_end = int(syllable["char_end"])
				else:
					break
		# Parsing BBCode and recalculating minimum size is only necessary when
		# the phrase, visibility state or sung syllable actually changes.
		if _lyric_render_phrase_idx != current_phrase_idx \
				or _lyric_render_active != active_now \
				or _lyric_render_sung_end != sung_end:
			_lyric_render_phrase_idx = current_phrase_idx
			_lyric_render_active = active_now
			_lyric_render_sung_end = sung_end
			lyric_rtl.text = _build_lyric_bbcode(
				phrase, next_text, active_now, sung_end)

	# Shrink the panel back down when a shorter phrase replaces a long one
	if lyric_panel.visible and _lyric_shown_idx != current_phrase_idx:
		_lyric_shown_idx = current_phrase_idx
		lyric_rtl.call_deferred("reset_size")
		lyric_panel.call_deferred("reset_size")
		call_deferred("_center_lyrics_panel")

var _lyric_shown_idx: int = -1
var _lyric_render_phrase_idx: int = -1
var _lyric_render_sung_end: int = -2
var _lyric_render_active: bool = false

# Cache: wrapping/ellipsis are computed once per phrase, not every frame
var _lyric_cache_idx: int = -1
var _lyric_wrapped: String = ""
var _lyric_next_short: String = ""

func _build_lyric_bbcode(phrase: Dictionary, next_text: String, active: bool,
		known_sung_end: int = -1) -> String:
	if _lyric_cache_idx != current_phrase_idx:
		_lyric_cache_idx = current_phrase_idx
		# Wrap long lines at word boundaries (space → \n keeps char indices
		# aligned with syllable char_end offsets)
		_lyric_wrapped = _wrap_lyric(String(phrase["text"]), _lyric_font_size)
		_lyric_next_short = _ellipsize_lyric(next_text, _lyric_next_font_size)

	var italic_ranges: Array = phrase.get("italic_ranges", [])
	var out := "[center]"
	if active:
		var sung_end := known_sung_end
		if sung_end < 0:
			sung_end = 0
			for syl in phrase["syllables"]:
				if float(syl["time_ms"]) <= song_time_ms:
					sung_end = int(syl["char_end"])
				else:
					break
		out += _colorize_lyric(_lyric_wrapped, sung_end, "EDEDF5", "8f8fa8aa", italic_ranges)
	else:
		# Upcoming line — everything dim
		out += _colorize_lyric(_lyric_wrapped, 0, "9a9ab2", "6a6a8090", italic_ranges)
	if _lyric_next_short != "":
		out += "\n[font_size=%d]" % _lyric_next_font_size + _colorize_lyric(_lyric_next_short, 0, "73738d", "55556c99") + "[/font_size]"
	out += "[/center]"
	return out

# Replaces spaces with newlines so no line exceeds ~86% of the screen width.
# String length is preserved, keeping syllable char offsets valid.
func _wrap_lyric(text: String, font_size: int) -> String:
	var f := UITheme.font_regular()
	if f == null:
		return text
	var max_w := get_viewport_rect().size.x * 0.86
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
		return text
	var result := text
	var line_start := 0
	var guard := 0
	while guard < 16:
		guard += 1
		var line_end := result.find("\n", line_start)
		if line_end < 0:
			line_end = result.length()
		var line := result.substr(line_start, line_end - line_start)
		if f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
			if line_end >= result.length():
				break
			line_start = line_end + 1
			continue
		# Line too wide — find the last space that still fits
		var break_pos := -1
		var search := line_start + 1
		while search < line_end:
			var sp := result.find(" ", search)
			if sp < 0 or sp >= line_end:
				break
			var seg := result.substr(line_start, sp - line_start)
			if f.get_string_size(seg, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
				break_pos = sp
				search = sp + 1
			else:
				break
		if break_pos < 0:
			# No usable space (single huge word) — leave as is
			if line_end >= result.length():
				break
			line_start = line_end + 1
			continue
		result = result.substr(0, break_pos) + "\n" + result.substr(break_pos + 1)
		line_start = break_pos + 1
	return result

# Trims the next-line preview to a single fitting line with an ellipsis.
func _ellipsize_lyric(text: String, font_size: int) -> String:
	if text.is_empty():
		return ""
	var f := UITheme.font_regular()
	if f == null:
		return text
	var max_w := get_viewport_rect().size.x * 0.78
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
		return text
	var lo := 3
	var hi := text.length()
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if f.get_string_size(text.substr(0, mid) + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
			lo = mid
		else:
			hi = mid - 1
	return text.substr(0, lo).strip_edges() + "…"

# Wraps runs of characters in bbcode color tags.
# sung chars (< sung_end): gold (dim gold in faint spans);
# unsung chars: `bright` (or `paren_col` in faint spans).
# Faint spans = (parentheses) OR italic_ranges from <i> tags — both mark
# backing/spoken vocals.
func _colorize_lyric(text: String, sung_end: int, bright: String, paren_col: String, italic_ranges: Array = []) -> String:
	if text.is_empty():
		return ""
	var mask := _lyric_paren_mask(text)
	for r in italic_ranges:
		if r is Array and r.size() >= 2:
			var ra := clampi(int(r[0]), 0, mask.size())
			var rb := clampi(int(r[1]), 0, mask.size())
			for mi in range(ra, rb):
				mask[mi] = true
	var out := ""
	var i := 0
	while i < text.length():
		var sung := i < sung_end
		var par: bool = mask[i]
		var j := i
		while j < text.length() and (j < sung_end) == sung and bool(mask[j]) == par:
			j += 1
		var col := ""
		if sung:
			col = "b89a3ecc" if par else "FFD700"
		else:
			col = paren_col if par else bright
		out += "[color=#%s]%s[/color]" % [col, text.substr(i, j - i)]
		i = j
	return out

# True per character while inside (parentheses) — used to mark backing vocals.
func _lyric_paren_mask(text: String) -> Array:
	var mask: Array = []
	var depth := 0
	for i in range(text.length()):
		var ch := text[i]
		if ch == "(":
			depth += 1
		mask.append(depth > 0)
		if ch == ")":
			depth = maxi(0, depth - 1)
	return mask

func _update_hud() -> void:
	var frame_delta := get_process_delta_time()
	if score != _hud_last_score:
		_hud_last_score = score
		score_label.text = str(score)
	_fps_timer -= frame_delta
	if _fps_timer <= 0.0:
		_fps_timer = 0.25
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	# Multiplier badge (combo count itself only pops at milestones)
	if _combo_multiplier != _hud_last_multiplier:
		_hud_last_multiplier = _combo_multiplier
		if _combo_multiplier > 1.0:
			mult_label.text = "x%s" % _get_combo_tier_label().trim_suffix("x")
			var mc := _combo_glow_color
			mult_label.add_theme_color_override("font_color", Color(mc.r, mc.g, mc.b, 1.0).lightened(0.25))
			mult_label.add_theme_color_override("font_shadow_color", Color(mc.r, mc.g, mc.b, 0.5))
			mult_label.visible = true
		else:
			mult_label.visible = false

	# Progress/rest controls do not need render-frame cadence. Updating them at
	# 20 Hz stays visually smooth and avoids repeated Control invalidation.
	_hud_slow_timer -= frame_delta
	if _hud_slow_timer > 0.0:
		return
	_hud_slow_timer = 0.05
	if notes.size() > 0:
		var last_time: float = notes[notes.size() - 1]["time_ms"]
		progress_bar.value = clampf(song_time_ms / last_time * 100.0, 0.0, 100.0)

	# Rest timer — find next active note
	var next_time := -1.0
	for idx in range(first_visible_idx, notes.size()):
		if note_state[idx] == 0:
			next_time = float(notes[idx]["time_ms"])
			break
	if next_time > 0:
		var gap := next_time - song_time_ms
		if gap > 3000.0:
			var secs := ceili(gap / 1000.0)
			rest_timer_label.text = "%d" % secs
			rest_timer_label.visible = true
		else:
			rest_timer_label.visible = false
	else:
		rest_timer_label.visible = false

# --- Drawing ---

func _cache_render_geometry() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	_frame_viewport_size = vp
	_cached_lane_width = vp.x * float(LAYOUT["highway_ratio"]) / float(lane_count)
	_cached_lanes_start_x = (vp.x - float(lane_count) * _cached_lane_width) * 0.5
	_cached_hit_line_y = vp.y * float(LAYOUT["hit_line_ratio"])
	_cached_note_height = _cached_lane_width * float(LAYOUT["note_h_ratio"])
	_cached_gh_vanish_y = vp.y * GH_VANISH_Y_RATIO
	var total_width := float(lane_count) * _cached_lane_width
	var z_far := 1.0 / GH_TOP_SCALE
	var z_bottom := (_cached_hit_line_y - _cached_gh_vanish_y) / (vp.y - _cached_gh_vanish_y)
	var horizon_y := _cached_gh_vanish_y + (_cached_hit_line_y - _cached_gh_vanish_y) / z_far
	var center_x := vp.x * 0.5
	var left_bottom := _cached_lanes_start_x
	var right_bottom := left_bottom + total_width
	var top_left := Vector2(center_x + (left_bottom - center_x) / z_far, horizon_y)
	var top_right := Vector2(center_x + (right_bottom - center_x) / z_far, horizon_y)
	var bottom_right := Vector2(center_x + (right_bottom - center_x) / z_bottom, vp.y)
	var bottom_left := Vector2(center_x + (left_bottom - center_x) / z_bottom, vp.y)
	_gh_surface_points = PackedVector2Array([
		top_left, top_right, bottom_right, bottom_left])
	_gh_combo_left_points = PackedVector2Array([
		top_left, top_left.lerp(top_right, 0.13),
		bottom_left.lerp(bottom_right, 0.13), bottom_left])
	_gh_combo_right_points = PackedVector2Array([
		top_right.lerp(top_left, 0.13), top_right,
		bottom_right, bottom_right.lerp(bottom_left, 0.13)])
	_background_points = PackedVector2Array([
		Vector2.ZERO, Vector2(vp.x, 0.0), vp, Vector2(0.0, vp.y)])

	var vignette_width := vp.x * 0.09
	_vignette_left_points = PackedVector2Array([
		Vector2.ZERO, Vector2(vignette_width, 0.0),
		Vector2(vignette_width, vp.y), Vector2(0.0, vp.y)])
	_vignette_right_points = PackedVector2Array([
		Vector2(vp.x - vignette_width, 0.0), Vector2(vp.x, 0.0),
		vp, Vector2(vp.x - vignette_width, vp.y)])
	var vignette_dark := Color(0, 0, 0, 0.32)
	var vignette_clear := Color(0, 0, 0, 0)
	_vignette_left_colors = PackedColorArray([
		vignette_dark, vignette_clear, vignette_clear, vignette_dark])
	_vignette_right_colors = PackedColorArray([
		vignette_clear, vignette_dark, vignette_dark, vignette_clear])

	var fade_height := vp.y * 0.16
	var fade_top := Color(BG_COLOR_TOP.r, BG_COLOR_TOP.g, BG_COLOR_TOP.b, 1.0)
	var fade_bottom := Color(BG_COLOR_TOP.r, BG_COLOR_TOP.g, BG_COLOR_TOP.b, 0.0)
	_spawn_fade_points = PackedVector2Array([
		Vector2.ZERO, Vector2(vp.x, 0.0),
		Vector2(vp.x, fade_height), Vector2(0.0, fade_height)])
	_spawn_fade_colors = PackedColorArray([
		fade_top, fade_top, fade_bottom, fade_bottom])
	_lyric_cache_idx = -1
	_lyric_render_phrase_idx = -1

func _draw() -> void:
	var vp := _frame_viewport_size
	if vp == Vector2.ZERO:
		vp = get_viewport_rect().size
	# Vertical gradient background (per-vertex colors)
	draw_polygon(_background_points, _background_colors)
	if is_loading or _countdown > 0:
		return

	_draw_starfield(vp)

	if _gh_mode:
		_draw_gh_highway(vp)
	else:
		_draw_flat_highway(vp)
	_draw_overdrive_overlay(vp)

	# One-shot sprite effects (hits, misses, rings) + lightning
	_draw_sprite_fx()
	_draw_bolts()

	_draw_particles()

	# Miss flash — red edges (thick + visible)
	if _miss_flash_alpha > 0:
		var mf_a := _miss_flash_alpha * 0.6
		var mf_col := Color(1, 0.1, 0.05, mf_a)
		var edge_w := 14.0
		draw_rect(Rect2(0, 0, edge_w, vp.y), mf_col)
		draw_rect(Rect2(vp.x - edge_w, 0, edge_w, vp.y), mf_col)
		draw_rect(Rect2(0, 0, vp.x, edge_w), mf_col)
		draw_rect(Rect2(0, vp.y - edge_w, vp.x, edge_w), mf_col)

	_draw_vignette(vp)

func _draw_overdrive_overlay(vp: Vector2) -> void:
	if not _overdrive_active:
		return
	var pulse := 0.5 + 0.5 * sin(_frame_time_msec * 0.009)
	var edge_col := Color(0.72, 0.28, 1.0, 0.24 + pulse * 0.18)
	var edge_w := maxf(4.0, _lane_width() * 0.045)
	var left := _lanes_start_x()
	var right := left + lane_count * _lane_width()
	draw_rect(Rect2(left, 0, edge_w, vp.y), edge_col)
	draw_rect(Rect2(right - edge_w, 0, edge_w, vp.y), edge_col)
	draw_line(Vector2(left, _hit_line_y()), Vector2(right, _hit_line_y()),
		Color(0.4, 0.9, 1.0, 0.48 + pulse * 0.25), maxf(3.0, edge_w * 0.7))

# --- Sprite FX (spritesheet animations from the VFX pack) ---

func _spawn_sprite_fx(fx_name: String, pos: Vector2, height: float, mod: Color = Color.WHITE, rot: float = 0.0) -> void:
	# Dense charts used to stack many copies of the same one-second animation
	# over one lane. Refresh that animation instead of multiplying overdraw.
	var merge_distance := _lane_width() * 0.42
	for i in range(_sprite_fx.size() - 1, -1, -1):
		var existing: Dictionary = _sprite_fx[i]
		if String(existing["name"]) == fx_name and (existing["pos"] as Vector2).distance_to(pos) <= merge_distance:
			existing["pos"] = pos
			existing["h"] = height
			existing["mod"] = mod
			existing["rot"] = rot
			existing["t"] = 0.0
			return
	if _sprite_fx.size() >= _vfx_sprite_cap():
		_sprite_fx.pop_front()
	_sprite_fx.append({"name": fx_name, "pos": pos, "h": height, "mod": mod, "t": 0.0, "rot": rot})

# Draws one frame of a sheet effect centered at pos, scaled to `height`.
func _draw_fx_frame(fx_name: String, frame: int, pos: Vector2, height: float, mod: Color, rot: float = 0.0) -> void:
	var t := VFX.tex(fx_name)
	if t == null:
		return
	var region := VFX.frame_region(fx_name, frame)
	var size := Vector2(height * VFX.frame_aspect(fx_name), height)
	if rot != 0.0:
		draw_set_transform(pos, rot, Vector2.ONE)
		draw_texture_rect_region(t, Rect2(-size / 2.0, size), region, mod)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(t, Rect2(pos - size / 2.0, size), region, mod)

# Crossfade adjacent flipbook frames to avoid stepped 30 FPS animation on
# 60/90/120 Hz phones.
func _draw_fx_loop_smooth(fx_name: String, pos: Vector2, height: float, mod: Color,
		speed: float = 1.0, phase: float = 0.0, rot: float = 0.0) -> void:
	var frame_position := (_frame_time_sec * speed + phase) * VFX.fps(fx_name)
	var frame_floor := floori(frame_position)
	var frame_total := VFX.frame_count(fx_name)
	var frame_a := posmod(frame_floor, frame_total)
	var frame_b := (frame_a + 1) % frame_total
	var blend := frame_position - float(frame_floor)
	blend = blend * blend * (3.0 - 2.0 * blend)
	if blend <= 0.02:
		_draw_fx_frame(fx_name, frame_a, pos, height, mod, rot)
		return
	if blend >= 0.98:
		_draw_fx_frame(fx_name, frame_b, pos, height, mod, rot)
		return
	_draw_fx_frame(fx_name, frame_a, pos, height,
		Color(mod.r, mod.g, mod.b, mod.a * (1.0 - blend)), rot)
	_draw_fx_frame(fx_name, frame_b, pos, height,
		Color(mod.r, mod.g, mod.b, mod.a * blend), rot)

func _draw_fx_frame_size(fx_name: String, frame: int, pos: Vector2, size: Vector2, mod: Color) -> void:
	var texture := VFX.tex(fx_name)
	if texture == null:
		return
	draw_texture_rect_region(texture, Rect2(pos - size / 2.0, size),
		VFX.frame_region(fx_name, frame), mod)

func _draw_fx_loop_smooth_size(fx_name: String, pos: Vector2, size: Vector2, mod: Color,
		speed: float = 1.0, phase: float = 0.0) -> void:
	var frame_position := (_frame_time_sec * speed + phase) * VFX.fps(fx_name)
	var frame_floor := floori(frame_position)
	var frame_total := VFX.frame_count(fx_name)
	var frame_a := posmod(frame_floor, frame_total)
	var frame_b := (frame_a + 1) % frame_total
	var blend := frame_position - float(frame_floor)
	blend = blend * blend * (3.0 - 2.0 * blend)
	if blend <= 0.02:
		_draw_fx_frame_size(fx_name, frame_a, pos, size, mod)
		return
	if blend >= 0.98:
		_draw_fx_frame_size(fx_name, frame_b, pos, size, mod)
		return
	_draw_fx_frame_size(fx_name, frame_a, pos, size,
		Color(mod.r, mod.g, mod.b, mod.a * (1.0 - blend)))
	_draw_fx_frame_size(fx_name, frame_b, pos, size,
		Color(mod.r, mod.g, mod.b, mod.a * blend))

# --- Procedural lightning (Guitar Hero vibe) ---

const BOLT_COLOR := Color(0.65, 0.85, 1.0)

func _spawn_lightning(from: Vector2, to: Vector2, col: Color = BOLT_COLOR, life: float = 0.18) -> void:
	if _bolts.size() >= 10:
		_bolts.pop_front()
	var seg := 8
	var pts := PackedVector2Array()
	var jitter := absf(to.y - from.y) * 0.06 + 6.0
	for i in range(seg + 1):
		var t := float(i) / float(seg)
		var p := from.lerp(to, t)
		if i > 0 and i < seg:
			p.x += randf_range(-jitter, jitter)
			p.y += randf_range(-jitter * 0.4, jitter * 0.4)
		pts.append(p)
	_bolts.append({"pts": pts, "life": life, "max_life": life, "col": col})
	# Short branch off a random midpoint
	if randf() < 0.7 and seg > 3:
		var bi := randi_range(2, seg - 2)
		var bp := pts[bi]
		var branch_end := bp + Vector2(randf_range(-40, 40), randf_range(20, 55))
		var bpts := PackedVector2Array([bp, bp.lerp(branch_end, 0.5) + Vector2(randf_range(-10, 10), 0), branch_end])
		_bolts.append({"pts": bpts, "life": life * 0.7, "max_life": life * 0.7, "col": col})

func _draw_bolts() -> void:
	for b in _bolts:
		var a: float = float(b["life"]) / float(b["max_life"])
		var pts: PackedVector2Array = b["pts"]
		var c: Color = b["col"]
		# Layered: wide glow, mid color, thin white-hot core
		draw_polyline(pts, Color(c.r, c.g, c.b, 0.15 * a), 7.0)
		draw_polyline(pts, Color(c.r, c.g, c.b, 0.55 * a), 3.0)
		draw_polyline(pts, Color(1, 1, 1, 0.9 * a), 1.3)

func _draw_sprite_fx() -> void:
	for fx in _sprite_fx:
		var fx_name: String = fx["name"]
		var frame := int(float(fx["t"]) * VFX.fps(fx_name))
		if frame >= VFX.frame_count(fx_name):
			continue
		_draw_fx_frame(fx_name, frame, fx["pos"], float(fx["h"]), fx["mod"], float(fx["rot"]))

# Low-profile metal fret note (Guitar Mode), tinted by lane color.
func _draw_gh_fret(center: Vector2, radius: float, col: Color, alpha: float, hit: bool) -> void:
	if radius < 1.5:
		return
	var texture := VFX.tex("gh_fret")
	if texture == null:
		return
	# Preserve lane width while cutting the old sphere's vertical footprint
	# roughly in half, so dense note streams remain readable.
	var fret_size := Vector2(radius * 2.0, radius * 1.02)
	if not hit and alpha > 0.3:
		var glow_size := fret_size * 1.16
		draw_texture_rect(texture, Rect2(center - glow_size * 0.5, glow_size), false,
			Color(col.r, col.g, col.b, 0.18 * alpha))
		if _combo_glow_color.a > 0:
			var combo_size := fret_size * 1.26
			draw_texture_rect(texture, Rect2(center - combo_size * 0.5, combo_size), false,
				Color(_combo_glow_color.r, _combo_glow_color.g, _combo_glow_color.b,
					_combo_glow_color.a * 0.18 * alpha))
	var modulate := col.darkened(0.55) if hit else col.lightened(0.08)
	draw_texture_rect(texture, Rect2(center - fret_size * 0.5, fret_size), false,
		Color(modulate.r, modulate.g, modulate.b, alpha))

# --- Shared drawing: starfield, vignette, particles ---

func _draw_starfield(vp: Vector2) -> void:
	var t := _frame_time_sec
	var horizon := _gh_horizon_y() if _gh_mode else vp.y
	for star_index in range(_star_x.size()):
		var sy := fmod(_star_y[star_index] + t * _star_speed[star_index], 1.0) * vp.y
		# In GH mode stars only live in the sky above the horizon
		if _gh_mode and sy > horizon - 8.0:
			continue
		var sx := _star_x[star_index] * vp.x
		var twinkle := 0.22 + 0.20 * sin(t * 1.7 + _star_phase[star_index])
		draw_circle(Vector2(sx, sy), _star_size[star_index], Color(0.75, 0.8, 1.0, twinkle))

func _draw_vignette(vp: Vector2) -> void:
	draw_polygon(_vignette_left_points, _vignette_left_colors)
	draw_polygon(_vignette_right_points, _vignette_right_colors)

func _draw_particles() -> void:
	for pt in _particles:
		var a: float = float(pt["life"]) / float(pt["max_life"])
		var c: Color = pt["color"]
		draw_circle(pt["pos"] as Vector2, float(pt["size"]) * (0.55 + 0.45 * a), Color(c.r, c.g, c.b, a))

func _draw_hyperspeed_flat(vp: Vector2) -> void:
	var texture := VFX.tex("hyperspeed")
	if texture == null:
		return
	var frame := VFX.loop_frame_at("hyperspeed", _frame_time_sec)
	var region := VFX.frame_region("hyperspeed", frame)
	# Stretch the animated frame to the complete portrait viewport. The old
	# square-sized draw left the lower portion of tall phones uncovered.
	# The source sheet travels horizontally. Transpose it clockwise so the
	# streaks run from the top of the portrait screen toward the hit line.
	draw_texture_rect_region(texture, Rect2(Vector2.ZERO, vp), region, Color(1, 1, 1, 0.22), true)

func _draw_hyperspeed_gh(points: PackedVector2Array) -> void:
	if points.size() != 4:
		return
	# A texture mapped over one large trapezoid develops a diagonal UV seam on
	# some mobile GPUs. Stable procedural streaks preserve the 500-combo speed
	# effect while following the highway perspective without atlas flicker.
	var tl := points[0]
	var tr := points[1]
	var br := points[2]
	var bl := points[3]
	var now := _frame_time_sec
	var streak_count := 24 if _effective_vfx_quality() == "full" else 17
	var tier_color := _combo_glow_color.lightened(0.22)
	for streak_i in range(streak_count):
		var seed := fposmod(sin(float(streak_i) * 12.9898) * 43758.5453, 1.0)
		var x_mix := 0.04 + 0.92 * fposmod(sin(float(streak_i + 19) * 78.233) * 23421.631, 1.0)
		var travel := fposmod(now * (0.72 + float(streak_i % 5) * 0.055) + seed, 1.0)
		var tail_travel := maxf(0.0, travel - 0.075 - seed * 0.045)
		# Accelerate toward the player to sell the Guitar Mode depth.
		var head_t := travel * travel
		var tail_t := tail_travel * tail_travel
		var head_left := tl.lerp(bl, head_t)
		var head_right := tr.lerp(br, head_t)
		var tail_left := tl.lerp(bl, tail_t)
		var tail_right := tr.lerp(br, tail_t)
		var head := head_left.lerp(head_right, x_mix)
		var tail := tail_left.lerp(tail_right, x_mix)
		var fade := clampf(travel / 0.12, 0.0, 1.0) * clampf((1.0 - travel) / 0.10, 0.0, 1.0)
		var alpha := (0.12 + head_t * 0.22) * fade
		var width := 1.0 + head_t * 3.2
		var streak_color := tier_color if streak_i % 4 else UITheme.NEON_CYAN
		draw_line(tail, head,
			Color(streak_color.r, streak_color.g, streak_color.b, alpha * 0.34), width * 3.0, true)
		draw_line(tail, head,
			Color(streak_color.r, streak_color.g, streak_color.b, alpha), width, true)

func _combo_streak_tint() -> Color:
	var tier_color := _combo_glow_color if _combo_glow_color.a > 0.0 else UITheme.NEON_CYAN
	var alpha := 0.24 if combo >= 300 else 0.17
	return Color(tier_color.r, tier_color.g, tier_color.b, alpha)

func _draw_combo_streaks_flat(vp: Vector2) -> void:
	var texture := VFX.tex("combo_streaks")
	if texture == null:
		return
	var frame := VFX.loop_frame_at("combo_streaks", _frame_time_sec, 0.72)
	var region := VFX.frame_region("combo_streaks", frame)
	var ls := _lanes_start_x()
	var total_w := lane_count * _lane_width()
	var strip_w := minf(_lane_width() * 0.28, vp.x * 0.075)
	var tint := _combo_streak_tint()
	draw_texture_rect_region(texture, Rect2(ls, 0.0, strip_w, _hit_line_y()), region, tint, true)
	draw_texture_rect_region(texture,
		Rect2(ls + total_w - strip_w, 0.0, strip_w, _hit_line_y()), region, tint, true)

func _draw_combo_streaks_gh(points: PackedVector2Array) -> void:
	var texture := VFX.tex("combo_streaks")
	if texture == null or points.size() != 4:
		return
	var frame := VFX.loop_frame_at("combo_streaks", _frame_time_sec, 0.72)
	var uvs := VFX.frame_uvs("combo_streaks", frame)
	var tint := _combo_streak_tint()
	var colors := PackedColorArray([tint, tint, tint, tint])
	draw_polygon(_gh_combo_left_points, colors, uvs, texture)
	draw_polygon(_gh_combo_right_points, colors, uvs, texture)

# =====================================================================
#  FLAT HIGHWAY (classic tiles view)
# =====================================================================

func _draw_flat_highway(vp: Vector2) -> void:
	var lw := _lane_width()
	var ls := _lanes_start_x()
	var hit_y := _hit_line_y()
	var app_ms := _approach_time_ms()

	# Highway background — single rect (per-lane full-height rects cost
	# serious fill-rate on mobile GPUs)
	draw_rect(Rect2(ls, 0, lane_count * lw, vp.y), LANE_BG)
	if combo >= 200 and combo < 500 and _vfx_heavy_enabled():
		_draw_combo_streaks_flat(vp)
	if combo >= 500 and _vfx_heavy_enabled():
		_draw_hyperspeed_flat(vp)
	for idx in range(lane_count + 1):
		var x := ls + idx * lw
		draw_line(Vector2(x, 0), Vector2(x, vp.y), LANE_BORDER, 1.0)

	# Beat lines — scroll down in sync with tempo
	var beat_start := maxi(0, _beat_idx - 6)
	for beat_index in range(beat_start, beat_times.size()):
		var beat_until := float(beat_times[beat_index]) - song_time_ms
		if beat_until > app_ms:
			break
		var b_ratio := 1.0 - (beat_until / app_ms)
		var by := b_ratio * hit_y
		if by < 0 or by > vp.y:
			continue
		var strong := (beat_index % 4) == 0
		var ba := (0.20 if strong else 0.08) * clampf(b_ratio / 0.3, 0.0, 1.0)
		draw_line(Vector2(ls, by), Vector2(ls + lane_count * lw, by),
			Color(0.7, 0.75, 1.0, ba), 2.0 if strong else 1.0)

	# Lane press streaks — light rises from the hit zone while held
	for li in range(lane_count):
		var s_a: float = _lane_streak[li]
		if s_a <= 0.01:
			continue
		var s_c: Color = lane_colors[li]
		var s_x := ls + li * lw
		var s_top := hit_y * 0.45
		draw_polygon(
			PackedVector2Array([Vector2(s_x, s_top), Vector2(s_x + lw, s_top), Vector2(s_x + lw, hit_y), Vector2(s_x, hit_y)]),
			PackedColorArray([
				Color(s_c.r, s_c.g, s_c.b, 0.0), Color(s_c.r, s_c.g, s_c.b, 0.0),
				Color(s_c.r, s_c.g, s_c.b, 0.16 * s_a), Color(s_c.r, s_c.g, s_c.b, 0.16 * s_a)]))

	# Hit line — layered neon glow
	var hl_start := Vector2(ls, hit_y)
	var hl_end := Vector2(ls + lane_count * lw, hit_y)
	draw_line(hl_start, hl_end, Color(HIT_LINE_COLOR.r, HIT_LINE_COLOR.g, HIT_LINE_COLOR.b, 0.10), 14.0)
	draw_line(hl_start, hl_end, Color(HIT_LINE_COLOR.r, HIT_LINE_COLOR.g, HIT_LINE_COLOR.b, 0.22), 7.0)
	draw_line(hl_start, hl_end, HIT_LINE_COLOR, 2.0)

	# Hit zone — large squares filling each lane
	var hz_h := lw * FLAT_HIT_ZONE_HEIGHT_RATIO
	var hz_margin := lw * FLAT_HIT_ZONE_MARGIN_RATIO
	for idx in range(lane_count):
		var hx := ls + idx * lw + hz_margin
		var hw := lw - hz_margin * 2.0
		var hy := hit_y - hz_h / 2.0
		var base_alpha := 0.2
		if lane_pressed[idx]:
			base_alpha = 0.45
		draw_rect(Rect2(hx, hy, hw, hz_h), lane_colors[idx] * Color(1, 1, 1, base_alpha))
		# Combo glow border on hit zone
		if _combo_glow_color.a > 0:
			var gz_pulse := 0.1 * sin(_frame_time_msec * 0.005)
			var gz_a := (_combo_glow_color.a * 0.5 + gz_pulse)
			draw_rect(Rect2(hx, hy, hw, hz_h), Color(_combo_glow_color.r, _combo_glow_color.g, _combo_glow_color.b, gz_a), false, 3.0)
		else:
			draw_rect(Rect2(hx, hy, hw, hz_h), lane_colors[idx] * Color(1, 1, 1, base_alpha + 0.15), false, 2.0)

	# Hit flash effects
	for eff in hit_effects:
		var eidx: int = eff["lane"]
		var ea: float = eff["alpha"]
		var fx := ls + eidx * lw + hz_margin
		var fw := lw - hz_margin * 2.0
		draw_rect(Rect2(fx, hit_y - hz_h / 2.0, fw, hz_h), lane_colors[eidx] * Color(1, 1, 1, ea))

	# Hit ring animations (expanding squares)
	for ring in hit_rings:
		var rl: int = ring["lane"]
		var rr: float = ring["radius"]
		var ra: float = ring["alpha"]
		var rx := ls + rl * lw + hz_margin - rr * 0.3
		var rw := lw - hz_margin * 2.0 + rr * 0.6
		var rh := hz_h + rr * 0.6
		draw_rect(Rect2(rx, hit_y - rh / 2.0, rw, rh), lane_colors[rl] * Color(1, 1, 1, ra), false, 2.5)

	# Miss lane flashes — soft red glow on missed/wrong-tapped lane
	for mlf in _miss_lane_flashes:
		var ml: int = mlf["lane"]
		var ma: float = mlf["alpha"]
		if ml >= lane_count:
			continue
		var mx := ls + ml * lw
		# Soft glow radiating from hit line
		var glow_h := lw * 1.8
		var glow_top := hit_y - glow_h / 2.0
		var glow_col := Color(1, 0.15, 0.08, ma * 0.3)
		draw_rect(Rect2(mx, glow_top, lw, glow_h), glow_col)
		# Brighter center strip
		var center_margin := lw * 0.15
		var center_h := lw * 0.7
		var center_col := Color(1, 0.2, 0.1, ma * 0.45)
		draw_rect(Rect2(mx + center_margin, hit_y - center_h / 2.0, lw - center_margin * 2.0, center_h), center_col)

	# Notes
	var note_h := _note_height()
	var margin := lw * FLAT_NOTE_MARGIN_RATIO

	for idx in range(first_visible_idx, notes.size()):
		var n = notes[idx]
		var t: float = n["time_ms"]
		var time_until := t - song_time_ms
		var state: int = note_state[idx]

		# Too far in future
		if time_until > app_ms:
			break
		# Missed — don't draw
		if state == 2:
			continue
		# Akıcı keeps every authored note for scoring, but impossible bursts in
		# one lane are represented by a single playable leader.
		if int(n.get("assist_cluster_id", -1)) >= 0 \
				and not bool(n.get("assist_cluster_leader", false)):
			continue

		var lane: int = n["lane"]
		if lane >= lane_count:
			continue

		var x := ls + lane * lw + margin
		var w := lw - margin * 2.0
		var ratio := 1.0 - (time_until / app_ms)
		var y := ratio * hit_y - note_h / 2.0

		var is_hit := (state == 1)
		var is_holding := (state == 3)

		# Alpha fade: notes fade in as they approach (0.2 at top -> 1.0 at 40% travel)
		var note_alpha := clampf(ratio / 0.4, 0.2, 1.0) if not is_hit else 0.5
		if bool(n.get("overdrive_phrase", -1) >= 0):
			var od_pulse := 0.55 + 0.25 * sin(_frame_time_msec * 0.008 + lane)
			draw_rect(Rect2(x - 3.0, y - 3.0, w + 6.0, note_h + 6.0),
				Color(0.72, 0.92, 1.0, od_pulse * note_alpha), false, maxf(2.0, lw * 0.025))

		# Off-screen below — skip
		if is_hit and y > vp.y + note_h:
			continue

		var dur_ms: float = n["duration_ms"]

		# --- Sustain tail ---
		if dur_ms > 0:
			var tail_until := (t + dur_ms) - song_time_ms
			var tail_ratio := 1.0 - (tail_until / app_ms)
			var tail_y := tail_ratio * hit_y - note_h / 2.0

			var sx := x + w * 0.3
			var sw := w * 0.4

			if is_holding:
				# While holding: clip tail top to current position, head at hit line
				var hold_top := maxf(tail_y, 0)
				var hold_bottom := hit_y
				var hc: Color = lane_colors[lane]
				if hold_bottom > hold_top:
					# Pulse effect
					var pulse := 0.15 * sin(_frame_time_msec * 0.008)
					var hold_style := sustain_styles_hold[lane]
					hold_style.bg_color = hc * Color(1, 1, 1, 0.65 + pulse)
					draw_style_box(hold_style, Rect2(sx, hold_top, sw, hold_bottom - hold_top + note_h))
				# Hold aura — pulsing lane-colored glow behind the head
				var hold_pulse := 0.5 + 0.5 * sin(_frame_time_msec * 0.012)
				draw_circle(Vector2(x + w / 2.0, hit_y), w * (0.55 + 0.08 * hold_pulse),
					Color(hc.r, hc.g, hc.b, 0.16 + 0.10 * hold_pulse))
				# Expanding pulse ring
				draw_rect(Rect2(x - 4 - 6 * hold_pulse, hit_y - note_h / 2.0 - 4 - 6 * hold_pulse,
					w + 8 + 12 * hold_pulse, note_h + 8 + 12 * hold_pulse),
					Color(hc.r, hc.g, hc.b, 0.45 * (1.0 - hold_pulse) + 0.1), false, 2.0)
				# Head stays at hit line — with glow if active tier
				if _combo_glow_color.a > 0:
					var glow_expand := 4.0
					var glow_col := Color(_combo_glow_color.r, _combo_glow_color.g, _combo_glow_color.b, _combo_glow_color.a * 0.8)
					draw_rect(Rect2(x - glow_expand, hit_y - note_h / 2.0 - glow_expand, w + glow_expand * 2, note_h + glow_expand * 2), glow_col)
				# At 100+ combo, sustained notes ignite behind their pressed head.
				# Smoke is deliberately subtle and disabled by Performance VFX mode.
				if combo >= 100:
					var burn_alpha := 0.86 if combo >= 300 else 0.76
					if _vfx_heavy_enabled():
						_draw_fx_loop_smooth("sustain_smoke",
							Vector2(x + w / 2.0, hit_y - w * 0.38), w * 0.78,
							Color(0.82, 0.79, 0.75, 0.27), 0.58, lane * 0.37 + 0.20)
					_draw_fx_loop_smooth("sustain_fire",
						Vector2(x + w / 2.0, hit_y - w * 0.22), w * 0.66,
						Color(1.0, 1.0, 1.0, burn_alpha), 0.82, lane * 0.41)
				var hold_tex: Texture2D = note_tex[lane] if lane < note_tex.size() else null
				if hold_tex:
					draw_texture_rect(hold_tex, Rect2(x, hit_y - note_h / 2.0, w, note_h), false, Color(1.15, 1.15, 1.15))
				else:
					draw_style_box(note_styles[lane], Rect2(x, hit_y - note_h / 2.0, w, note_h))
				# Brackeys electric ring sits on top of the pressed tile edge. Two
				# layers keep the lane color strong while retaining a white-hot core.
				var ring_center := Vector2(x + w / 2.0, hit_y)
				var ring_size := Vector2(w * 1.08, maxf(note_h * 2.10, w * 0.58))
				var ring_color: Color = lane_colors[lane].lightened(0.24)
				_draw_fx_loop_smooth_size("hold_ring", ring_center, ring_size,
					Color(ring_color.r, ring_color.g, ring_color.b, 0.96), 0.86, lane * 0.31)
				_draw_fx_loop_smooth_size("hold_ring", ring_center, ring_size * 0.94,
					Color(1.0, 1.0, 1.0, 0.30), 0.86, lane * 0.31)
				var orbit_time := _frame_time_msec * 0.0045 + lane * 0.9
				var spark_count := 3 if _effective_vfx_quality() == "performance" else 5
				for spark_i in range(spark_count):
					var spark_angle := orbit_time + TAU * float(spark_i) / float(spark_count)
					var spark_pos := ring_center + Vector2(
						cos(spark_angle) * ring_size.x * 0.48,
						sin(spark_angle) * ring_size.y * 0.46)
					draw_circle(spark_pos, maxf(2.0, note_h * 0.055), Color(1, 1, 1, 0.92))
				continue
			elif is_hit:
				# Hit sustain: darkened tail
				if y - tail_y + note_h > 0:
					draw_style_box(sustain_styles_hit[lane], Rect2(sx, tail_y, sw, y - tail_y + note_h))
			else:
				# Active sustain
				if y - tail_y + note_h > 0:
					draw_style_box(sustain_styles[lane], Rect2(sx, tail_y, sw, y - tail_y + note_h))

		# --- Note head (beveled tile texture) ---
		var head_tex: Texture2D = note_tex[lane] if lane < note_tex.size() else null
		if is_hit:
			if head_tex:
				draw_texture_rect(head_tex, Rect2(x, y, w, note_h), false, Color(0.42, 0.42, 0.48, note_alpha))
			else:
				var sh := note_styles_hit[lane]
				sh.bg_color.a = note_alpha
				draw_style_box(sh, Rect2(x, y, w, note_h))
		elif not is_holding:
			# Combo glow — expanded colored rect behind note
			if _combo_glow_color.a > 0:
				var glow_expand := 4.0
				var pulse := 0.15 * sin(_frame_time_msec * 0.006)
				var glow_a := (_combo_glow_color.a + pulse) * note_alpha
				var glow_col := Color(_combo_glow_color.r, _combo_glow_color.g, _combo_glow_color.b, glow_a)
				draw_rect(Rect2(x - glow_expand, y - glow_expand, w + glow_expand * 2, note_h + glow_expand * 2), glow_col)
			if head_tex:
				draw_texture_rect(head_tex, Rect2(x, y, w, note_h), false, Color(1, 1, 1, note_alpha))
			else:
				var sn := note_styles[lane]
				var orig_a := sn.bg_color.a
				sn.bg_color.a = note_alpha
				sn.border_color.a = note_alpha
				draw_style_box(sn, Rect2(x, y, w, note_h))
				sn.bg_color.a = orig_a
				sn.border_color.a = orig_a
		if not is_holding:
			_draw_assist_cluster_pips(
				Vector2(x + w * 0.5, y + note_h * 0.20), w,
				int(n.get("assist_cluster_size", 1)), note_alpha)

	# Spawn fade — notes emerge from darkness at the top
	draw_polygon(_spawn_fade_points, _spawn_fade_colors)

# =====================================================================
#  GH HIGHWAY (pseudo-3D perspective view)
# =====================================================================

func _draw_gh_highway(vp: Vector2) -> void:
	var lw := _lane_width()
	var ls := _lanes_start_x()
	var hit_y := _hit_line_y()
	var total_w := lane_count * lw
	var z_far := _gh_z_far()
	var z_bot := _gh_z_bottom()
	var horizon_y := _gh_y(z_far)
	var app_ms := _approach_time_ms()

	# Highway surface — trapezoid, darker toward the horizon
	var tl := _gh_surface_points[0]
	var tr := _gh_surface_points[1]
	var br := _gh_surface_points[2]
	var bl := _gh_surface_points[3]
	draw_polygon(_gh_surface_points, _gh_surface_colors)
	if combo >= 200 and combo < 500 and _vfx_heavy_enabled():
		_draw_combo_streaks_gh(_gh_surface_points)
	if combo >= 500 and _vfx_heavy_enabled():
		_draw_hyperspeed_gh(_gh_surface_points)

	# Horizon glow line
	var hcol := UITheme.NEON_PURPLE
	draw_line(tl + Vector2(0, 1), tr + Vector2(0, 1), Color(hcol.r, hcol.g, hcol.b, 0.10), 9.0)
	draw_line(tl, tr, Color(hcol.r, hcol.g, hcol.b, 0.40), 2.0)

	# Beat lines — scroll down the fretboard
	var beat_start := maxi(0, _beat_idx - 6)
	for beat_index in range(beat_start, beat_times.size()):
		var beat_until := float(beat_times[beat_index]) - song_time_ms
		if beat_until > app_ms:
			break
		var bz := _gh_z_for(beat_until)
		if bz < z_bot or bz > z_far:
			continue
		var by := _gh_y(bz)
		var strong := (beat_index % 4) == 0
		var bfade := clampf((app_ms - beat_until) / (app_ms * 0.3), 0.0, 1.0)
		var ba := (0.26 if strong else 0.09) * bfade
		draw_line(Vector2(_gh_x(ls, bz), by), Vector2(_gh_x(ls + total_w, bz), by),
			Color(0.7, 0.75, 1.0, ba), 2.5 if strong else 1.2)

	# Lane divider lines — converging toward the vanishing point
	for i in range(lane_count + 1):
		var xb := ls + i * lw
		draw_line(Vector2(_gh_x(xb, z_far), horizon_y), Vector2(_gh_x(xb, z_bot), vp.y),
			Color(LANE_BORDER.r, LANE_BORDER.g, LANE_BORDER.b, 0.5), 1.3)

	# Side rails — layered neon glow, pulse on beat, combo tier color
	var rail_col := _combo_glow_color if _combo_glow_color.a > 0 else UITheme.NEON_PURPLE
	var pulse_a := 0.55 + 0.40 * _beat_pulse
	for side_x in [ls, ls + total_w]:
		var p1 := Vector2(_gh_x(side_x, z_far), horizon_y)
		var p2 := Vector2(_gh_x(side_x, z_bot), vp.y)
		draw_line(p1, p2, Color(rail_col.r, rail_col.g, rail_col.b, 0.10 * pulse_a), 12.0)
		draw_line(p1, p2, Color(rail_col.r, rail_col.g, rail_col.b, 0.28 * pulse_a), 5.0)
		draw_line(p1, p2, Color(rail_col.r, rail_col.g, rail_col.b, 0.85 * pulse_a), 2.0)

	# Lane press streaks — light shoots up the lane while held
	for li in range(lane_count):
		var sa: float = _lane_streak[li]
		if sa <= 0.01:
			continue
		var sc: Color = lane_colors[li]
		var x1b := ls + li * lw
		var x2b := x1b + lw
		var streak_z := lerpf(1.0, z_far, 0.6)
		var s_top_l := Vector2(_gh_x(x1b, streak_z), _gh_y(streak_z))
		var s_top_r := Vector2(_gh_x(x2b, streak_z), _gh_y(streak_z))
		var top_c := Color(sc.r, sc.g, sc.b, 0.0)
		var bot_c := Color(sc.r, sc.g, sc.b, 0.20 * sa)
		draw_polygon(PackedVector2Array([s_top_l, s_top_r, Vector2(x2b, hit_y), Vector2(x1b, hit_y)]),
			PackedColorArray([top_c, top_c, bot_c, bot_c]))

	# Hit line — glow across the highway
	var hl1 := Vector2(ls, hit_y)
	var hl2 := Vector2(ls + total_w, hit_y)
	draw_line(hl1, hl2, Color(HIT_LINE_COLOR.r, HIT_LINE_COLOR.g, HIT_LINE_COLOR.b, 0.08), 16.0)
	draw_line(hl1, hl2, Color(HIT_LINE_COLOR.r, HIT_LINE_COLOR.g, HIT_LINE_COLOR.b, 0.20), 6.0)
	draw_line(hl1, hl2, Color(HIT_LINE_COLOR.r, HIT_LINE_COLOR.g, HIT_LINE_COLOR.b, 0.6), 1.5)

	# Wide colored pads make the exact Perfect area obvious on touchscreens.
	# The metal frets stay on top to preserve Guitar Mode's visual identity.
	var gem_r := lw * GH_HIT_FRET_RADIUS_RATIO
	for li in range(lane_count):
		var cx := ls + (li + 0.5) * lw
		var c: Color = lane_colors[li]
		var pressed: bool = lane_pressed[li]
		var pad_rect := _gh_hit_pad_rect(li)
		var pad_alpha := 0.18 if pressed else 0.065
		if pressed:
			draw_rect(pad_rect.grow(maxf(2.0, lw * 0.025)),
				Color(c.r, c.g, c.b, 0.055))
		draw_rect(pad_rect, Color(c.r, c.g, c.b, pad_alpha))
		draw_rect(pad_rect, Color(c.r, c.g, c.b, 0.52 if pressed else 0.26),
			false, maxf(2.0, lw * 0.018))
		# A bright center line ties the pad to the timing line without hiding it.
		draw_line(Vector2(pad_rect.position.x, hit_y),
			Vector2(pad_rect.end.x, hit_y), Color(c.r, c.g, c.b, 0.34),
			maxf(1.5, lw * 0.012))
		var r := gem_r * (1.06 if pressed else 1.0)
		r *= 1.0 + 0.03 * _beat_pulse
		var center := Vector2(cx, hit_y)
		if pressed:
			_draw_gh_fret(center, r, c.lightened(0.12), 1.0, false)
		else:
			_draw_gh_fret(center, r, c.darkened(0.48), 0.72, false)
		# combo tier ring
		if _combo_glow_color.a > 0:
			var gz_pulse := 0.1 * sin(_frame_time_msec * 0.005)
			draw_arc(center, r * 1.24, 0, TAU, 18,
				Color(_combo_glow_color.r, _combo_glow_color.g, _combo_glow_color.b, _combo_glow_color.a * 0.5 + gz_pulse), 2.0)

	# Hit flashes — bright gem burst
	for eff in hit_effects:
		var eidx: int = eff["lane"]
		var ea: float = eff["alpha"]
		var ecx := ls + (eidx + 0.5) * lw
		draw_circle(Vector2(ecx, hit_y), gem_r * 1.25, lane_colors[eidx] * Color(1, 1, 1, ea * 0.7))

	# Hit rings — expanding circles
	for ring in hit_rings:
		var rl: int = ring["lane"]
		var rr: float = ring["radius"]
		var ra: float = ring["alpha"]
		var rcx := ls + (rl + 0.5) * lw
		draw_arc(Vector2(rcx, hit_y), gem_r + rr, 0, TAU, 20, lane_colors[rl] * Color(1, 1, 1, ra), 3.0)

	# Miss lane flashes — red glow at the fret
	for mlf in _miss_lane_flashes:
		var ml: int = mlf["lane"]
		var ma: float = mlf["alpha"]
		if ml >= lane_count:
			continue
		var mcx := ls + (ml + 0.5) * lw
		draw_circle(Vector2(mcx, hit_y), gem_r * 1.6, Color(1, 0.15, 0.08, ma * 0.35))

	# --- Notes (fret caps with perspective) ---
	# Draw far-to-near. The previous order let farther frets paint over closer
	# notes, which made dense consecutive streams look like one opaque stack.
	var last_visible_note := first_visible_idx - 1
	for scan_idx in range(first_visible_idx, notes.size()):
		if float(notes[scan_idx]["time_ms"]) - song_time_ms > app_ms:
			break
		last_visible_note = scan_idx
	for idx in range(last_visible_note, first_visible_idx - 1, -1):
		var n = notes[idx]
		var t: float = n["time_ms"]
		var time_until := t - song_time_ms
		var state: int = note_state[idx]
		if state == 2:
			continue
		if int(n.get("assist_cluster_id", -1)) >= 0 \
				and not bool(n.get("assist_cluster_leader", false)):
			continue
		var lane: int = n["lane"]
		if lane >= lane_count:
			continue

		var z := _gh_z_for(time_until)
		var lane_cx_bottom := ls + (lane + 0.5) * lw
		var gx := _gh_x(lane_cx_bottom, z)
		var gy := _gh_y(z)
		var gr := lw * GH_NOTE_FRET_RADIUS_RATIO / z
		var is_hit := (state == 1)
		var is_holding := (state == 3)

		# Fade in near the horizon
		var ratio := 1.0 - (time_until / app_ms)
		var note_alpha := clampf(ratio / 0.25, 0.15, 1.0)
		if is_hit:
			note_alpha = 0.45
		if bool(n.get("overdrive_phrase", -1) >= 0):
			var od_pulse := 0.58 + 0.24 * sin(_frame_time_msec * 0.008 + lane)
			draw_arc(Vector2(gx, gy), gr * 1.24, 0.0, TAU, 28,
				Color(0.72, 0.92, 1.0, od_pulse * note_alpha), maxf(2.0, gr * 0.10), true)
		if is_hit and gy > vp.y + gr * 2.0:
			continue

		var dur_ms: float = n["duration_ms"]

		# --- Sustain trail ---
		if dur_ms > 0:
			var tail_until := (t + dur_ms) - song_time_ms
			var tz := minf(_gh_z_for(tail_until), z_far)
			var t_cx := _gh_x(lane_cx_bottom, tz)
			var t_y := _gh_y(tz)
			var t_w := lw * 0.20 / tz
			var cc: Color = lane_colors[lane]

			if is_holding:
				# Trail tapers from the tail down to the fret; head locked at hit line
				var h_w := lw * 0.20
				var pulse := 0.15 * sin(_frame_time_msec * 0.008)
				draw_polygon(PackedVector2Array([
					Vector2(t_cx - t_w, t_y), Vector2(t_cx + t_w, t_y),
					Vector2(lane_cx_bottom + h_w, hit_y), Vector2(lane_cx_bottom - h_w, hit_y)]),
					PackedColorArray([
						Color(cc.r, cc.g, cc.b, 0.12), Color(cc.r, cc.g, cc.b, 0.12),
						Color(cc.r, cc.g, cc.b, 0.7 + pulse), Color(cc.r, cc.g, cc.b, 0.7 + pulse)]))
				# Hold aura — pulsing glow + expanding ring around the head
				var hold_pulse := 0.5 + 0.5 * sin(_frame_time_msec * 0.012)
				var ring_center := Vector2(lane_cx_bottom, hit_y)
				draw_circle(ring_center, lw * (0.38 + 0.04 * hold_pulse),
					Color(cc.r, cc.g, cc.b, 0.08 + 0.05 * hold_pulse))
				# Keep the flame behind the fret so it appears to rise from the held
				# note instead of being pasted over the circular button.
				if combo >= 100:
					var burn_alpha := 0.88 if combo >= 300 else 0.78
					if _vfx_heavy_enabled():
						_draw_fx_loop_smooth("sustain_smoke",
							ring_center + Vector2(0.0, -lw * 0.40), lw * 0.70,
							Color(0.82, 0.79, 0.75, 0.26), 0.58, lane * 0.37 + 0.20)
					_draw_fx_loop_smooth("sustain_fire",
						ring_center + Vector2(0.0, -lw * 0.24), lw * 0.58,
						Color(1.0, 1.0, 1.0, burn_alpha), 0.82, lane * 0.41)
				_draw_gh_fret(ring_center, lw * GH_NOTE_FRET_RADIUS_RATIO, cc, 1.0, false)
				# The Brackeys ring is drawn after the fret, so its animated edge is
				# always visible instead of being buried behind the large button.
				var ring_h := lw * (0.78 + 0.035 * hold_pulse)
				var ring_color := cc.lightened(0.28)
				_draw_fx_loop_smooth("hold_ring", ring_center, ring_h,
					Color(ring_color.r, ring_color.g, ring_color.b, 0.98), 0.88, lane * 0.31)
				_draw_fx_loop_smooth("hold_ring", ring_center, ring_h * 0.93,
					Color(1.0, 1.0, 1.0, 0.32), 0.88, lane * 0.31)
				var orbit_time := _frame_time_msec * 0.0048 + lane * 0.9
				var spark_count := 3 if _effective_vfx_quality() == "performance" else 5
				for spark_i in range(spark_count):
					var spark_angle := orbit_time + TAU * float(spark_i) / float(spark_count)
					var spark_pos := ring_center + Vector2.from_angle(spark_angle) * lw * 0.405
					draw_circle(spark_pos, maxf(2.0, lw * 0.018), Color(1, 1, 1, 0.95))
				continue
			else:
				var head_w := lw * 0.20 / z
				var trail_a := 0.15 if is_hit else 0.35
				draw_polygon(PackedVector2Array([
					Vector2(t_cx - t_w, t_y), Vector2(t_cx + t_w, t_y),
					Vector2(gx + head_w, gy), Vector2(gx - head_w, gy)]),
					PackedColorArray([
						Color(cc.r, cc.g, cc.b, trail_a * 0.35 * note_alpha), Color(cc.r, cc.g, cc.b, trail_a * 0.35 * note_alpha),
						Color(cc.r, cc.g, cc.b, trail_a * note_alpha), Color(cc.r, cc.g, cc.b, trail_a * note_alpha)]))

		# --- Fret head ---
		if not is_holding:
			_draw_gh_fret(Vector2(gx, gy), gr, lane_colors[lane], note_alpha, is_hit)
			_draw_assist_cluster_pips(
				Vector2(gx, gy - gr * 0.12), gr * 1.5,
				int(n.get("assist_cluster_size", 1)), note_alpha)

func _draw_assist_cluster_pips(center: Vector2, width: float, count: int, alpha: float) -> void:
	if count <= 1:
		return
	var shown := mini(count, 3)
	var radius := maxf(2.0, width * 0.045)
	var spacing := radius * 2.6
	var start_x := center.x - spacing * float(shown - 1) * 0.5
	for pip_idx in range(shown):
		var pip_pos := Vector2(start_x + pip_idx * spacing, center.y)
		draw_circle(pip_pos, radius * 1.65, Color(0.0, 0.0, 0.0, 0.46 * alpha))
		draw_circle(pip_pos, radius, Color(1.0, 1.0, 1.0, 0.94 * alpha))

# --- Layout ---

func _lp() -> Dictionary:
	return LAYOUT

func _lane_width() -> float:
	if _cached_lane_width > 0.0:
		return _cached_lane_width
	return get_viewport_rect().size.x * float(LAYOUT["highway_ratio"]) / float(lane_count)

func _lanes_start_x() -> float:
	if _cached_lane_width > 0.0:
		return _cached_lanes_start_x
	return (get_viewport_rect().size.x - float(lane_count) * _lane_width()) / 2.0

func _hit_line_y() -> float:
	if _cached_hit_line_y > 0.0:
		return _cached_hit_line_y
	return get_viewport_rect().size.y * float(LAYOUT["hit_line_ratio"])

func _gh_hit_pad_rect(lane: int) -> Rect2:
	var lw := _lane_width()
	var margin := lw * GH_HIT_PAD_MARGIN_RATIO
	var height := lw * GH_HIT_PAD_HEIGHT_RATIO
	return Rect2(
		_lanes_start_x() + lane * lw + margin,
		_hit_line_y() - height * 0.5,
		lw - margin * 2.0,
		height)

func _note_height() -> float:
	if _cached_note_height > 0.0:
		return _cached_note_height
	return _lane_width() * float(LAYOUT["note_h_ratio"])

func _approach_time_ms() -> float:
	return _cached_approach_ms

# --- GH perspective projection ---
# z = 1.0 at the hit line, GH_Z_FAR at the spawn horizon. Screen positions are
# obtained by dividing distance-from-vanishing-point by z (perspective-correct).

func _gh_z_far() -> float:
	return 1.0 / GH_TOP_SCALE

func _gh_vanish_y() -> float:
	if _cached_gh_vanish_y != 0.0:
		return _cached_gh_vanish_y
	return get_viewport_rect().size.y * GH_VANISH_Y_RATIO

# time_until > 0: note approaching; < 0: passed hit line (grows toward viewer).
# Perspective-correct: z decreases linearly with time (constant world speed),
# screen motion accelerates near the hit line like real GH. A linear screen-
# speed variant was tried and REJECTED — it caused motion sickness.
func _gh_z_for(time_until: float) -> float:
	var p := time_until / _approach_time_ms()
	return maxf(1.0 + (_gh_z_far() - 1.0) * p, 0.45)

func _gh_x(x_bottom: float, z: float) -> float:
	var cx := _frame_viewport_size.x * 0.5
	return cx + (x_bottom - cx) / z

func _gh_y(z: float) -> float:
	var vy := _gh_vanish_y()
	return vy + (_hit_line_y() - vy) / z

func _gh_horizon_y() -> float:
	return _gh_y(_gh_z_far())

# z for the bottom edge of the screen (highway extends past the hit line)
func _gh_z_bottom() -> float:
	var vy := _gh_vanish_y()
	return (_hit_line_y() - vy) / (_frame_viewport_size.y - vy)

# --- Input (press AND release) ---

func _input(event: InputEvent) -> void:
	if not song_started or is_loading or _countdown > 0 or _paused:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_activate_overdrive()
		return

	var lane := -1
	var pressed := false
	var judgment := "perfect" # Keyboard has no horizontal touch position.

	if event is InputEventScreenTouch:
		pressed = event.pressed
		if pressed:
			if overdrive_button and overdrive_button.get_global_rect().has_point(event.position):
				# Never interpret an Overdrive tap as a fret press too.
				return
			var touch_hit := _pos_to_hit(event.position)
			lane = int(touch_hit.get("lane", -1))
			judgment = String(touch_hit.get("judgment", "perfect"))
		else:
			# Releasing a sustain remains forgiving if a finger slides slightly.
			lane = _pos_to_lane(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Android may still emit an emulated mouse event on a few vendor builds.
		# The real ScreenTouch above already handled that physical press.
		if OS.has_feature("android"):
			return
		pressed = event.pressed
		if pressed:
			if overdrive_button and overdrive_button.get_global_rect().has_point(event.position):
				return
			var mouse_hit := _pos_to_hit(event.position)
			lane = int(mouse_hit.get("lane", -1))
			judgment = String(mouse_hit.get("judgment", "perfect"))
		else:
			lane = _pos_to_lane(event.position)
	elif event is InputEventKey and not event.echo:
		lane = _key_to_lane(event.keycode)
		pressed = event.pressed

	if lane < 0:
		return

	if pressed:
		lane_pressed[lane] = true
		_try_hit(lane, judgment)
	else:
		lane_pressed[lane] = false
		# Sustain release handled in _update_sustains()

func _pos_to_lane(pos: Vector2) -> int:
	var lw := _lane_width()
	var start := _lanes_start_x()
	# 20% invisible padding on edges so taps outside highway still register
	var pad := lw * 0.2
	var rel := pos.x - start
	if rel < -pad:
		return -1
	if rel < 0:
		return 0
	if rel >= float(lane_count) * lw + pad:
		return -1
	if rel >= float(lane_count) * lw:
		return lane_count - 1
	return int(rel / lw)

# A hit must begin in or near the visible button at the hit line.
# Flat: the colored rectangle itself is Perfect.
# Guitar Mode: the visible colored pad itself is Perfect.
# The nearby area in the same lane is Good; farther touches are ignored.
func _pos_to_hit(pos: Vector2) -> Dictionary:
	var lw := _lane_width()
	var start := _lanes_start_x()
	var rel := pos.x - start
	var edge_padding_ratio := GH_GOOD_EDGE_PADDING_RATIO if _gh_mode else FLAT_GOOD_EDGE_PADDING_RATIO
	var edge_padding := lw * edge_padding_ratio
	if rel < -edge_padding or rel >= float(lane_count) * lw + edge_padding:
		return {}
	var lane := clampi(int(floor(rel / lw)), 0, lane_count - 1)
	var hit_y := _hit_line_y()

	# Good is deliberately limited to the immediate area around the controls;
	# tapping elsewhere on the highway should not trigger a note.
	var good_half_height_ratio := GH_GOOD_ZONE_HALF_HEIGHT_RATIO if _gh_mode else FLAT_GOOD_ZONE_HALF_HEIGHT_RATIO
	if PlayabilityScript.is_assisted_preset(song_preset):
		good_half_height_ratio *= ASSIST_GOOD_ZONE_SCALE
	if absf(pos.y - hit_y) > lw * good_half_height_ratio:
		return {}

	var is_perfect := false
	if _gh_mode:
		# Matches the visible Guitar Mode pad exactly.
		is_perfect = _gh_hit_pad_rect(lane).has_point(pos)
	else:
		# Matches the flat-mode colored hit rectangle exactly.
		var zone_height := lw * FLAT_HIT_ZONE_HEIGHT_RATIO
		var zone_margin := lw * FLAT_HIT_ZONE_MARGIN_RATIO
		var zone_rect := Rect2(
			start + lane * lw + zone_margin,
			hit_y - zone_height * 0.5,
			lw - zone_margin * 2.0,
			zone_height)
		is_perfect = zone_rect.has_point(pos)
	return {"lane": lane, "judgment": "perfect" if is_perfect else "good"}

func _key_to_lane(keycode: int) -> int:
	if lane_count == 4:
		match keycode:
			KEY_A, KEY_1: return 0
			KEY_S, KEY_2: return 1
			KEY_D, KEY_3: return 2
			KEY_F, KEY_4: return 3
	else:
		match keycode:
			KEY_A, KEY_1: return 0
			KEY_S, KEY_2: return 1
			KEY_D, KEY_3: return 2
			KEY_F, KEY_4: return 3
			KEY_G, KEY_5: return 4
	return -1

func _try_hit(lane: int, judgment: String = "perfect") -> void:
	if _overdrive_active:
		judgment = "perfect"
	var hit_window := _hit_window_ms()
	var best_idx := -1
	var best_diff := hit_window + 1.0

	for idx in range(first_visible_idx, notes.size()):
		var n = notes[idx]
		if note_state[idx] != 0:
			continue
		var t: float = n["time_ms"]
		var diff := absf(song_time_ms - t)
		if diff > _approach_time_ms():
			break
		if int(n["lane"]) == lane and diff < best_diff:
			best_diff = diff
			best_idx = idx

	if best_idx < 0 or best_diff > hit_window:
		if _overdrive_active:
			return
		_change_rock_meter(-ROCK_METER_WRONG_TAP_LOSS)
		_register_crowd_mistake()
		_register_solo_fault()
		_perfect_streak = 0
		_miss_lane_flashes.append({"lane": lane, "alpha": 0.72})
		return

	var n = notes[best_idx]
	var hit_indices := _active_assist_cluster_indices(best_idx)
	if hit_indices.is_empty():
		return
	var cluster_weight := hit_indices.size()
	var score_factor := PERFECT_SCORE_FACTOR if judgment == "perfect" else GOOD_SCORE_FACTOR
	var sustain_idx := -1
	for hit_idx in hit_indices:
		if float(notes[hit_idx]["duration_ms"]) > 0.0 and sustain_idx < 0:
			sustain_idx = hit_idx
	for hit_idx in hit_indices:
		# A merged group can contain only one playable hold; the leader carries
		# the group's longest sustain while every authored head still scores.
		note_state[hit_idx] = 3 if hit_idx == sustain_idx else 1
		notes[hit_idx]["hit_score_factor"] = score_factor
		_register_gameplay_hit(hit_idx, judgment)
	if sustain_idx >= 0:
		held_sustain[lane] = sustain_idx
	if judgment == "perfect":
		var previous_cheer_tier := _perfect_streak / 25
		_perfect_streak += cluster_weight
		if _perfect_streak / 25 > previous_cheer_tier:
			_play_crowd_reaction(_crowd_cheer_stream)
	else:
		_perfect_streak = 0
	combo += 1
	hit_count += cluster_weight
	if combo > max_combo:
		max_combo = combo
	var prev_mult := _combo_multiplier
	_update_combo_tier()
	score += int(BASE_HIT_SCORE * score_factor * _score_multiplier() * cluster_weight)
	_change_rock_meter(ROCK_METER_PERFECT_GAIN if judgment == "perfect" else ROCK_METER_GOOD_GAIN)
	_show_judgment(judgment, cluster_weight)

	# --- Sprite FX on hit ---
	var fret_pos := Vector2(_lanes_start_x() + (lane + 0.5) * _lane_width(), _hit_line_y())
	var lc: Color = lane_colors[lane]
	# Lane-colored impact flash on every hit
	_spawn_sprite_fx("impact", fret_pos, _lane_width() * 1.35, Color(lc.r, lc.g, lc.b, 0.9))
	# Brackeys impact accents begin at 50 combo. They are deliberately sparse;
	# milestones below provide the larger tier-specific animation.
	var special_stride := _vfx_special_stride()
	if combo >= 50 and special_stride > 0 and combo not in [50, 100, 200, 300, 500] \
			and combo % special_stride == 0:
		_spawn_sprite_fx("combo_impact", fret_pos,
			_lane_width() * (1.22 if _gh_mode else 1.42), Color(lc.r, lc.g, lc.b, 0.76))
	# Tier jump: lightning strikes down the lane only — NO sprite burst
	# (every electric sprite tried here covered the screen; user removed it twice)
	if _combo_multiplier > prev_mult:
		var strike_top := _gh_horizon_y() if _gh_mode else 0.0
		_spawn_lightning(Vector2(fret_pos.x + randf_range(-25, 25), strike_top), fret_pos)
		if _effective_vfx_quality() != "performance":
			_spawn_lightning(Vector2(fret_pos.x + randf_range(-60, 60), strike_top), fret_pos, BOLT_COLOR, 0.14)

	# Log first 20 hits for drift diagnosis
	if _hit_log_count < 20:
		_hit_log_count += 1
		var signed_diff := song_time_ms - float(n["time_ms"])
		if _hit_log_count == 1:
			var since_play := Time.get_ticks_msec() - _play_call_time_ms
			print("Sync: HIT #%d song=%.1f note=%.1f diff=%+.1f abs=%.1f since_play=%dms" % [
				_hit_log_count, song_time_ms, float(n["time_ms"]), signed_diff, best_diff, since_play])
		else:
			print("Sync: HIT #%d song=%.1f note=%.1f diff=%+.1f abs=%.1f" % [
				_hit_log_count, song_time_ms, float(n["time_ms"]), signed_diff, best_diff])

	# Hit flash + expanding ring + particles
	if hit_effects.size() >= _vfx_sprite_cap():
		hit_effects.pop_front()
	if hit_rings.size() >= _vfx_sprite_cap():
		hit_rings.pop_front()
	hit_effects.append({"lane": lane, "alpha": 0.8})
	hit_rings.append({"lane": lane, "radius": _lane_width() * 0.3, "alpha": 0.9})
	_spawn_hit_particles(lane)

	# Combo milestones — big golden tier unlock popup
	if combo in [25, 50, 100, 200, 300, 500]:
		var tier_label := _get_combo_tier_label()
		_spawn_combo_milestone_fx(combo, fret_pos, lc)
		_show_milestone("%d COMBO! %s" % [combo, tier_label])
		if combo >= 100:
			_play_crowd_reaction(_crowd_cheer_stream)
	elif combo >= 5 and combo % 5 == 0:
		# Small combo popup every 5 hits — pops in, then disappears
		_show_combo_popup("%d %s!" % [combo, I18n.t("combo_word")])

func _hit_window_ms() -> float:
	return ASSIST_HIT_WINDOW_MS if PlayabilityScript.is_assisted_preset(song_preset) else HIT_WINDOW_MS

func _spawn_combo_milestone_fx(milestone: int, fret_pos: Vector2, lane_color: Color) -> void:
	var lw := _lane_width()
	var tier_color := _combo_glow_color.lightened(0.22)
	match milestone:
		25:
			_spawn_sprite_fx("hold_ring", fret_pos, lw * 1.08,
				Color(lane_color.r, lane_color.g, lane_color.b, 0.92))
		50:
			_spawn_sprite_fx("combo_impact", fret_pos, lw * 1.48,
				Color(lane_color.r, lane_color.g, lane_color.b, 0.94))
		100:
			# Replaces the old fire/Elden ring with a clean gold-white impact and
			# a lane-colored electric wave.
			_spawn_sprite_fx("combo_impact", fret_pos, lw * 1.72,
				Color(tier_color.r, tier_color.g, tier_color.b, 0.98))
			_spawn_sprite_fx("hold_ring", fret_pos, lw * 1.36,
				Color(lane_color.r, lane_color.g, lane_color.b, 0.94))
		200:
			_spawn_sprite_fx("combo_impact", fret_pos, lw * 1.82,
				Color(tier_color.r, tier_color.g, tier_color.b, 0.96))
			_spawn_sprite_fx("hold_ring", fret_pos, lw * 1.50,
				Color(1.0, 0.88, 0.55, 0.88))
		300:
			_spawn_sprite_fx("combo_impact", fret_pos, lw * 1.96,
				Color(tier_color.r, tier_color.g, tier_color.b, 0.96))
			_spawn_sprite_fx("hold_ring", fret_pos, lw * 1.64,
				Color(1.0, 0.42, 0.20, 0.92))
			if _vfx_heavy_enabled():
				var strike_top := _gh_horizon_y() if _gh_mode else 0.0
				var ls := _lanes_start_x()
				_spawn_lightning(Vector2(ls, strike_top), fret_pos, tier_color, 0.24)
				_spawn_lightning(Vector2(ls + lane_count * lw, strike_top), fret_pos, tier_color, 0.24)
		500:
			_spawn_sprite_fx("combo_impact", fret_pos, lw * 2.08,
				Color(1.0, 0.82, 1.0, 0.98))
			_spawn_sprite_fx("hold_ring", fret_pos, lw * 1.80,
				Color(tier_color.r, tier_color.g, tier_color.b, 0.94))

func _spawn_combo_break_fx(lane: int, broken_combo: int) -> void:
	var lw := _lane_width()
	var origin := Vector2(_lanes_start_x() + (lane + 0.5) * lw, _hit_line_y())
	_spawn_sprite_fx("hold_ring", origin, lw * (1.28 if broken_combo >= 100 else 1.05),
		Color(1.0, 0.12, 0.08, 0.72), PI)
	var shard_count := 5 if _effective_vfx_quality() == "performance" else 9
	if _particles.size() > _vfx_particle_cap() - shard_count:
		return
	for shard_i in range(shard_count):
		var life := randf_range(0.28, 0.48)
		_particles.append({
			"pos": origin + Vector2(randf_range(-lw * 0.28, lw * 0.28), 0.0),
			"vel": Vector2(randf_range(-190.0, 190.0), randf_range(160.0, 360.0)),
			"color": Color(1.0, 0.16, 0.08, 1.0) if shard_i % 3 else Color.WHITE,
			"life": life,
			"max_life": life,
			"size": randf_range(2.5, 5.0),
		})

func _update_combo_tier() -> void:
	_combo_multiplier = 1.0
	_combo_glow_color = Color.TRANSPARENT
	for tier in COMBO_TIERS:
		if combo >= int(tier[0]):
			_combo_multiplier = float(tier[1])
			_combo_glow_color = tier[2] as Color
			break

func _get_combo_tier_label() -> String:
	for tier in COMBO_TIERS:
		if combo >= int(tier[0]):
			return tier[3] as String
	return ""

func _show_combo_popup(text: String) -> void:
	combo_label.text = text
	var tier_active := _combo_glow_color.a > 0
	combo_label.add_theme_color_override("font_color",
		_combo_glow_color.lightened(0.4) if tier_active else Color(1, 1, 1, 0.95))
	if _combo_popup_tw and _combo_popup_tw.is_valid():
		_combo_popup_tw.kill()
	combo_label.modulate.a = 1.0
	combo_label.scale = Vector2(0.6, 0.6)
	_combo_popup_tw = create_tween()
	_combo_popup_tw.tween_property(combo_label, "scale", Vector2(1.12, 1.12), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_combo_popup_tw.tween_property(combo_label, "scale", Vector2(1.0, 1.0), 0.08)
	_combo_popup_tw.tween_interval(0.45)
	_combo_popup_tw.tween_property(combo_label, "modulate:a", 0.0, 0.25)

func _show_judgment(judgment: String, cluster_weight: int = 1) -> void:
	if judgment_label == null:
		return
	var perfect := judgment == "perfect"
	judgment_label.text = "PERFECT" if perfect else "GOOD"
	if cluster_weight > 1:
		judgment_label.text += " ×%d" % cluster_weight
	judgment_label.add_theme_color_override("font_color",
		UITheme.NEON_CYAN.lightened(0.25) if perfect else UITheme.NEON_GREEN.lightened(0.15))
	if _judgment_tw and _judgment_tw.is_valid():
		_judgment_tw.kill()
	judgment_label.modulate.a = 1.0
	judgment_label.scale = Vector2(0.80, 0.80)
	_judgment_tw = create_tween()
	_judgment_tw.tween_property(judgment_label, "scale", Vector2(1.05, 1.05), 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_judgment_tw.tween_property(judgment_label, "scale", Vector2(1.0, 1.0), 0.08)
	_judgment_tw.tween_interval(0.20)
	_judgment_tw.tween_property(judgment_label, "modulate:a", 0.0, 0.18)

# Burst of sparks from the hit position (fret gem in GH mode, hit zone in flat)
func _spawn_hit_particles(lane: int) -> void:
	var spawn_count := _vfx_hit_particle_count()
	if _particles.size() > _vfx_particle_cap() - spawn_count:
		return
	var lw := _lane_width()
	var origin := Vector2(_lanes_start_x() + (lane + 0.5) * lw, _hit_line_y())
	var col: Color = lane_colors[lane]
	for i in range(spawn_count):
		var ang := randf_range(-PI * 0.85, -PI * 0.15)  # upward fan
		var speed := randf_range(220.0, 520.0)
		var life := randf_range(0.30, 0.55)
		_particles.append({
			"pos": origin + Vector2(randf_range(-lw * 0.2, lw * 0.2), 0),
			"vel": Vector2(cos(ang), sin(ang)) * speed,
			"color": col.lightened(0.3) if i % 3 != 0 else Color(1, 1, 1, 1),
			"life": life,
			"max_life": life,
			"size": randf_range(2.0, 4.2),
		})

func _show_milestone(text: String) -> void:
	# NOTE: no sprite behind the popup — the rainbow power_chords wave covered
	# the whole highway (user removed it). The golden label popup is enough.
	milestone_label.text = text
	milestone_label.modulate.a = 1.0
	milestone_label.scale = Vector2(0.5, 0.5)
	var tw := create_tween()
	tw.tween_property(milestone_label, "scale", Vector2(1.2, 1.2), 0.15).set_ease(Tween.EASE_OUT)
	tw.tween_property(milestone_label, "scale", Vector2(1.0, 1.0), 0.1)
	tw.tween_interval(0.6)
	tw.tween_property(milestone_label, "modulate:a", 0.0, 0.3)

func _on_song_finished() -> void:
	if _song_failed:
		return
	song_started = false
	if _active_solo_idx >= 0:
		_finish_solo(_active_solo_idx)
		_active_solo_idx = -1
	if _crowd_ambience: _crowd_ambience.stop()
	# Count remaining active notes as missed
	for idx in range(notes.size()):
		if note_state[idx] == 0:
			miss_count += 1
	total_notes = notes.size()
	# Save score and go to result screen
	var is_record := _save_score()
	_show_result_screen(is_record)

# Returns true when an existing best score was beaten.
func _save_score() -> bool:
	var scores_path := "user://scores.json"
	var scores := {}
	if FileAccess.file_exists(scores_path):
		var f := FileAccess.open(scores_path, FileAccess.READ)
		if f:
			var json := JSON.new()
			if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
				scores = json.data
			f.close()
	var key := "%s_%s_%s_%s" % [song_source.md5_text(), song_instrument, song_difficulty, song_preset]
	var accuracy := (float(hit_count) / float(total_notes) * 100.0) if total_notes > 0 else 0.0
	var stars := _calc_stars(accuracy)
	var entry := {
		"song": song_source.get_file(),
		"score": score,
		"accuracy": snappedf(accuracy, 0.1),
		"stars": stars,
		"max_combo": max_combo,
		"instrument": song_instrument,
		"difficulty": song_difficulty,
		"preset": song_preset,
	}
	# Only save if better score
	var had_prev: bool = scores.has(key)
	var prev_score: int = int(scores[key].get("score", 0)) if had_prev else 0
	if not had_prev or prev_score < score:
		scores[key] = entry
		var f := FileAccess.open(scores_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(scores))
			f.close()
		return had_prev  # badge only when beating an existing best
	return false

func _calc_stars(accuracy: float) -> int:
	if accuracy >= 98: return 5
	if accuracy >= 90: return 4
	if accuracy >= 75: return 3
	if accuracy >= 50: return 2
	if accuracy >= 25: return 1
	return 0

func _show_result_screen(is_record: bool = false, failed: bool = false) -> void:
	# Build result screen as overlay
	var result_layer := CanvasLayer.new()
	result_layer.layer = 20
	add_child(result_layer)

	var panel := ColorRect.new()
	panel.color = Color(0.02, 0.015, 0.05, 0.96)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.theme = _create_theme()
	result_layer.add_child(panel)

	# Soft glow blobs behind the card
	var glow1 := UITheme._make_glow_blob(UITheme.NEON_PURPLE, 0.12)
	glow1.position = Vector2(get_viewport_rect().size.x * 0.5 - 310, -220)
	panel.add_child(glow1)
	var glow2 := UITheme._make_glow_blob(UITheme.NEON_CYAN, 0.08)
	glow2.position = Vector2(get_viewport_rect().size.x * 0.5 - 310, get_viewport_rect().size.y - 400)
	panel.add_child(glow2)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sa := UITheme.safe_insets(self)
	scroll.offset_left = sa["l"] + _u(24); scroll.offset_right = -(sa["r"] + _u(24))
	scroll.offset_top = sa["t"] + _u(16); scroll.offset_bottom = -(sa["b"] + _u(16))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(minf(_u(430), get_viewport_rect().size.x - _u(64)), 0)
	vbox.add_theme_constant_override("separation", int(_u(12)))
	center.add_child(vbox)

	var accuracy := (float(hit_count) / float(total_notes) * 100.0) if total_notes > 0 else 0.0
	var stars := _calc_stars(accuracy)

	var result_title := Label.new()
	result_title.text = I18n.t("song_failed") if failed else I18n.t("result_title")
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_title.add_theme_font_size_override("font_size", _fs(36))
	var title_color := Color(1.0, 0.12, 0.08) if failed else UITheme.NEON_CYAN
	result_title.add_theme_color_override("font_color", title_color.lightened(0.18))
	result_title.add_theme_color_override("font_shadow_color", Color(title_color.r, title_color.g, title_color.b, 0.55))
	result_title.add_theme_constant_override("shadow_offset_x", 0)
	result_title.add_theme_constant_override("shadow_offset_y", 0)
	result_title.add_theme_constant_override("shadow_outline_size", int(_u(12)))
	if UITheme.font_bold():
		result_title.add_theme_font_override("font", UITheme.font_bold())
	vbox.add_child(result_title)
	if failed:
		var fail_reason := Label.new()
		fail_reason.text = I18n.t("rock_meter_empty")
		fail_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fail_reason.add_theme_font_size_override("font_size", _fs(19))
		fail_reason.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		vbox.add_child(fail_reason)

	# NEW RECORD badge
	if is_record and not failed:
		var record_lbl := Label.new()
		record_lbl.text = I18n.t("new_record")
		record_lbl.add_theme_font_size_override("font_size", _fs(27))
		record_lbl.add_theme_color_override("font_color", UITheme.NEON_MAGENTA.lightened(0.2))
		record_lbl.add_theme_color_override("font_shadow_color", Color(UITheme.NEON_MAGENTA.r, UITheme.NEON_MAGENTA.g, UITheme.NEON_MAGENTA.b, 0.5))
		record_lbl.add_theme_constant_override("shadow_offset_x", 0)
		record_lbl.add_theme_constant_override("shadow_offset_y", 0)
		record_lbl.add_theme_constant_override("shadow_outline_size", int(_u(12)))
		if UITheme.font_bold():
			record_lbl.add_theme_font_override("font", UITheme.font_bold())
		record_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(record_lbl)
		# Pulse the badge
		record_lbl.resized.connect(func(): record_lbl.pivot_offset = record_lbl.size / 2.0)
		var pulse := create_tween()
		pulse.set_loops()
		pulse.tween_property(record_lbl, "scale", Vector2(1.06, 1.06), 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(record_lbl, "scale", Vector2(1.0, 1.0), 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Stars — revealed one by one
	var star_hbox := HBoxContainer.new()
	star_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	star_hbox.add_theme_constant_override("separation", int(_u(6)))
	vbox.add_child(star_hbox)
	for si in range(5):
		var star_lbl := Label.new()
		var filled := si < stars
		star_lbl.text = "★" if filled else "☆"
		star_lbl.add_theme_font_size_override("font_size", _fs(46))
		if filled:
			star_lbl.add_theme_color_override("font_color", UITheme.NEON_GOLD)
			star_lbl.add_theme_color_override("font_shadow_color", Color(UITheme.NEON_GOLD.r, UITheme.NEON_GOLD.g, UITheme.NEON_GOLD.b, 0.5))
			star_lbl.add_theme_constant_override("shadow_offset_x", 0)
			star_lbl.add_theme_constant_override("shadow_offset_y", 0)
			star_lbl.add_theme_constant_override("shadow_outline_size", int(_u(10)))
		else:
			star_lbl.add_theme_color_override("font_color", Color(0.35, 0.33, 0.48))
		star_hbox.add_child(star_lbl)
		# Sequential pop-in for filled stars
		if filled:
			star_lbl.modulate.a = 0.0
			star_lbl.resized.connect(func(): star_lbl.pivot_offset = star_lbl.size / 2.0)
			star_lbl.scale = Vector2(2.2, 2.2)
			var stw := create_tween()
			stw.tween_interval(0.35 + si * 0.22)
			stw.tween_property(star_lbl, "modulate:a", 1.0, 0.18)
			stw.parallel().tween_property(star_lbl, "scale", Vector2(1.0, 1.0), 0.22) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Score — counts up
	var sc_lbl := Label.new()
	sc_lbl.text = "0"
	sc_lbl.add_theme_font_size_override("font_size", _fs(46))
	sc_lbl.add_theme_color_override("font_color", UITheme.TEXT_BRIGHT)
	sc_lbl.add_theme_color_override("font_shadow_color", Color(UITheme.NEON_CYAN.r, UITheme.NEON_CYAN.g, UITheme.NEON_CYAN.b, 0.35))
	sc_lbl.add_theme_constant_override("shadow_offset_x", 0)
	sc_lbl.add_theme_constant_override("shadow_offset_y", 0)
	sc_lbl.add_theme_constant_override("shadow_outline_size", int(_u(10)))
	if UITheme.font_bold():
		sc_lbl.add_theme_font_override("font", UITheme.font_bold())
	sc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sc_lbl)
	var count_tw := create_tween()
	count_tw.tween_method(func(v: float): sc_lbl.text = str(int(v)), 0.0, float(score), 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Stats card
	var stats_panel := PanelContainer.new()
	stats_panel.add_theme_stylebox_override("panel", UITheme.card_style())
	vbox.add_child(stats_panel)

	var stats_vbox := VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", int(_u(8)))
	stats_panel.add_child(stats_vbox)

	var stat_rows := [
		[I18n.t("accuracy"), "%d / %d  (%%%.1f)" % [hit_count, total_notes, accuracy]],
		[I18n.t("max_combo"), str(max_combo)],
		[I18n.t("missed"), str(miss_count)],
	]
	if not _solo_result_scores.is_empty():
		var solo_sum := 0.0
		for solo_score in _solo_result_scores:
			solo_sum += solo_score
		stat_rows.append([I18n.t("solo"), "%%%d" % int(roundf(solo_sum / float(_solo_result_scores.size())))])
	for row in stat_rows:
		var row_hbox := HBoxContainer.new()
		stats_vbox.add_child(row_hbox)
		var name_lbl := Label.new()
		name_lbl.text = row[0]
		name_lbl.add_theme_font_size_override("font_size", _fs(19))
		name_lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_hbox.add_child(name_lbl)
		var val_lbl := Label.new()
		val_lbl.text = row[1]
		val_lbl.add_theme_font_size_override("font_size", _fs(19))
		val_lbl.add_theme_color_override("font_color", UITheme.TEXT_BRIGHT)
		if UITheme.font_bold():
			val_lbl.add_theme_font_override("font", UITheme.font_bold())
		row_hbox.add_child(val_lbl)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, _u(10))
	vbox.add_child(spacer)

	# Base and assisted variants progress as pairs, ending with faithful charts.
	var preset_order: Array = PlayabilityScript.PRESET_ORDER
	var current_idx := preset_order.find(song_preset)
	if not failed and current_idx >= 0 and current_idx < preset_order.size() - 1:
		var next_preset: String = preset_order[current_idx + 1]
		var next_btn := Button.new()
		next_btn.text = I18n.t("next_preset", [I18n.preset_name(next_preset)])
		UITheme.style_primary_button(next_btn, UITheme.NEON_GREEN, _fs(22))
		next_btn.custom_minimum_size = Vector2(0, _u(66))
		next_btn.pressed.connect(func():
			song_preset = next_preset
			get_tree().reload_current_scene()
		)
		vbox.add_child(next_btn)
	elif not failed and current_idx == preset_order.size() - 1:
		# Completed Sadık — show congratulations
		var congrats := Label.new()
		congrats.text = I18n.t("all_levels_done")
		congrats.add_theme_font_size_override("font_size", _fs(21))
		congrats.add_theme_color_override("font_color", UITheme.NEON_GOLD)
		congrats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		congrats.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(congrats)

	# Retry button
	var retry_btn := Button.new()
	retry_btn.text = I18n.t("play_again")
	UITheme.style_primary_button(retry_btn, UITheme.NEON_CYAN, _fs(20))
	retry_btn.custom_minimum_size = Vector2(0, _u(62))
	retry_btn.pressed.connect(func(): get_tree().reload_current_scene())
	vbox.add_child(retry_btn)

	# Back to menu button
	var menu_btn := Button.new()
	menu_btn.text = I18n.t("song_list")
	UITheme.style_ghost_button(menu_btn, _fs(19))
	menu_btn.custom_minimum_size = Vector2(0, _u(60))
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	vbox.add_child(menu_btn)

	# Fade in
	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.4)

func _on_offset_changed(val: float) -> void:
	audio_offset_ms = val
	offset_label.text = I18n.t("offset_label", [int(val)])

func _exit_tree() -> void:
	if _music_duck_tween and _music_duck_tween.is_valid():
		_music_duck_tween.kill()
	var music_bus_idx := AudioServer.get_bus_index("Music")
	if music_bus_idx >= 0:
		AudioServer.set_bus_volume_db(music_bus_idx, MUSIC_BUS_GAIN_DB)
	for p in audio_players:
		if is_instance_valid(p):
			p.stop()
	if _crowd_ambience: _crowd_ambience.stop()
	if _crowd_reaction: _crowd_reaction.stop()
	_stop_crowd_burst_players()
