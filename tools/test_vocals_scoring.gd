extends SceneTree

# Phrase scoring, checked against a hand-built chart and then against the real
# Rhiannon stem when its pitch track is present.

const HOP_MS := 16.0


func _note(time_ms: float, end_ms: float, midi: int, talkie := false) -> Dictionary:
	return {
		"time_ms": time_ms, "end_ms": end_ms, "midi_note": midi,
		"text": "la", "non_pitched": talkie, "slide": false,
		"word_continues": false, "joins": false, "hidden": false,
	}


## Sings `midi` for the whole span, or nothing when `midi` < 0.
func _perform(scorer, from_ms: float, to_ms: float, midi: float) -> void:
	var t := from_ms
	while t < to_ms:
		scorer.update(t, midi, midi > 0.0)
		t += HOP_MS
	# Always land exactly on the end, or a phrase boundary can fall between two
	# steps and never close.
	scorer.update(to_ms, midi, midi > 0.0)


func _initialize() -> void:
	var notes := [
		_note(0.0, 500.0, 60),
		_note(500.0, 1000.0, 62),
		_note(1000.0, 1500.0, 64),
	]
	var phrases := [{"start_ms": 0.0, "end_ms": 1600.0, "overdrive": false}]

	# --- Perfect on one note only: a third of the phrase ---
	var scorer = VocalsScoring.new()
	scorer.setup(notes, phrases, "Hard")
	var results: Array = []
	scorer.phrase_completed.connect(func(r): results.append(r))
	_perform(scorer, 0.0, 500.0, 60.0)
	_perform(scorer, 500.0, 1600.0, -1.0)
	assert(results.size() == 1)
	assert(absf(float(results[0]["accuracy"]) - 0.333) < 0.06)
	assert(int(results[0]["tier"]) == VocalsScoring.Tier.MISS)
	assert(scorer.phrase_streak == 0)

	# --- Sing every note: awesome ---
	scorer = VocalsScoring.new()
	scorer.setup(notes, phrases, "Hard")
	results = []
	scorer.phrase_completed.connect(func(r): results.append(r))
	_perform(scorer, 0.0, 500.0, 60.0)
	_perform(scorer, 500.0, 1000.0, 62.0)
	_perform(scorer, 1000.0, 1500.0, 64.0)
	_perform(scorer, 1500.0, 1700.0, -1.0)
	assert(results.size() == 1)
	assert(float(results[0]["accuracy"]) > 0.9)
	assert(int(results[0]["tier"]) == VocalsScoring.Tier.AWESOME)
	assert(scorer.score > 0)
	# Note fill drives the highway, so it has to track too.
	for value in scorer.note_progress:
		assert(value > 0.9)

	# --- An octave down is still correct ---
	scorer = VocalsScoring.new()
	scorer.setup(notes, phrases, "Hard")
	results = []
	scorer.phrase_completed.connect(func(r): results.append(r))
	_perform(scorer, 0.0, 500.0, 48.0)
	_perform(scorer, 500.0, 1000.0, 50.0)
	_perform(scorer, 1000.0, 1500.0, 52.0)
	_perform(scorer, 1500.0, 1700.0, -1.0)
	assert(int(results[0]["tier"]) == VocalsScoring.Tier.AWESOME)

	# --- A talkie only needs sound, any pitch ---
	var talkie_notes := [_note(0.0, 500.0, 60, true)]
	scorer = VocalsScoring.new()
	scorer.setup(talkie_notes, [{"start_ms": 0.0, "end_ms": 600.0, "overdrive": false}], "Expert")
	results = []
	scorer.phrase_completed.connect(func(r): results.append(r))
	_perform(scorer, 0.0, 500.0, 40.0)     # nowhere near the charted pitch
	_perform(scorer, 500.0, 700.0, -1.0)
	assert(int(results[0]["tier"]) == VocalsScoring.Tier.AWESOME)

	# --- Silence scores nothing, and an empty phrase is not graded ---
	scorer = VocalsScoring.new()
	scorer.setup(notes, phrases, "Hard")
	results = []
	scorer.phrase_completed.connect(func(r): results.append(r))
	_perform(scorer, 0.0, 1700.0, -1.0)
	assert(int(results[0]["tier"]) == VocalsScoring.Tier.MISS)
	assert(scorer.score == 0)
	scorer = VocalsScoring.new()
	scorer.setup([], [{"start_ms": 0.0, "end_ms": 500.0, "overdrive": false}], "Hard")
	results = []
	scorer.phrase_completed.connect(func(r): results.append(r))
	_perform(scorer, 0.0, 600.0, 60.0)
	assert(results.is_empty())

	# --- Tolerance widens on lower difficulties ---
	for pair in [["Expert", false], ["Easy", true]]:
		scorer = VocalsScoring.new()
		scorer.setup(notes, phrases, String(pair[0]))
		results = []
		scorer.phrase_completed.connect(func(r): results.append(r))
		# Two semitones sharp throughout.
		_perform(scorer, 0.0, 500.0, 62.0)
		_perform(scorer, 500.0, 1000.0, 64.0)
		_perform(scorer, 1000.0, 1500.0, 66.0)
		_perform(scorer, 1500.0, 1700.0, -1.0)
		var forgiven := int(results[0]["tier"]) == VocalsScoring.Tier.AWESOME
		assert(forgiven == bool(pair[1]))

	# --- Overdrive phrases are worth double ---
	scorer = VocalsScoring.new()
	scorer.setup(notes, [{"start_ms": 0.0, "end_ms": 1600.0, "overdrive": true}], "Hard")
	results = []
	scorer.phrase_completed.connect(func(r): results.append(r))
	_perform(scorer, 0.0, 500.0, 60.0)
	_perform(scorer, 500.0, 1000.0, 62.0)
	_perform(scorer, 1000.0, 1500.0, 64.0)
	_perform(scorer, 1500.0, 1700.0, -1.0)
	assert(bool(results[0]["overdrive"]))
	assert(int(results[0]["score"]) == VocalsScoring.TIER_SCORE[VocalsScoring.Tier.AWESOME] * 2)

	_check_against_stem()
	print("Vocals scoring tests passed")
	quit(0)


## Replays the analysed Rhiannon vocal against its own chart. The recording is
## the artist singing the line it was charted from, so a scorer that is tuned
## sanely has to grade it well.
func _check_against_stem() -> void:
	var pitch_path := "res://tmp/rhiannon_pitch.json"
	var midi_path := "res://tmp/notes.mid"
	if not FileAccess.file_exists(pitch_path) or not FileAccess.file_exists(midi_path):
		print("(stem replay skipped - tmp/ inputs absent)")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(pitch_path))
	var track: Array = parsed.get("midi", [])
	var hop_ms := float(parsed.get("hop_ms", 30.0))
	var midi_file := FileAccess.open(midi_path, FileAccess.READ)
	var parser = MidiParser.new()
	parser.parse_data(midi_file.get_buffer(midi_file.get_length()), "Expert", "guitar")
	midi_file.close()

	var scorer = VocalsScoring.new()
	scorer.setup(parser.vocal_parts.get("lead", []), parser.vocal_phrases, "Hard")
	var tiers := {}
	scorer.phrase_completed.connect(func(r):
		var tier_name := String(r["tier_name"])
		tiers[tier_name] = int(tiers.get(tier_name, 0)) + 1)
	for i in range(track.size()):
		var midi := float(track[i])
		scorer.update(float(i) * hop_ms, midi, midi > 0.0)

	var graded: int = scorer.completed_phrases
	var good := int(tiers.get("AWESOME", 0)) + int(tiers.get("STRONG", 0))
	print("stem replay: %d phrases graded, %s, score %d" % [graded, tiers, scorer.score])
	assert(graded > 20)
	# The artist singing their own line should mostly clear STRONG. If this
	# fails the thresholds are wrong, not the singer.
	assert(float(good) / float(graded) > 0.5)
