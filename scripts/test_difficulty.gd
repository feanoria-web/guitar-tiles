extends SceneTree

const ChartParserScript = preload("res://scripts/chart_parser.gd")

func _init() -> void:
	# Test difficulty scanning
	var diffs = ChartParserScript.scan_difficulties_from_file("res://notes.chart")
	print("Available difficulties: %s" % str(diffs))

	# Test parsing each difficulty
	for diff in diffs:
		var parser = ChartParserScript.new()
		parser.parse_file("res://notes.chart", diff)
		print("  [%s] %d notes" % [diff, parser.notes.size()])

	# Test piano lane merging
	var parser = ChartParserScript.new()
	parser.parse_file("res://notes.chart", "Expert")
	var original_count: int = parser.notes.size()

	# Count lanes
	var lane_counts := [0, 0, 0, 0, 0]
	for n in parser.notes:
		lane_counts[int(n["lane"])] += 1
	print("\nGuitar lanes: %s (total %d)" % [str(lane_counts), original_count])

	# Simulate piano merge
	var time_set := {}
	for n in parser.notes:
		if int(n["lane"]) == 3:
			var key := "%.1f" % float(n["time_ms"])
			time_set[key] = true

	var merged_count := 0
	var skipped := 0
	for n in parser.notes:
		if int(n["lane"]) == 4:
			var key := "%.1f" % float(n["time_ms"])
			if time_set.has(key):
				skipped += 1
				continue
			time_set[key] = true
		merged_count += 1

	print("Piano mode: %d notes (%d blue+orange merged, %d duplicates removed)" % [merged_count, lane_counts[4] - skipped, skipped])

	quit(0)
