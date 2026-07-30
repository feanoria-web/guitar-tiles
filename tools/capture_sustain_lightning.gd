extends SceneTree

const CAPTURE_SIZE := Vector2i(540, 960)
const LANE_COLORS := [
	Color("#49d86d"),
	Color("#ef3e46"),
	Color("#ffd33d"),
	Color("#3488ff"),
	Color("#ff8b24"),
]

var preview
var frame_count := 0


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(CAPTURE_SIZE)
	root.content_scale_size = CAPTURE_SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = CAPTURE_SIZE

	# game.gd is extended at runtime, after project autoload identifiers have
	# been registered. The override keeps its heavy chart/audio _ready path out
	# of this visual harness while preserving the real lightning implementation.
	var preview_script := GDScript.new()
	preview_script.source_code = """
extends "res://scripts/game.gd"
var preview_driver

func _ready() -> void:
	lane_count = 5
	_vfx_quality = "full"
	_adaptive_vfx_reduced = false
	_cached_lane_width = 88.0
	_cached_lanes_start_x = 50.0
	_cached_hit_line_y = 790.0
	_frame_time_sec = 1.35
	queue_redraw()

func _process(_delta: float) -> void:
	pass

func _draw() -> void:
	preview_driver._draw_preview(self)
"""
	var script_error := preview_script.reload()
	assert(script_error == OK)
	preview = preview_script.new()
	preview.preview_driver = self
	preview.position = Vector2.ZERO
	preview.size = Vector2(CAPTURE_SIZE)
	root.add_child(preview)


func _process(delta: float) -> bool:
	frame_count += 1
	preview._frame_time_sec += delta
	preview.queue_redraw()
	if frame_count < 10:
		return false

	var image := root.get_texture().get_image()
	assert(image != null)
	assert(not image.is_empty())
	assert(image.get_size() == CAPTURE_SIZE)
	var output_path := "res://tmp/sustain-lightning-mobile.png"
	var error := image.save_png(output_path)
	assert(error == OK)
	print("SUSTAIN LIGHTNING CAPTURE PASS: ", output_path, " ", image.get_size())
	quit(0)
	return true


# Called from the preview CanvasItem's real draw notification. Prefixing every
# command with `canvas` makes the draw target explicit and lets the final calls
# execute game.gd's shipped _draw_sustain_lightning_column implementation.
func _draw_preview(canvas) -> void:
	_draw_backdrop(canvas)
	_draw_highway(canvas)
	_draw_sustain_samples(canvas)


func _draw_backdrop(canvas) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(CAPTURE_SIZE)), Color("#050507"))
	for band in range(12):
		var band_rect := Rect2(
			0.0, float(band) * CAPTURE_SIZE.y / 12.0,
			CAPTURE_SIZE.x, CAPTURE_SIZE.y / 12.0 + 1.0)
		var shade := lerpf(0.055, 0.012, float(band) / 11.0)
		canvas.draw_rect(band_rect,
			Color(shade, shade * 0.90, shade * 0.72, 1.0))

	# Restrained stage haze keeps the dark edges readable in a phone capture.
	for radius in range(230, 20, -18):
		var alpha := 0.0025 + (230.0 - float(radius)) * 0.000015
		canvas.draw_circle(Vector2(270.0, 465.0), float(radius),
			Color(0.55, 0.32, 0.08, alpha))


func _draw_highway(canvas) -> void:
	var top_left := Vector2(164.0, 82.0)
	var top_right := Vector2(376.0, 82.0)
	var bottom_right := Vector2(535.0, 936.0)
	var bottom_left := Vector2(5.0, 936.0)
	canvas.draw_polygon(
		PackedVector2Array([top_left, top_right, bottom_right, bottom_left]),
		PackedColorArray([
			Color("#131216"), Color("#131216"),
			Color("#09090c"), Color("#09090c"),
		]))

	for lane in range(5):
		var left_ratio := float(lane) / 5.0
		var right_ratio := float(lane + 1) / 5.0
		var lane_poly := PackedVector2Array([
			top_left.lerp(top_right, left_ratio),
			top_left.lerp(top_right, right_ratio),
			bottom_left.lerp(bottom_right, right_ratio),
			bottom_left.lerp(bottom_right, left_ratio),
		])
		var lane_shade := 0.050 if lane % 2 == 0 else 0.028
		var lane_color := Color(
			lane_shade, lane_shade, lane_shade * 1.10, 0.72)
		canvas.draw_polygon(lane_poly, PackedColorArray([
			lane_color, lane_color, lane_color, lane_color,
		]))

	for divider in range(6):
		var ratio := float(divider) / 5.0
		canvas.draw_line(
			top_left.lerp(top_right, ratio),
			bottom_left.lerp(bottom_right, ratio),
			Color(0.58, 0.54, 0.48, 0.24), 1.25)

	for depth in range(8):
		var ratio := float(depth) / 7.0
		var eased := ratio * ratio
		var left := top_left.lerp(bottom_left, eased)
		var right := top_right.lerp(bottom_right, eased)
		canvas.draw_line(left, right, Color(0.55, 0.50, 0.43, 0.13),
			2.0 if depth == 7 else 1.0)

	canvas.draw_line(Vector2(30.0, 790.0), Vector2(510.0, 790.0),
		Color(1.0, 0.70, 0.20, 0.12), 16.0)
	canvas.draw_line(Vector2(30.0, 790.0), Vector2(510.0, 790.0),
		Color(1.0, 0.78, 0.35, 0.82), 2.0)


func _draw_sustain_samples(canvas) -> void:
	var samples := [
		{
			"from": Vector2(92.0, 708.0),
			"to": Vector2(198.0, 395.0),
			"color": LANE_COLORS[0],
			"intensity": 0.30,
			"index": 12,
			"lane": 0,
			"held": false,
		},
		{
			"from": Vector2(184.0, 738.0),
			"to": Vector2(229.0, 300.0),
			"color": LANE_COLORS[1],
			"intensity": 0.48,
			"index": 27,
			"lane": 1,
			"held": false,
		},
		{
			"from": Vector2(270.0, 790.0),
			"to": Vector2(270.0, 156.0),
			"color": LANE_COLORS[2],
			"intensity": 1.0,
			"index": 41,
			"lane": 2,
			"held": true,
		},
		{
			"from": Vector2(356.0, 750.0),
			"to": Vector2(319.0, 334.0),
			"color": LANE_COLORS[3],
			"intensity": 0.72,
			"index": 58,
			"lane": 3,
			"held": true,
		},
		{
			"from": Vector2(448.0, 674.0),
			"to": Vector2(356.0, 430.0),
			"color": LANE_COLORS[4],
			"intensity": 0.35,
			"index": 73,
			"lane": 4,
			"held": false,
		},
	]

	for sample in samples:
		var from: Vector2 = sample["from"]
		var to: Vector2 = sample["to"]
		var color: Color = sample["color"]
		var intensity: float = sample["intensity"]
		var held: bool = sample["held"]

		# A subdued lane-colored bed makes the actual bolt readable while
		# keeping game.gd's white-hot filaments visually dominant.
		canvas.draw_line(from, to, Color(color.r, color.g, color.b,
			0.055 + intensity * 0.08), 18.0 if held else 11.0)
		canvas._draw_sustain_lightning_column(
			from, to, color, intensity,
			int(sample["index"]), int(sample["lane"]), held)

		var head_radius := 20.0 if held else 14.0
		canvas.draw_circle(from, head_radius * 1.8,
			Color(color.r, color.g, color.b, 0.08 + intensity * 0.10))
		canvas.draw_circle(from, head_radius,
			Color(color.r, color.g, color.b, 0.48 + intensity * 0.30))
		canvas.draw_circle(from, head_radius * 0.43,
			Color(1.0, 1.0, 0.92, 0.78 + intensity * 0.20))
