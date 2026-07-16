extends SceneTree

const ChartParserScript = preload("res://scripts/chart_parser.gd")

func _init() -> void:
	var parser = ChartParserScript.new()
	var ok := parser.parse_file("res://notes.chart")
	if not ok:
		print("FAILED to parse chart!")
		quit(1)
		return
	parser.print_summary()
	quit(0)
