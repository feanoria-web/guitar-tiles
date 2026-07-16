extends SceneTree

func _init() -> void:
	var scene = load("res://scenes/game.tscn")
	if scene == null:
		print("FAILED: could not load game.tscn")
		quit(1)
		return
	print("game.tscn loaded OK")
	var instance = scene.instantiate()
	print("Game scene instantiated OK")
	instance.queue_free()
	quit(0)
