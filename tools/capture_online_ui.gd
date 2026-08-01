extends SceneTree

var menu: Control
var post_open_frames := 0
var save_screenshot := false
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

func _process(_delta: float) -> bool:
	if is_instance_valid(menu._menu_loading_layer) and menu._menu_loading_layer.visible:
		return false
	if not is_instance_valid(menu._battle_overlay):
		menu._open_battle_menu()
		return false
	post_open_frames += 1
	if post_open_frames < 4:
		return false
	var mode_buttons: Dictionary = menu._battle_mode_buttons
	assert(mode_buttons.size() == 2)
	for button in mode_buttons.values():
		assert(button.custom_minimum_size.y >= 150.0)
	assert(menu._battle_name_edit.custom_minimum_size.y >= 70.0)
	assert(menu._battle_code_edit.custom_minimum_size.y >= 80.0)
	_assert_battle_back_button()
	if save_screenshot:
		var image := root.get_texture().get_image()
		var capture_path := "res://tmp/online-entry-mobile.png" \
			if mobile else "res://tmp/online-entry.png"
		var error := image.save_png(capture_path)
		assert(error == OK)
		print("ONLINE UI SCREENSHOT PASS: ", image.get_size())
	else:
		print("ONLINE UI ENTRY PASS: giant controls verified")
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
