extends SceneTree

## Plays a song and scrolls the vocal pitch highway against it, in landscape.
##
##   godot --path . --script res://tools/vocals_preview.gd
##
## The cursor is driven by a pre-analysed pitch track of the song's own
## isolated vocal stem, so it shows a real performance against the real chart
## with nobody singing. Press Escape or close the window to stop.
##
## Setup (tmp/ is gitignored - this is copyrighted audio):
##   ffmpeg -i vocals.opus -ac 1 -ar 16000 -c:a pcm_s16le tmp/vocals16k.wav
##   ffmpeg -i vocals.opus -ac 2 -ar 44100 -c:a pcm_s16le tmp/song.wav

const SIZE := Vector2i(1100, 620)
const WAV_PATH := "res://tmp/song.wav"
const MIDI_PATH := "res://tmp/notes.mid"
const PITCH_PATH := "res://tmp/rhiannon_pitch.json"
# How close the sung pitch has to be for a note to count as being held.
const HIT_SEMITONES := 1.5

var _track: VocalsTrack
var _player: AudioStreamPlayer
var _pitch_midi: Array = []
var _pitch_hop_ms := 30.0
var _notes: Array = []
var _progress := PackedFloat32Array()
var _started := false


func _load_wav(path: String) -> AudioStreamWAV:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var data := file.get_buffer(file.get_length())
	file.close()
	var pos := 12
	var channels := 2
	var rate := 44100
	while pos + 8 <= data.size():
		var chunk := data.slice(pos, pos + 4).get_string_from_ascii()
		var chunk_size := (
			data[pos + 4] | (data[pos + 5] << 8)
			| (data[pos + 6] << 16) | (data[pos + 7] << 24))
		if chunk == "fmt ":
			channels = data[pos + 10] | (data[pos + 11] << 8)
			rate = (
				data[pos + 12] | (data[pos + 13] << 8)
				| (data[pos + 14] << 16) | (data[pos + 15] << 24))
		elif chunk == "data":
			var stream := AudioStreamWAV.new()
			stream.format = AudioStreamWAV.FORMAT_16_BITS
			stream.stereo = channels == 2
			stream.mix_rate = rate
			stream.data = data.slice(pos + 8, pos + 8 + chunk_size)
			return stream
		pos += 8 + chunk_size + (chunk_size & 1)
	return null


func _initialize() -> void:
	for required in [WAV_PATH, MIDI_PATH]:
		if not FileAccess.file_exists(required):
			print("missing ", required, " - see header for setup")
			quit(1)
			return
	if DisplayServer.get_name() == "headless":
		print("Run windowed; this plays audio.")
		quit(1)
		return

	DisplayServer.window_set_size(SIZE)
	DisplayServer.window_set_title("Riffline - vokal onizleme")
	root.content_scale_size = SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = SIZE

	var midi_file := FileAccess.open(MIDI_PATH, FileAccess.READ)
	var parser = MidiParser.new()
	parser.parse_data(
		midi_file.get_buffer(midi_file.get_length()), "Expert", "guitar")
	midi_file.close()
	_notes = parser.vocal_parts.get("lead", [])
	if _notes.is_empty():
		print("chart has no lead vocal part")
		quit(1)
		return
	_progress.resize(_notes.size())

	if FileAccess.file_exists(PITCH_PATH):
		var raw := FileAccess.get_file_as_string(PITCH_PATH)
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary:
			_pitch_midi = parsed.get("midi", [])
			_pitch_hop_ms = float(parsed.get("hop_ms", 30.0))
		print("pitch track: %d points" % _pitch_midi.size())
	else:
		print("no pitch track - cursor will stay hidden")

	_track = VocalsTrack.new()
	_track.notes = _notes
	_track.phrases = parser.vocal_phrases
	_track.size = Vector2(SIZE)
	root.add_child(_track)

	var stream := _load_wav(WAV_PATH)
	if stream == null:
		print("could not read ", WAV_PATH)
		quit(1)
		return
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	root.add_child(_player)
	_player.call_deferred("play")
	_started = true
	print("playing - close the window or press Escape to stop")


func _process(_delta: float) -> bool:
	if not _started:
		return true
	if Input.is_key_pressed(KEY_ESCAPE):
		return true
	if not _player.playing and _player.get_playback_position() <= 0.0:
		return false
	var time_ms := _player.get_playback_position() * 1000.0
	_track.song_time_ms = time_ms

	# Sample the pre-analysed stem to drive the cursor.
	var midi := -1.0
	if _pitch_midi.size() > 0:
		var index := int(time_ms / _pitch_hop_ms)
		if index >= 0 and index < _pitch_midi.size():
			midi = float(_pitch_midi[index])
	_track.detected_voiced = midi > 0.0
	_track.detected_midi = midi

	# Fill each note as it is held, so the board reacts like it will in play.
	for i in range(_notes.size()):
		var note: Dictionary = _notes[i]
		var start_ms := float(note["time_ms"])
		var end_ms := float(note["end_ms"])
		if time_ms < start_ms or _progress[i] >= 1.0:
			continue
		var span := maxf(end_ms - start_ms, 1.0)
		var elapsed := clampf((time_ms - start_ms) / span, 0.0, 1.0)
		var matched := bool(note["non_pitched"])
		if not matched and midi > 0.0:
			matched = PitchDetector.pitch_class_distance(
				midi, float(note["midi_note"])) <= HIT_SEMITONES
		if matched:
			_progress[i] = maxf(_progress[i], elapsed)
	_track.note_progress = _progress

	if not _player.playing and time_ms > 1000.0:
		return true
	return false
