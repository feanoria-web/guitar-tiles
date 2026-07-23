extends SceneTree

func _initialize() -> void:
	var assisted_pairs := {
		"Tiles": "TilesAkici",
		"Rahat": "RahatAkici",
		"Normal": "NormalAkici",
	}
	for base_name in assisted_pairs:
		var assisted_name: String = assisted_pairs[base_name]
		var base_cfg: Dictionary = Playability.PRESETS[base_name]
		var assisted_cfg: Dictionary = Playability.PRESETS[assisted_name]
		assert(Playability.is_assisted_preset(assisted_name))
		assert(assisted_cfg["chord_mode"] == base_cfg["chord_mode"])
		assert(assisted_cfg["density_max"] == base_cfg["density_max"])
		assert(assisted_cfg["sustain_min_ms"] == base_cfg["sustain_min_ms"])
	assert(Playability.is_assisted_preset("Akici"))
	assert(not Playability.is_assisted_preset("Sadik"))

	var playability := Playability.new()
	playability.apply_preset("Akici")

	# Six simultaneous notes authored on one lane cannot occupy five distinct
	# lanes. Akıcı must preserve all six and leave only the overflow pair for
	# gameplay clustering.
	var dense_notes: Array = []
	for _idx in range(6):
		dense_notes.append({"time_ms": 1000.0, "lane": 0, "duration_ms": 0.0})
	var assisted_notes := playability.process(dense_notes, 480, 5)
	assert(assisted_notes.size() == dense_notes.size())
	var occupied_lanes := {}
	for note in assisted_notes:
		occupied_lanes[int(note["lane"])] = true
	assert(occupied_lanes.size() == 5)

	var game_script = load("res://scripts/game.gd")
	var game = game_script.new()
	game_script.song_preset = "Akici"
	game.notes = assisted_notes
	game.note_state.resize(game.notes.size())
	game.note_state.fill(0)
	game._build_assist_clusters()
	assert(game._assist_clusters.size() == 1)
	var leader_idx := -1
	for idx in range(game.notes.size()):
		if bool(game.notes[idx].get("assist_cluster_leader", false)):
			leader_idx = idx
			break
	assert(leader_idx >= 0)
	assert(int(game.notes[leader_idx]["assist_cluster_size"]) == 2)
	assert(game._active_assist_cluster_indices(leader_idx).size() == 2)
	assert(is_equal_approx(game._hit_window_ms(), game.ASSIST_HIT_WINDOW_MS))
	assert(game._assist_cluster_window_ms() >= game.ASSIST_CLUSTER_MIN_MS)
	for assisted_name in ["TilesAkici", "RahatAkici", "NormalAkici", "Akici"]:
		game_script.song_preset = assisted_name
		assert(is_equal_approx(game._hit_window_ms(), game.ASSIST_HIT_WINDOW_MS))
	game_script.song_preset = "Akici"

	# A full five-lane wall repeated 120 ms later previously survived as an
	# unreadable stack. All ten authored heads remain, while each lane becomes
	# one visible/tappable two-note cluster.
	var wall_notes: Array = []
	for wall_time in [0.0, 120.0]:
		for lane in range(5):
			wall_notes.append({"time_ms": wall_time, "lane": lane, "duration_ms": 0.0})
	var assisted_wall := playability.process(wall_notes, 480, 5)
	assert(assisted_wall.size() == wall_notes.size())
	game.notes = assisted_wall
	game.note_state.resize(game.notes.size())
	game.note_state.fill(0)
	game._build_assist_clusters()
	assert(game._assist_clusters.size() == 5)
	var visible_heads := 0
	for note in game.notes:
		if not note.has("assist_cluster_id") or bool(note.get("assist_cluster_leader", false)):
			visible_heads += 1
	assert(visible_heads == 5)

	# A new head inside an old sustain is retained; the old tail ends just before
	# it so one finger never has to hold and retrigger the same lane.
	var sustain_notes := [
		{"time_ms": 0.0, "lane": 0, "duration_ms": 1000.0},
		{"time_ms": 500.0, "lane": 0, "duration_ms": 0.0},
	]
	var assisted_sustains := playability.process(sustain_notes, 480, 1)
	assert(assisted_sustains.size() == 2)
	assert(is_equal_approx(float(assisted_sustains[0]["duration_ms"]), 440.0))

	game_script.song_preset = "Tiles"
	game.free()
	print("Assisted gameplay tests passed: paired presets, lane spread, clusters, sustain trim")
	quit(0)
