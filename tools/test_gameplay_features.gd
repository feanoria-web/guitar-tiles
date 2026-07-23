extends SceneTree

func _initialize() -> void:
	var chart_text := """
[Song]
{
  Resolution = 480
}
[SyncTrack]
{
  0 = B 120000
}
[ExpertSingle]
{
  0 = N 0 0
  0 = S 2 960
  480 = E \"solo\"
  480 = N 1 0
  960 = N 2 0
  1440 = E \"soloend\"
}
"""
	var chart := ChartParser.new()
	assert(chart.parse_text(chart_text, "Expert", "guitar"))
	assert(chart.overdrive_phrases.size() == 1)
	assert(chart.solo_sections.size() == 1)

	var midi := MidiParser.new()
	midi.resolution = 480
	midi.bpm_events = [{"tick": 0, "bpm": 120.0}]
	midi._extract_gameplay_phrases({"events": [
		{"type": "note_on", "tick": 0, "note": 116, "velocity": 100},
		{"type": "note_off", "tick": 960, "note": 116},
		{"type": "text", "tick": 480, "text": "[solo_on]"},
		{"type": "text", "tick": 1440, "text": "[solo_off]"},
	]})
	assert(midi.overdrive_phrases.size() == 1)
	assert(midi.solo_sections.size() == 1)

	var game_script = load("res://scripts/game.gd")
	var game = game_script.new()
	game._ensure_music_audio_bus()
	game._ensure_crowd_audio_bus()
	game._ensure_sfx_audio_bus()
	var music_bus_idx := AudioServer.get_bus_index("Music")
	var crowd_bus_idx := AudioServer.get_bus_index("Crowd")
	var sfx_bus_idx := AudioServer.get_bus_index("SFX")
	assert(music_bus_idx >= 0)
	assert(crowd_bus_idx >= 0)
	assert(sfx_bus_idx >= 0)
	assert(is_equal_approx(AudioServer.get_bus_volume_db(music_bus_idx), game.MUSIC_BUS_GAIN_DB))
	assert(is_equal_approx(AudioServer.get_bus_volume_db(crowd_bus_idx), game.CROWD_BUS_GAIN_DB))
	assert(is_equal_approx(AudioServer.get_bus_volume_db(sfx_bus_idx), game.SFX_BUS_GAIN_DB))
	var crowd_has_limiter := false
	for effect_idx in range(AudioServer.get_bus_effect_count(crowd_bus_idx)):
		if AudioServer.get_bus_effect(crowd_bus_idx, effect_idx) is AudioEffectLimiter:
			crowd_has_limiter = true
	assert(crowd_has_limiter)
	game._crowd_ambience_streams = game._load_crowd_stream_pool("crowd_ambience")
	game._crowd_cheer_streams = game._load_crowd_stream_pool("crowd_cheer")
	game._crowd_boo_streams = game._load_crowd_stream_pool("crowd_boo")
	assert(game._crowd_ambience_streams.size() >= 2)
	assert(game._crowd_cheer_streams.size() >= 2)
	assert(game._crowd_boo_streams.size() >= 3)
	for previous_idx in range(2):
		assert(game._pick_nonrepeating_index(2, previous_idx) != previous_idx)
	game._crowd_cheer_stream = game._crowd_cheer_streams[0]
	var cheer_a = game._resolve_crowd_reaction_stream(game._crowd_cheer_stream)
	var cheer_b = game._resolve_crowd_reaction_stream(game._crowd_cheer_stream)
	assert(cheer_a != cheer_b)
	game._crowd_boo_stream = game._crowd_boo_streams[0]
	var boo_a = game._resolve_crowd_reaction_stream(game._crowd_boo_stream)
	var boo_b = game._resolve_crowd_reaction_stream(game._crowd_boo_stream)
	assert(boo_a != boo_b)
	var ambience_a = game._pick_crowd_ambience_stream()
	var ambience_b = game._pick_crowd_ambience_stream()
	assert(ambience_a != ambience_b)
	for idx in range(80):
		game.notes.append({"time_ms": float(idx * 250), "lane": idx % 5, "duration_ms": 0.0})
	game._prepare_gameplay_sections()
	assert(not game.overdrive_phrases.is_empty())
	assert(int(game.notes[16].get("overdrive_phrase", -1)) >= 0)
	# Old mistakes heal one at a time for every five consecutive Perfects. Five
	# mistakes followed by thirty Perfects must make the next miss strike one,
	# not an immediate boo.
	game._crowd_mistake_count = 5
	for perfect_idx in range(30):
		game._register_crowd_perfect()
	assert(game._crowd_mistake_count == 0)
	game.song_time_ms = 200.0
	game._register_crowd_mistake()
	assert(game._crowd_mistake_count == 1)
	assert(not game._crowd_pending_boo)
	game._crowd_mistake_count = 0
	for mistake_idx in range(5):
		game.song_time_ms = 1000.0 + mistake_idx * 200.0
		game._register_crowd_mistake()
	assert(game._crowd_mistake_count == 5)
	game.song_time_ms += 200.0
	game._register_crowd_mistake()
	assert(game._crowd_mistake_count == 0)
	assert(game._crowd_pending_boo)
	# A queued boo prevents a cheer from taking its next available slot. With no
	# runtime player in this parser-focused test, the queue must remain intact.
	game._crowd_performance_started = true
	assert(not game._play_crowd_reaction(game._crowd_cheer_stream))
	game._update_crowd_audio(0.1)
	assert(game._crowd_pending_boo)
	# Releasing a sustain inside the visual tail grace succeeds and never adds
	# crowd mistake debt. Even a genuinely early release stays out of boo debt.
	game.lane_count = 1
	game.notes = [{"time_ms": 0.0, "lane": 0, "duration_ms": 1000.0, "hit_score_factor": 1.0}]
	game.note_state = PackedByteArray([3])
	game.held_sustain = [0]
	game.lane_pressed = [false]
	game.song_time_ms = 760.0
	game._update_sustains()
	assert(game.note_state[0] == 1)
	assert(game._crowd_mistake_count == 0)
	game.note_state = PackedByteArray([3])
	game.held_sustain = [0]
	game.song_time_ms = 500.0
	game._update_sustains()
	assert(game._crowd_mistake_count == 0)
	if OS.is_debug_build():
		game_script.debug_infinite_overdrive = true
		game.overdrive_button = Button.new()
		game.overdrive_bar = ProgressBar.new()
		game._overdrive_energy = 1.0
		game._overdrive_active = true
		game.song_started = true
		game._update_overdrive_ui()
		assert(not game.overdrive_button.disabled)
		game._activate_overdrive()
		assert(not game._overdrive_active)
		game.overdrive_button.free()
		game.overdrive_bar.free()
		game_script.debug_infinite_overdrive = false
	game.free()

	print("Gameplay feature tests passed: crowd pools, audio buses, OD/solo parsing")
	quit(0)
