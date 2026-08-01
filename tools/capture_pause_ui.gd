extends SceneTree

const CAPTURE_SIZE := Vector2i(1280, 720)

var preview
var frame_count := 0


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(CAPTURE_SIZE)
	root.content_scale_size = CAPTURE_SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = CAPTURE_SIZE

	var preview_script := GDScript.new()
	preview_script.source_code = """
extends "res://scripts/game.gd"

func _ready() -> void:
	size = Vector2(1280, 720)
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
	assert(preview_script.reload() == OK)
	preview = preview_script.new()
	preview.position = Vector2.ZERO
	preview.size = Vector2(CAPTURE_SIZE)
	root.add_child(preview)


func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count < 12:
		return false
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Pause capture viewport image is unavailable")
		quit(1)
		return true
	assert(image.get_size() == CAPTURE_SIZE)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://tmp"))
	var output_path := "res://tmp/pause-ui-landscape.png"
	assert(image.save_png(output_path) == OK)
	print("PAUSE UI CAPTURE PASS: ", output_path, " ", image.get_size())
	quit(0)
	return true
