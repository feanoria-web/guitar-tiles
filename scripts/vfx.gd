extends RefCounted
class_name VFX

# Spritesheet effect definitions (30fps sheets from the free VFX pack).
# fw/fh = frame size in the (downscaled) sheet, cols = grid columns.
const DEFS := {
	"pixel_fire": {"path": "res://assets/vfx/pixel_fire.png", "fw": 173.0, "fh": 193.0, "cols": 6, "frames": 30, "fps": 30.0},
	# Brackeys VFX Bundle electric ring (CC0), converted to a neutral alpha mask
	# so the looping hold effect can inherit each lane color.
	"hold_ring": {"path": "res://assets/vfx/brackeys_electric_ring.png", "fw": 265.0, "fh": 265.0, "cols": 6, "frames": 30, "fps": 30.0},
	"sustain_fire": {"path": "res://assets/vfx/brackeys_fire_04.png", "fw": 128.0, "fh": 128.0, "cols": 8, "frames": 64, "fps": 30.0},
	"sustain_smoke": {"path": "res://assets/vfx/brackeys_wispy_smoke_01.png", "fw": 128.0, "fh": 128.0, "cols": 8, "frames": 64, "fps": 30.0},
	"combo_impact": {"path": "res://assets/vfx/brackeys_impact_white.png", "fw": 291.0, "fh": 301.0, "cols": 6, "frames": 24, "fps": 30.0},
	"combo_streaks": {"path": "res://assets/vfx/brackeys_lightstreaks.png", "fw": 256.0, "fh": 256.0, "cols": 6, "frames": 30, "fps": 30.0},
	"impact": {"path": "res://assets/vfx/impact.png", "fw": 247.5, "fh": 256.0, "cols": 6, "frames": 30, "fps": 30.0},
	"puff": {"path": "res://assets/vfx/puff.png", "fw": 120.0, "fh": 109.0, "cols": 7, "frames": 40, "fps": 30.0},
	"hyperspeed": {"path": "res://assets/vfx/hyperspeed.png", "fw": 256.0, "fh": 255.0, "cols": 6, "frames": 30, "fps": 30.0},
}

# Note skin textures
const NOTE_SKINS := {
	"tile_green": "res://assets/notes/tile_green.png",
	"tile_red": "res://assets/notes/tile_red.png",
	"tile_yellow": "res://assets/notes/tile_yellow.png",
	"tile_blue": "res://assets/notes/tile_blue.png",
	"tile_orange": "res://assets/notes/tile_orange.png",
	"ball_grey": "res://assets/notes/ball_grey.png",
	"gh_fret": "res://assets/notes/gh_fret_metal.png",
}

static var _tex_cache: Dictionary = {}
static var _region_cache: Dictionary = {}
static var _fps_cache: Dictionary = {}
static var _frame_count_cache: Dictionary = {}
static var _aspect_cache: Dictionary = {}
static var _uv_cache: Dictionary = {}

static func preload_effects(include_heavy: bool = true) -> void:
	# Keep disk/resource loading out of the first gameplay frame in which an
	# effect appears. Calling get_rid() also prepares the rendering resource.
	var keys := ["impact", "puff", "hold_ring", "sustain_fire", "combo_impact"]
	if include_heavy:
		keys.append_array(["sustain_smoke", "combo_streaks", "hyperspeed"])
	for key in keys:
		var texture := tex(key as String)
		if texture:
			texture.get_rid()
		_prepare_animation_cache(key as String)

static func tex(key: String) -> Texture2D:
	if _tex_cache.has(key):
		return _tex_cache[key]
	var path: String = ""
	if DEFS.has(key):
		path = DEFS[key]["path"]
	elif NOTE_SKINS.has(key):
		path = NOTE_SKINS[key]
	if path == "":
		return null
	var t := load(path) as Texture2D
	_tex_cache[key] = t
	return t

# Source region for frame index of a sheet effect.
static func frame_region(name: String, frame: int) -> Rect2:
	_prepare_animation_cache(name)
	var regions: Array = _region_cache[name]
	return regions[posmod(frame, regions.size())]

static func frame_uvs(name: String, frame: int) -> PackedVector2Array:
	_prepare_animation_cache(name)
	var uv_frames: Array = _uv_cache[name]
	return uv_frames[posmod(frame, uv_frames.size())]

static func frame_count(name: String) -> int:
	_prepare_animation_cache(name)
	return int(_frame_count_cache[name])

static func fps(name: String) -> float:
	_prepare_animation_cache(name)
	return float(_fps_cache[name])

# Frame index for a looping animation driven by engine time.
static func loop_frame(name: String, speed: float = 1.0, phase: float = 0.0) -> int:
	var t := Time.get_ticks_msec() / 1000.0 * speed + phase
	return int(t * fps(name)) % frame_count(name)

# Same calculation as loop_frame(), using the timestamp already captured by
# the caller for this render frame.
static func loop_frame_at(name: String, time_sec: float, speed: float = 1.0, phase: float = 0.0) -> int:
	return int((time_sec * speed + phase) * fps(name)) % frame_count(name)

# Aspect ratio (w/h) of one frame, for sizing draws.
static func frame_aspect(name: String) -> float:
	_prepare_animation_cache(name)
	return float(_aspect_cache[name])

static func _prepare_animation_cache(name: String) -> void:
	if _region_cache.has(name):
		return
	var d: Dictionary = DEFS[name]
	var frame_total := int(d["frames"])
	var cols := int(d["cols"])
	var fw := float(d["fw"])
	var fh := float(d["fh"])
	var regions: Array[Rect2] = []
	var uv_frames: Array[PackedVector2Array] = []
	regions.resize(frame_total)
	uv_frames.resize(frame_total)
	var texture_size := tex(name).get_size()
	for frame in range(frame_total):
		var col := frame % cols
		var row := frame / cols
		var region := Rect2(col * fw, row * fh, fw, fh)
		regions[frame] = region
		var u0 := region.position.x / texture_size.x
		var v0 := region.position.y / texture_size.y
		var u1 := region.end.x / texture_size.x
		var v1 := region.end.y / texture_size.y
		uv_frames[frame] = PackedVector2Array([
			Vector2(u0, v1), Vector2(u0, v0),
			Vector2(u1, v0), Vector2(u1, v1)])
	_region_cache[name] = regions
	_uv_cache[name] = uv_frames
	_frame_count_cache[name] = frame_total
	_fps_cache[name] = float(d["fps"])
	_aspect_cache[name] = fw / fh
