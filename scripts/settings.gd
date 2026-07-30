extends RefCounted
class_name Settings

const SETTINGS_PATH := "user://settings.json"
const CUSTOM_ARENA_HIGHWAY_DIR := "user://visuals"
const CUSTOM_ARENA_HIGHWAY_PATH := "user://visuals/arena_highway.png"

# Defaults
static var approach_time_sec: float = 1.4
static var language: String = "tr"           # "tr" or "en"
static var highway_style: String = "gh"      # "gh" (3D perspective) or "flat"
static var vfx_quality: String = "balanced"  # "full", "balanced" or "performance"
static var rock_meter_mode: String = "visual" # "off", "visual" or "fail"
static var crowd_audio_enabled: bool = true
static var miss_sfx_enabled: bool = true
static var guitar_highway_theme: String = "neon" # "neon", "classic" or "midnight"
static var guitar_presentation_mode: String = "classic" # "classic" or "arena"
static var arena_fret_skin: String = "blade" # "blade", "anvil" or "coil"
static var arena_custom_highway_enabled: bool = false
static var pixel_stage_enabled: bool = true
static var pixel_stage_intensity: String = "live" # "subtle" or "live"

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
		if data.has("guitar_highway_theme"):
			var saved_theme := String(data["guitar_highway_theme"])
			if saved_theme in ["neon", "classic", "midnight"]:
				guitar_highway_theme = saved_theme
		if data.has("guitar_presentation_mode"):
			var saved_presentation := String(data["guitar_presentation_mode"])
			if saved_presentation in ["classic", "arena"]:
				guitar_presentation_mode = saved_presentation
		if data.has("arena_fret_skin"):
			var saved_fret_skin := String(data["arena_fret_skin"])
			if saved_fret_skin in ["blade", "anvil", "coil"]:
				arena_fret_skin = saved_fret_skin
		if data.has("arena_custom_highway_enabled"):
			arena_custom_highway_enabled = bool(
				data["arena_custom_highway_enabled"])
		if (arena_custom_highway_enabled
				and not FileAccess.file_exists(CUSTOM_ARENA_HIGHWAY_PATH)):
			arena_custom_highway_enabled = false
		if data.has("pixel_stage_enabled"):
			pixel_stage_enabled = bool(data["pixel_stage_enabled"])
		if data.has("pixel_stage_intensity"):
			var saved_stage_intensity := String(data["pixel_stage_intensity"])
			if saved_stage_intensity in ["subtle", "live"]:
				pixel_stage_intensity = saved_stage_intensity

static func save_settings() -> void:
	var data := {
		"approach_time_sec": approach_time_sec,
		"language": language,
		"highway_style": highway_style,
		"vfx_quality": vfx_quality,
		"rock_meter_mode": rock_meter_mode,
		"crowd_audio_enabled": crowd_audio_enabled,
		"miss_sfx_enabled": miss_sfx_enabled,
		"guitar_highway_theme": guitar_highway_theme,
		"guitar_presentation_mode": guitar_presentation_mode,
		"arena_fret_skin": arena_fret_skin,
		"arena_custom_highway_enabled": arena_custom_highway_enabled,
		"pixel_stage_enabled": pixel_stage_enabled,
		"pixel_stage_intensity": pixel_stage_intensity,
	}
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

static func get_approach_ms() -> float:
	return approach_time_sec * 1000.0
