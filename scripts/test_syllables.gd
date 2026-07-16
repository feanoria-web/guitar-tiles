extends SceneTree

const ChartParserScript = preload("res://scripts/chart_parser.gd")

func _init() -> void:
	var parser = ChartParserScript.new()
	parser.parse_file("res://notes.chart", "Expert")
	print("Phrases: %d\n" % parser.lyric_phrases.size())

	for i in range(mini(5, parser.lyric_phrases.size())):
		var p = parser.lyric_phrases[i]
		print("[%.1fs] \"%s\"" % [float(p["start_ms"]) / 1000.0, p["text"]])
		var syls: Array = p["syllables"]
		for s in syls:
			var t: float = s["time_ms"]
			var cs: int = s["char_start"]
			var ce: int = s["char_end"]
			var txt: String = p["text"]
			print("  %.1fs  [%d:%d] \"%s\"" % [t / 1000.0, cs, ce, txt.substr(cs, ce - cs)])
		print("")
	quit(0)
