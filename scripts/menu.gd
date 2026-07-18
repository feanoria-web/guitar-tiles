extends Control

const GameScript = preload("res://scripts/game.gd")
const ChartParserScript = preload("res://scripts/chart_parser.gd")
const MidiParserScript = preload("res://scripts/midi_parser.gd")
const SngLoaderScript = preload("res://scripts/sng_loader.gd")
const StfsParserScript = preload("res://scripts/stfs_parser.gd")
const DtaParserScript = preload("res://scripts/dta_parser.gd")
const MoggHandlerScript = preload("res://scripts/mogg_handler.gd")

const BG_COLOR := Color(0.05, 0.05, 0.07)
const ACCENT := Color(0.3, 0.55, 1.0)
const CARD_BG := Color(0.10, 0.10, 0.14)
const CARD_SELECTED := Color(0.15, 0.22, 0.38)
const TEXT_DIM := Color(0.5, 0.5, 0.55)
const TEXT_BRIGHT := Color(0.92, 0.92, 0.96)
const STAR_COLOR := Color(1, 0.85, 0.15)

var card_container: VBoxContainer
var found_songs: Array = []
var card_panels: Array = []
var saved_scores: Dictionary = {}

const USER_SONGS_DIR := "user://songs"
const MIX_CACHE_DIR := "user://cache"

# Import status
var _import_status_label: Label = null

# Launch screen state
var _launch_overlay: Control = null
var _launch_song_index: int = -1
# Scanned instrument data: {instrument_key: [difficulties]}
var _launch_instruments: Dictionary = {}
var _launch_selected_instrument: String = ""
var _launch_instrument_btns: Dictionary = {}  # instrument_key -> Button
var _launch_diff_btns: Dictionary = {}  # difficulty -> Button
var _launch_selected_difficulty: String = "Expert"
var _launch_preset_option: OptionButton
var _launch_orientation_option: OptionButton
var _launch_approach_slider: HSlider
var _launch_approach_label: Label
var _launch_star_label: Label

func _ready() -> void:
	Settings.load_settings()
	_load_scores()
	_build_ui()
	_scan_songs()

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
	var t := Theme.new()
	var font_bold := load("res://fonts/Inter-Bold.ttf") as Font
	var font_regular := load("res://fonts/Inter-Regular.ttf") as Font
	if font_bold:
		t.set_default_font(font_bold)
	if font_regular:
		t.set_font("font", "Label", font_regular)
	if font_bold:
		t.set_font("font", "Button", font_bold)
		t.set_font("font", "OptionButton", font_bold)
	t.set_color("font_color", "Label", TEXT_BRIGHT)
	t.set_color("font_color", "Button", TEXT_BRIGHT)
	t.set_font_size("font_size", "Label", 20)
	t.set_font_size("font_size", "Button", 20)
	t.set_font_size("font_size", "OptionButton", 16)

	var btn_n := StyleBoxFlat.new()
	btn_n.bg_color = ACCENT.darkened(0.25)
	btn_n.set_corner_radius_all(12)
	btn_n.content_margin_left = 24; btn_n.content_margin_right = 24
	btn_n.content_margin_top = 16; btn_n.content_margin_bottom = 16
	t.set_stylebox("normal", "Button", btn_n)
	var btn_h := btn_n.duplicate()
	btn_h.bg_color = ACCENT.darkened(0.1)
	t.set_stylebox("hover", "Button", btn_h)
	var btn_p := btn_n.duplicate()
	btn_p.bg_color = ACCENT
	t.set_stylebox("pressed", "Button", btn_p)

	var opt_n := StyleBoxFlat.new()
	opt_n.bg_color = Color(0.13, 0.13, 0.18)
	opt_n.set_corner_radius_all(8)
	opt_n.content_margin_left = 10; opt_n.content_margin_right = 10
	opt_n.content_margin_top = 6; opt_n.content_margin_bottom = 6
	t.set_stylebox("normal", "OptionButton", opt_n)
	var opt_h := opt_n.duplicate()
	opt_h.bg_color = Color(0.18, 0.18, 0.25)
	t.set_stylebox("hover", "OptionButton", opt_h)

	return t

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vp := get_viewport_rect().size
	var theme := _create_theme()

	# Safe area
	var sa_l := 0.0; var sa_t := 0.0; var sa_r := 0.0; var sa_b := 0.0
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if screen.x > 0 and screen.y > 0:
		var sx := vp.x / float(screen.x)
		var sy := vp.y / float(screen.y)
		sa_l = safe.position.x * sx
		sa_t = safe.position.y * sy
		sa_r = (screen.x - safe.end.x) * sx
		sa_b = (screen.y - safe.end.y) * sy

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", int(sa_l + 12))
	root.add_theme_constant_override("margin_right", int(sa_r + 12))
	root.add_theme_constant_override("margin_top", int(sa_t + 8))
	root.add_theme_constant_override("margin_bottom", int(sa_b + 8))
	root.theme = theme
	add_child(root)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	root.add_child(main_vbox)

	# --- Title ---
	var title := Label.new()
	title.text = "Guitar Tiles"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", ACCENT.lightened(0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(title)

	# --- Song cards scroll area ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	card_container = VBoxContainer.new()
	card_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_container.add_theme_constant_override("separation", 10)
	scroll.add_child(card_container)

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

	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.set_corner_radius_all(14)
	style.content_margin_left = 18; style.content_margin_right = 18
	style.content_margin_top = 14; style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(0, 90)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(text_vbox)

	var title_lbl := Label.new()
	title_lbl.text = parsed["title"]
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", TEXT_BRIGHT)
	var font_bold := load("res://fonts/Inter-Bold.ttf") as Font
	if font_bold:
		title_lbl.add_theme_font_override("font", font_bold)
	text_vbox.add_child(title_lbl)

	if parsed["artist"] != "":
		var artist_lbl := Label.new()
		artist_lbl.text = parsed["artist"]
		artist_lbl.add_theme_font_size_override("font_size", 18)
		artist_lbl.add_theme_color_override("font_color", TEXT_DIM)
		text_vbox.add_child(artist_lbl)

	# Best star rating (across all instrument/difficulty combos for this song)
	var best_stars := _get_best_stars_for_song(song)
	if best_stars > 0:
		var stars_lbl := Label.new()
		var star_str := ""
		for si in range(5):
			star_str += "★" if si < best_stars else "☆"
		stars_lbl.text = star_str
		stars_lbl.add_theme_font_size_override("font_size", 22)
		stars_lbl.add_theme_color_override("font_color", STAR_COLOR)
		stars_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(stars_lbl)

	# Chevron
	var arrow := Label.new()
	arrow.text = "›"
	arrow.add_theme_font_size_override("font_size", 36)
	arrow.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(arrow)

	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_card_input.bind(index, panel))

	return panel

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
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_launch_screen(index)
	elif event is InputEventScreenTouch and event.pressed:
		_open_launch_screen(index)

# --- Song scanning ---

func _scan_songs() -> void:
	found_songs.clear()
	card_panels.clear()
	for child in card_container.get_children():
		child.queue_free()

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
					found_songs.append({"path": full_path, "display_name": fname})
			else:
				if scan_dir in deep_scan_dirs:
					_scan_subdir(scan_dir, fname)
			fname = dir.get_next()
		dir.list_dir_end()

	found_songs.sort_custom(func(a, b): return a["display_name"].to_lower() < b["display_name"].to_lower())

	for i in range(found_songs.size()):
		var card := _create_song_card(i, found_songs[i])
		card_container.add_child(card)
		card_panels.append(card)

	if found_songs.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Sarki bulunamadi\nAsagidaki butonla sarki ekleyin"
		empty_lbl.add_theme_font_size_override("font_size", 22)
		empty_lbl.add_theme_color_override("font_color", TEXT_DIM)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		card_container.add_child(empty_lbl)

	# Import button at end of list
	_add_import_button()

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
	spacer.custom_minimum_size = Vector2(0, 6)
	card_container.add_child(spacer)

	var import_btn := Button.new()
	import_btn.text = "+ Sarki Ekle"
	import_btn.add_theme_font_size_override("font_size", 22)
	import_btn.custom_minimum_size = Vector2(0, 56)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.12, 0.12, 0.16)
	btn_style.set_corner_radius_all(14)
	btn_style.content_margin_top = 14; btn_style.content_margin_bottom = 14
	btn_style.border_color = Color(0.25, 0.25, 0.32)
	btn_style.set_border_width_all(2)
	import_btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover := btn_style.duplicate()
	btn_hover.bg_color = Color(0.16, 0.16, 0.22)
	import_btn.add_theme_stylebox_override("hover", btn_hover)
	import_btn.add_theme_color_override("font_color", TEXT_DIM)
	import_btn.pressed.connect(_on_import_pressed)
	card_container.add_child(import_btn)

	# Status label (hidden by default)
	_import_status_label = Label.new()
	_import_status_label.text = ""
	_import_status_label.add_theme_font_size_override("font_size", 16)
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

	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.06, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # block clicks to song list
	_launch_overlay.add_child(bg)

	# Safe area margin
	var vp := get_viewport_rect().size
	var sa_l := 0.0; var sa_t := 0.0; var sa_r := 0.0; var sa_b := 0.0
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if screen.x > 0 and screen.y > 0:
		var sx := vp.x / float(screen.x)
		var sy := vp.y / float(screen.y)
		sa_l = safe.position.x * sx
		sa_t = safe.position.y * sy
		sa_r = (screen.x - safe.end.x) * sx
		sa_b = (screen.y - safe.end.y) * sy

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = sa_l + 16; scroll.offset_right = -(sa_r + 16)
	scroll.offset_top = sa_t + 12; scroll.offset_bottom = -(sa_b + 12)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_launch_overlay.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(vbox)

	# --- Top bar: Back + Delete ---
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 8)
	vbox.add_child(top_bar)

	var back_btn := Button.new()
	back_btn.text = "< Geri"
	back_btn.add_theme_font_size_override("font_size", 18)
	var back_style := StyleBoxFlat.new()
	back_style.bg_color = Color(0.12, 0.12, 0.16)
	back_style.set_corner_radius_all(8)
	back_style.content_margin_left = 12; back_style.content_margin_right = 12
	back_style.content_margin_top = 8; back_style.content_margin_bottom = 8
	back_btn.add_theme_stylebox_override("normal", back_style)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back_btn.pressed.connect(_close_launch_screen)
	top_bar.add_child(back_btn)

	# Spacer
	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_spacer)

	# Delete button — only for user-imported songs
	if song["path"].begins_with("user://"):
		var del_btn := Button.new()
		del_btn.text = "Sil"
		del_btn.add_theme_font_size_override("font_size", 18)
		del_btn.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		var del_style := StyleBoxFlat.new()
		del_style.bg_color = Color(0.2, 0.08, 0.08)
		del_style.set_corner_radius_all(8)
		del_style.content_margin_left = 12; del_style.content_margin_right = 12
		del_style.content_margin_top = 8; del_style.content_margin_bottom = 8
		del_style.border_color = Color(0.5, 0.15, 0.15)
		del_style.set_border_width_all(1)
		del_btn.add_theme_stylebox_override("normal", del_style)
		del_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
		del_btn.pressed.connect(_on_delete_song)
		top_bar.add_child(del_btn)

	# --- Song info (album art placeholder + title/artist) ---
	var info_hbox := HBoxContainer.new()
	info_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(info_hbox)

	# Album art
	var art_texture := _load_album_art(song)
	if art_texture:
		var art_rect := TextureRect.new()
		art_rect.texture = art_texture
		art_rect.custom_minimum_size = Vector2(110, 110)
		art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		info_hbox.add_child(art_rect)
	else:
		var art_panel := PanelContainer.new()
		var art_style := StyleBoxFlat.new()
		art_style.bg_color = Color(0.15, 0.15, 0.2)
		art_style.set_corner_radius_all(12)
		art_panel.add_theme_stylebox_override("panel", art_style)
		art_panel.custom_minimum_size = Vector2(110, 110)
		info_hbox.add_child(art_panel)
		var art_icon := Label.new()
		art_icon.text = "♪"
		art_icon.add_theme_font_size_override("font_size", 48)
		art_icon.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
		art_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		art_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		art_panel.add_child(art_icon)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 4)
	info_hbox.add_child(info_vbox)

	var title_lbl := Label.new()
	title_lbl.text = parsed["title"]
	title_lbl.add_theme_font_size_override("font_size", 32)
	title_lbl.add_theme_color_override("font_color", TEXT_BRIGHT)
	var font_bold := load("res://fonts/Inter-Bold.ttf") as Font
	if font_bold:
		title_lbl.add_theme_font_override("font", font_bold)
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	info_vbox.add_child(title_lbl)

	if parsed["artist"] != "":
		var artist_lbl := Label.new()
		artist_lbl.text = parsed["artist"]
		artist_lbl.add_theme_font_size_override("font_size", 22)
		artist_lbl.add_theme_color_override("font_color", TEXT_DIM)
		info_vbox.add_child(artist_lbl)

	# --- Separator ---
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	vbox.add_child(sep)

	# --- Instrument selection ---
	if _launch_instruments.size() > 1 or not _launch_instruments.has("guitar"):
		var inst_label := Label.new()
		inst_label.text = "Enstruman"
		inst_label.add_theme_font_size_override("font_size", 16)
		inst_label.add_theme_color_override("font_color", TEXT_DIM)
		vbox.add_child(inst_label)

		var inst_hbox := HBoxContainer.new()
		inst_hbox.add_theme_constant_override("separation", 8)
		vbox.add_child(inst_hbox)

		_launch_instrument_btns.clear()
		# Order: guitar, bass, keys, drums
		for inst_key in ["guitar", "bass", "keys", "drums"]:
			if not _launch_instruments.has(inst_key):
				continue
			var btn := Button.new()
			btn.text = ChartParserScript.INSTRUMENT_DISPLAY.get(inst_key, inst_key)
			btn.add_theme_font_size_override("font_size", 20)
			btn.custom_minimum_size = Vector2(0, 48)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.pressed.connect(_on_instrument_selected.bind(inst_key))
			inst_hbox.add_child(btn)
			_launch_instrument_btns[inst_key] = btn
	else:
		_launch_instrument_btns.clear()

	# --- Difficulty selection ---
	var diff_label := Label.new()
	diff_label.text = "Zorluk"
	diff_label.add_theme_font_size_override("font_size", 16)
	diff_label.add_theme_color_override("font_color", TEXT_DIM)
	vbox.add_child(diff_label)

	var diff_hbox := HBoxContainer.new()
	diff_hbox.add_theme_constant_override("separation", 8)
	diff_hbox.name = "DifficultyRow"
	vbox.add_child(diff_hbox)
	_rebuild_difficulty_buttons(diff_hbox)

	# --- Best score for current selection ---
	_launch_star_label = Label.new()
	_launch_star_label.add_theme_font_size_override("font_size", 20)
	_launch_star_label.add_theme_color_override("font_color", STAR_COLOR)
	vbox.add_child(_launch_star_label)

	# --- Preset ---
	var preset_hbox := HBoxContainer.new()
	preset_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(preset_hbox)

	var preset_lbl := Label.new()
	preset_lbl.text = "Oynanis:"
	preset_lbl.add_theme_font_size_override("font_size", 16)
	preset_lbl.add_theme_color_override("font_color", TEXT_DIM)
	preset_hbox.add_child(preset_lbl)

	_launch_preset_option = OptionButton.new()
	for item in ["Tiles", "Rahat", "Normal", "Sadik"]:
		_launch_preset_option.add_item(item)
	_launch_preset_option.select(0)
	_launch_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_launch_preset_option.custom_minimum_size = Vector2(80, 40)
	preset_hbox.add_child(_launch_preset_option)

	# --- Mode (Piano 4 / Guitar 5) ---
	var mode_hbox := HBoxContainer.new()
	mode_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(mode_hbox)

	var mode_lbl := Label.new()
	mode_lbl.text = "Mod:"
	mode_lbl.add_theme_font_size_override("font_size", 16)
	mode_lbl.add_theme_color_override("font_color", TEXT_DIM)
	mode_hbox.add_child(mode_lbl)

	var mode_option := OptionButton.new()
	mode_option.add_item("Piyano (4)")
	mode_option.add_item("Gitar (5)")
	mode_option.select(0)
	mode_option.name = "ModeOption"
	mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_option.custom_minimum_size = Vector2(80, 40)
	mode_hbox.add_child(mode_option)

	# --- Orientation + Speed ---
	var orient_hbox := HBoxContainer.new()
	orient_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(orient_hbox)

	var orient_lbl := Label.new()
	orient_lbl.text = "Yon:"
	orient_lbl.add_theme_font_size_override("font_size", 16)
	orient_lbl.add_theme_color_override("font_color", TEXT_DIM)
	orient_hbox.add_child(orient_lbl)

	_launch_orientation_option = OptionButton.new()
	_launch_orientation_option.add_item("Dikey")
	_launch_orientation_option.add_item("Yatay")
	_launch_orientation_option.select(0 if Settings.orientation == "portrait" else 1)
	_launch_orientation_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_launch_orientation_option.custom_minimum_size = Vector2(80, 40)
	_launch_orientation_option.item_selected.connect(_on_launch_orientation_changed)
	orient_hbox.add_child(_launch_orientation_option)

	var speed_hbox := HBoxContainer.new()
	speed_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(speed_hbox)

	var speed_lbl := Label.new()
	speed_lbl.text = "Hiz:"
	speed_lbl.add_theme_font_size_override("font_size", 16)
	speed_lbl.add_theme_color_override("font_color", TEXT_DIM)
	speed_hbox.add_child(speed_lbl)

	_launch_approach_slider = HSlider.new()
	_launch_approach_slider.min_value = 0.8; _launch_approach_slider.max_value = 2.0; _launch_approach_slider.step = 0.05
	_launch_approach_slider.value = Settings.approach_time_sec
	_launch_approach_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_launch_approach_slider.custom_minimum_size = Vector2(100, 28)
	_launch_approach_slider.value_changed.connect(_on_launch_approach_changed)
	speed_hbox.add_child(_launch_approach_slider)

	_launch_approach_label = Label.new()
	_launch_approach_label.text = "%.1f" % Settings.approach_time_sec
	_launch_approach_label.add_theme_font_size_override("font_size", 16)
	_launch_approach_label.custom_minimum_size = Vector2(36, 0)
	speed_hbox.add_child(_launch_approach_label)

	# --- Spacer ---
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	# --- BAŞLAT button ---
	var start_btn := Button.new()
	start_btn.text = "BASLAT"
	start_btn.add_theme_font_size_override("font_size", 28)
	start_btn.custom_minimum_size = Vector2(0, 64)
	var start_style := StyleBoxFlat.new()
	start_style.bg_color = Color(0.15, 0.65, 0.3)
	start_style.set_corner_radius_all(14)
	start_style.content_margin_top = 16; start_style.content_margin_bottom = 16
	start_btn.add_theme_stylebox_override("normal", start_style)
	var start_hover := start_style.duplicate()
	start_hover.bg_color = Color(0.2, 0.75, 0.35)
	start_btn.add_theme_stylebox_override("hover", start_hover)
	var start_pressed := start_style.duplicate()
	start_pressed.bg_color = Color(0.25, 0.8, 0.4)
	start_btn.add_theme_stylebox_override("pressed", start_pressed)
	start_btn.pressed.connect(_on_launch_start)
	vbox.add_child(start_btn)

	# Update visuals
	_update_instrument_highlight()
	_update_launch_star()

	# Fade in
	_launch_overlay.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_launch_overlay, "modulate:a", 1.0, 0.2)

func _close_launch_screen() -> void:
	if _launch_overlay:
		_launch_overlay.queue_free()
		_launch_overlay = null

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
	_scan_songs()

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
	var img := Image.new()
	# Try JPEG first, then PNG
	if img.load_jpg_from_buffer(data) == OK:
		pass
	elif img.load_png_from_buffer(data) == OK:
		pass
	else:
		return null
	# Resize for display performance
	if img.get_width() > 256 or img.get_height() > 256:
		img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _rebuild_difficulty_buttons(container: HBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()
	_launch_diff_btns.clear()

	var diffs: Array = _launch_instruments.get(_launch_selected_instrument, [])
	for diff in diffs:
		var btn := Button.new()
		btn.text = diff as String
		btn.add_theme_font_size_override("font_size", 18)
		btn.custom_minimum_size = Vector2(0, 44)
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

func _update_instrument_highlight() -> void:
	for inst_key in _launch_instrument_btns:
		var btn: Button = _launch_instrument_btns[inst_key]
		var selected: bool = (inst_key == _launch_selected_instrument)
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(10)
		style.content_margin_left = 12; style.content_margin_right = 12
		style.content_margin_top = 10; style.content_margin_bottom = 10
		if selected:
			style.bg_color = ACCENT
			style.border_color = ACCENT.lightened(0.3)
			style.set_border_width_all(2)
		else:
			style.bg_color = Color(0.12, 0.12, 0.16)
		btn.add_theme_stylebox_override("normal", style)

func _update_difficulty_highlight() -> void:
	for diff_key in _launch_diff_btns:
		var btn: Button = _launch_diff_btns[diff_key]
		var selected: bool = (diff_key == _launch_selected_difficulty)
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(10)
		style.content_margin_left = 10; style.content_margin_right = 10
		style.content_margin_top = 8; style.content_margin_bottom = 8
		if selected:
			style.bg_color = ACCENT
			style.border_color = ACCENT.lightened(0.3)
			style.set_border_width_all(2)
		else:
			style.bg_color = Color(0.12, 0.12, 0.16)
		btn.add_theme_stylebox_override("normal", style)

func _update_launch_star() -> void:
	if not _launch_star_label:
		return
	var song: Dictionary = found_songs[_launch_song_index]
	var score_key := _make_score_key(song, _launch_selected_instrument, _launch_selected_difficulty, "")
	# Check all presets for best score on this instrument+difficulty
	var best_stars := 0
	var best_score := 0
	for preset in ["Tiles", "Rahat", "Normal", "Sadik"]:
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
		_launch_star_label.text = "%s  En iyi: %d" % [star_str, best_score]
	else:
		_launch_star_label.text = ""

func _make_score_key(song: Dictionary, instrument: String, difficulty: String, preset: String) -> String:
	var song_hash: String = String(song["path"]).md5_text()
	return "%s_%s_%s_%s" % [song_hash, instrument, difficulty, preset]

func _on_launch_orientation_changed(idx: int) -> void:
	Settings.orientation = "portrait" if idx == 0 else "landscape"
	Settings.approach_time_sec = Settings.default_approach_for_orientation()
	if _launch_approach_slider:
		_launch_approach_slider.value = Settings.approach_time_sec
	if _launch_approach_label:
		_launch_approach_label.text = "%.1f" % Settings.approach_time_sec
	Settings.save_settings()

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

	# Mode from OptionButton
	var mode_opt = _launch_overlay.find_child("ModeOption", true, false) as OptionButton
	if mode_opt:
		GameScript.song_mode = "piano" if mode_opt.selected == 0 else "guitar"
	else:
		GameScript.song_mode = "piano"

	var preset_names := ["Tiles", "Rahat", "Normal", "Sadik"]
	GameScript.song_preset = preset_names[_launch_preset_option.selected]

	get_tree().change_scene_to_file("res://scenes/game.tscn")

# =====================================================================
#  SONG IMPORT
# =====================================================================

func _on_import_pressed() -> void:
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
		"Sarki Dosyasi Sec",
		"",
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILES,
		filters,
		_on_files_selected
	)

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
		# Android content:// URI — copy to temp via plugin, then import
		if path.begins_with("content://"):
			actual_path = _resolve_content_uri(path)
			if actual_path == "":
				print("Import: content URI resolve failed: %s" % path)
				continue
		var ok := _import_file(actual_path)
		print("Import: _import_file(%s) = %s" % [actual_path, str(ok)])
		if ok:
			imported += 1
		# Clean up temp file if we copied from content URI
		if path.begins_with("content://") and actual_path != "" and FileAccess.file_exists(actual_path):
			DirAccess.remove_absolute(actual_path)
	if imported > 0:
		_show_import_status("%d sarki eklendi!" % imported)
		_scan_songs()
	else:
		_show_import_status("Desteklenen dosya bulunamadi.")

func _resolve_content_uri(uri: String) -> String:
	if not Engine.has_singleton("NativeAudioDecoder"):
		push_error("Import: NativeAudioDecoder not available for content URI")
		return ""
	var plugin = Engine.get_singleton("NativeAudioDecoder")
	# Copy to a temp location, get original filename
	var temp_dir := OS.get_cache_dir().path_join("import_temp")
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var temp_file := temp_dir.path_join("import_temp_file")
	var display_name: String = plugin.call("copyContentUri", uri, temp_file)
	if display_name == "" or not FileAccess.file_exists(temp_file):
		print("Import: copyContentUri failed for %s" % uri)
		return ""
	# Rename temp file with the correct extension from display name
	var final_path := temp_dir.path_join(display_name)
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	DirAccess.rename_absolute(temp_file, final_path)
	print("Import: resolved content URI → %s (%s)" % [final_path, display_name])
	return final_path

func _import_file(path: String) -> bool:
	var fl := path.to_lower()
	if fl.ends_with(".zip"):
		return _import_zip(path)
	elif fl.ends_with(".sng"):
		return _copy_file_to_songs(path, path.get_file())
	elif fl.ends_with(".chart") or fl.ends_with(".mid"):
		return _import_chart_folder(path)
	elif fl.ends_with(".con") or fl.ends_with(".live"):
		return _import_con(path)
	elif _is_stfs_by_magic(path):
		return _import_con(path)
	return false

func _is_stfs_by_magic(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
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
			if _convert_mogg_to_stereo(raw_ogg_path, stereo_path):
				saved += 1
				DirAccess.remove_absolute(raw_ogg_path)
			else:
				# Fallback: keep raw OGG, desktop ffmpeg will handle during playback
				DirAccess.rename_absolute(raw_ogg_path, stereo_path)
				saved += 1
				print("Import: kept raw multi-channel OGG (will convert during playback)")
		elif mogg.is_encrypted:
			push_error("Import: encrypted MOGG — cannot import")
			return false

	# Save DTA for reference
	if dta_text != "":
		var dta_path := dest_dir.path_join("songs.dta")
		var f := FileAccess.open(dta_path, FileAccess.WRITE)
		if f:
			f.store_string(dta_text)
			f.close()

	# Save album art
	var art_data := stfs.get_album_art_data()
	if art_data.size() > 0:
		# Detect format from header
		var ext := ".png"
		if art_data.size() >= 2 and art_data[0] == 0xFF and art_data[1] == 0xD8:
			ext = ".jpg"
		var art_path := dest_dir.path_join("album" + ext)
		var f := FileAccess.open(art_path, FileAccess.WRITE)
		if f:
			f.store_buffer(art_data)
			f.close()
			print("Import: saved album art (%d bytes)" % art_data.size())

	print("Import: CON extracted to %s (%d files)" % [folder_name, saved])
	return saved >= 2  # Need at least MIDI + audio

func _convert_mogg_to_stereo(input_ogg: String, output_path: String) -> bool:
	var os_input := ProjectSettings.globalize_path(input_ogg)
	var os_output := ProjectSettings.globalize_path(output_path)

	if OS.has_feature("android"):
		# Android: use NativeAudioDecoder to decode multi-ch OGG → stereo WAV
		if not Engine.has_singleton("NativeAudioDecoder"):
			return false
		var plugin = Engine.get_singleton("NativeAudioDecoder")
		# decodeAndMix with single input handles multi-channel → stereo downmix
		# But it's async... use sync approach: save as WAV directly
		var wav_output := output_path.get_base_dir().path_join("song.wav")
		var os_wav := ProjectSettings.globalize_path(wav_output)
		# Call sync decode for import (blocking is OK during import)
		var result = plugin.call("decodeToStereoWav", os_input, os_wav)
		if result == null or str(result) != "":
			print("Import: Android stereo convert failed: %s" % str(result))
			return false
		# Rename wav to the output path (keep as wav, game handles both)
		if wav_output != output_path:
			var final_wav := output_path.get_base_dir().path_join("song.wav")
			if final_wav != wav_output:
				DirAccess.rename_absolute(wav_output, final_wav)
		print("Import: Android converted to stereo WAV")
		return true
	else:
		# PC: use ffmpeg
		# Probe channel count
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
			# Build pan filter for multi-channel
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
