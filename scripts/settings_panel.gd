class_name SettingsPanel
extends Control
## The settings screen: Graphics, Sound and Controls tabs. Used by the main menu and the
## pause menu. Changes apply at once and are saved to user://settings.cfg.

signal closed

var tabs: TabContainer
var _rebinding := ""          # action waiting for a key press
var _key_btns := {}           # action -> Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UI.backdrop())
	var p := UI.panel(18)
	p.custom_minimum_size = Vector2(760, 0)
	var v := UI.column(10)
	v.add_child(UI.label("SETTINGS", 11, UI.BRASS))
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(720, 460)
	tabs.add_theme_font_size_override("font_size", 14)
	tabs.add_child(_graphics_tab())
	tabs.add_child(_sound_tab())
	tabs.add_child(_controls_tab())
	v.add_child(tabs)
	v.add_child(UI.row([UI.button("Done", func(): Game.save_settings(); closed.emit(); queue_free())]))
	p.add_child(v)
	add_child(p)
	UI.center(p)
	set_process_unhandled_input(true)


func _margin(v: Control) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_bottom", 12)
	m.add_child(v)
	return m


# ---------- graphics ----------

func _graphics_tab() -> Control:
	var v := UI.column(12)
	var S: Dictionary = Game.settings
	v.add_child(UI.row([UI.caps("Quality"), UI.option([["low", "Low (no shadows, fewer particles)"], ["medium", "Medium"], ["high", "High"]], S.quality,
		func(q): S.quality = q; Game.apply_graphics())]))
	v.add_child(UI.row([UI.caps("Window"), UI.check("Fullscreen", S.fullscreen, func(on): S.fullscreen = on; Game.apply_window()),
		UI.check("V-sync", S.vsync, func(on): S.vsync = on; Game.apply_window())]))
	var res := []
	for r in Game.RESOLUTIONS:
		res.append([r, r])
	v.add_child(UI.row([UI.caps("Resolution"), UI.option(res, S.resolution, func(r): S.resolution = r; Game.apply_window()),
		UI.label("(windowed mode)", 12, UI.MUTED)]))
	var sc_lbl := UI.label("%d%%" % int(S.ui_scale * 100), 13)
	v.add_child(UI.row([UI.caps("UI scale"), UI.slider(S.ui_scale, func(x): S.ui_scale = x; sc_lbl.text = "%d%%" % int(x * 100); Game.apply_window(), 0.75, 1.5, 0.05), sc_lbl]))
	v.add_child(UI.check("PYROLUX fire and explosion effects (when the addon is installed)", S.pyro, func(on): S.pyro = on; Game.apply_graphics()))
	v.add_child(UI.wrap("Quality changes take effect at once. Low turns off shadows and glow and draws fewer smoke and foam particles; use it if the battle stutters.", 680, 12, UI.MUTED))
	var m := _margin(v)
	m.name = "Graphics"
	return m


# ---------- sound ----------

func _sound_tab() -> Control:
	var v := UI.column(12)
	var S: Dictionary = Game.settings
	for it in [["vol_master", "Master"], ["vol_music", "Music"], ["vol_fx", "Effects"], ["vol_radio", "Radio chatter"]]:
		var key: String = it[0]
		var lbl := UI.label("%d%%" % int(S[key] * 100), 13)
		v.add_child(UI.row([UI.caps(it[1]), UI.slider(S[key], func(x): S[key] = x; lbl.text = "%d%%" % int(x * 100); Game.apply_audio()), lbl]))
	v.add_child(UI.wrap("Music and radio chatter arrive with the sound build; the sliders are wired up already.", 680, 12, UI.MUTED))
	var m := _margin(v)
	m.name = "Sound"
	return m


# ---------- controls ----------

func _controls_tab() -> Control:
	var v := UI.column(6)
	v.add_child(UI.wrap("Click a key to change it, then press the new key. Esc cancels. A key already in use is taken from its old action.", 680, 12, UI.MUTED))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(680, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	for a in Game.ACTIONS:
		var act: String = a[0]
		var l := UI.label(a[1], 13)
		l.custom_minimum_size.x = 200
		grid.add_child(l)
		var b := UI.button(Game.key_name(act), func(): _start_rebind(act))
		b.custom_minimum_size.x = 110
		_key_btns[act] = b
		grid.add_child(b)
	scroll.add_child(grid)
	v.add_child(scroll)
	v.add_child(UI.row([UI.button("Reset to defaults", func(): Game.reset_keys(); _refresh_keys())]))
	var m := _margin(v)
	m.name = "Controls"
	return m


func _start_rebind(act: String) -> void:
	if _rebinding != "":
		_refresh_keys()
	_rebinding = act
	_key_btns[act].text = "press a key…"


func _refresh_keys() -> void:
	for act in _key_btns:
		_key_btns[act].text = Game.key_name(act)


func _unhandled_input(e: InputEvent) -> void:
	if _rebinding == "":
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			Game.save_settings()
			closed.emit()
			queue_free()
		return
	if e is InputEventKey and e.pressed:
		get_viewport().set_input_as_handled()
		if e.keycode != KEY_ESCAPE:
			Game.rebind(_rebinding, e.keycode)
		_rebinding = ""
		_refresh_keys()
