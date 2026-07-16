extends Control

const GameScript = preload("res://scripts/game.gd")
const ChartParserScript = preload("res://scripts/chart_parser.gd")
const SngLoaderScript = preload("res://scripts/sng_loader.gd")

var song_list: ItemList
var difficulty_option: OptionButton
var mode_option: OptionButton
var preset_option: OptionButton
var play_button: Button
var title_label: Label
var found_songs: Array = []  # [{path, display_name, difficulties}]

func _ready() -> void:
	_build_ui()
	_scan_songs()

func _build_ui() -> void:
	var vp := get_viewport_rect().size

	# Title
	title_label = Label.new()
	title_label.text = "Guitar Tiles"
	title_label.add_theme_font_size_override("font_size", 48)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.position = Vector2(0, 20)
	title_label.size = Vector2(vp.x, 60)
	add_child(title_label)

	# Mode selector
	var mode_lbl := Label.new()
	mode_lbl.text = "Mod:"
	mode_lbl.add_theme_font_size_override("font_size", 20)
	mode_lbl.position = Vector2(vp.x * 0.2, 95)
	add_child(mode_lbl)

	mode_option = OptionButton.new()
	mode_option.add_item("Gitar Deneyimi (5 Serit)")
	mode_option.add_item("Piyano Deneyimi (4 Serit)")
	mode_option.add_theme_font_size_override("font_size", 18)
	mode_option.position = Vector2(vp.x * 0.2 + 50, 90)
	mode_option.size = Vector2(250, 35)
	add_child(mode_option)

	# Difficulty selector
	var diff_lbl := Label.new()
	diff_lbl.text = "Zorluk:"
	diff_lbl.add_theme_font_size_override("font_size", 20)
	diff_lbl.position = Vector2(vp.x * 0.6, 95)
	add_child(diff_lbl)

	difficulty_option = OptionButton.new()
	difficulty_option.add_theme_font_size_override("font_size", 18)
	difficulty_option.position = Vector2(vp.x * 0.6 + 70, 90)
	difficulty_option.size = Vector2(150, 35)
	add_child(difficulty_option)

	# Preset selector
	var preset_lbl := Label.new()
	preset_lbl.text = "Oynanis:"
	preset_lbl.add_theme_font_size_override("font_size", 20)
	preset_lbl.position = Vector2(vp.x * 0.2, 130)
	add_child(preset_lbl)

	preset_option = OptionButton.new()
	preset_option.add_item("Rahat")
	preset_option.add_item("Normal")
	preset_option.add_item("Sadik (orijinal)")
	preset_option.select(0)  # default Rahat
	preset_option.add_theme_font_size_override("font_size", 18)
	preset_option.position = Vector2(vp.x * 0.2 + 80, 125)
	preset_option.size = Vector2(200, 35)
	add_child(preset_option)

	# Song list
	song_list = ItemList.new()
	song_list.position = Vector2(vp.x * 0.15, 175)
	song_list.size = Vector2(vp.x * 0.7, vp.y - 265)
	song_list.add_theme_font_size_override("font_size", 22)
	song_list.item_activated.connect(_on_song_activated)
	song_list.item_selected.connect(_on_song_selected)
	add_child(song_list)

	# Play button
	play_button = Button.new()
	play_button.text = "Play"
	play_button.add_theme_font_size_override("font_size", 24)
	play_button.position = Vector2(vp.x / 2.0 - 60, vp.y - 70)
	play_button.size = Vector2(120, 45)
	play_button.pressed.connect(_on_play_pressed)
	add_child(play_button)

func _scan_songs() -> void:
	found_songs.clear()
	song_list.clear()

	var scan_dirs: Array = []
	var res_songs := "res://songs"
	if DirAccess.dir_exists_absolute(res_songs):
		scan_dirs.append(res_songs)
	scan_dirs.append("res://")

	for _sd in scan_dirs:
		var scan_dir: String = _sd
		var dir := DirAccess.open(scan_dir)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir():
				if fname.ends_with(".chart") or fname.ends_with(".sng"):
					var full_path := scan_dir.path_join(fname)
					found_songs.append({"path": full_path, "display_name": fname, "difficulties": []})
			else:
				if scan_dir == "res://songs":
					var sub_dir := DirAccess.open(scan_dir.path_join(fname))
					if sub_dir:
						sub_dir.list_dir_begin()
						var sub_fname := sub_dir.get_next()
						while sub_fname != "":
							if sub_fname.ends_with(".chart") or sub_fname.ends_with(".sng"):
								var full_path := scan_dir.path_join(fname).path_join(sub_fname)
								found_songs.append({"path": full_path, "display_name": "%s / %s" % [fname, sub_fname], "difficulties": []})
							sub_fname = sub_dir.get_next()
						sub_dir.list_dir_end()
			fname = dir.get_next()
		dir.list_dir_end()

	for song in found_songs:
		song_list.add_item(song["display_name"])

	if found_songs.is_empty():
		song_list.add_item("(No songs found -- add .chart or .sng to songs/)")

	# Select first and load its difficulties
	if found_songs.size() > 0:
		song_list.select(0)
		_on_song_selected(0)

func _on_song_selected(index: int) -> void:
	if index < 0 or index >= found_songs.size():
		return

	var song = found_songs[index]

	# Scan difficulties if not cached
	if song["difficulties"].is_empty():
		var diffs: Array[String] = []
		var path: String = song["path"]
		if path.ends_with(".chart"):
			diffs = ChartParserScript.scan_difficulties_from_file(path)
		elif path.ends_with(".sng"):
			var loader = SngLoaderScript.new()
			if loader.load_sng(path):
				var chart_text: String = loader.get_chart_text()
				if chart_text != "":
					diffs = ChartParserScript.scan_difficulties_from_text(chart_text)
		song["difficulties"] = diffs

	# Update difficulty dropdown
	difficulty_option.clear()
	var diffs_arr: Array = song["difficulties"]
	if diffs_arr.is_empty():
		difficulty_option.add_item("Expert")
	else:
		for d in diffs_arr:
			difficulty_option.add_item(d)
		# Default to Expert if available
		for i in range(diffs_arr.size()):
			if diffs_arr[i] == "Expert":
				difficulty_option.select(i)
				break

func _on_song_activated(index: int) -> void:
	_launch_song(index)

func _on_play_pressed() -> void:
	var selected := song_list.get_selected_items()
	if selected.size() > 0:
		_launch_song(selected[0])

func _launch_song(index: int) -> void:
	if index < 0 or index >= found_songs.size():
		return
	GameScript.song_source = found_songs[index]["path"]
	GameScript.song_difficulty = difficulty_option.get_item_text(difficulty_option.selected)
	GameScript.song_mode = "piano" if mode_option.selected == 1 else "guitar"
	var preset_names := ["Rahat", "Normal", "Sadik"]
	GameScript.song_preset = preset_names[preset_option.selected]
	get_tree().change_scene_to_file("res://scenes/game.tscn")
