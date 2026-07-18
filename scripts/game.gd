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

# Layout params per orientation {portrait, landscape}
const LAYOUT := {
	"portrait": {
		"highway_ratio": 1.0,    # full width
		"hit_line_ratio": 0.82,  # from top (18% from bottom)
		"note_h_ratio": 0.55,   # note height = lane_width * this
		"approach_default": 1.4,
	},
	"landscape": {
		"highway_ratio": 0.60,  # 60% centered
		"hit_line_ratio": 0.85,
		"note_h_ratio": 0.42,
		"approach_default": 1.15,
	},
}

var _orientation: String = "portrait"  # set from Settings before _ready

const GUITAR_COLORS: Array[Color] = [
	Color(0.18, 0.85, 0.18),  Color(0.9, 0.15, 0.15),
	Color(0.9, 0.85, 0.1),    Color(0.25, 0.5, 1.0),
	Color(1.0, 0.55, 0.05),
]
const PIANO_COLORS: Array[Color] = [
	Color(0.18, 0.85, 0.18),  Color(0.9, 0.15, 0.15),
	Color(0.9, 0.85, 0.1),    Color(0.35, 0.55, 1.0),
]
const BG_COLOR := Color(0.06, 0.06, 0.08)
const LANE_BG := Color(0.12, 0.12, 0.15, 0.55)
const LANE_BORDER := Color(0.22, 0.22, 0.28, 0.4)
const HIT_LINE_COLOR := Color(1, 1, 1, 0.6)


# Note states: 0=active, 1=hit(darkened,scrolling), 2=missed, 3=sustain_holding
var notes: Array = []
var lyric_phrases: Array = []
var note_state: PackedByteArray = PackedByteArray()
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
var combo_label: Label
var lyric_panel: PanelContainer
var lyric_rtl: RichTextLabel
var warning_label: Label
var progress_bar: ProgressBar
var offset_slider: HSlider
var offset_label: Label
var milestone_label: Label
var rest_timer_label: Label

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

func _ready() -> void:
	Settings.load_settings()
	_orientation = Settings.orientation

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

	lane_pressed.resize(lane_count)
	held_sustain.resize(lane_count)
	for i in range(lane_count):
		lane_pressed[i] = false
		held_sustain[i] = -1

	_build_note_styles()
	_build_ui()
	_load_song()

# --- StyleBoxFlat caches ---

func _build_note_styles() -> void:
	note_styles.clear()
	note_styles_hit.clear()
	sustain_styles.clear()
	sustain_styles_hit.clear()
	sustain_styles_hold.clear()
	for c in lane_colors:
		# Active note
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(6)
		sb.border_color = c.lightened(0.35)
		sb.set_border_width_all(2)
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

	# Score — top center
	score_label = Label.new()
	score_label.text = "0"
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.anchor_left = 0.0; score_label.anchor_right = 1.0
	score_label.anchor_top = 0.0; score_label.offset_top = 8
	score_label.add_theme_font_size_override("font_size", 24)
	score_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 0.8))
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(score_label)

	# Progress bar — thin, top
	progress_bar = ProgressBar.new()
	progress_bar.show_percentage = false
	progress_bar.anchor_left = 0.0; progress_bar.anchor_right = 1.0
	progress_bar.anchor_top = 0.0; progress_bar.offset_top = 0
	progress_bar.size.y = 3
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(progress_bar)

	# Menu button — top left, small
	var back_btn := Button.new()
	back_btn.text = "< "
	back_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	back_btn.offset_left = 8; back_btn.offset_top = 6
	back_btn.size = Vector2(48, 32)
	back_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	back_btn.add_theme_font_size_override("font_size", 16)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	hud_root.add_child(back_btn)

	# Combo — big, positioned above hit line
	combo_label = Label.new()
	combo_label.text = ""
	combo_label.add_theme_font_size_override("font_size", 52)
	combo_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.anchor_left = 0.0; combo_label.anchor_right = 1.0
	var hlr2: float = _lp()["hit_line_ratio"]
	combo_label.anchor_top = hlr2 - 0.12; combo_label.anchor_bottom = hlr2 - 0.02
	combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# pivot_offset set after layout so scale animation centers properly
	combo_label.resized.connect(func(): combo_label.pivot_offset = combo_label.size / 2.0)
	hud_root.add_child(combo_label)

	# Lyrics box — positioned above combo label, near hit line
	lyric_panel = PanelContainer.new()
	var lyric_style := StyleBoxFlat.new()
	lyric_style.bg_color = Color(0.10, 0.10, 0.13, 0.0)
	lyric_style.set_corner_radius_all(14)
	lyric_style.content_margin_left = 20; lyric_style.content_margin_right = 20
	lyric_style.content_margin_top = 10; lyric_style.content_margin_bottom = 10
	lyric_panel.add_theme_stylebox_override("panel", lyric_style)
	lyric_panel.anchor_left = 0.05; lyric_panel.anchor_right = 0.95
	lyric_panel.anchor_top = hlr2 - 0.22; lyric_panel.anchor_bottom = hlr2 - 0.13
	lyric_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lyric_panel.visible = false
	hud_root.add_child(lyric_panel)

	lyric_rtl = RichTextLabel.new()
	lyric_rtl.bbcode_enabled = true
	lyric_rtl.fit_content = true
	lyric_rtl.scroll_active = false
	lyric_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lyric_rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lyric_rtl.add_theme_font_size_override("normal_font_size", 32)
	lyric_rtl.add_theme_color_override("default_color", Color(0.6, 0.6, 0.65))
	lyric_panel.add_child(lyric_rtl)

	offset_label = Label.new()
	offset_label.text = "Offset: 0 ms"
	offset_label.add_theme_font_size_override("font_size", 14)
	offset_label.anchor_left = 1.0; offset_label.anchor_right = 1.0; offset_label.anchor_top = 1.0
	offset_label.offset_left = -170; offset_label.offset_top = -62
	hud_root.add_child(offset_label)

	offset_slider = HSlider.new()
	offset_slider.min_value = -200; offset_slider.max_value = 200; offset_slider.step = 5; offset_slider.value = 0
	offset_slider.anchor_left = 1.0; offset_slider.anchor_right = 1.0; offset_slider.anchor_top = 1.0
	offset_slider.offset_left = -170; offset_slider.offset_top = -38
	offset_slider.size = Vector2(150, 20)
	offset_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	offset_slider.value_changed.connect(_on_offset_changed)
	hud_root.add_child(offset_slider)

	# Loading screen (separate CanvasLayer, above everything)
	_build_loading_screen()

	# Combo milestone popup
	milestone_label = Label.new()
	milestone_label.text = ""
	milestone_label.add_theme_font_size_override("font_size", 64)
	milestone_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
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
	rest_timer_label.add_theme_font_size_override("font_size", 40)
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
	warning_label.add_theme_font_size_override("font_size", 22)
	warning_label.add_theme_color_override("font_color", Color(1, 0.3, 0.2))
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	warning_label.size = Vector2(600, 40)
	warning_label.offset_left = -300; warning_label.offset_top = 60
	warning_label.visible = false
	hud_root.add_child(warning_label)

func _create_theme() -> Theme:
	var t := Theme.new()
	var font_bold := load("res://fonts/Inter-Bold.ttf") as Font
	var font_regular := load("res://fonts/Inter-Regular.ttf") as Font
	if font_bold:
		t.set_default_font(font_bold)
	if font_regular:
		t.set_font("font", "Label", font_regular)
		t.set_font("font", "RichTextLabel", font_regular)
	if font_bold:
		t.set_font("font", "Button", font_bold)
	t.set_color("font_color", "Label", Color(0.9, 0.9, 0.95))
	t.set_color("font_color", "Button", Color(0.9, 0.9, 0.95))
	t.set_font_size("font_size", "Label", 20)
	t.set_font_size("font_size", "Button", 20)

	var btn_n := StyleBoxFlat.new()
	btn_n.bg_color = Color(0.2, 0.45, 0.9, 0.85)
	btn_n.set_corner_radius_all(10)
	btn_n.content_margin_left = 20; btn_n.content_margin_right = 20
	btn_n.content_margin_top = 14; btn_n.content_margin_bottom = 14
	t.set_stylebox("normal", "Button", btn_n)
	var btn_h := btn_n.duplicate()
	btn_h.bg_color = Color(0.3, 0.55, 1.0)
	t.set_stylebox("hover", "Button", btn_h)
	var btn_p := btn_n.duplicate()
	btn_p.bg_color = Color(0.35, 0.6, 1.0)
	t.set_stylebox("pressed", "Button", btn_p)
	return t

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

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.offset_left = -220; vbox.offset_right = 220
	vbox.offset_top = -180; vbox.offset_bottom = 180
	vbox.add_theme_constant_override("separation", 10)
	root.add_child(vbox)

	# Album art
	var art_texture := _load_album_art_for_loading()
	if art_texture:
		var art_rect := TextureRect.new()
		art_rect.texture = art_texture
		art_rect.custom_minimum_size = Vector2(130, 130)
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
		art_panel.custom_minimum_size = Vector2(130, 130)
		art_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(art_panel)
		var art_icon := Label.new()
		art_icon.text = "♪"
		art_icon.add_theme_font_size_override("font_size", 56)
		art_icon.add_theme_color_override("font_color", Color(0.35, 0.35, 0.45))
		art_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		art_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		art_panel.add_child(art_icon)

	# Song title
	var parsed := _parse_loading_song_name()
	loading_song_label = Label.new()
	loading_song_label.text = parsed["title"]
	loading_song_label.add_theme_font_size_override("font_size", 30)
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
	loading_artist_label.add_theme_font_size_override("font_size", 20)
	loading_artist_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	loading_artist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_artist_label.visible = parsed["artist"] != ""
	vbox.add_child(loading_artist_label)

	# Info line: instrument + difficulty + preset
	var inst_display: String = ChartParserScript.INSTRUMENT_DISPLAY.get(song_instrument, song_instrument)
	loading_info_label = Label.new()
	loading_info_label.text = "%s  •  %s  •  %s" % [inst_display, song_difficulty, song_preset]
	loading_info_label.add_theme_font_size_override("font_size", 17)
	loading_info_label.add_theme_color_override("font_color", Color(0.4, 0.55, 0.9))
	loading_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(loading_info_label)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(spacer)

	# Status text
	loading_status_label = Label.new()
	loading_status_label.text = ""
	loading_status_label.add_theme_font_size_override("font_size", 22)
	loading_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	loading_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(loading_status_label)

	# Progress bar
	loading_bar = ProgressBar.new()
	loading_bar.show_percentage = false
	loading_bar.max_value = 100
	loading_bar.custom_minimum_size = Vector2(0, 8)
	loading_bar.visible = false

	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.12, 0.12, 0.16)
	bar_style.set_corner_radius_all(4)
	loading_bar.add_theme_stylebox_override("background", bar_style)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.3, 0.55, 1.0)
	bar_fill.set_corner_radius_all(4)
	loading_bar.add_theme_stylebox_override("fill", bar_fill)
	vbox.add_child(loading_bar)

	# Back button on loading screen
	var loading_back := Button.new()
	loading_back.text = "< Geri"
	loading_back.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	loading_back.offset_left = 12; loading_back.offset_top = 10
	loading_back.size = Vector2(80, 36)
	loading_back.add_theme_font_size_override("font_size", 16)
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
	var img := Image.new()
	if img.load_jpg_from_buffer(data) == OK:
		pass
	elif img.load_png_from_buffer(data) == OK:
		pass
	else:
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
	loading_status = "Chart yukleniyor"
	var source := song_source if song_source != "" else "res://notes.chart"
	var difficulty := song_difficulty if song_difficulty != "" else "Expert"
	var sng_loader: RefCounted = null
	var parse_ok := false
	var parsed_notes: Array = []
	var parsed_lyrics: Array = []
	var parsed_resolution: int = 480

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
				parsed_resolution = parser.resolution
				chart_offset_sec = parser.audio_offset_sec
				print("Game: parsed .chart from .sng (instrument=%s)" % song_instrument)
		if not parse_ok and sng_loader.has_midi():
			var midi_parser = MidiParserScript.new()
			var midi_data: PackedByteArray = sng_loader.get_midi_data()
			parse_ok = midi_parser.parse_data(midi_data, difficulty, song_instrument)
			if parse_ok:
				parsed_notes = midi_parser.notes
				parsed_lyrics = midi_parser.lyric_phrases
				parsed_resolution = midi_parser.resolution
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
		parsed_resolution = parser.resolution
		chart_offset_sec = parser.audio_offset_sec

	elif source.ends_with(".mid"):
		var midi_parser = MidiParserScript.new()
		parse_ok = midi_parser.parse_file(source, difficulty, song_instrument)
		if not parse_ok:
			push_error("Game: failed to parse .mid"); return
		parsed_notes = midi_parser.notes
		parsed_lyrics = midi_parser.lyric_phrases
		parsed_resolution = midi_parser.resolution

	elif _is_stfs_source(source):
		# Direct CON/LIVE loading
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
		parsed_resolution = midi_parser.resolution
		# Extract MOGG→OGG to temp dir for audio
		var mogg_data := stfs.get_mogg_data()
		if mogg_data.size() > 0:
			var tmp_dir := "user://sng_temp"
			_clear_dir(tmp_dir)
			DirAccess.make_dir_recursive_absolute(tmp_dir)
			var mogg := MoggHandlerScript.new()
			mogg.save_ogg_to_file(mogg_data, tmp_dir.path_join("song.ogg"))
			# Also save album art if available
			var art := stfs.get_album_art_data()
			if art.size() > 0:
				var art_ext := ".png"
				if art.size() >= 2 and art[0] == 0xFF and art[1] == 0xD8:
					art_ext = ".jpg"
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

	# Apply playability processing
	var playability = PlayabilityScript.new()
	playability.apply_preset(song_preset)
	notes = playability.process(notes, parsed_resolution, lane_count)

	if song_mode == "piano":
		_merge_piano_lanes()
		# Tiles mode: ensure no simultaneous notes after piano merge
		if song_preset == "Tiles":
			_dedup_simultaneous()

	note_state.resize(notes.size())
	note_state.fill(0)
	first_visible_idx = 0
	current_phrase_idx = 0
	total_notes = notes.size()
	hit_count = 0
	miss_count = 0

	print("Game: [%s][%s][%s] %d notes, %d phrases" % [song_instrument, song_mode, difficulty, notes.size(), lyric_phrases.size()])

	is_loading = true
	loading_status = "Ses hazirlaniyor"
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

func _merge_piano_lanes() -> void:
	# Build occupied set: time_key -> set of occupied lanes
	var occupied := {}  # "time_key" -> Dictionary{lane: true}
	for n in notes:
		if int(n["lane"]) <= 3:
			var key := "%.1f" % float(n["time_ms"])
			if not occupied.has(key):
				occupied[key] = {}
			occupied[key][int(n["lane"])] = true

	var merged: Array = []
	for n in notes:
		if int(n["lane"]) == 4:
			var key := "%.1f" % float(n["time_ms"])
			if not occupied.has(key):
				occupied[key] = {}
			# Try lane 3 first, then nearest free lane
			var placed := false
			for try_lane in [3, 2, 1, 0]:
				if not occupied[key].has(try_lane):
					n["lane"] = try_lane
					occupied[key][try_lane] = true
					placed = true
					break
			if not placed:
				continue  # all 4 lanes full — drop note
		merged.append(n)
	notes = merged

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
		_show_audio_error("Ses dosyasi bulunamadi!")
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

	loading_status = "Ses hazırlanıyor"
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
			_show_audio_error("Ses işlenemedi!")
			is_loading = false
			return
		print("Audio: processing complete — %s" % cached_path)
		loading_status = "Ses yükleniyor"
		var stream := _load_cached(cached_path)
		if stream == null:
			_show_audio_error("Ses dosyasi yüklenemedi!")
			is_loading = false
			return
		_setup_single_player(stream)

func _load_cached(path: String) -> AudioStream:
	if path.ends_with(".wav"):
		return _load_wav_file(path)
	return AudioStreamOggVorbis.load_from_file(path)

func _setup_single_player(stream: AudioStream) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	audio_players.append(player)
	master_player = player
	print("Audio: 1 player ready")
	is_loading = false
	_countdown = 3.0


func _decode_android_async(inputs: Array[String], output: String) -> void:
	if not Engine.has_singleton("NativeAudioDecoder"):
		push_error("Audio: NativeAudioDecoder singleton not found!")
		_show_audio_error("NativeAudioDecoder bulunamadı!")
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
	loading_status = "Ses yükleniyor"
	loading_progress = 95
	var stream := _load_cached(cached_path)
	if stream == null:
		_show_audio_error("Ses dosyasi yüklenemedi!")
		is_loading = false
		return
	_setup_single_player(stream)

func _on_decode_failed(error: String) -> void:
	push_error("Audio: NativeAudioDecoder failed — %s" % error)
	if error == "Cancelled":
		return  # User navigated away, don't show error
	_show_audio_error("Ses işlenemedi!")
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

# --- Playback ---

func _start_playback() -> void:
	song_started = true
	_first_hit_logged = false
	_hit_log_count = 0
	_start_ticks = Time.get_ticks_msec()
	_play_call_time_ms = _start_ticks
	for player in audio_players:
		player.play()
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

func _process(delta: float) -> void:
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

	# State: countdown before play
	if _countdown > 0:
		_countdown -= delta
		if loading_status_label:
			loading_status_label.text = str(ceili(_countdown))
			loading_status_label.add_theme_font_size_override("font_size", 64)
		if loading_bar:
			loading_bar.visible = false
		queue_redraw()
		if _countdown <= 0:
			_hide_loading_screen()
			_start_playback()
		return

	if not song_started:
		return

	song_time_ms = _get_song_time_ms()

	# Mark active notes past hit window as missed
	for idx in range(first_visible_idx, notes.size()):
		var t: float = notes[idx]["time_ms"]
		if t > song_time_ms + HIT_WINDOW_MS:
			break
		if note_state[idx] == 0 and song_time_ms - t > HIT_WINDOW_MS:
			note_state[idx] = 2
			combo = 0
			_update_combo_tier()
			miss_count += 1
			_miss_flash_alpha = 1.0
			_miss_lane_flashes.append({"lane": int(notes[idx]["lane"]), "alpha": 1.0})

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

		if not lane_pressed[lane]:
			# Released early — becomes hit (darkened, scrolling)
			note_state[idx] = 1
			held_sustain[lane] = -1
		elif song_time_ms >= end_time:
			# Sustain completed
			note_state[idx] = 1
			held_sustain[lane] = -1
			score += int(25.0 * _combo_multiplier)

func _update_lyrics() -> void:
	if lyric_phrases.is_empty():
		lyric_panel.visible = false; return
	while current_phrase_idx < lyric_phrases.size():
		if float(lyric_phrases[current_phrase_idx]["end_ms"]) >= song_time_ms:
			break
		current_phrase_idx += 1
	if current_phrase_idx < lyric_phrases.size():
		var phrase = lyric_phrases[current_phrase_idx]
		var start: float = phrase["start_ms"]
		var end: float = phrase["end_ms"]
		if song_time_ms >= start - 300 and song_time_ms <= end:
			lyric_rtl.text = _build_highlighted_bbcode(phrase)
			lyric_panel.visible = true
			return
	lyric_panel.visible = false

func _build_highlighted_bbcode(phrase: Dictionary) -> String:
	var full_text: String = phrase["text"]
	var syllables: Array = phrase["syllables"]
	if syllables.is_empty():
		return "[center]" + full_text + "[/center]"
	var sung_end := 0
	for syl in syllables:
		if float(syl["time_ms"]) <= song_time_ms:
			sung_end = int(syl["char_end"])
		else:
			break
	return "[center][color=#FFD700]%s[/color][color=#666670]%s[/color][/center]" % [
		full_text.substr(0, sung_end), full_text.substr(sung_end)]

func _update_hud() -> void:
	score_label.text = str(score)
	if combo >= 2:
		var tier_txt := _get_combo_tier_label()
		if tier_txt != "":
			combo_label.text = "%d Combo  %s" % [combo, tier_txt]
			combo_label.add_theme_color_override("font_color", _combo_glow_color.lightened(0.4))
		else:
			combo_label.text = "%d Combo" % combo
			combo_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	else:
		combo_label.text = ""
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

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), BG_COLOR)
	if is_loading or _countdown > 0:
		return

	var lw := _lane_width()
	var ls := _lanes_start_x()
	var hit_y := _hit_line_y()

	# Lane backgrounds
	for idx in range(lane_count):
		var x := ls + idx * lw
		draw_rect(Rect2(x, 0, lw, vp.y), LANE_BG)
		draw_line(Vector2(x, 0), Vector2(x, vp.y), LANE_BORDER, 1.0)
	draw_line(Vector2(ls + lane_count * lw, 0), Vector2(ls + lane_count * lw, vp.y), LANE_BORDER, 1.0)

	# Hit line
	draw_line(Vector2(ls, hit_y), Vector2(ls + lane_count * lw, hit_y), HIT_LINE_COLOR, 2.0)

	# Hit zone — large squares filling each lane
	var hz_h := lw * 0.9  # square height ≈ lane width
	var hz_margin := lw * 0.04
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
			var gz_pulse := 0.1 * sin(Time.get_ticks_msec() * 0.005)
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

	# Miss flash — red edges (thick + visible)
	if _miss_flash_alpha > 0:
		var mf_a := _miss_flash_alpha * 0.6
		var mf_col := Color(1, 0.1, 0.05, mf_a)
		var edge_w := 14.0
		draw_rect(Rect2(0, 0, edge_w, vp.y), mf_col)
		draw_rect(Rect2(vp.x - edge_w, 0, edge_w, vp.y), mf_col)
		draw_rect(Rect2(0, 0, vp.x, edge_w), mf_col)
		draw_rect(Rect2(0, vp.y - edge_w, vp.x, edge_w), mf_col)

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
	var margin := lw * 0.06

	for idx in range(first_visible_idx, notes.size()):
		var n = notes[idx]
		var t: float = n["time_ms"]
		var time_until := t - song_time_ms
		var state: int = note_state[idx]

		# Too far in future
		if time_until > _approach_time_ms():
			break
		# Missed — don't draw
		if state == 2:
			continue

		var lane: int = n["lane"]
		if lane >= lane_count:
			continue

		var x := ls + lane * lw + margin
		var w := lw - margin * 2.0
		var ratio := 1.0 - (time_until / _approach_time_ms())
		var y := ratio * hit_y - note_h / 2.0

		var is_hit := (state == 1)
		var is_holding := (state == 3)

		# Alpha fade: notes fade in as they approach (0.2 at top -> 1.0 at 40% travel)
		var note_alpha := clampf(ratio / 0.4, 0.2, 1.0) if not is_hit else 0.5

		# Off-screen below — skip
		if is_hit and y > vp.y + note_h:
			continue

		var dur_ms: float = n["duration_ms"]

		# --- Sustain tail ---
		if dur_ms > 0:
			var tail_until := (t + dur_ms) - song_time_ms
			var tail_ratio := 1.0 - (tail_until / _approach_time_ms())
			var tail_y := tail_ratio * hit_y - note_h / 2.0

			var sx := x + w * 0.3
			var sw := w * 0.4

			if is_holding:
				# While holding: clip tail top to current position, head at hit line
				var hold_top := maxf(tail_y, 0)
				var hold_bottom := hit_y
				if hold_bottom > hold_top:
					# Pulse effect
					var pulse := 0.15 * sin(Time.get_ticks_msec() * 0.008)
					var hold_style := sustain_styles_hold[lane]
					hold_style.bg_color = lane_colors[lane] * Color(1, 1, 1, 0.65 + pulse)
					draw_style_box(hold_style, Rect2(sx, hold_top, sw, hold_bottom - hold_top + note_h))
				# Head stays at hit line — with glow if active tier
				if _combo_glow_color.a > 0:
					var glow_expand := 4.0
					var glow_col := Color(_combo_glow_color.r, _combo_glow_color.g, _combo_glow_color.b, _combo_glow_color.a * 0.8)
					draw_rect(Rect2(x - glow_expand, hit_y - note_h / 2.0 - glow_expand, w + glow_expand * 2, note_h + glow_expand * 2), glow_col)
				draw_style_box(note_styles[lane], Rect2(x, hit_y - note_h / 2.0, w, note_h))
				continue
			elif is_hit:
				# Hit sustain: darkened tail
				if y - tail_y + note_h > 0:
					draw_style_box(sustain_styles_hit[lane], Rect2(sx, tail_y, sw, y - tail_y + note_h))
			else:
				# Active sustain
				if y - tail_y + note_h > 0:
					draw_style_box(sustain_styles[lane], Rect2(sx, tail_y, sw, y - tail_y + note_h))

		# --- Note head ---
		if is_hit:
			var sh := note_styles_hit[lane]
			sh.bg_color.a = note_alpha
			draw_style_box(sh, Rect2(x, y, w, note_h))
		elif not is_holding:
			# Combo glow — expanded colored rect behind note
			if _combo_glow_color.a > 0:
				var glow_expand := 4.0
				var pulse := 0.15 * sin(Time.get_ticks_msec() * 0.006)
				var glow_a := (_combo_glow_color.a + pulse) * note_alpha
				var glow_col := Color(_combo_glow_color.r, _combo_glow_color.g, _combo_glow_color.b, glow_a)
				draw_rect(Rect2(x - glow_expand, y - glow_expand, w + glow_expand * 2, note_h + glow_expand * 2), glow_col)
			var sn := note_styles[lane]
			var orig_a := sn.bg_color.a
			sn.bg_color.a = note_alpha
			sn.border_color.a = note_alpha
			draw_style_box(sn, Rect2(x, y, w, note_h))
			sn.bg_color.a = orig_a
			sn.border_color.a = orig_a

# --- Layout ---

func _lp() -> Dictionary:
	return LAYOUT[_orientation]

func _lane_width() -> float:
	return get_viewport_rect().size.x * float(_lp()["highway_ratio"]) / float(lane_count)

func _lanes_start_x() -> float:
	return (get_viewport_rect().size.x - float(lane_count) * _lane_width()) / 2.0

func _hit_line_y() -> float:
	return get_viewport_rect().size.y * float(_lp()["hit_line_ratio"])

func _note_height() -> float:
	return _lane_width() * float(_lp()["note_h_ratio"])

func _approach_time_ms() -> float:
	return Settings.get_approach_ms()

# --- Input (press AND release) ---

func _input(event: InputEvent) -> void:
	if not song_started or is_loading or _countdown > 0:
		return

	var lane := -1
	var pressed := false

	if event is InputEventScreenTouch:
		lane = _pos_to_lane(event.position)
		pressed = event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		lane = _pos_to_lane(event.position)
		pressed = event.pressed
	elif event is InputEventKey and not event.echo:
		lane = _key_to_lane(event.keycode)
		pressed = event.pressed

	if lane < 0:
		return

	if pressed:
		lane_pressed[lane] = true
		_try_hit(lane)
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

func _try_hit(lane: int) -> void:
	var best_idx := -1
	var best_diff := HIT_WINDOW_MS + 1.0

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

	if best_idx < 0 or best_diff > HIT_WINDOW_MS:
		return

	var n = notes[best_idx]
	var dur: float = n["duration_ms"]

	if dur > 0:
		# Sustain — enter holding state
		note_state[best_idx] = 3
		held_sustain[lane] = best_idx
	else:
		# Regular — hit (darkened, scrolling)
		note_state[best_idx] = 1

	combo += 1
	hit_count += 1
	if combo > max_combo:
		max_combo = combo
	_update_combo_tier()
	score += int(50.0 * _combo_multiplier)

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

	# Hit flash + expanding ring
	hit_effects.append({"lane": lane, "alpha": 0.8})
	hit_rings.append({"lane": lane, "radius": _lane_width() * 0.3, "alpha": 0.9})

	# Combo scale animation
	if combo >= 2:
		var tw := create_tween()
		tw.tween_property(combo_label, "scale", Vector2(1.25, 1.25), 0.07)
		tw.tween_property(combo_label, "scale", Vector2(1.0, 1.0), 0.08)

	# Combo milestones — show tier unlock
	if combo in [25, 50, 100, 200, 300, 500]:
		var tier_label := _get_combo_tier_label()
		_show_milestone("%d COMBO! %s" % [combo, tier_label])

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

func _show_milestone(text: String) -> void:
	milestone_label.text = text
	milestone_label.modulate.a = 1.0
	milestone_label.scale = Vector2(0.5, 0.5)
	var tw := create_tween()
	tw.tween_property(milestone_label, "scale", Vector2(1.2, 1.2), 0.15).set_ease(Tween.EASE_OUT)
	tw.tween_property(milestone_label, "scale", Vector2(1.0, 1.0), 0.1)
	tw.tween_interval(0.6)
	tw.tween_property(milestone_label, "modulate:a", 0.0, 0.3)

func _on_song_finished() -> void:
	song_started = false
	# Count remaining active notes as missed
	for idx in range(notes.size()):
		if note_state[idx] == 0:
			miss_count += 1
	total_notes = notes.size()
	# Save score and go to result screen
	_save_score()
	_show_result_screen()

func _save_score() -> void:
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
	if not scores.has(key) or int(scores[key].get("score", 0)) < score:
		scores[key] = entry
		var f := FileAccess.open(scores_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(scores))
			f.close()

func _calc_stars(accuracy: float) -> int:
	if accuracy >= 98: return 5
	if accuracy >= 90: return 4
	if accuracy >= 75: return 3
	if accuracy >= 50: return 2
	if accuracy >= 25: return 1
	return 0

func _show_result_screen() -> void:
	# Build result screen as overlay
	var result_layer := CanvasLayer.new()
	result_layer.layer = 20
	add_child(result_layer)

	var panel := ColorRect.new()
	panel.color = Color(0.04, 0.04, 0.06, 0.95)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.theme = _create_theme()
	result_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.offset_left = -200; vbox.offset_right = 200
	vbox.offset_top = -220; vbox.offset_bottom = 220
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var accuracy := (float(hit_count) / float(total_notes) * 100.0) if total_notes > 0 else 0.0
	var stars := _calc_stars(accuracy)

	# Stars
	var star_label := Label.new()
	var star_text := ""
	for si in range(5):
		star_text += "[fill]" if si < stars else "[empty]"
	star_label.text = star_text.replace("[fill]", "★").replace("[empty]", "☆")
	star_label.add_theme_font_size_override("font_size", 48)
	star_label.add_theme_color_override("font_color", Color(1, 0.85, 0.15))
	star_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(star_label)

	# Score
	var sc_lbl := Label.new()
	sc_lbl.text = "Skor: %d" % score
	sc_lbl.add_theme_font_size_override("font_size", 36)
	sc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sc_lbl)

	# Stats
	var stats := Label.new()
	stats.text = "Isabet: %d / %d  (%%%.1f)\nMaks Kombo: %d\nKaçan: %d" % [
		hit_count, total_notes, accuracy, max_combo, miss_count]
	stats.add_theme_font_size_override("font_size", 22)
	stats.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	# Next preset progression: Tiles → Rahat → Normal → Sadık
	var preset_order := ["Tiles", "Rahat", "Normal", "Sadik"]
	var current_idx := preset_order.find(song_preset)
	if current_idx >= 0 and current_idx < preset_order.size() - 1:
		var next_preset: String = preset_order[current_idx + 1]
		var next_btn := Button.new()
		next_btn.text = "Sonraki: %s" % next_preset
		next_btn.add_theme_font_size_override("font_size", 24)
		next_btn.custom_minimum_size = Vector2(250, 56)
		var next_style := StyleBoxFlat.new()
		next_style.bg_color = Color(0.15, 0.65, 0.3)
		next_style.set_corner_radius_all(10)
		next_style.content_margin_left = 20; next_style.content_margin_right = 20
		next_style.content_margin_top = 14; next_style.content_margin_bottom = 14
		next_btn.add_theme_stylebox_override("normal", next_style)
		var next_hover := next_style.duplicate()
		next_hover.bg_color = Color(0.2, 0.75, 0.35)
		next_btn.add_theme_stylebox_override("hover", next_hover)
		next_btn.pressed.connect(func():
			song_preset = next_preset
			get_tree().reload_current_scene()
		)
		vbox.add_child(next_btn)
	elif current_idx == preset_order.size() - 1:
		# Completed Sadık — show congratulations
		var congrats := Label.new()
		congrats.text = "Tebrikler! Tum seviyeleri tamamladin!"
		congrats.add_theme_font_size_override("font_size", 22)
		congrats.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
		congrats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		congrats.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(congrats)

	# Retry button
	var retry_btn := Button.new()
	retry_btn.text = "Tekrar Oyna"
	retry_btn.add_theme_font_size_override("font_size", 24)
	retry_btn.custom_minimum_size = Vector2(250, 56)
	retry_btn.pressed.connect(func(): get_tree().reload_current_scene())
	vbox.add_child(retry_btn)

	# Back to menu button
	var menu_btn := Button.new()
	menu_btn.text = "Sarki Listesi"
	menu_btn.add_theme_font_size_override("font_size", 24)
	menu_btn.custom_minimum_size = Vector2(250, 56)
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	vbox.add_child(menu_btn)

	# Fade in
	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.4)

func _on_offset_changed(val: float) -> void:
	audio_offset_ms = val
	offset_label.text = "Offset: %d ms" % int(val)

func _exit_tree() -> void:
	for p in audio_players:
		if is_instance_valid(p):
			p.stop()
