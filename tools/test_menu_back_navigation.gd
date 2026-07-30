extends SceneTree

var menu: Control
var frame_count := 0
var launch_button: Button
var closed := false
var battle_back_button: Button


func _initialize() -> void:
	var packed := load("res://scenes/menu.tscn") as PackedScene
	menu = packed.instantiate()
	root.add_child(menu)


func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 4:
		menu.found_songs = [{
			"path": "res://notes.chart",
			"display_name": "Back Navigation Test",
		}]
		menu._open_launch_screen(0)
		if not is_instance_valid(menu._launch_overlay):
			return _fail("Launch overlay was not created")
	if frame_count == 12:
		launch_button = menu._launch_overlay.find_child(
			"LaunchStartButton", true, false) as Button
		if not is_instance_valid(launch_button):
			return _fail("Launch start button was not found")
		menu._close_launch_screen()
		closed = true
	if closed and frame_count >= 130:
		if menu._launch_overlay != null:
			return _fail("Launch overlay reference was not cleared")
		if is_instance_valid(launch_button):
			return _fail("Launch start button survived overlay close")
		closed = false
		menu._open_battle_menu()
		if not is_instance_valid(menu._battle_overlay):
			return _fail("Battle overlay was not created")
	if frame_count == 138:
		battle_back_button = menu._battle_overlay.find_child(
			"BattleBackButton", true, false) as Button
		if not is_instance_valid(battle_back_button):
			return _fail("Battle back button was not found")
		if battle_back_button.custom_minimum_size.x < 64.0 \
				or battle_back_button.custom_minimum_size.y < 64.0:
			return _fail("Battle back button is too small for mobile navigation")
		var battle_header := battle_back_button.get_parent()
		if not is_instance_valid(battle_header) \
				or battle_header.get_child(0) != battle_back_button:
			return _fail("Battle back button is not the first header control")
		if not menu._handle_back_navigation():
			return _fail("Unified back handler did not close the battle overlay")
	if frame_count == 146:
		if menu._battle_overlay != null:
			return _fail("Battle overlay reference was not cleared")
		if is_instance_valid(battle_back_button):
			return _fail("Battle back button survived overlay close")
		menu._open_song_tutorial()
		if not is_instance_valid(menu._tutorial_overlay):
			return _fail("Tutorial overlay was not created")
	if frame_count == 154:
		if not menu._handle_back_navigation():
			return _fail("Unified back handler did not close the tutorial overlay")
	if frame_count == 162:
		if menu._tutorial_overlay != null:
			return _fail("Tutorial overlay reference was not cleared")
		if menu._handle_back_navigation():
			return _fail("Unified back handler consumed back with no overlay open")
		print(
			"Menu back-navigation test passed: launch tween, battle back, "
			+ "and tutorial back are safe")
		quit(0)
		return true
	return false


func _fail(message: String) -> bool:
	push_error("Menu back-navigation test failed: %s" % message)
	quit(1)
	return true
