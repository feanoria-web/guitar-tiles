extends Control

const ChartParserScript = preload("res://scripts/chart_parser.gd")
const MidiParserScript = preload("res://scripts/midi_parser.gd")
const SngLoaderScript = preload("res://scripts/sng_loader.gd")
const PlayabilityScript = preload("res://scripts/playability.gd")

# --- Config ---
const APPROACH_TIME_MS := 2500.0
const HIT_WINDOW_MS := 150.0
const HIT_LINE_RATIO := 0.85
const HIGHWAY_RATIO := 0.60
const HIT_LINGER_MS := 1200.0  # how long hit notes stay visible past hit line

const GUITAR_COLORS: Array[Color] = [
	Color(0.18, 0.85, 0.18),  Color(0.9, 0.15, 0.15),
	Color(0.9, 0.85, 0.1),    Color(0.25, 0.5, 1.0),
	Color(1.0, 0.55, 0.05),
]
const PIANO_COLORS: Array[Color] = [
	Color(0.18, 0.85, 0.18),  Color(0.9, 0.15, 0.15),
	Color(0.9, 0.85, 0.1),    Color(0.35, 0.55, 1.0),
]
const BG_COLOR := Color(0.06, 0.06, 0.08)
const LANE_BG := Color(0.12, 0.12, 0.15, 0.55)
const LANE_BORDER := Color(0.22, 0.22, 0.28, 0.4)
const HIT_LINE_COLOR := Color(1, 1, 1, 0.6)

const ESSENTIAL_STEMS: Array[String] = ["song", "guitar", "rhythm", "vocals"]

# Note states: 0=active, 1=hit(darkened,scrolling), 2=missed, 3=sustain_holding
var notes: Array = []
var lyric_phrases: Array = []
var note_state: PackedByteArray = PackedByteArray()
var score: int = 0
var combo: int = 0
var max_combo: int = 0
var audio_offset_ms: float = 0.0
var song_started: bool = false
var song_time_ms: float = 0.0
var first_visible_idx: int = 0
var current_phrase_idx: int = 0
var lane_count: int = 5
var lane_colors: Array[Color] = []
var _start_ticks: int = 0
var _first_hit_logged: bool = false
var _play_call_time_ms: int = 0
var _hit_log_count: int = 0
var _chart_offset_ms: float = 0.0

# Decode pipeline (AudioEffectCapture → single AudioStreamWAV)
var _decode_bus_idx: int = -1
var _decode_capture: AudioEffectCapture = null
var _decode_players: Array[AudioStreamPlayer] = []
var _decode_pcm: PackedVector2Array = PackedVector2Array()
var _decode_start_ms: int = 0
var _decode_longest_sec: float = 0.0
var _cache_path: String = ""
var _countdown: float = -1.0

# Sustain hold tracking
var lane_pressed: Array = []   # bool per lane
var held_sustain: Array = []   # note index per lane (-1 = none)

# Hit flash effects
var hit_effects: Array = []

# Loading
var is_loading: bool = false
var loading_status: String = ""

# Nodes
var audio_players: Array[AudioStreamPlayer] = []
var master_player: AudioStreamPlayer = null
var hud_layer: CanvasLayer
var score_label: Label
var combo_label: Label
var lyric_rtl: RichTextLabel
var loading_label: Label
var warning_label: Label
var progress_bar: ProgressBar
var offset_slider: HSlider
var offset_label: Label

# Note style caches
var note_styles: Array[StyleBoxFlat] = []
var note_styles_hit: Array[StyleBoxFlat] = []
var sustain_styles: Array[StyleBoxFlat] = []
var sustain_styles_hit: Array[StyleBoxFlat] = []
var sustain_styles_hold: Array[StyleBoxFlat] = []

static var song_source: String = ""
static var song_difficulty: String = "Expert"
static var song_mode: String = "guitar"
static var song_preset: String = "Rahat"

func _ready() -> void:
	if ClassDB.class_exists("AudioStreamOpus"):
		print("AUDIO: opus extension OK")
	else:
		push_error("AUDIO: opus extension MISSING — AudioStreamOpus class not found!")

	if song_mode == "piano":
		lane_count = 4
		lane_colors.assign(PIANO_COLORS)
	else:
		lane_count = 5
		lane_colors.assign(GUITAR_COLORS)

	lane_pressed.resize(lane_count)
	held_sustain.resize(lane_count)
	for i in range(lane_count):
		lane_pressed[i] = false
		held_sustain[i] = -1

	_build_note_styles()
	_build_ui()
	_load_song()

# --- StyleBoxFlat caches ---

func _build_note_styles() -> void:
	note_styles.clear()
	note_styles_hit.clear()
	sustain_styles.clear()
	sustain_styles_hit.clear()
	sustain_styles_hold.clear()
	for c in lane_colors:
		# Active note
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(6)
		sb.border_color = c.lightened(0.35)
		sb.set_border_width_all(2)
		note_styles.append(sb)

		# Hit note (darkened)
		var sh := StyleBoxFlat.new()
		sh.bg_color = c.darkened(0.45)
		sh.set_corner_radius_all(6)
		sh.border_color = c.darkened(0.25)
		sh.set_border_width_all(1)
		note_styles_hit.append(sh)

		# Sustain tail (active)
		var ss := StyleBoxFlat.new()
		ss.bg_color = c * Color(1, 1, 1, 0.4)
		ss.set_corner_radius_all(3)
		sustain_styles.append(ss)

		# Sustain tail (hit/released)
		var ssh := StyleBoxFlat.new()
		ssh.bg_color = c.darkened(0.45) * Color(1, 1, 1, 0.35)
		ssh.set_corner_radius_all(3)
		sustain_styles_hit.append(ssh)

		# Sustain tail (being held — brighter)
		var sshold := StyleBoxFlat.new()
		sshold.bg_color = c * Color(1, 1, 1, 0.65)
		sshold.set_corner_radius_all(3)
		sshold.border_color = c.lightened(0.2)
		sshold.set_border_width_all(1)
		sustain_styles_hold.append(sshold)

# --- UI ---

func _build_ui() -> void:
	var theme := _create_theme()
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)

	var hud_root := Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.theme = theme
	hud_layer.add_child(hud_root)

	score_label = Label.new()
	score_label.text = "Score: 0"
	score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	score_label.offset_left = 16; score_label.offset_top = 12
	score_label.add_theme_font_size_override("font_size", 28)
	hud_root.add_child(score_label)

	var back_btn := Button.new()
	back_btn.text = "Menu"
	back_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	back_btn.offset_left = 16; back_btn.offset_top = 48
	back_btn.size = Vector2(72, 30)
	back_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	hud_root.add_child(back_btn)

	combo_label = Label.new()
	combo_label.text = ""
	combo_label.add_theme_font_size_override("font_size", 44)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.anchor_left = 0.3; combo_label.anchor_right = 0.7
	combo_label.anchor_top = 0.0; combo_label.offset_top = 8
	combo_label.size.y = 55
	combo_label.pivot_offset = Vector2(combo_label.size.x / 2.0, combo_label.size.y / 2.0)
	hud_root.add_child(combo_label)

	progress_bar = ProgressBar.new()
	progress_bar.show_percentage = false
	progress_bar.anchor_left = 0.35; progress_bar.anchor_right = 0.65
	progress_bar.anchor_top = 0.0; progress_bar.offset_top = 62
	progress_bar.size.y = 6
	hud_root.add_child(progress_bar)

	lyric_rtl = RichTextLabel.new()
	lyric_rtl.bbcode_enabled = true
	lyric_rtl.fit_content = true
	lyric_rtl.scroll_active = false
	lyric_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lyric_rtl.anchor_left = 0.1; lyric_rtl.anchor_right = 0.9
	lyric_rtl.anchor_top = HIT_LINE_RATIO + 0.02
	lyric_rtl.anchor_bottom = HIT_LINE_RATIO + 0.08
	lyric_rtl.add_theme_font_size_override("normal_font_size", 24)
	lyric_rtl.add_theme_color_override("default_color", Color(0.5, 0.5, 0.55))
	hud_root.add_child(lyric_rtl)

	offset_label = Label.new()
	offset_label.text = "Offset: 0 ms"
	offset_label.add_theme_font_size_override("font_size", 14)
	offset_label.anchor_left = 1.0; offset_label.anchor_right = 1.0; offset_label.anchor_top = 1.0
	offset_label.offset_left = -170; offset_label.offset_top = -62
	hud_root.add_child(offset_label)

	offset_slider = HSlider.new()
	offset_slider.min_value = -200; offset_slider.max_value = 200; offset_slider.step = 5; offset_slider.value = 0
	offset_slider.anchor_left = 1.0; offset_slider.anchor_right = 1.0; offset_slider.anchor_top = 1.0
	offset_slider.offset_left = -170; offset_slider.offset_top = -38
	offset_slider.size = Vector2(150, 20)
	offset_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	offset_slider.value_changed.connect(_on_offset_changed)
	hud_root.add_child(offset_slider)

	loading_label = Label.new()
	loading_label.text = ""
	loading_label.add_theme_font_size_override("font_size", 32)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	loading_label.size = Vector2(500, 50)
	loading_label.offset_left = -250; loading_label.offset_top = -25
	hud_root.add_child(loading_label)

	warning_label = Label.new()
	warning_label.text = ""
	warning_label.add_theme_font_size_override("font_size", 22)
	warning_label.add_theme_color_override("font_color", Color(1, 0.3, 0.2))
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	warning_label.size = Vector2(600, 40)
	warning_label.offset_left = -300; warning_label.offset_top = 60
	warning_label.visible = false
	hud_root.add_child(warning_label)

func _create_theme() -> Theme:
	var t := Theme.new()
	t.set_color("font_color", "Label", Color(0.9, 0.9, 0.95))
	t.set_color("font_color", "Button", Color(0.85, 0.85, 0.9))
	t.set_font_size("font_size", "Label", 20)
	t.set_font_size("font_size", "Button", 16)
	return t

# --- Song loading ---

func _load_song() -> void:
	var source := song_source if song_source != "" else "res://notes.chart"
	var difficulty := song_difficulty if song_difficulty != "" else "Expert"
	var sng_loader: RefCounted = null
	var parse_ok := false
	var parsed_notes: Array = []
	var parsed_lyrics: Array = []
	var parsed_resolution: int = 480

	var chart_offset_sec := 0.0

	if source.ends_with(".sng"):
		sng_loader = SngLoaderScript.new()
		if not sng_loader.load_sng(source):
			push_error("Game: failed to load .sng"); return

		# Priority: .chart first, then .mid
		if sng_loader.has_chart():
			var parser = ChartParserScript.new()
			var chart_text: String = sng_loader.get_chart_text()
			parse_ok = parser.parse_text(chart_text, difficulty)
			if parse_ok:
				parsed_notes = parser.notes
				parsed_lyrics = parser.lyric_phrases
				parsed_resolution = parser.resolution
				chart_offset_sec = parser.audio_offset_sec
				print("Game: parsed .chart from .sng")
		if not parse_ok and sng_loader.has_midi():
			var midi_parser = MidiParserScript.new()
			var midi_data: PackedByteArray = sng_loader.get_midi_data()
			parse_ok = midi_parser.parse_data(midi_data, difficulty)
			if parse_ok:
				parsed_notes = midi_parser.notes
				parsed_lyrics = midi_parser.lyric_phrases
				parsed_resolution = midi_parser.resolution
				print("Game: parsed .mid from .sng")
		if not parse_ok:
			push_error("Game: no chart or midi in .sng"); return

	elif source.ends_with(".chart"):
		var parser = ChartParserScript.new()
		parse_ok = parser.parse_file(source, difficulty)
		if not parse_ok:
			push_error("Game: failed to parse .chart"); return
		parsed_notes = parser.notes
		parsed_lyrics = parser.lyric_phrases
		parsed_resolution = parser.resolution
		chart_offset_sec = parser.audio_offset_sec

	elif source.ends_with(".mid"):
		var midi_parser = MidiParserScript.new()
		parse_ok = midi_parser.parse_file(source, difficulty)
		if not parse_ok:
			push_error("Game: failed to parse .mid"); return
		parsed_notes = midi_parser.notes
		parsed_lyrics = midi_parser.lyric_phrases
		parsed_resolution = midi_parser.resolution

	else:
		push_error("Game: unknown file type: %s" % source); return

	_chart_offset_ms = chart_offset_sec * 1000.0
	if absf(_chart_offset_ms) > 0.1:
		print("Game: chart offset = %.1f ms" % _chart_offset_ms)

	notes = parsed_notes
	lyric_phrases = parsed_lyrics

	# Apply playability processing
	var playability = PlayabilityScript.new()
	playability.apply_preset(song_preset)
	notes = playability.process(notes, parsed_resolution, lane_count)

	if song_mode == "piano":
		_merge_piano_lanes()

	note_state.resize(notes.size())
	note_state.fill(0)
	first_visible_idx = 0
	current_phrase_idx = 0

	print("Game: [%s][%s] %d notes, %d phrases" % [song_mode, difficulty, notes.size(), lyric_phrases.size()])

	is_loading = true
	loading_status = "Ses hazirlaniyor..."
	if sng_loader:
		var tmp_dir := "user://sng_temp"
		_clear_dir(tmp_dir)
		sng_loader.extract_to_dir(tmp_dir)
		_prepare_audio(tmp_dir)
	else:
		_prepare_audio(source.get_base_dir())

func _merge_piano_lanes() -> void:
	var time_set := {}
	for n in notes:
		if int(n["lane"]) == 3:
			time_set["%.1f" % float(n["time_ms"])] = true
	var merged: Array = []
	for n in notes:
		if int(n["lane"]) == 4:
			var key := "%.1f" % float(n["time_ms"])
			if time_set.has(key):
				continue
			n["lane"] = 3
			time_set[key] = true
		merged.append(n)
	notes = merged

# --- Audio decode pipeline ---

func _prepare_audio(dir_path: String) -> void:
	print("Audio: scanning stems in %s" % dir_path)

	# List all audio files
	var all_audio: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir():
				var fl := fname.to_lower()
				if fl.ends_with(".opus") or fl.ends_with(".ogg") or fl.ends_with(".mp3"):
					all_audio.append(fname)
			fname = dir.get_next()
		dir.list_dir_end()
	print("Audio: found files: %s" % str(all_audio))

	# Categorize: song.*, preview.*, stems
	var song_files: Array[String] = []
	var stem_files: Array[String] = []
	for af: String in all_audio:
		var base := af.get_basename().to_lower()
		if base == "preview":
			print("Audio: skipping preview: %s" % af)
			continue
		if base == "song":
			song_files.append(af)
		else:
			stem_files.append(af)

	# Determine which files to use
	var to_load: Array[String] = []
	if stem_files.size() >= 2:
		to_load = stem_files
		print("Audio: STEM MODE — %d stems, skipping song.*" % stem_files.size())
	elif song_files.size() > 0:
		to_load.append(song_files[0])
		print("Audio: SONG MODE — %s" % song_files[0])
	elif stem_files.size() == 1:
		to_load.append(stem_files[0])
		print("Audio: SINGLE STEM — %s" % stem_files[0])
	elif all_audio.size() > 0:
		to_load.append(all_audio[0])
		print("Audio: FALLBACK — %s" % all_audio[0])

	if to_load.is_empty():
		_show_audio_error("Ses dosyasi bulunamadi!")
		is_loading = false
		return

	# Build cache key from file names + dir
	var cache_key := dir_path
	for f2: String in to_load:
		cache_key += "|" + f2
	_cache_path = "user://cache/" + cache_key.md5_text() + ".pcm"

	# Try cache
	var cached := _load_from_cache()
	if cached:
		_setup_final_player(cached)
		return

	# No cache — load streams and start decode via AudioEffectCapture
	var streams: Array = []
	for i in range(to_load.size()):
		var stem_fname: String = to_load[i]
		loading_status = "Kanal yukleniyor %s (%d/%d)..." % [stem_fname, i + 1, to_load.size()]
		var stream = _load_audio_stream(dir_path.path_join(stem_fname))
		if stream:
			streams.append({"name": stem_fname, "stream": stream})

	if streams.is_empty():
		_show_audio_error("Hicbir ses dosyasi yuklenemedi!")
		is_loading = false
		return

	# Set up decode bus (silent, with capture)
	_decode_bus_idx = AudioServer.bus_count
	AudioServer.set_bus_count(_decode_bus_idx + 1)
	AudioServer.set_bus_name(_decode_bus_idx, "Decode")
	AudioServer.set_bus_volume_db(_decode_bus_idx, -80.0)
	_decode_capture = AudioEffectCapture.new()
	_decode_capture.buffer_length = 2.0
	AudioServer.add_bus_effect(_decode_bus_idx, _decode_capture)

	# Play all stems on decode bus simultaneously
	_decode_players.clear()
	_decode_pcm.clear()
	_decode_longest_sec = 0.0
	_decode_start_ms = Time.get_ticks_msec()

	for s in streams:
		var player := AudioStreamPlayer.new()
		player.stream = s["stream"]
		player.bus = "Decode"
		add_child(player)
		_decode_players.append(player)
		var length: float = s["stream"].get_length() if s["stream"].has_method("get_length") else 0.0
		if length > _decode_longest_sec:
			_decode_longest_sec = length
		player.play()
		print("Decode: started '%s' on Decode bus (length=%.1fs)" % [s["name"], length])

	print("Decode: %d stems decoding, estimated %.0fs" % [_decode_players.size(), _decode_longest_sec])
	loading_status = "Ses cozuluyor... 0%%"


func _decode_step() -> void:
	# Pull captured frames
	var available := _decode_capture.get_frames_available()
	if available > 0:
		var frames := _decode_capture.get_buffer(available)
		_decode_pcm.append_array(frames)

	# Check progress
	var all_done := true
	var max_pos := 0.0
	for p in _decode_players:
		if p.playing:
			all_done = false
			max_pos = maxf(max_pos, p.get_playback_position())
		else:
			max_pos = maxf(max_pos, _decode_longest_sec)

	if _decode_longest_sec > 0:
		var pct := clampf(max_pos / _decode_longest_sec * 100.0, 0.0, 100.0)
		loading_status = "Ses cozuluyor... %d%%" % int(pct)

	if all_done:
		# Grab any remaining frames
		available = _decode_capture.get_frames_available()
		if available > 0:
			_decode_pcm.append_array(_decode_capture.get_buffer(available))
		_finalize_decode()

func _finalize_decode() -> void:
	var decode_ms := Time.get_ticks_msec() - _decode_start_ms
	var frame_count := _decode_pcm.size()
	print("Decode: captured %d frames (%.1f sec) in %dms" % [
		frame_count, float(frame_count) / 48000.0, decode_ms])

	# Clean up decode players and bus
	for p in _decode_players:
		p.stop()
		p.queue_free()
	_decode_players.clear()
	if _decode_bus_idx >= 0:
		AudioServer.remove_bus(_decode_bus_idx)
		_decode_bus_idx = -1
	_decode_capture = null

	if frame_count == 0:
		_show_audio_error("Ses cozulemedi — bos PCM!")
		is_loading = false
		return

	loading_status = "Ses birlestiriliyor..."

	# Find peak for normalization (only scale down if clipping)
	var peak: float = 0.001
	for i in range(frame_count):
		peak = maxf(peak, absf(_decode_pcm[i].x))
		peak = maxf(peak, absf(_decode_pcm[i].y))
	var gain := 1.0 / peak if peak > 1.0 else 1.0
	print("Decode: peak=%.3f gain=%.3f" % [peak, gain])

	# Convert to 16-bit stereo PCM
	var wav_data := PackedByteArray()
	wav_data.resize(frame_count * 4)
	for i in range(frame_count):
		var l := clampi(int(_decode_pcm[i].x * gain * 32767.0), -32768, 32767)
		var r := clampi(int(_decode_pcm[i].y * gain * 32767.0), -32768, 32767)
		wav_data.encode_s16(i * 4, l)
		wav_data.encode_s16(i * 4 + 2, r)
	_decode_pcm.clear()

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 48000
	wav.data = wav_data

	# Save to cache
	_save_to_cache(wav_data)

	_setup_final_player(wav)

func _setup_final_player(wav: AudioStreamWAV) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = wav
	add_child(player)
	audio_players.clear()
	audio_players.append(player)
	master_player = player
	print("Audio: SINGLE player ready — WAV %d frames, %.1fs, 1 player" % [
		wav.data.size() / 4, float(wav.data.size() / 4) / 48000.0])

	is_loading = false
	_countdown = 3.0

func _save_to_cache(wav_data: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute("user://cache")
	var f := FileAccess.open(_cache_path, FileAccess.WRITE)
	if f:
		f.store_32(48000)
		f.store_32(wav_data.size())
		f.store_buffer(wav_data)
		f.close()
		print("Cache: SAVED %s (%d bytes, %.1f MB)" % [
			_cache_path, wav_data.size(), float(wav_data.size()) / 1048576.0])
	else:
		push_error("Cache: failed to save %s" % _cache_path)

func _load_from_cache() -> AudioStreamWAV:
	var f := FileAccess.open(_cache_path, FileAccess.READ)
	if f == null:
		print("Cache: MISS %s" % _cache_path)
		return null
	var mix_rate_val := f.get_32()
	var data_size := f.get_32()
	if data_size == 0 or data_size > 200_000_000:
		f.close()
		print("Cache: CORRUPT (size=%d) %s" % [data_size, _cache_path])
		return null
	var wav_data := f.get_buffer(data_size)
	f.close()
	if wav_data.size() != data_size:
		print("Cache: TRUNCATED %s" % _cache_path)
		return null
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = mix_rate_val
	wav.data = wav_data
	print("Cache: HIT %s (%d bytes, %.1f MB)" % [
		_cache_path, data_size, float(data_size) / 1048576.0])
	return wav

func _clear_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			dir.remove(fname)
		fname = dir.get_next()
	dir.list_dir_end()

func _load_audio_stream(path: String) -> AudioStream:
	var fname := path.get_file()
	var ext := fname.get_extension().to_lower()
	var loader_name := ""
	var start_ms := Time.get_ticks_msec()
	var stream: AudioStream = null
	var mix_rate := AudioServer.get_mix_rate()

	if ext == "ogg":
		# Check for opus-inside-ogg via magic bytes
		var probe := FileAccess.open(path, FileAccess.READ)
		if probe:
			var header := probe.get_buffer(mini(40, probe.get_length()))
			probe.close()
			var has_opus_head := false
			for i in range(header.size() - 7):
				if header[i] == 0x4F and header[i+1] == 0x70 and header[i+2] == 0x75 and header[i+3] == 0x73 \
					and header[i+4] == 0x48 and header[i+5] == 0x65 and header[i+6] == 0x61 and header[i+7] == 0x64:
					has_opus_head = true
					break
			if has_opus_head:
				print("Audio: [%s] OGG container contains Opus data — routing to opus loader" % fname)
				stream = _load_opus_stream(path)
				loader_name = "opus (ogg container)"
				var elapsed := Time.get_ticks_msec() - start_ms
				_log_audio_load(fname, ext, loader_name, mix_rate, stream, elapsed)
				return stream

		loader_name = "native OggVorbis"
		stream = AudioStreamOggVorbis.load_from_file(path)
		if stream == null:
			var err_msg := "Audio: OGG load FAILED: %s" % path
			push_error(err_msg)
			_show_audio_error(err_msg)
	elif ext == "mp3":
		loader_name = "native MP3"
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var mp3 := AudioStreamMP3.new()
			mp3.data = f.get_buffer(f.get_length())
			f.close()
			stream = mp3
		else:
			var err_msg := "Audio: MP3 open FAILED: %s" % path
			push_error(err_msg)
			_show_audio_error(err_msg)
	elif ext == "opus":
		loader_name = "audio-stream-plus (opus)"
		stream = _load_opus_stream(path)
	else:
		var err_msg := "Audio: unsupported format '.%s': %s" % [ext, path]
		push_error(err_msg)
		_show_audio_error(err_msg)
		return null

	var elapsed := Time.get_ticks_msec() - start_ms
	_log_audio_load(fname, ext, loader_name, mix_rate, stream, elapsed)
	return stream

func _load_opus_stream(path: String) -> AudioStream:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		var err_msg := "Audio: cannot open opus file: %s" % path
		push_error(err_msg)
		_show_audio_error(err_msg)
		return null
	var data := f.get_buffer(f.get_length())
	f.close()
	if not ClassDB.class_exists("AudioStreamOpus"):
		var err_msg := "Audio: AudioStreamOpus class not found — GDExtension not loaded!"
		push_error(err_msg)
		_show_audio_error(err_msg)
		return null
	var opus_stream = ClassDB.instantiate("AudioStreamOpus")
	if opus_stream == null:
		var err_msg := "Audio: AudioStreamOpus instantiate failed"
		push_error(err_msg)
		_show_audio_error(err_msg)
		return null
	opus_stream.set("data", data)
	return opus_stream

func _log_audio_load(fname: String, ext: String, loader: String, mix_rate: float, stream: AudioStream, elapsed_ms: int) -> void:
	if stream:
		var sample_rate := "unknown"
		var channels := "unknown"
		if stream is AudioStreamOggVorbis:
			sample_rate = "native"
			channels = "native"
		elif stream is AudioStreamMP3:
			sample_rate = "native"
			channels = "native"
		elif stream is AudioStreamWAV:
			sample_rate = str(int((stream as AudioStreamWAV).mix_rate))
			channels = "stereo" if (stream as AudioStreamWAV).stereo else "mono"
		else:
			# AudioStreamOpus or other extension types
			sample_rate = "48000 (opus default)"
			channels = "stereo (opus default)"
		print("Audio: LOADED [%s] ext=%s loader=%s sample_rate=%s channels=%s project_mix_rate=%d elapsed=%dms" % [
			fname, ext, loader, sample_rate, channels, int(mix_rate), elapsed_ms])
	else:
		var err_msg := "Audio: FAILED [%s] ext=%s loader=%s elapsed=%dms" % [fname, ext, loader, elapsed_ms]
		push_error(err_msg)
		_show_audio_error(err_msg)

func _show_audio_error(msg: String) -> void:
	if warning_label:
		warning_label.text = msg
		warning_label.visible = true

# --- Playback ---

func _start_playback() -> void:
	song_started = true
	_first_hit_logged = false
	_hit_log_count = 0
	_start_ticks = Time.get_ticks_msec()
	_play_call_time_ms = _start_ticks
	master_player.play()
	print("Sync: play() at ticks=%d, 1 player, chart_offset=%.1fms" % [
		_play_call_time_ms, _chart_offset_ms])

func _get_song_time_ms() -> float:
	if not master_player:
		return 0.0
	if not master_player.playing:
		return song_time_ms
	var t := master_player.get_playback_position()
	t += AudioServer.get_time_since_last_mix()
	t -= AudioServer.get_output_latency()
	return t * 1000.0 + _chart_offset_ms + audio_offset_ms

# --- Main loop ---

func _process(_delta: float) -> void:
	# State: decoding stems via AudioEffectCapture
	if is_loading:
		if _decode_capture:
			_decode_step()
		loading_label.text = loading_status
		queue_redraw()
		return

	# State: countdown before play
	if _countdown > 0:
		_countdown -= _delta
		loading_label.text = str(ceili(_countdown))
		queue_redraw()
		if _countdown <= 0:
			loading_label.text = ""
			_start_playback()
		return

	loading_label.text = ""
	if not song_started:
		return

	song_time_ms = _get_song_time_ms()

	# Mark active notes past hit window as missed
	for idx in range(first_visible_idx, notes.size()):
		var t: float = notes[idx]["time_ms"]
		if t > song_time_ms + HIT_WINDOW_MS:
			break
		if note_state[idx] == 0 and song_time_ms - t > HIT_WINDOW_MS:
			note_state[idx] = 2
			combo = 0

	# Advance first_visible_idx past notes way off-screen
	while first_visible_idx < notes.size():
		var t: float = notes[first_visible_idx]["time_ms"]
		if song_time_ms - t < APPROACH_TIME_MS + HIT_LINGER_MS:
			break
		first_visible_idx += 1

	# Update sustain holds
	_update_sustains()

	# Decay hit flash effects
	var i := 0
	while i < hit_effects.size():
		hit_effects[i]["alpha"] -= 0.045
		if float(hit_effects[i]["alpha"]) <= 0:
			hit_effects.remove_at(i)
		else:
			i += 1

	_update_lyrics()
	_update_hud()
	queue_redraw()

func _update_sustains() -> void:
	for lane in range(lane_count):
		var idx: int = held_sustain[lane]
		if idx < 0:
			continue
		var n = notes[idx]
		var end_time: float = float(n["time_ms"]) + float(n["duration_ms"])

		if not lane_pressed[lane]:
			# Released early — becomes hit (darkened, scrolling)
			note_state[idx] = 1
			held_sustain[lane] = -1
		elif song_time_ms >= end_time:
			# Sustain completed
			note_state[idx] = 1
			held_sustain[lane] = -1
			score += 25 * combo

func _update_lyrics() -> void:
	if lyric_phrases.is_empty():
		lyric_rtl.text = ""; return
	while current_phrase_idx < lyric_phrases.size():
		if float(lyric_phrases[current_phrase_idx]["end_ms"]) >= song_time_ms:
			break
		current_phrase_idx += 1
	if current_phrase_idx < lyric_phrases.size():
		var phrase = lyric_phrases[current_phrase_idx]
		var start: float = phrase["start_ms"]
		var end: float = phrase["end_ms"]
		if song_time_ms >= start - 300 and song_time_ms <= end:
			lyric_rtl.text = _build_highlighted_bbcode(phrase)
			return
	lyric_rtl.text = ""

func _build_highlighted_bbcode(phrase: Dictionary) -> String:
	var full_text: String = phrase["text"]
	var syllables: Array = phrase["syllables"]
	if syllables.is_empty():
		return "[center]" + full_text + "[/center]"
	var sung_end := 0
	for syl in syllables:
		if float(syl["time_ms"]) <= song_time_ms:
			sung_end = int(syl["char_end"])
		else:
			break
	return "[center][color=#FFD700]%s[/color][color=#666670]%s[/color][/center]" % [
		full_text.substr(0, sung_end), full_text.substr(sung_end)]

func _update_hud() -> void:
	score_label.text = "Score: %d" % score
	combo_label.text = "%d Combo" % combo if combo >= 2 else ""
	if notes.size() > 0:
		var last_time: float = notes[notes.size() - 1]["time_ms"]
		progress_bar.value = clampf(song_time_ms / last_time * 100.0, 0.0, 100.0)

# --- Drawing ---

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), BG_COLOR)
	if is_loading or _countdown > 0:
		return

	var lw := _lane_width()
	var ls := _lanes_start_x()
	var hit_y := vp.y * HIT_LINE_RATIO

	# Lane backgrounds
	for idx in range(lane_count):
		var x := ls + idx * lw
		draw_rect(Rect2(x, 0, lw, vp.y), LANE_BG)
		draw_line(Vector2(x, 0), Vector2(x, vp.y), LANE_BORDER, 1.0)
	draw_line(Vector2(ls + lane_count * lw, 0), Vector2(ls + lane_count * lw, vp.y), LANE_BORDER, 1.0)

	# Hit line
	draw_line(Vector2(ls, hit_y), Vector2(ls + lane_count * lw, hit_y), HIT_LINE_COLOR, 2.0)

	# Hit zone circles
	for idx in range(lane_count):
		var cx := ls + (idx + 0.5) * lw
		var r := lw * 0.28
		var base_alpha := 0.25
		# Brighten if lane is pressed
		if lane_pressed[idx]:
			base_alpha = 0.5
		draw_circle(Vector2(cx, hit_y), r, lane_colors[idx] * Color(1, 1, 1, base_alpha))
		draw_arc(Vector2(cx, hit_y), r, 0, TAU, 32, lane_colors[idx] * Color(1, 1, 1, base_alpha + 0.2), 2.0)

	# Hit flash effects
	for eff in hit_effects:
		var eidx: int = eff["lane"]
		var ea: float = eff["alpha"]
		draw_circle(Vector2(ls + (eidx + 0.5) * lw, hit_y), lw * 0.38, lane_colors[eidx] * Color(1, 1, 1, ea))

	# Notes
	var note_h := lw * 0.42
	var margin := lw * 0.06

	for idx in range(first_visible_idx, notes.size()):
		var n = notes[idx]
		var t: float = n["time_ms"]
		var time_until := t - song_time_ms
		var state: int = note_state[idx]

		# Too far in future
		if time_until > APPROACH_TIME_MS:
			break
		# Missed — don't draw
		if state == 2:
			continue

		var lane: int = n["lane"]
		if lane >= lane_count:
			continue

		var x := ls + lane * lw + margin
		var w := lw - margin * 2.0
		var ratio := 1.0 - (time_until / APPROACH_TIME_MS)
		var y := ratio * hit_y - note_h / 2.0

		var is_hit := (state == 1)
		var is_holding := (state == 3)

		# Off-screen below — skip
		if is_hit and y > vp.y + note_h:
			continue

		var dur_ms: float = n["duration_ms"]

		# --- Sustain tail ---
		if dur_ms > 0:
			var tail_until := (t + dur_ms) - song_time_ms
			var tail_ratio := 1.0 - (tail_until / APPROACH_TIME_MS)
			var tail_y := tail_ratio * hit_y - note_h / 2.0

			var sx := x + w * 0.3
			var sw := w * 0.4

			if is_holding:
				# While holding: clip tail top to current position, head at hit line
				var hold_top := maxf(tail_y, 0)
				var hold_bottom := hit_y
				if hold_bottom > hold_top:
					# Pulse effect
					var pulse := 0.15 * sin(Time.get_ticks_msec() * 0.008)
					var hold_style := sustain_styles_hold[lane]
					hold_style.bg_color = lane_colors[lane] * Color(1, 1, 1, 0.65 + pulse)
					draw_style_box(hold_style, Rect2(sx, hold_top, sw, hold_bottom - hold_top + note_h))
				# Head stays at hit line
				draw_style_box(note_styles[lane], Rect2(x, hit_y - note_h / 2.0, w, note_h))
				continue
			elif is_hit:
				# Hit sustain: darkened tail
				if y - tail_y + note_h > 0:
					draw_style_box(sustain_styles_hit[lane], Rect2(sx, tail_y, sw, y - tail_y + note_h))
			else:
				# Active sustain
				if y - tail_y + note_h > 0:
					draw_style_box(sustain_styles[lane], Rect2(sx, tail_y, sw, y - tail_y + note_h))

		# --- Note head ---
		if is_hit:
			draw_style_box(note_styles_hit[lane], Rect2(x, y, w, note_h))
		elif not is_holding:
			draw_style_box(note_styles[lane], Rect2(x, y, w, note_h))

# --- Layout ---

func _lane_width() -> float:
	return get_viewport_rect().size.x * HIGHWAY_RATIO / float(lane_count)

func _lanes_start_x() -> float:
	return (get_viewport_rect().size.x - float(lane_count) * _lane_width()) / 2.0

# --- Input (press AND release) ---

func _input(event: InputEvent) -> void:
	if not song_started or is_loading or _countdown > 0:
		return

	var lane := -1
	var pressed := false

	if event is InputEventScreenTouch:
		lane = _pos_to_lane(event.position)
		pressed = event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		lane = _pos_to_lane(event.position)
		pressed = event.pressed
	elif event is InputEventKey and not event.echo:
		lane = _key_to_lane(event.keycode)
		pressed = event.pressed

	if lane < 0:
		return

	if pressed:
		lane_pressed[lane] = true
		_try_hit(lane)
	else:
		lane_pressed[lane] = false
		# Sustain release handled in _update_sustains()

func _pos_to_lane(pos: Vector2) -> int:
	var lw := _lane_width()
	var start := _lanes_start_x()
	var rel := pos.x - start
	if rel < 0 or rel >= float(lane_count) * lw:
		return -1
	return int(rel / lw)

func _key_to_lane(keycode: int) -> int:
	if lane_count == 4:
		match keycode:
			KEY_A, KEY_1: return 0
			KEY_S, KEY_2: return 1
			KEY_D, KEY_3: return 2
			KEY_F, KEY_4: return 3
	else:
		match keycode:
			KEY_A, KEY_1: return 0
			KEY_S, KEY_2: return 1
			KEY_D, KEY_3: return 2
			KEY_F, KEY_4: return 3
			KEY_G, KEY_5: return 4
	return -1

func _try_hit(lane: int) -> void:
	var best_idx := -1
	var best_diff := HIT_WINDOW_MS + 1.0

	for idx in range(first_visible_idx, notes.size()):
		var n = notes[idx]
		if note_state[idx] != 0:
			continue
		var t: float = n["time_ms"]
		var diff := absf(song_time_ms - t)
		if diff > APPROACH_TIME_MS:
			break
		if int(n["lane"]) == lane and diff < best_diff:
			best_diff = diff
			best_idx = idx

	if best_idx < 0 or best_diff > HIT_WINDOW_MS:
		return

	var n = notes[best_idx]
	var dur: float = n["duration_ms"]

	if dur > 0:
		# Sustain — enter holding state
		note_state[best_idx] = 3
		held_sustain[lane] = best_idx
	else:
		# Regular — hit (darkened, scrolling)
		note_state[best_idx] = 1

	combo += 1
	if combo > max_combo:
		max_combo = combo
	score += 50 * combo

	# Log first 20 hits for drift diagnosis
	if _hit_log_count < 20:
		_hit_log_count += 1
		var signed_diff := song_time_ms - float(n["time_ms"])
		if _hit_log_count == 1:
			var since_play := Time.get_ticks_msec() - _play_call_time_ms
			print("Sync: HIT #%d song=%.1f note=%.1f diff=%+.1f abs=%.1f since_play=%dms" % [
				_hit_log_count, song_time_ms, float(n["time_ms"]), signed_diff, best_diff, since_play])
		else:
			print("Sync: HIT #%d song=%.1f note=%.1f diff=%+.1f abs=%.1f" % [
				_hit_log_count, song_time_ms, float(n["time_ms"]), signed_diff, best_diff])

	# Hit flash
	hit_effects.append({"lane": lane, "alpha": 0.8})

	# Combo scale animation (reuse tween to avoid micro-stutter from allocation)
	if combo >= 2:
		var tw := create_tween()
		tw.tween_property(combo_label, "scale", Vector2(1.25, 1.25), 0.07)
		tw.tween_property(combo_label, "scale", Vector2(1.0, 1.0), 0.08)

func _on_offset_changed(val: float) -> void:
	audio_offset_ms = val
	offset_label.text = "Offset: %d ms" % int(val)

func _exit_tree() -> void:
	for p in _decode_players:
		if is_instance_valid(p):
			p.stop()
	if _decode_bus_idx >= 0 and _decode_bus_idx < AudioServer.bus_count:
		AudioServer.remove_bus(_decode_bus_idx)
		_decode_bus_idx = -1
