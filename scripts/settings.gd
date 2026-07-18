extends RefCounted
class_name Settings

const SETTINGS_PATH := "user://settings.json"

# Defaults
static var orientation: String = "portrait"  # "portrait" or "landscape"
static var approach_time_sec: float = 1.4    # portrait default; landscape default is 1.15

static func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		f.close()
		return
	f.close()
	var data = json.data
	if data is Dictionary:
		if data.has("orientation"):
			orientation = data["orientation"]
		if data.has("approach_time_sec"):
			approach_time_sec = float(data["approach_time_sec"])

static func save_settings() -> void:
	var data := {
		"orientation": orientation,
		"approach_time_sec": approach_time_sec,
	}
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

static func get_approach_ms() -> float:
	return approach_time_sec * 1000.0

static func default_approach_for_orientation() -> float:
	return 1.4 if orientation == "portrait" else 1.15
