extends SceneTree

var game
var frames := 0


func _initialize() -> void:
	root.content_scale_size = Vector2i(540, 960)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = Vector2i(540, 960)

	var game_script := GDScript.new()
	game_script.source_code = """
extends "res://scripts/game.gd"

func _ready() -> void:
	size = Vector2(540, 960)
	_ui_scale = 1.0
	song_source = "Tester - Loading UI.chart"
	_build_loading_screen()

func _process(_delta: float) -> void:
	pass

func _draw() -> void:
	pass
"""
	assert(game_script.reload() == OK)
	game = game_script.new()
	game.size = Vector2(540, 960)
	root.add_child(game)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 4:
		return false
	var root_control: Control = game.loading_layer.get_child(1)
	var back := root_control.find_child("LoadingBackButton", true, false) as Button
	var card := root_control.find_child("LoadingContentCard", true, false) as PanelContainer
	var album := root_control.find_child("LoadingAlbumFrame", true, false) as PanelContainer
	var rail := root_control.find_child("LoadingStatusRail", true, false) as PanelContainer
	var countdown := root_control.find_child("LoadingCountdownPlate", true, false) as PanelContainer
	assert(back != null)
	assert(card != null)
	assert(album != null)
	assert(rail != null)
	assert(countdown != null)
	assert(game.loading_status_label != game.loading_countdown_label)
	assert(back.size.x >= 118.0 and back.size.y >= 58.0)
	assert(back.position.x >= 0.0 and back.position.y >= 0.0)
	game._show_loading_countdown(3)
	assert(countdown.visible)
	assert(game.loading_countdown_label.text == "3")
	game._hide_loading_countdown()
	assert(not countdown.visible)
	game.free()
	print("Loading UI tests passed: hard-rock hierarchy, persistent Back, separate status/countdown")
	quit(0)
	return true
