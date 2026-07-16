extends SceneTree

const ChartParserScript = preload("res://scripts/chart_parser.gd")

func _init() -> void:
	var parser = ChartParserScript.new()
	parser.parse_file("res://notes.chart")
	print("Lyric phrases: %d" % parser.lyric_phrases.size())
	print("")
	for i in range(mini(10, parser.lyric_phrases.size())):
		var p = parser.lyric_phrases[i]
		print("  [%.1fs - %.1fs] %s" % [float(p["start_ms"]) / 1000.0, float(p["end_ms"]) / 1000.0, p["text"]])
	quit(0)
