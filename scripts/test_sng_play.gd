extends SceneTree

const GameScript = preload("res://scripts/game.gd")

func _init() -> void:
	var dir := DirAccess.open("res://songs")
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".sng"):
				GameScript.song_source = "res://songs/" + fname
				print("Selected: %s" % fname)
				break
			fname = dir.get_next()

	if GameScript.song_source == "":
		print("No .sng found in songs/")
		quit(1)
		return

	var scene = load("res://scenes/game.tscn")
	var instance = scene.instantiate()
	root.add_child(instance)

	# Let it run briefly to check audio loading
	await create_timer(3.0).timeout
	quit(0)
