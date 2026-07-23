class_name Playability
extends RefCounted

# Preset definitions (order: easy → hard)
const PRESETS := {
	"Tiles":  {"chord_mode": "tek",  "density_max": 3, "same_lane_min_ms": 350.0, "sustain_min_ms": 500.0},
	"TilesAkici": {"chord_mode": "tek", "density_max": 3, "same_lane_min_ms": 350.0,
		"sustain_min_ms": 500.0, "preserve_notes": true, "assisted": true},
	"Rahat":  {"chord_mode": "tek",  "density_max": 4, "same_lane_min_ms": 200.0, "sustain_min_ms": 300.0},
	"RahatAkici": {"chord_mode": "tek", "density_max": 4, "same_lane_min_ms": 260.0,
		"sustain_min_ms": 300.0, "preserve_notes": true, "assisted": true},
	"Normal": {"chord_mode": "cift", "density_max": 5, "same_lane_min_ms": 220.0, "sustain_min_ms": 300.0},
	"NormalAkici": {"chord_mode": "cift", "density_max": 5, "same_lane_min_ms": 260.0,
		"sustain_min_ms": 300.0, "preserve_notes": true, "assisted": true},
	# Faithful note count/density with mobile-only lane and overlap assistance.
	"Akici":  {"chord_mode": "tam", "density_max": 0, "same_lane_min_ms": 260.0,
		"sustain_min_ms": 0.0, "preserve_notes": true, "assisted": true},
	"Sadik":  {},  # empty = no processing
}
const PRESET_ORDER := [
	"Tiles", "TilesAkici", "Rahat", "RahatAkici",
	"Normal", "NormalAkici", "Sadik", "Akici",
]

static func is_assisted_preset(preset_name: String) -> bool:
	return bool(PRESETS.get(preset_name, {}).get("assisted", false))

# Settings
var chord_mode: String = "tek"    # "tek", "cift", "tam"
var density_max: int = 3          # max notes per 1s window
var same_lane_min_ms: float = 350.0
var sustain_min_ms: float = 500.0
var preserve_notes: bool = false
var resolution: int = 480
var enabled: bool = true

# Log counters
var _log_original: int = 0
var _log_chords_reduced: int = 0
var _log_density_removed: int = 0
var _log_lane_shifted: int = 0
var _log_lane_removed: int = 0
var _log_sustain_trimmed: int = 0
var _log_sustain_overlap: int = 0
var _log_zigzag: int = 0

func apply_preset(preset_name: String) -> void:
	preserve_notes = false
	if preset_name == "Sadik" or not PRESETS.has(preset_name):
		enabled = false
		return
	enabled = true
	var p: Dictionary = PRESETS[preset_name]
	chord_mode = p.get("chord_mode", "cift")
	density_max = p.get("density_max", 6)
	same_lane_min_ms = p.get("same_lane_min_ms", 150.0)
	sustain_min_ms = p.get("sustain_min_ms", 300.0)
	preserve_notes = bool(p.get("preserve_notes", false))

func process(notes: Array, res: int, lane_count: int) -> Array:
	if not enabled or notes.is_empty():
		return notes.duplicate(true)

	resolution = res
	_reset_log()
	_log_original = notes.size()

	var result := notes.duplicate(true)

	# Step 1: Chord reduction
	result = _reduce_chords(result)

	# Step 2: Sustain pruning (before density, so short sustains don't count as complex)
	result = _prune_sustains(result)

	# Step 3: Same-lane spacing
	result = _fix_same_lane_spacing(result, lane_count)

	# Step 4: Density limiting
	result = _limit_density(result)

	# Step 5: Clean sustain overlaps
	result = _clean_sustain_overlaps(result)

	_print_log(result.size())
	_print_comparison(notes, res, lane_count)
	return result

func _reset_log() -> void:
	_log_original = 0
	_log_chords_reduced = 0
	_log_density_removed = 0
	_log_lane_shifted = 0
	_log_lane_removed = 0
	_log_sustain_trimmed = 0
	_log_sustain_overlap = 0
	_log_zigzag = 0

func _print_log(final_count: int) -> void:
	var parts: Array[String] = []
	if _log_chords_reduced > 0:
		parts.append("%d akor indirgendi" % _log_chords_reduced)
	if _log_density_removed > 0:
		parts.append("%d yogunluktan elendi" % _log_density_removed)
	if _log_lane_shifted > 0:
		parts.append("%d lane kaydirma" % _log_lane_shifted)
	if _log_lane_removed > 0:
		parts.append("%d lane cakisma silme" % _log_lane_removed)
	if _log_sustain_trimmed > 0:
		parts.append("%d kisa sustain budandi" % _log_sustain_trimmed)
	if _log_sustain_overlap > 0:
		parts.append("%d sustain cakisma silme" % _log_sustain_overlap)
	if _log_zigzag > 0:
		parts.append("%d zigzag dagitim" % _log_zigzag)
	var detail := ", ".join(parts) if parts.size() > 0 else "degisiklik yok"
	print("Playability: %d nota -> %d nota (%s)" % [_log_original, final_count, detail])

# --- Step 1: Chord Reduction ---

func _reduce_chords(notes: Array) -> Array:
	if chord_mode == "tam":
		return notes

	var result: Array = []
	var i := 0
	while i < notes.size():
		# Collect chord (same time_ms)
		var chord_start := i
		var t: float = notes[i]["time_ms"]
		while i < notes.size() and absf(float(notes[i]["time_ms"]) - t) < 1.0:
			i += 1
		var chord_size := i - chord_start

		if chord_size <= 1:
			result.append(notes[chord_start])
			continue

		# Sort chord notes by lane
		var chord: Array = []
		for j in range(chord_start, i):
			chord.append(notes[j])
		chord.sort_custom(func(a, b): return int(a["lane"]) < int(b["lane"]))

		var keep_count := chord_size
		if chord_mode == "tek":
			keep_count = 1
		elif chord_mode == "cift":
			keep_count = mini(2, chord_size)

		for j in range(keep_count):
			result.append(chord[j])
		_log_chords_reduced += chord_size - keep_count

	return result

# --- Step 2: Sustain Pruning ---

func _prune_sustains(notes: Array) -> Array:
	for n in notes:
		var dur: float = n["duration_ms"]
		if dur > 0 and dur < sustain_min_ms:
			n["duration_ms"] = 0.0
			_log_sustain_trimmed += 1
	return notes

# --- Step 3: Same-Lane Spacing ---

func _fix_same_lane_spacing(notes: Array, lane_count: int) -> Array:
	var last_time := {}  # lane -> time_ms
	var consecutive_count := {}  # lane -> how many consecutive notes
	var result: Array = []

	for n in notes:
		var lane: int = n["lane"]
		var t: float = n["time_ms"]

		var too_close := last_time.has(lane) and t - float(last_time[lane]) < same_lane_min_ms

		# Track consecutive same-lane count
		if too_close:
			consecutive_count[lane] = consecutive_count.get(lane, 1) + 1
		else:
			consecutive_count[lane] = 1

		# Zigzag rule: 3+ consecutive on same lane → force distribute from 3rd onward
		var force_zigzag: bool = consecutive_count.get(lane, 1) >= 3

		if too_close or force_zigzag:
			var shifted := false
			# Prefer alternating sides for a zigzag feel, but inspect every lane.
			# The old fixed +/-2 list left lanes 3-4 unused when a burst started at
			# an edge, causing unnecessary same-lane stacks in five-lane charts.
			var offsets: Array[int] = []
			for distance in range(1, lane_count):
				offsets.append(distance)
				offsets.append(-distance)
			for offset in offsets:
				var new_lane: int = lane + offset
				if new_lane < 0 or new_lane >= lane_count:
					continue
				if not last_time.has(new_lane) or t - float(last_time[new_lane]) >= same_lane_min_ms:
					n["lane"] = new_lane
					last_time[new_lane] = t
					if force_zigzag and not too_close:
						_log_zigzag += 1
					else:
						_log_lane_shifted += 1
					shifted = true
					consecutive_count[lane] = 0
					break
			if not shifted:
				if preserve_notes:
					# Assisted Faithful mode keeps the authored note. The gameplay
					# layer will merge this rare no-free-lane case into a tap cluster.
					last_time[lane] = t
				else:
					_log_lane_removed += 1
					continue
		else:
			last_time[lane] = t

		result.append(n)

	return result

# --- Step 4: Density Limiting ---

func _limit_density(notes: Array) -> Array:
	if density_max <= 0:
		return notes

	# Sliding 1-second window
	var result: Array = []
	var window_notes: Array = []  # notes in current 1s window

	for n in notes:
		var t: float = n["time_ms"]

		# Remove notes outside the 1s window
		while window_notes.size() > 0 and t - float(window_notes[0]["time_ms"]) > 1000.0:
			window_notes.pop_front()

		if window_notes.size() >= density_max:
			# Over density — check if this note is on-beat
			var tick_approx := int(t)  # not real tick, but we can check beat alignment
			# Use a simple heuristic: keep notes at rounder times
			# We'll remove off-beat notes first
			if not _is_on_beat_approx(n, notes):
				_log_density_removed += 1
				continue

			# Still over? Skip every other excess note
			if window_notes.size() >= density_max:
				_log_density_removed += 1
				continue

		result.append(n)
		window_notes.append(n)

	return result

func _is_on_beat_approx(note: Dictionary, _all_notes: Array) -> bool:
	# Beat alignment heuristic — notes closer to a beat grid are kept.
	# Check multiple common grids (quarter, half, whole at ~120bpm = 500ms beat)
	var t: float = note["time_ms"]
	# Quarter-note grid (~500ms at 120bpm, ~430ms at 140bpm) — use 250ms as half-beat
	var grid_500 := fmod(t, 500.0)
	if grid_500 < 50.0 or grid_500 > 450.0:
		return true  # on a beat
	# Half-beat grid
	var grid_250 := fmod(t, 250.0)
	if grid_250 < 30.0 or grid_250 > 220.0:
		return true  # on a half-beat
	return false

# --- Step 5: Clean Sustain Overlaps ---

func _clean_sustain_overlaps(notes: Array) -> Array:
	# Remove notes that fall during an active sustain on the same lane
	var lane_sustain_end := {}  # lane -> end_time_ms
	var lane_sustain_note := {} # lane -> active sustain Dictionary
	var result: Array = []

	for n in notes:
		var lane: int = n["lane"]
		var t: float = n["time_ms"]
		var dur: float = n["duration_ms"]

		# Check if this note falls inside an active sustain on same lane
		if lane_sustain_end.has(lane) and t < float(lane_sustain_end[lane]) - 10.0:
			if preserve_notes:
				# Keep the new note and end the previous hold shortly before it.
				# This preserves Sadık's note count without asking one finger to
				# hold and retrigger the same lane simultaneously.
				var previous: Dictionary = lane_sustain_note[lane]
				var previous_start := float(previous["time_ms"])
				previous["duration_ms"] = maxf(0.0, t - previous_start - 60.0)
				_log_sustain_trimmed += 1
				lane_sustain_end.erase(lane)
				lane_sustain_note.erase(lane)
			else:
				_log_sustain_overlap += 1
				continue

		result.append(n)
		if dur > 0:
			lane_sustain_end[lane] = t + dur
			lane_sustain_note[lane] = n

	return result

func _print_comparison(original_notes: Array, res: int, lane_count: int) -> void:
	print("--- Preset Karsilastirma ---")
	for preset_name in PRESET_ORDER:
		var p = Playability.new()
		p.apply_preset(preset_name)
		if not p.enabled:
			print("  %-8s: %d nota (orijinal)" % [preset_name, _log_original])
		else:
			var tmp = p._run_pipeline(original_notes, res, lane_count)
			print("  %-8s: %d nota" % [preset_name, tmp.size()])
	print("----------------------------")

func _run_pipeline(notes: Array, res: int, lane_count: int) -> Array:
	resolution = res
	var result := notes.duplicate(true)
	result = _reduce_chords(result)
	result = _prune_sustains(result)
	result = _fix_same_lane_spacing(result, lane_count)
	result = _limit_density(result)
	result = _clean_sustain_overlaps(result)
	return result
