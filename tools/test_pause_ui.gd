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
	song_started = true
	is_loading = false
	_countdown = -1.0
	_pause_game()

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
	if frames < 5:
		return false

	assert(game._paused)
	assert(game._pause_layer != null)
	var card := game._pause_layer.find_child("PauseCard", true, false) as PanelContainer
	var logo := game._pause_layer.find_child("PauseLogo", true, false) as TextureRect
	var resume := game._pause_layer.find_child(
		"PauseResumeButton", true, false) as Button
	var restart := game._pause_layer.find_child(
		"PauseRestartButton", true, false) as Button
	var quit_button := game._pause_layer.find_child(
		"PauseQuitButton", true, false) as Button
	assert(card != null)
	assert(logo != null and logo.texture != null)
	assert(logo.texture.resource_path == UITheme.GAME_LOGO_PATH)
	assert(resume != null and restart != null and quit_button != null)
	assert(resume.size.y >= 72.0)
	assert(restart.size.y >= 60.0)
	assert(quit_button.size.y >= 60.0)
	assert(card.position.x >= 0.0 and card.position.y >= 0.0)
	assert(card.position.x + card.size.x <= 540.5)
	assert(card.position.y + card.size.y <= 960.5)

	assert(game._handle_game_back())
	assert(not game._paused and game._pause_layer == null)
	assert(game._handle_game_back())
	assert(game._paused and game._pause_layer != null)

	game.free()
	print("Pause UI tests passed: hard-rock layout, own logo, touch targets, Back toggle")
	quit(0)
	return true
