extends SceneTree

## On-screen microphone pitch monitor.
##
##   godot --path . --script res://tools/mic_pitch_monitor.gd
##
## Must run windowed: --headless swaps in the dummy audio driver and the
## microphone goes silent. Sing along with the prompts; the window closes itself
## when the routine finishes and prints a per-step summary.

const WINDOW_SIZE := Vector2i(560, 940)

var _view: Control
var _vox: VocalInput


func _initialize() -> void:
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		print("audio/driver/enable_input is off - microphone capture cannot start")
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		print("Running headless: audio input is unavailable. Run windowed.")
		quit(1)
		return

	DisplayServer.window_set_size(WINDOW_SIZE)
	DisplayServer.window_set_title("Riffline - mikrofon testi")
	root.content_scale_size = WINDOW_SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = WINDOW_SIZE

	print("input devices: ", AudioServer.get_input_device_list())
	print("current: ", AudioServer.input_device)

	_vox = VocalInput.new()
	root.add_child(_vox)
	_vox.capture_failed.connect(
		func(reason): print("capture failed: ", reason))
	if not _vox.start():
		quit(1)
		return

	_view = load("res://tools/mic_monitor_view.gd").new()
	_view.vocal_input = _vox
	_view.size = Vector2(WINDOW_SIZE)
	root.add_child(_view)


func _process(_delta: float) -> bool:
	if _view == null:
		return true
	if not _view.is_finished():
		return false
	_vox.stop()
	return true
