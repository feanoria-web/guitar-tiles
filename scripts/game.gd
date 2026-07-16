extends Control

const ChartParserScript = preload("res://scripts/chart_parser.gd")
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
	var parser = ChartParserScript.new()
	var sng_loader: RefCounted = null

	if source.ends_with(".sng"):
		sng_loader = SngLoaderScript.new()
		if not sng_loader.load_sng(source):
			push_error("Game: failed to load .sng"); return
		var chart_text: String = sng_loader.get_chart_text()
		if chart_text == "":
			push_error("Game: no chart in .sng"); return
		parser.parse_text(chart_text, difficulty)
	elif source.ends_with(".chart"):
		parser.parse_file(source, difficulty)
	else:
		push_error("Game: unknown file type"); return

	notes = parser.notes
	lyric_phrases = parser.lyric_phrases

	# Apply playability processing
	var playability = PlayabilityScript.new()
	playability.apply_preset(song_preset)
	notes = playability.process(notes, parser.resolution, lane_count)

	if song_mode == "piano":
		_merge_piano_lanes()

	note_state.resize(notes.size())
	note_state.fill(0)
	first_visible_idx = 0
	current_phrase_idx = 0

	print("Game: [%s][%s] %d notes, %d phrases" % [song_mode, difficulty, notes.size(), lyric_phrases.size()])

	is_loading = true
	loading_status = "Loading audio..."
	if sng_loader:
		var tmp_dir := "user://sng_temp"
		_clear_dir(tmp_dir)
		sng_loader.extract_to_dir(tmp_dir)
		_load_stems_from_dir(tmp_dir)
	else:
		_load_stems_from_dir(source.get_base_dir())

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

# --- Threaded audio ---

func _load_stems_from_dir(dir_path: String) -> void:
	print("Audio: scanning stems in %s" % dir_path)

	# List all audio files in directory
	var all_audio: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir():
				if fname.ends_with(".opus") or fname.ends_with(".ogg") or fname.ends_with(".mp3"):
					all_audio.append(fname)
			fname = dir.get_next()
		dir.list_dir_end()
	print("Audio: found files: %s" % str(all_audio))

	# Load only the main "song" stem (mixed audio) to avoid mono/stereo glitches
	var priority := ["song", "guitar", "rhythm", "vocals"]
	for stem_name in priority:
		for ext in [".opus", ".ogg", ".mp3"]:
			var fname2: String = stem_name + ext
			if all_audio.has(fname2):
				loading_status = "Loading %s..." % fname2
				var stream = _load_audio_stream(dir_path.path_join(fname2))
				if stream:
					var player := AudioStreamPlayer.new()
					player.stream = stream
					add_child(player)
					audio_players.append(player)
					master_player = player
					print("Game: loaded '%s'" % fname2)
				break
		if not audio_players.is_empty():
			break

	# Fallback: load ANY audio file
	if audio_players.is_empty():
		for fname3: String in all_audio:
			loading_status = "Loading %s..." % fname3
			var stream = _load_audio_stream(dir_path.path_join(fname3))
			if stream:
				var player := AudioStreamPlayer.new()
				player.stream = stream
				add_child(player)
				audio_players.append(player)
				master_player = player
				print("Game: loaded '%s' (fallback)" % fname3)
				break

	if audio_players.is_empty():
		push_error("Audio: NO playable stems in %s" % dir_path)
		warning_label.text = "Ses dosyasi bulunamadi! .opus/.ogg dosyalari eksik."
		warning_label.visible = true

	is_loading = false
	loading_status = ""
	_start_song()


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
	if path.ends_with(".ogg"):
		var stream = AudioStreamOggVorbis.load_from_file(path)
		if stream == null:
			push_error("Audio: OGG load failed: %s" % path)
		else:
			print("Audio: OGG OK: %s" % path)
		return stream
	elif path.ends_with(".mp3"):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var mp3 := AudioStreamMP3.new()
			mp3.data = f.get_buffer(f.get_length())
			f.close()
			print("Audio: MP3 OK: %s" % path)
			return mp3
		push_error("Audio: MP3 open failed: %s" % path)
	elif path.ends_with(".opus"):
		# Use audio-stream-plus GDExtension — load bytes directly (no resource cache)
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var data := f.get_buffer(f.get_length())
			f.close()
			if ClassDB.class_exists("AudioStreamOpus"):
				var opus_stream = ClassDB.instantiate("AudioStreamOpus")
				if opus_stream:
					opus_stream.set("data", data)
					print("Audio: Opus OK (%d bytes): %s" % [data.size(), path])
					return opus_stream
				push_error("Audio: AudioStreamOpus instantiate failed")
			else:
				push_error("Audio: AudioStreamOpus class not found — GDExtension not loaded!")
		else:
			push_error("Audio: cannot open opus file: %s" % path)
	return null

# --- Playback ---

func _start_song() -> void:
	song_started = true
	_start_ticks = Time.get_ticks_msec()
	for player in audio_players:
		player.play()

func _get_song_time_ms() -> float:
	if master_player and master_player.playing:
		var t := master_player.get_playback_position()
		t += AudioServer.get_time_since_last_mix()
		t -= AudioServer.get_output_latency()
		return t * 1000.0 + audio_offset_ms
	elif song_started:
		return float(Time.get_ticks_msec() - _start_ticks) + audio_offset_ms
	return 0.0

# --- Main loop ---

func _process(_delta: float) -> void:
	if is_loading:
		loading_label.text = loading_status
		queue_redraw()
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
	if is_loading:
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
	if not song_started or is_loading:
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

	# Hit flash
	hit_effects.append({"lane": lane, "alpha": 0.8})

	# Combo scale animation
	if combo >= 2:
		var tw := create_tween()
		tw.tween_property(combo_label, "scale", Vector2(1.25, 1.25), 0.07)
		tw.tween_property(combo_label, "scale", Vector2(1.0, 1.0), 0.08)

func _on_offset_changed(val: float) -> void:
	audio_offset_ms = val
	offset_label.text = "Offset: %d ms" % int(val)

func _exit_tree() -> void:
	pass
