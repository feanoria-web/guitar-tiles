extends SceneTree

var menu: Control
var configured := false
var post_open_frames := 0
var save_screenshot := false
var capture_english := false
var previous_language := ""
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
	save_screenshot = "--save-screenshot" in OS.get_cmdline_user_args()
	capture_english = "--english" in OS.get_cmdline_user_args()
	previous_language = Settings.language

func _process(_delta: float) -> bool:
	if is_instance_valid(menu._menu_loading_layer) and menu._menu_loading_layer.visible:
		return false
	if not configured:
		if capture_english:
			Settings.language = "en"
		var session = root.get_node("BattleSession")
		session.session_state = "lobby"
		session.is_host = true
		session.local_uid = "host"
		session.room_code = "RIFF42"
		session.room_mode = "battle"
		session.selected_song = {
			"name": "Riffline Test Song",
			"fingerprint": "ui-test",
			"mode": "guitar",
			"preset": "TilesAkici",
			"instruments": {
				"guitar": ["Easy", "Medium", "Hard", "Expert"],
				"bass": ["Hard", "Expert"],
				"drums": ["Expert"],
				"vocals": ["Expert"],
			},
		}
		session.players = {
			"host": {"uid": "host", "name": "Gürkan", "host": true, "ready": true, "song_ok": true, "instrument": "guitar", "difficulty": "Expert"},
			"p2": {"uid": "p2", "name": "Bandmate", "host": false, "ready": false, "song_ok": true, "instrument": "drums", "difficulty": "Expert"},
		}
		configured = true
		menu._open_battle_menu()
		return false
	post_open_frames += 1
	if post_open_frames == 2:
		var scrolls: Array[Node] = menu._battle_overlay.find_children("*", "ScrollContainer", true, false)
		if not scrolls.is_empty():
			var scroll := scrolls[0] as ScrollContainer
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	if post_open_frames < 6:
		return false
	assert(menu._battle_players_box.get_child_count() == 2)
	assert(menu._battle_instrument_option.custom_minimum_size.y >= 80.0)
	assert(menu._battle_ready_button.custom_minimum_size.y >= 90.0)
	assert(menu._battle_start_button.custom_minimum_size.y >= 100.0)
	_assert_battle_back_button()
	if save_screenshot:
		var image := root.get_texture().get_image()
		var basename := "online-lobby-en" \
			if capture_english else "online-lobby"
		var suffix := "-mobile" if mobile else ""
		var capture_path := "res://tmp/%s%s.png" % [basename, suffix]
		var error := image.save_png(capture_path)
		assert(error == OK)
		print("ONLINE UI LOBBY SCREENSHOT PASS: ", image.get_size())
	else:
		print("ONLINE UI LOBBY PASS: giant controls verified")
	Settings.language = previous_language
	quit()
	return true


func _assert_battle_back_button() -> void:
	var back_button := menu._battle_overlay.find_child(
		"BattleBackButton", true, false) as Button
	assert(is_instance_valid(back_button))
	assert(back_button.is_visible_in_tree())
	var rect := back_button.get_global_rect()
	var touch_width := maxf(rect.size.x, back_button.custom_minimum_size.x)
	var touch_height := maxf(rect.size.y, back_button.custom_minimum_size.y)
	assert(touch_width >= 64.0)
	assert(touch_height >= 64.0)
	assert(rect.position.x >= 0.0)
	assert(rect.end.x <= float(root.size.x) * 0.5)
	assert(rect.position.y >= 0.0)
	assert(rect.end.y <= float(root.size.y) * 0.25)
