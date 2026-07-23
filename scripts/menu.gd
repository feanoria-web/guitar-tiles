extends Control

const GameScript = preload("res://scripts/game.gd")
const ChartParserScript = preload("res://scripts/chart_parser.gd")
const MidiParserScript = preload("res://scripts/midi_parser.gd")
const SngLoaderScript = preload("res://scripts/sng_loader.gd")
const StfsParserScript = preload("res://scripts/stfs_parser.gd")
const DtaParserScript = preload("res://scripts/dta_parser.gd")
const MoggHandlerScript = preload("res://scripts/mogg_handler.gd")
const PlayabilityScript = preload("res://scripts/playability.gd")

const BG_COLOR := UITheme.BG_BOTTOM
const ACCENT := UITheme.NEON_CYAN
const CARD_BG := UITheme.CARD_BG
const CARD_SELECTED := Color(0.15, 0.22, 0.38)
const TEXT_DIM := UITheme.TEXT_DIM
const TEXT_BRIGHT := UITheme.TEXT_BRIGHT
const STAR_COLOR := UITheme.NEON_GOLD

var card_container: VBoxContainer
var found_songs: Array = []
var card_panels: Array = []
var saved_scores: Dictionary = {}

const USER_SONGS_DIR := "user://songs"
const HIDDEN_BUNDLED_SONG_PATHS := ["res://notes.chart"]
const MIX_CACHE_DIR := "user://cache"
const THUMB_CACHE_DIR := "user://menu_thumbnails"
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

var _menu_loading_label: Label = null
var _menu_loading_layer: CanvasLayer = null
var _menu_loading_bar: ProgressBar = null
var _scan_generation: int = 0
var _ui_scale: float = 1.0

func _ready() -> void:
	Settings.load_settings()
	_ui_scale = _detect_ui_scale()
	print("Menu UI: scale=%.2f dpi=%d viewport=%s" % [
		_ui_scale, DisplayServer.screen_get_dpi(), str(get_viewport_rect().size)])
	_load_scores()
	_build_ui()
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

func _section_label(text: String) -> Label:
	var label := UITheme.section_label(text)
	label.add_theme_font_size_override("font_size", _fs(15))
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
	UITheme.add_neon_background(bg, 2)

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
	return theme

func _build_ui() -> void:
	UITheme.add_neon_background(self)

	var theme := _create_theme()

	# Safe area
	var sa := UITheme.safe_insets(self)

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", int(sa["l"] + _u(16)))
	root.add_theme_constant_override("margin_right", int(sa["r"] + _u(16)))
	root.add_theme_constant_override("margin_top", int(sa["t"] + _u(12)))
	root.add_theme_constant_override("margin_bottom", int(sa["b"] + _u(10)))
	root.theme = theme
	add_child(root)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", int(_u(12)))
	root.add_child(main_vbox)

	# --- Header: neon title + language toggle ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", int(_u(12)))
	main_vbox.add_child(header)

	var title := Label.new()
	title.text = I18n.t("app_title")
	title.add_theme_font_size_override("font_size", _fs(36))
	title.add_theme_color_override("font_color", ACCENT.lightened(0.35))
	title.add_theme_color_override("font_shadow_color", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_constant_override("shadow_outline_size", int(_u(14)))
	if UITheme.font_bold():
		title.add_theme_font_override("font", UITheme.font_bold())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var help_btn := Button.new()
	help_btn.text = "?"
	help_btn.tooltip_text = I18n.t("song_tutorial_title")
	UITheme.style_ghost_button(help_btn, _fs(22))
	help_btn.custom_minimum_size = Vector2(_u(52), _u(52))
	help_btn.pressed.connect(_open_song_tutorial)
	header.add_child(help_btn)

	var lang_btn := Button.new()
	lang_btn.text = "TR" if Settings.language == "tr" else "EN"
	UITheme.style_ghost_button(lang_btn, _fs(18))
	lang_btn.custom_minimum_size = Vector2(_u(60), _u(52))
	lang_btn.pressed.connect(_on_language_toggle)
	header.add_child(lang_btn)

	# Subtle accent divider under header
	var divider := ColorRect.new()
	divider.color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.25)
	divider.custom_minimum_size = Vector2(0, _u(2))
	main_vbox.add_child(divider)

	# --- Song cards scroll area ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = int(_u(14))
	main_vbox.add_child(scroll)

	card_container = VBoxContainer.new()
	card_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_container.add_theme_constant_override("separation", int(_u(16)))
	scroll.add_child(card_container)

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
	shade.color = Color(0.01, 0.005, 0.03, 0.92)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_tutorial_overlay.add_child(shade)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.05
	panel.anchor_top = 0.04
	panel.anchor_right = 0.95
	panel.anchor_bottom = 0.96
	var panel_style := UITheme.glow_style(UITheme.PANEL_BG, UITheme.NEON_PURPLE, 20, 12)
	panel_style.content_margin_left = _u(18)
	panel_style.content_margin_right = _u(18)
	panel_style.content_margin_top = _u(18)
	panel_style.content_margin_bottom = _u(18)
	panel.add_theme_stylebox_override("panel", panel_style)
	_tutorial_overlay.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", int(_u(12)))
	panel.add_child(layout)

	var heading_row := HBoxContainer.new()
	heading_row.add_theme_constant_override("separation", int(_u(10)))
	layout.add_child(heading_row)

	var heading := Label.new()
	heading.text = title_text
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", _fs(28))
	heading.add_theme_color_override("font_color", UITheme.NEON_CYAN.lightened(0.25))
	if UITheme.font_bold():
		heading.add_theme_font_override("font", UITheme.font_bold())
	heading_row.add_child(heading)

	var close_icon := Button.new()
	close_icon.text = "×"
	close_icon.custom_minimum_size = Vector2(_u(48), _u(48))
	UITheme.style_ghost_button(close_icon, _fs(24))
	close_icon.pressed.connect(_close_song_tutorial)
	heading_row.add_child(close_icon)

	var intro := Label.new()
	intro.text = intro_text
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", _fs(18))
	intro.add_theme_color_override("font_color", TEXT_DIM)
	layout.add_child(intro)

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
		I18n.t("song_tutorial_step_1_body"), UITheme.NEON_CYAN)

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
		I18n.t("song_tutorial_step_2_body"), UITheme.NEON_MAGENTA)
	_add_tutorial_step(steps, "3", I18n.t("song_tutorial_step_3"),
		I18n.t("song_tutorial_step_3_body"), UITheme.NEON_PURPLE)
	_add_tutorial_step(steps, "4", I18n.t("song_tutorial_step_4"),
		I18n.t("song_tutorial_step_4_body"), UITheme.NEON_GREEN)

	var formats := Label.new()
	formats.text = I18n.t("song_tutorial_formats")
	formats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	formats.add_theme_font_size_override("font_size", _fs(16))
	formats.add_theme_color_override("font_color", UITheme.NEON_GOLD)
	steps.add_child(formats)

	var legal := Label.new()
	legal.text = I18n.t("song_tutorial_legal")
	legal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legal.add_theme_font_size_override("font_size", _fs(14))
	legal.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	steps.add_child(legal)

	_finish_tutorial(layout)

func _open_game_settings_tutorial() -> void:
	var shell := _create_tutorial_shell(
		I18n.t("settings_tutorial_title"), I18n.t("settings_tutorial_intro"))
	if shell.is_empty():
		return
	var layout: VBoxContainer = shell["layout"]
	var steps: VBoxContainer = shell["steps"]

	_add_tutorial_step(steps, "1", I18n.t("settings_help_track"),
		I18n.t("settings_help_track_body"), UITheme.NEON_CYAN)
	_add_tutorial_step(steps, "2", I18n.t("settings_help_gameplay"),
		I18n.t("settings_help_gameplay_body"), UITheme.NEON_MAGENTA)
	_add_tutorial_step(steps, "3", I18n.t("settings_help_mode"),
		I18n.t("settings_help_mode_body"), UITheme.NEON_PURPLE)
	_add_tutorial_step(steps, "4", I18n.t("settings_help_view"),
		I18n.t("settings_help_view_body"), UITheme.NEON_GREEN)
	_add_tutorial_step(steps, "5", I18n.t("settings_help_vfx"),
		I18n.t("settings_help_vfx_body"), UITheme.NEON_GOLD)
	_add_tutorial_step(steps, "6", I18n.t("settings_help_rock"),
		I18n.t("settings_help_rock_body"), UITheme.NEON_RED)
	_add_tutorial_step(steps, "7", I18n.t("settings_help_audio"),
		I18n.t("settings_help_audio_body"), UITheme.NEON_CYAN)
	_add_tutorial_step(steps, "8", I18n.t("settings_help_speed"),
		I18n.t("settings_help_speed_body"), UITheme.NEON_PURPLE)

	_finish_tutorial(layout)

func _finish_tutorial(layout: VBoxContainer) -> void:
	var done_btn := Button.new()
	done_btn.text = I18n.t("song_tutorial_close")
	done_btn.custom_minimum_size = Vector2(0, _u(58))
	UITheme.style_primary_button(done_btn, UITheme.NEON_CYAN, _fs(19))
	done_btn.pressed.connect(_close_song_tutorial)
	layout.add_child(done_btn)

	_tutorial_overlay.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_tutorial_overlay, "modulate:a", 1.0, 0.18)

func _add_tutorial_step(parent: VBoxContainer, number: String, title: String,
		body: String, accent: Color) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.card_style(accent))
	parent.add_child(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", int(_u(5)))
	card.add_child(content)

	var step_title := Label.new()
	step_title.text = "%s  %s" % [number, title]
	step_title.add_theme_font_size_override("font_size", _fs(19))
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

# Neon accents cycled across song cards
const CARD_ACCENTS := [UITheme.NEON_CYAN, UITheme.NEON_MAGENTA, UITheme.NEON_PURPLE, UITheme.NEON_GREEN]

func _create_song_card(index: int, song: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var parsed := _parse_song_name(song["display_name"])
	var accent: Color = CARD_ACCENTS[index % CARD_ACCENTS.size()]

	# Magic Tiles style: oversized artwork-first card with a large touch target.
	var card_style := UITheme.card_style(accent)
	card_style.bg_color = UITheme.CARD_BG.lerp(accent, 0.09)
	card_style.set_corner_radius_all(int(_u(22)))
	card_style.border_width_left = int(_u(6))
	card_style.content_margin_left = _u(16); card_style.content_margin_right = _u(18)
	card_style.content_margin_top = _u(14); card_style.content_margin_bottom = _u(14)
	panel.add_theme_stylebox_override("panel", card_style)
	panel.custom_minimum_size = Vector2(0, _u(176))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", int(_u(18)))
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	# Album art thumbnail (placeholder now, lazy-loaded after scan)
	var thumb := PanelContainer.new()
	var thumb_style := UITheme.glow_style(Color(0.14, 0.13, 0.24), accent, int(_u(16)), int(_u(7)))
	thumb_style.content_margin_left = 0; thumb_style.content_margin_right = 0
	thumb_style.content_margin_top = 0; thumb_style.content_margin_bottom = 0
	thumb.add_theme_stylebox_override("panel", thumb_style)
	thumb.custom_minimum_size = Vector2(_u(144), _u(144))
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(thumb)

	var thumb_icon := Label.new()
	thumb_icon.text = "♪"
	thumb_icon.add_theme_font_size_override("font_size", _fs(58))
	thumb_icon.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.5))
	thumb_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thumb_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	thumb.add_child(thumb_icon)
	_art_pending.append({"index": index, "holder": thumb})

	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_vbox.add_theme_constant_override("separation", int(_u(7)))
	text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_vbox)

	var title_lbl := Label.new()
	title_lbl.text = parsed["title"]
	title_lbl.add_theme_font_size_override("font_size", _fs(30))
	title_lbl.add_theme_color_override("font_color", TEXT_BRIGHT)
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if UITheme.font_bold():
		title_lbl.add_theme_font_override("font", UITheme.font_bold())
	text_vbox.add_child(title_lbl)

	if parsed["artist"] != "":
		var artist_lbl := Label.new()
		artist_lbl.text = parsed["artist"]
		artist_lbl.add_theme_font_size_override("font_size", _fs(20))
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

	# Play button circle — Magic Tiles style
	var play_circle := Label.new()
	play_circle.text = "▶"
	play_circle.add_theme_font_size_override("font_size", _fs(36))
	play_circle.add_theme_color_override("font_color", accent.lightened(0.25))
	play_circle.add_theme_color_override("font_shadow_color", Color(accent.r, accent.g, accent.b, 0.45))
	play_circle.add_theme_constant_override("shadow_offset_x", 0)
	play_circle.add_theme_constant_override("shadow_offset_y", 0)
	play_circle.add_theme_constant_override("shadow_outline_size", int(_u(12)))
	play_circle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(play_circle)

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

	# Import button at end of list
	_add_import_button()

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

func _add_import_button() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, _u(10))
	card_container.add_child(spacer)

	var import_btn := Button.new()
	import_btn.text = I18n.t("add_song")
	UITheme.style_primary_button(import_btn, UITheme.NEON_PURPLE, _fs(23))
	import_btn.custom_minimum_size = Vector2(0, _u(68))
	import_btn.pressed.connect(_on_import_pressed)
	card_container.add_child(import_btn)

	# Status label (hidden by default)
	_import_status_label = Label.new()
	_import_status_label.text = ""
	_import_status_label.add_theme_font_size_override("font_size", _fs(18))
	_import_status_label.add_theme_color_override("font_color", ACCENT)
	_import_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_import_status_label.visible = false
	card_container.add_child(_import_status_label)

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

	# Background — near-opaque dark with a soft accent glow behind the hero
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.025, 0.07, 0.985)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # block clicks to song list
	_launch_overlay.add_child(bg)

	var hero_glow := UITheme._make_glow_blob(UITheme.NEON_PURPLE, 0.14)
	hero_glow.position = Vector2(get_viewport_rect().size.x * 0.5 - 310, -260)
	_launch_overlay.add_child(hero_glow)

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

	# --- Top bar: Back + Delete ---
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", int(_u(10)))
	vbox.add_child(top_bar)

	var back_btn := Button.new()
	back_btn.text = "‹  " + I18n.t("back")
	UITheme.style_ghost_button(back_btn, _fs(19))
	back_btn.custom_minimum_size = Vector2(_u(118), _u(56))
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back_btn.pressed.connect(_close_launch_screen)
	top_bar.add_child(back_btn)

	# Spacer
	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_spacer)

	var settings_help_btn := Button.new()
	settings_help_btn.text = "?"
	settings_help_btn.tooltip_text = I18n.t("settings_tutorial_title")
	UITheme.style_ghost_button(settings_help_btn, _fs(22))
	settings_help_btn.custom_minimum_size = Vector2(_u(56), _u(56))
	settings_help_btn.pressed.connect(_open_game_settings_tutorial)
	top_bar.add_child(settings_help_btn)

	# Delete button — only for user-imported songs
	if song["path"].begins_with("user://"):
		var del_btn := Button.new()
		del_btn.text = I18n.t("delete")
		UITheme.style_danger_button(del_btn, _fs(19))
		del_btn.custom_minimum_size = Vector2(_u(90), _u(56))
		del_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
		del_btn.pressed.connect(_on_delete_song)
		top_bar.add_child(del_btn)

	# --- Hero: album art + title/artist ---
	var info_hbox := HBoxContainer.new()
	info_hbox.add_theme_constant_override("separation", int(_u(20)))
	vbox.add_child(info_hbox)

	var art_texture := _load_album_art(song)
	if art_texture:
		var art_frame := PanelContainer.new()
		var frame_style := UITheme.glow_style(Color(0, 0, 0, 0), UITheme.NEON_CYAN, int(_u(16)), int(_u(8)))
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
		var art_style := UITheme.flat_style(Color(0.13, 0.12, 0.22), int(_u(16)))
		art_style.border_color = UITheme.CARD_BORDER
		art_style.set_border_width_all(1)
		art_panel.add_theme_stylebox_override("panel", art_style)
		art_panel.custom_minimum_size = Vector2(_u(156), _u(156))
		art_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info_hbox.add_child(art_panel)
		var art_icon := Label.new()
		art_icon.text = "♪"
		art_icon.add_theme_font_size_override("font_size", _fs(64))
		art_icon.add_theme_color_override("font_color", Color(UITheme.NEON_PURPLE.r, UITheme.NEON_PURPLE.g, UITheme.NEON_PURPLE.b, 0.55))
		art_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		art_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		art_panel.add_child(art_icon)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_vbox.add_theme_constant_override("separation", int(_u(6)))
	info_hbox.add_child(info_vbox)

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
			btn.text = I18n.instrument_name(inst_key)
			btn.add_theme_font_size_override("font_size", _fs(19))
			btn.custom_minimum_size = Vector2(0, _u(58))
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
		pbtn.text = I18n.preset_name(preset)
		pbtn.add_theme_font_size_override("font_size", _fs(17))
		pbtn.custom_minimum_size = Vector2(0, _u(56))
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
		mbtn.text = I18n.t("mode_piano") if mode_key == "piano" else I18n.t("mode_guitar")
		mbtn.add_theme_font_size_override("font_size", _fs(18))
		mbtn.custom_minimum_size = Vector2(0, _u(56))
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
		vbtn.text = I18n.t("view_gh") if view_key == "gh" else I18n.t("view_flat")
		vbtn.add_theme_font_size_override("font_size", _fs(18))
		vbtn.custom_minimum_size = Vector2(0, _u(56))
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
		qbtn.text = I18n.t("vfx_" + quality_key)
		qbtn.add_theme_font_size_override("font_size", _fs(16))
		qbtn.custom_minimum_size = Vector2(0, _u(54))
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
		rock_btn.text = I18n.t("rock_meter_" + rock_mode)
		rock_btn.add_theme_font_size_override("font_size", _fs(15))
		rock_btn.custom_minimum_size = Vector2(0, _u(54))
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
		crowd_btn.text = I18n.t("crowd_" + crowd_mode)
		crowd_btn.add_theme_font_size_override("font_size", _fs(17))
		crowd_btn.custom_minimum_size = Vector2(0, _u(54))
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
		miss_sfx_btn.text = I18n.t("miss_sfx_" + miss_sfx_mode)
		miss_sfx_btn.add_theme_font_size_override("font_size", _fs(17))
		miss_sfx_btn.custom_minimum_size = Vector2(0, _u(54))
		miss_sfx_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		miss_sfx_btn.pressed.connect(_on_miss_sfx_selected.bind(miss_sfx_mode))
		miss_sfx_hbox.add_child(miss_sfx_btn)
		_launch_miss_sfx_btns[miss_sfx_mode] = miss_sfx_btn

	# Developer-only assist for device testing. Release exports never show it.
	if OS.is_debug_build():
		var infinite_toggle := CheckButton.new()
		infinite_toggle.text = I18n.t("infinite_overdrive_test")
		infinite_toggle.button_pressed = GameScript.debug_infinite_overdrive
		infinite_toggle.add_theme_font_size_override("font_size", _fs(16))
		infinite_toggle.custom_minimum_size = Vector2(0, _u(54))
		infinite_toggle.toggled.connect(_on_infinite_overdrive_toggled)
		vbox.add_child(infinite_toggle)

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

	# --- START button — big neon green glow ---
	var start_btn := Button.new()
	start_btn.text = I18n.t("start")
	UITheme.style_primary_button(start_btn, UITheme.NEON_GREEN, _fs(28))
	start_btn.custom_minimum_size = Vector2(0, _u(78))
	start_btn.pressed.connect(_on_launch_start)
	vbox.add_child(start_btn)

	# Gentle pulse on the start button
	start_btn.pivot_offset = start_btn.size / 2.0
	start_btn.resized.connect(func(): start_btn.pivot_offset = start_btn.size / 2.0)
	var pulse := create_tween()
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
	var tw := create_tween()
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
		btn.text = I18n.difficulty_name(diff as String)
		btn.add_theme_font_size_override("font_size", _fs(18))
		btn.custom_minimum_size = Vector2(0, _u(56))
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
	_restyle_chip_group(_launch_instrument_btns, _launch_selected_instrument, UITheme.NEON_CYAN)

func _update_difficulty_highlight() -> void:
	_restyle_chip_group(_launch_diff_btns, _launch_selected_difficulty, UITheme.NEON_MAGENTA)

func _update_preset_highlight() -> void:
	_restyle_chip_group(_launch_preset_btns, _launch_selected_preset, UITheme.NEON_PURPLE)

func _update_mode_highlight() -> void:
	_restyle_chip_group(_launch_mode_btns, _launch_selected_mode, UITheme.NEON_CYAN)

func _update_view_highlight() -> void:
	_restyle_chip_group(_launch_view_btns, Settings.highway_style, UITheme.NEON_MAGENTA)

func _update_vfx_quality_highlight() -> void:
	_restyle_chip_group(_launch_vfx_btns, Settings.vfx_quality, UITheme.NEON_GOLD)

func _update_rock_meter_highlight() -> void:
	_restyle_chip_group(_launch_rock_meter_btns, Settings.rock_meter_mode, UITheme.NEON_GREEN)

func _update_crowd_audio_highlight() -> void:
	_restyle_chip_group(_launch_crowd_btns, "on" if Settings.crowd_audio_enabled else "off", UITheme.NEON_CYAN)

func _update_miss_sfx_highlight() -> void:
	_restyle_chip_group(_launch_miss_sfx_btns, "on" if Settings.miss_sfx_enabled else "off", UITheme.NEON_MAGENTA)

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

func _on_infinite_overdrive_toggled(enabled: bool) -> void:
	GameScript.debug_infinite_overdrive = enabled

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
		plugin.call("openFilePicker")
		return

	var filters := PackedStringArray([
		"*.sng ; SNG Sarki Paketi",
		"*.zip ; ZIP Arsiv",
		"*.chart ; Chart Dosyasi",
		"*.mid ; MIDI Dosyasi",
		"*.con ; Rock Band CON",
		"*.live ; Rock Band LIVE",
		"* ; Tum Dosyalar",
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
	if paths_str == "":
		return
	var uris := paths_str.split(";", false)
	print("Import: plugin picker returned %d files" % uris.size())
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
		_import_progress_label.text = "%s %%%d" % [stage, pct]
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
	if _import_progress_label == null:
		_import_progress_label = Label.new()
		_import_progress_label.add_theme_font_size_override("font_size", _fs(20))
		_import_progress_label.add_theme_color_override("font_color", ACCENT)
		_import_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_container.add_child(_import_progress_label)
	if _import_progress_bar == null:
		_import_progress_bar = ProgressBar.new()
		_import_progress_bar.show_percentage = false
		_import_progress_bar.max_value = 100
		_import_progress_bar.custom_minimum_size = Vector2(0, _u(8))
		_import_progress_bar.visible = false
		card_container.add_child(_import_progress_bar)
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
