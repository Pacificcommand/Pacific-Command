class_name WT
## The War Room look of the operations map: a chart on a wooden table, brass plates, dark wood
## buttons, a clipboard of paper and index cards. Fonts: Oswald (stencil-ish headings and tags),
## Special Elite (typewriter), Libre Caslon (printed titles). Everything here is static.

const INK := Color("2b2419")
const INK_BLUE := Color("284f7a")
const INK_RED := Color("a8321f")
const INK_BRASS := Color("7a5a1c")
const INK_GREEN := Color("2f6b3a")
const INK_MUTED := Color("5d4a33")
const PAPER := Color("f3ecd8")
const TAG := Color("efe4c4")
const BRASS := Color("c9a24a")
const BRASS_EDGE := Color("7a5a1c")
const BRASS_TEXT := Color("2e220b")
const WOOD_BTN := Color("2a1c11")
const WOOD_TEXT := Color("e8d6a8")
const BOARD := Color("6b4a26")
const PIN_US := Color("284f7a")
const PIN_JP := Color("b42e1c")
const BLOCK_US := Color("3c6b9c")
const BLOCK_US_SIDE := Color("22405f")
const BLOCK_JP := Color("b03a26")
const BLOCK_JP_SIDE := Color("6e2015")
const YOU := Color("f2c14e")
const YOU_SIDE := Color("9a6f1c")
const PENCIL := Color("d86a1c")
const PERIMETER := Color("9b2d1f")
const RADAR := Color("2c5d70")
const GRATICULE := Color("8aa197")

static var _fonts := {}
static var _tex := {}


## "head" Oswald semibold, "headb" Oswald bold, "type" Special Elite, "serif" Libre Caslon, "serifb" bold.
static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var path: String = {"head": "res://assets/fonts/Oswald.ttf", "headb": "res://assets/fonts/Oswald.ttf", "type": "res://assets/fonts/SpecialElite.ttf",
		"serif": "res://assets/fonts/LibreCaslonText.ttf", "serifb": "res://assets/fonts/LibreCaslonText.ttf"}.get(kind, "")
	var f: Font = ThemeDB.fallback_font
	if path != "" and ResourceLoader.exists(path):
		var base: FontFile = load(path)
		var wght: int = {"head": 600, "headb": 700, "serif": 400, "serifb": 700}.get(kind, 0)
		if wght > 0:
			var v := FontVariation.new()
			v.base_font = base
			v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): wght}
			f = v
		else:
			f = base
	_fonts[kind] = f
	return f


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = null
		for ext in ["png", "jpg"]:
			var p := "res://assets/map/%s.%s" % [name, ext]
			if ResourceLoader.exists(p):
				_tex[name] = load(p)
				break
	return _tex[name]


static func flat(bg: Color, border := Color(0, 0, 0, 0), bw := 0, radius := 0, margin := -1.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	if margin >= 0.0:
		sb.set_content_margin_all(margin)
	return sb


## A sheet of paper (texture if there is one), with a soft drop shadow.
static func paper_box(margin := 18.0, shadow := 10) -> StyleBox:
	var t := tex("paper")
	if t != null:
		var sb := StyleBoxTexture.new()
		sb.texture = t
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		sb.set_content_margin_all(margin)
		return sb
	var f := flat(PAPER, Color(0, 0, 0, 0), 0, 0, margin)
	f.shadow_size = shadow
	f.shadow_color = Color(0, 0, 0, 0.45)
	f.shadow_offset = Vector2(0, 5)
	return f


## Wrap a finished card panel (UI.panel) in paper: a sheet with a drop shadow, ink inside.
static func paperize_panel(p: PanelContainer, margin := 24.0) -> void:
	var frame := flat(PAPER, Color("b9a982"), 1, 2, margin)
	frame.shadow_size = 18
	frame.shadow_color = Color(0, 0, 0, 0.55)
	frame.shadow_offset = Vector2(0, 8)
	p.add_theme_stylebox_override("panel", frame)
	paperize(p)


## Dark wood button with a brass edge (top bar). `on` = the brass face (pressed speed).
static func wood_button(b: Button, size := 15, h := 48.0) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = h
	b.add_theme_font_override("font", font("head"))
	b.add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := flat(WOOD_BTN, BRASS_EDGE, 2, 4)
		sb.content_margin_left = 16; sb.content_margin_right = 16
		sb.content_margin_top = 4; sb.content_margin_bottom = 4
		sb.shadow_size = 6; sb.shadow_color = Color(0, 0, 0, 0.45); sb.shadow_offset = Vector2(0, 3)
		if st == "hover":
			sb.bg_color = Color("3a2817")
		if st == "pressed" or st == "hover_pressed":
			sb.bg_color = BRASS
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", WOOD_TEXT)
	b.add_theme_color_override("font_hover_color", Color("fff1cc"))
	b.add_theme_color_override("font_pressed_color", BRASS_TEXT)
	b.add_theme_color_override("font_hover_pressed_color", BRASS_TEXT)
	b.add_theme_color_override("font_disabled_color", Color("8a7a5a"))


## The big brass button (Go to the dock).
static func brass_button(b: Button, size := 18) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font("headb"))
	b.add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := flat(BRASS, BRASS_EDGE, 2, 4)
		sb.content_margin_left = 26; sb.content_margin_right = 26
		sb.content_margin_top = 10; sb.content_margin_bottom = 10
		sb.shadow_size = 8; sb.shadow_color = Color(0, 0, 0, 0.5); sb.shadow_offset = Vector2(0, 5)
		if st == "hover":
			sb.bg_color = Color("d9b25a")
		if st == "pressed" or st == "hover_pressed":
			sb.bg_color = Color("a8853a")
		b.add_theme_stylebox_override(st, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, BRASS_TEXT)


## Ink on paper: buttons outlined in ink (or filled red for the main action).
static func paper_button(b: Button, primary := false, tint := INK) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font("head"))
	var fs := 14
	if b.has_theme_font_size_override("font_size"):
		fs = maxi(13, b.get_theme_font_size("font_size") - (2 if primary else 0))
	b.add_theme_font_size_override("font_size", fs)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb: StyleBoxFlat
		if primary:
			sb = flat(INK_RED, Color("6e2015"), 0, 3)
			if st == "hover":
				sb.bg_color = Color("bf3d27")
			elif st == "disabled":
				sb.bg_color = Color("c9a99a")
		else:
			sb = flat(Color(0, 0, 0, 0), INK, 2, 3)
			if st == "hover":
				sb.bg_color = Color(0.17, 0.14, 0.10, 0.10)
			elif st == "pressed" or st == "hover_pressed":
				sb.bg_color = Color(0.17, 0.14, 0.10, 0.85)
			elif st == "disabled":
				sb.border_color = Color(0.17, 0.14, 0.10, 0.35)
		sb.content_margin_left = 12; sb.content_margin_right = 12
		sb.content_margin_top = 6 if not primary else 10; sb.content_margin_bottom = 6 if not primary else 10
		b.add_theme_stylebox_override(st, sb)
	var fc := Color("fbf3df") if primary else tint
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", Color("fbf3df"))
	b.add_theme_color_override("font_hover_pressed_color", Color("fbf3df"))
	b.add_theme_color_override("font_disabled_color", Color(0.17, 0.14, 0.10, 0.45) if not primary else Color("f3ecd8"))


## A dark-screen colour, read as ink on paper.
static func ink_for(c: Color) -> Color:
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	var sat := 0.0 if mx <= 0.0 else (mx - mn) / mx
	if sat < 0.18:
		return INK if mx > 0.72 else INK_MUTED
	if c.b > c.r + 0.15:
		return INK_BLUE
	if c.g > c.r and c.g > c.b:
		return INK_GREEN
	if c.r > 0.6 and c.g > 0.5 and c.b < 0.45:
		return INK_BRASS
	if c.r > c.g + 0.2:
		return INK_RED
	return INK


## Restyle a finished tree of UI.* widgets as ink on paper: labels in the War Room fonts and
## ink colours, buttons outlined (big ones filled red), strength bars kept.
static func paperize(n: Node, wrap_max := 0.0) -> void:
	for c in n.get_children():
		if c is Button:
			var b: Button = c
			var primary: bool = b.custom_minimum_size.y >= 44.0 and not b.text in ["Not yet", "Close", "Later", "Cancel", "Back"]
			var tint := INK
			if b.has_theme_color_override("font_color"):
				tint = ink_for(b.get_theme_color("font_color"))
			paper_button(b, primary, tint)
			if wrap_max > 0.0:
				# the clipboard is narrow: long buttons shorten with "..." instead of widening it
				b.clip_text = true
				b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				b.custom_minimum_size.x = minf(b.custom_minimum_size.x, wrap_max)
				if b.get_parent() is HBoxContainer:
					b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				elif not primary and b.get_parent() == n and n is VBoxContainer:
					b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		elif c is Label:
			var l: Label = c
			var col: Color = l.get_theme_color("font_color") if l.has_theme_color_override("font_color") else UI.INK
			var sz: int = l.get_theme_font_size("font_size") if l.has_theme_font_size_override("font_size") else 14
			var ink := ink_for(col)
			var caps := l.text == l.text.to_upper() and l.text.length() > 2
			if sz >= 22:
				l.add_theme_font_override("font", font("serifb"))
			elif caps and sz <= 13:
				l.add_theme_font_override("font", font("type"))
				l.add_theme_font_size_override("font_size", sz + 1)
				if ink == INK_BRASS or ink == INK:
					ink = Color("8f3420")
			elif sz >= 16 and not l.autowrap_mode:
				l.add_theme_font_override("font", font("head"))
			else:
				l.add_theme_font_override("font", font("type"))
				l.add_theme_font_size_override("font_size", sz + 1)
			l.add_theme_color_override("font_color", ink)
			if wrap_max > 0.0 and l.custom_minimum_size.x > wrap_max:
				l.custom_minimum_size.x = wrap_max
		elif c is ColorRect:
			var r: ColorRect = c
			# strength bars: our blue, their red, in ink
			if r.color.b > r.color.r + 0.15:
				r.color = INK_BLUE
			elif r.color.r > r.color.b + 0.2:
				r.color = INK_RED
		paperize(c, wrap_max)


# ---------------------------------------------------------------------
# the satellite look (0.28): dark glass panels floating over the ocean
# ---------------------------------------------------------------------

const GLASS := Color(0.035, 0.07, 0.11, 0.78)
const GLASS_EDGE := Color(1, 1, 1, 0.13)
const GLASS_TEXT := Color(0.92, 0.95, 0.97)
const ACCENT := Color("ffd166")          # the player's colour: course line, own ship ring
const US_RING := Color(0.40, 0.70, 1.00)
const JP_RING := Color(1.00, 0.33, 0.27)


static func glass(margin := 16.0, radius := 10) -> StyleBoxFlat:
	var sb := flat(GLASS, GLASS_EDGE, 1, radius, margin)
	sb.shadow_size = 14
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_offset = Vector2(0, 6)
	return sb


## A finished card panel (UI.panel) on dark glass.
static func glass_panel(p: PanelContainer, margin := 24.0) -> void:
	var sb := glass(margin, 12)
	sb.bg_color = Color(0.03, 0.06, 0.10, 0.92)
	p.add_theme_stylebox_override("panel", sb)


## A glass button for the top bars. `on` (pressed) glows in the accent colour.
static func glass_button(b: Button, size := 14, h := 40.0) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = h
	b.add_theme_font_override("font", font("head"))
	b.add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := flat(Color(0.035, 0.07, 0.11, 0.72), GLASS_EDGE, 1, 8)
		sb.content_margin_left = 14; sb.content_margin_right = 14
		sb.content_margin_top = 4; sb.content_margin_bottom = 4
		if st == "hover":
			sb.bg_color = Color(0.08, 0.14, 0.20, 0.85)
		if st == "pressed" or st == "hover_pressed":
			sb.bg_color = Color(ACCENT, 0.92)
			sb.border_color = ACCENT
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", GLASS_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color("1b1405"))
	b.add_theme_color_override("font_hover_pressed_color", Color("1b1405"))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
