extends RefCounted
class_name Settings

const SETTINGS_PATH := "user://settings.json"

# Defaults
static var approach_time_sec: float = 1.4
static var language: String = "tr"           # "tr" or "en"
static var highway_style: String = "gh"      # "gh" (3D perspective) or "flat"
static var vfx_quality: String = "balanced"  # "full", "balanced" or "performance"
static var rock_meter_mode: String = "visual" # "off", "visual" or "fail"
static var crowd_audio_enabled: bool = true
static var miss_sfx_enabled: bool = true

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
		if data.has("approach_time_sec"):
			approach_time_sec = float(data["approach_time_sec"])
		if data.has("language"):
			language = data["language"]
		if data.has("highway_style"):
			highway_style = data["highway_style"]
		if data.has("vfx_quality"):
			var saved_quality := String(data["vfx_quality"])
			if saved_quality in ["full", "balanced", "performance"]:
				vfx_quality = saved_quality
		if data.has("rock_meter_mode"):
			var saved_rock_meter := String(data["rock_meter_mode"])
			if saved_rock_meter in ["off", "visual", "fail"]:
				rock_meter_mode = saved_rock_meter
		if data.has("crowd_audio_enabled"):
			crowd_audio_enabled = bool(data["crowd_audio_enabled"])
		if data.has("miss_sfx_enabled"):
			miss_sfx_enabled = bool(data["miss_sfx_enabled"])

static func save_settings() -> void:
	var data := {
		"approach_time_sec": approach_time_sec,
		"language": language,
		"highway_style": highway_style,
		"vfx_quality": vfx_quality,
		"rock_meter_mode": rock_meter_mode,
		"crowd_audio_enabled": crowd_audio_enabled,
		"miss_sfx_enabled": miss_sfx_enabled,
	}
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

static func get_approach_ms() -> float:
	return approach_time_sec * 1000.0
