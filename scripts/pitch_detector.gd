class_name PitchDetector
extends RefCounted

## Monophonic pitch detection for sung vocals, using the McLeod Pitch Method
## (normalised square difference + first-major-peak selection).
##
## MPM is chosen over plain autocorrelation because it does not systematically
## pick the octave below on harmonic-rich signals, which is exactly what a sung
## voice is. It is also cheaper than FFT-based methods at this window size, and
## Godot has no built-in FFT.
##
## `detect()` is pure and takes a raw buffer, so it can be unit tested against
## synthetic tones with no microphone involved. See VocalInput for the live
## capture side.

# Sung range plus headroom: a low male voice bottoms out near 80Hz, a soprano
# tops out near 1050Hz.
const MIN_HZ := 70.0
const MAX_HZ := 1200.0
# NSDF peak below this is treated as unvoiced (silence, noise, consonants).
const CLARITY_THRESHOLD := 0.55
# MPM: accept the first peak that reaches this fraction of the highest peak.
# Lower values bias toward the true fundamental over its octave.
const PEAK_RATIO := 0.85

const NOTE_NAMES := [
	"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


static func hz_to_midi(hz: float) -> float:
	if hz <= 0.0:
		return -1.0
	return 69.0 + 12.0 * (log(hz / 440.0) / log(2.0))


static func midi_to_hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


static func midi_note_name(midi: float) -> String:
	if midi < 0.0:
		return "--"
	var rounded := int(round(midi))
	return "%s%d" % [NOTE_NAMES[posmod(rounded, 12)], int(floor(rounded / 12.0)) - 1]


## Semitone distance between two pitches, ignoring octave. Rock Band scores
## vocals this way so a bass and a soprano can both sing the same line.
static func pitch_class_distance(midi_a: float, midi_b: float) -> float:
	var diff := fposmod(midi_a - midi_b, 12.0)
	return minf(diff, 12.0 - diff)


## Returns {hz, midi, clarity, voiced}. `hz` is 0.0 when unvoiced.
static func detect(samples: PackedFloat32Array, sample_rate: float) -> Dictionary:
	var unvoiced := {"hz": 0.0, "midi": -1.0, "clarity": 0.0, "voiced": false}
	var count := samples.size()
	if count < 64 or sample_rate <= 0.0:
		return unvoiced

	var min_lag := maxi(2, int(sample_rate / MAX_HZ))
	var max_lag := mini(count / 2, int(sample_rate / MIN_HZ))
	if max_lag <= min_lag:
		return unvoiced

	# Total power, plus running sums so the NSDF divisor is O(1) per lag
	# instead of O(N). Without this the whole thing is twice as expensive.
	var power := 0.0
	for i in range(count):
		power += samples[i] * samples[i]
	if power <= 1e-9:
		return unvoiced

	var nsdf := PackedFloat32Array()
	nsdf.resize(max_lag + 1)
	var head_sum := 0.0   # sum of squares of the first tau samples
	var tail_sum := 0.0   # sum of squares of the last tau samples
	for lag in range(1, min_lag):
		head_sum += samples[lag - 1] * samples[lag - 1]
		tail_sum += samples[count - lag] * samples[count - lag]
	for lag in range(min_lag, max_lag + 1):
		head_sum += samples[lag - 1] * samples[lag - 1]
		tail_sum += samples[count - lag] * samples[count - lag]
		var correlation := 0.0
		var limit := count - lag
		for i in range(limit):
			correlation += samples[i] * samples[i + lag]
		var divisor := 2.0 * power - head_sum - tail_sum
		nsdf[lag] = float(2.0 * correlation / divisor) if divisor > 1e-9 else 0.0

	# --- MPM peak picking ---
	# Collect the highest point of each positive hump, then take the earliest
	# hump that is nearly as tall as the tallest. Taking the tallest outright is
	# what makes naive autocorrelation jump an octave down on rich voices.
	var peak_lags := PackedInt32Array()
	var highest := 0.0
	var lag_index := min_lag
	# The NSDF opens near 1.0 and decays toward the first zero crossing. That
	# opening slope is not a peak, but for a low note it is still high at
	# min_lag — high enough to be picked as the "first major peak" and report a
	# pitch an octave or more too high. Skip past the first zero crossing.
	while lag_index < max_lag and nsdf[lag_index] > 0.0:
		lag_index += 1
	while lag_index < max_lag:
		# Walk to the start of a positive region.
		if nsdf[lag_index] <= 0.0 or nsdf[lag_index] < nsdf[lag_index - 1]:
			lag_index += 1
			continue
		var best_lag := lag_index
		while lag_index < max_lag and nsdf[lag_index] > 0.0:
			if nsdf[lag_index] > nsdf[best_lag]:
				best_lag = lag_index
			lag_index += 1
		peak_lags.append(best_lag)
		highest = maxf(highest, float(nsdf[best_lag]))
	if peak_lags.is_empty() or highest < CLARITY_THRESHOLD:
		return unvoiced

	var chosen_lag := -1
	var threshold := highest * PEAK_RATIO
	for candidate in peak_lags:
		if nsdf[candidate] >= threshold:
			chosen_lag = candidate
			break
	if chosen_lag <= 0:
		return unvoiced

	# Parabolic interpolation around the peak for sub-sample resolution; at
	# 16kHz a whole-sample lag is worth ~0.6 semitones up high, far too coarse.
	var refined := float(chosen_lag)
	if chosen_lag > min_lag and chosen_lag < max_lag:
		var left := float(nsdf[chosen_lag - 1])
		var mid := float(nsdf[chosen_lag])
		var right := float(nsdf[chosen_lag + 1])
		var denominator := 2.0 * (2.0 * mid - left - right)
		if absf(denominator) > 1e-9:
			refined += (right - left) / denominator
	if refined <= 0.0:
		return unvoiced

	var hz := sample_rate / refined
	if hz < MIN_HZ or hz > MAX_HZ:
		return unvoiced
	return {
		"hz": hz,
		"midi": hz_to_midi(hz),
		"clarity": float(nsdf[chosen_lag]),
		"voiced": true,
	}


## Pulls a detection back to the octave nearest the recent trend.
##
## Autocorrelation methods occasionally lock onto a sub-harmonic, and bleed from
## other instruments in an imperfectly separated stem pulls the same way. Both
## show up as the reading teleporting down an octave for a few frames. A singer
## does not move an octave in 30ms, so a candidate far from the trend is almost
## always the detector, not the voice.
static func snap_to_trend(
		candidate: float, trend: float, max_octaves := 2) -> float:
	if candidate < 0.0 or trend < 0.0:
		return candidate
	var best := candidate
	var best_distance := absf(candidate - trend)
	for shift in range(-max_octaves, max_octaves + 1):
		if shift == 0:
			continue
		var shifted := candidate + 12.0 * float(shift)
		var distance := absf(shifted - trend)
		if distance < best_distance:
			best_distance = distance
			best = shifted
	return best


## Median of the recent voiced readings, or -1 when there are none. Median
## rather than mean so one wild frame cannot drag the trend with it.
static func trend_of(history: PackedFloat32Array) -> float:
	var valid: Array = []
	for value in history:
		if value > 0.0:
			valid.append(value)
	if valid.is_empty():
		return -1.0
	valid.sort()
	return float(valid[valid.size() / 2])


## Cheap decimation with a box pre-filter. Voice tops out around 1.1kHz, so
## 48kHz capture carries nothing useful above the decimated Nyquist and the
## detector runs on a third of the samples.
static func downsample(
		samples: PackedFloat32Array, factor: int) -> PackedFloat32Array:
	if factor <= 1:
		return samples
	var out := PackedFloat32Array()
	var count := samples.size() / factor
	out.resize(count)
	for i in range(count):
		var total := 0.0
		var base := i * factor
		for j in range(factor):
			total += samples[base + j]
		out[i] = total / float(factor)
	return out
