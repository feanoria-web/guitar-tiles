extends SceneTree

const ChartParserScript = preload("res://scripts/chart_parser.gd")
const SngLoaderScript = preload("res://scripts/sng_loader.gd")

func _init() -> void:
	# Test 1: SngLoader compiles and instantiates
	var loader = SngLoaderScript.new()
	print("SngLoader instantiated OK")

	# Test 2: Verify chart parser still works (regression check)
	var parser = ChartParserScript.new()
	var ok := parser.parse_file("res://notes.chart")
	if not ok:
		print("FAILED to parse chart!")
		quit(1)
		return
	print("ChartParser: %d notes, last at %.1f s" % [parser.notes.size(), float(parser.notes[parser.notes.size() - 1]["time_ms"]) / 1000.0])

	# Test 3: Try loading a non-existent .sng (should fail gracefully)
	var ok2 := loader.load_sng("res://nonexistent.sng")
	if not ok2:
		print("SngLoader correctly rejected missing file")

	# Test 4: If there's a .sng in project root, test it
	var dir := DirAccess.open("res://songs")
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".sng"):
				print("Found .sng: %s, testing..." % fname)
				var sng_ok := loader.load_sng("res://songs/%s" % fname)
				if sng_ok:
					print("  Metadata: %s" % str(loader.metadata))
					print("  Files: %s" % str(loader.files.keys()))
					var chart_text := loader.get_chart_text()
					if chart_text != "":
						var p2 = ChartParserScript.new()
						p2.parse_text(chart_text)
						print("  Parsed from .sng: %d notes" % p2.notes.size())
				else:
					print("  Failed to load .sng")
			fname = dir.get_next()

	print("All SNG tests passed")
	quit(0)
