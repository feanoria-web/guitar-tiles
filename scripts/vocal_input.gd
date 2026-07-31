class_name VocalInput
extends Node

## Live microphone capture feeding PitchDetector on a worker thread.
##
## Detection costs ~10ms per window, which is most of a frame at 60fps, so it
## must never run on the main thread — that is the project's hard rule about the
## Android render thread. The main thread only drains the capture buffer, which
## is a memcpy, and reads the last published result.

signal pitch_updated(result: Dictionary)
signal capture_failed(reason: String)

const CAPTURE_BUS := "VocalCapture"
const DECIMATION := 3                  # 48kHz capture -> 16kHz analysis
const WINDOW_SAMPLES := 1024           # 64ms at 16kHz
const ANALYSIS_HZ := 25.0
# Ring buffer holds a little over one window of decimated audio.
const RING_SAMPLES := WINDOW_SAMPLES * 2

var _player: AudioStreamPlayer = null
var _capture: AudioEffectCapture = null
var _thread: Thread = null
var _mutex := Mutex.new()
var _semaphore := Semaphore.new()
var _running := false
var _bus_index := -1

# Guarded by _mutex.
var _ring := PackedFloat32Array()
var _ring_filled := 0
var _latest := {"hz": 0.0, "midi": -1.0, "clarity": 0.0, "voiced": false}
var _latest_dirty := false
var _input_level := 0.0


func is_running() -> bool:
	return _running


## True once the OS has granted microphone access. On Android this is only
## known after the user answers the runtime prompt.
static func has_permission() -> bool:
	if OS.get_name() != "Android":
		return true
	return OS.get_granted_permissions().has(
		"android.permission.RECORD_AUDIO")


static func request_permission() -> void:
	if OS.get_name() == "Android":
		OS.request_permission("android.permission.RECORD_AUDIO")


func start() -> bool:
	if _running:
		return true
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		capture_failed.emit("audio_input_disabled")
		return false
	if not has_permission():
		request_permission()
		capture_failed.emit("permission_pending")
		return false

	_bus_index = AudioServer.get_bus_index(CAPTURE_BUS)
	if _bus_index < 0:
		_bus_index = AudioServer.bus_count
		AudioServer.add_bus(_bus_index)
		AudioServer.set_bus_name(_bus_index, CAPTURE_BUS)
	# Silent: this bus exists to be analysed, not heard. Monitoring the mic
	# through the speakers during a song would feed straight back in.
	AudioServer.set_bus_mute(_bus_index, true)
	AudioServer.set_bus_send(_bus_index, "Master")

	_capture = null
	for effect_index in range(AudioServer.get_bus_effect_count(_bus_index)):
		var existing := AudioServer.get_bus_effect(_bus_index, effect_index)
		if existing is AudioEffectCapture:
			_capture = existing
			break
	if _capture == null:
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.2
		AudioServer.add_bus_effect(_bus_index, _capture)

	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = CAPTURE_BUS
	add_child(_player)
	# start() may be called before this node is in the tree, and an
	# AudioStreamPlayer refuses to play until it is.
	_player.call_deferred("play")

	_ring = PackedFloat32Array()
	_ring.resize(RING_SAMPLES)
	_ring_filled = 0
	_running = true
	_thread = Thread.new()
	_thread.start(_analysis_loop)
	set_process(true)
	return true


func stop() -> void:
	if not _running:
		return
	_running = false
	_semaphore.post()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	if is_instance_valid(_player):
		_player.stop()
		_player.queue_free()
	_player = null
	set_process(false)


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	if not _running or _capture == null:
		return
	var available := _capture.get_frames_available()
	if available > 0:
		var frames := _capture.get_buffer(available)
		_push_frames(frames)
	if _latest_dirty:
		_mutex.lock()
		var snapshot := _latest.duplicate()
		_latest_dirty = false
		_mutex.unlock()
		pitch_updated.emit(snapshot)


## Mixes to mono and decimates before storing, so the worker only ever sees the
## 16kHz signal and the ring stays small.
func _push_frames(frames: PackedVector2Array) -> void:
	var count := frames.size()
	if count < DECIMATION:
		return
	var produced := count / DECIMATION
	var decimated := PackedFloat32Array()
	decimated.resize(produced)
	for i in range(produced):
		var total := 0.0
		var base := i * DECIMATION
		for j in range(DECIMATION):
			var frame := frames[base + j]
			total += (frame.x + frame.y) * 0.5
		decimated[i] = total / float(DECIMATION)

	# Track input loudness separately from pitch. Without it there is no way to
	# tell "nothing reached the microphone" apart from "sound arrived but was
	# rejected as unvoiced", which are very different problems.
	var sum_squares := 0.0
	for value in decimated:
		sum_squares += value * value
	var rms := sqrt(sum_squares / float(maxi(produced, 1)))

	_mutex.lock()
	# Fast attack, slow release, so a meter built on this stays readable.
	_input_level = maxf(rms, _input_level * 0.80)
	for value in decimated:
		if _ring_filled < RING_SAMPLES:
			_ring[_ring_filled] = value
			_ring_filled += 1
		else:
			# Drop the oldest half rather than shifting every sample.
			var keep := RING_SAMPLES / 2
			for k in range(keep):
				_ring[k] = _ring[k + keep]
			_ring_filled = keep
			_ring[_ring_filled] = value
			_ring_filled += 1
	var ready := _ring_filled >= WINDOW_SAMPLES
	_mutex.unlock()
	if ready:
		_semaphore.post()


func _analysis_loop() -> void:
	var window := PackedFloat32Array()
	window.resize(WINDOW_SAMPLES)
	var min_interval_usec := int(1_000_000.0 / ANALYSIS_HZ)
	var last_run := 0
	while true:
		_semaphore.wait()
		if not _running:
			return
		var now := Time.get_ticks_usec()
		if now - last_run < min_interval_usec:
			continue
		last_run = now

		_mutex.lock()
		var have := _ring_filled >= WINDOW_SAMPLES
		if have:
			# Analyse the most recent window.
			var start := _ring_filled - WINDOW_SAMPLES
			for i in range(WINDOW_SAMPLES):
				window[i] = _ring[start + i]
		_mutex.unlock()
		if not have:
			continue

		var result := PitchDetector.detect(
			window, 48000.0 / float(DECIMATION))
		_mutex.lock()
		_latest = result
		_latest_dirty = true
		_mutex.unlock()


## Smoothed microphone loudness, 0..1-ish. Independent of pitch detection.
func get_input_level() -> float:
	_mutex.lock()
	var level := _input_level
	_mutex.unlock()
	return level


## Last published result. Safe to poll from the main thread every frame.
func get_pitch() -> Dictionary:
	_mutex.lock()
	var snapshot := _latest.duplicate()
	_mutex.unlock()
	return snapshot
