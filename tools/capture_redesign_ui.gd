extends SceneTree

var menu: Control
var frame_count := 0
var stage := 0
var mobile := false


func _initialize() -> void:
	mobile = "--mobile" in OS.get_cmdline_user_args()
	var capture_size := Vector2i(540, 960) if mobile else Vector2i(1280, 720)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(capture_size)
	root.size = capture_size
	var packed := load("res://scenes/menu.tscn") as PackedScene
	menu = packed.instantiate()
	root.add_child(menu)


func _process(_delta: float) -> bool:
	if is_instance_valid(menu._menu_loading_layer) and menu._menu_loading_layer.visible:
		return false
	frame_count += 1

	match stage:
		0:
			if frame_count < 8:
				return false
			_save(_capture_path("redesign-main"))
			menu._open_song_tutorial()
			stage = 1
			frame_count = 0
		1:
			if frame_count < 12:
				return false
			_save(_capture_path("redesign-help"))
			var help_scroll := _find_scroll(menu._tutorial_overlay)
			if help_scroll:
				help_scroll.scroll_vertical = int(
					help_scroll.get_v_scroll_bar().max_value)
			stage = 2
			frame_count = 0
		2:
			if frame_count < 12:
				return false
			_save(_capture_path("redesign-help-credits"))
			menu._close_song_tutorial()
			stage = 3
			frame_count = 0
		3:
			if frame_count < 20:
				return false
			if menu.found_songs.is_empty():
				menu.found_songs = [{
					"path": "res://notes.chart",
					"display_name": "Neon Highway Preview",
				}]
			menu._open_launch_screen(0)
			stage = 4
			frame_count = 0
		4:
			if frame_count < 12:
				return false
			_save(_capture_path("redesign-launch-top"))
			var scroll := _find_launch_scroll()
			if scroll:
				scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
			stage = 5
			frame_count = 0
		5:
			if frame_count < 12:
				return false
			_save(_capture_path("redesign-launch-bottom"))
			print("REDESIGN UI SCREENSHOTS PASS")
			quit(0)
			return true
	return false


func _find_launch_scroll() -> ScrollContainer:
	if not is_instance_valid(menu._launch_overlay):
		return null
	return _find_scroll(menu._launch_overlay)


func _find_scroll(owner: Node) -> ScrollContainer:
	if not is_instance_valid(owner):
		return null
	var scrolls: Array[Node] = owner.find_children(
		"*", "ScrollContainer", true, false)
	return scrolls[0] as ScrollContainer if not scrolls.is_empty() else null


func _capture_path(basename: String) -> String:
	var suffix := "-mobile" if mobile else ""
	return "res://tmp/%s%s.png" % [basename, suffix]


func _save(path: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	assert(error == OK)
	print("Saved ", path, " ", image.get_size())
