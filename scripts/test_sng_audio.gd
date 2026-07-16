extends SceneTree

const SngLoaderScript = preload("res://scripts/sng_loader.gd")

func _init() -> void:
	# Check if GDExtension is loaded
	print("AudioStreamOpus exists: %s" % str(ClassDB.class_exists("AudioStreamOpus")))

	# Extract Bring Me To Life
	var sng_path := "res://songs/Evanescence - Bring Me to Life (Add Keyboard) (Harmonix; Austin Tomlinson).sng"
	var loader = SngLoaderScript.new()
	if not loader.load_sng(sng_path):
		print("FAILED to load SNG")
		quit(1)
		return

	var tmp := "user://sng_test"
	DirAccess.make_dir_recursive_absolute(tmp)
	loader.extract_to_dir(tmp)

	# Try loading song.opus
	var opus_path := tmp.path_join("song.opus")
	var f := FileAccess.open(opus_path, FileAccess.READ)
	if not f:
		print("Cannot open: %s" % opus_path)
		quit(1)
		return
	var data := f.get_buffer(f.get_length())
	f.close()
	print("Read %d bytes from song.opus" % data.size())
	print("Header: %02x %02x %02x %02x" % [data[0], data[1], data[2], data[3]])

	if ClassDB.class_exists("AudioStreamOpus"):
		var stream = ClassDB.instantiate("AudioStreamOpus")
		stream.set("data", data)
		print("AudioStreamOpus created: %s" % str(stream))
		print("Stream length: %s" % str(stream.get("length")))
	else:
		print("ERROR: AudioStreamOpus not available!")

	quit(0)
