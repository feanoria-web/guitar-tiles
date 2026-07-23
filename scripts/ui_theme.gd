extends RefCounted
class_name UITheme

# Neon rhythm-game design system shared by menu + game.
# All colors/styles live here so screens stay consistent.

# --- Palette ---
const BG_TOP := Color(0.045, 0.035, 0.10)      # deep indigo
const BG_BOTTOM := Color(0.02, 0.015, 0.05)    # near-black purple
const NEON_CYAN := Color(0.10, 0.85, 1.0)
const NEON_MAGENTA := Color(1.0, 0.25, 0.72)
const NEON_PURPLE := Color(0.58, 0.35, 1.0)
const NEON_GREEN := Color(0.25, 1.0, 0.55)
const NEON_GOLD := Color(1.0, 0.85, 0.25)
const NEON_RED := Color(1.0, 0.30, 0.25)

const CARD_BG := Color(0.10, 0.09, 0.17, 0.92)
const CARD_BORDER := Color(0.35, 0.30, 0.55, 0.55)
const PANEL_BG := Color(0.07, 0.06, 0.13, 0.97)
const TEXT_BRIGHT := Color(0.96, 0.95, 1.0)
const TEXT_DIM := Color(0.62, 0.60, 0.74)
const TEXT_FAINT := Color(0.42, 0.40, 0.55)

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
	t.set_font_size("font_size", "Button", 19)
	t.set_font_size("font_size", "OptionButton", 17)

	# Default button: dark pill with subtle border
	var btn_n := flat_style(Color(0.13, 0.12, 0.22), 12)
	btn_n.border_color = CARD_BORDER
	btn_n.set_border_width_all(1)
	btn_n.content_margin_left = 22; btn_n.content_margin_right = 22
	btn_n.content_margin_top = 13; btn_n.content_margin_bottom = 13
	t.set_stylebox("normal", "Button", btn_n)
	var btn_h := btn_n.duplicate()
	btn_h.bg_color = Color(0.18, 0.16, 0.30)
	t.set_stylebox("hover", "Button", btn_h)
	var btn_p := btn_n.duplicate()
	btn_p.bg_color = Color(0.24, 0.21, 0.40)
	btn_p.border_color = NEON_PURPLE
	t.set_stylebox("pressed", "Button", btn_p)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	# OptionButton
	var opt_n := flat_style(Color(0.12, 0.11, 0.20), 10)
	opt_n.border_color = CARD_BORDER
	opt_n.set_border_width_all(1)
	opt_n.content_margin_left = 14; opt_n.content_margin_right = 14
	opt_n.content_margin_top = 8; opt_n.content_margin_bottom = 8
	t.set_stylebox("normal", "OptionButton", opt_n)
	var opt_h := opt_n.duplicate()
	opt_h.bg_color = Color(0.17, 0.15, 0.28)
	t.set_stylebox("hover", "OptionButton", opt_h)
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())

	# Slider
	var slider_bg := flat_style(Color(0.14, 0.13, 0.24), 4)
	slider_bg.content_margin_top = 4; slider_bg.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", slider_bg)
	var slider_fill := flat_style(NEON_PURPLE.darkened(0.15), 4)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)

	# Scrollbar — slim
	var sb := flat_style(Color(0.30, 0.28, 0.45, 0.5), 4)
	t.set_stylebox("grabber", "VScrollBar", sb)
	var sb_bg := flat_style(Color(0, 0, 0, 0), 4)
	t.set_stylebox("scroll", "VScrollBar", sb_bg)

	return t

# --- StyleBox factories ---

static func flat_style(bg: Color, radius: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	return s

# Neon glow via stylebox shadow
static func glow_style(bg: Color, glow: Color, radius: int = 14, glow_size: int = 8) -> StyleBoxFlat:
	var s := flat_style(bg, radius)
	s.shadow_color = Color(glow.r, glow.g, glow.b, 0.45)
	s.shadow_size = glow_size
	s.border_color = glow.lightened(0.2)
	s.set_border_width_all(1)
	return s

static func card_style(accent: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var s := flat_style(CARD_BG, 16)
	s.border_color = CARD_BORDER
	s.set_border_width_all(1)
	s.content_margin_left = 16; s.content_margin_right = 16
	s.content_margin_top = 12; s.content_margin_bottom = 12
	if accent.a > 0:
		s.border_width_left = 4
		s.border_color = accent
	return s

static func chip_style(selected: bool, accent: Color = NEON_CYAN) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(12)
	s.content_margin_left = 14; s.content_margin_right = 14
	s.content_margin_top = 10; s.content_margin_bottom = 10
	if selected:
		s.bg_color = Color(accent.r, accent.g, accent.b, 0.18)
		s.border_color = accent
		s.set_border_width_all(2)
		s.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
		s.shadow_size = 6
	else:
		s.bg_color = Color(0.12, 0.11, 0.20)
		s.border_color = CARD_BORDER
		s.set_border_width_all(1)
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
	btn.add_theme_color_override("font_color", accent.lightened(0.35) if selected else TEXT_DIM)
	btn.add_theme_color_override("font_pressed_color", TEXT_BRIGHT)
	btn.add_theme_color_override("font_hover_color", accent.lightened(0.35) if selected else TEXT_BRIGHT)

static func style_primary_button(btn: Button, accent: Color = NEON_CYAN, font_size: int = 22) -> void:
	var n := glow_style(Color(accent.r * 0.16, accent.g * 0.16, accent.b * 0.16), accent, 16, 10)
	n.bg_color = Color(accent.r, accent.g, accent.b, 0.16)
	n.content_margin_left = 24; n.content_margin_right = 24
	n.content_margin_top = 15; n.content_margin_bottom = 15
	btn.add_theme_stylebox_override("normal", n)
	var h := n.duplicate()
	h.bg_color = Color(accent.r, accent.g, accent.b, 0.28)
	btn.add_theme_stylebox_override("hover", h)
	var p := n.duplicate()
	p.bg_color = Color(accent.r, accent.g, accent.b, 0.42)
	btn.add_theme_stylebox_override("pressed", p)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", accent.lightened(0.45))
	btn.add_theme_color_override("font_hover_color", TEXT_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", TEXT_BRIGHT)
	btn.add_theme_font_size_override("font_size", font_size)

static func style_ghost_button(btn: Button, font_size: int = 17) -> void:
	var n := flat_style(Color(0.11, 0.10, 0.19, 0.85), 10)
	n.border_color = CARD_BORDER
	n.set_border_width_all(1)
	n.content_margin_left = 14; n.content_margin_right = 14
	n.content_margin_top = 9; n.content_margin_bottom = 9
	btn.add_theme_stylebox_override("normal", n)
	var h := n.duplicate()
	h.bg_color = Color(0.17, 0.15, 0.28)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", TEXT_DIM)
	btn.add_theme_color_override("font_hover_color", TEXT_BRIGHT)
	btn.add_theme_font_size_override("font_size", font_size)

static func style_danger_button(btn: Button, font_size: int = 17) -> void:
	var n := flat_style(Color(0.24, 0.07, 0.10, 0.9), 10)
	n.border_color = Color(NEON_RED.r, NEON_RED.g, NEON_RED.b, 0.55)
	n.set_border_width_all(1)
	n.content_margin_left = 14; n.content_margin_right = 14
	n.content_margin_top = 9; n.content_margin_bottom = 9
	btn.add_theme_stylebox_override("normal", n)
	var h := n.duplicate()
	h.bg_color = Color(0.34, 0.10, 0.14)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", NEON_RED.lightened(0.3))
	btn.add_theme_font_size_override("font_size", font_size)

# --- Labels ---

static func section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", TEXT_FAINT)
	if font_bold():
		l.add_theme_font_override("font", font_bold())
	return l

# --- Background ---

# Dark vertical gradient + drifting neon glow blobs.
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
	var screen := DisplayServer.screen_get_size()
	if screen.x > 0 and screen.y > 0:
		var sx := vp.x / float(screen.x)
		var sy := vp.y / float(screen.y)
		out["l"] = safe.position.x * sx
		out["t"] = safe.position.y * sy
		out["r"] = (screen.x - safe.end.x) * sx
		out["b"] = (screen.y - safe.end.y) * sy
	return out
