extends RefCounted
class_name UITheme

# Original hard-rock rhythm-game design system shared by menu + game.
# The chrome uses scorched metal, worn print and tungsten stage light. Gameplay
# lane/effect colors remain free to communicate notes, streaks and feedback.

# --- Palette ---
const ROCK_COAL := Color(0.043, 0.035, 0.031)
const ROCK_CHARRED := Color(0.090, 0.067, 0.055)
const ROCK_IRON := Color(0.165, 0.145, 0.129)
const ROCK_STEEL := Color(0.318, 0.282, 0.239)
const ROCK_STEEL_LIGHT := Color(0.48, 0.43, 0.37)
const ROCK_IVORY := Color(0.91, 0.87, 0.78)
const ROCK_PARCHMENT := Color(0.66, 0.60, 0.51)
const ROCK_AMBER := Color(0.90, 0.63, 0.10)
const ROCK_AMBER_HOT := Color(1.0, 0.83, 0.47)
const ROCK_RED := Color(0.65, 0.18, 0.11)
const ROCK_DANGER := Color(0.82, 0.23, 0.13)
const ROCK_READY := Color(0.43, 0.66, 0.24)

# Keep the original gameplay semantics intact. Menu code opts into the ROCK_*
# palette explicitly, so the highway, streak tiers, stage and HUD retain their
# established color language.
const BG_TOP := Color(0.045, 0.035, 0.10)
const BG_BOTTOM := Color(0.02, 0.015, 0.05)
const NEON_CYAN := Color(0.10, 0.85, 1.0)
const NEON_MAGENTA := Color(1.0, 0.25, 0.72)
const NEON_PURPLE := Color(0.58, 0.35, 1.0)
const NEON_GREEN := Color(0.25, 1.0, 0.55)
const NEON_GOLD := Color(1.0, 0.85, 0.25)
const NEON_RED := Color(1.0, 0.30, 0.25)
const NEON_BLUE := Color(0.30, 0.64, 1.0)

const CARD_BG := Color(0.10, 0.09, 0.17, 0.92)
const CARD_BORDER := Color(0.35, 0.30, 0.55, 0.55)
const PANEL_BG := Color(0.07, 0.06, 0.13, 0.97)
const TEXT_BRIGHT := Color(0.96, 0.95, 1.0)
const TEXT_DIM := Color(0.62, 0.60, 0.74)
const TEXT_FAINT := Color(0.42, 0.40, 0.55)

const ARENA_BG_PATH := "res://assets/ui/riffline_hardrock_bg.png"
const GAME_LOGO_PATH := "res://assets/ui/riffline_logo_mark.png"

static var _font_bold: Font = null
static var _font_regular: Font = null

static func font_bold() -> Font:
	if _font_bold == null:
		_font_bold = load("res://fonts/Inter-Bold.ttf") as Font
	return _font_bold

static func font_regular() -> Font:
	if _font_regular == null:
		_font_regular = load("res://fonts/Inter-Regular.ttf") as Font
	return _font_regular

# --- Theme ---

static func create_theme() -> Theme:
	var t := Theme.new()
	var fb := font_bold()
	var fr := font_regular()
	if fb:
		t.set_default_font(fb)
		t.set_font("font", "Button", fb)
		t.set_font("font", "OptionButton", fb)
	if fr:
		t.set_font("font", "Label", fr)
		t.set_font("font", "RichTextLabel", fr)
	t.set_color("font_color", "Label", TEXT_BRIGHT)
	t.set_color("font_color", "Button", TEXT_BRIGHT)
	t.set_font_size("font_size", "Label", 19)
	t.set_font_size("font_size", "Button", 20)
	t.set_font_size("font_size", "OptionButton", 20)

	# Default button: stamped iron plate with a hard lower lip.
	var btn_n := flat_style(Color(0.105, 0.086, 0.073, 0.98), 4)
	btn_n.border_color = ROCK_STEEL
	btn_n.set_border_width_all(1)
	btn_n.border_width_bottom = 4
	btn_n.content_margin_left = 24; btn_n.content_margin_right = 24
	btn_n.content_margin_top = 15; btn_n.content_margin_bottom = 15
	t.set_stylebox("normal", "Button", btn_n)
	var btn_h := btn_n.duplicate()
	btn_h.bg_color = ROCK_IRON
	btn_h.border_color = NEON_CYAN
	btn_h.shadow_color = Color(0, 0, 0, 0.72)
	btn_h.shadow_size = 6
	btn_h.shadow_offset = Vector2(3, 4)
	t.set_stylebox("hover", "Button", btn_h)
	var btn_p := btn_n.duplicate()
	btn_p.bg_color = Color(0.22, 0.15, 0.10)
	btn_p.border_color = NEON_MAGENTA
	btn_p.border_width_bottom = 2
	t.set_stylebox("pressed", "Button", btn_p)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	# OptionButton
	var opt_n := flat_style(Color(0.082, 0.068, 0.058, 0.99), 4)
	opt_n.border_color = ROCK_STEEL
	opt_n.set_border_width_all(1)
	opt_n.border_width_left = 4
	opt_n.content_margin_left = 18; opt_n.content_margin_right = 18
	opt_n.content_margin_top = 12; opt_n.content_margin_bottom = 12
	t.set_stylebox("normal", "OptionButton", opt_n)
	var opt_h := opt_n.duplicate()
	opt_h.bg_color = ROCK_IRON
	opt_h.border_color = NEON_CYAN
	t.set_stylebox("hover", "OptionButton", opt_h)
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_color("font_color", "OptionButton", TEXT_BRIGHT)

	# Line edits used by online rooms.
	var edit_n := flat_style(Color(0.035, 0.030, 0.027, 0.98), 4)
	edit_n.border_color = ROCK_STEEL
	edit_n.set_border_width_all(2)
	edit_n.content_margin_left = 20; edit_n.content_margin_right = 20
	edit_n.content_margin_top = 13; edit_n.content_margin_bottom = 13
	t.set_stylebox("normal", "LineEdit", edit_n)
	var edit_focus := edit_n.duplicate()
	edit_focus.border_color = NEON_CYAN
	edit_focus.shadow_color = Color(0, 0, 0, 0.78)
	edit_focus.shadow_size = 7
	edit_focus.shadow_offset = Vector2(3, 4)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_color("font_color", "LineEdit", TEXT_BRIGHT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_FAINT)
	t.set_font_size("font_size", "LineEdit", 22)

	# Slider
	var slider_bg := flat_style(Color(0.12, 0.10, 0.085), 2)
	slider_bg.border_color = ROCK_STEEL
	slider_bg.set_border_width_all(1)
	slider_bg.content_margin_top = 6; slider_bg.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", slider_bg)
	var slider_fill := glow_style(
		Color(NEON_MAGENTA.r, NEON_MAGENTA.g, NEON_MAGENTA.b, 0.55),
		NEON_MAGENTA, 5, 5)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)

	# Progress bars should read as energy meters.
	var progress_bg := flat_style(Color(0.025, 0.021, 0.019, 0.98), 2)
	progress_bg.border_color = ROCK_STEEL
	progress_bg.set_border_width_all(1)
	var progress_fill := glow_style(
		Color(NEON_CYAN.r, NEON_CYAN.g, NEON_CYAN.b, 0.70),
		NEON_CYAN, 7, 6)
	t.set_stylebox("background", "ProgressBar", progress_bg)
	t.set_stylebox("fill", "ProgressBar", progress_fill)
	t.set_color("font_color", "ProgressBar", TEXT_BRIGHT)
	t.set_font_size("font_size", "ProgressBar", 16)

	# Scrollbar — slim
	var sb := flat_style(Color(0.42, 0.36, 0.29, 0.72), 2)
	t.set_stylebox("grabber", "VScrollBar", sb)
	var sb_bg := flat_style(Color(0, 0, 0, 0), 4)
	t.set_stylebox("scroll", "VScrollBar", sb_bg)

	return t

# --- StyleBox factories ---

static func flat_style(bg: Color, radius: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(mini(radius, 6))
	return s

# Kept as a compatibility factory, but rendered as a weighty metal plate rather
# than a colored neon halo.
static func glow_style(bg: Color, glow: Color, radius: int = 14, glow_size: int = 8) -> StyleBoxFlat:
	var s := flat_style(bg, radius)
	s.shadow_color = Color(0, 0, 0, 0.72)
	s.shadow_size = clampi(glow_size, 4, 9)
	s.shadow_offset = Vector2(4, 5)
	s.border_color = glow.darkened(0.18)
	s.set_border_width_all(1)
	s.border_width_bottom = 4
	return s

static func card_style(accent: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var s := flat_style(CARD_BG, 5)
	s.border_color = ROCK_STEEL
	s.set_border_width_all(1)
	s.border_width_bottom = 4
	s.shadow_color = Color(0, 0, 0, 0.66)
	s.shadow_size = 7
	s.shadow_offset = Vector2(4, 5)
	s.content_margin_left = 20; s.content_margin_right = 20
	s.content_margin_top = 16; s.content_margin_bottom = 16
	if accent.a > 0:
		s.border_width_left = 6
		s.border_color = accent.darkened(0.12)
	return s

static func chip_style(selected: bool, accent: Color = NEON_CYAN) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(4)
	s.content_margin_left = 18; s.content_margin_right = 18
	s.content_margin_top = 13; s.content_margin_bottom = 13
	if selected:
		s.bg_color = ROCK_IRON.lerp(accent, 0.18)
		s.border_color = accent
		s.set_border_width_all(2)
		s.border_width_bottom = 4
		s.shadow_color = Color(0, 0, 0, 0.72)
		s.shadow_size = 6
		s.shadow_offset = Vector2(3, 4)
	else:
		s.bg_color = Color(0.075, 0.061, 0.052, 0.97)
		s.border_color = ROCK_STEEL
		s.set_border_width_all(1)
		s.border_width_bottom = 3
	return s

# --- Button factories ---

static func style_chip_button(btn: Button, selected: bool, accent: Color = NEON_CYAN) -> void:
	var n := chip_style(selected, accent)
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover", n)
	var p := chip_style(true, accent)
	p.bg_color = Color(accent.r, accent.g, accent.b, 0.30)
	btn.add_theme_stylebox_override("pressed", p)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override(
		"font_color", accent.lightened(0.35) if selected else ROCK_PARCHMENT)
	btn.add_theme_color_override("font_pressed_color", TEXT_BRIGHT)
	btn.add_theme_color_override("font_hover_color", accent.lightened(0.35) if selected else TEXT_BRIGHT)

static func style_primary_button(btn: Button, accent: Color = NEON_CYAN, font_size: int = 22) -> void:
	var n := glow_style(ROCK_IRON, accent, 5, 8)
	n.bg_color = ROCK_IRON.lerp(accent, 0.12)
	n.set_border_width_all(2)
	n.border_width_bottom = 5
	n.border_width_left = 5
	n.content_margin_left = 28; n.content_margin_right = 28
	n.content_margin_top = 17; n.content_margin_bottom = 17
	btn.add_theme_stylebox_override("normal", n)
	var h := n.duplicate()
	h.bg_color = ROCK_IRON.lerp(accent, 0.25)
	h.shadow_size = 9
	btn.add_theme_stylebox_override("hover", h)
	var p := n.duplicate()
	p.bg_color = ROCK_CHARRED.lerp(accent, 0.32)
	p.border_width_bottom = 2
	btn.add_theme_stylebox_override("pressed", p)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", accent.lightened(0.35))
	btn.add_theme_color_override("font_hover_color", TEXT_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", TEXT_BRIGHT)
	btn.add_theme_font_size_override("font_size", font_size)

static func style_ghost_button(btn: Button, font_size: int = 17) -> void:
	var n := flat_style(Color(0.055, 0.047, 0.041, 0.97), 4)
	n.border_color = ROCK_STEEL
	n.set_border_width_all(1)
	n.border_width_bottom = 3
	n.content_margin_left = 17; n.content_margin_right = 17
	n.content_margin_top = 11; n.content_margin_bottom = 11
	btn.add_theme_stylebox_override("normal", n)
	var h := n.duplicate()
	h.bg_color = ROCK_IRON
	h.border_color = NEON_CYAN
	h.shadow_color = Color(0, 0, 0, 0.72)
	h.shadow_size = 6
	h.shadow_offset = Vector2(3, 4)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", ROCK_PARCHMENT)
	btn.add_theme_color_override("font_hover_color", TEXT_BRIGHT)
	btn.add_theme_font_size_override("font_size", font_size)

static func style_danger_button(btn: Button, font_size: int = 17) -> void:
	var n := flat_style(Color(0.18, 0.045, 0.025, 0.96), 4)
	n.border_color = Color(NEON_RED.r, NEON_RED.g, NEON_RED.b, 0.55)
	n.set_border_width_all(1)
	n.border_width_bottom = 3
	n.content_margin_left = 17; n.content_margin_right = 17
	n.content_margin_top = 11; n.content_margin_bottom = 11
	btn.add_theme_stylebox_override("normal", n)
	var h := n.duplicate()
	h.bg_color = Color(0.31, 0.075, 0.040)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", NEON_RED.lightened(0.3))
	btn.add_theme_font_size_override("font_size", font_size)

# --- Labels ---

static func section_label(text: String) -> Label:
	var l := Label.new()
	l.text = "//  %s" % text.to_upper()
	l.custom_minimum_size = Vector2(0, 30)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", NEON_CYAN.lightened(0.15))
	if font_bold():
		l.add_theme_font_override("font", font_bold())
	return l

static func make_game_logo(size: float = 88.0) -> TextureRect:
	var logo := TextureRect.new()
	if ResourceLoader.exists(GAME_LOGO_PATH):
		logo.texture = load(GAME_LOGO_PATH) as Texture2D
	logo.custom_minimum_size = Vector2(size, size)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return logo

static func badge_style(accent: Color, selected: bool = true) -> StyleBoxFlat:
	var alpha := 0.28 if selected else 0.10
	var s := glow_style(
		Color(accent.r, accent.g, accent.b, alpha),
		accent, 16, 10 if selected else 4)
	s.set_border_width_all(2 if selected else 1)
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 10; s.content_margin_bottom = 10
	return s

static func add_edge_light(parent: Container, accent: Color = NEON_CYAN) -> void:
	var line := ColorRect.new()
	line.color = Color(accent.r, accent.g, accent.b, 0.72)
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

# --- Background ---

# Distressed amplifier wall + dark readability treatment used by menus.
static func add_hardrock_background(parent: Control) -> void:
	if ResourceLoader.exists(ARENA_BG_PATH):
		var arena := TextureRect.new()
		arena.texture = load(ARENA_BG_PATH) as Texture2D
		arena.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		arena.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		arena.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		arena.modulate = Color(0.70, 0.68, 0.66, 0.82)
		arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(arena)

	var grad := Gradient.new()
	grad.set_color(0, Color(ROCK_CHARRED.r, ROCK_CHARRED.g, ROCK_CHARRED.b, 0.56))
	grad.set_color(1, Color(ROCK_COAL.r, ROCK_COAL.g, ROCK_COAL.b, 0.84))
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0, 0)
	grad_tex.fill_to = Vector2(0, 1)
	var bg := TextureRect.new()
	bg.texture = grad_tex
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)

# Original animated background remains available to gameplay overlays. This
# keeps the highway/loading/results color language unchanged by the menu skin.
static func add_neon_background(parent: Control, blob_count: int = 3) -> void:
	var grad := Gradient.new()
	grad.set_color(0, BG_TOP)
	grad.set_color(1, BG_BOTTOM)
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0, 0)
	grad_tex.fill_to = Vector2(0, 1)
	var bg := TextureRect.new()
	bg.texture = grad_tex
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)

	var blob_colors := [NEON_PURPLE, NEON_CYAN, NEON_MAGENTA]
	for i in range(blob_count):
		var blob := _make_glow_blob(blob_colors[i % blob_colors.size()], 0.10)
		parent.add_child(blob)
		_animate_blob(parent, blob, i)

static func _make_glow_blob(color: Color, alpha: float) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(color.r, color.g, color.b, alpha))
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 512
	tex.height = 512
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var size := 620.0
	rect.size = Vector2(size, size)
	return rect

static func _animate_blob(host: Control, blob: TextureRect, seed_idx: int) -> void:
	var vp := host.get_viewport_rect().size
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337 + seed_idx * 977
	blob.position = Vector2(
		rng.randf_range(-200, vp.x - 300),
		rng.randf_range(-200, vp.y - 300))
	var tw := host.create_tween()
	tw.set_loops()
	var duration := rng.randf_range(9.0, 14.0)
	var target := Vector2(
		rng.randf_range(-200, vp.x - 300),
		rng.randf_range(-200, vp.y - 300))
	tw.tween_property(blob, "position", target, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(blob, "position", blob.position, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# --- Safe area ---

# Returns {l, t, r, b} insets in viewport coordinates.
static func safe_insets(host: Control) -> Dictionary:
	var out := {"l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0}
	var vp := host.get_viewport_rect().size
	var safe := DisplayServer.get_display_safe_area()
	var screen_index := DisplayServer.window_get_current_screen()
	var screen_position := DisplayServer.screen_get_position(screen_index)
	var screen_size := DisplayServer.screen_get_size(screen_index)
	if screen_size.x <= 0 or screen_size.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return out

	# On desktop platforms the safe-area fallback is expressed in virtual
	# desktop coordinates. Subtract the current monitor's origin before
	# converting it to viewport margins; otherwise every control is shifted off
	# screen when the game/editor is running on a secondary monitor.
	var safe_position := safe.position
	var global_screen_end := screen_position + screen_size
	var safe_is_global := (
		safe.position.x >= screen_position.x
		and safe.position.y >= screen_position.y
		and safe.end.x <= global_screen_end.x
		and safe.end.y <= global_screen_end.y
	)
	if safe_is_global:
		safe_position -= screen_position
	elif not (
		safe.position.x >= 0
		and safe.position.y >= 0
		and safe.end.x <= screen_size.x
		and safe.end.y <= screen_size.y
	):
		return out

	var left_px := clampi(safe_position.x, 0, screen_size.x)
	var top_px := clampi(safe_position.y, 0, screen_size.y)
	var right_px := clampi(screen_size.x - (safe_position.x + safe.size.x), 0, screen_size.x)
	var bottom_px := clampi(screen_size.y - (safe_position.y + safe.size.y), 0, screen_size.y)
	if left_px + right_px >= screen_size.x or top_px + bottom_px >= screen_size.y:
		return out

	var sx := vp.x / float(screen_size.x)
	var sy := vp.y / float(screen_size.y)
	out["l"] = left_px * sx
	out["t"] = top_px * sy
	out["r"] = right_px * sx
	out["b"] = bottom_px * sy
	return out
