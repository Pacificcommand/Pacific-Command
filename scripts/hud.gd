extends CanvasLayer
## Heads-up display: instrument plates in the corners, message log, markers drawn
## over the sea, the mission briefing and the action report. Built in code so it
## does not depend on any editor scene. Keyboard and mouse input is handled here too.

const C_GLASS := Color(0.027, 0.063, 0.078, 0.84)
const C_LINE := Color(0.79, 0.64, 0.29, 0.32)
const C_INK := Color(0.91, 0.93, 0.91)
const C_MUTED := Color(0.6, 0.66, 0.67)
const C_BRASS := Color(0.79, 0.64, 0.29)
const C_BRASS_INK := Color(0.11, 0.086, 0.024)
const C_RED := Color(0.89, 0.34, 0.25)
const C_GREEN := Color(0.31, 0.62, 0.5)
const C_WATER := Color(0.35, 0.66, 0.84)

var B   # the battle
var root: Control
var overlay: Control
var log_box: VBoxContainer
var seg_groups := {}           # name -> {value: Button}
var lbl := {}                  # named labels
var bars := {}                 # named ProgressBar-like ColorRects
var btn := {}
var rud_view: Control
var guns_box: HBoxContainer
var brief: PanelContainer
var endp: PanelContainer
var pausep: Control = null
var air_plate: PanelContainer
var sub_row: HBoxContainer
var support_row: HBoxContainer
var mission_row: HBoxContainer
var cond_row: HBoxContainer
var asw_row: HBoxContainer
var ship_row: HBoxContainer
var _pause_prev := 1.0
var drag := {}
var tele_btns: Array = []
var dial_view: Control
var squad_plate: PanelContainer
var squad_box: VBoxContainer
var _squad_key := ""
var squad_open := false        # the orders panel starts folded to one line
var _last_click_t := -9.0


func _ready() -> void:
	B = get_parent()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	root.add_child(overlay)
	_build_plates()
	_build_log()
	_build_brief()
	_build_end()


# =====================================================================
# building blocks
# =====================================================================

func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_GLASS
	sb.border_color = C_LINE
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _label(text: String, size := 14, col := C_INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _caps(text: String) -> Label:
	var l := _label(text.to_upper(), 11, C_MUTED)
	l.custom_minimum_size.x = 74
	return l


func _button(text: String, cb: Callable, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.border_color = C_LINE
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 8; sb.content_margin_right = 8
		sb.content_margin_top = 4; sb.content_margin_bottom = 4
		sb.bg_color = Color(0, 0, 0, 0)
		if st == "hover":
			sb.bg_color = Color(0.08, 0.13, 0.16, 0.95)
		if st == "pressed" or st == "hover_pressed":
			sb.bg_color = C_BRASS
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", C_INK)
	b.add_theme_color_override("font_pressed_color", C_BRASS_INK)
	b.add_theme_color_override("font_hover_pressed_color", C_BRASS_INK)
	b.add_theme_color_override("font_disabled_color", C_MUTED)
	b.pressed.connect(func(): Audio.ui("click", 0.5))
	b.pressed.connect(cb)
	return b


## A row of buttons where one is selected.
func _seg(group: String, items: Array, cb: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	seg_groups[group] = {}
	for it in items:
		var v = it[0]
		var b := _button(it[1], func(): cb.call(v), true)
		seg_groups[group][v] = b
		hb.add_child(b)
	return hb


func _set_seg(group: String, value) -> void:
	for v in seg_groups[group]:
		seg_groups[group][v].set_pressed_no_signal(v == value)


func _row(children: Array) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 7)
	for c in children:
		hb.add_child(c)
	return hb


func _bar(nm: String, col: Color) -> Control:
	var back := ColorRect.new()
	back.color = Color(1, 1, 1, 0.12)
	back.custom_minimum_size = Vector2(120, 7)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := ColorRect.new()
	fill.color = col
	fill.size = Vector2(0, 7)
	back.add_child(fill)
	bars[nm] = fill
	return back


func _set_bar(nm: String, f: float) -> void:
	var fill: ColorRect = bars[nm]
	fill.size = Vector2(fill.get_parent().size.x * clampf(f, 0.0, 1.0), fill.get_parent().size.y)


## Pin a control to a corner or edge of the screen; it grows inward to fit its contents.
func _place(c: Control, where: String, m := 12.0) -> void:
	root.add_child(c)
	var ax = {"tl": 0.0, "tr": 1.0, "bl": 0.0, "br": 1.0, "bc": 0.5, "c": 0.5, "tc": 0.5, "ml": 0.0}[where]
	var ay = {"tl": 0.0, "tr": 0.0, "bl": 1.0, "br": 1.0, "bc": 1.0, "c": 0.5, "tc": 0.0, "ml": 0.5}[where]
	c.anchor_left = ax; c.anchor_right = ax; c.anchor_top = ay; c.anchor_bottom = ay
	var ox := m if ax == 0.0 else (-m if ax == 1.0 else 0.0)
	var oy := m if ay == 0.0 else (-m if ay == 1.0 else 0.0)
	c.offset_left = ox; c.offset_right = ox; c.offset_top = oy; c.offset_bottom = oy
	c.grow_horizontal = Control.GROW_DIRECTION_END if ax == 0.0 else (Control.GROW_DIRECTION_BEGIN if ax == 1.0 else Control.GROW_DIRECTION_BOTH)
	c.grow_vertical = Control.GROW_DIRECTION_END if ay == 0.0 else (Control.GROW_DIRECTION_BEGIN if ay == 1.0 else Control.GROW_DIRECTION_BOTH)


# =====================================================================
# plates
# =====================================================================

func _build_plates() -> void:
	# top left: ship name
	var tl := _panel()
	var tlv := VBoxContainer.new()
	tlv.add_child(_label("PACIFIC COMMAND  ·  COMBAT SANDBOX", 11, C_BRASS))
	lbl.title = _label("USS O'Bannon", 26)
	tlv.add_child(lbl.title)
	lbl.sub = _label("", 13, C_MUTED)
	tlv.add_child(lbl.sub)
	# detection and ranges, World of Warships style
	lbl.detected = _label("", 12, C_RED)
	tlv.add_child(lbl.detected)
	var dg := GridContainer.new()
	dg.columns = 4
	dg.add_theme_constant_override("h_separation", 12)
	dg.add_theme_constant_override("v_separation", 1)
	for key in ["conceal", "spot", "radar", "main", "secondary", "aa", "torp", "sonar"]:
		var cap := _caps({"conceal": "Concealment", "spot": "Spotting", "radar": "Radar", "main": "Main guns", "secondary": "Secondaries", "aa": "AA guns", "torp": "Torpedoes", "sonar": "Sonar"}[key])
		cap.custom_minimum_size.x = 90
		dg.add_child(cap)
		lbl["det_" + key] = _label("", 12)
		dg.add_child(lbl["det_" + key])
	tlv.add_child(dg)
	tl.add_child(tlv)
	_place(tl, "tl")

	# top right: time and options
	var trv := VBoxContainer.new()
	trv.add_theme_constant_override("separation", 6)
	var p1 := _panel()
	p1.add_child(_row([_caps("Time"), _seg("time", [[0.0, "Pause"], [0.25, "Slow ¼×"], [1.0, "Normal"], [3.0, "Fast 3×"]], func(v): B.set_speed(v))]))
	trv.add_child(p1)
	var p2 := _panel()
	btn.follow = _button("Follow salvos (V)", func(): B.follow = btn.follow.button_pressed, true)
	btn.slowf = _button("Slow-mo when following", func(): B.slow_follow = btn.slowf.button_pressed, true)
	p2.add_child(_row([_caps("Camera"), btn.follow, btn.slowf]))
	trv.add_child(p2)
	var p3 := _panel()
	btn.snd = _button("Sound on", _on_sound, true)
	btn.restart = _button("New battle", func(): B.new_game())
	btn.pyro = _button("PYROLUX effects", _on_pyro, true)
	p3.add_child(_row([_caps("Game"), btn.snd, btn.pyro, btn.restart, _button("Menu (Esc)", open_pause)]))
	trv.add_child(p3)
	_place(trv, "tr")

	# bottom left: the ship dial (World of Warships style): the ship from above with every
	# gun's state, the bearing ring and the target wedge; telegraph and rudder beside it
	var bl := _panel()
	var blh := HBoxContainer.new()
	blh.add_theme_constant_override("separation", 10)
	dial_view = Control.new()
	dial_view.custom_minimum_size = Vector2(230, 230)
	dial_view.draw.connect(_draw_dial)
	dial_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blh.add_child(dial_view)
	var blv := VBoxContainer.new()
	blv.add_theme_constant_override("separation", 2)
	lbl.spd = _label("25.0 kn", 22)
	lbl.hdg = _label("Course 000°", 12, C_MUTED)
	blv.add_child(lbl.spd)
	blv.add_child(lbl.hdg)
	for i in range(Data.TELE.size() - 1, -1, -1):
		var b := _button(Data.TELE[i].n.to_upper(), func(): B.order_tele(i), true)
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size.x = 86
		tele_btns.insert(0, b)
		blv.add_child(b)
	rud_view = Control.new()
	rud_view.custom_minimum_size = Vector2(86, 14)
	rud_view.draw.connect(_draw_rudder)
	blv.add_child(_row([_button("◀", func(): B.order_rudder(B.player.rud_cmd - 10.0)), rud_view, _button("▶", func(): B.order_rudder(B.player.rud_cmd + 10.0))]))
	lbl.rud = _label("Rudder amidships", 11, C_MUTED)
	blv.add_child(lbl.rud)
	blh.add_child(blv)
	# ship status under the dial: crew, efficiency, list, flooding, fires
	var status := VBoxContainer.new()
	status.add_theme_constant_override("separation", 3)
	lbl.fires = _label("No fires", 11, C_MUTED)
	lbl.crew = _label("329 / 329", 11)
	status.add_child(_row([_caps("Crew"), _bar("crew", C_GREEN), lbl.crew]))
	lbl.flood = _label("0 t", 11)
	status.add_child(_row([_caps("Flooding"), _bar("flood", C_WATER), lbl.flood]))
	lbl.eff = _label("100%", 11)
	lbl.list = _label("0.0°", 11)
	status.add_child(_row([_caps("Efficiency"), lbl.eff, _caps("List"), lbl.list, lbl.fires]))
	var blall := VBoxContainer.new()
	blall.add_theme_constant_override("separation", 4)
	blall.add_child(blh)
	blall.add_child(status)
	bl.add_child(blall)
	_place(bl, "bl")

	# middle left: air group (carriers and ships with floatplanes)
	air_plate = _panel()
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 5)
	av.add_child(_label("AIR GROUP", 11, C_BRASS))
	lbl.air = _label("", 12)
	av.add_child(lbl.air)
	btn.strike = _button("Strike target (L)", func(): B.order_strike())
	btn.cap = _button("Fighter patrol", func(): B.order_cap())
	btn.scout = _button("Scout", func(): B.order_scout())
	btn.recall = _button("Recall", func(): B.air.recall(B.player); log_msg("All aircraft ordered home."))
	av.add_child(_row([btn.strike, btn.cap, btn.scout, btn.recall]))
	av.add_child(_row([_caps("AA guns"), _seg("aa", [["self", "Protect self"], ["carrier", "Protect carrier"], ["bombers", "Bombers first"]], func(v): B.air.aa_mode = v; _set_seg("aa", v))]))
	air_plate.add_child(av)
	# orders to the ships in company
	squad_plate = _panel()
	squad_box = VBoxContainer.new()
	squad_box.add_theme_constant_override("separation", 3)
	squad_plate.add_child(squad_box)
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 8)
	left_col.add_child(air_plate)
	left_col.add_child(squad_plate)
	_place(left_col, "ml")
	air_plate.visible = false

	# bottom right: fire control
	var brv := VBoxContainer.new()
	brv.add_theme_constant_override("separation", 6)
	var br := _panel()
	br.custom_minimum_size.x = 380
	var fv := VBoxContainer.new()
	fv.add_theme_constant_override("separation", 6)
	var fh := HBoxContainer.new()
	var fl := _label("FIRE CONTROL", 11, C_BRASS)
	fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fh.add_child(fl)
	lbl.tgt = _label("No target", 12, C_MUTED)
	fh.add_child(lbl.tgt)
	fv.add_child(fh)
	btn.lead = _button("Lead marker", func(): B.show_lead = btn.lead.button_pressed, true)
	fv.add_child(_row([_caps("Aim"), _seg("aim", [["auto", "Crew (auto)"], ["manual", "Manual (mouse)"]], func(v): B.set_aim(v)), btn.lead]))
	lbl.sol = _label("No solution", 12, C_MUTED)
	fv.add_child(_row([_caps("Solution"), _bar("sol", C_BRASS), lbl.sol]))
	guns_box = HBoxContainer.new()
	guns_box.add_theme_constant_override("separation", 3)
	lbl.gun_caps = _caps("Guns")
	fv.add_child(_row([lbl.gun_caps, guns_box]))
	lbl.torps = _label("5/5 · 5/5", 12)
	fv.add_child(_row([_caps("Torpedoes"), lbl.torps]))
	btn.fire = _button("Open fire (F)", func(): B.toggle_fire(), true)
	btn.torp = _button("Torpedo aim (T)", func(): B.fire_torpedoes(), true)
	btn.smoke = _button("Lay smoke (Z)", func(): B.toggle_smoke(), true)
	btn.star = _button("Star shell (I)", func(): B.order_star())
	fv.add_child(_row([btn.fire, btn.torp, btn.smoke, btn.star]))
	# submarines: depth; escorts: depth charges and hedgehog
	sub_row = _row([_caps("Depth"), _seg("depth", [[0, "Surfaced"], [1, "Periscope"], [2, "Deep"]], func(v): B.order_depth(v))])
	lbl.battery = _label("Battery 100%", 12, C_MUTED)
	sub_row.add_child(lbl.battery)
	fv.add_child(sub_row)
	btn.charges = _button("Depth charges (G)", func(): B.order_charges())
	btn.hedgehog = _button("Hedgehog (H)", func(): B.order_hedgehog())
	lbl.dc = _label("", 12, C_MUTED)
	asw_row = _row([_caps("ASW"), btn.charges, btn.hedgehog, lbl.dc])
	fv.add_child(asw_row)
	br.add_child(fv)
	brv.add_child(br)
	var vp := _panel()
	var vpv := VBoxContainer.new()
	vpv.add_theme_constant_override("separation", 4)
	vpv.add_child(_row([_caps("View"), _seg("view", [["close", "Close"], ["ship", "Ship"], ["wide", "Wide"], ["tac", "Tactical"]], _on_view)]))
	vpv.add_child(_row([_caps("Camera on"), _seg("cam", [["player", "Own ship"], ["target", "Enemy target (C)"]], _on_focus)]))
	vp.add_child(vpv)
	brv.add_child(vp)
	lbl.keys = _label("", 11, C_MUTED)
	_update_keys_help()
	var kp := _panel()
	kp.add_child(lbl.keys)
	brv.add_child(kp)
	_place(brv, "br")


func _update_keys_help() -> void:
	var k := Game.key_name
	lbl.keys.text = "%s/%s engines · %s/%s rudder · %s center · %s crew/manual aim\n%s fire · %s torpedo aim · %s smoke · %s next target · %s follow salvos\n%s camera on target · %s pause · %s/%s/%s slow/normal/fast · %s menu\nWheel zoom · drag to look around (%s locks the camera back on)\nLeft-click: target (crew aim) or fire (manual) · right-click: target" % [
		k.call("tele_up"), k.call("tele_down"), k.call("rudder_left"), k.call("rudder_right"), k.call("rudder_center"), k.call("aim_mode"),
		k.call("fire"), k.call("torpedo"), k.call("smoke"), k.call("next_target"), k.call("follow"),
		k.call("camera"), k.call("pause"), k.call("slow"), k.call("normal"), k.call("fast"), k.call("menu"), k.call("recenter")]


func _build_log() -> void:
	log_box = VBoxContainer.new()
	log_box.add_theme_constant_override("separation", 3)
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_box.custom_minimum_size.x = 520
	_place(log_box, "tc")


func log_msg(txt: String, kind := "") -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_GLASS
	sb.border_color = C_RED if kind == "bad" else (C_GREEN if kind == "good" else C_BRASS)
	sb.border_width_left = 3
	sb.content_margin_left = 9; sb.content_margin_right = 9
	sb.content_margin_top = 4; sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(txt, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 500
	p.add_child(l)
	log_box.add_child(p)
	log_box.move_child(p, 0)
	while log_box.get_child_count() > 5:
		var last := log_box.get_child(log_box.get_child_count() - 1)
		log_box.remove_child(last)
		last.queue_free()
	var tw := p.create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.9)
	tw.tween_callback(p.queue_free)


# =====================================================================
# briefing and action report
# =====================================================================

func _build_brief() -> void:
	brief = _panel()
	brief.custom_minimum_size = Vector2(560, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 9)
	v.add_child(_label("MISSION BRIEFING", 11, C_BRASS))
	lbl.brief_title = _label("Intercept the Tokyo Express", 28)
	v.add_child(lbl.brief_title)
	lbl.threat = _label("", 15, C_BRASS)
	v.add_child(lbl.threat)
	lbl.brief_text = _label("", 14, Color(0.8, 0.84, 0.83))
	lbl.brief_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.brief_text.custom_minimum_size.x = 520
	v.add_child(lbl.brief_text)
	mission_row = _row([_caps("Mission"), _seg("mission", [["dd", "Destroyers"], ["barges", "PT barge hunt"], ["convoy", "PT convoy"], ["cruisers", "Cruiser night action"], ["bbs", "Battleship action"], ["fleet", "Fleet action"], ["carriers", "Carrier strike"], ["subpatrol", "Submarine patrol"], ["subhunt", "Submarine hunt"], ["escort", "Convoy escort"], ["bombard", "Shore bombardment"], ["rescue", "Rescue"]], _on_mission)])
	v.add_child(mission_row)
	ship_row = HBoxContainer.new()
	ship_row.add_theme_constant_override("separation", 2)
	v.add_child(_row([_caps("Your ship"), ship_row]))
	support_row = HBoxContainer.new()
	support_row.add_theme_constant_override("separation", 2)
	lbl.rep = _label("", 12, C_BRASS)
	var sup_box := VBoxContainer.new()
	sup_box.add_child(lbl.rep)
	sup_box.add_child(support_row)
	v.add_child(_row([_caps("Support"), sup_box]))
	cond_row = _row([_caps("Conditions"), _seg("weather", [["clear", "Clear day"], ["overcast", "Overcast"], ["fog", "Fog"], ["night", "Night"]], _on_weather)])
	v.add_child(cond_row)
	v.add_child(_row([_caps("Aim"), _seg("aim_b", [["auto", "Crew (auto)"], ["manual", "Manual (mouse)"]], _on_aim_brief)]))
	v.add_child(_row([_caps("Magazines"), _seg("mag", [["historical", "Historical"], ["reduced", "Reduced"], ["off", "Off"]], _on_mag)]))
	v.add_child(_row([_caps("Paint"), _seg("scheme", [["m21", "Measure 21"], ["m22", "Measure 22"]], _on_scheme)]))
	var go := _button("Begin the action", _on_begin)
	go.add_theme_font_size_override("font_size", 16)
	v.add_child(go)
	brief.add_child(v)
	_place(brief, "c")


## Support ships for sale on the briefing, within rank cap and reputation.
func _build_support_row() -> void:
	for c in support_row.get_children():
		c.queue_free()
	var p: Ship = B.player
	var avail: Array = Missions.support_available(int(Game.career.year), p.cls())
	var cap: int = Missions.RANK_CAP[clampi(Game.career.rank, 0, Missions.RANK_CAP.size() - 1)]
	var in_group := 1
	for sh in B.ships:
		if sh.team == p.team and sh != p and sh.group == p.group and sh.group != "":
			in_group += 1
	lbl.rep.text = "%s · reputation %d (%d to spend after this) · ships in battle %d of %d allowed" % [Missions.RANKS[clampi(Game.career.rank, 0, 8)], Game.career.reputation, Game.career.reputation - B._spent, in_group, cap]
	# in the campaign, ships are recruited in port instead (the squadron sails with you)
	support_row.get_parent().get_parent().visible = not avail.is_empty() and not Game.campaign_active()
	if Game.campaign_active():
		return
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	for it in avail:
		var tid: String = it[0]
		var n: int = B.support.count(tid)
		var b := _button("%s%s · %d" % [("%d× " % n) if n > 0 else "", it[1].replace("-class ", " "), it[2]], func(): B.toggle_support(tid), true)
		b.add_theme_font_size_override("font_size", 11)
		b.set_pressed_no_signal(n > 0)
		grid.add_child(b)
	support_row.add_child(grid)


func _update_brief() -> void:
	var W: Dictionary = Data.WEATHER[B.weather]
	var bf: Dictionary = B.brief
	lbl.brief_title.text = bf.get("title", "")
	var threat: String = bf.get("threat", "Moderate")
	if B.weather == "fog":
		threat += "; fog will hide both sides"
	lbl.threat.text = "Threat assessment: %s" % threat
	if not Game.mission.is_empty():
		var zone_name := ""
		if War.ZONES.has(Game.mission.get("zone", "")):
			zone_name = War.ZONES[Game.mission.zone].name
		Audio.ui("radio", 0.7, "Radio")
		lbl.brief_text.text = Story.dispatch(bf, int(Game.mission.get("day", 0)), B.player.ship_name, Missions.RANKS[clampi(Game.career.rank, 0, 8)], zone_name) + "\nConditions: %s." % W.name.to_lower()
	else:
		lbl.brief_text.text = "%s Conditions: %s." % [bf.get("text", ""), W.name.to_lower()]


func _build_end() -> void:
	endp = _panel()
	endp.custom_minimum_size = Vector2(460, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 9)
	v.add_child(_label("ACTION REPORT", 11, C_BRASS))
	lbl.end_t = _label("", 28)
	v.add_child(lbl.end_t)
	lbl.end_p = _label("", 14, Color(0.8, 0.84, 0.83))
	lbl.end_p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.end_p.custom_minimum_size.x = 430
	v.add_child(lbl.end_p)
	btn.fight_again = _button("Fight again", func(): B.new_game())
	btn.to_map = _button("Return to the map", func(): get_tree().change_scene_to_file("res://scenes/ops.tscn"))
	btn.aar = _button("After-action report", _show_aar)
	v.add_child(_row([btn.fight_again, btn.to_map, btn.aar, _button("Keep watching", func(): endp.visible = false)]))
	endp.add_child(v)
	_place(endp, "c")
	endp.visible = false


func show_end() -> void:
	var st: Dictionary = B.stats
	var p: Ship = B.player
	var lost: int = st.start_crew - p.crew
	match B.over:
		"won":
			lbl.end_t.text = "Mission accomplished"
		"escaped":
			lbl.end_t.text = "The enemy got through"
		"lost_convoy":
			lbl.end_t.text = "Mission failed"
		_:
			lbl.end_t.text = "%s lost" % p.ship_name
	var sunk_txt: String = ", ".join(st.sunk) if not st.sunk.is_empty() else "none"
	var acc: float = 100.0 * st.hits / maxf(1.0, _shells_fired())
	var txt := "Battle time %s.\nEnemy sunk: %s.\n" % [_clock(B.t), sunk_txt]
	if not st.escaped.is_empty():
		txt += "Got away: %s.\n" % ", ".join(st.escaped)
	if st.get("rescued", 0) > 0:
		txt += "Survivors rescued: %d.\n" % st.rescued
	var rep: int = st.get("rep_gained", 0)
	txt += "Reputation %s%d (now %d).\n" % ["+" if rep >= 0 else "", rep, Game.career.reputation]
	for ln in st.get("career_lines", []):
		txt += "\n" + ln
	txt += "Bursts and salvos fired: %d, hits: %d (%.0f%%).\nTorpedoes fired: %d, torpedo hits: %d.\nCrew lost: %d of %d." % [st.salvos, st.hits, acc, st.torps, st.torp_hits, lost, st.start_crew]
	var friends_lost := []
	for s in B.ships:
		if s.team == p.team and s != p and not s.alive:
			friends_lost.append(s.ship_name)
	if not friends_lost.is_empty():
		txt += "\nFriendly boats lost: %s." % ", ".join(friends_lost)
	if B.over == "won" and p.alive:
		txt += "\n\nObjective destroyed and your boat is still afloat. Well done, Captain."
	lbl.end_p.text = txt
	btn.to_map.visible = not Game.mission.is_empty()
	btn.aar.visible = st.has("aar")
	var diff: Dictionary = Career.DIFFICULTY.get(Game.career.get("difficulty", "officer"), Career.DIFFICULTY.officer)
	btn.fight_again.visible = Game.mission.is_empty() or (diff.retry and B.over != "won")
	if not Game.mission.is_empty() and diff.retry and B.over != "won":
		btn.fight_again.text = "Retry (Ensign difficulty)"
	endp.visible = true


func _show_aar() -> void:
	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(UI.backdrop(0.6))
	var p := UI.panel(20)
	var v := UI.column(8)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(760, 560)
	var l := UI.label(B.stats.get("aar", ""), 13)
	l.add_theme_font_override("font", ThemeDB.fallback_font)
	sc.add_child(l)
	v.add_child(sc)
	v.add_child(UI.row([UI.button("Close", func(): panel.queue_free())]))
	p.add_child(v)
	panel.add_child(p)
	UI.center(p)
	root.add_child(panel)


func _shells_fired() -> float:
	return float(B.stats.shells)


func _clock(sec: float) -> String:
	return "%d:%02d" % [int(sec) / 60, int(sec) % 60]


# =====================================================================
# callbacks from the battle
# =====================================================================

func on_new_game() -> void:
	brief.visible = true
	endp.visible = false
	_update_keys_help()
	for c in log_box.get_children():
		c.queue_free()
	_set_seg("weather", B.weather)
	_set_seg("mission", B.scenario)
	mission_row.visible = Game.mission.is_empty()
	cond_row.visible = Game.mission.is_empty()
	for c in ship_row.get_children():
		c.queue_free()
	var choices: Array = B.brief.get("ships", [])
	for ch in choices:
		var id: String = ch[0]
		var b := _button(ch[1], func(): B.ship_choice = id; B.new_game(), true)
		b.add_theme_font_size_override("font_size", 12)
		b.set_pressed_no_signal(B.player.type_id == id)
		ship_row.add_child(b)
	ship_row.get_parent().visible = not choices.is_empty()
	_build_support_row()
	_set_seg("view", "close" if B.player.T.L < 40.0 else "ship")
	_set_seg("cam", "player")
	_set_seg("depth", B.player.depth)
	_set_seg("mag", B.magazine)
	_set_seg("scheme", B.scheme)
	btn.follow.set_pressed_no_signal(B.follow)
	btn.slowf.set_pressed_no_signal(B.slow_follow)
	btn.lead.set_pressed_no_signal(B.show_lead)
	btn.snd.set_pressed_no_signal(B.sfx.enabled)
	btn.pyro.set_pressed_no_signal(B.fx.use_pyro and B.fx.has_pyro())
	btn.pyro.visible = B.fx.has_pyro()
	on_aim()
	for c in guns_box.get_children():
		c.queue_free()
	for m in B.player.mounts:
		var cr := ColorRect.new()
		cr.custom_minimum_size = Vector2(14, 14)
		guns_box.add_child(cr)
	lbl.title.text = B.player.ship_name
	_update_brief()


func on_speed(v: float) -> void:
	_set_seg("time", v)


func on_aim() -> void:
	_set_seg("aim", B.aim_mode)
	_set_seg("aim_b", B.aim_mode)


func on_focus() -> void:
	_set_seg("cam", B.camst.focus)


# =====================================================================
# per-frame refresh
# =====================================================================

func refresh() -> void:
	var p: Ship = B.player
	if p == null:
		return
	_refresh_air(p)
	_refresh_sub(p)
	_refresh_squad(p)
	var W: Dictionary = Data.WEATHER[B.weather]
	lbl.sub.text = "%s · %s · Battle time %s" % [p.T.name, W.name, _clock(B.t)]
	_refresh_detection(p, W)
	for i in tele_btns.size():
		tele_btns[i].set_pressed_no_signal(i == p.tele)
	lbl.spd.text = "%.1f kn" % (p.v / Data.KN)
	lbl.hdg.text = "Course %s°" % U.deg3(p.h)
	if B.t < p.rud_jam_until:
		lbl.rud.text = "RUDDER JAMMED at %d° %s" % [absi(int(p.rud)), "right" if p.rud > 0 else "left"]
	elif absf(p.rud_cmd) < 0.5:
		lbl.rud.text = "Rudder amidships"
	else:
		lbl.rud.text = "%s %d° rudder" % ["Right" if p.rud_cmd > 0 else "Left", absi(int(round(p.rud_cmd)))]
	rud_view.queue_redraw()
	dial_view.queue_redraw()
	# damage
	lbl.crew.text = "%d / %d" % [p.crew, p.T.crew]
	_set_bar("crew", float(p.crew) / p.T.crew)
	lbl.eff.text = "%d%%" % int(round(p.eff() * 100.0))
	lbl.flood.text = "%d t" % int(p.flood)
	_set_bar("flood", p.flood / p.flood_cap())
	lbl.list.text = "%.1f° %s" % [absf(rad_to_deg(p.roll)), "" if absf(p.roll) < 0.01 else ("stbd" if p.roll > 0 else "port")]
	var fire_sum := 0.0
	for f in p.fires:
		fire_sum += f.int
	lbl.fires.text = "No fires" if p.fires.is_empty() else "%d fire%s burning%s" % [p.fires.size(), "s" if p.fires.size() > 1 else "", ", spreading" if fire_sum > 1.2 else ""]
	lbl.fires.add_theme_color_override("font_color", C_MUTED if p.fires.is_empty() else C_RED)
	# fire control
	var tg: Ship = p.target
	if tg and tg.alive:
		var how := "visual" if p.vis.get(tg.ship_name, false) else ("radar" if p.radar.get(tg.ship_name, false) else "lost contact")
		lbl.tgt.text = "%s · %s · %s" % [tg.ship_name, U.yards(p.range_to(tg)), how]
	else:
		lbl.tgt.text = "No target"
	_set_bar("sol", p.q / 0.95)
	if B.aim_mode == "manual":
		lbl.sol.text = "Manual aim"
	elif tg == null:
		lbl.sol.text = "No solution"
	else:
		lbl.sol.text = "Poor" if p.q < 0.3 else ("Fair" if p.q < 0.6 else ("Good" if p.q < 0.85 else "Excellent"))
	var gi := 0
	for c in guns_box.get_children():
		if gi >= p.mounts.size():
			break
		var m: Dictionary = p.mounts[gi]
		c.color = Color(0.07, 0.07, 0.07) if m.hp <= 0.0 else (C_GREEN if m.reload <= 0.0 else C_BRASS)
		gi += 1
	if not p.torps.is_empty() and p.torps[0].fixed:
		var left := 0
		for tp in p.torps:
			left += tp.left if tp.hp > 0.0 else 0
		lbl.torps.text = "%d of %d ready · fire ahead" % [left, p.torps.size()]
	else:
		var tparts := []
		for tp in p.torps:
			if tp.hp <= 0.0:
				tparts.append("x")
			elif tp.left == 0:
				tparts.append("reloading %ds" % int(ceil(B.torp_reload_time(p) - tp.reload_t)))
			else:
				tparts.append("%d/%d" % [tp.left, tp.n])
		lbl.torps.text = " · ".join(tparts) if not tparts.is_empty() else "none"
	btn.fire.disabled = B.aim_mode == "manual"
	btn.fire.text = "Click to fire" if B.aim_mode == "manual" else ("Cease fire (F)" if p.fire else "Open fire (F)")
	btn.fire.set_pressed_no_signal(p.fire and B.aim_mode != "manual")
	btn.smoke.set_pressed_no_signal(p.smoke_on)
	btn.torp.set_pressed_no_signal(B.torp_aim)
	overlay.queue_redraw()


# =====================================================================
# drawing
# =====================================================================

func on_depth() -> void:
	_set_seg("depth", B.player.depth)


func _refresh_sub(p: Ship) -> void:
	sub_row.visible = p.is_sub()
	if p.is_sub():
		lbl.battery.text = "Battery %d%%  ·  %s" % [int(p.battery * 100), ["surfaced", "periscope depth, %d m" % int(p.depth_m), "deep, %d m" % int(p.depth_m)][p.depth]]
	var asw: bool = p.dc_left > 0 or p.T.get("hedgehog", p.type_id == "buckley") or p.sonar_range() > 0.0
	asw_row.visible = asw and not p.is_sub()
	if asw_row.visible:
		btn.charges.visible = p.T.get("depth_charges", 0) > 0
		btn.hedgehog.visible = p.T.get("hedgehog", p.type_id == "buckley")
		var txt := "%d charges" % p.dc_left if p.T.get("depth_charges", 0) > 0 else ""
		if p.sonar_contacts.is_empty():
			txt += "  ·  sonar: no contact" if p.sonar_range() > 0.0 else ""
		else:
			var k = p.sonar_contacts.keys()[0]
			var c: Dictionary = p.sonar_contacts[k]
			txt += "  ·  sonar contact %s, %s (%s)" % [U.deg3(p.bearing_to(c.x, c.z)), U.yards(U.hyp(c.x - p.x, c.z - p.z)), "deep" if c.depth == 2 else "shallow"]
		lbl.dc.text = txt


## The squadron plate: one row per friendly ship with its state and order buttons, and an
## "All ships" row. Rebuilt only when the list of ships or their orders change.
func _refresh_squad(p: Ship) -> void:
	var mates := []
	for s in B.ships:
		if s.team == p.team and s != p and s.alive and not s.escaped and s.role() in ["warship", "pt"] and s.T.get("crew", 0) >= 10 and not s.T.get("ground", false):
			mates.append(s)
	squad_plate.visible = not mates.is_empty()
	if mates.is_empty():
		return
	var key := ""
	for s in mates:
		key += "%s:%s:%s|" % [s.ship_name, s.order, s.ai_state]
	key += (p.target.ship_name if p.target else "-") + str(squad_open)
	if key == _squad_key:
		return
	_squad_key = key
	for c in squad_box.get_children():
		c.queue_free()
	# header with a fold button; folded, the panel is one line with the count and any orders
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	var fold := _button("▾ Orders" if squad_open else "▸ Orders", func(): squad_open = not squad_open; _squad_key = "")
	fold.add_theme_font_size_override("font_size", 11)
	hdr.add_child(fold)
	var ordered := 0
	for s in mates:
		if s.order != "":
			ordered += 1
	hdr.add_child(_label("SHIPS IN COMPANY · %d ship%s%s" % [mates.size(), "" if mates.size() == 1 else "s", (" · %d under orders" % ordered) if ordered > 0 else ""], 11, C_BRASS))
	squad_box.add_child(hdr)
	if not squad_open:
		return
	var tgt_name: String = p.target.ship_name if p.target and p.target.alive else ""
	var order_row := func(who: Array, label: String, state: String):
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 2)
		var nm := _label(label, 12)
		nm.custom_minimum_size.x = 150
		hb.add_child(nm)
		for od in [["follow", "Follow"], ["engage", "Engage"], ["fallback", "Fall back"], ["rescue", "Rescue"], ["attack", "Attack " + (tgt_name if tgt_name != "" else "target")]]:
			var b := _button(od[1], (func(ships, o): _give_order(ships, o)).bind(who, od[0]), true)
			b.add_theme_font_size_override("font_size", 11)
			if who.size() == 1 and who[0].order == od[0]:
				b.set_pressed_no_signal(true)
			if od[0] == "attack" and tgt_name == "":
				b.disabled = true
			hb.add_child(b)
		squad_box.add_child(hb)
		if state != "":
			var st := _label(state, 10, C_MUTED)
			squad_box.add_child(st)
	order_row.call(mates, "All ships", "")
	for s in mates:
		var o_txt: String = {"": "", "follow": "following", "engage": "engaging", "fallback": "falling back", "rescue": "rescuing", "attack": "attacking %s" % (s.order_target.ship_name if s.order_target else "")}.get(s.order, "")
		order_row.call([s], "%s · %s" % [s.ship_name, s.T.name.replace(" class", "")], s.ai_state if (o_txt == "" or s.ai_state.begins_with(o_txt.substr(0, 5))) else "%s · %s" % [s.ai_state, o_txt])


func _give_order(ships: Array, o: String) -> void:
	var p: Ship = B.player
	for s in ships:
		if s.order == o and ships.size() == 1:
			s.order = ""          # click again to release
			s.order_target = null
			continue
		s.order = o
		s.order_target = p.target if o == "attack" and p.target and p.target.alive else null
		s.detached = false
	var names: String = "All ships" if ships.size() > 1 else ships[0].ship_name
	var txt: String = {"follow": "%s: form on me.", "engage": "%s: engage at will.", "fallback": "%s: fall back and open the range.", "rescue": "%s: pick up survivors.", "attack": "%s: attack " + (p.target.ship_name if p.target else "the target") + "."}.get(o, "%s: carry on.")
	B.say(txt % names, "")
	Audio.ui("radio", 0.4, "Radio")
	_squad_key = ""


## Concealment and ranges, refreshed every frame (cheap: a few numbers).
func _refresh_detection(p: Ship, W: Dictionary) -> void:
	var cc: Array = B.concealment(p)
	var det: bool = B.detected(p)
	var firing: bool = B.t - p.last_fired < 3.0 and (W.night or B.weather == "fog")
	lbl.detected.text = ("DETECTED" if det else "Not detected") + (" · gun flashes seen to %s" % U.yards(cc[1]) if firing else "")
	lbl.detected.add_theme_color_override("font_color", C_RED if det else C_GREEN)
	lbl.det_conceal.text = "%s by sea%s" % [U.yards(cc[0]), (" · %s firing" % U.yards(cc[1])) if cc[1] > cc[0] * 1.05 else ""]
	var eye: float = W.vis * (p.T.night_eye if W.night else 1.0)
	lbl.det_spot.text = "PT %s · DD %s · BB %s" % [U.yards(eye * 0.5), U.yards(eye * 0.95), U.yards(eye * 1.4)]
	lbl.det_radar.text = U.yards(p.T.radar) if p.T.radar > 0.0 and p.mod_health("director") > 0.0 else ("knocked out" if p.T.radar > 0.0 else "none")
	lbl.det_main.text = U.yards(p.max_range()) if p.max_range() > 0.0 else "none"
	var sr := p.secondary_range()
	lbl.det_secondary.text = U.yards(sr) if sr > 0.0 else "none"
	var ar := p.aa_range()
	lbl.det_aa.text = U.yards(ar) if ar > 0.0 else "none"
	lbl.det_torp.text = ("%s · %d fish" % [U.yards(p.T.torp.range), p.torps_left()]) if not p.torps.is_empty() else "none"
	lbl.det_sonar.text = U.yards(p.sonar_range()) if p.sonar_range() > 0.0 else "none"


func _refresh_air(p: Ship) -> void:
	var mine := []
	for sq in B.air.sqs:
		if sq.home == p and sq.state != "lost":
			mine.append(sq)
	air_plate.visible = not mine.is_empty()
	if mine.is_empty():
		return
	var lines := []
	for sq in mine:
		var A: Dictionary = Data.AIRCRAFT[sq.type]
		var st: String = sq.state
		if st == "ready":
			st = "ready" if sq.rearm <= 0.0 else "rearming %d:%02d" % [int(sq.rearm) / 60, int(sq.rearm) % 60]
		elif st == "outbound" and sq.target:
			st = "outbound to %s" % sq.target.ship_name
		lines.append("%d %s (%s): %s" % [sq.n, A.name, _kind_short(sq.kind), st])
	lbl.air.text = "\n".join(lines)
	_set_seg("aa", B.air.aa_mode)
	btn.strike.disabled = B.air.ready_squadrons(p, ["dive", "torpedo"]).is_empty() or _rearming(p, ["dive", "torpedo"])
	btn.cap.disabled = B.air.ready_squadrons(p, ["fighter"]).is_empty() or _rearming(p, ["fighter"])
	btn.scout.disabled = B.air.ready_squadrons(p, ["scout"]).is_empty() or _rearming(p, ["scout"])


func _rearming(p: Ship, kinds: Array) -> bool:
	for sq in B.air.ready_squadrons(p, kinds):
		if sq.rearm <= 0.0:
			return false
	return true


func _kind_short(kind: String) -> String:
	return {"fighter": "fighters", "dive": "dive bombers", "torpedo": "torpedo bombers", "scout": "scouts"}.get(kind, kind)


## The ship dial: hull from above (bow up), each mount as a turret with its barrels where they
## point, coloured by state (ready, loading with a fill, cannot bear, knocked out); torpedo
## tubes as bars; a ring of relative bearings; the target as a wedge and a tick on the ring.
func _draw_dial() -> void:
	var p: Ship = B.player
	if p == null:
		return
	var s := dial_view.size
	var c := s / 2.0
	var R := minf(s.x, s.y) / 2.0 - 6.0
	var font = ThemeDB.fallback_font
	# ring and ticks
	dial_view.draw_circle(c, R, Color(0.02, 0.05, 0.07, 0.75))
	dial_view.draw_arc(c, R, 0, TAU, 72, Color(0.75, 0.8, 0.8, 0.5), 1.2)
	for i in 36:
		var a := TAU * i / 36.0
		var ln := 7.0 if i % 9 == 0 else (4.5 if i % 3 == 0 else 2.5)
		dial_view.draw_line(c + Vector2(sin(a), -cos(a)) * (R - ln), c + Vector2(sin(a), -cos(a)) * R, Color(0.75, 0.8, 0.8, 0.6 if i % 3 == 0 else 0.35), 1.0)
	# the target: a wedge for the main battery's chance to bear, and a tick on the ring
	var tg: Ship = p.target
	if tg and tg.alive and p.contact(tg):
		var rb := p.rel_bearing(tg.x, tg.z)
		var pts := PackedVector2Array([c])
		for k in 13:
			var a2 := rb + deg_to_rad(-9.0 + 1.5 * k)
			pts.append(c + Vector2(sin(a2), -cos(a2)) * (R - 2.0))
		dial_view.draw_colored_polygon(pts, Color(0.55, 0.85, 1.0, 0.16))
		dial_view.draw_line(c + Vector2(sin(rb), -cos(rb)) * (R - 12.0), c + Vector2(sin(rb), -cos(rb)) * R, C_RED, 3.0)
	# hull
	var L: float = p.T.L
	var k := (R * 1.5) / L
	var hull := PackedVector2Array()
	var steps := 36
	for i in steps + 1:
		var lx := -L / 2.0 + L * i / steps
		hull.append(c + Vector2(p.half_width_at(lx) * k * 2.4, -lx * k))
	for i in range(steps, -1, -1):
		var lx := -L / 2.0 + L * i / steps
		hull.append(c + Vector2(-p.half_width_at(lx) * k * 2.4, -lx * k))
	dial_view.draw_colored_polygon(hull, Color(0.16, 0.2, 0.22, 0.95))
	# flooding: water fills the hull from the keel line outward
	var ff := clampf(p.flood / p.flood_cap(), 0.0, 1.0)
	if ff > 0.0:
		var wp := PackedVector2Array()
		for q in hull:
			wp.append(Vector2(lerpf(c.x, q.x, ff), q.y))
		dial_view.draw_colored_polygon(wp, Color(C_WATER, 0.5))
	hull.append(hull[0])
	dial_view.draw_polyline(hull, Color(0.8, 0.85, 0.85, 0.85), 1.2)
	# internal modules (engines, magazines, bridge, steering...) as small blocks by health,
	# engines to port of the centreline, magazines to starboard
	for m in p.modules:
		if m.kind in ["mount", "torp"]:
			continue
		var f: float = m.hp / m.max
		var col := Color(0.12, 0.12, 0.12) if f <= 0.0 else (C_RED if f < 0.4 else (C_BRASS if f < 0.8 else Color(0.35, 0.6, 0.45)))
		var off := 0.0
		if m.kind == "engine": off = -p.half_width_at(m.x) * k * 2.4 * 0.55
		elif m.kind == "magazine": off = p.half_width_at(m.x) * k * 2.4 * 0.55
		var mpos := c + Vector2(off, -m.x * k)
		dial_view.draw_rect(Rect2(mpos - Vector2(2.5, 2.5), Vector2(5, 5)), col)
	# holes at the waterline and fires on deck
	for hl in p.holes:
		var hp := c + Vector2(hl.side * p.half_width_at(hl.lx) * k * 2.4, -hl.lx * k)
		dial_view.draw_circle(hp, 3.5 if hl.fix < 0.9 else 2.0, C_WATER if hl.fix < 0.9 else Color(C_WATER, 0.4))
	for fr in p.fires:
		var fp := c + Vector2(fr.lz * k * 2.4 * 0.5, -fr.lx * k)
		var a := 0.6 + 0.4 * sin(B.t * 9.0 + fr.lx)
		dial_view.draw_circle(fp, 3.0 + fr.int * 4.0, Color(1.0, 0.5, 0.15, a))
	# mounts
	for m in p.mounts:
		var g: Dictionary = m.gun
		var main: bool = g == p.gun
		var pos := c + Vector2(m.get("lz", 0.0) * k * 2.4, -m.x * k)
		var sz: float = (5.5 if main else 3.0) * clampf(g.size, 0.6, 1.4)
		var col: Color
		if m.hp <= 0.0:
			col = Color(0.5, 0.12, 0.1)
		elif not m.bears and tg != null:
			col = Color(0.45, 0.48, 0.5)
		elif m.reload > 0.0:
			col = Color(0.85, 0.65, 0.3)
		else:
			col = Color(1.0, 0.86, 0.45) if main else Color(0.7, 0.9, 0.75)
		if main:
			dial_view.draw_rect(Rect2(pos - Vector2(sz, sz * 0.8), Vector2(sz * 2.0, sz * 1.6)), col)
			# loading: the dark part is what is left to load
			if m.reload > 0.0 and m.hp > 0.0:
				var frac: float = clampf(m.reload / maxf(0.1, g.reload / maxf(0.3, p.eff())), 0.0, 1.0)
				dial_view.draw_rect(Rect2(pos - Vector2(sz, sz * 0.8), Vector2(sz * 2.0 * frac, sz * 1.6)), Color(0.1, 0.12, 0.13, 0.85))
			var bl := sz * 2.2
			var ang: float = m.ang
			dial_view.draw_line(pos, pos + Vector2(sin(ang), -cos(ang)) * bl, col, 2.0)
		else:
			dial_view.draw_circle(pos, sz, col)
			if g.dmg >= 0.5:
				dial_view.draw_line(pos, pos + Vector2(sin(m.ang), -cos(m.ang)) * sz * 1.8, col, 1.2)
	# torpedo tubes
	for tb in p.torps:
		var pos := c + Vector2(0.0, -tb.x * k)
		var col := Color(0.5, 0.12, 0.1) if tb.hp <= 0.0 else (Color(0.85, 0.65, 0.3) if tb.left == 0 else Color(0.6, 0.85, 1.0))
		dial_view.draw_rect(Rect2(pos - Vector2(7, 2), Vector2(14, 4)), Color(col, 0.35))
		var tf: float = 1.0 if tb.left > 0 else clampf(tb.reload_t / B.torp_reload_time(p), 0.0, 1.0)
		dial_view.draw_rect(Rect2(pos - Vector2(7, 2), Vector2(14 * tf, 4)), col)
		dial_view.draw_string(font, pos + Vector2(9, 4), str(tb.left) if tb.left > 0 else "%ds" % int(ceil(B.torp_reload_time(p) - tb.reload_t)), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)
	# heading at the top of the ring
	dial_view.draw_string(font, c + Vector2(-12, -R + 16), U.deg3(p.h), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_INK)
	# aim mode and fire state at the bottom
	var mode := "MANUAL" if B.aim_mode == "manual" else ("FIRING" if p.fire else "HOLDING")
	dial_view.draw_string(font, c + Vector2(-22, R - 6), mode, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_BRASS)


func _draw_rudder() -> void:
	var p: Ship = B.player
	var s := rud_view.size
	rud_view.draw_rect(Rect2(0, s.y / 2 - 3, s.x, 6), Color(1, 1, 1, 0.12))
	rud_view.draw_line(Vector2(s.x / 2, 1), Vector2(s.x / 2, s.y - 1), Color(1, 1, 1, 0.5), 1.0)
	var xc := s.x / 2 + p.rud_cmd / 35.0 * (s.x / 2 - 3)
	rud_view.draw_line(Vector2(xc, s.y / 2 - 5), Vector2(xc, s.y / 2 + 5), Color(1, 1, 1, 0.35), 2.0)
	var x := s.x / 2 + p.rud / 35.0 * (s.x / 2 - 3)
	rud_view.draw_rect(Rect2(x - 2, 0, 4, s.y), C_BRASS)


func _p(x: float, z: float, y := 0.0) -> Vector2:
	return B.cam.unproject_position(Vector3(x, y, z))


var _edge_used: Array = []

func _draw_overlay() -> void:
	_edge_used.clear()
	var p: Ship = B.player
	if p == null:
		return
	var vs := overlay.size
	var font = ThemeDB.fallback_font
	var px_per_m: float = vs.y / (2.0 * tan(deg_to_rad(32.0) / 2.0) * B.camst.h)
	# gun range ring when zoomed out
	if px_per_m < 0.12 and p.alive:
		_ring(Vector2(p.x, p.z), p.max_range(), Color(C_BRASS, 0.35), "Main guns")
		var sr := p.secondary_range()
		if sr > 0.0:
			_ring(Vector2(p.x, p.z), sr, Color(C_BRASS, 0.18), "Secondaries")
		var ar := p.aa_range()
		if ar > 0.0 and ar < sr * 0.9:
			_ring(Vector2(p.x, p.z), ar, Color(0.7, 0.9, 0.75, 0.18), "AA")
		if p.T.radar > 0.0:
			_ring(Vector2(p.x, p.z), p.T.radar, Color(C_GREEN, 0.25), "Radar")
		var cc: Array = B.concealment(p)
		_ring(Vector2(p.x, p.z), cc[0], Color(1.0, 1.0, 1.0, 0.3), "Concealment")
	# own ship marker when zoomed far out
	if px_per_m < 0.5 and not p.gone:
		var pc := _p(p.x, p.z, 6.0)
		overlay.draw_arc(pc, 9.0, 0, TAU, 24, Color(0.55, 0.85, 1.0, 0.9), 1.6)
		var fwv := U.fwd(p.h)
		overlay.draw_line(pc, pc + Vector2(fwv.x, fwv.y) * 18.0, Color(0.55, 0.85, 1.0, 0.9), 1.6)
	# reported enemy position until they are found
	var rp: Dictionary = B.report
	if rp.active:
		var c := _p(rp.x, rp.z)
		var rr: float = rp.r * px_per_m
		if rr > 8.0:
			_dashed_circle(c, rr, Color(C_RED, 0.6))
		var f := U.fwd(rp.h)
		var tip := _p(rp.x + f.x * rp.r * 0.9, rp.z + f.y * rp.r * 0.9)
		if Rect2(Vector2.ZERO, vs).has_point(c):
			overlay.draw_line(c, tip, Color(C_RED, 0.8), 2.0)
			overlay.draw_string(font, c + Vector2(8, -6), "Enemy reported here, course %s" % U.deg3(rp.h), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_RED)
		else:
			_edge_arrow(c, "Enemy reported · %s" % U.yards(p.range_to(rp)), C_RED)
	# ships
	for s in B.ships:
		if s == p or s.gone:
			continue
		if s.team == p.team:
			# friendly ships: a blue ring and the name
			var fp := _p(s.x, s.z, 3.0)
			var fc := Color(0.55, 0.85, 1.0, 0.9) if s.alive else C_MUTED
			var fr := maxf(8.0, s.T.L * 0.5 * px_per_m + 4.0)
			overlay.draw_arc(fp, fr, 0, TAU, 24, fc, 1.2)
			overlay.draw_string(font, fp + Vector2(fr + 4, 4), s.ship_name + ("" if s.alive else " · sinking"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, fc)
			continue
		var known: bool = p.contact(s) or (not s.alive and s.spotted_once)
		if not known:
			continue
		var sp := _p(s.x, s.z, 6.0)
		var on := Rect2(Vector2.ZERO, vs).grow(-20).has_point(sp)
		var is_t = s == p.target
		var col := C_BRASS if is_t else (C_RED if s.alive else C_MUTED)
		var name_txt: String = s.ship_name if p.vis.get(s.ship_name, false) or not s.alive else "Radar contact"
		var info := "%s · %s" % [name_txt, U.yards(p.range_to(s))]
		if not s.alive:
			info = "%s · sinking" % s.ship_name
		if on:
			var half := maxf(10.0, s.T.L * 0.5 * px_per_m + 6.0)
			_bracket(sp, half, col, is_t)
			overlay.draw_string(font, sp + Vector2(half + 6, -half + 10), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
			if is_t:
				overlay.draw_string(font, sp + Vector2(half + 6, -half + 26), "TARGET", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		else:
			_edge_arrow(sp, info, col)
	# torpedoes we know about
	for tp in B.torps:
		if tp.team == "us" or tp.warned:
			var tc := _p(tp.x, tp.z)
			var f2 := U.fwd(tp.h)
			var tail := _p(tp.x - f2.x * 35.0, tp.z - f2.y * 35.0)
			overlay.draw_line(tail, tc, Color(C_INK, 0.55) if tp.team == "us" else Color(C_RED, 0.6), 1.5)
	# torpedo aiming fan and lead marker, or the manual gun reticle
	if B.torp_aim and p.alive and B.started:
		_draw_torp_aim(p, px_per_m, font)
	elif B.aim_mode == "manual" and B.mouse_w != null and p.alive and B.started:
		_draw_reticle(p, px_per_m, font)
	# crew aim: show where the guns are pointing
	if B.speed == 0.0 and B.started:
		var t := "TACTICAL PAUSE"
		overlay.draw_string(font, Vector2(vs.x / 2 - 90, vs.y * 0.3), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, C_BRASS)
	if B.camst.salvo != null:
		var sv: Dictionary = B.camst.salvo
		overlay.draw_string(font, Vector2(vs.x / 2 - 120, vs.y * 0.3 + 30), "Following salvo %d  (V to stop)" % sv.n, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_INK)


func _draw_reticle(p: Ship, px_per_m: float, font: Font) -> void:
	var mw: Vector2 = B.mouse_w
	var mp := _p(mw.x, mw.y)
	var R := U.hyp(mw.x - p.x, mw.y - p.z)
	var rb := p.rel_bearing(mw.x, mw.y)
	var bearing := 0
	var ready := 0
	for m in p.mounts:
		if m.hp > 0.0 and Ship.mount_can_bear(m, rb):
			bearing += 1
			if m.reload <= 0.0 and absf(U.ang_d(m.ang, rb)) < deg_to_rad(4.0):
				ready += 1
	var in_range: bool = R <= p.max_range()
	var col := C_RED if not in_range or bearing == 0 else (Color(0.44, 0.81, 0.66) if ready > 0 else C_BRASS)
	var spread := maxf(10.0, R * 0.007 / p.eff() * px_per_m * 2.0)
	overlay.draw_arc(mp, spread, 0, TAU, 48, col, 1.6)
	overlay.draw_line(mp + Vector2(-spread - 10, 0), mp + Vector2(-4, 0), col, 1.6)
	overlay.draw_line(mp + Vector2(4, 0), mp + Vector2(spread + 10, 0), col, 1.6)
	overlay.draw_line(mp + Vector2(0, -spread - 10), mp + Vector2(0, -4), col, 1.6)
	overlay.draw_line(mp + Vector2(0, 4), mp + Vector2(0, spread + 10), col, 1.6)
	overlay.draw_string(font, mp + Vector2(spread + 14, -4), "%s · %d s" % [U.yards(R), int(round(p.tof_for(R)))], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_INK)
	var st := "Out of range" if not in_range else ("Guns cannot bear" if bearing == 0 else "%d/%d guns ready" % [ready, bearing])
	overlay.draw_string(font, mp + Vector2(spread + 14, 12), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_INK)
	# reload ring: one segment per main-battery gun, filling as it loads; bright when ready
	var mains := []
	for m in p.mounts:
		if m.gun == p.gun and m.hp > 0.0:
			mains.append(m)
	if not mains.is_empty():
		var n := mains.size()
		var rr := spread + 7.0
		var gap := deg_to_rad(6.0)
		var full: float = maxf(0.1, p.gun.reload / maxf(0.3, p.eff()))
		var soonest := 99.0
		for i in n:
			var m: Dictionary = mains[i]
			var a0 := -PI / 2.0 + TAU * i / n + gap / 2.0
			var a1 := -PI / 2.0 + TAU * (i + 1) / n - gap / 2.0
			overlay.draw_arc(mp, rr, a0, a1, 12, Color(1, 1, 1, 0.18), 3.0)
			var frac: float = 1.0 if m.reload <= 0.0 else clampf(1.0 - m.reload / full, 0.0, 1.0)
			var bears: bool = Ship.mount_can_bear(m, rb)
			var seg_col := (Color(0.44, 0.81, 0.66) if bears else Color(0.6, 0.6, 0.6)) if m.reload <= 0.0 else Color(C_BRASS, 0.9)
			if frac > 0.01:
				overlay.draw_arc(mp, rr, a0, a0 + (a1 - a0) * frac, 12, seg_col, 3.0)
			if m.reload > 0.0:
				soonest = minf(soonest, m.reload)
		if ready == 0 and soonest < 99.0:
			overlay.draw_string(font, mp + Vector2(-14, -spread - 16), "%.1f s" % soonest, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_BRASS)
		elif ready > 0:
			overlay.draw_string(font, mp + Vector2(-22, -spread - 16), "READY" if ready == n else "%d READY" % ready, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.44, 0.81, 0.66))
	overlay.draw_string(font, mp + Vector2(spread + 14, 28), "click: one gun · double-click: salvo", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_MUTED)
	# lead marker: where the target will be when the shells arrive
	var tg: Ship = p.target
	if B.show_lead and tg and tg.alive and p.contact(tg):
		var Rt := p.range_to(tg)
		var tof := p.tof_for(Rt)
		var f := U.fwd(tg.h)
		var a := _p(tg.x, tg.z)
		var b := _p(tg.x + f.x * tg.v * tof, tg.z + f.y * tg.v * tof)
		_dashed_line(a, b, Color(C_INK, 0.6))
		overlay.draw_line(b + Vector2(-7, -7), b + Vector2(7, 7), Color(C_INK, 0.9), 1.6)
		overlay.draw_line(b + Vector2(7, -7), b + Vector2(-7, 7), Color(C_INK, 0.9), 1.6)
		overlay.draw_string(font, b + Vector2(-14, -12), "Lead", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_INK)


## World of Warships-style torpedo aiming: lanes from the tubes along the mouse bearing,
## and a lead marker showing where the target will be when the torpedoes get there.
func _draw_torp_aim(p: Ship, px_per_m: float, font: Font) -> void:
	var green := Color(0.44, 0.81, 0.66)
	var vs := overlay.size
	var tg: Ship = p.target if p.target and p.target.alive and p.contact(p.target) else null
	var rng: float = p.T.torp.range
	var spd := p.torp_speed()
	# lead marker on the selected target
	var lead = null
	if tg:
		var ip: Array = p.torp_intercept(tg, p.x, p.z)
		lead = ip[0]
		var a := _p(tg.x, tg.z)
		var b := _p(lead.x, lead.y)
		_dashed_line(a, b, Color(1.0, 0.85, 0.4, 0.7))
		var half := maxf(9.0, tg.T.L * 0.5 * px_per_m)
		# ghost outline of the target where it will be
		var fwv := U.fwd(tg.h)
		var bow := _p(lead.x + fwv.x * tg.T.L * 0.5, lead.y + fwv.y * tg.T.L * 0.5)
		var stern := _p(lead.x - fwv.x * tg.T.L * 0.5, lead.y - fwv.y * tg.T.L * 0.5)
		overlay.draw_line(stern, bow, Color(1.0, 0.85, 0.4, 0.9), maxf(3.0, tg.T.B * px_per_m))
		overlay.draw_arc(b, half + 6.0, 0, TAU, 32, Color(1.0, 0.85, 0.4, 0.9), 1.5)
		var far: bool = U.hyp(lead.x - p.x, lead.y - p.z) > rng
		overlay.draw_string(font, b + Vector2(half + 10, -4), "Torpedo lead · %d s" % int(ip[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.85, 0.4))
		if far:
			overlay.draw_string(font, b + Vector2(half + 10, 12), "Beyond torpedo range", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_RED)
		if not Rect2(Vector2.ZERO, vs).has_point(b):
			_edge_arrow(b, "Torpedo lead", Color(1.0, 0.85, 0.4))
	if B.mouse_w == null:
		return
	var mw: Vector2 = B.mouse_w
	var brg := p.bearing_to(mw.x, mw.y)
	var ok: Array = p.torp_mounts_for(brg)
	var col := green if not ok.is_empty() else C_RED
	# lanes: two from a PT boat's racks, or one mount's fan
	var lanes := []
	if ok.is_empty() or p.torps[ok[0]].fixed:
		for sd in [-1.0, 1.0]:
			lanes.append([p.to_world_xz(2.9, p.T.B * 0.4 * sd), brg + deg_to_rad(1.0) * sd])
	else:
		var m: Dictionary = p.torps[ok[0]]
		var n: int = m.left
		var mp := p.to_world_xz(m.x, 0.0)
		for k in n:
			lanes.append([mp, brg + (k - (n - 1) / 2.0) * deg_to_rad(1.4)])
	var on_target := false
	for ln in lanes:
		var st: Vector2 = ln[0]
		var a2: float = ln[1]
		var en := st + Vector2(sin(a2), -cos(a2)) * rng
		overlay.draw_line(_p(st.x, st.y), _p(en.x, en.y), Color(col, 0.18), 6.0)
		_dashed_line(_p(st.x, st.y), _p(en.x, en.y), Color(col, 1.0), 2.2)
		var ep := _p(en.x, en.y)
		overlay.draw_line(ep + Vector2(-5, 0), ep + Vector2(5, 0), col, 2.0)
		if lead != null and tg:
			# does this lane pass through the target at the lead point?
			var d := Vector2(sin(a2), -cos(a2))
			var rel: Vector2 = lead - st
			var along := rel.dot(d)
			var across := absf(rel.x * d.y - rel.y * d.x)
			if along > 0.0 and along < rng and across < tg.T.L * 0.45:
				on_target = true
	var mp2 := _p(mw.x, mw.y)
	var txt := "TORPEDO AIM · bearing %s · %d ready" % [U.deg3(brg), p.torps_left()]
	overlay.draw_string(font, mp2 + Vector2(16, -6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	var tip := "Click to fire"
	if ok.is_empty():
		tip = "Turn the boat: racks angle only 30° off the bow" if p.torps[0].fixed else "Mounts fire off the beam only"
	elif on_target:
		tip = "ON TARGET · click to fire"
	elif tg:
		tip = "Line the lanes up with the lead marker"
	overlay.draw_string(font, mp2 + Vector2(16, 10), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, green if on_target else (col if ok.is_empty() else C_INK))


func _bracket(c: Vector2, half: float, col: Color, thick: bool) -> void:
	var l := half * 0.4
	var w := 2.0 if thick else 1.3
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			var corner := c + Vector2(sx * half, sy * half)
			overlay.draw_line(corner, corner - Vector2(sx * l, 0), col, w)
			overlay.draw_line(corner, corner - Vector2(0, sy * l), col, w)


func _ring(center: Vector2, radius: float, col: Color, text: String) -> void:
	var c := _p(center.x, center.y)
	var e := _p(center.x + radius, center.y)
	var rr := (e - c).length()
	_dashed_circle(c, rr, col)
	overlay.draw_string(ThemeDB.fallback_font, c + Vector2(6, -rr - 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


func _dashed_circle(c: Vector2, rr: float, col: Color) -> void:
	var n := 72
	for i in n:
		if i % 2 == 0:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			overlay.draw_line(c + Vector2(cos(a0), sin(a0)) * rr, c + Vector2(cos(a1), sin(a1)) * rr, col, 1.4)


func _dashed_line(a: Vector2, b: Vector2, col: Color, w := 1.2) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 1.0:
		return
	var u := d / ln
	var s := 0.0
	while s < ln:
		overlay.draw_line(a + u * s, a + u * minf(ln, s + 5.0), col, w)
		s += 10.0


func _edge_arrow(target: Vector2, text: String, col: Color) -> void:
	var vs := overlay.size
	var c := vs / 2.0
	var d := target - c
	if d.length() < 1.0:
		return
	# keep arrows inside the area between the instrument plates
	var inner := Rect2(Vector2(70, 180), vs - Vector2(140, 400))
	c = inner.get_center()
	d = target - c
	var kx: float = (inner.size.x / 2.0) / maxf(absf(d.x), 0.001)
	var ky: float = (inner.size.y / 2.0) / maxf(absf(d.y), 0.001)
	var p := c + d * minf(kx, ky)
	var u := d.normalized()
	var n := Vector2(-u.y, u.x)
	var tri := PackedVector2Array([p + u * 12.0, p - u * 6.0 + n * 8.0, p - u * 6.0 - n * 8.0])
	overlay.draw_colored_polygon(tri, col)
	var font = ThemeDB.fallback_font
	var tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var tp := p - u * 22.0 - Vector2(tw / 2.0, -4)
	tp.x = clampf(tp.x, 8.0, vs.x - tw - 8.0)
	# stack labels that would overlap an earlier one
	for r in _edge_used:
		if absf(r.y - tp.y) < 14.0 and tp.x < r.x + r.z + 6.0 and tp.x + tw + 6.0 > r.x:
			tp.y = r.y + 15.0 * (1.0 if u.y <= 0.0 else -1.0)
	_edge_used.append(Vector3(tp.x, tp.y, tw))
	overlay.draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


# =====================================================================
# input
# =====================================================================

func _unhandled_input(e: InputEvent) -> void:
	var p: Ship = B.player
	if e is InputEventKey and e.pressed:
		if pausep != null and pausep.visible:
			if Game.pressed(e, "menu"):
				close_pause()
			return
		if brief.visible:
			if e.keycode == KEY_ENTER or e.keycode == KEY_SPACE:
				brief.visible = false
				B.begin()
			elif Game.pressed(e, "menu"):
				open_pause()
			return
		if Game.pressed(e, "tele_up"): B.order_tele(p.tele + 1)
		elif Game.pressed(e, "tele_down"): B.order_tele(p.tele - 1)
		elif Game.pressed(e, "rudder_left"): B.order_rudder(p.rud_cmd - 5.0)
		elif Game.pressed(e, "rudder_right"): B.order_rudder(p.rud_cmd + 5.0)
		elif Game.pressed(e, "rudder_center"): B.order_rudder(0.0)
		elif Game.pressed(e, "fire"): B.toggle_fire()
		elif Game.pressed(e, "aim_mode"): B.set_aim("auto" if B.aim_mode == "manual" else "manual")
		elif Game.pressed(e, "torpedo"): B.fire_torpedoes()
		elif Game.pressed(e, "smoke"): B.toggle_smoke()
		elif Game.pressed(e, "next_target"): B.cycle_target()
		elif Game.pressed(e, "follow"):
			B.follow = not B.follow
			btn.follow.set_pressed_no_signal(B.follow)
			if not B.follow:
				B.camst.salvo = null
		elif Game.pressed(e, "camera"): B.set_focus("player" if B.camst.focus == "target" else "target")
		elif Game.pressed(e, "recenter"): B.recenter()
		elif Game.pressed(e, "pause"): _toggle_pause()
		elif Game.pressed(e, "slow"): B.set_speed(0.25)
		elif Game.pressed(e, "normal"): B.set_speed(1.0)
		elif Game.pressed(e, "fast"): B.set_speed(3.0)
		elif Game.pressed(e, "strike"): B.order_strike()
		elif Game.pressed(e, "star"): B.order_star()
		elif Game.pressed(e, "dive"): B.order_depth(p.depth + 1)
		elif Game.pressed(e, "surface"): B.order_depth(p.depth - 1)
		elif Game.pressed(e, "charges"): B.order_charges()
		elif Game.pressed(e, "hedgehog"): B.order_hedgehog()
		elif Game.pressed(e, "menu"):
			if B.torp_aim:
				B.torp_aim = false
			else:
				open_pause()
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			B.zoom(1.0 / 1.15)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			B.zoom(1.15)
		elif e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT:
			var pan_btn: int = MOUSE_BUTTON_LEFT if Game.settings.get("pan_left", false) else MOUSE_BUTTON_RIGHT
			if e.button_index == pan_btn:
				# drag moves the camera; a plain click still picks a target
				if e.pressed:
					drag = {"start": e.position, "last": e.position, "moved": 0.0}
				else:
					if not drag.is_empty() and drag.moved < 6.0 and B.started:
						var w0 = B.screen_to_world(e.position)
						if w0 != null:
							B.pick_target_at(w0)
					drag = {}
			elif e.pressed and B.started:
				var w = B.screen_to_world(e.position)
				if w != null:
					if B.torp_aim and p.alive:
						B.torp_click(w)
					elif B.aim_mode == "manual" and p.alive:
						# click: one gun; a second click within a third of a second: the whole salvo
						var now := Time.get_ticks_msec() / 1000.0
						var dbl: bool = now - _last_click_t < 0.33
						_last_click_t = now
						B.click_shot = {"aim": w, "salvo": dbl}
					else:
						B.pick_target_at(w)
	elif e is InputEventMouseMotion:
		B.mouse_w = B.screen_to_world(e.position)
		if not drag.is_empty():
			var d: Vector2 = e.position - drag.last
			drag.last = e.position
			drag.moved += d.length()
			if drag.moved >= 6.0:
				B.pan(d.x, d.y)


# =====================================================================
# pause menu (Esc)
# =====================================================================

func open_pause() -> void:
	if pausep != null:
		return
	_pause_prev = B.speed if B.speed > 0.0 else B.prev_speed
	B.set_speed(0.0)
	pausep = Control.new()
	pausep.set_anchors_preset(Control.PRESET_FULL_RECT)
	pausep.mouse_filter = Control.MOUSE_FILTER_STOP
	pausep.add_child(UI.backdrop(0.5))
	var pnl := UI.panel(22)
	var v := UI.column(8)
	v.add_child(UI.label("PAUSED", 11, UI.BRASS))
	v.add_child(UI.label(B.brief.get("title", "Battle"), 24))
	v.add_child(UI.label("%s · battle time %s" % [B.player.ship_name, _clock(B.t)], 12, UI.MUTED))
	var sp := Control.new()
	sp.custom_minimum_size.y = 8
	v.add_child(sp)
	v.add_child(UI.big_button("Resume", close_pause))
	var sv := UI.big_button("Save battle", _pause_save)
	sv.disabled = not B.started or B.over != ""
	v.add_child(sv)
	v.add_child(UI.big_button("Load battle", _pause_load))
	v.add_child(UI.big_button("Settings", func(): pausep.add_child(SettingsPanel.new())))
	if not Game.mission.is_empty():
		v.add_child(UI.big_button("Career", func(): pausep.add_child(CareerPanel.new())))
	v.add_child(UI.big_button("Encyclopedia", func(): pausep.add_child(EncyclopediaPanel.new())))
	v.add_child(UI.big_button("New battle (briefing)", func(): close_pause(); B.new_game()))
	if not Game.mission.is_empty():
		v.add_child(UI.big_button("Abandon battle (back to the map)", func(): Game.last_result = {"over": "abandoned", "mission": Game.mission.duplicate(true)}; get_tree().change_scene_to_file("res://scenes/ops.tscn")))
	v.add_child(UI.big_button("Main menu", func(): get_tree().change_scene_to_file("res://scenes/menu.tscn")))
	v.add_child(UI.big_button("Quit to desktop", func(): get_tree().quit()))
	pnl.add_child(v)
	pausep.add_child(pnl)
	UI.center(pnl)
	root.add_child(pausep)


func close_pause() -> void:
	if pausep == null:
		return
	pausep.queue_free()
	pausep = null
	if B.started and B.over == "":
		B.set_speed(_pause_prev if _pause_prev > 0.0 else 1.0)


func _pause_save() -> void:
	var sp := SlotPanel.new("save")
	pausep.add_child(sp)
	sp.picked.connect(func(i):
		if Game.save_slot(i, B.save_state()):
			log_msg("Battle saved to slot %d." % (i + 1), "good")
		else:
			log_msg("Could not write the save file.", "bad")
		close_pause())


func _pause_load() -> void:
	var sp := SlotPanel.new("load")
	pausep.add_child(sp)
	sp.picked.connect(func(i):
		var d := Game.load_slot(i)
		close_pause()
		if d.is_empty():
			log_msg("That slot is empty.", "bad")
		else:
			B.load_state(d))


func _toggle_pause() -> void:
	if B.speed == 0.0:
		B.set_speed(B.prev_speed if B.prev_speed > 0.0 else 1.0)
	else:
		B.prev_speed = B.speed
		B.set_speed(0.0)


func _on_pyro() -> void:
	B.fx.use_pyro = btn.pyro.button_pressed
	Game.settings.pyro = btn.pyro.button_pressed
	Game.save_settings()
	if not B.fx.use_pyro:
		for n in get_tree().get_nodes_in_group("pyro"):
			n.queue_free()

func _on_sound() -> void:
	B.sfx.enabled = btn.snd.button_pressed
	btn.snd.text = "Sound on" if B.sfx.enabled else "Sound off"

func _on_view(v) -> void:
	B.set_view(v)
	_set_seg("view", v)

func _on_focus(v) -> void:
	B.set_focus(v)

func _on_mission(m) -> void:
	B.set_scenario(m)

func _on_weather(w) -> void:
	B.weather = w
	B.apply_weather()
	_set_seg("weather", w)
	_update_brief()

func _on_aim_brief(m) -> void:
	B.aim_mode = m
	on_aim()

func _on_mag(m) -> void:
	B.magazine = m
	_set_seg("mag", m)

func _on_scheme(sc) -> void:
	B.set_scheme(sc)
	_set_seg("scheme", sc)

func _on_begin() -> void:
	brief.visible = false
	B.begin()
