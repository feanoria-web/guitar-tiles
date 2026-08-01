class_name VocalsScoring
extends RefCounted

## Phrase-based vocal scoring, the way Rock Band grades singing.
##
## Individual notes are not scored on their own. Time held on pitch accumulates
## across a whole phrase, and the phrase is awarded a tier when it ends. That is
## what makes singing feel forgiving: missing the attack of one syllable barely
## moves a phrase, while being flat for a whole line clearly does.

signal phrase_completed(result: Dictionary)

enum Tier { MISS, OK, STRONG, AWESOME }

# Fraction of a phrase's singable time that has to land on pitch.
const TIER_AWESOME := 0.75
const TIER_STRONG := 0.55
const TIER_OK := 0.35
# Singers scoop into a note and let its tail go; charts also hold notes longer
# than anyone sustains them. Grading the attack and the tail made accurate
# singing score badly, so both ends are excluded from the phrase total.
const NOTE_ONSET_GRACE := 0.18
const NOTE_TAIL_GRACE := 0.12
# Being slightly outside tolerance is not the same as being silent. Between one
# and two times the tolerance still earns partial credit, which removes the
# cliff edge that made the mode feel arbitrary.
const NEAR_MISS_CREDIT := 0.5

const TIER_NAMES := {
	Tier.AWESOME: "AWESOME",
	Tier.STRONG: "STRONG",
	Tier.OK: "OK",
	Tier.MISS: "MISS",
}
const TIER_SCORE := {
	Tier.AWESOME: 1000,
	Tier.STRONG: 700,
	Tier.OK: 400,
	Tier.MISS: 0,
}
# Semitone tolerance by difficulty, octave-agnostic.
const TOLERANCE := {
	"Easy": 3.0,
	"Medium": 2.2,
	"Hard": 1.6,
	"Expert": 1.2,
}

var notes: Array = []
var phrases: Array = []
var tolerance_semitones := 1.6

var score := 0
var phrase_streak := 0
var completed_phrases := 0
## Per-note fraction held on pitch, index-aligned with `notes`. Drives the
## highway's note fill.
var note_progress := PackedFloat32Array()

var _note_matched_ms := PackedFloat32Array()
var _phrase_index := 0
var _last_time_ms := -1.0
var _search_from := 0


func setup(source_notes: Array, source_phrases: Array, difficulty := "Hard") -> void:
	notes = source_notes
	phrases = source_phrases
	tolerance_semitones = float(TOLERANCE.get(difficulty, 1.6))
	note_progress = PackedFloat32Array()
	note_progress.resize(notes.size())
	_note_matched_ms = PackedFloat32Array()
	_note_matched_ms.resize(notes.size())
	score = 0
	phrase_streak = 0
	completed_phrases = 0
	_phrase_index = 0
	_last_time_ms = -1.0
	_search_from = 0


## Call once per frame. `detected_midi` is the sung pitch, `voiced` false when
## the singer is silent.
func update(time_ms: float, detected_midi: float, voiced: bool) -> void:
	if _last_time_ms < 0.0:
		_last_time_ms = time_ms
		return
	# Credit the elapsed slice rather than a frame count, so scoring does not
	# depend on frame rate.
	var slice_ms := clampf(time_ms - _last_time_ms, 0.0, 100.0)
	_last_time_ms = time_ms
	if slice_ms > 0.0:
		_credit(time_ms, slice_ms, detected_midi, voiced)
	_close_finished_phrases(time_ms)


func _credit(time_ms: float, slice_ms: float, detected_midi: float,
		voiced: bool) -> void:
	# Notes are time-ordered, so the scan only ever moves forward.
	while _search_from < notes.size() \
			and float(notes[_search_from]["end_ms"]) < time_ms - 200.0:
		_search_from += 1
	for index in range(_search_from, notes.size()):
		var note: Dictionary = notes[index]
		var start_ms := float(note["time_ms"])
		if start_ms > time_ms:
			break
		if float(note["end_ms"]) < time_ms:
			continue
		if not voiced:
			continue
		var span := maxf(float(note["end_ms"]) - start_ms, 1.0)
		# Skip the scoop in and the release; see NOTE_ONSET_GRACE.
		if time_ms < start_ms + span * NOTE_ONSET_GRACE:
			continue
		if time_ms > float(note["end_ms"]) - span * NOTE_TAIL_GRACE:
			continue
		# A non-pitched syllable only asks for sound, not a pitch.
		var credit := 0.0
		if bool(note["non_pitched"]):
			credit = 1.0
		elif detected_midi > 0.0:
			var distance := PitchDetector.pitch_class_distance(
				detected_midi, float(note["midi_note"]))
			if distance <= tolerance_semitones:
				credit = 1.0
			elif distance <= tolerance_semitones * 2.0:
				credit = NEAR_MISS_CREDIT
		if credit <= 0.0:
			continue
		_note_matched_ms[index] += slice_ms * credit
		note_progress[index] = clampf(
			_note_matched_ms[index] / (span * _gradeable_fraction()), 0.0, 1.0)


## Portion of a note that is actually graded, once both grace windows are off.
func _gradeable_fraction() -> float:
	return maxf(1.0 - NOTE_ONSET_GRACE - NOTE_TAIL_GRACE, 0.05)


func _close_finished_phrases(time_ms: float) -> void:
	while _phrase_index < phrases.size():
		var phrase: Dictionary = phrases[_phrase_index]
		if time_ms < float(phrase["end_ms"]):
			return
		_award(phrase)
		_phrase_index += 1


func _award(phrase: Dictionary) -> void:
	var start_ms := float(phrase["start_ms"])
	var end_ms := float(phrase["end_ms"])
	var singable_ms := 0.0
	var matched_ms := 0.0
	for index in range(notes.size()):
		var note: Dictionary = notes[index]
		var note_start := float(note["time_ms"])
		if note_start < start_ms or note_start >= end_ms:
			continue
		var note_span := maxf(float(note["end_ms"]) - note_start, 1.0)
		singable_ms += note_span * _gradeable_fraction()
		matched_ms += float(_note_matched_ms[index])
	# A phrase with no notes in it is a rest; it is not graded at all.
	if singable_ms <= 0.0:
		return
	var accuracy := clampf(matched_ms / singable_ms, 0.0, 1.0)
	var tier := Tier.MISS
	if accuracy >= TIER_AWESOME:
		tier = Tier.AWESOME
	elif accuracy >= TIER_STRONG:
		tier = Tier.STRONG
	elif accuracy >= TIER_OK:
		tier = Tier.OK

	if tier == Tier.MISS:
		phrase_streak = 0
	else:
		phrase_streak += 1
	# Streak multiplier caps at 4x, matching the instrument tracks' feel.
	var multiplier := mini(1 + phrase_streak / 4, 4)
	var awarded := int(TIER_SCORE[tier]) * multiplier
	if bool(phrase.get("overdrive", false)):
		awarded *= 2
	score += awarded
	completed_phrases += 1
	phrase_completed.emit({
		"accuracy": accuracy,
		"tier": tier,
		"tier_name": String(TIER_NAMES[tier]),
		"score": awarded,
		"multiplier": multiplier,
		"overdrive": bool(phrase.get("overdrive", false)),
		"start_ms": start_ms,
		"end_ms": end_ms,
	})
