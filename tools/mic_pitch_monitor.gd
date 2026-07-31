extends SceneTree

## Live microphone pitch readout. Sing into the mic and watch the note.
##
##   godot --path . --script res://tools/mic_pitch_monitor.gd
##
## This is the check that has to pass before any pitch highway gets drawn: if
## detection is wrong here, it will be wrong there too, only harder to see.

const RUN_SECONDS := 30.0

var _vox: VocalInput
var _elapsed := 0.0
var _next_print := 0.0
var _voiced_frames := 0
var _total_frames := 0


func _initialize() -> void:
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		print("audio/driver/enable_input is off - microphone capture cannot start")
		quit(1)
		return
	print("input devices: ", AudioServer.get_input_device_list())
	print("current: ", AudioServer.input_device)
	_vox = VocalInput.new()
	root.add_child(_vox)
	_vox.capture_failed.connect(
		func(reason): print("capture failed: ", reason))
	if not _vox.start():
		quit(1)
		return
	print("\nSing. Showing detected pitch for %d seconds.\n" % int(RUN_SECONDS))
	print("%-9s %-9s %-7s %-8s %s" % ["time", "note", "hz", "clarity", "level"])


func _process(delta: float) -> bool:
	_elapsed += delta
	_total_frames += 1
	var pitch := _vox.get_pitch()
	if bool(pitch["voiced"]):
		_voiced_frames += 1
	if _elapsed >= _next_print:
		_next_print = _elapsed + 0.15
		var clarity := float(pitch["clarity"])
		var bar := ""
		for i in range(int(clarity * 20.0)):
			bar += "#"
		if bool(pitch["voiced"]):
			print("%7.1fs  %-9s %-7.1f %-8.2f %s" % [
				_elapsed,
				PitchDetector.midi_note_name(float(pitch["midi"])),
				float(pitch["hz"]), clarity, bar])
		else:
			print("%7.1fs  %-9s" % [_elapsed, "--"])
	if _elapsed < RUN_SECONDS:
		return false
	_vox.stop()
	var voiced_pct := 100.0 * float(_voiced_frames) / float(maxi(_total_frames, 1))
	print("\nvoiced on %.0f%% of frames" % voiced_pct)
	return true
