extends SceneTree

const ChartParserScript = preload("res://scripts/chart_parser.gd")

func _init() -> void:
	for diff in ["Easy", "Medium", "Hard", "Expert"]:
		var parser = ChartParserScript.new()
		parser.parse_file("res://notes.chart", diff)
		var lc := [0, 0, 0, 0, 0]
		for n in parser.notes:
			lc[int(n["lane"])] += 1
		print("[%s] %d notes -> lanes: %s" % [diff, parser.notes.size(), str(lc)])
	quit(0)
