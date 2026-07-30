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
[ExpertDrums]
{
  0 = N 0 0
  480 = N 1 0
}
[Events]
{
  0 = E \"phrase_start\"
  0 = E \"lyric Hey\"
  480 = E \"lyric now\"
  960 = E \"phrase_end\"
}
"""
	var chart := ChartParser.new()
	assert(chart.parse_text(chart_text, "Expert", "guitar"))
	assert(chart.overdrive_phrases.size() == 1)
	assert(chart.solo_sections.size() == 1)
	assert(chart.lyric_phrases.size() == 1)

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
	var previous_presentation := Settings.guitar_presentation_mode
	var previous_fret_skin := Settings.arena_fret_skin
	Settings.pixel_stage_enabled = true
	Settings.guitar_presentation_mode = "classic"
	game._gh_mode = true
	game._configure_guitar_visuals()
	for stage_role in ["guitarist", "drummer", "bassist", "vocalist"]:
		assert(game._pixel_stage_textures.has(stage_role))
		assert((game._pixel_stage_textures[stage_role] as Array).size() \
			== int(game.PIXEL_STAGE_FRAME_COUNTS[stage_role]))
	Settings.guitar_presentation_mode = "arena"
	Settings.arena_fret_skin = "blade"
	game._configure_guitar_visuals()
	assert(game._arena_mode)
	assert(game._arena_highway_texture != null)
	assert(game._arena_effect_texture != null)
	assert(game._arena_highway_texture.resource_path == game.ARENA_HIGHWAY_TEXTURE_PATH)
	assert(game._arena_effect_texture.resource_path == game.ARENA_EFFECT_ATLAS_PATH)
	# The shipped WoR deck tiles seamlessly, so it must wrap rather than mirror
	# (mirroring flipped every other copy of the art upside down).
	assert(not game._arena_highway_mirror)
	assert(game.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED)
	# The deck is minified hard toward the horizon; without a mip chain that
	# far half aliases and the aliasing crawls as it scrolls.
	assert(game.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	assert(game._arena_highway_texture.get_image().has_mipmaps())
	# 512x1024 art is two highway widths long, so it tiles 3.0 / 2.0 times.
	assert(is_equal_approx(game._arena_highway_repeat, 1.5))
	assert(game._arena_effect_frame(0.0) == 0)
	assert(game._arena_effect_frame(1000.0) >= 0)
	assert(game._arena_effect_frame(1000.0) < game.ARENA_EFFECT_FRAME_COUNT)
	# 4.8fps ghosted through the crossfade, so the atlas is played faster than
	# its source duration; the loop is the frame count over the actual rate.
	assert(game.ARENA_EFFECT_FPS > 8.0)
	var effect_loop_ms: float = float(game.ARENA_EFFECT_FRAME_COUNT) \
		/ game.ARENA_EFFECT_FPS * 1000.0
	assert(game._arena_effect_frame(effect_loop_ms - 1.0) \
		== game.ARENA_EFFECT_FRAME_COUNT - 1)
	assert(game._arena_effect_frame(effect_loop_ms) == 0)
	assert(game._arena_effect_uvs_for_frame(0) \
		!= game._arena_effect_uvs_for_frame(1))
	assert(game._arena_effect_uvs_for_frame(15) \
		!= game._arena_effect_uvs_for_frame(16))
	var last_effect_uvs: PackedVector2Array = game._arena_effect_uvs_for_frame(
		game.ARENA_EFFECT_FRAME_COUNT - 1)
	assert(last_effect_uvs.size() == 4)
	for effect_uv in last_effect_uvs:
		assert(effect_uv.x >= 0.0 and effect_uv.x <= 1.0)
		assert(effect_uv.y >= 0.0 and effect_uv.y <= 1.0)
	game._arena_combo_energy_display = 0.0
	assert(is_equal_approx(game._arena_effect_alpha(), 0.0))
	game._arena_combo_energy_display = 0.90
	# The overlay is alpha-blended over the deck art, so it has to stay low
	# enough to tint the surface rather than grey it out.
	assert(game._arena_effect_alpha() > 0.10)
	assert(game._arena_effect_alpha() <= 0.16)
	# The deck art itself is lifted from the near-black sheets these rips ship
	# as, but must stay clearly below the gems.
	assert(game._arena_highway_gain > 1.5)
	assert(game._arena_highway_gain <= game.ARENA_HIGHWAY_MAX_GAIN)
	var period: float = game._arena_highway_period()
	assert(is_equal_approx(period, 1.0))
	var scroll_phase_a: float = game._arena_highway_scroll_phase(200.0)
	var scroll_phase_b: float = game._arena_highway_scroll_phase(700.0)
	assert(not is_equal_approx(scroll_phase_a, scroll_phase_b))
	assert(scroll_phase_a >= 0.0 and scroll_phase_a < period)
	assert(scroll_phase_b >= 0.0 and scroll_phase_b < period)
	# One full cycle of the art must land back on itself.
	var highway_loop_ms: float = game._approach_time_ms() * period \
		/ game._arena_highway_repeat
	assert(is_equal_approx(
		game._arena_highway_scroll_phase(0.0),
		game._arena_highway_scroll_phase(highway_loop_ms)))
	# Advancing one repeat per approach time is what locks the deck to the
	# notes: base_v at the hit line equals the repeat count.
	assert(is_equal_approx(
		game._arena_highway_base_v(1.0), game._arena_highway_repeat))
	assert(is_equal_approx(game._arena_highway_base_v(game._gh_z_far()), 0.0))
	_check_arena_highway_deck(game)
	_check_arena_highway_variations(game)
	# Restore the shipped deck for the rest of the suite.
	game._configure_guitar_visuals()
	for stage_role in ["guitarist", "drummer", "bassist", "vocalist"]:
		assert(game._pixel_stage_textures.has(stage_role))
		assert((game._pixel_stage_textures[stage_role] as Array).size() \
			== game.ARENA_STAGE_FRAME_COUNT)
		assert((game._pixel_stage_frame_rects[stage_role] as Array).size() \
			== game.ARENA_STAGE_FRAME_COUNT)
	assert(is_equal_approx(game._arena_combo_energy(0), 0.0))
	var previous_energy := -1.0
	for combo_value in [0, 25, 50, 100, 200, 500, 1000]:
		var energy: float = game._arena_combo_energy(combo_value)
		assert(energy >= previous_energy)
		assert(energy >= 0.0 and energy <= 1.0)
		previous_energy = energy
	game._vfx_quality = "performance"
	assert(game._arena_rib_count() == 4)
	game._vfx_quality = "balanced"
	assert(game._arena_rib_count() == 8)
	game._vfx_quality = "full"
	assert(game._arena_rib_count() == 12)
	game._vfx_quality = "balanced"
	Settings.guitar_presentation_mode = "classic"
	game._configure_guitar_visuals()
	assert(not game._arena_mode)
	assert(game._arena_highway_texture == null)
	assert(game._arena_effect_texture == null)
	assert(game.texture_repeat == CanvasItem.TEXTURE_REPEAT_DISABLED)
	assert(game.texture_filter == CanvasItem.TEXTURE_FILTER_PARENT_NODE)
	assert(is_equal_approx(game._arena_effect_alpha(), 0.0))
	game_script.song_instrument = "guitar"
	game_script.song_available_instruments = {
		"guitar": ["Expert"],
		"drums": ["Expert"],
	}
	game.lyric_phrases = chart.lyric_phrases.duplicate(true)
	game._prepare_stage_event_tracks(
		"res://unused.chart", chart.notes, "Expert", chart_text, PackedByteArray())
	assert(int(game.PIXEL_STAGE_FRAME_COUNTS["guitarist"]) == 40)
	assert(int(game.PIXEL_STAGE_FRAME_COUNTS["drummer"]) == 36)
	assert((game.PIXEL_STAGE_ACTION_FRAMES_BY_ROLE["guitarist"] as Array).size() == 36)
	assert((game.PIXEL_STAGE_ACTION_FRAMES_BY_ROLE["drummer"] as Array).size() == 32)
	assert(game._stage_visible_roles == ["guitarist", "vocalist", "drummer"])
	assert(game._stage_note_tracks.has("guitarist"))
	assert(game._stage_note_tracks.has("drummer"))
	assert(not game._stage_note_tracks.has("bassist"))
	game.song_time_ms = 0.0
	game.current_phrase_idx = 0
	game._update_stage_event_cursors()
	assert(game._stage_role_is_active("guitarist"))
	assert(game._stage_role_is_active("drummer"))
	assert(game._stage_role_is_active("vocalist"))
	assert(game._stage_animation_frame("vocalist", true, false) in game.PIXEL_STAGE_ACTION_FRAMES)
	game_script.song_available_instruments = {"guitar": ["Expert"]}
	game._prepare_stage_event_tracks(
		"res://unused.chart", chart.notes, "Expert", chart_text, PackedByteArray())
	assert(game._stage_visible_roles == ["guitarist", "vocalist"])

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
	# Sustain lightning is deterministic, quality capped, and visibly escalates
	# only while a long note is being held. These helpers are drawing-only and
	# deliberately carry no scoring or input state.
	game._adaptive_vfx_reduced = false
	game._frame_time_sec = 1.25
	game._vfx_quality = "full"
	assert(game._sustain_lightning_segment_count() == 9)
	assert(game._sustain_lightning_preview_cap() == 6)
	assert(game._sustain_lightning_filament_count(false) == 2)
	assert(game._sustain_lightning_filament_count(true) == 3)
	var lightning_a: PackedVector2Array = game._sustain_lightning_points(
		Vector2(20.0, 10.0), Vector2(20.0, 210.0), 7, 2, 0, 9, 12.0)
	var lightning_b: PackedVector2Array = game._sustain_lightning_points(
		Vector2(20.0, 10.0), Vector2(20.0, 210.0), 7, 2, 0, 9, 12.0)
	assert(lightning_a == lightning_b)
	assert(lightning_a.size() == 10)
	assert(lightning_a[0].is_equal_approx(Vector2(20.0, 10.0)))
	assert(lightning_a[lightning_a.size() - 1].is_equal_approx(Vector2(20.0, 210.0)))
	var preview_lightning: float = game._sustain_lightning_intensity(
		1000.0, 300.0, 1400.0, false)
	var held_lightning: float = game._sustain_lightning_intensity(
		1000.0, 300.0, 1400.0, true)
	assert(preview_lightning > 0.0)
	assert(held_lightning > preview_lightning)
	assert(game._sustain_lightning_intensity(
		game.SUSTAIN_LIGHTNING_MIN_DURATION_MS - 1.0, 0.0, 1400.0, false) == 0.0)
	game._vfx_quality = "performance"
	assert(game._sustain_lightning_segment_count() == 5)
	assert(game._sustain_lightning_preview_cap() == 2)
	assert(game._sustain_lightning_filament_count(true) == 1)
	game.overdrive_button = Button.new()
	game.overdrive_bar = ProgressBar.new()
	game._overdrive_energy = 1.0
	game._overdrive_active = true
	game.song_started = true
	game._update_overdrive_ui()
	assert(game.overdrive_button.disabled)
	game.overdrive_button.free()
	game.overdrive_bar.free()
	# The only bundled miss cue is explicitly a guitar-string mistake. Drum and
	# keys charts must not create that player or duck the music bus.
	var previous_miss_setting := Settings.miss_sfx_enabled
	Settings.miss_sfx_enabled = true
	game_script.song_instrument = "drums"
	game._setup_miss_sfx()
	assert(game._miss_sfx_player == null)
	game_script.song_instrument = "keys"
	game._setup_miss_sfx()
	assert(game._miss_sfx_player == null)
	game_script.song_instrument = "guitar"
	game._setup_miss_sfx()
	assert(game._miss_sfx_player != null)
	assert(game._miss_sfx_player.bus == "SFX")
	assert(game._miss_sfx_player.stream.resource_path.ends_with("guitar_miss.mp3"))
	Settings.miss_sfx_enabled = previous_miss_setting
	Settings.guitar_presentation_mode = previous_presentation
	Settings.arena_fret_skin = previous_fret_skin
	game.free()
	game_script.song_available_instruments = {}

	print("Gameplay feature tests passed: Arena visuals, sustain lightning, stage sync, crowd pools, audio buses, miss SFX, OD/solo parsing")
	quit(0)

# Imported art comes in every shape (256x512 GH1 rips, 512x1024 WoR sheets,
# whatever a player picks). The tile count has to follow the aspect ratio, and
# the wrap mode has to follow whether the art meets end to end, or added
# variations scroll at the wrong scale and show a seam or a fold.
func _check_arena_highway_variations(game) -> void:
	var seamless := Image.create(64, 128, false, Image.FORMAT_RGBA8)
	for y in range(128):
		# A vertical ramp that returns to its starting value: tiles cleanly.
		var shade: float = absf(64.0 - float(y)) / 64.0
		for x in range(64):
			seamless.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	game._arena_highway_texture = ImageTexture.create_from_image(seamless)
	game._configure_arena_highway_tiling(seamless)
	assert(not game._arena_highway_mirror)
	# 64x128 is two widths long, same as every stock GH sheet.
	assert(is_equal_approx(game._arena_highway_repeat, 1.5))

	# Square art is half as long, so it has to tile twice as often to keep its
	# proportions instead of being stretched down the deck.
	var square := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	square.fill(Color(0.5, 0.5, 0.5, 1.0))
	game._arena_highway_texture = ImageTexture.create_from_image(square)
	game._configure_arena_highway_tiling(square)
	assert(is_equal_approx(game._arena_highway_repeat, 3.0))
	assert(not game._arena_highway_mirror)

	# Art whose ends do not meet folds instead of jumping.
	var stepped := Image.create(64, 128, false, Image.FORMAT_RGBA8)
	for y in range(128):
		var shade := float(y) / 127.0
		for x in range(64):
			stepped.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	game._arena_highway_texture = ImageTexture.create_from_image(stepped)
	game._configure_arena_highway_tiling(stepped)
	assert(game._arena_highway_mirror)
	assert(is_equal_approx(game._arena_highway_period(), 2.0))
	# Mirrored art still has to return to its start after one full cycle.
	var mirrored_loop_ms: float = game._approach_time_ms() * 2.0 \
		/ game._arena_highway_repeat
	assert(is_equal_approx(
		game._arena_highway_scroll_phase(0.0),
		game._arena_highway_scroll_phase(mirrored_loop_ms)))
	_check_arena_highway_deck(game)

	# Extreme aspect ratios stay inside the clamp instead of tiling into mush.
	var wide := Image.create(512, 64, false, Image.FORMAT_RGBA8)
	wide.fill(Color(0.5, 0.5, 0.5, 1.0))
	game._arena_highway_texture = ImageTexture.create_from_image(wide)
	game._configure_arena_highway_tiling(wide)
	assert(game._arena_highway_repeat <= game.ARENA_HIGHWAY_REPEAT_MAX)
	assert(game._arena_highway_repeat >= game.ARENA_HIGHWAY_REPEAT_MIN)

# Regression guard for the wobbling Arena deck.
#
# The deck used to be sliced at fixed screen rows, which left the affine UV
# error standing still on screen: the art sped up and slowed down again through
# every slice as it scrolled. Slices are now pinned to texture rows, so this
# checks both halves of that fix — the slice edges move with the art, and the
# surface they describe stays on the analytic perspective curve at any phase.
func _check_arena_highway_deck(game) -> void:
	var viewport := Vector2(1080.0, 1920.0)
	game.lane_count = 5
	game._frame_viewport_size = viewport
	game._cached_lane_width = viewport.x / float(game.lane_count)
	game._cached_lanes_start_x = 0.0
	game._cached_hit_line_y = viewport.y * float(game.LAYOUT["hit_line_ratio"])
	game._cached_gh_vanish_y = viewport.y * game.GH_VANISH_Y_RATIO
	var vanish_y: float = game._cached_gh_vanish_y
	var deck_height: float = game._cached_hit_line_y - vanish_y
	var z_bottom: float = deck_height / (viewport.y - vanish_y)
	game._arena_highway_v_span = game._arena_highway_base_v(z_bottom)
	var slice_span: float = 1.0 / float(game.ARENA_HIGHWAY_SLICES_PER_TILE)
	game._arena_deck_slice_count = int(ceil(
		game._arena_highway_v_span / slice_span)) + 1
	game._arena_deck_slices.clear()
	game._arena_deck_slice_uvs.clear()
	var blank := PackedVector2Array([
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	for _slot in range(game._arena_deck_slice_count):
		game._arena_deck_slices.append(blank.duplicate())
		game._arena_deck_slice_uvs.append(blank.duplicate())
	# Freshly allocated slices hold nothing, so the phase cache must not claim
	# they are already built — this is what _cache_render_geometry does too.
	game._arena_highway_scroll_phase_cached = -1000.0
	game._arena_deck_used_cached = 0

	var approach_ms: float = game._approach_time_ms()
	var period: float = game._arena_highway_period()
	var loop_ms: float = approach_ms * period / game._arena_highway_repeat
	var first_edges := PackedFloat32Array()
	for step in range(24):
		var time_ms: float = loop_ms * float(step) / 24.0
		var used: int = game._update_arena_highway_deck(time_ms)
		assert(used > 0 and used <= game._arena_deck_slice_count)
		var previous_bottom_y := -INF
		for slice_index in range(used):
			var quad: PackedVector2Array = game._arena_deck_slices[slice_index]
			var uvs: PackedVector2Array = game._arena_deck_slice_uvs[slice_index]
			# Slices tile the deck top to bottom without gaps or overlap.
			if slice_index == 0:
				assert(is_equal_approx(quad[0].y, game._gh_horizon_y()))
			else:
				assert(is_equal_approx(quad[0].y, previous_bottom_y))
			assert(quad[2].y > quad[0].y)
			previous_bottom_y = quad[2].y
			# UVs stay inside one repeat cycle and never wrap mid-slice.
			assert(uvs[0].y >= 0.0 and uvs[2].y <= period + 0.0001)
			assert(uvs[2].y > uvs[0].y)
			assert(is_equal_approx(uvs[0].x, 0.0) and is_equal_approx(uvs[1].x, 1.0))
			# The linear span of a slice must track the exact hyperbolic curve.
			var depth_top: float = game._arena_highway_base_v(
				deck_height / (quad[0].y - vanish_y))
			var depth_bottom: float = game._arena_highway_base_v(
				deck_height / (quad[2].y - vanish_y))
			var exact_mid_y: float = vanish_y + deck_height \
				/ game._arena_highway_z_at((depth_top + depth_bottom) * 0.5)
			var drawn_mid_y: float = (quad[0].y + quad[2].y) * 0.5
			assert(absf(exact_mid_y - drawn_mid_y) < viewport.y * 0.005)
		assert(previous_bottom_y >= viewport.y - 0.5)
		if step == 0:
			for slice_index in range(used):
				first_edges.append(
					(game._arena_deck_slices[slice_index] as PackedVector2Array)[0].y)
	# Edges ride with the art. Fixed screen-row slicing would leave them put,
	# which is exactly what produced the wobble.
	# Sample a phase that is not slice-aligned, otherwise the layout repeats
	# exactly (edges cycle with a period of one slice, which is the point).
	var moved := false
	game._update_arena_highway_deck(loop_ms * 0.02)
	for slice_index in range(mini(first_edges.size(), game._arena_deck_slices.size())):
		var edge_y: float = (
			game._arena_deck_slices[slice_index] as PackedVector2Array)[0].y
		if absf(edge_y - float(first_edges[slice_index])) > 1.0:
			moved = true
	assert(moved)
	# A full cycle returns the deck to its starting layout, so the loop is
	# seamless no matter which art variation is loaded.
	var start_slices: Array[PackedVector2Array] = []
	var start_used: int = game._update_arena_highway_deck(0.0)
	for slice_index in range(start_used):
		start_slices.append(
			(game._arena_deck_slices[slice_index] as PackedVector2Array).duplicate())
	var looped_used: int = game._update_arena_highway_deck(loop_ms)
	assert(looped_used == start_used)
	for slice_index in range(start_used):
		var looped: PackedVector2Array = game._arena_deck_slices[slice_index]
		for corner in range(4):
			assert(looped[corner].distance_to(start_slices[slice_index][corner]) < 0.5)
