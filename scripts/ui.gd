class_name UI
## Shared look for every screen: dark glass panels, brass accents, ink-white text.
## hud.gd keeps its own copies of a few of these for the battle plates.

const GLASS := Color(0.027, 0.063, 0.078, 0.84)
const LINE := Color(0.79, 0.64, 0.29, 0.32)
const INK := Color(0.91, 0.93, 0.91)
const MUTED := Color(0.6, 0.66, 0.67)
const BRASS := Color(0.79, 0.64, 0.29)
const BRASS_INK := Color(0.11, 0.086, 0.024)
const RED := Color(0.89, 0.34, 0.25)
const GREEN := Color(0.31, 0.62, 0.5)


static func panel(margin := 14.0) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = GLASS
	sb.border_color = LINE
	sb.set_border_width_all(1)
	sb.set_content_margin_all(margin)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


static func label(text: String, size := 14, col := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


static func caps(text: String, width := 110) -> Label:
	var l := label(text.to_upper(), 11, MUTED)
	l.custom_minimum_size.x = width
	return l


static func wrap(text: String, width := 520, size := 14, col := Color(0.8, 0.84, 0.83)) -> Label:
	var l := label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


static func style_button(b: Button, size := 13) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.border_color = LINE
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 10; sb.content_margin_right = 10
		sb.content_margin_top = 5; sb.content_margin_bottom = 5
		sb.bg_color = Color(0, 0, 0, 0)
		if st == "hover":
			sb.bg_color = Color(0.08, 0.13, 0.16, 0.95)
		if st == "pressed" or st == "hover_pressed":
			sb.bg_color = BRASS
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_pressed_color", BRASS_INK)
	b.add_theme_color_override("font_hover_pressed_color", BRASS_INK)
	b.add_theme_color_override("font_disabled_color", MUTED)


static func button(text: String, cb: Callable, toggle := false, size := 13) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	style_button(b, size)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func big_button(text: String, cb: Callable) -> Button:
	var b := button(text, cb, false, 18)
	b.custom_minimum_size = Vector2(300, 44)
	return b


static func row(children: Array, sep := 8) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", sep)
	for c in children:
		hb.add_child(c)
	return hb


static func column(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func slider(value: float, cb: Callable, mn := 0.0, mx := 1.0, step := 0.05) -> HSlider:
	var s := HSlider.new()
	s.min_value = mn; s.max_value = mx; s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(220, 20)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(cb)
	return s


static func option(items: Array, current, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	style_button(o, 13)
	for i in items.size():
		o.add_item(String(items[i][1]), i)
	for i in items.size():
		if items[i][0] == current:
			o.select(i)
	o.item_selected.connect(func(i): cb.call(items[i][0]))
	return o


static func check(text: String, on: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 13)
	c.add_theme_color_override("font_color", INK)
	c.toggled.connect(cb)
	return c


## Center a control on the screen (inside a full-rect parent).
static func center(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH


## Full-screen dark backdrop that swallows clicks.
static func backdrop(alpha := 0.55) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.0, 0.02, 0.03, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r
