extends Control
## The operations map: the Pacific from Pearl Harbor to Japan, sailed freely in real time with
## time compression. Contacts appear in the sea zones; sail to one and engage to open the battle.
## The war moves along its historical timeline, nudged by the player's results (campaign.shift).

const HOURS_PER_SEC := 0.35          # at speed 1: one game hour every ~3 seconds
const SPEEDS := [0.0, 1.0, 4.0, 24.0]
const ENGAGE_NM := 60.0
const PORT_NM := 70.0
const KIND_LABEL := {"express": "Tokyo Express", "convoy": "Convoy", "barges": "Barge traffic", "sub": "Submarine", "taskforce": "Task force", "carriers": "Carrier force",
	"bombard": "Bombardment request", "rescue": "Rescue", "escort": "Convoy to escort"}

var C: Dictionary                     # Game.campaign
var map: Control
var cam_lon := 160.0
var cam_lat := 5.0
var zoom := 9.0                        # pixels per degree
var speed_i := 1
var selected := ""                     # contact id
var lbl := {}
var btn := {}
var side: VBoxContainer
var log_box: VBoxContainer
var card: Control = null
var _drag := {}
var _hour_acc := 0.0
var _rng := RandomNumberGenerator.new()
var _save_t := 0.0


func _ready() -> void:
	_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if Game.campaign.is_empty():
		Game.campaign = new_campaign(0, "fletcher", "USS O'Bannon")
	C = Game.campaign
	if Career.ship(Game.career).is_empty() or Career.ship(Game.career).type != C.ship:
		Career.take_command(Game.career, C.ship, C.name, int(C.day))
	cam_lon = C.lon; cam_lat = C.lat
	_build_ui()
	_apply_result()
	speed_i = 0
	_refresh_top()
	_log("Operations map. Click the sea to set a course; sail to a contact and engage it.")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ops="):
			# test: run the map fast for a while, then screenshot
			speed_i = 3
			_test_shot(a.split("=")[1])


func _test_shot(path: String) -> void:
	for i in 300:
		await get_tree().process_frame
		if card != null:
			_close_card()
			speed_i = 3
	speed_i = 0
	if "--career" in OS.get_cmdline_user_args():
		add_child(CareerPanel.new())
		for i in 10:
			await get_tree().process_frame
	await get_tree().process_frame
	print("contacts ", C.contacts.size(), " day ", C.day, " ops ", C.done_ops)
	if "--engage" in OS.get_cmdline_user_args() and not C.contacts.is_empty():
		var ct: Dictionary = C.contacts[0]
		C.lon = ct.lon; C.lat = ct.lat
		print("engaging ", ct.kind, " ", ct.desc)
		_engage(ct)
		return
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	get_tree().quit()


static func new_campaign(start_day: int, ship: String, name: String) -> Dictionary:
	var base := "Pearl Harbor" if start_day < 180 else ("Espiritu Santo" if start_day < 900 else "Ulithi")
	var b: Dictionary = War.BASES[base]
	var done := []
	for op in War.OPERATIONS:
		if op.day < start_day:
			done.append(op.name)
	return {"day": float(start_day), "lon": b.lon, "lat": b.lat, "dest": null, "shift": 0.0, "contacts": [], "done_ops": done, "ship": ship, "name": name,
		"log": [], "sunk_total": 0, "won": 0, "lost": 0}


# =====================================================================
# UI
# =====================================================================

func _build_ui() -> void:
	var back := ColorRect.new()
	back.color = Color(0.03, 0.10, 0.17)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	map = Control.new()
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.draw.connect(_draw_map)
	map.gui_input.connect(_map_input)
	add_child(map)
	# top bar
	var top := UI.panel(10)
	var th := UI.row([], 14)
	lbl.date = UI.label("", 20)
	th.add_child(lbl.date)
	var sp := HBoxContainer.new()
	sp.add_theme_constant_override("separation", 2)
	for i in SPEEDS.size():
		var b := UI.button(["Pause", "1 h / 3 s", "Fast", "Very fast"][i], (func(k): speed_i = k; _refresh_top()).bind(i), true)
		btn["sp%d" % i] = b
		sp.add_child(b)
	th.add_child(UI.row([UI.caps("Time", 40), sp]))
	lbl.ship = UI.label("", 14)
	th.add_child(lbl.ship)
	lbl.career = UI.label("", 14, UI.BRASS)
	th.add_child(lbl.career)
	th.add_child(UI.button("Main menu", func(): _save(); get_tree().change_scene_to_file("res://scenes/menu.tscn")))
	top.add_child(th)
	add_child(top)
	top.anchor_right = 1.0
	top.offset_left = 12; top.offset_top = 12; top.offset_right = -12; top.offset_bottom = 12
	top.grow_vertical = Control.GROW_DIRECTION_END
	# side panel
	var sp2 := UI.panel(12)
	side = UI.column(6)
	side.custom_minimum_size.x = 360
	sp2.add_child(side)
	add_child(sp2)
	sp2.anchor_left = 1.0; sp2.anchor_right = 1.0; sp2.anchor_top = 0.0
	sp2.offset_left = -12; sp2.offset_right = -12; sp2.offset_top = 90; sp2.offset_bottom = 90
	sp2.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sp2.grow_vertical = Control.GROW_DIRECTION_END
	# log
	log_box = UI.column(3)
	log_box.custom_minimum_size.x = 560
	add_child(log_box)
	log_box.anchor_top = 1.0; log_box.anchor_bottom = 1.0
	log_box.offset_left = 12; log_box.offset_top = -12; log_box.offset_right = 12; log_box.offset_bottom = -12
	log_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	log_box.grow_horizontal = Control.GROW_DIRECTION_END
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_side()


func _refresh_top() -> void:
	var h := int(fposmod(C.day, 1.0) * 24.0)
	lbl.date.text = "%s  %02d:00" % [War.date_str(int(C.day)), h]
	for i in SPEEDS.size():
		btn["sp%d" % i].set_pressed_no_signal(i == speed_i)
	var T: Dictionary = Data.TYPES[C.ship]
	lbl.ship.text = "%s (%s) · %s" % [C.name, T.name, _where()]
	lbl.career.text = "%s · reputation %d · %d sunk, %d won, %d lost" % [Missions.RANKS[clampi(Game.career.rank, 0, 8)], Game.career.reputation, C.sunk_total, C.won, C.lost]


func _where() -> String:
	var best := ""
	var bd := 1e9
	for zid in War.ZONES:
		var z: Dictionary = War.ZONES[zid]
		var d := War.dist_nm(C.lon, C.lat, z.lon, z.lat)
		if d < bd:
			bd = d; best = z.name
	var port := _port_here()
	if port != "":
		return "in port at %s" % port
	return best


func _port_here() -> String:
	for nm in War.BASES:
		var b: Dictionary = War.BASES[nm]
		if b.side == "us" and b.from >= 0 and C.day >= b.from and War.dist_nm(C.lon, C.lat, b.lon, b.lat) < PORT_NM:
			return nm
	return ""


func _refresh_side() -> void:
	for c in side.get_children():
		c.queue_free()
	side.add_child(UI.label("OPERATIONS", 11, UI.BRASS))
	side.add_child(UI.row([UI.button("Career", func(): add_child(CareerPanel.new())), UI.label("%d skill point%s to spend" % [Career.skill_points_left(Game.career), "" if Career.skill_points_left(Game.career) == 1 else "s"], 12, UI.BRASS if Career.skill_points_left(Game.career) > 0 else UI.MUTED)]))
	var port := _port_here()
	if port != "":
		side.add_child(UI.label("In port: %s" % port, 16))
		var cs := Career.ship(Game.career)
		var repair_days := _repair_days(cs)
		if repair_days > 0:
			var rb := UI.button("Repair (%d day%s in the yard)" % [repair_days, "" if repair_days == 1 else "s"], func(): _repair(repair_days))
			side.add_child(rb)
		else:
			side.add_child(UI.label("Ship in good order, crew at full strength.", 12, UI.GREEN))
		side.add_child(UI.row([UI.button("Request a new command", _request_command), UI.button("Refit (%d supply)" % Game.career.get("supply", 0), _refit_menu)]))
	var sel = _contact(selected)
	if sel != null:
		var d := War.dist_nm(C.lon, C.lat, sel.lon, sel.lat)
		side.add_child(UI.label(KIND_LABEL.get(sel.kind, sel.kind), 18))
		side.add_child(UI.wrap("%s · %s · threat %s · %.0f nm away · fades in %d h" % [War.ZONES[sel.zone].name, sel.desc, sel.threat, d, int((sel.expires - C.day) * 24.0)], 330, 12))
		var go := UI.button("Set course", func(): C.dest = [sel.lon, sel.lat]; _refresh_side())
		var eng := UI.button("Engage (%s)" % ("in range" if d < ENGAGE_NM else "%.0f nm to go" % (d - ENGAGE_NM)), func(): _engage(sel))
		eng.disabled = d > ENGAGE_NM
		side.add_child(UI.row([go, eng]))
	else:
		side.add_child(UI.wrap("Contacts appear in the zones as red markers. Click one for details; sail within %d nm to engage. Friendly bases are blue, enemy bases red; zones held by Japan are tinted red." % int(ENGAGE_NM), 330, 12, UI.MUTED))
	side.add_child(UI.label("Nearby contacts", 11, UI.BRASS))
	var near: Array = C.contacts.duplicate()
	near.sort_custom(func(a, b): return War.dist_nm(C.lon, C.lat, a.lon, a.lat) < War.dist_nm(C.lon, C.lat, b.lon, b.lat))
	var shown := 0
	for ct in near:
		if shown >= 6:
			break
		shown += 1
		var d2 := War.dist_nm(C.lon, C.lat, ct.lon, ct.lat)
		var b := UI.button("%s · %s · %.0f nm · %s" % [KIND_LABEL.get(ct.kind, ct.kind), War.ZONES[ct.zone].name, d2, ct.threat], (func(id): selected = id; _refresh_side()).bind(ct.id))
		b.add_theme_font_size_override("font_size", 12)
		side.add_child(b)
	if C.contacts.is_empty():
		side.add_child(UI.label("No contacts reported yet.", 12, UI.MUTED))


## Days in the yard to make good the ship's damage and bring the crew up to strength.
func _repair_days(cs: Dictionary) -> int:
	if cs.is_empty():
		return 0
	var T: Dictionary = Data.TYPES[cs.type]
	var miss := 0.0
	for k in cs.damage:
		miss += 1.0 - float(cs.damage[k]) / 4.0
	var crew_miss: float = 1.0 - float(cs.crew) / float(T.crew)
	var days := int(ceil(miss * 2.0 + crew_miss * 6.0 + cs.get("flood", 0.0) * 4.0))
	return days


func _repair(days: int) -> void:
	var cs := Career.ship(Game.career)
	var T: Dictionary = Data.TYPES[cs.type]
	# replacements are green: training is diluted by the share of new men
	var frac: float = 1.0 - float(cs.crew) / float(T.crew)
	cs.training = cs.training * (1.0 - frac * 0.7)
	cs.crew = int(T.crew)
	cs.damage = {}
	cs.flood = 0.0
	C.day += days
	_log("%s repaired and brought up to strength: %d day%s in the yard." % [cs.name, days, "" if days == 1 else "s"])
	_save()
	_refresh_side()
	_refresh_top()


func _request_command() -> void:
	var c: Dictionary = Game.career
	var year := War.year_of(int(C.day))
	var avail := Career.available_commands(c, year)
	card = Control.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(UI.backdrop(0.5))
	var p := UI.panel(20)
	p.custom_minimum_size.x = 640
	var v := UI.column(8)
	v.add_child(UI.label("REQUEST A COMMAND · %s" % Missions.RANKS[clampi(c.rank, 0, 8)], 11, UI.BRASS))
	v.add_child(UI.wrap("Your current ship goes into reserve with her crew, exactly as she is; you can ask for her back later. Officers come with you. A new ship means a new, green crew.", 600, 12, UI.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	for tid in avail:
		var T: Dictionary = Data.TYPES[tid]
		var names: Array = Career.SHIP_NAMES.get(tid, ["USS " + T.name])
		var nm: String = names[0]
		for cand in names:
			if not c.ships.has("%s|%s" % [tid, cand]):
				nm = cand
				break
		var same: bool = c.current == "%s|%s" % [tid, nm]
		var b := UI.button("%s · %s%s" % [nm, T.name, " (current)" if same else ""], (func(t2, n2): Career.take_command(c, t2, n2, int(C.day)); C.ship = t2; C.name = n2; _log("Took command of %s (%s)." % [n2, Data.TYPES[t2].name]); _close_card(); _save(); _refresh_side(); _refresh_top()).bind(tid, nm))
		b.disabled = same
		b.add_theme_font_size_override("font_size", 12)
		grid.add_child(b)
	for key in c.ships:
		if key != c.current:
			var o: Dictionary = c.ships[key]
			var b2 := UI.button("%s · %s (reserve, crew %s)" % [o.name, Data.TYPES[o.type].name, Career.training_label(o.training)], (func(k2): c.current = k2; C.ship = c.ships[k2].type; C.name = c.ships[k2].name; _log("Back aboard %s." % C.name); _close_card(); _save(); _refresh_side(); _refresh_top()).bind(key))
			b2.add_theme_font_size_override("font_size", 12)
			grid.add_child(b2)
	v.add_child(grid)
	v.add_child(UI.row([UI.button("Cancel", _close_card)]))
	p.add_child(v)
	card.add_child(p)
	UI.center(p)
	add_child(card)


func _refit_menu() -> void:
	var c: Dictionary = Game.career
	var year := War.year_of(int(C.day))
	var cs := Career.ship(c)
	card = Control.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(UI.backdrop(0.5))
	var p := UI.panel(20)
	p.custom_minimum_size.x = 700
	var v := UI.column(6)
	v.add_child(UI.label("REFIT · %s · %d supply points" % [cs.name, c.get("supply", 0)], 11, UI.BRASS))
	v.add_child(UI.wrap("Refits follow the real timeline: SG radar in 1942, fixed torpedoes and proximity fuzes in 1943. A ship in the yard misses what happens meanwhile.", 660, 12, UI.MUTED))
	for id in Career.refits_for(c, year):
		var r: Array = Career.REFITS[id]
		var row := UI.row([], 8)
		var b := UI.button("%d supply · %d day%s" % [r[2], r[4], "" if r[4] == 1 else "s"], (func(rid):
			var rr: Array = Career.REFITS[rid]
			c.supply -= rr[2]
			cs.refits.append(rid)
			C.day += rr[4]
			_log("%s refitted: %s (%d days)." % [cs.name, rr[0], rr[4]])
			_close_card(); _save(); _refresh_side(); _refresh_top()).bind(id))
		b.disabled = c.get("supply", 0) < r[2]
		b.custom_minimum_size.x = 150
		row.add_child(b)
		var col := UI.column(0)
		col.add_child(UI.label("%s · %s" % [r[0], r[1]], 13))
		col.add_child(UI.label(r[6], 11, UI.MUTED))
		row.add_child(col)
		v.add_child(row)
	v.add_child(UI.row([UI.button("Close", _close_card)]))
	p.add_child(v)
	card.add_child(p)
	UI.center(p)
	add_child(card)


func _log(txt: String) -> void:
	var l := UI.label("%s  %s" % [War.date_str(int(C.day)), txt], 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 540
	var p := UI.panel(6)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	log_box.add_child(p)
	log_box.move_child(p, 0)
	while log_box.get_child_count() > 5:
		var last := log_box.get_child(log_box.get_child_count() - 1)
		log_box.remove_child(last); last.queue_free()
	C.log.append([int(C.day), txt])
	if C.log.size() > 200:
		C.log.pop_front()


# =====================================================================
# time and the war
# =====================================================================

func _process(delta: float) -> void:
	if card != null:
		return
	var hours: float = delta * SPEEDS[speed_i] * HOURS_PER_SEC
	if hours <= 0.0:
		map.queue_redraw()
		return
	var day0 := int(C.day)
	C.day += hours / 24.0
	_sail(hours)
	_hour_acc += hours
	while _hour_acc >= 1.0:
		_hour_acc -= 1.0
		_tick_hour()
	if int(C.day) != day0:
		_tick_day()
	_check_operations()
	_save_t += delta
	if _save_t > 10.0:
		_save_t = 0.0
		_save()
	_refresh_top()
	map.queue_redraw()


func _sail(hours: float) -> void:
	if C.dest == null:
		return
	var T: Dictionary = Data.TYPES[C.ship]
	var kn: float = T.max_kn * 0.65
	var d := War.dist_nm(C.lon, C.lat, C.dest[0], C.dest[1])
	var step := kn * hours
	if d <= step:
		C.lon = C.dest[0]; C.lat = C.dest[1]
		C.dest = null
		speed_i = mini(speed_i, 1)
		_log("Arrived. %s." % _where().capitalize())
		_refresh_side()
		return
	var k := step / d
	C.lon += (C.dest[0] - C.lon) * k
	C.lat += (C.dest[1] - C.lat) * k


func _tick_hour() -> void:
	# contacts fade, new ones appear in active zones near the player
	var keep := []
	for ct in C.contacts:
		if ct.expires > C.day:
			keep.append(ct)
		elif ct.id == selected:
			selected = ""
	var changed: bool = keep.size() != C.contacts.size()
	C.contacts = keep
	for zid in War.ZONES:
		var z: Dictionary = War.ZONES[zid]
		var d := War.dist_nm(C.lon, C.lat, z.lon, z.lat)
		if d > 900.0:
			continue
		var here := 0
		for ct in C.contacts:
			if ct.zone == zid:
				here += 1
		if here >= 2 or C.contacts.size() >= 7:
			continue
		var act := War.activity(zid, C.day, C.shift)
		if _rng.randf() < act * 0.05:
			C.contacts.append(_make_contact(zid))
			changed = true
	if changed:
		_refresh_side()


func _tick_day() -> void:
	pass


func _make_contact(zid: String) -> Dictionary:
	var z: Dictionary = War.ZONES[zid]
	var own := War.owner(zid, C.day, C.shift)
	var T: Dictionary = Data.TYPES[C.ship]
	var cls: String = T.get("cls", "dd")
	var pool := []
	if own == "ijn":
		pool = ["express", "express", "convoy", "convoy", "barges", "sub", "taskforce"]
		var us_day: int = z.us
		if us_day > 0 and absf((us_day - C.shift) - C.day) < 60.0:
			pool += ["bombard", "bombard"]
		if cls in ["cv", "cvl", "cve"]:
			pool += ["carriers", "carriers"]
	else:
		pool = ["sub", "sub", "escort", "escort", "rescue", "convoy"]
	if cls == "pt":
		pool = ["barges", "barges", "convoy", "express", "rescue"]
	if cls == "ss":
		pool = ["convoy", "convoy", "convoy", "taskforce", "express"]
	var kind: String = pool[_rng.randi() % pool.size()]
	var strength := clampf(War.activity(zid, C.day, C.shift) * _rng.randf_range(0.6, 1.6) + (0.6 if cls in ["bb", "cv", "ca"] else 0.0), 0.3, 2.5)
	var a := _rng.randf() * TAU
	var r: float = z.r * _rng.randf_range(0.1, 0.8) / 60.0
	var lon: float = z.lon + cos(a) * r / cos(deg_to_rad(z.lat))
	var lat: float = z.lat + sin(a) * r
	var year := War.year_of(int(C.day))
	var plan := Missions.for_contact(kind, _rng, strength, year, C.ship, C.name)
	var et := []
	for e in plan.enemies:
		for sh in e.ships:
			et.append(sh[0])
	for sd in plan.get("shore", []):
		et.append(sd[0])
	var night: bool = plan.weather == "night"
	var th := Missions.threat(et, "night" if night else "clear")
	var desc := _describe(plan)
	return {"id": "%d_%d" % [int(C.day * 24.0), _rng.randi() % 10000], "kind": kind, "lon": lon, "lat": lat, "zone": zid, "expires": C.day + _rng.randf_range(1.0, 3.0),
		"strength": strength, "threat": th[1], "level": th[0], "plan": plan, "desc": desc}


func _describe(plan: Dictionary) -> String:
	var counts := {}
	for e in plan.enemies:
		for sh in e.ships:
			var nm: String = Data.TYPES[sh[0]].name.replace(" class", "").replace("Daihatsu landing barge", "barge").replace("Armed Daihatsu (gun barge)", "gun barge")
			counts[nm] = counts.get(nm, 0) + 1
	for sd in plan.get("shore", []):
		var nm2: String = Data.TYPES[sd[0]].name
		counts[nm2] = counts.get(nm2, 0) + 1
	var parts := []
	for k in counts:
		parts.append("%d %s" % [counts[k], k])
	return ", ".join(parts)


func _contact(id: String):
	for ct in C.contacts:
		if ct.id == id:
			return ct
	return null


## Historical operations arrive on their day (nudged by the player's shift) and are offered once.
func _check_operations() -> void:
	for op in War.OPERATIONS:
		if C.done_ops.has(op.name):
			continue
		if C.day >= op.day - C.shift * 0.5:
			C.done_ops.append(op.name)
			_offer_operation(op)
			return


func _offer_operation(op: Dictionary) -> void:
	speed_i = 0
	_refresh_top()
	var z: Dictionary = War.ZONES[op.zone]
	card = Control.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(UI.backdrop(0.45))
	var p := UI.panel(22)
	p.custom_minimum_size.x = 560
	var v := UI.column(8)
	v.add_child(UI.label("HISTORICAL OPERATION · %s" % War.date_str(int(C.day)), 11, UI.BRASS))
	v.add_child(UI.label(op.name, 26))
	v.add_child(UI.wrap(op.text, 520))
	v.add_child(UI.wrap("Area: %s. Taking part moves you there and opens the battle." % z.name, 520, 12, UI.MUTED))
	var row := UI.row([])
	if op.scenario != "":
		row.add_child(UI.big_button("Take part", func():
			C.lon = z.lon; C.lat = z.lat; C.dest = null
			_close_card()
			_launch(op.scenario, {}, "op", op.name, op.zone)))
	row.add_child(UI.big_button("Carry on" if op.scenario != "" else "Continue", _close_card))
	v.add_child(row)
	p.add_child(v)
	card.add_child(p)
	UI.center(p)
	add_child(card)
	_log("Operation: %s." % op.name)
	if op.scenario == "":
		C.war_over = true


func _close_card() -> void:
	if card:
		card.queue_free()
		card = null


# =====================================================================
# battles
# =====================================================================

func _engage(ct: Dictionary) -> void:
	_launch("", ct.plan, "contact", ct.id, ct.zone)


func _launch(scenario: String, plan: Dictionary, kind: String, ref: String, zone: String) -> void:
	var hour := fposmod(C.day, 1.0) * 24.0
	var night := hour < 5.5 or hour > 18.5
	var weather: String = "night" if night else ["clear", "clear", "overcast", "fog"][_rng.randi() % 4]
	if not plan.is_empty():
		if plan.weather == "night":
			weather = "night"
		Game.mission = {"plan": plan, "weather": weather, "kind": kind, "ref": ref, "zone": zone, "day": C.day}
	else:
		Game.mission = {"kind": kind, "ref": ref, "zone": zone, "day": C.day, "scenario": scenario}
		Game.start_scenario = scenario
	Game.career.year = War.year_of(int(C.day))
	Game.pending_load = -1
	_save()
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


## Back from a battle: apply the result to the war.
func _apply_result() -> void:
	var r: Dictionary = Game.last_result
	Game.last_result = {}
	Game.mission = {}
	if r.is_empty():
		return
	var m: Dictionary = r.get("mission", {})
	if m.get("kind", "") == "contact":
		var keep := []
		for ct in C.contacts:
			if ct.id != m.get("ref", ""):
				keep.append(ct)
		C.contacts = keep
		selected = ""
	var sunk: Array = r.get("sunk", [])
	C.sunk_total += sunk.size()
	match r.get("over", ""):
		"won":
			C.won += 1
			C.shift += 4.0 if m.get("kind", "") == "contact" else 12.0
			_log("Mission accomplished: %s. The war moves our way." % (", ".join(sunk) + " sunk" if not sunk.is_empty() else "objective met"))
		"abandoned":
			_log("Battle abandoned.")
		_:
			C.lost += 1
			C.shift -= 3.0
			_log("Mission failed%s." % ((": %s lost" % C.name) if not r.get("player_alive", true) else ""))
			if not r.get("player_alive", true):
				_ship_lost()
	# a battle takes the rest of the day
	C.day += 0.3
	_save()
	_refresh_side()


## The player's ship was sunk: Ironman ends the career; otherwise you survive, wait for a new
## command in port, and the ship is struck from the list.
func _ship_lost() -> void:
	var c: Dictionary = Game.career
	var diff: Dictionary = Career.DIFFICULTY.get(c.get("difficulty", "officer"), Career.DIFFICULTY.officer)
	var lost_name: String = C.name
	c.ships.erase(c.current)
	c.current = ""
	if diff.ironman:
		_log("%s was lost with all hands. The career ends here." % lost_name)
		Game.campaign = {}
		Game.save_campaign()
		_offer_end("Your ship was lost", "%s went down and the career ends with her (Ironman). Start a new campaign from the main menu." % lost_name)
		return
	# survivors are picked up and taken to the nearest friendly base
	var best := ""
	var bd := 1e9
	for nm in War.BASES:
		var b: Dictionary = War.BASES[nm]
		if b.side == "us" and b.from >= 0 and C.day >= b.from:
			var d := War.dist_nm(C.lon, C.lat, b.lon, b.lat)
			if d < bd:
				bd = d; best = nm
	if best != "":
		C.lon = War.BASES[best].lon; C.lat = War.BASES[best].lat
	C.day += 10.0
	c.reputation = maxi(0, c.reputation - 150)
	var year := War.year_of(int(C.day))
	var avail := Career.available_commands(c, year)
	var tid: String = avail[0] if not avail.is_empty() else "fletcher"
	for t in avail:
		if t == C.ship:
			tid = t
	var names: Array = Career.SHIP_NAMES.get(tid, ["USS Replacement"])
	var nm2: String = names[0]
	for cand in names:
		if not c.ships.has("%s|%s" % [tid, cand]):
			nm2 = cand
			break
	Career.take_command(c, tid, nm2, int(C.day))
	C.ship = tid; C.name = nm2
	_log("Survivors of %s landed at %s. After ten days you are given %s." % [lost_name, best, nm2])


func _offer_end(title: String, text: String) -> void:
	card = Control.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(UI.backdrop(0.6))
	var p := UI.panel(22)
	var v := UI.column(8)
	v.add_child(UI.label(title, 26))
	v.add_child(UI.wrap(text, 520))
	v.add_child(UI.big_button("Main menu", func(): get_tree().change_scene_to_file("res://scenes/menu.tscn")))
	p.add_child(v)
	card.add_child(p)
	UI.center(p)
	add_child(card)


func _save() -> void:
	Game.campaign = C
	Game.save_campaign()
	Game.save_career()


# =====================================================================
# map drawing and input
# =====================================================================

func _to_px(lon: float, lat: float) -> Vector2:
	var s := map.size
	return Vector2(s.x / 2 + (lon - cam_lon) * zoom, s.y / 2 - (lat - cam_lat) * zoom)


func _from_px(p: Vector2) -> Vector2:
	var s := map.size
	return Vector2(cam_lon + (p.x - s.x / 2) / zoom, cam_lat - (p.y - s.y / 2) / zoom)


## Very rough coastlines (lon, lat) for the look of the thing.
const LAND := {
	"Honshu": [[131, 34], [133, 35.5], [136, 36.5], [138, 37.5], [140, 39.5], [141.5, 41], [141.8, 38.5], [140.8, 36], [139.8, 35], [137, 34.5], [135, 33.6], [132.5, 33.8]],
	"Kyushu": [[129.6, 33.2], [131, 33.9], [131.9, 33.2], [131.3, 31.2], [130.3, 31.2], [129.7, 32.5]],
	"Hokkaido": [[140, 42], [141.5, 43.2], [144.5, 44], [145.5, 43.3], [143.5, 42], [141.5, 41.5]],
	"Formosa": [[120.2, 22], [120.7, 24.6], [121.6, 25.3], [121.9, 24.3], [120.9, 21.9]],
	"Luzon": [[120, 15.5], [120.5, 18.5], [122.2, 18.4], [122.1, 16.5], [121.5, 14.2], [120.7, 13.8]],
	"Mindanao": [[122, 7.5], [123, 8.6], [124.5, 8.2], [126.2, 7.2], [126.3, 6.3], [125.4, 5.6], [124, 6.6], [122.4, 6.8]],
	"Borneo": [[109, 1.5], [110, 3], [113, 4], [115, 5], [117, 7], [119, 5.3], [118, 1], [117, -2], [116, -3.8], [113.5, -3.2], [110, -2.5], [109, 0]],
	"Sumatra": [[95.5, 5.5], [98, 3.5], [102, -1], [104.5, -3], [106, -5.5], [104, -5.5], [101, -2.8], [97.5, 1.5]],
	"Java": [[105.2, -6.3], [108, -6.3], [111, -6.5], [114, -7.8], [114.3, -8.3], [111, -8.3], [108, -7.8], [105.5, -7]],
	"Celebes": [[119, 1.2], [120.5, 1.4], [122, 1], [124.5, 1.5], [125, 0.5], [123, 0.3], [121, -1], [122.5, -4], [121, -5.5], [120, -3], [119, -1]],
	"New Guinea": [[131, -1.5], [134, -1], [137, -1.6], [141, -2.6], [145, -4.3], [147.5, -6.3], [150.5, -10.5], [147.5, -10.2], [144.5, -8], [141, -9.2], [138, -8.3], [135, -4.5], [132, -4]],
	"New Britain": [[148.4, -5.6], [150.5, -5.1], [152.3, -4.2], [151.2, -5.8], [149.6, -6.3]],
	"Bougainville": [[154.7, -5.5], [155.9, -6.3], [156, -6.9], [155, -6.2]],
	"Guadalcanal": [[159.6, -9.3], [160.5, -9.6], [160.8, -9.9], [159.8, -9.8]],
	"Malaita": [[160.6, -8.4], [161.3, -9.2], [161, -9.5], [160.6, -8.8]],
	"Australia": [[131, -12], [136, -12.5], [138, -16.5], [141.5, -12.5], [143.5, -14], [145.8, -16.9], [149, -21], [152, -25], [153.5, -28], [153, -32], [148, -36], [141, -38], [136, -35], [130, -31], [124, -33], [117, -35], [115, -31], [114, -26], [117, -21], [122, -18], [128, -15]],
	"Oahu": [[-158.3, 21.3], [-157.6, 21.3], [-157.7, 21.7], [-158.3, 21.6]],
}
const DOTS := [[-156, 20.5, 3.0], [-155.5, 19.6, 4.0], [182.6, 28.2, 1.5], [173, 1.5, 1.2], [171.2, 7.1, 1.2], [167.7, 8.7, 1.2], [162.3, 11.4, 1.2],
	[145.7, 15.2, 1.8], [144.8, 13.4, 1.8], [151.8, 7.4, 1.5], [139.7, 10, 1.2], [134.5, 7.3, 1.8], [141.5, 24.8, 1.2], [127.7, 26.3, 2.5], [128.3, 27, 1.5], [166.4, -22.3, 3.5], [167.2, -15.5, 2.5], [160.1, -9.1, 1.2], [157, -8.3, 2.0], [158.6, -5.0, 1.0]]


func _draw_map() -> void:
	var font = ThemeDB.fallback_font
	var vs := map.size
	# zones first, tinted by owner
	for zid in War.ZONES:
		var z: Dictionary = War.ZONES[zid]
		var c := _to_px(z.lon, z.lat)
		var r: float = z.r / 60.0 * zoom
		var own := War.owner(zid, C.day, C.shift)
		var act := War.activity(zid, C.day, C.shift)
		var col := Color(0.85, 0.3, 0.25, 0.10 + 0.12 * act) if own == "ijn" else Color(0.35, 0.65, 0.95, 0.06 + 0.06 * act)
		map.draw_circle(c, r, col)
		map.draw_arc(c, r, 0, TAU, 48, Color(col, 0.5), 1.0)
		map.draw_string(font, c + Vector2(-r * 0.5, -r * 0.7), z.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.55))
	# land
	for nm in LAND:
		var pts := PackedVector2Array()
		for p in LAND[nm]:
			var lon: float = p[0] if p[0] > 0 else p[0] + 360.0
			pts.append(_to_px(lon, p[1]))
		if pts.size() >= 3:
			map.draw_colored_polygon(pts, Color(0.30, 0.36, 0.24))
			map.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.55, 0.6, 0.45, 0.8), 1.0)
	for d in DOTS:
		var lon: float = d[0] if d[0] > 0 else d[0] + 360.0
		map.draw_circle(_to_px(lon, d[1]), maxf(2.0, d[2] * zoom * 0.08), Color(0.32, 0.38, 0.26))
	# bases
	for nm in War.BASES:
		var b: Dictionary = War.BASES[nm]
		var us: bool = b.side == "us" and b.from >= 0 and C.day >= b.from
		var p := _to_px(b.lon, b.lat)
		var col := Color(0.55, 0.85, 1.0) if us else Color(0.95, 0.45, 0.35)
		map.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), col)
		if zoom > 7.0:
			map.draw_string(font, p + Vector2(7, 4), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col, 0.9))
	# contacts
	for ct in C.contacts:
		var p := _to_px(ct.lon, ct.lat)
		var col := UI.BRASS if ct.id == selected else Color(0.95, 0.35, 0.3)
		var pts := PackedVector2Array([p + Vector2(0, -8), p + Vector2(8, 0), p + Vector2(0, 8), p + Vector2(-8, 0)])
		map.draw_colored_polygon(pts, col)
		map.draw_string(font, p + Vector2(11, 4), "%s · %s" % [KIND_LABEL.get(ct.kind, ct.kind), ct.threat], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	# the player
	var pp := _to_px(C.lon, C.lat)
	if C.dest != null:
		var dp := _to_px(C.dest[0], C.dest[1])
		map.draw_line(pp, dp, Color(0.55, 0.85, 1.0, 0.7), 1.5)
		map.draw_circle(dp, 4, Color(0.55, 0.85, 1.0, 0.7))
	map.draw_arc(pp, ENGAGE_NM / 60.0 * zoom, 0, TAU, 32, Color(0.55, 0.85, 1.0, 0.25), 1.0)
	var tri := PackedVector2Array([pp + Vector2(0, -10), pp + Vector2(7, 8), pp + Vector2(-7, 8)])
	map.draw_colored_polygon(tri, Color(0.55, 0.85, 1.0))
	map.draw_string(font, pp + Vector2(10, -8), C.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.85, 1.0))
	# scale bar
	var nm500 := 500.0 / 60.0 * zoom
	map.draw_line(Vector2(20, vs.y - 110), Vector2(20 + nm500, vs.y - 110), Color(1, 1, 1, 0.6), 2.0)
	map.draw_string(font, Vector2(20, vs.y - 116), "500 nautical miles", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.6))
	if C.get("war_over", false):
		map.draw_string(font, Vector2(vs.x / 2 - 200, 110), "The war is over. The Pacific stays open for patrols.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UI.BRASS)


func _map_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			zoom = clampf(zoom * 1.15, 3.0, 40.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			zoom = clampf(zoom / 1.15, 3.0, 40.0)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_drag = {"start": e.position, "last": e.position, "moved": 0.0}
			else:
				if not _drag.is_empty() and _drag.moved < 6.0:
					_click(e.position)
				_drag = {}
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			var w := _from_px(e.position)
			C.dest = [w.x, w.y]
			_refresh_side()
		map.queue_redraw()
	elif e is InputEventMouseMotion and not _drag.is_empty():
		var d: Vector2 = e.position - _drag.last
		_drag.last = e.position
		_drag.moved += d.length()
		if _drag.moved >= 6.0:
			cam_lon -= d.x / zoom
			cam_lat += d.y / zoom
			map.queue_redraw()


func _click(pos: Vector2) -> void:
	# a contact under the mouse selects it; otherwise set course
	for ct in C.contacts:
		if _to_px(ct.lon, ct.lat).distance_to(pos) < 14.0:
			selected = ct.id
			_refresh_side()
			return
	var w := _from_px(pos)
	C.dest = [w.x, w.y]
	if speed_i == 0:
		speed_i = 1
	_refresh_side()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		if Game.pressed(e, "pause"):
			speed_i = 0 if speed_i > 0 else 1
			_refresh_top()
		elif Game.pressed(e, "menu"):
			_save()
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
