extends Control

const GameScript = preload("res://scripts/game.gd")
const ChartParserScript = preload("res://scripts/chart_parser.gd")
const MidiParserScript = preload("res://scripts/midi_parser.gd")
const SngLoaderScript = preload("res://scripts/sng_loader.gd")
const StfsParserScript = preload("res://scripts/stfs_parser.gd")
const DtaParserScript = preload("res://scripts/dta_parser.gd")
const MoggHandlerScript = preload("res://scripts/mogg_handler.gd")
const PlayabilityScript = preload("res://scripts/playability.gd")

const BG_COLOR := UITheme.ROCK_COAL
const ACCENT := UITheme.ROCK_RED
const CARD_BG := Color(0.065, 0.052, 0.046, 0.97)
const CARD_SELECTED := Color(0.18, 0.075, 0.045)
const TEXT_DIM := UITheme.ROCK_PARCHMENT
const TEXT_BRIGHT := UITheme.ROCK_IVORY
const STAR_COLOR := UITheme.ROCK_AMBER_HOT

var card_container: VBoxContainer
var found_songs: Array = []
var card_panels: Array = []
var saved_scores: Dictionary = {}

const USER_SONGS_DIR := "user://songs"
const HIDDEN_BUNDLED_SONG_PATHS := ["res://notes.chart"]
const MIX_CACHE_DIR := "user://cache"
const THUMB_CACHE_DIR := "user://menu_thumbnails"
const SECRET_TAP_COUNT := 5
const SECRET_TAP_WINDOW_MS := 1600
const CUSTOM_HIGHWAY_MAX_BYTES := 16 * 1024 * 1024
const CUSTOM_HIGHWAY_MAX_PIXELS := 16 * 1024 * 1024
const CUSTOM_HIGHWAY_MAX_WIDTH := 1024
const CUSTOM_HIGHWAY_MAX_HEIGHT := 2048
const CHORUS_ENCORE_URL := "https://www.enchor.us/"
const RHYTHMVERSE_URL := "https://rhythmverse.co/"

# Import status
var _import_status_label: Label = null
var _import_progress_label: Label = null
var _import_progress_bar: ProgressBar = null
var _import_in_progress: bool = false
var _import_pending_folder: String = ""
var _import_pending_raw_ogg: String = ""
var _import_decode_plugin = null
var _import_thread: Thread = null

# Scroll-friendly tap detection
var _card_touch_start: Vector2 = Vector2.ZERO
var _card_touch_index: int = -1
const SCROLL_TAP_THRESHOLD := 20.0  # pixels — beyond this it's a scroll, not a tap

# Launch screen state
var _launch_overlay: Control = null
var _launch_song_index: int = -1
# Scanned instrument data: {instrument_key: [difficulties]}
var _launch_instruments: Dictionary = {}
var _launch_selected_instrument: String = ""
var _launch_instrument_btns: Dictionary = {}  # instrument_key -> Button
var _launch_diff_btns: Dictionary = {}  # difficulty -> Button
var _launch_selected_difficulty: String = "Expert"
var _launch_selected_preset: String = "Tiles"
var _launch_preset_btns: Dictionary = {}       # preset -> Button
var _launch_selected_mode: String = "piano"    # "piano" or "guitar"
var _launch_mode_btns: Dictionary = {}         # mode -> Button
var _launch_view_btns: Dictionary = {}         # "gh"/"flat" -> Button
var _launch_vfx_btns: Dictionary = {}          # quality -> Button
var _launch_rock_meter_btns: Dictionary = {}   # "off"/"visual"/"fail" -> Button
var _launch_crowd_btns: Dictionary = {}        # "on"/"off" -> Button
var _launch_miss_sfx_btns: Dictionary = {}     # "on"/"off" -> Button
var _launch_approach_slider: HSlider
var _launch_approach_label: Label
var _launch_star_label: Label
var _tutorial_overlay: Control = null
var _guitar_presentation_btns: Dictionary = {}
var _arena_fret_btns: Dictionary = {}
var _guitar_theme_btns: Dictionary = {}
var _arena_highway_status_label: Label = null
var _last_tutorial_body: Label = null
var _secret_body_label: Label = null
var _secret_tap_count: int = 0
var _secret_tap_deadline_ms: int = 0
var _native_picker_context: String = ""
var _pixel_stage_btns: Dictionary = {}
var _stage_intensity_btns: Dictionary = {}
var _battle_overlay: Control = null
var _battle_mode: String = "battle"
var _battle_status_label: Label = null
var _battle_players_box: VBoxContainer = null
var _battle_name_edit: LineEdit = null
var _battle_code_edit: LineEdit = null
var _battle_song_option: OptionButton = null
var _battle_instrument_option: OptionButton = null
var _battle_difficulty_option: OptionButton = null
var _battle_preset_option: OptionButton = null
var _battle_game_mode_option: OptionButton = null
var _battle_transfer_label: Label = null
var _battle_transfer_bar: ProgressBar = null
var _battle_ready_button: Button = null
var _battle_start_button: Button = null
var _battle_lobby_controls: VBoxContainer = null
var _battle_connection_panel: PanelContainer = null
var _battle_mode_buttons: Dictionary = {}
var _battle_rendered_song_fingerprint: String = ""
var _battle_back_button: Button = null
var _main_actions_container: VBoxContainer = null

var _menu_loading_label: Label = null
var _menu_loading_layer: CanvasLayer = null
var _menu_loading_bar: ProgressBar = null
var _song_count_label: Label = null
var _scan_generation: int = 0
var _ui_scale: float = 1.0

func _ready() -> void:
	Settings.load_settings()
	_ui_scale = _detect_ui_scale()
	print("Menu UI: scale=%.2f dpi=%d viewport=%s" % [
		_ui_scale, DisplayServer.screen_get_dpi(), str(get_viewport_rect().size)])
	_load_scores()
	_build_ui()
	BattleSession.set_song_catalog(found_songs)
	if not BattleSession.state_changed.is_connected(_on_battle_state_changed):
		BattleSession.state_changed.connect(_on_battle_state_changed)
	if not BattleSession.lobby_changed.is_connected(_on_battle_lobby_changed):
		BattleSession.lobby_changed.connect(_on_battle_lobby_changed)
	if not BattleSession.session_error.is_connected(_on_battle_error):
		BattleSession.session_error.connect(_on_battle_error)
	if not BattleSession.song_transfer_progress_changed.is_connected(
			_on_battle_song_transfer_progress):
		BattleSession.song_transfer_progress_changed.connect(
			_on_battle_song_transfer_progress)
	if not BattleSession.song_transfer_completed.is_connected(
			_on_battle_song_transfer_completed):
		BattleSession.song_transfer_completed.connect(
			_on_battle_song_transfer_completed)
	_scan_songs()

# Android phones often have much higher pixel density than tablets. Scale
# controls by DPI, but cap it using the logical viewport so portrait layouts
# never become wider than the screen.
func _detect_ui_scale() -> float:
	var dpi := float(DisplayServer.screen_get_dpi())
	var density_scale := clampf(dpi / 220.0, 1.0, 1.85) if dpi > 0.0 else 1.0
	# A few Android vendors report a generic/invalid DPI. Keep those devices
	# comfortably touchable instead of silently falling back to desktop sizing.
	if OS.has_feature("android") and dpi <= 160.0:
		density_scale = 1.25
	var short_edge := minf(get_viewport_rect().size.x, get_viewport_rect().size.y)
	var viewport_cap := clampf(short_edge / 480.0, 1.0, 1.70)
	return minf(density_scale, viewport_cap)

func _u(value: float) -> float:
	return roundf(value * _ui_scale)

func _fs(value: float) -> int:
	return maxi(1, int(roundf(value * _ui_scale)))

func _is_compact_layout() -> bool:
	var viewport_size := get_viewport_rect().size
	return viewport_size.x < 760.0 or viewport_size.y > viewport_size.x * 1.12

func _section_label(text: String) -> Label:
	var label := UITheme.section_label(text)
	label.add_theme_font_size_override("font_size", _fs(15))
	label.add_theme_color_override("font_color", UITheme.ROCK_PARCHMENT)
	return label

func _set_menu_loading(on: bool, progress: float = -1.0) -> void:
	if _menu_loading_layer == null:
		_build_menu_loading_screen()
	_menu_loading_layer.visible = on
	if _menu_loading_bar:
		_menu_loading_bar.visible = progress >= 0.0
		if progress >= 0.0:
			_menu_loading_bar.value = clampf(progress, 0.0, 100.0)

func _build_menu_loading_screen() -> void:
	_menu_loading_layer = CanvasLayer.new()
	_menu_loading_layer.layer = 50
	add_child(_menu_loading_layer)

	var bg := ColorRect.new()
	bg.color = UITheme.BG_BOTTOM
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.theme = _create_theme()
	_menu_loading_layer.add_child(bg)
	UITheme.add_hardrock_background(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var box_w := minf(_u(440), get_viewport_rect().size.x - _u(48))
	vbox.offset_left = -box_w * 0.5
	vbox.offset_right = box_w * 0.5
	vbox.offset_top = -_u(130)
	vbox.offset_bottom = _u(130)
	vbox.add_theme_constant_override("separation", int(_u(20)))
	bg.add_child(vbox)

	var title := Label.new()
	title.text = I18n.t("app_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", _fs(42))
	title.add_theme_color_override("font_color", ACCENT.lightened(0.35))
	title.add_theme_color_override("font_shadow_color", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_constant_override("shadow_outline_size", int(_u(16)))
	if UITheme.font_bold():
		title.add_theme_font_override("font", UITheme.font_bold())
	vbox.add_child(title)

	_menu_loading_label = Label.new()
	_menu_loading_label.text = I18n.t("loading") + "..."
	_menu_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_loading_label.add_theme_font_size_override("font_size", _fs(24))
	_menu_loading_label.add_theme_color_override("font_color", UITheme.TEXT_BRIGHT)
	vbox.add_child(_menu_loading_label)

	_menu_loading_bar = ProgressBar.new()
	_menu_loading_bar.show_percentage = false
	_menu_loading_bar.max_value = 100.0
	_menu_loading_bar.custom_minimum_size = Vector2(0, _u(10))
	_menu_loading_bar.add_theme_stylebox_override("background", UITheme.flat_style(Color(1, 1, 1, 0.08), 5))
	_menu_loading_bar.add_theme_stylebox_override("fill", UITheme.flat_style(ACCENT, 5))
	vbox.add_child(_menu_loading_bar)

	var pulse := create_tween()
	pulse.set_loops()
	pulse.tween_property(_menu_loading_label, "modulate:a", 0.45, 0.65).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_menu_loading_label, "modulate:a", 1.0, 0.65).set_trans(Tween.TRANS_SINE)

func _load_scores() -> void:
	var path := "user://scores.json"
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var json := JSON.new()
			if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
				saved_scores = json.data
			f.close()

func _create_theme() -> Theme:
	var theme := UITheme.create_theme()
	theme.set_font_size("font_size", "Label", _fs(19))
	theme.set_font_size("font_size", "Button", _fs(19))
	theme.set_font_size("font_size", "OptionButton", _fs(17))
	var slider_fill := UITheme.glow_style(
		Color(UITheme.ROCK_RED.r, UITheme.ROCK_RED.g, UITheme.ROCK_RED.b, 0.62),
		UITheme.ROCK_RED, 4, 5)
	theme.set_stylebox("grabber_area", "HSlider", slider_fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	var progress_fill := UITheme.glow_style(
		Color(
			UITheme.ROCK_STEEL_LIGHT.r,
			UITheme.ROCK_STEEL_LIGHT.g,
			UITheme.ROCK_STEEL_LIGHT.b,
			0.78),
		UITheme.ROCK_STEEL_LIGHT, 4, 5)
	theme.set_stylebox("fill", "ProgressBar", progress_fill)
	return theme

func _build_ui() -> void:
	UITheme.add_hardrock_background(self)

	var theme := _create_theme()
	var compact := _is_compact_layout()

	# Safe area
	var sa := UITheme.safe_insets(self)

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var side_margin := _u(8 if compact else 18)
	root.add_theme_constant_override("margin_left", int(sa["l"] + side_margin))
	root.add_theme_constant_override("margin_right", int(sa["r"] + side_margin))
	root.add_theme_constant_override(
		"margin_top", int(sa["t"] + _u(8 if compact else 12)))
	root.add_theme_constant_override(
		"margin_bottom", int(sa["b"] + _u(8 if compact else 12)))
	root.theme = theme
	add_child(root)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", int(_u(10 if compact else 14)))
	root.add_child(main_vbox)

	# --- Hero masthead: crest, game identity and large utility controls ---
	var header_panel := PanelContainer.new()
	var header_style := UITheme.glow_style(
		Color(0.035, 0.029, 0.026, 0.97), UITheme.ROCK_RED, 5, 8)
	header_style.set_border_width_all(1)
	header_style.border_color = UITheme.ROCK_STEEL
	header_style.border_width_left = int(_u(5))
	header_style.border_width_bottom = int(_u(5))
	header_style.content_margin_left = _u(10 if compact else 16)
	header_style.content_margin_right = _u(10 if compact else 16)
	header_style.content_margin_top = _u(8 if compact else 10)
	header_style.content_margin_bottom = _u(8 if compact else 10)
	header_panel.add_theme_stylebox_override("panel", header_style)
	main_vbox.add_child(header_panel)

	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, _u(68 if compact else 88))
	header.add_theme_constant_override("separation", int(_u(8 if compact else 14)))
	header_panel.add_child(header)

	header.add_child(UITheme.make_game_logo(_u(52 if compact else 78)))

	var brand := VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.add_theme_constant_override("separation", int(_u(-2)))
	brand.clip_contents = true
	header.add_child(brand)

	var brand_kicker := Label.new()
	brand_kicker.text = I18n.t("menu_kicker")
	brand_kicker.add_theme_font_size_override("font_size", _fs(14))
	brand_kicker.add_theme_color_override("font_color", UITheme.ROCK_PARCHMENT)
	brand_kicker.visible = not compact
	if UITheme.font_bold():
		brand_kicker.add_theme_font_override("font", UITheme.font_bold())
	brand.add_child(brand_kicker)

	var title := Label.new()
	title.text = I18n.t("app_title").to_upper()
	title.add_theme_font_size_override("font_size", _fs(29 if compact else 43))
	title.add_theme_color_override("font_color", TEXT_BRIGHT)
	title.add_theme_color_override(
		"font_shadow_color",
		Color(UITheme.ROCK_RED.r, UITheme.ROCK_RED.g, UITheme.ROCK_RED.b, 0.62))
	title.add_theme_constant_override("shadow_offset_x", int(_u(2)))
	title.add_theme_constant_override("shadow_offset_y", int(_u(3)))
	title.add_theme_constant_override("shadow_outline_size", int(_u(7)))
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if UITheme.font_bold():
		title.add_theme_font_override("font", UITheme.font_bold())
	brand.add_child(title)

	var subtitle := Label.new()
	subtitle.text = I18n.t("menu_subtitle")
	subtitle.add_theme_font_size_override("font_size", _fs(14))
	subtitle.add_theme_color_override("font_color", TEXT_DIM)
	subtitle.visible = not compact
	brand.add_child(subtitle)

	var guitar_visuals_btn := Button.new()
	guitar_visuals_btn.text = "FX" if compact else "FX\n%s" % I18n.t("menu_visuals")
	guitar_visuals_btn.tooltip_text = I18n.t("guitar_visuals_title")
	UITheme.style_ghost_button(guitar_visuals_btn, _fs(20 if compact else 15))
	guitar_visuals_btn.custom_minimum_size = Vector2(
		_u(58 if compact else 112), _u(58 if compact else 70))
	guitar_visuals_btn.pressed.connect(_open_guitar_visual_settings)
	header.add_child(guitar_visuals_btn)

	var help_btn := Button.new()
	help_btn.text = "?" if compact else "?\n%s" % I18n.t("menu_guide")
	help_btn.tooltip_text = I18n.t("song_tutorial_title")
	UITheme.style_ghost_button(help_btn, _fs(24 if compact else 16))
	help_btn.custom_minimum_size = Vector2(
		_u(54 if compact else 98), _u(58 if compact else 70))
	help_btn.pressed.connect(_open_song_tutorial)
	header.add_child(help_btn)

	var lang_btn := Button.new()
	lang_btn.text = "TR" if Settings.language == "tr" else "EN"
	if not compact:
		lang_btn.text += "\n<>"
	UITheme.style_ghost_button(lang_btn, _fs(18))
	lang_btn.custom_minimum_size = Vector2(
		_u(54 if compact else 78), _u(58 if compact else 70))
	lang_btn.pressed.connect(_on_language_toggle)
	header.add_child(lang_btn)

	# Portrait: the setlist expands above a fixed action dock. Landscape: the
	# same setlist sits beside a dedicated action rail.
	var body: BoxContainer
	if compact:
		body = VBoxContainer.new()
	else:
		body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", int(_u(10 if compact else 16)))
	main_vbox.add_child(body)

	var list_column := VBoxContainer.new()
	list_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_column.add_theme_constant_override("separation", int(_u(8 if compact else 12)))
	body.add_child(list_column)

	# Setlist header reads like a stamped road-case label.
	var setlist_panel := PanelContainer.new()
	var setlist_style := UITheme.card_style(UITheme.ROCK_RED)
	setlist_style.bg_color = Color(0.055, 0.045, 0.040, 0.96)
	setlist_style.border_color = UITheme.ROCK_STEEL
	setlist_style.border_width_left = int(_u(5))
	setlist_style.content_margin_top = _u(8)
	setlist_style.content_margin_bottom = _u(8)
	setlist_panel.add_theme_stylebox_override("panel", setlist_style)
	list_column.add_child(setlist_panel)
	var setlist_row := HBoxContainer.new()
	setlist_panel.add_child(setlist_row)
	var setlist_title := Label.new()
	setlist_title.text = "♫  %s" % I18n.t("setlist_title")
	setlist_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setlist_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	setlist_title.add_theme_font_size_override("font_size", _fs(18 if compact else 21))
	setlist_title.add_theme_color_override("font_color", UITheme.ROCK_IVORY)
	if UITheme.font_bold():
		setlist_title.add_theme_font_override("font", UITheme.font_bold())
	setlist_row.add_child(setlist_title)
	_song_count_label = Label.new()
	_song_count_label.text = I18n.t("song_count") % 0
	_song_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_song_count_label.add_theme_font_size_override("font_size", _fs(14 if compact else 16))
	_song_count_label.add_theme_color_override("font_color", UITheme.ROCK_PARCHMENT)
	setlist_row.add_child(_song_count_label)

	# --- Song cards scroll area ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = int(_u(14))
	list_column.add_child(scroll)

	card_container = VBoxContainer.new()
	card_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_container.add_theme_constant_override("separation", int(_u(10 if compact else 14)))
	scroll.add_child(card_container)

	var actions_panel := _build_main_actions_panel(compact)
	if not compact:
		actions_panel.custom_minimum_size = Vector2(_u(330), 0)
		actions_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(actions_panel)

func _on_language_toggle() -> void:
	Settings.language = "en" if Settings.language == "tr" else "tr"
	Settings.save_settings()
	get_tree().reload_current_scene()

func _create_tutorial_shell(title_text: String, intro_text: String) -> Dictionary:
	if is_instance_valid(_tutorial_overlay):
		return {}

	_tutorial_overlay = Control.new()
	_tutorial_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tutorial_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_tutorial_overlay.z_index = 100
	_tutorial_overlay.theme = _create_theme()
	add_child(_tutorial_overlay)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.020, 0.016, 0.014, 0.97)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_tutorial_overlay.add_child(shade)
	UITheme.add_hardrock_background(shade)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.025
	panel.anchor_top = 0.025
	panel.anchor_right = 0.975
	panel.anchor_bottom = 0.975
	var panel_style := UITheme.glow_style(CARD_BG, UITheme.ROCK_RED, 5, 9)
	panel_style.set_border_width_all(2)
	panel_style.border_width_bottom = int(_u(5))
	panel_style.content_margin_left = _u(22)
	panel_style.content_margin_right = _u(22)
	panel_style.content_margin_top = _u(16)
	panel_style.content_margin_bottom = _u(18)
	panel.add_theme_stylebox_override("panel", panel_style)
	_tutorial_overlay.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", int(_u(12)))
	panel.add_child(layout)

	var heading_row := HBoxContainer.new()
	heading_row.custom_minimum_size = Vector2(0, _u(76))
	heading_row.add_theme_constant_override("separation", int(_u(14)))
	layout.add_child(heading_row)
	heading_row.add_child(UITheme.make_game_logo(_u(68)))

	var heading := Label.new()
	heading.text = "?  %s" % title_text.to_upper()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", _fs(31))
	heading.add_theme_color_override("font_color", UITheme.ROCK_IVORY)
	if UITheme.font_bold():
		heading.add_theme_font_override("font", UITheme.font_bold())
	heading_row.add_child(heading)

	var close_icon := Button.new()
	close_icon.text = "×"
	close_icon.custom_minimum_size = Vector2(_u(66), _u(66))
	UITheme.style_ghost_button(close_icon, _fs(30))
	close_icon.pressed.connect(_close_song_tutorial)
	heading_row.add_child(close_icon)

	var intro := Label.new()
	intro.text = intro_text
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", _fs(19))
	intro.add_theme_color_override("font_color", TEXT_DIM)
	layout.add_child(intro)
	UITheme.add_edge_light(layout, UITheme.ROCK_STEEL_LIGHT)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = int(_u(14))
	layout.add_child(scroll)

	var steps := VBoxContainer.new()
	steps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	steps.add_theme_constant_override("separation", int(_u(10)))
	scroll.add_child(steps)

	return {"layout": layout, "steps": steps}

func _open_song_tutorial() -> void:
	var shell := _create_tutorial_shell(
		I18n.t("song_tutorial_title"), I18n.t("song_tutorial_intro"))
	if shell.is_empty():
		return
	var layout: VBoxContainer = shell["layout"]
	var steps: VBoxContainer = shell["steps"]

	_add_tutorial_step(steps, "1", I18n.t("song_tutorial_step_1"),
		I18n.t("song_tutorial_step_1_body"), UITheme.ROCK_RED)

	var source_row := HBoxContainer.new()
	source_row.add_theme_constant_override("separation", int(_u(10)))
	steps.add_child(source_row)
	var chorus_btn := Button.new()
	chorus_btn.text = "Chorus Encore  ↗"
	chorus_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_ghost_button(chorus_btn, _fs(16))
	chorus_btn.pressed.connect(func(): OS.shell_open(CHORUS_ENCORE_URL))
	source_row.add_child(chorus_btn)
	var rhythmverse_btn := Button.new()
	rhythmverse_btn.text = "RhythmVerse  ↗"
	rhythmverse_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_ghost_button(rhythmverse_btn, _fs(16))
	rhythmverse_btn.pressed.connect(func(): OS.shell_open(RHYTHMVERSE_URL))
	source_row.add_child(rhythmverse_btn)

	_add_tutorial_step(steps, "2", I18n.t("song_tutorial_step_2"),
		I18n.t("song_tutorial_step_2_body"), UITheme.ROCK_RED)
	_add_tutorial_step(steps, "3", I18n.t("song_tutorial_step_3"),
		I18n.t("song_tutorial_step_3_body"), UITheme.ROCK_RED)
	_add_tutorial_step(steps, "4", I18n.t("song_tutorial_step_4"),
		I18n.t("song_tutorial_step_4_body"), UITheme.ROCK_RED)

	var formats := Label.new()
	formats.text = I18n.t("song_tutorial_formats")
	formats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	formats.add_theme_font_size_override("font_size", _fs(16))
	formats.add_theme_color_override("font_color", UITheme.ROCK_PARCHMENT)
	steps.add_child(formats)

	var legal := Label.new()
	legal.text = I18n.t("song_tutorial_legal")
	legal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legal.add_theme_font_size_override("font_size", _fs(14))
	legal.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	steps.add_child(legal)

	var thanks_card := _add_tutorial_step(
		steps, "★", I18n.t("song_tutorial_thanks_title"),
		I18n.t("song_tutorial_thanks_body"), UITheme.ROCK_PARCHMENT)
	_arm_secret_unlock(thanks_card)

	_finish_tutorial(layout)

func _open_guitar_visual_settings() -> void:
	var shell := _create_tutorial_shell(
		I18n.t("guitar_visuals_title"), I18n.t("guitar_visuals_intro"))
	if shell.is_empty():
		return
	var layout: VBoxContainer = shell["layout"]
	var steps: VBoxContainer = shell["steps"]

	_add_guitar_visual_choice(
		steps,
		I18n.t("guitar_presentation"),
		["classic", "arena"],
		[
			I18n.t("guitar_presentation_classic"),
			I18n.t("guitar_presentation_arena"),
		],
		Settings.guitar_presentation_mode,
		_guitar_presentation_btns,
		_on_guitar_presentation_selected,
		UITheme.ROCK_RED)
	_add_guitar_visual_choice(
		steps,
		I18n.t("arena_fret_skin"),
		["blade", "anvil", "coil"],
		[
			I18n.t("arena_fret_blade"),
			I18n.t("arena_fret_anvil"),
			I18n.t("arena_fret_coil"),
		],
		Settings.arena_fret_skin,
		_arena_fret_btns,
		_on_arena_fret_selected,
		UITheme.ROCK_STEEL_LIGHT)

	var arena_hint := Label.new()
	arena_hint.text = I18n.t("arena_visuals_hint")
	arena_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	arena_hint.add_theme_font_size_override("font_size", _fs(15))
	arena_hint.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	steps.add_child(arena_hint)

	_add_arena_highway_import_card(steps)

	_add_guitar_visual_choice(
		steps,
		I18n.t("highway_theme"),
		["neon", "classic", "midnight"],
		[
			I18n.t("highway_theme_neon"),
			I18n.t("highway_theme_classic"),
			I18n.t("highway_theme_midnight"),
		],
		Settings.guitar_highway_theme,
		_guitar_theme_btns,
		_on_guitar_theme_selected,
		UITheme.ROCK_STEEL_LIGHT)
	_add_guitar_visual_choice(
		steps,
		I18n.t("pixel_stage"),
		["on", "off"],
		[I18n.t("pixel_stage_on"), I18n.t("pixel_stage_off")],
		"on" if Settings.pixel_stage_enabled else "off",
		_pixel_stage_btns,
		_on_pixel_stage_selected,
		UITheme.ROCK_RED)
	_add_guitar_visual_choice(
		steps,
		I18n.t("pixel_stage_intensity"),
		["subtle", "live"],
		[I18n.t("pixel_stage_subtle"), I18n.t("pixel_stage_live")],
		Settings.pixel_stage_intensity,
		_stage_intensity_btns,
		_on_stage_intensity_selected,
		UITheme.ROCK_STEEL_LIGHT)

	var hint := Label.new()
	hint.text = I18n.t("guitar_visuals_hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", _fs(15))
	hint.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	steps.add_child(hint)

	_finish_tutorial(layout)

func _add_arena_highway_import_card(parent: VBoxContainer) -> void:
	var card := PanelContainer.new()
	var card_style := UITheme.card_style(UITheme.ROCK_STEEL_LIGHT)
	card_style.bg_color = CARD_BG
	card.add_theme_stylebox_override("panel", card_style)
	parent.add_child(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", int(_u(9)))
	card.add_child(content)

	var title := Label.new()
	title.text = I18n.t("arena_highway_art")
	title.add_theme_font_size_override("font_size", _fs(18))
	title.add_theme_color_override(
		"font_color", UITheme.ROCK_STEEL_LIGHT.lightened(0.25))
	if UITheme.font_bold():
		title.add_theme_font_override("font", UITheme.font_bold())
	content.add_child(title)

	_arena_highway_status_label = Label.new()
	_arena_highway_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_arena_highway_status_label.add_theme_font_size_override(
		"font_size", _fs(15))
	_arena_highway_status_label.add_theme_color_override(
		"font_color", UITheme.ROCK_PARCHMENT)
	content.add_child(_arena_highway_status_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", int(_u(8)))
	content.add_child(actions)

	var import_button := Button.new()
	import_button.text = I18n.t("arena_highway_import")
	import_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_button.custom_minimum_size = Vector2(0, _u(54))
	UITheme.style_primary_button(
		import_button, UITheme.ROCK_STEEL_LIGHT, _fs(16))
	import_button.pressed.connect(_on_arena_highway_import_pressed)
	actions.add_child(import_button)

	var default_button := Button.new()
	default_button.text = I18n.t("arena_highway_use_default")
	default_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	default_button.custom_minimum_size = Vector2(0, _u(54))
	UITheme.style_ghost_button(default_button, _fs(16))
	default_button.pressed.connect(_on_arena_highway_default_pressed)
	actions.add_child(default_button)

	var hint := Label.new()
	hint.text = I18n.t("arena_highway_hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", _fs(14))
	hint.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	content.add_child(hint)
	_refresh_arena_highway_status()

func _refresh_arena_highway_status(message: String = "") -> void:
	if not is_instance_valid(_arena_highway_status_label):
		return
	if not message.is_empty():
		_arena_highway_status_label.text = message
	elif (Settings.arena_custom_highway_enabled
			and FileAccess.file_exists(Settings.CUSTOM_ARENA_HIGHWAY_PATH)):
		_arena_highway_status_label.text = I18n.t(
			"arena_highway_current_custom")
	else:
		_arena_highway_status_label.text = I18n.t(
			"arena_highway_current_builtin")

func _on_arena_highway_default_pressed() -> void:
	Settings.arena_custom_highway_enabled = false
	Settings.save_settings()
	_refresh_arena_highway_status()

func _on_arena_highway_import_pressed() -> void:
	if OS.get_name() == "Android" and Engine.has_singleton("NativeAudioDecoder"):
		var plugin = Engine.get_singleton("NativeAudioDecoder")
		if not plugin.is_connected("files_picked", _on_plugin_files_picked):
			plugin.connect("files_picked", _on_plugin_files_picked)
		_native_picker_context = "arena_highway"
		plugin.call("openFilePicker", I18n.t("arena_highway_picker_title"))
		return

	var filters := PackedStringArray([
		"*.png, *.jpg, *.jpeg, *.webp ; PNG/JPG/WebP",
	])
	DisplayServer.file_dialog_show(
		I18n.t("arena_highway_picker_title"),
		"",
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		filters,
		_on_arena_highway_files_selected
	)

func _on_arena_highway_files_selected(
		status: bool, selected: PackedStringArray, _idx: int) -> void:
	if not status or selected.is_empty():
		return
	_install_arena_highway_from_selected_path(selected[0])

func _install_arena_highway_from_selected_path(selected_path: String) -> void:
	var actual_path := selected_path
	var remove_after := false
	if selected_path.begins_with("content://"):
		actual_path = _resolve_content_uri(selected_path)
		remove_after = not actual_path.is_empty()
	elif OS.get_name() == "Android" and not FileAccess.file_exists(selected_path):
		actual_path = _resolve_content_uri(selected_path)
		remove_after = not actual_path.is_empty()

	if actual_path.is_empty():
		_refresh_arena_highway_status(I18n.t("arena_highway_invalid_image"))
		return
	var result_key := _save_custom_arena_highway(actual_path)
	if remove_after and FileAccess.file_exists(actual_path):
		DirAccess.remove_absolute(actual_path)
	_refresh_arena_highway_status(I18n.t(result_key))

func _save_custom_arena_highway(source_path: String) -> String:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return "arena_highway_invalid_image"
	var file_size := source.get_length()
	if file_size <= 0 or file_size > CUSTOM_HIGHWAY_MAX_BYTES:
		source.close()
		return "arena_highway_image_too_large"
	var bytes := source.get_buffer(file_size)
	source.close()

	var image := Image.new()
	var error := image.load_png_from_buffer(bytes)
	if error != OK:
		error = image.load_jpg_from_buffer(bytes)
	if error != OK:
		error = image.load_webp_from_buffer(bytes)
	if error != OK or image.is_empty():
		return "arena_highway_invalid_image"

	var width := image.get_width()
	var height := image.get_height()
	if width < 64 or height < 128:
		return "arena_highway_invalid_image"
	if width * height > CUSTOM_HIGHWAY_MAX_PIXELS:
		return "arena_highway_image_too_large"

	var fit_scale := minf(
		1.0,
		minf(
			float(CUSTOM_HIGHWAY_MAX_WIDTH) / float(width),
			float(CUSTOM_HIGHWAY_MAX_HEIGHT) / float(height)))
	if fit_scale < 1.0:
		image.resize(
			maxi(1, int(round(width * fit_scale))),
			maxi(1, int(round(height * fit_scale))),
			Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGBA8)

	DirAccess.make_dir_recursive_absolute(Settings.CUSTOM_ARENA_HIGHWAY_DIR)
	if image.save_png(Settings.CUSTOM_ARENA_HIGHWAY_PATH) != OK:
		return "arena_highway_save_failed"
	Settings.arena_custom_highway_enabled = true
	Settings.save_settings()
	return "arena_highway_import_success"

func _add_guitar_visual_choice(parent: VBoxContainer, title: String,
		keys: Array, labels: Array, selected_key: String, button_map: Dictionary,
		callback: Callable, accent: Color) -> void:
	var card := PanelContainer.new()
	var card_style := UITheme.card_style(accent)
	card_style.bg_color = CARD_BG
	card.add_theme_stylebox_override("panel", card_style)
	parent.add_child(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", int(_u(9)))
	card.add_child(content)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", _fs(18))
	title_label.add_theme_color_override("font_color", accent.lightened(0.25))
	if UITheme.font_bold():
		title_label.add_theme_font_override("font", UITheme.font_bold())
	content.add_child(title_label)

	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", int(_u(8)))
	content.add_child(choices)

	button_map.clear()
	for index in range(keys.size()):
		var key := String(keys[index])
		var button := Button.new()
		button.text = String(labels[index])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, _u(54))
		button.add_theme_font_size_override("font_size", _fs(16))
		UITheme.style_chip_button(button, key == selected_key, accent)
		button.pressed.connect(callback.bind(key))
		choices.add_child(button)
		button_map[key] = button

func _on_guitar_presentation_selected(presentation_key: String) -> void:
	Settings.guitar_presentation_mode = presentation_key
	Settings.save_settings()
	_restyle_chip_group(
		_guitar_presentation_btns, presentation_key, UITheme.ROCK_RED)

func _on_arena_fret_selected(fret_key: String) -> void:
	Settings.arena_fret_skin = fret_key
	Settings.save_settings()
	_restyle_chip_group(
		_arena_fret_btns, fret_key, UITheme.ROCK_STEEL_LIGHT)

func _on_guitar_theme_selected(theme_key: String) -> void:
	Settings.guitar_highway_theme = theme_key
	Settings.save_settings()
	_restyle_chip_group(_guitar_theme_btns, theme_key, UITheme.ROCK_STEEL_LIGHT)

func _on_pixel_stage_selected(stage_mode: String) -> void:
	Settings.pixel_stage_enabled = stage_mode == "on"
	Settings.save_settings()
	_restyle_chip_group(_pixel_stage_btns, stage_mode, UITheme.ROCK_RED)

func _on_stage_intensity_selected(intensity: String) -> void:
	Settings.pixel_stage_intensity = intensity
	Settings.save_settings()
	_restyle_chip_group(_stage_intensity_btns, intensity, UITheme.ROCK_STEEL_LIGHT)

func _open_game_settings_tutorial() -> void:
	var shell := _create_tutorial_shell(
		I18n.t("settings_tutorial_title"), I18n.t("settings_tutorial_intro"))
	if shell.is_empty():
		return
	var layout: VBoxContainer = shell["layout"]
	var steps: VBoxContainer = shell["steps"]

	_add_tutorial_step(steps, "1", I18n.t("settings_help_track"),
		I18n.t("settings_help_track_body"), UITheme.ROCK_RED)
	_add_tutorial_step(steps, "2", I18n.t("settings_help_gameplay"),
		I18n.t("settings_help_gameplay_body"), UITheme.ROCK_RED)
	_add_tutorial_step(steps, "3", I18n.t("settings_help_mode"),
		I18n.t("settings_help_mode_body"), UITheme.ROCK_RED)
	_add_tutorial_step(steps, "4", I18n.t("settings_help_view"),
		I18n.t("settings_help_view_body"), UITheme.ROCK_RED)
	_add_tutorial_step(steps, "5", I18n.t("settings_help_vfx"),
		I18n.t("settings_help_vfx_body"), UITheme.ROCK_RED)
	_add_tutorial_step(steps, "6", I18n.t("settings_help_rock"),
		I18n.t("settings_help_rock_body"), UITheme.ROCK_RED)
	_add_tutorial_step(steps, "7", I18n.t("settings_help_audio"),
		I18n.t("settings_help_audio_body"), UITheme.ROCK_RED)
	_add_tutorial_step(steps, "8", I18n.t("settings_help_speed"),
		I18n.t("settings_help_speed_body"), UITheme.ROCK_RED)

	_finish_tutorial(layout)

func _finish_tutorial(layout: VBoxContainer) -> void:
	var done_btn := Button.new()
	done_btn.text = I18n.t("song_tutorial_close")
	done_btn.custom_minimum_size = Vector2(0, _u(58))
	UITheme.style_primary_button(done_btn, UITheme.ROCK_RED, _fs(19))
	done_btn.pressed.connect(_close_song_tutorial)
	layout.add_child(done_btn)

	_tutorial_overlay.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_tutorial_overlay, "modulate:a", 1.0, 0.18)

func _add_tutorial_step(parent: VBoxContainer, number: String, title: String,
		body: String, accent: Color) -> PanelContainer:
	var card := PanelContainer.new()
	var card_style := UITheme.card_style(accent)
	card_style.bg_color = CARD_BG
	card.add_theme_stylebox_override("panel", card_style)
	parent.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(_u(14)))
	card.add_child(row)

	var number_badge := PanelContainer.new()
	number_badge.custom_minimum_size = Vector2(_u(62), _u(62))
	number_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	number_badge.add_theme_stylebox_override("panel", UITheme.badge_style(accent, true))
	row.add_child(number_badge)
	var number_label := Label.new()
	number_label.text = number
	number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number_label.add_theme_font_size_override("font_size", _fs(26))
	number_label.add_theme_color_override("font_color", accent.lightened(0.28))
	if UITheme.font_bold():
		number_label.add_theme_font_override("font", UITheme.font_bold())
	number_badge.add_child(number_label)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", int(_u(6)))
	row.add_child(content)

	var step_title := Label.new()
	step_title.text = title.to_upper()
	step_title.add_theme_font_size_override("font_size", _fs(20))
	step_title.add_theme_color_override("font_color", accent.lightened(0.25))
	if UITheme.font_bold():
		step_title.add_theme_font_override("font", UITheme.font_bold())
	content.add_child(step_title)

	var step_body := Label.new()
	step_body.text = body
	step_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_body.add_theme_font_size_override("font_size", _fs(16))
	step_body.add_theme_color_override("font_color", TEXT_DIM)
	content.add_child(step_body)
	_last_tutorial_body = step_body
	return card

# Hidden unlock: five taps on the tester-thanks card toggle unlimited overdrive.
# The card stays MOUSE_FILTER_PASS so the event still reaches the scroll
# container — anything else breaks touch scrolling on this panel.
func _arm_secret_unlock(card: PanelContainer) -> void:
	if not is_instance_valid(card):
		return
	_secret_body_label = _last_tutorial_body
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	for child in card.find_children("", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.gui_input.connect(_on_secret_card_input)

func _on_secret_card_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	var now := Time.get_ticks_msec()
	# Taps have to be deliberate and consecutive, so a slow scroll that happens
	# to start on this card never trips it.
	if now > _secret_tap_deadline_ms:
		_secret_tap_count = 0
	_secret_tap_count += 1
	_secret_tap_deadline_ms = now + SECRET_TAP_WINDOW_MS
	if _secret_tap_count < SECRET_TAP_COUNT:
		return
	_secret_tap_count = 0
	Settings.unlimited_overdrive = not Settings.unlimited_overdrive
	Settings.save_settings()
	if is_instance_valid(_secret_body_label):
		_secret_body_label.text = I18n.t(
			"secret_overdrive_on" if Settings.unlimited_overdrive
			else "secret_overdrive_off")
		_secret_body_label.add_theme_color_override(
			"font_color",
			UITheme.NEON_CYAN if Settings.unlimited_overdrive else TEXT_DIM)

func _close_song_tutorial() -> void:
	if not is_instance_valid(_tutorial_overlay):
		_tutorial_overlay = null
		return
	var closing_overlay := _tutorial_overlay
	_tutorial_overlay = null
	var tween := create_tween()
	tween.tween_property(closing_overlay, "modulate:a", 0.0, 0.14)
	tween.tween_callback(closing_overlay.queue_free)

# --- Song card creation ---

func _parse_song_name(display: String) -> Dictionary:
	var name := display
	for ext in [".sng", ".chart", ".mid"]:
		if name.to_lower().ends_with(ext):
			name = name.substr(0, name.length() - ext.length())
	var paren := name.rfind("(")
	if paren > 0:
		name = name.substr(0, paren).strip_edges()
	var sep := name.find(" - ")
	if sep > 0:
		return {"artist": name.substr(0, sep).strip_edges(), "title": name.substr(sep + 3).strip_edges()}
	sep = name.find(" / ")
	if sep > 0:
		var folder := name.substr(0, sep).strip_edges()
		var fname := name.substr(sep + 3).strip_edges()
		var fsep := folder.find(" - ")
		if fsep > 0:
			return {"artist": folder.substr(0, fsep).strip_edges(), "title": folder.substr(fsep + 3).strip_edges()}
		return {"artist": folder, "title": fname}
	return {"artist": "", "title": name}

func _create_song_card(index: int, song: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var parsed := _parse_song_name(song["display_name"])
	var compact := _is_compact_layout()
	var accent := UITheme.ROCK_RED

	# One coherent material language across the setlist. Album art supplies the
	# natural color variation instead of cycling synthetic accent colors.
	var card_style := UITheme.card_style(accent)
	card_style.bg_color = Color(0.045, 0.037, 0.033, 0.97)
	card_style.set_corner_radius_all(int(_u(4)))
	card_style.border_color = UITheme.ROCK_STEEL
	card_style.border_width_left = int(_u(6))
	card_style.border_width_bottom = int(_u(4))
	card_style.shadow_color = Color(0, 0, 0, 0.76)
	card_style.shadow_size = int(_u(7))
	card_style.content_margin_left = _u(9 if compact else 12)
	card_style.content_margin_right = _u(10 if compact else 18)
	card_style.content_margin_top = _u(9 if compact else 12)
	card_style.content_margin_bottom = _u(9 if compact else 12)
	panel.add_theme_stylebox_override("panel", card_style)
	panel.custom_minimum_size = Vector2(0, _u(166 if compact else 188))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", int(_u(9 if compact else 14)))
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	var track_plate := PanelContainer.new()
	var track_style := UITheme.badge_style(accent, true)
	track_style.bg_color = Color(0.13, 0.045, 0.032, 0.94)
	track_style.border_color = accent.darkened(0.08)
	track_plate.add_theme_stylebox_override("panel", track_style)
	track_plate.custom_minimum_size = Vector2(
		_u(58 if compact else 70), _u(142 if compact else 156))
	track_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(track_plate)
	var track_box := VBoxContainer.new()
	track_box.alignment = BoxContainer.ALIGNMENT_CENTER
	track_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track_plate.add_child(track_box)
	var track_caption := Label.new()
	track_caption.text = I18n.t("track_number")
	track_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	track_caption.add_theme_font_size_override("font_size", _fs(11))
	track_caption.add_theme_color_override("font_color", TEXT_DIM)
	track_box.add_child(track_caption)
	var track_number := Label.new()
	track_number.text = "%02d" % (index + 1)
	track_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	track_number.add_theme_font_size_override("font_size", _fs(25 if compact else 30))
	track_number.add_theme_color_override("font_color", UITheme.ROCK_IVORY)
	if UITheme.font_bold():
		track_number.add_theme_font_override("font", UITheme.font_bold())
	track_box.add_child(track_number)

	# Album art thumbnail (placeholder now, lazy-loaded after scan)
	var thumb := PanelContainer.new()
	var thumb_style := UITheme.glow_style(
		Color(0.025, 0.022, 0.020), UITheme.ROCK_STEEL, 4, 7)
	thumb_style.set_border_width_all(2)
	thumb_style.content_margin_left = 0; thumb_style.content_margin_right = 0
	thumb_style.content_margin_top = 0; thumb_style.content_margin_bottom = 0
	thumb.add_theme_stylebox_override("panel", thumb_style)
	var thumb_size := _u(142 if compact else 156)
	thumb.custom_minimum_size = Vector2(thumb_size, thumb_size)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(thumb)

	var thumb_icon := Label.new()
	thumb_icon.text = "♪"
	thumb_icon.add_theme_font_size_override("font_size", _fs(48 if compact else 58))
	thumb_icon.add_theme_color_override("font_color", UITheme.ROCK_STEEL_LIGHT)
	thumb_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thumb_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	thumb.add_child(thumb_icon)
	_art_pending.append({"index": index, "holder": thumb})

	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_vbox.add_theme_constant_override("separation", int(_u(5 if compact else 8)))
	text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_vbox)

	var status_lbl := Label.new()
	status_lbl.text = "◆  %s" % I18n.t("tap_to_play")
	status_lbl.add_theme_font_size_override("font_size", _fs(11 if compact else 13))
	status_lbl.add_theme_color_override("font_color", UITheme.ROCK_PARCHMENT)
	if UITheme.font_bold():
		status_lbl.add_theme_font_override("font", UITheme.font_bold())
	text_vbox.add_child(status_lbl)

	var title_lbl := Label.new()
	title_lbl.text = parsed["title"]
	title_lbl.add_theme_font_size_override("font_size", _fs(24 if compact else 31))
	title_lbl.add_theme_color_override("font_color", TEXT_BRIGHT)
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if UITheme.font_bold():
		title_lbl.add_theme_font_override("font", UITheme.font_bold())
	text_vbox.add_child(title_lbl)

	if parsed["artist"] != "":
		var artist_lbl := Label.new()
		artist_lbl.text = parsed["artist"]
		artist_lbl.add_theme_font_size_override("font_size", _fs(17 if compact else 20))
		artist_lbl.add_theme_color_override("font_color", TEXT_DIM)
		artist_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text_vbox.add_child(artist_lbl)

	# Best star rating (across all instrument/difficulty combos for this song)
	var best_stars := _get_best_stars_for_song(song)
	if best_stars > 0:
		var stars_lbl := Label.new()
		var star_str := ""
		for si in range(5):
			star_str += "★" if si < best_stars else "☆"
		stars_lbl.text = star_str
		stars_lbl.add_theme_font_size_override("font_size", _fs(19))
		stars_lbl.add_theme_color_override("font_color", STAR_COLOR)
		stars_lbl.add_theme_color_override("font_shadow_color", Color(STAR_COLOR.r, STAR_COLOR.g, STAR_COLOR.b, 0.4))
		stars_lbl.add_theme_constant_override("shadow_offset_x", 0)
		stars_lbl.add_theme_constant_override("shadow_offset_y", 0)
		stars_lbl.add_theme_constant_override("shadow_outline_size", int(_u(6)))
		text_vbox.add_child(stars_lbl)

	# Heavy launch plate; no colored halo.
	var play_badge := PanelContainer.new()
	play_badge.custom_minimum_size = Vector2(
		_u(66 if compact else 78), _u(66 if compact else 78))
	play_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	play_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_badge.add_theme_stylebox_override("panel", UITheme.badge_style(accent, true))
	hbox.add_child(play_badge)
	var play_circle := Label.new()
	play_circle.text = "▶"
	play_circle.add_theme_font_size_override("font_size", _fs(30 if compact else 34))
	play_circle.add_theme_color_override("font_color", UITheme.ROCK_IVORY)
	play_circle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.72))
	play_circle.add_theme_constant_override("shadow_offset_x", int(_u(2)))
	play_circle.add_theme_constant_override("shadow_offset_y", int(_u(3)))
	play_circle.add_theme_constant_override("shadow_outline_size", int(_u(4)))
	play_circle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_circle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	play_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_badge.add_child(play_circle)

	# PASS (not STOP): the card still gets gui_input for tap detection, but the
	# ScrollContainer above also sees the drag — otherwise scrolling breaks.
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.gui_input.connect(_on_card_input.bind(index, panel))

	return panel

# --- Lazy album-art thumbnails: one song per frame to keep scrolling smooth ---

var _art_pending: Array = []
var _art_scan_token: int = 0

func _start_art_queue(track_loading: bool = false) -> void:
	_art_scan_token += 1
	var token := _art_scan_token
	var queue := _art_pending.duplicate()
	if track_loading:
		await _process_art_queue(token, queue, true)
	else:
		_process_art_queue(token, queue, false)

func _process_art_queue(token: int, queue: Array, track_loading: bool) -> void:
	for item_idx in range(queue.size()):
		var item = queue[item_idx]
		if token != _art_scan_token or not is_inside_tree():
			return
		await get_tree().process_frame
		if token != _art_scan_token or not is_inside_tree():
			return
		var idx: int = item["index"]
		var holder: PanelContainer = item["holder"]
		if track_loading:
			var pct := 90.0 + 9.0 * float(item_idx + 1) / maxf(1.0, float(queue.size()))
			_set_menu_loading(true, pct)
		if idx >= found_songs.size() or not is_instance_valid(holder):
			continue
		var tex := _load_album_art(found_songs[idx])
		if tex == null or not is_instance_valid(holder):
			continue
		for child in holder.get_children():
			child.queue_free()
		var art := TextureRect.new()
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE  # don't block scroll drags
		holder.add_child(art)

func _get_best_stars_for_song(song: Dictionary) -> int:
	var song_hash: String = String(song["path"]).md5_text()
	var best := 0
	for key in saved_scores:
		if (key as String).begins_with(song_hash):
			var s: int = int(saved_scores[key].get("stars", 0))
			if s > best:
				best = s
	return best

func _on_card_input(event: InputEvent, index: int, _panel: PanelContainer) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_card_touch_start = event.position
			_card_touch_index = index
		else:
			if _card_touch_index == index:
				var dist := _card_touch_start.distance_to(event.position)
				if dist < _u(SCROLL_TAP_THRESHOLD):
					_open_launch_screen(index)
			_card_touch_index = -1
	elif event is InputEventScreenTouch:
		if event.pressed:
			_card_touch_start = event.position
			_card_touch_index = index
		else:
			if _card_touch_index == index:
				var dist := _card_touch_start.distance_to(event.position)
				if dist < _u(SCROLL_TAP_THRESHOLD):
					_open_launch_screen(index)
			_card_touch_index = -1

# --- Song scanning ---

# Coroutine: paints a loading frame first, then builds cards in small batches
# so returning to the menu never freezes the screen.
func _scan_songs(force_rescan: bool = false) -> void:
	_scan_generation += 1
	var gen := _scan_generation
	found_songs.clear()
	card_panels.clear()
	_art_pending.clear()
	_art_scan_token += 1  # cancel any in-flight art loads
	for child in card_container.get_children():
		child.queue_free()

	if not force_rescan and AppCache.song_list_valid:
		found_songs = AppCache.songs.duplicate(true)
		print("Menu: session cache kullanildi (%d sarki)" % found_songs.size())
		await _build_song_cards(gen, false)
		return

	_set_menu_loading(true, 4.0)

	# Let the loading label paint before doing any file IO
	await get_tree().process_frame
	if gen != _scan_generation or not is_inside_tree():
		return

	# Scan directories: res://songs, res://, user://songs
	var scan_dirs: Array = []
	var res_songs := "res://songs"
	if DirAccess.dir_exists_absolute(res_songs):
		scan_dirs.append(res_songs)
	scan_dirs.append("res://")
	DirAccess.make_dir_recursive_absolute(USER_SONGS_DIR)
	scan_dirs.append(USER_SONGS_DIR)

	# Directories that support subdirectory scanning
	var deep_scan_dirs := ["res://songs", USER_SONGS_DIR]

	for _sd in scan_dirs:
		var scan_dir: String = _sd
		var dir := DirAccess.open(scan_dir)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir():
				if _is_chart_file_or_stfs(fname, scan_dir):
					var full_path := scan_dir.path_join(fname)
					if full_path not in HIDDEN_BUNDLED_SONG_PATHS:
						found_songs.append({"path": full_path, "display_name": fname})
			else:
				if scan_dir in deep_scan_dirs:
					_scan_subdir(scan_dir, fname)
			fname = dir.get_next()
		dir.list_dir_end()

	found_songs.sort_custom(func(a, b): return a["display_name"].to_lower() < b["display_name"].to_lower())
	AppCache.store_songs(found_songs)
	await _build_song_cards(gen, true)

func _build_song_cards(gen: int, show_loading: bool) -> void:
	if gen != _scan_generation or not is_inside_tree():
		return
	if is_instance_valid(_song_count_label):
		_song_count_label.text = I18n.t("song_count") % found_songs.size()

	# Build cards in batches of 8 — keeps every frame under budget
	for i in range(found_songs.size()):
		var card := _create_song_card(i, found_songs[i])
		card_container.add_child(card)
		card_panels.append(card)
		if i % 8 == 7:
			if show_loading:
				var pct := 10.0 + 80.0 * float(i + 1) / maxf(1.0, float(found_songs.size()))
				_set_menu_loading(true, pct)
			await get_tree().process_frame
			if gen != _scan_generation or not is_inside_tree():
				return

	if found_songs.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = I18n.t("no_songs")
		empty_lbl.add_theme_font_size_override("font_size", _fs(24))
		empty_lbl.add_theme_color_override("font_color", TEXT_DIM)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		card_container.add_child(empty_lbl)

	BattleSession.set_song_catalog(found_songs)

	if show_loading:
		await _start_art_queue(true)
		_set_menu_loading(true, 100.0)
		await get_tree().process_frame
		if gen != _scan_generation or not is_inside_tree():
			return
		_set_menu_loading(false)
	else:
		_start_art_queue(false)

func _is_chart_file(fname: String) -> bool:
	var fl := fname.to_lower()
	return fl.ends_with(".chart") or fl.ends_with(".sng") or fl.ends_with(".mid") or fl.ends_with(".con") or fl.ends_with(".live")

func _is_chart_file_or_stfs(fname: String, dir_path: String) -> bool:
	if _is_chart_file(fname):
		return true
	# Check magic bytes for extensionless STFS files (rb3con etc.)
	if fname.find(".") < 0:  # No extension
		var f := FileAccess.open(dir_path.path_join(fname), FileAccess.READ)
		if f and f.get_length() >= 4:
			var magic := f.get_buffer(4).get_string_from_ascii()
			f.close()
			return magic == "CON " or magic == "LIVE" or magic == "PIRS"
		if f:
			f.close()
	return false

func _scan_subdir(parent_dir: String, folder_name: String) -> void:
	var sub_dir := DirAccess.open(parent_dir.path_join(folder_name))
	if sub_dir == null:
		return
	sub_dir.list_dir_begin()
	var sub_fname := sub_dir.get_next()
	while sub_fname != "":
		if _is_chart_file_or_stfs(sub_fname, parent_dir.path_join(folder_name)):
			var full_path := parent_dir.path_join(folder_name).path_join(sub_fname)
			found_songs.append({"path": full_path, "display_name": "%s / %s" % [folder_name, sub_fname]})
		sub_fname = sub_dir.get_next()
	sub_dir.list_dir_end()

func _build_main_actions_panel(compact: bool) -> PanelContainer:
	var actions_panel := PanelContainer.new()
	var actions_style := UITheme.glow_style(
		Color(0.042, 0.034, 0.030, 0.98), UITheme.ROCK_STEEL, 5, 8)
	actions_style.border_color = UITheme.ROCK_STEEL
	actions_style.border_width_top = int(_u(4 if compact else 1))
	actions_style.border_width_left = int(_u(5))
	actions_style.content_margin_left = _u(10 if compact else 16)
	actions_style.content_margin_right = _u(10 if compact else 16)
	actions_style.content_margin_top = _u(9 if compact else 16)
	actions_style.content_margin_bottom = _u(9 if compact else 16)
	actions_panel.add_theme_stylebox_override("panel", actions_style)
	actions_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", int(_u(7 if compact else 14)))
	actions_panel.add_child(actions)
	_main_actions_container = actions
	var actions_title := Label.new()
	actions_title.text = "//  %s" % I18n.t("main_actions").to_upper()
	actions_title.add_theme_font_size_override("font_size", _fs(15 if compact else 19))
	actions_title.add_theme_color_override("font_color", UITheme.ROCK_IVORY)
	if UITheme.font_bold():
		actions_title.add_theme_font_override("font", UITheme.font_bold())
	actions.add_child(actions_title)

	var action_grid := GridContainer.new()
	action_grid.columns = 2 if compact else 1
	action_grid.add_theme_constant_override("h_separation", int(_u(10)))
	action_grid.add_theme_constant_override("v_separation", int(_u(12)))
	actions.add_child(action_grid)

	var import_btn := Button.new()
	import_btn.text = "+\n%s" % I18n.t("add_song").trim_prefix("+").strip_edges().to_upper()
	import_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_primary_button(import_btn, UITheme.ROCK_STEEL_LIGHT, _fs(20 if compact else 25))
	import_btn.custom_minimum_size = Vector2(0, _u(88 if compact else 132))
	import_btn.pressed.connect(_on_import_pressed)
	action_grid.add_child(import_btn)

	var battle_btn := Button.new()
	battle_btn.text = "VS\n%s" % I18n.t("battle_menu_button").to_upper()
	battle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_primary_button(battle_btn, UITheme.ROCK_RED, _fs(20 if compact else 25))
	battle_btn.custom_minimum_size = Vector2(0, _u(88 if compact else 132))
	battle_btn.pressed.connect(_open_battle_menu)
	action_grid.add_child(battle_btn)

	var battle_hint := Label.new()
	battle_hint.text = I18n.t("battle_menu_hint")
	battle_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	battle_hint.add_theme_font_size_override("font_size", _fs(13 if compact else 16))
	battle_hint.add_theme_color_override("font_color", TEXT_DIM)
	actions.add_child(battle_hint)

	# Status label (hidden by default)
	_import_status_label = Label.new()
	_import_status_label.text = ""
	_import_status_label.add_theme_font_size_override("font_size", _fs(18))
	_import_status_label.add_theme_color_override("font_color", ACCENT)
	_import_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_import_status_label.visible = false
	actions.add_child(_import_status_label)
	return actions_panel

func _open_battle_menu() -> void:
	if is_instance_valid(_battle_overlay):
		return
	var compact := _is_compact_layout()
	_battle_mode = BattleSession.room_mode if BattleSession.session_state == "lobby" else "battle"
	_battle_overlay = Control.new()
	_battle_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_battle_overlay.z_index = 120
	_battle_overlay.theme = _create_theme()
	add_child(_battle_overlay)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.020, 0.016, 0.014, 0.965)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_battle_overlay.add_child(shade)
	UITheme.add_hardrock_background(shade)

	var sa := UITheme.safe_insets(self)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(
		"margin_left", int(sa["l"] + _u(8 if compact else 14)))
	margin.add_theme_constant_override(
		"margin_right", int(sa["r"] + _u(8 if compact else 14)))
	margin.add_theme_constant_override(
		"margin_top", int(sa["t"] + _u(8 if compact else 10)))
	margin.add_theme_constant_override(
		"margin_bottom", int(sa["b"] + _u(8 if compact else 10)))
	_battle_overlay.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", int(_u(10)))
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, _u(104 if compact else 78))
	header.add_theme_constant_override("separation", int(_u(8 if compact else 12)))
	layout.add_child(header)

	# Keep navigation in the phone's safe top-left corner. The old trailing X
	# could sit directly under OEM game/FPS overlays at the top-right.
	_battle_back_button = Button.new()
	_battle_back_button.name = "BattleBackButton"
	_battle_back_button.text = "‹  %s" % I18n.t("back").to_upper()
	_battle_back_button.custom_minimum_size = Vector2(
		_u(168 if compact else 142), _u(104 if compact else 72))
	UITheme.style_primary_button(
		_battle_back_button, UITheme.ROCK_RED, _fs(18 if compact else 20))
	_battle_back_button.pressed.connect(_close_battle_menu)
	header.add_child(_battle_back_button)

	header.add_child(UITheme.make_game_logo(_u(72 if compact else 68)))
	var title := Label.new()
	title.text = I18n.t("battle_title").to_upper()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", _fs(27 if compact else 36))
	title.add_theme_color_override("font_color", UITheme.ROCK_IVORY)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if UITheme.font_bold():
		title.add_theme_font_override("font", UITheme.font_bold())
	header.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", int(_u(16)))
	scroll.add_child(content)

	_battle_connection_panel = PanelContainer.new()
	_battle_connection_panel.add_theme_stylebox_override(
		"panel", UITheme.glow_style(CARD_BG, UITheme.ROCK_STEEL, 5, 8))
	_battle_connection_panel.visible = BattleSession.session_state != "lobby"
	content.add_child(_battle_connection_panel)
	var connection_box := VBoxContainer.new()
	connection_box.add_theme_constant_override("separation", int(_u(16)))
	_battle_connection_panel.add_child(connection_box)

	var intro := HBoxContainer.new()
	intro.add_theme_constant_override("separation", int(_u(16)))
	connection_box.add_child(intro)
	intro.add_child(_battle_icon_badge("2–4", UITheme.ROCK_STEEL_LIGHT, 100))
	var intro_text := VBoxContainer.new()
	intro_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro_text.alignment = BoxContainer.ALIGNMENT_CENTER
	intro.add_child(intro_text)
	var intro_title := Label.new()
	intro_title.text = I18n.t("online_choose_mode")
	intro_title.add_theme_font_size_override("font_size", _fs(28))
	intro_title.add_theme_color_override("font_color", TEXT_BRIGHT)
	if UITheme.font_bold():
		intro_title.add_theme_font_override("font", UITheme.font_bold())
	intro_text.add_child(intro_title)
	var intro_hint := Label.new()
	intro_hint.text = I18n.t("battle_menu_hint")
	intro_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_hint.add_theme_font_size_override("font_size", _fs(18))
	intro_hint.add_theme_color_override("font_color", TEXT_DIM)
	intro_text.add_child(intro_hint)

	var mode_cards := HBoxContainer.new()
	mode_cards.add_theme_constant_override("separation", int(_u(14)))
	connection_box.add_child(mode_cards)
	_battle_mode_buttons.clear()
	for data in [
		["battle", "VS", I18n.t("battle_mode"), I18n.t("battle_mode_short"), UITheme.ROCK_RED],
		["band", "BAND", I18n.t("band_mode"), I18n.t("band_mode_short"), UITheme.ROCK_STEEL_LIGHT],
	]:
		var button := _make_battle_mode_card(
			String(data[0]), String(data[1]), String(data[2]),
			String(data[3]), data[4])
		button.button_pressed = String(data[0]) == _battle_mode
		_style_battle_mode_card(button, button.button_pressed)
		button.pressed.connect(_on_battle_mode_selected.bind(String(data[0])))
		mode_cards.add_child(button)
		_battle_mode_buttons[String(data[0])] = button

	var mode_help := Label.new()
	mode_help.name = "ModeHelp"
	mode_help.text = _battle_mode_help()
	mode_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_help.add_theme_color_override("font_color", TEXT_DIM)
	mode_help.add_theme_font_size_override("font_size", _fs(18))
	connection_box.add_child(mode_help)

	connection_box.add_child(_battle_field_label(I18n.t("player_name")))
	_battle_name_edit = LineEdit.new()
	_battle_name_edit.placeholder_text = I18n.t("player_name")
	_battle_name_edit.text = I18n.t("default_player_name")
	_battle_name_edit.max_length = 18
	_battle_name_edit.custom_minimum_size = Vector2(0, _u(76))
	_battle_name_edit.add_theme_font_size_override("font_size", _fs(25))
	connection_box.add_child(_battle_name_edit)

	connection_box.add_child(_battle_field_label(I18n.t("room_code")))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", int(_u(12)))
	connection_box.add_child(join_row)
	_battle_code_edit = LineEdit.new()
	_battle_code_edit.placeholder_text = "ABC123"
	_battle_code_edit.max_length = 6
	_battle_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_code_edit.custom_minimum_size = Vector2(0, _u(82))
	_battle_code_edit.add_theme_font_size_override("font_size", _fs(30))
	_battle_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_row.add_child(_battle_code_edit)
	var join_btn := Button.new()
	join_btn.text = "→  %s" % I18n.t("join_room")
	join_btn.custom_minimum_size = Vector2(_u(230), _u(82))
	UITheme.style_primary_button(join_btn, UITheme.ROCK_READY, _fs(25))
	join_btn.pressed.connect(_on_battle_join)
	join_row.add_child(join_btn)
	var create_btn := Button.new()
	create_btn.text = "+  %s" % I18n.t("create_room")
	create_btn.custom_minimum_size = Vector2(0, _u(92))
	UITheme.style_primary_button(create_btn, UITheme.ROCK_RED, _fs(27))
	create_btn.pressed.connect(_on_battle_create)
	connection_box.add_child(create_btn)

	_battle_status_label = Label.new()
	_battle_status_label.text = I18n.t("multiplayer_not_configured") \
		if not BattleSession.configured else I18n.t("multiplayer_ready")
	_battle_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_battle_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_battle_status_label.add_theme_font_size_override("font_size", _fs(19))
	_battle_status_label.add_theme_color_override("font_color", UITheme.ROCK_PARCHMENT)
	_battle_status_label.visible = BattleSession.session_state != "lobby"
	content.add_child(_battle_status_label)

	_battle_lobby_controls = VBoxContainer.new()
	_battle_lobby_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_lobby_controls.add_theme_constant_override("separation", int(_u(16)))
	content.add_child(_battle_lobby_controls)
	_build_battle_lobby_controls()
	if BattleSession.session_state == "lobby":
		_on_battle_lobby_changed(BattleSession._players_array(), BattleSession.room_data)
func _build_battle_lobby_controls() -> void:
	if not is_instance_valid(_battle_lobby_controls):
		return
	for child in _battle_lobby_controls.get_children():
		child.queue_free()
	if BattleSession.session_state != "lobby":
		_battle_rendered_song_fingerprint = ""
		return
	_battle_rendered_song_fingerprint = _battle_song_render_key()

	var room_panel := PanelContainer.new()
	room_panel.custom_minimum_size = Vector2(0, _u(112))
	room_panel.add_theme_stylebox_override(
		"panel", UITheme.glow_style(CARD_BG, UITheme.ROCK_PARCHMENT, 5, 8))
	_battle_lobby_controls.add_child(room_panel)
	var room_row := HBoxContainer.new()
	room_row.add_theme_constant_override("separation", int(_u(18)))
	room_panel.add_child(room_row)
	room_row.add_child(_battle_icon_badge("#", UITheme.ROCK_PARCHMENT, 84))
	var room_text := VBoxContainer.new()
	room_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_text.alignment = BoxContainer.ALIGNMENT_CENTER
	room_row.add_child(room_text)
	var room_caption := Label.new()
	room_caption.text = I18n.t("room_code").to_upper()
	room_caption.add_theme_font_size_override("font_size", _fs(18))
	room_caption.add_theme_color_override("font_color", TEXT_DIM)
	room_text.add_child(room_caption)
	var code := Label.new()
	code.text = BattleSession.room_code
	code.add_theme_font_size_override("font_size", _fs(42))
	code.add_theme_color_override("font_color", UITheme.ROCK_IVORY)
	if UITheme.font_bold():
		code.add_theme_font_override("font", UITheme.font_bold())
	room_text.add_child(code)

	_battle_lobby_controls.add_child(
		_battle_section_title("2–4", I18n.t("multiplayer_players"), UITheme.ROCK_READY))
	_battle_players_box = VBoxContainer.new()
	_battle_players_box.add_theme_constant_override("separation", int(_u(10)))
	_battle_lobby_controls.add_child(_battle_players_box)

	var song_panel := PanelContainer.new()
	song_panel.add_theme_stylebox_override(
		"panel", UITheme.glow_style(CARD_BG, UITheme.ROCK_STEEL_LIGHT, 5, 8))
	_battle_lobby_controls.add_child(song_panel)
	var song_box := VBoxContainer.new()
	song_box.add_theme_constant_override("separation", int(_u(12)))
	song_panel.add_child(song_box)
	song_box.add_child(
		_battle_section_title("♫", I18n.t("multiplayer_song"), UITheme.ROCK_STEEL_LIGHT))
	if BattleSession.is_host:
		_battle_song_option = OptionButton.new()
		_battle_song_option.custom_minimum_size = Vector2(0, _u(82))
		_battle_song_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_battle_song_option.add_item("+  %s" % I18n.t("choose_song"))
		for song in found_songs:
			_battle_song_option.add_item("♫  %s" % String(
				song.get("display_name", I18n.t("default_song_name"))))
		_style_battle_option(_battle_song_option)
		_battle_song_option.item_selected.connect(_on_battle_song_selected)
		song_box.add_child(_battle_song_option)
		var selected_name := String(BattleSession.selected_song.get("name", ""))
		if not selected_name.is_empty():
			for song_index in range(found_songs.size()):
				if String(found_songs[song_index].get("display_name", "")) == selected_name:
					_battle_song_option.select(song_index + 1)
					break
	elif not BattleSession.selected_song.is_empty():
		var song_name := Label.new()
		song_name.text = "♫  %s" % String(BattleSession.selected_song.get("name", ""))
		song_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		song_name.add_theme_font_size_override("font_size", _fs(27))
		song_name.add_theme_color_override("font_color", TEXT_BRIGHT)
		song_box.add_child(song_name)
	else:
		var waiting_song := Label.new()
		waiting_song.text = I18n.t("multiplayer_waiting_song")
		waiting_song.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		waiting_song.add_theme_font_size_override("font_size", _fs(20))
		waiting_song.add_theme_color_override("font_color", TEXT_DIM)
		song_box.add_child(waiting_song)

	_build_battle_host_options(song_box)

	_battle_transfer_label = Label.new()
	_battle_transfer_label.visible = not BattleSession.song_transfer_detail.is_empty()
	_battle_transfer_label.text = BattleSession.song_transfer_detail
	_battle_transfer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_battle_transfer_label.add_theme_font_size_override("font_size", _fs(19))
	_battle_transfer_label.add_theme_color_override("font_color", UITheme.ROCK_PARCHMENT)
	song_box.add_child(_battle_transfer_label)
	_battle_transfer_bar = ProgressBar.new()
	_battle_transfer_bar.visible = BattleSession.song_transfer_active
	_battle_transfer_bar.show_percentage = true
	_battle_transfer_bar.value = BattleSession.song_transfer_progress * 100.0
	_battle_transfer_bar.custom_minimum_size = Vector2(0, _u(30))
	song_box.add_child(_battle_transfer_bar)

	var setup_panel := PanelContainer.new()
	setup_panel.add_theme_stylebox_override(
		"panel", UITheme.glow_style(CARD_BG, UITheme.ROCK_RED, 5, 8))
	_battle_lobby_controls.add_child(setup_panel)
	var setup_box := VBoxContainer.new()
	setup_box.add_theme_constant_override("separation", int(_u(12)))
	setup_panel.add_child(setup_box)
	setup_box.add_child(
		_battle_section_title("◆", I18n.t("multiplayer_your_setup"), UITheme.ROCK_RED))

	setup_box.add_child(_battle_field_label(I18n.t("instrument")))
	_battle_instrument_option = OptionButton.new()
	_battle_instrument_option.custom_minimum_size = Vector2(0, _u(82))
	_battle_instrument_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_instrument_option.add_item("?  %s" % I18n.t("choose_instrument"))
	var instruments: Dictionary = BattleSession.selected_song.get("instruments", {})
	var local_player: Dictionary = BattleSession.players.get(
		BattleSession.local_uid, {})
	var current_instrument := String(local_player.get("instrument", ""))
	var instrument_order: Array[String] = ["guitar", "bass", "drums", "keys", "vocals"]
	for instrument_value in instruments.keys():
		var instrument_key := String(instrument_value)
		if instrument_key not in instrument_order:
			instrument_order.append(instrument_key)
	for instrument in instrument_order:
		if not instruments.has(instrument):
			continue
		_battle_instrument_option.add_item("%s  %s" % [
			_instrument_icon(instrument), _instrument_label(instrument)])
		_battle_instrument_option.set_item_metadata(
			_battle_instrument_option.item_count - 1, instrument)
		if instrument == current_instrument:
			_battle_instrument_option.select(
				_battle_instrument_option.item_count - 1)
	_battle_instrument_option.disabled = instruments.is_empty()
	_style_battle_option(_battle_instrument_option)
	_battle_instrument_option.item_selected.connect(_on_battle_instrument_selected)
	setup_box.add_child(_battle_instrument_option)

	setup_box.add_child(_battle_field_label(I18n.t("difficulty")))
	_battle_difficulty_option = OptionButton.new()
	_battle_difficulty_option.custom_minimum_size = Vector2(0, _u(82))
	_battle_difficulty_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current_difficulty := String(local_player.get("difficulty", "Expert"))
	var available_difficulties: Array = instruments.get(current_instrument, [])
	if available_difficulties.is_empty():
		available_difficulties = ["Easy", "Medium", "Hard", "Expert"]
	for difficulty in ["Easy", "Medium", "Hard", "Expert"]:
		if difficulty not in available_difficulties:
			continue
		_battle_difficulty_option.add_item("★  %s" % I18n.difficulty_name(difficulty))
		_battle_difficulty_option.set_item_metadata(
			_battle_difficulty_option.item_count - 1, difficulty)
		if difficulty == current_difficulty:
			_battle_difficulty_option.select(
				_battle_difficulty_option.item_count - 1)
	_battle_difficulty_option.disabled = current_instrument.is_empty()
	_style_battle_option(_battle_difficulty_option)
	_battle_difficulty_option.item_selected.connect(_on_battle_difficulty_selected)
	setup_box.add_child(_battle_difficulty_option)

	_battle_ready_button = Button.new()
	var currently_ready := bool(local_player.get("ready", false))
	var ready_icon := "✓" if currently_ready else "○"
	_battle_ready_button.text = "%s  %s" % [
		ready_icon, I18n.t("ready") if currently_ready else I18n.t("not_ready")]
	_battle_ready_button.toggle_mode = true
	_battle_ready_button.button_pressed = currently_ready
	_battle_ready_button.custom_minimum_size = Vector2(0, _u(90))
	UITheme.style_primary_button(
		_battle_ready_button,
		UITheme.ROCK_READY if currently_ready else UITheme.ROCK_STEEL_LIGHT,
		_fs(28))
	_battle_ready_button.toggled.connect(_on_battle_ready_toggled)
	_battle_lobby_controls.add_child(_battle_ready_button)

	if BattleSession.is_host:
		_battle_start_button = Button.new()
		_battle_start_button.text = "▶  %s" % I18n.t("start_match")
		_battle_start_button.custom_minimum_size = Vector2(0, _u(104))
		UITheme.style_primary_button(_battle_start_button, UITheme.ROCK_RED, _fs(31))
		_battle_start_button.pressed.connect(BattleSession.host_start_match)
		_battle_lobby_controls.add_child(_battle_start_button)

	var leave_btn := Button.new()
	leave_btn.text = "×  %s" % I18n.t("leave_room")
	leave_btn.custom_minimum_size = Vector2(0, _u(70))
	UITheme.style_danger_button(leave_btn, _fs(21))
	leave_btn.pressed.connect(_on_battle_leave)
	_battle_lobby_controls.add_child(leave_btn)
	_refresh_battle_player_list()

func _build_battle_host_options(parent: VBoxContainer) -> void:
	var selected: Dictionary = BattleSession.selected_song
	var current_mode := String(selected.get("mode", "guitar"))
	var current_preset := String(selected.get("preset", "Tiles"))
	if not BattleSession.is_host:
		if not selected.is_empty():
			var summary := Label.new()
			summary.text = "%s  %s    •    %s" % [
				"GTR" if current_mode == "guitar" else "KEY",
				I18n.t("guitar_mode") if current_mode == "guitar" else I18n.t("piano_mode"),
				I18n.preset_name(current_preset),
			]
			summary.custom_minimum_size = Vector2(0, _u(64))
			summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			summary.add_theme_font_size_override("font_size", _fs(22))
			summary.add_theme_color_override("font_color", UITheme.ROCK_PARCHMENT)
			parent.add_child(summary)
		return

	parent.add_child(_battle_section_title(
		"★", I18n.t("multiplayer_host_settings"), UITheme.ROCK_PARCHMENT))
	parent.add_child(_battle_field_label(I18n.t("game_mode")))
	_battle_game_mode_option = OptionButton.new()
	_battle_game_mode_option.custom_minimum_size = Vector2(0, _u(78))
	_battle_game_mode_option.add_item("KEY  %s" % I18n.t("piano_mode"))
	_battle_game_mode_option.set_item_metadata(0, "piano")
	_battle_game_mode_option.add_item("GTR  %s" % I18n.t("guitar_mode"))
	_battle_game_mode_option.set_item_metadata(1, "guitar")
	_battle_game_mode_option.select(1 if current_mode == "guitar" else 0)
	_style_battle_option(_battle_game_mode_option)
	_battle_game_mode_option.item_selected.connect(_on_battle_game_mode_selected)
	parent.add_child(_battle_game_mode_option)

	parent.add_child(_battle_field_label(I18n.t("gameplay_preset")))
	_battle_preset_option = OptionButton.new()
	_battle_preset_option.custom_minimum_size = Vector2(0, _u(78))
	for preset in PlayabilityScript.PRESET_ORDER:
		var preset_tag := I18n.t("preset_assisted_tag") \
			if PlayabilityScript.is_assisted_preset(preset) else I18n.t("preset_raw_tag")
		_battle_preset_option.add_item(
			"%s  %s" % [preset_tag, I18n.preset_name(preset)])
		_battle_preset_option.set_item_metadata(
			_battle_preset_option.item_count - 1, preset)
		if preset == current_preset:
			_battle_preset_option.select(_battle_preset_option.item_count - 1)
	_style_battle_option(_battle_preset_option)
	_battle_preset_option.item_selected.connect(_on_battle_preset_selected)
	parent.add_child(_battle_preset_option)

func _refresh_battle_player_list() -> void:
	if not is_instance_valid(_battle_players_box):
		return
	for child in _battle_players_box.get_children():
		child.queue_free()
	for player in BattleSession._players_array():
		var ready := bool(player.get("ready", false))
		var accent := UITheme.ROCK_READY if ready else UITheme.ROCK_STEEL_LIGHT
		var instrument := String(player.get("instrument", ""))
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0, _u(88))
		card.add_theme_stylebox_override(
			"panel", UITheme.glow_style(CARD_BG, accent, 5, 7))
		_battle_players_box.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(_u(14)))
		card.add_child(row)
		row.add_child(_battle_icon_badge(
			_instrument_icon(instrument), accent, 70))
		var player_text := VBoxContainer.new()
		player_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_text.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(player_text)
		var name := Label.new()
		name.text = "%s%s" % [
			player.get("name", I18n.t("default_player_name")),
			"  ★ HOST" if bool(player.get("host", false)) else "",
		]
		name.add_theme_font_size_override("font_size", _fs(24))
		name.add_theme_color_override("font_color", TEXT_BRIGHT)
		if UITheme.font_bold():
			name.add_theme_font_override("font", UITheme.font_bold())
		player_text.add_child(name)
		var detail := Label.new()
		detail.text = _instrument_label(instrument) if not instrument.is_empty() \
			else I18n.t("choose_instrument")
		var transfer_status := BattleSession.song_transfer_status_for(
			String(player.get("uid", "")))
		if not transfer_status.is_empty():
			detail.text += "  •  %s" % transfer_status
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_theme_font_size_override("font_size", _fs(17))
		detail.add_theme_color_override("font_color", TEXT_DIM)
		player_text.add_child(detail)
		var state_badge := Label.new()
		state_badge.text = "✓\n%s" % I18n.t("ready") if ready else "…\n%s" % I18n.t("not_ready")
		state_badge.custom_minimum_size = Vector2(_u(118), 0)
		state_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		state_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		state_badge.add_theme_font_size_override("font_size", _fs(17))
		state_badge.add_theme_color_override("font_color", accent)
		row.add_child(state_badge)

func _on_battle_mode_selected(mode: String) -> void:
	if BattleSession.session_state == "lobby":
		return
	_battle_mode = mode
	for key in _battle_mode_buttons:
		var button: Button = _battle_mode_buttons[key]
		button.button_pressed = key == mode
		_style_battle_mode_card(button, key == mode)
	if is_instance_valid(_battle_overlay):
		var help := _battle_overlay.find_child("ModeHelp", true, false) as Label
		if help:
			help.text = _battle_mode_help()

func _battle_mode_help() -> String:
	return I18n.t("battle_mode_help") if _battle_mode == "battle" else I18n.t("band_mode_help")

func _on_battle_create() -> void:
	BattleSession.set_song_catalog(found_songs)
	BattleSession.create_room(_battle_mode, _battle_name_edit.text)

func _on_battle_join() -> void:
	BattleSession.set_song_catalog(found_songs)
	BattleSession.join_room(_battle_code_edit.text, _battle_name_edit.text)

func _on_battle_leave() -> void:
	BattleSession.leave_room()
	if is_instance_valid(_battle_connection_panel):
		_battle_connection_panel.visible = true
	_build_battle_lobby_controls()

func _on_battle_song_selected(index: int) -> void:
	if index <= 0 or index - 1 >= found_songs.size():
		return
	var song: Dictionary = found_songs[index - 1]
	var instruments := _scan_song_instruments(song)
	if instruments.is_empty():
		instruments = {"guitar": ["Expert"]}
	BattleSession.host_select_song(song, instruments)

func _on_battle_instrument_selected(index: int) -> void:
	if index <= 0:
		BattleSession.update_local_player({"instrument": "", "ready": false})
		return
	var instrument := String(_battle_instrument_option.get_item_metadata(index))
	var instruments: Dictionary = BattleSession.selected_song.get("instruments", {})
	var difficulties: Array = instruments.get(instrument, ["Expert"])
	var difficulty := "Expert" if "Expert" in difficulties else String(difficulties.back())
	_refresh_battle_difficulty_options(difficulties, difficulty)
	BattleSession.update_local_player({
		"instrument": instrument, "difficulty": difficulty, "ready": false})

func _refresh_battle_difficulty_options(
		difficulties: Array, selected_difficulty: String) -> void:
	if not is_instance_valid(_battle_difficulty_option):
		return
	_battle_difficulty_option.clear()
	for difficulty in ["Easy", "Medium", "Hard", "Expert"]:
		if difficulty not in difficulties:
			continue
		_battle_difficulty_option.add_item(I18n.difficulty_name(difficulty))
		_battle_difficulty_option.set_item_metadata(
			_battle_difficulty_option.item_count - 1, difficulty)
		if difficulty == selected_difficulty:
			_battle_difficulty_option.select(
				_battle_difficulty_option.item_count - 1)
	_battle_difficulty_option.disabled = difficulties.is_empty()

func _on_battle_difficulty_selected(index: int) -> void:
	var difficulty := String(_battle_difficulty_option.get_item_metadata(index))
	BattleSession.update_local_player({
		"difficulty": difficulty, "ready": false})

func _on_battle_preset_selected(index: int) -> void:
	var preset := String(_battle_preset_option.get_item_metadata(index))
	var mode := String(BattleSession.selected_song.get("mode", "guitar"))
	BattleSession.host_update_match_options(mode, preset)

func _on_battle_game_mode_selected(index: int) -> void:
	var mode := String(_battle_game_mode_option.get_item_metadata(index))
	var preset := String(BattleSession.selected_song.get("preset", "Tiles"))
	BattleSession.host_update_match_options(mode, preset)

func _on_battle_ready_toggled(ready: bool) -> void:
	var ready_icon := "✓" if ready else "○"
	_battle_ready_button.text = "%s  %s" % [
		ready_icon, I18n.t("ready") if ready else I18n.t("not_ready")]
	UITheme.style_primary_button(
		_battle_ready_button,
		UITheme.ROCK_READY if ready else UITheme.ROCK_STEEL_LIGHT,
		_fs(28))
	BattleSession.update_local_player({"ready": ready})

func _on_battle_state_changed(_state: String, detail: String) -> void:
	if is_instance_valid(_battle_status_label):
		_battle_status_label.text = detail
		_battle_status_label.visible = _state != "lobby"
	if is_instance_valid(_battle_connection_panel):
		_battle_connection_panel.visible = BattleSession.session_state != "lobby"
	# Validation errors (not ready, missing song, duplicate Band role, etc.)
	# must not recreate the controls and visually clear the player's choices.
	if is_instance_valid(_battle_overlay) and _state == "lobby" \
			and not is_instance_valid(_battle_players_box):
		_build_battle_lobby_controls()

func _on_battle_lobby_changed(_players: Array, _room: Dictionary) -> void:
	if not is_instance_valid(_battle_overlay):
		return
	_battle_mode = BattleSession.room_mode
	if is_instance_valid(_battle_connection_panel):
		_battle_connection_panel.visible = false
	var current_fingerprint := _battle_song_render_key()
	if not is_instance_valid(_battle_players_box) \
			or current_fingerprint != _battle_rendered_song_fingerprint:
		_build_battle_lobby_controls()
	else:
		_refresh_battle_player_list()

func _on_battle_error(message: String) -> void:
	if is_instance_valid(_battle_status_label):
		_battle_status_label.visible = true
		_battle_status_label.text = message
		_battle_status_label.add_theme_color_override("font_color", UITheme.ROCK_DANGER)

func _on_battle_song_transfer_progress(
		progress: float, detail: String, active: bool) -> void:
	if is_instance_valid(_battle_transfer_label):
		_battle_transfer_label.visible = not detail.is_empty()
		_battle_transfer_label.text = detail
	if is_instance_valid(_battle_transfer_bar):
		_battle_transfer_bar.visible = active
		_battle_transfer_bar.value = progress * 100.0
	if is_instance_valid(_battle_status_label) and not detail.is_empty():
		_battle_status_label.text = detail
		_battle_status_label.add_theme_color_override(
			"font_color", UITheme.ROCK_PARCHMENT)

func _on_battle_song_transfer_completed(_song: Dictionary) -> void:
	AppCache.song_list_valid = false
	_scan_songs(true)

func _close_battle_menu() -> void:
	if is_instance_valid(_battle_overlay):
		_battle_overlay.queue_free()
	_battle_overlay = null
	_battle_back_button = null

func _handle_back_navigation() -> bool:
	if is_instance_valid(_tutorial_overlay):
		_close_song_tutorial()
		return true
	if is_instance_valid(_battle_overlay):
		_close_battle_menu()
		return true
	if is_instance_valid(_launch_overlay):
		_close_launch_screen()
		return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _handle_back_navigation():
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if not _handle_back_navigation() and is_inside_tree():
			get_tree().quit()

func _instrument_label(key: String) -> String:
	return I18n.instrument_name(key)

func _instrument_icon(key: String) -> String:
	match key:
		"guitar": return "GTR"
		"bass": return "BAS"
		"drums": return "DRM"
		"keys": return "KEY"
		"vocals": return "VOX"
	return "?"

func _battle_song_render_key() -> String:
	return "%s|%s|%s" % [
		BattleSession.selected_song.get("fingerprint", ""),
		BattleSession.selected_song.get("mode", "guitar"),
		BattleSession.selected_song.get("preset", "Tiles"),
	]

func _battle_field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.custom_minimum_size = Vector2(0, _u(32))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", _fs(20))
	label.add_theme_color_override("font_color", TEXT_DIM)
	if UITheme.font_bold():
		label.add_theme_font_override("font", UITheme.font_bold())
	return label

func _style_battle_option(option: OptionButton) -> void:
	option.add_theme_font_size_override("font_size", _fs(26))
	option.add_theme_color_override("font_color", TEXT_BRIGHT)
	var popup := option.get_popup()
	popup.add_theme_font_size_override("font_size", _fs(25))
	popup.add_theme_constant_override("v_separation", int(_u(16)))
	popup.add_theme_constant_override("item_start_padding", int(_u(18)))
	popup.add_theme_constant_override("item_end_padding", int(_u(18)))

func _battle_icon_badge(text: String, accent: Color, size: float) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(_u(size), _u(size))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UITheme.glow_style(
		Color(accent.r, accent.g, accent.b, 0.16), accent, 18, 10)
	style.set_border_width_all(2)
	badge.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(
		"font_size", _fs(34 if text.length() <= 3 else 22))
	label.add_theme_color_override("font_color", accent.lightened(0.28))
	if UITheme.font_bold():
		label.add_theme_font_override("font", UITheme.font_bold())
	badge.add_child(label)
	return badge

func _battle_section_title(icon_text: String, text: String, accent: Color) -> Label:
	var label := Label.new()
	label.text = "%s   %s" % [icon_text, text.to_upper()]
	label.custom_minimum_size = Vector2(0, _u(46))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", _fs(25))
	label.add_theme_color_override("font_color", accent.lightened(0.22))
	if UITheme.font_bold():
		label.add_theme_font_override("font", UITheme.font_bold())
	return label

func _make_battle_mode_card(
		mode: String, icon_text: String, title_text: String,
		subtitle: String, accent: Color) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, _u(156))
	button.set_meta("battle_mode", mode)
	button.set_meta("battle_accent", accent)
	button.text = ""

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = _u(14)
	row.offset_top = _u(14)
	row.offset_right = -_u(14)
	row.offset_bottom = -_u(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(_u(16)))
	button.add_child(row)
	row.add_child(_battle_icon_badge(icon_text, accent, 104))

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	var title := Label.new()
	title.text = title_text
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", _fs(28))
	title.add_theme_color_override("font_color", accent.lightened(0.28))
	if UITheme.font_bold():
		title.add_theme_font_override("font", UITheme.font_bold())
	words.add_child(title)
	var hint := Label.new()
	hint.text = subtitle
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", _fs(17))
	hint.add_theme_color_override("font_color", TEXT_DIM)
	words.add_child(hint)
	return button

func _style_battle_mode_card(button: Button, selected: bool) -> void:
	var accent: Color = button.get_meta("battle_accent", UITheme.ROCK_STEEL_LIGHT)
	var normal := UITheme.glow_style(
		Color(accent.r, accent.g, accent.b, 0.24 if selected else 0.08),
		accent if selected else UITheme.ROCK_STEEL, 5, 8 if selected else 4)
	normal.set_border_width_all(3 if selected else 1)
	var hover := normal.duplicate()
	hover.bg_color = Color(accent.r, accent.g, accent.b, 0.20)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(accent.r, accent.g, accent.b, 0.32)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
# =====================================================================
#  LAUNCH SCREEN
# =====================================================================

func _open_launch_screen(index: int) -> void:
	if index < 0 or index >= found_songs.size():
		return
	if _launch_overlay:
		_launch_overlay.queue_free()
		_launch_overlay = null

	_launch_song_index = index
	var song: Dictionary = found_songs[index]
	var parsed := _parse_song_name(song["display_name"])

	# Scan instruments
	_launch_instruments = _scan_song_instruments(song)
	if _launch_instruments.is_empty():
		# Fallback: assume guitar Expert
		_launch_instruments = {"guitar": ["Expert"]}

	# Pick default instrument (guitar first, then first available)
	if _launch_instruments.has("guitar"):
		_launch_selected_instrument = "guitar"
	else:
		_launch_selected_instrument = _launch_instruments.keys()[0]

	# Pick default difficulty
	var inst_diffs: Array = _launch_instruments[_launch_selected_instrument]
	_launch_selected_difficulty = "Expert" if "Expert" in inst_diffs else inst_diffs[inst_diffs.size() - 1]

	# Build overlay
	var theme := _create_theme()

	_launch_overlay = Control.new()
	_launch_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_launch_overlay.theme = theme
	add_child(_launch_overlay)

	# Concert-stage background with a dark readability layer.
	var bg := ColorRect.new()
	bg.color = Color(0.020, 0.016, 0.014, 0.975)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # block clicks to song list
	_launch_overlay.add_child(bg)
	UITheme.add_hardrock_background(bg)

	var sa := UITheme.safe_insets(self)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = sa["l"] + _u(18); scroll.offset_right = -(sa["r"] + _u(18))
	scroll.offset_top = sa["t"] + _u(14); scroll.offset_bottom = -(sa["b"] + _u(14))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = int(_u(14))
	_launch_overlay.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", int(_u(16)))
	scroll.add_child(vbox)

	# --- Chrome top bar: Back + screen identity + Help/Delete ---
	var top_panel := PanelContainer.new()
	var top_style := UITheme.glow_style(
		Color(0.035, 0.029, 0.026, 0.97), UITheme.ROCK_RED, 5, 8)
	top_style.border_color = UITheme.ROCK_STEEL
	top_style.border_width_left = int(_u(5))
	top_style.border_width_bottom = int(_u(4))
	top_style.content_margin_left = _u(12)
	top_style.content_margin_right = _u(12)
	top_style.content_margin_top = _u(10)
	top_style.content_margin_bottom = _u(10)
	top_panel.add_theme_stylebox_override("panel", top_style)
	vbox.add_child(top_panel)
	var top_bar := HBoxContainer.new()
	top_bar.custom_minimum_size = Vector2(0, _u(72))
	top_bar.add_theme_constant_override("separation", int(_u(10)))
	top_panel.add_child(top_bar)

	var back_btn := Button.new()
	back_btn.text = "‹  " + I18n.t("back")
	UITheme.style_ghost_button(back_btn, _fs(19))
	back_btn.custom_minimum_size = Vector2(_u(132), _u(64))
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back_btn.pressed.connect(_close_launch_screen)
	top_bar.add_child(back_btn)

	top_bar.add_child(UITheme.make_game_logo(_u(62)))
	var screen_identity := VBoxContainer.new()
	screen_identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen_identity.alignment = BoxContainer.ALIGNMENT_CENTER
	top_bar.add_child(screen_identity)
	var identity_kicker := Label.new()
	identity_kicker.text = I18n.t("launch_kicker")
	identity_kicker.add_theme_font_size_override("font_size", _fs(13))
	identity_kicker.add_theme_color_override("font_color", UITheme.ROCK_PARCHMENT)
	screen_identity.add_child(identity_kicker)
	var identity_title := Label.new()
	identity_title.text = I18n.t("launch_title").to_upper()
	identity_title.add_theme_font_size_override("font_size", _fs(25))
	identity_title.add_theme_color_override("font_color", TEXT_BRIGHT)
	if UITheme.font_bold():
		identity_title.add_theme_font_override("font", UITheme.font_bold())
	screen_identity.add_child(identity_title)

	var settings_help_btn := Button.new()
	settings_help_btn.text = "?\n%s" % I18n.t("menu_guide")
	settings_help_btn.tooltip_text = I18n.t("settings_tutorial_title")
	UITheme.style_ghost_button(settings_help_btn, _fs(15))
	settings_help_btn.custom_minimum_size = Vector2(_u(96), _u(64))
	settings_help_btn.pressed.connect(_open_game_settings_tutorial)
	top_bar.add_child(settings_help_btn)

	# Delete button — only for user-imported songs
	if song["path"].begins_with("user://"):
		var del_btn := Button.new()
		del_btn.text = "×\n%s" % I18n.t("delete").to_upper()
		UITheme.style_danger_button(del_btn, _fs(19))
		del_btn.custom_minimum_size = Vector2(_u(108), _u(64))
		del_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
		del_btn.pressed.connect(_on_delete_song)
		top_bar.add_child(del_btn)

	# --- Song hero card: album art + title/artist ---
	var info_panel := PanelContainer.new()
	var info_style := UITheme.card_style(UITheme.ROCK_RED)
	info_style.bg_color = CARD_BG
	info_style.border_color = UITheme.ROCK_STEEL
	info_style.border_width_bottom = int(_u(4))
	info_panel.add_theme_stylebox_override("panel", info_style)
	vbox.add_child(info_panel)
	var info_hbox := HBoxContainer.new()
	info_hbox.add_theme_constant_override("separation", int(_u(20)))
	info_panel.add_child(info_hbox)

	var art_texture := _load_album_art(song)
	if art_texture:
		var art_frame := PanelContainer.new()
		var frame_style := UITheme.glow_style(
			Color(0, 0, 0, 0), UITheme.ROCK_STEEL_LIGHT, 4, int(_u(8)))
		frame_style.content_margin_left = 0; frame_style.content_margin_right = 0
		frame_style.content_margin_top = 0; frame_style.content_margin_bottom = 0
		art_frame.add_theme_stylebox_override("panel", frame_style)
		art_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info_hbox.add_child(art_frame)
		var art_rect := TextureRect.new()
		art_rect.texture = art_texture
		art_rect.custom_minimum_size = Vector2(_u(156), _u(156))
		art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art_frame.add_child(art_rect)
	else:
		var art_panel := PanelContainer.new()
		var art_style := UITheme.flat_style(Color(0.055, 0.047, 0.041), 4)
		art_style.border_color = UITheme.ROCK_STEEL
		art_style.set_border_width_all(1)
		art_panel.add_theme_stylebox_override("panel", art_style)
		art_panel.custom_minimum_size = Vector2(_u(156), _u(156))
		art_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info_hbox.add_child(art_panel)
		var art_icon := Label.new()
		art_icon.text = "♪"
		art_icon.add_theme_font_size_override("font_size", _fs(64))
		art_icon.add_theme_color_override("font_color", UITheme.ROCK_STEEL_LIGHT)
		art_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		art_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		art_panel.add_child(art_icon)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_vbox.add_theme_constant_override("separation", int(_u(6)))
	info_hbox.add_child(info_vbox)

	var now_playing := Label.new()
	now_playing.text = "◆  %s" % I18n.t("now_playing")
	now_playing.add_theme_font_size_override("font_size", _fs(14))
	now_playing.add_theme_color_override("font_color", UITheme.ROCK_RED.lightened(0.28))
	if UITheme.font_bold():
		now_playing.add_theme_font_override("font", UITheme.font_bold())
	info_vbox.add_child(now_playing)

	var title_lbl := Label.new()
	title_lbl.text = parsed["title"]
	title_lbl.add_theme_font_size_override("font_size", _fs(32))
	title_lbl.add_theme_color_override("font_color", TEXT_BRIGHT)
	if UITheme.font_bold():
		title_lbl.add_theme_font_override("font", UITheme.font_bold())
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	info_vbox.add_child(title_lbl)

	if parsed["artist"] != "":
		var artist_lbl := Label.new()
		artist_lbl.text = parsed["artist"]
		artist_lbl.add_theme_font_size_override("font_size", _fs(21))
		artist_lbl.add_theme_color_override("font_color", TEXT_DIM)
		info_vbox.add_child(artist_lbl)

	var loadout_banner := PanelContainer.new()
	var loadout_style := UITheme.glow_style(
		CARD_BG, UITheme.ROCK_RED, 5, 8)
	loadout_style.border_width_left = int(_u(6))
	loadout_style.content_margin_left = _u(18)
	loadout_style.content_margin_right = _u(18)
	loadout_style.content_margin_top = _u(10)
	loadout_style.content_margin_bottom = _u(10)
	loadout_banner.add_theme_stylebox_override("panel", loadout_style)
	vbox.add_child(loadout_banner)
	var loadout_row := HBoxContainer.new()
	loadout_banner.add_child(loadout_row)
	var loadout_title := Label.new()
	loadout_title.text = "⚡  %s" % I18n.t("build_loadout")
	loadout_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loadout_title.add_theme_font_size_override("font_size", _fs(22))
	loadout_title.add_theme_color_override("font_color", UITheme.ROCK_IVORY)
	if UITheme.font_bold():
		loadout_title.add_theme_font_override("font", UITheme.font_bold())
	loadout_row.add_child(loadout_title)
	var loadout_hint := Label.new()
	loadout_hint.text = I18n.t("build_loadout_hint")
	loadout_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loadout_hint.add_theme_font_size_override("font_size", _fs(14))
	loadout_hint.add_theme_color_override("font_color", TEXT_DIM)
	loadout_row.add_child(loadout_hint)

	# --- Instrument selection ---
	if _launch_instruments.size() > 1 or not _launch_instruments.has("guitar"):
		vbox.add_child(_section_label(I18n.t("instrument")))

		var inst_hbox := HBoxContainer.new()
		inst_hbox.add_theme_constant_override("separation", int(_u(10)))
		vbox.add_child(inst_hbox)

		_launch_instrument_btns.clear()
		# Order: guitar, bass, keys, drums
		for inst_key in ["guitar", "bass", "keys", "drums"]:
			if not _launch_instruments.has(inst_key):
				continue
			var btn := Button.new()
			btn.text = "%s\n%s" % [
				_instrument_icon(inst_key), I18n.instrument_name(inst_key).to_upper()]
			btn.add_theme_font_size_override("font_size", _fs(18))
			btn.custom_minimum_size = Vector2(0, _u(74))
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.pressed.connect(_on_instrument_selected.bind(inst_key))
			inst_hbox.add_child(btn)
			_launch_instrument_btns[inst_key] = btn
	else:
		_launch_instrument_btns.clear()

	# --- Difficulty selection ---
	vbox.add_child(_section_label(I18n.t("difficulty")))

	var diff_hbox := HBoxContainer.new()
	diff_hbox.add_theme_constant_override("separation", int(_u(10)))
	diff_hbox.name = "DifficultyRow"
	vbox.add_child(diff_hbox)
	_rebuild_difficulty_buttons(diff_hbox)

	# --- Best score for current selection ---
	_launch_star_label = Label.new()
	_launch_star_label.add_theme_font_size_override("font_size", _fs(20))
	_launch_star_label.add_theme_color_override("font_color", STAR_COLOR)
	vbox.add_child(_launch_star_label)

	# --- Preset chips ---
	vbox.add_child(_section_label(I18n.t("gameplay")))

	var preset_grid := GridContainer.new()
	preset_grid.columns = 2
	preset_grid.add_theme_constant_override("h_separation", int(_u(10)))
	preset_grid.add_theme_constant_override("v_separation", int(_u(10)))
	vbox.add_child(preset_grid)

	_launch_preset_btns.clear()
	for preset in PlayabilityScript.PRESET_ORDER:
		var pbtn := Button.new()
		pbtn.text = "%s\n%s" % [
			I18n.t("preset_assisted_tag") if PlayabilityScript.is_assisted_preset(preset) \
				else I18n.t("preset_raw_tag"),
			I18n.preset_name(preset).to_upper()]
		pbtn.add_theme_font_size_override("font_size", _fs(17))
		pbtn.custom_minimum_size = Vector2(0, _u(70))
		pbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pbtn.pressed.connect(_on_preset_selected.bind(preset))
		preset_grid.add_child(pbtn)
		_launch_preset_btns[preset] = pbtn

	# --- Mode chips (Piano 4 / Guitar 5) ---
	vbox.add_child(_section_label(I18n.t("mode")))

	var mode_hbox := HBoxContainer.new()
	mode_hbox.add_theme_constant_override("separation", int(_u(10)))
	vbox.add_child(mode_hbox)

	_launch_mode_btns.clear()
	for mode_key in ["piano", "guitar"]:
		var mbtn := Button.new()
		mbtn.text = "4K\n%s" % I18n.t("mode_piano").to_upper() \
			if mode_key == "piano" else "5K\n%s" % I18n.t("mode_guitar").to_upper()
		mbtn.add_theme_font_size_override("font_size", _fs(18))
		mbtn.custom_minimum_size = Vector2(0, _u(70))
		mbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mbtn.pressed.connect(_on_mode_selected.bind(mode_key))
		mode_hbox.add_child(mbtn)
		_launch_mode_btns[mode_key] = mbtn

	# --- View chips (Guitar Hero / Flat) ---
	vbox.add_child(_section_label(I18n.t("view")))

	var view_hbox := HBoxContainer.new()
	view_hbox.add_theme_constant_override("separation", int(_u(10)))
	vbox.add_child(view_hbox)

	_launch_view_btns.clear()
	for view_key in ["gh", "flat"]:
		var vbtn := Button.new()
		vbtn.text = "3D\n%s" % I18n.t("view_gh").to_upper() \
			if view_key == "gh" else "2D\n%s" % I18n.t("view_flat").to_upper()
		vbtn.add_theme_font_size_override("font_size", _fs(18))
		vbtn.custom_minimum_size = Vector2(0, _u(68))
		vbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbtn.pressed.connect(_on_view_selected.bind(view_key))
		view_hbox.add_child(vbtn)
		_launch_view_btns[view_key] = vbtn

	# --- Effect quality chips ---
	vbox.add_child(_section_label(I18n.t("vfx_quality")))

	var vfx_hbox := HBoxContainer.new()
	vfx_hbox.add_theme_constant_override("separation", int(_u(8)))
	vbox.add_child(vfx_hbox)

	_launch_vfx_btns.clear()
	for quality_key in ["full", "balanced", "performance"]:
		var qbtn := Button.new()
		qbtn.text = "FX\n%s" % I18n.t("vfx_" + quality_key).to_upper()
		qbtn.add_theme_font_size_override("font_size", _fs(16))
		qbtn.custom_minimum_size = Vector2(0, _u(66))
		qbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qbtn.pressed.connect(_on_vfx_quality_selected.bind(quality_key))
		vfx_hbox.add_child(qbtn)
		_launch_vfx_btns[quality_key] = qbtn

	# --- Rock Meter behavior ---
	vbox.add_child(_section_label(I18n.t("rock_meter")))

	var rock_hbox := HBoxContainer.new()
	rock_hbox.add_theme_constant_override("separation", int(_u(8)))
	vbox.add_child(rock_hbox)

	_launch_rock_meter_btns.clear()
	for rock_mode in ["off", "visual", "fail"]:
		var rock_btn := Button.new()
		rock_btn.text = "♥\n%s" % I18n.t("rock_meter_" + rock_mode).to_upper()
		rock_btn.add_theme_font_size_override("font_size", _fs(15))
		rock_btn.custom_minimum_size = Vector2(0, _u(66))
		rock_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rock_btn.pressed.connect(_on_rock_meter_selected.bind(rock_mode))
		rock_hbox.add_child(rock_btn)
		_launch_rock_meter_btns[rock_mode] = rock_btn

	# --- Dynamic crowd audio ---
	vbox.add_child(_section_label(I18n.t("crowd_audio")))
	var crowd_hbox := HBoxContainer.new()
	crowd_hbox.add_theme_constant_override("separation", int(_u(10)))
	vbox.add_child(crowd_hbox)
	_launch_crowd_btns.clear()
	for crowd_mode in ["on", "off"]:
		var crowd_btn := Button.new()
		crowd_btn.text = "♫\n%s" % I18n.t("crowd_" + crowd_mode).to_upper()
		crowd_btn.add_theme_font_size_override("font_size", _fs(17))
		crowd_btn.custom_minimum_size = Vector2(0, _u(66))
		crowd_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crowd_btn.pressed.connect(_on_crowd_audio_selected.bind(crowd_mode))
		crowd_hbox.add_child(crowd_btn)
		_launch_crowd_btns[crowd_mode] = crowd_btn

	# --- Wrong-note guitar feedback ---
	vbox.add_child(_section_label(I18n.t("miss_sfx")))
	var miss_sfx_hbox := HBoxContainer.new()
	miss_sfx_hbox.add_theme_constant_override("separation", int(_u(10)))
	vbox.add_child(miss_sfx_hbox)
	_launch_miss_sfx_btns.clear()
	for miss_sfx_mode in ["on", "off"]:
		var miss_sfx_btn := Button.new()
		miss_sfx_btn.text = "!\n%s" % I18n.t("miss_sfx_" + miss_sfx_mode).to_upper()
		miss_sfx_btn.add_theme_font_size_override("font_size", _fs(17))
		miss_sfx_btn.custom_minimum_size = Vector2(0, _u(66))
		miss_sfx_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		miss_sfx_btn.pressed.connect(_on_miss_sfx_selected.bind(miss_sfx_mode))
		miss_sfx_hbox.add_child(miss_sfx_btn)
		_launch_miss_sfx_btns[miss_sfx_mode] = miss_sfx_btn

	# --- Speed slider ---
	vbox.add_child(_section_label(I18n.t("speed")))

	var speed_hbox := HBoxContainer.new()
	speed_hbox.add_theme_constant_override("separation", int(_u(12)))
	vbox.add_child(speed_hbox)

	_launch_approach_slider = HSlider.new()
	_launch_approach_slider.min_value = 0.8; _launch_approach_slider.max_value = 2.0; _launch_approach_slider.step = 0.05
	_launch_approach_slider.value = Settings.approach_time_sec
	_launch_approach_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_launch_approach_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_launch_approach_slider.custom_minimum_size = Vector2(_u(120), _u(52))
	_launch_approach_slider.value_changed.connect(_on_launch_approach_changed)
	speed_hbox.add_child(_launch_approach_slider)

	_launch_approach_label = Label.new()
	_launch_approach_label.text = "%.1f" % Settings.approach_time_sec
	_launch_approach_label.add_theme_font_size_override("font_size", _fs(18))
	_launch_approach_label.add_theme_color_override("font_color", ACCENT.lightened(0.3))
	_launch_approach_label.custom_minimum_size = Vector2(_u(48), 0)
	speed_hbox.add_child(_launch_approach_label)

	# --- Refresh cache button ---
	var cache_btn := Button.new()
	cache_btn.text = I18n.t("refresh_cache")
	UITheme.style_ghost_button(cache_btn, _fs(17))
	cache_btn.custom_minimum_size = Vector2(0, _u(54))
	cache_btn.pressed.connect(_on_clear_cache.bind(song))
	vbox.add_child(cache_btn)

	# --- Spacer ---
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, _u(10))
	vbox.add_child(spacer)

	# --- START button — stamped red stage trigger ---
	var start_btn := Button.new()
	start_btn.name = "LaunchStartButton"
	start_btn.text = "▶  %s" % I18n.t("start").to_upper()
	UITheme.style_primary_button(start_btn, UITheme.ROCK_RED, _fs(31))
	start_btn.custom_minimum_size = Vector2(0, _u(98))
	start_btn.pressed.connect(_on_launch_start)
	vbox.add_child(start_btn)

	# Gentle pulse on the start button
	start_btn.pivot_offset = start_btn.size / 2.0
	start_btn.resized.connect(func(): start_btn.pivot_offset = start_btn.size / 2.0)
	# Bind the infinite pulse to the button. It is destroyed with the launch
	# overlay, preventing an orphaned infinite tween when Back is pressed.
	var pulse := start_btn.create_tween()
	pulse.set_loops()
	pulse.tween_property(start_btn, "scale", Vector2(1.015, 1.015), 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(start_btn, "scale", Vector2(1.0, 1.0), 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Update visuals
	_update_instrument_highlight()
	_update_preset_highlight()
	_update_mode_highlight()
	_update_view_highlight()
	_update_vfx_quality_highlight()
	_update_rock_meter_highlight()
	_update_crowd_audio_highlight()
	_update_miss_sfx_highlight()
	_update_launch_star()

	# Fade in
	_launch_overlay.modulate.a = 0.0
	var tw := _launch_overlay.create_tween()
	tw.tween_property(_launch_overlay, "modulate:a", 1.0, 0.2)

func _close_launch_screen() -> void:
	if _launch_overlay:
		_launch_overlay.queue_free()
		_launch_overlay = null

func _on_clear_cache(song: Dictionary) -> void:
	var cache_key: String = String(song["path"]).md5_text()
	var deleted := 0
	# 1. Delete cached mix files
	for ext in ["_mixed.ogg", "_mixed.wav"]:
		var cached := MIX_CACHE_DIR.path_join(cache_key + ext)
		if FileAccess.file_exists(cached):
			DirAccess.remove_absolute(cached)
			deleted += 1
			print("Cache: silindi — %s" % cached)

	# 2. If song dir has a pre-converted song.wav from old import + raw mogg,
	#    delete the bad song.wav so it gets re-converted from raw source next time
	var song_dir: String = String(song["path"]).get_base_dir()
	if song_dir.begins_with("user://"):
		var raw_mogg := song_dir.path_join("_raw_mogg.ogg")
		var bad_wav := song_dir.path_join("song.wav")
		var bad_ogg := song_dir.path_join("song.ogg")
		# If raw multi-ch OGG exists, the converted file is suspect — delete it
		if FileAccess.file_exists(raw_mogg):
			if FileAccess.file_exists(bad_wav):
				DirAccess.remove_absolute(bad_wav)
				deleted += 1
				print("Cache: eski song.wav silindi (raw mogg'dan yeniden olusturulacak)")
			if FileAccess.file_exists(bad_ogg):
				DirAccess.remove_absolute(bad_ogg)
				deleted += 1
				print("Cache: eski song.ogg silindi (raw mogg'dan yeniden olusturulacak)")
			# Re-convert raw mogg → stereo now (async on Android)
			var stereo_path := song_dir.path_join("song.ogg")
			if _convert_mogg_to_stereo(raw_mogg, stereo_path):
				if OS.has_feature("android"):
					return  # async — _on_import_decode_done handles the rest
				else:
					deleted += 1
		elif FileAccess.file_exists(bad_wav):
			# No raw mogg but has song.wav — might have wrong sample rate header
			# Delete it + force re-decode from original source during playback
			DirAccess.remove_absolute(bad_wav)
			deleted += 1
			print("Cache: song.wav silindi (sample rate düzeltmesi)")

	if deleted > 0:
		_show_import_status(I18n.t("cache_cleared"))
	else:
		_show_import_status(I18n.t("cache_not_found"))

func _on_delete_song() -> void:
	if _launch_song_index < 0 or _launch_song_index >= found_songs.size():
		return
	var song: Dictionary = found_songs[_launch_song_index]
	var path: String = song["path"]
	if not path.begins_with("user://"):
		return

	# Delete the file
	if path.ends_with(".sng") or path.get_base_dir() == USER_SONGS_DIR:
		# Single file in user://songs/
		DirAccess.remove_absolute(path)
		print("Deleted: %s" % path)
	else:
		# File inside a subfolder — delete the entire folder
		var folder := path.get_base_dir()
		if folder.begins_with(USER_SONGS_DIR):
			_delete_dir_recursive(folder)
			print("Deleted folder: %s" % folder)

	# Also delete cached audio
	var cache_key := path.md5_text()
	for ext in ["_mixed.ogg", "_mixed.wav"]:
		var cached := MIX_CACHE_DIR.path_join(cache_key + ext)
		if FileAccess.file_exists(cached):
			DirAccess.remove_absolute(cached)

	_close_launch_screen()
	AppCache.remove_song(path)
	_scan_songs(true)

func _delete_dir_recursive(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if dir.current_is_dir():
			_delete_dir_recursive(dir_path.path_join(fname))
		else:
			dir.remove(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)

func _scan_song_instruments(song: Dictionary) -> Dictionary:
	var path: String = song["path"]
	if AppCache.instrument_data.has(path):
		return (AppCache.instrument_data[path] as Dictionary).duplicate(true)
	var result := _scan_song_instruments_uncached(song)
	AppCache.instrument_data[path] = result.duplicate(true)
	return result

func _scan_song_instruments_uncached(song: Dictionary) -> Dictionary:
	var path: String = song["path"]
	if path.ends_with(".chart"):
		return ChartParserScript.scan_instruments_from_file(path)
	elif path.to_lower().ends_with(".mid"):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return {}
		var data := file.get_buffer(file.get_length())
		file.close()
		return MidiParserScript.scan_instruments_from_data(data)
	elif path.to_lower().ends_with(".con") or path.to_lower().ends_with(".live"):
		var stfs := StfsParserScript.new()
		if not stfs.load_stfs(path):
			return {}
		var midi_data := stfs.get_midi_data()
		if midi_data.size() > 0:
			return MidiParserScript.scan_instruments_from_data(midi_data)
		return {}
	elif path.ends_with(".sng"):
		var loader = SngLoaderScript.new()
		if not loader.load_sng(path):
			return {}
		if loader.has_chart():
			var chart_text: String = loader.get_chart_text()
			if chart_text != "":
				return ChartParserScript.scan_instruments_from_text(chart_text)
		if loader.has_midi():
			var midi_data: PackedByteArray = loader.get_midi_data()
			return MidiParserScript.scan_instruments_from_data(midi_data)
	elif _is_stfs_by_magic(path):
		var stfs := StfsParserScript.new()
		if not stfs.load_stfs(path):
			return {}
		var midi_data := stfs.get_midi_data()
		if midi_data.size() > 0:
			return MidiParserScript.scan_instruments_from_data(midi_data)
	return {}

func _load_album_art(song: Dictionary) -> ImageTexture:
	var path: String = song["path"]
	if AppCache.album_art.has(path):
		var cached_entry := String(AppCache.album_art[path])
		if cached_entry.is_empty():
			return null
		var cached_texture := _load_cached_thumbnail(cached_entry)
		if cached_texture:
			return cached_texture

	var art_limit := clampi(int(_u(256)), 256, 384)
	var thumb_key := (path + "|" + str(art_limit)).md5_text()
	var thumb_path := THUMB_CACHE_DIR.path_join(thumb_key + ".png")
	if FileAccess.file_exists(thumb_path):
		var disk_texture := _load_cached_thumbnail(thumb_path)
		if disk_texture:
			AppCache.album_art[path] = thumb_path
			return disk_texture

	var texture := _load_album_art_uncached(song)
	if texture:
		DirAccess.make_dir_recursive_absolute(THUMB_CACHE_DIR)
		var image := texture.get_image()
		if image and image.save_png(ProjectSettings.globalize_path(thumb_path)) == OK:
			AppCache.album_art[path] = thumb_path
		else:
			# Keep this scene's texture, but retry persistence next app launch.
			AppCache.album_art.erase(path)
	else:
		# Cache missing artwork too so empty archives are not reopened on return.
		AppCache.album_art[path] = ""
	return texture

func _load_cached_thumbnail(path: String) -> ImageTexture:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var data := file.get_buffer(file.get_length())
	file.close()
	var image := Image.new()
	if image.load_png_from_buffer(data) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _load_album_art_uncached(song: Dictionary) -> ImageTexture:
	var path: String = song["path"]
	if path.ends_with(".sng"):
		var loader = SngLoaderScript.new()
		if loader.load_sng(path):
			var art_data := loader.get_album_art_data()
			if art_data.size() > 0:
				return _image_from_bytes(art_data)
	elif path.to_lower().ends_with(".con") or path.to_lower().ends_with(".live") or _is_stfs_by_magic(path):
		var stfs := StfsParserScript.new()
		if stfs.load_stfs(path):
			var art_data := stfs.get_album_art_data()
			if art_data.size() > 0:
				return _image_from_bytes(art_data)
	else:
		# Look for album.jpg/png in the same directory
		var dir_path := path.get_base_dir()
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
	# Skip Xbox DXT textures (png_xbox) — not standard PNG/JPEG, can't decode
	# Real JPEG starts with FF D8, real PNG starts with 89 50 4E 47
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
	# Keep large Magic-Tiles-style artwork crisp on high-DPI phones without
	# forcing every tablet/desktop thumbnail to consume 512px textures.
	var art_limit := clampi(int(_u(256)), 256, 384)
	if img.get_width() > art_limit or img.get_height() > art_limit:
		img.resize(art_limit, art_limit, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _rebuild_difficulty_buttons(container: HBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()
	_launch_diff_btns.clear()

	var diffs: Array = _launch_instruments.get(_launch_selected_instrument, [])
	for diff in diffs:
		var btn := Button.new()
		btn.text = "★\n%s" % I18n.difficulty_name(diff as String).to_upper()
		btn.add_theme_font_size_override("font_size", _fs(18))
		btn.custom_minimum_size = Vector2(0, _u(68))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_difficulty_selected.bind(diff as String))
		container.add_child(btn)
		_launch_diff_btns[diff as String] = btn

	# Select default
	if not (diffs as Array).has(_launch_selected_difficulty):
		_launch_selected_difficulty = "Expert" if "Expert" in diffs else (diffs[diffs.size() - 1] as String if diffs.size() > 0 else "Expert")
	_update_difficulty_highlight()

func _on_instrument_selected(inst_key: String) -> void:
	_launch_selected_instrument = inst_key
	_update_instrument_highlight()
	# Rebuild difficulty buttons for new instrument
	if _launch_overlay:
		var diff_row = _launch_overlay.find_child("DifficultyRow", true, false)
		if diff_row:
			_rebuild_difficulty_buttons(diff_row)
	_update_launch_star()

func _on_difficulty_selected(diff: String) -> void:
	_launch_selected_difficulty = diff
	_update_difficulty_highlight()
	_update_launch_star()

func _restyle_chip_group(btns: Dictionary, selected_key: String, accent: Color) -> void:
	for k in btns:
		UITheme.style_chip_button(btns[k], k == selected_key, accent)

func _update_instrument_highlight() -> void:
	_restyle_chip_group(_launch_instrument_btns, _launch_selected_instrument, UITheme.ROCK_RED)

func _update_difficulty_highlight() -> void:
	_restyle_chip_group(_launch_diff_btns, _launch_selected_difficulty, UITheme.ROCK_RED)

func _update_preset_highlight() -> void:
	_restyle_chip_group(_launch_preset_btns, _launch_selected_preset, UITheme.ROCK_RED)

func _update_mode_highlight() -> void:
	_restyle_chip_group(_launch_mode_btns, _launch_selected_mode, UITheme.ROCK_RED)

func _update_view_highlight() -> void:
	_restyle_chip_group(_launch_view_btns, Settings.highway_style, UITheme.ROCK_RED)

func _update_vfx_quality_highlight() -> void:
	_restyle_chip_group(_launch_vfx_btns, Settings.vfx_quality, UITheme.ROCK_RED)

func _update_rock_meter_highlight() -> void:
	_restyle_chip_group(_launch_rock_meter_btns, Settings.rock_meter_mode, UITheme.ROCK_RED)

func _update_crowd_audio_highlight() -> void:
	_restyle_chip_group(
		_launch_crowd_btns,
		"on" if Settings.crowd_audio_enabled else "off",
		UITheme.ROCK_RED)

func _update_miss_sfx_highlight() -> void:
	_restyle_chip_group(
		_launch_miss_sfx_btns,
		"on" if Settings.miss_sfx_enabled else "off",
		UITheme.ROCK_RED)

func _on_view_selected(view_key: String) -> void:
	Settings.highway_style = view_key
	Settings.save_settings()
	_update_view_highlight()

func _on_vfx_quality_selected(quality_key: String) -> void:
	Settings.vfx_quality = quality_key
	Settings.save_settings()
	_update_vfx_quality_highlight()

func _on_rock_meter_selected(rock_mode: String) -> void:
	Settings.rock_meter_mode = rock_mode
	Settings.save_settings()
	_update_rock_meter_highlight()

func _on_crowd_audio_selected(crowd_mode: String) -> void:
	Settings.crowd_audio_enabled = crowd_mode == "on"
	Settings.save_settings()
	_update_crowd_audio_highlight()

func _on_miss_sfx_selected(miss_sfx_mode: String) -> void:
	Settings.miss_sfx_enabled = miss_sfx_mode == "on"
	Settings.save_settings()
	_update_miss_sfx_highlight()

func _on_preset_selected(preset: String) -> void:
	_launch_selected_preset = preset
	_update_preset_highlight()

func _on_mode_selected(mode_key: String) -> void:
	_launch_selected_mode = mode_key
	_update_mode_highlight()

func _update_launch_star() -> void:
	if not _launch_star_label:
		return
	var song: Dictionary = found_songs[_launch_song_index]
	var score_key := _make_score_key(song, _launch_selected_instrument, _launch_selected_difficulty, "")
	# Check all presets for best score on this instrument+difficulty
	var best_stars := 0
	var best_score := 0
	for preset in PlayabilityScript.PRESET_ORDER:
		var key := _make_score_key(song, _launch_selected_instrument, _launch_selected_difficulty, preset)
		if saved_scores.has(key):
			var s: int = int(saved_scores[key].get("stars", 0))
			var sc: int = int(saved_scores[key].get("score", 0))
			if s > best_stars:
				best_stars = s
			if sc > best_score:
				best_score = sc
	if best_stars > 0:
		var star_str := ""
		for si in range(5):
			star_str += "★" if si < best_stars else "☆"
		_launch_star_label.text = "%s  %s: %d" % [star_str, I18n.t("best"), best_score]
	else:
		_launch_star_label.text = ""

func _make_score_key(song: Dictionary, instrument: String, difficulty: String, preset: String) -> String:
	var song_hash: String = String(song["path"]).md5_text()
	return "%s_%s_%s_%s" % [song_hash, instrument, difficulty, preset]

func _on_launch_approach_changed(val: float) -> void:
	Settings.approach_time_sec = val
	if _launch_approach_label:
		_launch_approach_label.text = "%.1f" % val
	Settings.save_settings()

func _on_launch_start() -> void:
	if _launch_song_index < 0 or _launch_song_index >= found_songs.size():
		return
	var song: Dictionary = found_songs[_launch_song_index]

	GameScript.song_source = song["path"]
	GameScript.song_difficulty = _launch_selected_difficulty
	GameScript.song_instrument = _launch_selected_instrument
	GameScript.song_available_instruments = _launch_instruments.duplicate(true)
	GameScript.song_mode = _launch_selected_mode
	GameScript.song_preset = _launch_selected_preset

	get_tree().change_scene_to_file("res://scenes/game.tscn")

# =====================================================================
#  SONG IMPORT
# =====================================================================

func _on_import_pressed() -> void:
	if OS.get_name() == "Android" and Engine.has_singleton("NativeAudioDecoder"):
		# Use plugin file picker — bypasses Samsung's file type restrictions
		var plugin = Engine.get_singleton("NativeAudioDecoder")
		if not plugin.is_connected("files_picked", _on_plugin_files_picked):
			plugin.connect("files_picked", _on_plugin_files_picked)
		_native_picker_context = "songs"
		plugin.call("openFilePicker", I18n.t("file_dialog_title"))
		return

	var filters := PackedStringArray([
		"*.sng ; SNG",
		"*.zip ; ZIP",
		"*.chart ; CHART",
		"*.mid ; MIDI",
		"*.con ; Rock Band CON",
		"*.live ; Rock Band LIVE",
		"* ; %s" % I18n.t("all_files"),
	])
	DisplayServer.file_dialog_show(
		I18n.t("file_dialog_title"),
		"",
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILES,
		filters,
		_on_files_selected
	)

func _on_plugin_files_picked(paths_str: String) -> void:
	var picker_context := _native_picker_context
	_native_picker_context = ""
	if paths_str == "":
		return
	var uris := paths_str.split(";", false)
	print("Import: plugin picker returned %d files" % uris.size())
	if picker_context == "arena_highway":
		_install_arena_highway_from_selected_path(String(uris[0]))
		return
	# Convert to PackedStringArray and use same flow as _on_files_selected
	var selected := PackedStringArray(uris)
	_on_files_selected(true, selected, 0)

func _on_files_selected(status: bool, selected: PackedStringArray, _idx: int) -> void:
	print("Import: callback status=%s, count=%d" % [str(status), selected.size()])
	for i in range(selected.size()):
		print("Import: selected[%d] = %s" % [i, selected[i]])
	if not status or selected.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(USER_SONGS_DIR)
	var imported := 0
	for path in selected:
		var actual_path := path
		# Android: file dialog always returns content:// URIs
		if path.begins_with("content://"):
			actual_path = _resolve_content_uri(path)
			if actual_path == "":
				print("Import: content URI resolve failed: %s" % path)
				continue
		elif OS.get_name() == "Android" and not FileAccess.file_exists(path):
			# Some devices return paths without content:// but still need resolution
			print("Import: file not accessible directly, trying as content URI: %s" % path)
			actual_path = _resolve_content_uri(path)
			if actual_path == "":
				continue
		var ok := _import_file(actual_path)
		print("Import: _import_file(%s) = %s" % [actual_path, str(ok)])
		if ok:
			imported += 1
		else:
			# Clean up temp file only if import didn't start (threaded imports clean up themselves)
			if path.begins_with("content://") and actual_path != "" and FileAccess.file_exists(actual_path):
				DirAccess.remove_absolute(actual_path)
	if _import_in_progress or (_import_thread != null and _import_thread.is_started()):
		# Async import (Android decode or PC threaded CON) — scan will happen when done
		return
	if imported > 0:
		_show_import_status(I18n.t("songs_added", [imported]))
		_scan_songs(true)
	else:
		_show_import_status(I18n.t("unsupported_file"))

func _resolve_content_uri(uri: String) -> String:
	if not Engine.has_singleton("NativeAudioDecoder"):
		push_error("Import: NativeAudioDecoder not available for content URI")
		return ""
	var plugin = Engine.get_singleton("NativeAudioDecoder")
	# Copy to a temp location, get original filename
	var temp_dir := OS.get_cache_dir().path_join("import_temp")
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var temp_file := temp_dir.path_join("import_temp_file")
	print("Import: copying content URI: %s → %s" % [uri, temp_file])
	var display_name: String = plugin.call("copyContentUri", uri, temp_file)
	print("Import: copyContentUri returned display_name='%s'" % display_name)
	if not FileAccess.file_exists(temp_file):
		print("Import: temp file does not exist after copy!")
		return ""
	var file_size := FileAccess.open(temp_file, FileAccess.READ).get_length()
	print("Import: temp file size = %d bytes" % file_size)
	if file_size == 0:
		DirAccess.remove_absolute(temp_file)
		return ""
	# If display_name is empty, use a fallback name
	if display_name == "":
		display_name = "imported_file"
	# Rename temp file with the correct name from display name
	var final_path := temp_dir.path_join(display_name)
	if final_path == temp_file:
		return final_path
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	var err := DirAccess.rename_absolute(temp_file, final_path)
	if err != OK:
		print("Import: rename failed (err=%d), using temp_file directly" % err)
		return temp_file
	print("Import: resolved content URI → %s (%s)" % [final_path, display_name])
	return final_path

func _import_file(path: String) -> bool:
	var fl := path.to_lower()
	# Check STFS magic first (CON/LIVE files often have no extension on Android)
	if _is_stfs_by_magic(path):
		print("Import: detected STFS magic in %s" % path)
		_import_con_threaded(path)
		return true
	if fl.ends_with(".zip"):
		return _import_zip(path)
	elif fl.ends_with(".sng"):
		return _copy_file_to_songs(path, path.get_file())
	elif fl.ends_with(".chart") or fl.ends_with(".mid"):
		return _import_chart_folder(path)
	elif fl.ends_with(".con") or fl.ends_with(".live"):
		_import_con_threaded(path)
		return true
	print("Import: unrecognized format — %s (size=%d)" % [path, FileAccess.open(path, FileAccess.READ).get_length() if FileAccess.file_exists(path) else -1])
	return false

func _is_stfs_by_magic(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("Import: _is_stfs_by_magic — cannot open: %s (error=%d)" % [path, FileAccess.get_open_error()])
		return false
	if f.get_length() < 4:
		f.close()
		return false
	var magic := f.get_buffer(4).get_string_from_ascii()
	f.close()
	return magic == "CON " or magic == "LIVE" or magic == "PIRS"

func _copy_file_to_songs(src_path: String, dest_name: String) -> bool:
	var dest := USER_SONGS_DIR.path_join(dest_name)
	if FileAccess.file_exists(dest):
		print("Import: already exists — %s" % dest_name)
		return true  # already imported
	var src := FileAccess.open(src_path, FileAccess.READ)
	if src == null:
		push_error("Import: cannot read %s" % src_path)
		return false
	var data := src.get_buffer(src.get_length())
	src.close()
	var dst := FileAccess.open(dest, FileAccess.WRITE)
	if dst == null:
		push_error("Import: cannot write %s" % dest)
		return false
	dst.store_buffer(data)
	dst.close()
	print("Import: copied %s (%d bytes)" % [dest_name, data.size()])
	return true

func _import_chart_folder(chart_path: String) -> bool:
	# Copy chart + all siblings (audio, album art) to a subfolder in user://songs/
	var src_dir := chart_path.get_base_dir()
	var folder_name := chart_path.get_file().get_basename()
	# Use parent folder name if it looks like a song name (has " - ")
	var parent := src_dir.get_file()
	if parent.find(" - ") > 0:
		folder_name = parent
	var dest_dir := USER_SONGS_DIR.path_join(folder_name)
	DirAccess.make_dir_recursive_absolute(dest_dir)

	var dir := DirAccess.open(src_dir)
	if dir == null:
		push_error("Import: cannot open source dir %s" % src_dir)
		return false
	var copied := 0
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var fl := fname.to_lower()
			if fl.ends_with(".chart") or fl.ends_with(".mid") or fl.ends_with(".ini") \
				or fl.ends_with(".opus") or fl.ends_with(".ogg") or fl.ends_with(".mp3") \
				or fl.ends_with(".wav") or fl.ends_with(".jpg") or fl.ends_with(".png"):
				var src := FileAccess.open(src_dir.path_join(fname), FileAccess.READ)
				if src:
					var data := src.get_buffer(src.get_length())
					src.close()
					var dst := FileAccess.open(dest_dir.path_join(fname), FileAccess.WRITE)
					if dst:
						dst.store_buffer(data)
						dst.close()
						copied += 1
		fname = dir.get_next()
	dir.list_dir_end()
	print("Import: chart folder — copied %d files to %s" % [copied, folder_name])
	return copied > 0

func _import_con_threaded(con_path: String) -> void:
	_show_import_status(I18n.t("importing"))
	if _import_thread != null:
		if _import_thread.is_started():
			_import_thread.wait_to_finish()
		_import_thread = null
	_import_thread = Thread.new()
	_import_thread.start(_import_con_thread_func.bind(con_path))

func _import_con_thread_func(con_path: String) -> void:
	var success := _import_con(con_path)
	# Clean up temp file from content URI copy (thread-safe: file ops are OK)
	if con_path.begins_with(OS.get_cache_dir()):
		DirAccess.remove_absolute(con_path)
	call_deferred("_on_con_import_finished", success)

func _on_con_import_finished(success: bool) -> void:
	if _import_thread != null:
		if _import_thread.is_started():
			_import_thread.wait_to_finish()
		_import_thread = null
	if success:
		_show_import_status(I18n.t("song_added"))
		_scan_songs(true)
	else:
		_show_import_status(I18n.t("import_failed"))

func _import_con(con_path: String) -> bool:
	print("Import: parsing CON/LIVE — %s" % con_path)
	var stfs := StfsParserScript.new()
	if not stfs.load_stfs(con_path):
		push_error("Import: STFS parse failed")
		return false

	# Parse DTA for song name
	var dta_text := stfs.get_dta_text()
	var folder_name := con_path.get_file().get_basename()
	if dta_text != "":
		var dta := DtaParserScript.new()
		if dta.parse(dta_text):
			if dta.artist != "" and dta.song_name != "":
				folder_name = "%s - %s" % [dta.artist, dta.song_name]
			elif dta.song_name != "":
				folder_name = dta.song_name
			dta.print_summary()

	# Clean folder name
	folder_name = folder_name.replace("/", "_").replace("\\", "_").replace(":", "_")
	var dest_dir := USER_SONGS_DIR.path_join(folder_name)
	DirAccess.make_dir_recursive_absolute(dest_dir)

	var saved := 0

	# Save MIDI
	var midi_data := stfs.get_midi_data()
	if midi_data.size() > 0:
		var mid_path := dest_dir.path_join("notes.mid")
		var f := FileAccess.open(mid_path, FileAccess.WRITE)
		if f:
			f.store_buffer(midi_data)
			f.close()
			saved += 1
			print("Import: saved notes.mid (%d bytes)" % midi_data.size())

	# Extract OGG from MOGG and convert to stereo
	var mogg_data := stfs.get_mogg_data()
	if mogg_data.size() > 0:
		var mogg := MoggHandlerScript.new()
		var raw_ogg_path := dest_dir.path_join("_raw_mogg.ogg")
		if mogg.save_ogg_to_file(mogg_data, raw_ogg_path):
			# Convert multi-channel OGG to stereo
			var stereo_path := dest_dir.path_join("song.ogg")
			var convert_ok := _convert_mogg_to_stereo(raw_ogg_path, stereo_path)
			if convert_ok:
				if OS.has_feature("android"):
					# Async path: conversion started on worker thread
					# _on_import_decode_done will handle cleanup + scan
					saved += 1  # count audio as saved (will appear after decode)
				else:
					saved += 1
					DirAccess.remove_absolute(raw_ogg_path)
			else:
				# Fallback: keep raw OGG, desktop ffmpeg will handle during playback
				DirAccess.rename_absolute(raw_ogg_path, stereo_path)
				saved += 1
				print("Import: kept raw multi-channel OGG (will convert during playback)")
		else:
			if mogg.is_encrypted:
				print("Import: MOGG decryption failed")
			else:
				print("Import: mogg.save_ogg_to_file failed (OGG extract issue)")
			return false

	# Save DTA for reference
	if dta_text != "":
		var dta_path := dest_dir.path_join("songs.dta")
		var f := FileAccess.open(dta_path, FileAccess.WRITE)
		if f:
			f.store_string(dta_text)
			f.close()

	# Save album art — only save standard formats (skip Xbox DXT textures)
	var art_data := stfs.get_album_art_data()
	if art_data.size() >= 4:
		var is_jpeg := (art_data[0] == 0xFF and art_data[1] == 0xD8)
		var is_png := (art_data[0] == 0x89 and art_data[1] == 0x50 and art_data[2] == 0x4E and art_data[3] == 0x47)
		if is_jpeg or is_png:
			var ext := ".jpg" if is_jpeg else ".png"
			var art_path := dest_dir.path_join("album" + ext)
			var f := FileAccess.open(art_path, FileAccess.WRITE)
			if f:
				f.store_buffer(art_data)
				f.close()
				print("Import: saved album art (%d bytes)" % art_data.size())
		else:
			print("Import: skipped Xbox texture album art (unsupported format)")

	print("Import: CON extracted to %s (%d files)" % [folder_name, saved])
	# On Android with async decode, return true even if only MIDI is saved so far
	if OS.has_feature("android") and _import_in_progress:
		return saved >= 1  # MIDI saved, audio is being decoded async
	return saved >= 2  # Need at least MIDI + audio

func _convert_mogg_to_stereo(input_ogg: String, output_path: String) -> bool:
	var os_input := ProjectSettings.globalize_path(input_ogg)
	var os_output := ProjectSettings.globalize_path(output_path)

	if OS.has_feature("android"):
		# Android: use async decodeAndMix (worker thread) — NEVER block render thread
		if not Engine.has_singleton("NativeAudioDecoder"):
			return false
		var plugin = Engine.get_singleton("NativeAudioDecoder")
		var wav_output := output_path.get_base_dir().path_join("song.wav")
		var os_wav := ProjectSettings.globalize_path(wav_output)
		# Store state for async completion
		_import_pending_raw_ogg = input_ogg
		_import_pending_folder = output_path.get_base_dir()
		_import_in_progress = true
		_import_decode_plugin = plugin
		# Connect signals + start decode on main thread via deferred
		call_deferred("_start_android_decode", plugin, os_input, os_wav)
		return true  # async — will complete via signal
	else:
		# PC: use ffmpeg (fast enough to not block)
		var probe_output: Array = []
		OS.execute("ffprobe", [
			"-v", "error", "-select_streams", "a:0",
			"-show_entries", "stream=channels",
			"-of", "csv=p=0", os_input
		], probe_output, true)
		var ch_count := 2
		if probe_output.size() > 0:
			ch_count = maxi(int(str(probe_output[0]).strip_edges()), 1)

		var args: Array = ["-hide_banner", "-i", os_input]
		if ch_count > 2:
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
			args.append_array(["-af", "pan=stereo|c0=%s|c1=%s" % [left, right]])
		args.append_array(["-ac", "2", "-c:a", "libvorbis", "-q:a", "6", "-y", os_output])

		print("Import: ffmpeg stereo convert: %d channels" % ch_count)
		var cmd_output: Array = []
		var code := OS.execute("ffmpeg", args, cmd_output, true)
		if code != 0:
			print("Import: ffmpeg stereo convert failed (exit %d)" % code)
			for line in cmd_output:
				print("  ffmpeg: %s" % str(line))
			return false
		print("Import: converted to stereo OGG")
		return true

func _on_import_decode_progress(pct: int, stage: String) -> void:
	if _import_progress_label:
		_import_progress_label.text = "%s  %%%d" % [I18n.decode_stage(stage), pct]
	if _import_progress_bar:
		_import_progress_bar.value = pct
		_import_progress_bar.visible = true

func _start_android_decode(plugin, os_input: String, os_wav: String) -> void:
	if not plugin.is_connected("decode_progress", _on_import_decode_progress):
		plugin.connect("decode_progress", _on_import_decode_progress)
	if not plugin.is_connected("decode_done", _on_import_decode_done):
		plugin.connect("decode_done", _on_import_decode_done)
	if not plugin.is_connected("decode_failed", _on_import_decode_failed):
		plugin.connect("decode_failed", _on_import_decode_failed)
	plugin.call("decodeAndMix", [os_input], os_wav)
	_show_import_progress(I18n.t("importing"))

func _on_import_decode_done(_wav_path: String) -> void:
	print("Import: async stereo conversion done — %s" % _wav_path)
	# Remove raw multi-ch OGG
	if _import_pending_raw_ogg != "" and FileAccess.file_exists(_import_pending_raw_ogg):
		DirAccess.remove_absolute(_import_pending_raw_ogg)
	_import_in_progress = false
	_disconnect_import_signals()
	_hide_import_progress()
	_show_import_status(I18n.t("song_added"))
	_scan_songs(true)

func _on_import_decode_failed(error: String) -> void:
	print("Import: async stereo conversion failed — %s" % error)
	_import_in_progress = false
	_disconnect_import_signals()
	_hide_import_progress()
	if error != "Cancelled":
		_show_import_status(I18n.t("convert_error", [error]))

func _disconnect_import_signals() -> void:
	if _import_decode_plugin == null:
		return
	if _import_decode_plugin.is_connected("decode_progress", _on_import_decode_progress):
		_import_decode_plugin.disconnect("decode_progress", _on_import_decode_progress)
	if _import_decode_plugin.is_connected("decode_done", _on_import_decode_done):
		_import_decode_plugin.disconnect("decode_done", _on_import_decode_done)
	if _import_decode_plugin.is_connected("decode_failed", _on_import_decode_failed):
		_import_decode_plugin.disconnect("decode_failed", _on_import_decode_failed)
	_import_decode_plugin = null

func _show_import_progress(text: String) -> void:
	var status_parent: Container = _main_actions_container \
		if is_instance_valid(_main_actions_container) else card_container
	if _import_progress_label == null:
		_import_progress_label = Label.new()
		_import_progress_label.add_theme_font_size_override("font_size", _fs(20))
		_import_progress_label.add_theme_color_override("font_color", ACCENT)
		_import_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_parent.add_child(_import_progress_label)
	if _import_progress_bar == null:
		_import_progress_bar = ProgressBar.new()
		_import_progress_bar.show_percentage = false
		_import_progress_bar.max_value = 100
		_import_progress_bar.custom_minimum_size = Vector2(0, _u(18))
		_import_progress_bar.visible = false
		status_parent.add_child(_import_progress_bar)
	_import_progress_label.text = text
	_import_progress_label.visible = true

func _hide_import_progress() -> void:
	if _import_progress_label:
		_import_progress_label.visible = false
	if _import_progress_bar:
		_import_progress_bar.visible = false

func _import_zip(zip_path: String) -> bool:
	var reader := ZIPReader.new()
	var err := reader.open(zip_path)
	if err != OK:
		push_error("Import: cannot open ZIP %s (err=%d)" % [zip_path, err])
		return false
	var files := reader.get_files()
	if files.is_empty():
		reader.close()
		return false

	# Determine target folder name from zip filename
	var zip_name := zip_path.get_file().get_basename()

	# Find chart/mid/sng files in the zip to understand structure
	var chart_files: Array[String] = []
	var sng_files: Array[String] = []
	for f in files:
		var fl: String = (f as String).to_lower()
		if fl.ends_with(".chart") or fl.ends_with(".mid"):
			chart_files.append(f)
		elif fl.ends_with(".sng"):
			sng_files.append(f)

	if chart_files.is_empty() and sng_files.is_empty():
		reader.close()
		push_error("Import: ZIP has no chart/mid/sng files")
		return false

	var imported := false

	# Case 1: ZIP contains .sng files — extract them directly
	for sng_f in sng_files:
		var fname: String = sng_f.get_file()
		var data := reader.read_file(sng_f)
		if data.size() > 0:
			var dest := USER_SONGS_DIR.path_join(fname)
			var dst := FileAccess.open(dest, FileAccess.WRITE)
			if dst:
				dst.store_buffer(data)
				dst.close()
				print("Import: extracted sng — %s" % fname)
				imported = true

	# Case 2: ZIP contains chart/mid + audio — extract all relevant files
	if chart_files.size() > 0:
		# Find common root directory in zip
		var root_prefix := ""
		var first_chart: String = chart_files[0]
		if first_chart.contains("/"):
			root_prefix = first_chart.substr(0, first_chart.rfind("/") + 1)

		# Determine folder name from zip structure
		var folder_name := zip_name
		if root_prefix != "" and root_prefix.get_slice("/", 0) != "":
			folder_name = root_prefix.get_slice("/", 0)

		var dest_dir := USER_SONGS_DIR.path_join(folder_name)
		DirAccess.make_dir_recursive_absolute(dest_dir)

		var extracted := 0
		for f in files:
			var fl: String = (f as String).to_lower()
			var fname: String = (f as String).get_file()
			if fname == "" or fname.begins_with("."):
				continue
			# Extract relevant file types
			if fl.ends_with(".chart") or fl.ends_with(".mid") or fl.ends_with(".ini") \
				or fl.ends_with(".opus") or fl.ends_with(".ogg") or fl.ends_with(".mp3") \
				or fl.ends_with(".wav") or fl.ends_with(".jpg") or fl.ends_with(".png") \
				or fl.ends_with(".sng"):
				var data := reader.read_file(f)
				if data.size() > 0:
					var dest := dest_dir.path_join(fname)
					var dst := FileAccess.open(dest, FileAccess.WRITE)
					if dst:
						dst.store_buffer(data)
						dst.close()
						extracted += 1
		print("Import: ZIP extracted %d files to %s" % [extracted, folder_name])
		imported = extracted > 0

	reader.close()
	return imported

func _show_import_status(text: String) -> void:
	if _import_status_label:
		_import_status_label.text = text
		_import_status_label.visible = true
		# Auto-hide after 3 seconds
		var tw := create_tween()
		tw.tween_interval(3.0)
		tw.tween_callback(func():
			if _import_status_label:
				_import_status_label.visible = false
		)
