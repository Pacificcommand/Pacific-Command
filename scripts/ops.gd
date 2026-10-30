extends Control
## The operations map: the Pacific from Pearl Harbor to Japan, sailed freely in real time with
## time compression. Friendly and enemy groups (convoys, task forces, Tokyo Express runs,
## patrols, submarines) sail between bases and zones like the player does; when they meet they
## fight, and the player can intercept an enemy group, join a battle in progress, or sail with a
## friendly group as its escort. Ports repair and refit the ship and recruit ships for the
## player's squadron with reputation. The war follows its historical timeline, nudged by results.

const HOURS_PER_SEC := 0.35          # at speed 1: one game hour every ~3 seconds
const SPEEDS := [0.0, 1.0, 4.0, 24.0]
const ENGAGE_NM := 40.0              # close enough to open a battle
const MEET_NM := 25.0                # groups this close fight each other
const PORT_NM := 70.0
const MAX_GROUPS := 7                # per side
const KIND_LABEL := {"convoy": "Convoy", "express": "Tokyo Express", "taskforce": "Task force", "carriers": "Carrier force", "barges": "Barge traffic", "sub": "Submarine", "patrol": "Patrol"}

var C: Dictionary                     # Game.campaign
var map: Control
var cam_lon := 160.0
var cam_lat := 5.0
var zoom := 9.0                        # pixels per degree
var speed_i := 1
var selected := ""                     # group or fight id
var lbl := {}
var btn := {}
var side: VBoxContainer
var log_box: VBoxContainer
var card: Control = null
var _drag := {}
var _hour_acc := 0.0
var _ach_day := -1
var _rng := RandomNumberGenerator.new()
var _save_t := 0.0
var _side_t := 0.0
var _asked_fight := ""                 # fight id the player was already offered


func _ready() -> void:
	_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if Game.campaign.is_empty():
		Game.campaign = new_campaign(0, "pt_elco", "PT-109")
	C = Game.campaign
	_migrate()
	if Career.ship(Game.career).is_empty() or Career.ship(Game.career).type != C.ship:
		Career.take_command(Game.career, C.ship, C.name, int(C.day))
	cam_lon = C.lon; cam_lat = C.lat
	_build_ui()
	Audio.music("map")
	Audio.ambience("clear", 0.35)
	Audio.loop("fire", 0.0)
	Audio.loop("plane", 0.0)
	_apply_result()
	if not Game.last_result_letter.is_empty():
		var lt: Dictionary = Game.last_result_letter
		Game.last_result_letter = {}
		_show_card(("LETTER HOME · " if lt.kind == "letter" else "DIARY · ") + War.date_str(int(lt.day)), lt.title, lt.text, "Continue")
	speed_i = 0
	_refresh_top()
	_refresh_side()
	_log("Operations map. Click the sea to set a course. Blue: our groups; red: enemy groups our radar, aircraft or friends have found.")
	# a few groups are already at sea when the campaign opens
	if C.groups.is_empty():
		for i in 8:
			_spawn_group("us" if i % 2 == 0 else "ijn", true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ops="):
			speed_i = 3
			_test_shot(a.split("=")[1])


## Older campaign saves get the new fields.
func _migrate() -> void:
	for k in ["groups", "fights", "squadron"]:
		if not C.has(k):
			C[k] = []
	if not C.has("attached"):
		C.attached = ""
	if not C.has("intercept"):
		C.intercept = ""
	C.erase("contacts")


func _test_shot(path: String) -> void:
	var days := 0.3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = float(a.split("=")[1])
	var start_day: float = C.day
	var frames := 0
	while C.day < start_day + days and frames < 6000:
		frames += 1
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
	var seen := 0
	for g in C.groups:
		if g.side == "ijn" and g.seen >= 0.0:
			seen += 1
	print("groups ", C.groups.size(), " (enemy seen ", seen, ") fights ", C.fights.size(), " day ", C.day, " ops ", C.done_ops)
	for g in C.groups:
		print("  %s %s %s [%s] at %.1f,%.1f -> %s %s" % [g.side, g.kind, g.name, _describe(g.ships), g.lon, g.lat, _dest_name(g), g.state])
	if "--joinfight" in OS.get_cmdline_user_args():
		# test: a convoy of ours under attack right here
		var year := War.year_of(int(C.day))
		var gu := _make_group("us", "Espiritu Santo", [C.lon + 1.0, C.lat], true, year, "convoy")
		var gj := _make_group("ijn", "Rabaul", [C.lon, C.lat + 1.0], false, year, "express")
		gu.lon = C.lon; gu.lat = C.lat; gj.lon = C.lon; gj.lat = C.lat
		C.groups.append(gu); C.groups.append(gj)
		var f := {"id": "ftest", "lon": C.lon, "lat": C.lat, "us": gu.id, "ijn": gj.id, "start": C.day, "ends": C.day + 0.2}
		C.fights.append(f)
		print("joining fight: ", _describe(gu.ships), " vs ", _describe(gj.ships))
		_join_fight(f)
		return
	if "--engage" in OS.get_cmdline_user_args():
		for g in C.groups:
			if g.side == "ijn":
				C.lon = g.lon; C.lat = g.lat
				print("engaging ", g.kind, " ", _describe(g.ships))
				_engage(g)
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
	return {"day": float(start_day), "lon": b.lon, "lat": b.lat, "dest": null, "shift": 0.0, "groups": [], "fights": [], "squadron": [], "attached": "", "intercept": "",
		"done_ops": done, "ship": ship, "name": name, "log": [], "sunk_total": 0, "won": 0, "lost": 0, "next_id": 1}


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
	side.custom_minimum_size.x = 380
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


func _refresh_top() -> void:
	var h := int(fposmod(C.day, 1.0) * 24.0)
	lbl.date.text = "%s  %02d:00" % [War.date_str(int(C.day)), h]
	for i in SPEEDS.size():
		btn["sp%d" % i].set_pressed_no_signal(i == speed_i)
	var T: Dictionary = Data.TYPES[C.ship]
	var sq: String = "" if C.squadron.is_empty() else " +%d" % C.squadron.size()
	lbl.ship.text = "%s (%s)%s · %s" % [C.name, T.name, sq, _where()]
	lbl.career.text = "%s · reputation %d · %d sunk, %d won, %d lost" % [Missions.RANKS[clampi(Game.career.rank, 0, 8)], Game.career.reputation, C.sunk_total, C.won, C.lost]


func _where() -> String:
	var port := _port_here()
	if port != "":
		return "in port at %s" % port
	if C.attached != "":
		var g = _group(C.attached)
		if g != null:
			return "sailing with %s" % g.name
	var best := ""
	var bd := 1e9
	for zid in War.ZONES:
		var z: Dictionary = War.ZONES[zid]
		var d := War.dist_nm(C.lon, C.lat, z.lon, z.lat)
		if d < bd:
			bd = d; best = z.name
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
	side.add_child(UI.row([UI.button("Career", func(): add_child(CareerPanel.new())), UI.button("Encyclopedia", func(): add_child(EncyclopediaPanel.new())), UI.button("Mail (%d)" % Game.career.get("mail", []).size(), _show_mail), UI.label("%d skill point%s to spend" % [Career.skill_points_left(Game.career), "" if Career.skill_points_left(Game.career) == 1 else "s"], 12, UI.BRASS if Career.skill_points_left(Game.career) > 0 else UI.MUTED)]))
	# squadron
	if not C.squadron.is_empty():
		side.add_child(UI.wrap("Squadron: %s." % _describe(C.squadron), 350, 12, Color(0.55, 0.85, 1.0)))
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
		side.add_child(UI.button("Recruit ships for the squadron (%d reputation)" % Game.career.reputation, _recruit_menu))
	# attached to a friendly group
	if C.attached != "":
		var ag = _group(C.attached)
		if ag != null:
			side.add_child(UI.wrap("Sailing with %s (%s) toward %s. You fight if they are attacked." % [ag.name, _describe(ag.ships), _dest_name(ag)], 350, 12, Color(0.55, 0.85, 1.0)))
			side.add_child(UI.button("Detach and sail on your own", func(): C.attached = ""; _log("Detached from %s." % ag.name); _refresh_side()))
	# the selected thing
	var g = _group(selected)
	var f = _fight(selected)
	if f != null:
		var gu = _group(f.us)
		var gj = _group(f.ijn)
		var d: float = War.dist_nm(C.lon, C.lat, f.lon, f.lat)
		side.add_child(UI.label("Battle in progress", 18))
		side.add_child(UI.wrap("%s (%s) is engaging %s (%s). %.0f nm away; the action will last about %d more hour%s." % [gu.name if gu else "Our ships", _describe(gu.ships) if gu else "?", gj.name if gj else "the enemy", _describe(gj.ships) if gj else "?", d, int(maxf(1.0, (f.ends - C.day) * 24.0)), "" if int((f.ends - C.day) * 24.0) == 1 else "s"], 350, 12))
		var go := UI.button("Make for the battle", func(): C.attached = ""; C.intercept = ""; C.dest = [f.lon, f.lat]; if speed_i == 0: speed_i = 1; _refresh_side())
		var join := UI.button("Join the battle" if d < ENGAGE_NM else "Join (%.0f nm to go)" % (d - ENGAGE_NM), func(): _join_fight(f))
		join.disabled = d > ENGAGE_NM
		side.add_child(UI.row([go, join]))
	elif g != null:
		var d2: float = War.dist_nm(C.lon, C.lat, g.lon, g.lat)
		if g.side == "us":
			side.add_child(UI.label("%s · %s" % [g.name, KIND_LABEL.get(g.kind, g.kind)], 18))
			side.add_child(UI.wrap("%s · %.0f nm away · %d kn, bound for %s%s." % [_describe(g.ships), d2, int(g.kn), _dest_name(g), " · in action" if g.state == "fight" else ""], 350, 12))
			var go2 := UI.button("Set course to them", func(): C.attached = ""; C.intercept = g.id; _set_dest(g.lon, g.lat); _refresh_side())
			var att := UI.button("Sail with them" if d2 < ENGAGE_NM else "Sail with them (%.0f nm to go)" % (d2 - ENGAGE_NM), func(): _attach(g))
			att.disabled = d2 > ENGAGE_NM or C.attached == g.id
			side.add_child(UI.row([go2, att]))
		else:
			var age: float = (C.day - g.seen) * 24.0
			side.add_child(UI.label("Enemy %s" % _kind_lc(g.kind), 18))
			var where: String = "%.0f nm away" % d2 if age < 3.0 else "last seen %d h ago, %.0f nm from the position" % [int(age), d2]
			side.add_child(UI.wrap("%s · threat %s · %s · course %s at about %d kn." % [_describe(g.ships), Missions.threat(_types(g.ships), "clear")[1], where, U.deg3(_course(g)), int(g.kn)], 350, 12))
			var icpt := UI.button("Intercept", func(): C.attached = ""; C.intercept = g.id; _set_dest(g.lon, g.lat); _refresh_side())
			var eng := UI.button("Engage" if d2 < ENGAGE_NM else "Engage (%.0f nm to go)" % (d2 - ENGAGE_NM), func(): _engage(g))
			eng.disabled = d2 > ENGAGE_NM or age > 6.0
			side.add_child(UI.row([icpt, eng]))
	else:
		side.add_child(UI.wrap("Click a group for details. Blue circles are our convoys, patrols and task forces; red diamonds are enemy groups we have found (hollow when the report is old). Crossed lines mark a battle you can sail to and join. Sail within %d nm to engage or join." % int(ENGAGE_NM), 350, 12, UI.MUTED))
	# nearby list
	side.add_child(UI.label("Groups in range", 11, UI.BRASS))
	var near: Array = []
	for g2 in C.groups:
		if g2.side == "us" or g2.seen >= 0.0:
			near.append(g2)
	near.sort_custom(func(a, b): return War.dist_nm(C.lon, C.lat, a.lon, a.lat) < War.dist_nm(C.lon, C.lat, b.lon, b.lat))
	var shown := 0
	for g3 in near:
		if shown >= 7:
			break
		shown += 1
		var d3: float = War.dist_nm(C.lon, C.lat, g3.lon, g3.lat)
		var txt: String = "%s%s · %d ships · %.0f nm" % ["" if g3.side == "us" else "Enemy ", g3.name if g3.side == "us" else _kind_lc(g3.kind), g3.ships.size(), d3]
		var b := UI.button(txt, (func(id): selected = id; _refresh_side()).bind(g3.id))
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0) if g3.side == "us" else Color(0.95, 0.45, 0.4))
		side.add_child(b)
	for f2 in C.fights:
		var b2 := UI.button("Battle: %s vs %s · %.0f nm" % [_gname(f2.us), _gname(f2.ijn), War.dist_nm(C.lon, C.lat, f2.lon, f2.lat)], (func(id): selected = id; _refresh_side()).bind(f2.id))
		b2.add_theme_font_size_override("font_size", 12)
		b2.add_theme_color_override("font_color", UI.BRASS)
		side.add_child(b2)
	if near.is_empty():
		side.add_child(UI.label("Nothing reported nearby.", 12, UI.MUTED))


## "Tokyo Express run" / "convoy" ... for the middle of a sentence.
static func _kind_lc(kind: String) -> String:
	match kind:
		"express": return "Tokyo Express run"
		"convoy": return "convoy"
		"taskforce": return "task force"
		"carriers": return "carrier force"
		"barges": return "barge column"
		"sub": return "submarine"
		"patrol": return "patrol"
	return kind


func _gname(gid: String) -> String:
	var g = _group(gid)
	if g == null:
		return "?"
	return g.name if g.side == "us" else "enemy %s" % _kind_lc(g.kind)


func _dest_name(g: Dictionary) -> String:
	if g.dest == null:
		return "nowhere in particular"
	var best := ""
	var bd := 60.0
	for nm in War.BASES:
		var b: Dictionary = War.BASES[nm]
		var d := War.dist_nm(g.dest[0], g.dest[1], b.lon, b.lat)
		if d < bd:
			bd = d; best = nm
	if best != "":
		return best
	for zid in War.ZONES:
		var z: Dictionary = War.ZONES[zid]
		if War.dist_nm(g.dest[0], g.dest[1], z.lon, z.lat) < z.r:
			return z.name
	return "the open sea"


func _set_dest(lon: float, lat: float) -> void:
	C.dest = [lon, lat]
	if speed_i == 0:
		speed_i = 1


func _attach(g: Dictionary) -> void:
	C.attached = g.id
	C.intercept = ""
	C.dest = null
	C.lon = g.lon; C.lat = g.lat
	_log("Joined %s as escort. Bound for %s." % [g.name, _dest_name(g)])
	_refresh_side()


## "2 Fletcher, 1 Cleveland" from a list of [type, name] ships.
static func _describe(ships: Array) -> String:
	var counts := {}
	var order := []
	for sh in ships:
		var nm: String = Data.TYPES[sh[0]].name.replace(" class", "").replace("Daihatsu landing barge", "barge").replace("Armed Daihatsu (gun barge)", "gun barge").replace("Cargo ship (maru)", "cargo ship").replace("Oil tanker (maru)", "tanker").replace(" destroyer escort", "").replace(" submarine", "").replace(" escort carrier", "").replace(" light carrier", "")
		if not counts.has(nm):
			order.append(nm)
		counts[nm] = counts.get(nm, 0) + 1
	var parts := []
	for k in order:
		parts.append("%d %s" % [counts[k], k])
	return ", ".join(parts)


static func _types(ships: Array) -> Array:
	var out := []
	for sh in ships:
		out.append(sh[0])
	return out


func _course(g: Dictionary) -> float:
	if g.dest == null:
		return 0.0
	var dx: float = (g.dest[0] - g.lon) * cos(deg_to_rad(g.lat))
	var dy: float = g.dest[1] - g.lat
	return fposmod(atan2(dx, dy), TAU)


func _show_mail() -> void:
	var mail: Array = Game.career.get("mail", [])
	if mail.is_empty():
		_log("No letters yet. They arrive after battles.")
		return
	var lt: Dictionary = mail[mail.size() - 1]
	_show_card(("LETTER HOME · " if lt.kind == "letter" else "DIARY · ") + War.date_str(int(lt.day)), lt.title, lt.text, "Close")


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
	_move_groups(hours)
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
	_side_t += delta
	if _side_t > 2.0:
		_side_t = 0.0
		_refresh_side()
	_refresh_top()
	map.queue_redraw()


func _sail(hours: float) -> void:
	# riding with a friendly group
	if C.attached != "":
		var ag = _group(C.attached)
		if ag == null:
			C.attached = ""
			_log("The group you were sailing with has made port; you are on your own.")
		else:
			C.lon = ag.lon; C.lat = ag.lat
			C.dest = null
			return
	# chasing a group: the course follows it
	if C.intercept != "":
		var tg = _group(C.intercept)
		if tg == null:
			C.intercept = ""
		else:
			C.dest = [tg.lon, tg.lat]
	if C.dest == null:
		return
	var T: Dictionary = Data.TYPES[C.ship]
	var kn: float = _squadron_speed()
	var d := War.dist_nm(C.lon, C.lat, C.dest[0], C.dest[1])
	var step := kn * hours
	if d <= step:
		C.lon = C.dest[0]; C.lat = C.dest[1]
		if C.intercept == "":
			C.dest = null
			speed_i = mini(speed_i, 1)
			_log("Arrived. %s." % _where().capitalize())
			_refresh_side()
		return
	var k := step / d
	C.lon += (C.dest[0] - C.lon) * k
	C.lat += (C.dest[1] - C.lat) * k


## Cruising speed of the player and squadron: the slowest ship sets it.
func _squadron_speed() -> float:
	var kn: float = Data.TYPES[C.ship].max_kn
	for sh in C.squadron:
		kn = minf(kn, float(Data.TYPES[sh[0]].max_kn))
	return kn * 0.65


func _move_groups(hours: float) -> void:
	for g in C.groups:
		if g.state == "fight" or g.dest == null:
			continue
		var d: float = War.dist_nm(g.lon, g.lat, g.dest[0], g.dest[1])
		var step: float = float(g.kn) * hours
		if d <= step:
			g.lon = g.dest[0]; g.lat = g.dest[1]
			g.dest = null
			g.arrived = true
		else:
			var k: float = step / d
			g.lon += (g.dest[0] - g.lon) * k
			g.lat += (g.dest[1] - g.lat) * k


func _tick_hour() -> void:
	if int(C.day) != _ach_day:
		_ach_day = int(C.day)
		SteamHook.check_day(_ach_day)
	# groups that have arrived go into port (or turn for home from a patrol area)
	var keep := []
	for g in C.groups:
		if g.get("arrived", false):
			g.arrived = false
			if g.get("leg", 0) == 0 and g.get("home", "") != "":
				var hb: Dictionary = War.BASES[g.home]
				g.leg = 1
				g.dest = [hb.lon, hb.lat]
				g.kn = g.kn
				if g.side == "us" and g.kind != "sub":
					_log("%s has reached %s and turns for %s." % [g.name, _dest_name({"dest": [g.lon, g.lat]}), g.home])
				keep.append(g)
				continue
			if g.id == C.attached:
				C.attached = ""
				_log("%s has made port at %s. You are detached with thanks." % [g.name, _dest_name({"dest": [g.lon, g.lat]})])
			if g.id == selected:
				selected = ""
			if g.id == C.intercept:
				C.intercept = ""
			continue
		keep.append(g)
	C.groups = keep
	# new groups put to sea
	var n_us := 0
	var n_ijn := 0
	for g in C.groups:
		if g.side == "us": n_us += 1
		else: n_ijn += 1
	if n_us < MAX_GROUPS and _rng.randf() < 0.10:
		_spawn_group("us", false)
	if n_ijn < MAX_GROUPS and _rng.randf() < 0.10 and not C.get("war_over", false):
		_spawn_group("ijn", false)
	_detect()
	_hunt()
	_meet()
	_resolve_fights()


func _tick_day() -> void:
	pass


# ---------------------------------------------------------------- groups

const PHONETIC := ["Able", "Baker", "Charlie", "Dog", "Easy", "Fox", "George", "How", "Item", "Jig", "King", "Love", "Mike", "Nan", "Oboe", "Peter", "Queen", "Roger", "Sugar", "Tare", "Uncle", "Victor", "William", "X-ray", "Yoke", "Zebra"]

## A name for a new group that no group at sea is using.
func _group_name(side: String, kind: String, ships: Array) -> String:
	var used := []
	for g in C.groups:
		used.append(g.name)
	for tries in 40:
		var nm := ""
		var w: String = PHONETIC[_rng.randi() % PHONETIC.size()]
		if side == "us":
			match kind:
				"convoy": nm = "Convoy %s" % w
				"patrol": nm = "DesDiv %d" % (11 + _rng.randi() % 80)
				"taskforce": nm = "Task Group %s" % w
				"carriers": nm = "Task Force %d" % (11 + _rng.randi() % 60)
				"sub":
					nm = ships[0][1]
					if used.has(nm):
						var alt := ["USS Flasher", "USS Barb", "USS Tang", "USS Rasher", "USS Bowfin", "USS Tautog", "USS Seawolf", "USS Snook", "USS Trout", "USS Gudgeon"]
						nm = alt[_rng.randi() % alt.size()]
						ships[0][1] = nm
				_: nm = "Task Unit %s" % w
		else:
			match kind:
				"convoy": nm = "Transport Unit %d" % (1 + _rng.randi() % 20)
				"express": nm = "Reinforcement Unit %d" % (1 + _rng.randi() % 12)
				"taskforce": nm = ["Striking Force", "Diversion Force", "Advance Force", "Guard Force", "Bombardment Unit"][_rng.randi() % 5]
				"carriers": nm = "Carrier Division %d" % (1 + _rng.randi() % 5)
				"sub":
					nm = ships[0][1]
					if used.has(nm):
						nm = "I-%d" % (15 + _rng.randi() % 160)
						ships[0][1] = nm
				"barges": nm = "Barge convoy %d" % (1 + _rng.randi() % 30)
				_: nm = "Escort Unit %d" % (1 + _rng.randi() % 20)
		if not used.has(nm):
			return nm
	return "%s group" % side.to_upper()

func _active_bases(side: String) -> Array:
	var out := []
	for nm in War.BASES:
		var b: Dictionary = War.BASES[nm]
		if b.side != side:
			continue
		if side == "us":
			if b.from >= 0 and C.day >= b.from:
				out.append(nm)
		else:
			if War.owner(b.zone, C.day, C.shift) == "ijn":
				out.append(nm)
	return out


## Zones where the war is being fought now: the ones that change hands within about a year of
## today, plus whatever is unusually active. Both sides send their groups there.
func _front_zones() -> Array:
	var out := []
	for zid in War.ZONES:
		var z: Dictionary = War.ZONES[zid]
		var us: int = z.us
		var w := 0.0
		if us > 0:
			var dt: float = (us - C.shift) - C.day
			if dt > -200.0 and dt < 520.0:
				w = 1.0 - absf(dt - 60.0) / 500.0
		if War.activity(zid, C.day, C.shift) >= 0.8 and zid != "home":
			w = maxf(w, 0.5)
		if w > 0.0:
			for i in int(w * 6.0 + 1.0):
				out.append(zid)
	if out.is_empty():
		out.append("solomons" if C.day < 700 else ("philippines" if C.day < 1150 else "ryukyus"))
	return out


## The two active bases of a side nearest a point; groups sail from there.
func _bases_near(side: String, lon: float, lat: float) -> Array:
	var bases := _active_bases(side)
	bases.sort_custom(func(a, b): return War.dist_nm(lon, lat, War.BASES[a].lon, War.BASES[a].lat) < War.dist_nm(lon, lat, War.BASES[b].lon, War.BASES[b].lat))
	return bases.slice(0, mini(2, bases.size()))


## Put a new group to sea. `anywhere` places it along its route (for the start of a campaign).
func _spawn_group(side: String, anywhere: bool) -> void:
	var bases := _active_bases(side)
	if bases.is_empty():
		return
	var year := War.year_of(int(C.day))
	var kind := _pick_kind(side, year)
	var fronts := _front_zones()
	var zid: String = fronts[_rng.randi() % fronts.size()]
	var z: Dictionary = War.ZONES[zid]
	var near := _bases_near(side, z.lon, z.lat)
	var home: String = near[_rng.randi() % near.size()]
	var hb: Dictionary = War.BASES[home]
	# destination: a point in the front zone, or (for convoys) a base near the front
	var dest := []
	var to_base: bool = kind in ["convoy", "sub"] and _rng.randf() < 0.5 and near.size() > 1
	var dest_name := ""
	if to_base:
		var other: String = near[0] if near[0] != home else near[1]
		dest = [War.BASES[other].lon, War.BASES[other].lat]
		dest_name = other
	else:
		var a := _rng.randf() * TAU
		var r: float = z.r * _rng.randf_range(0.1, 0.7) / 60.0
		dest = [z.lon + cos(a) * r / cos(deg_to_rad(z.lat)), z.lat + sin(a) * r]
		# convoys and barges do not sail into waters the other side holds
		if kind in ["convoy", "barges"] and War.owner(zid, C.day, C.shift) != side:
			if near.size() > 1:
				var other2: String = near[0] if near[0] != home else near[1]
				dest = [War.BASES[other2].lon, War.BASES[other2].lat]
				dest_name = other2
				to_base = true
			else:
				kind = "express" if side == "ijn" else "patrol"
	if War.dist_nm(hb.lon, hb.lat, dest[0], dest[1]) > 2600.0 or War.dist_nm(hb.lon, hb.lat, dest[0], dest[1]) < 30.0:
		return
	var g := _make_group(side, home, dest, to_base, year, kind)
	if g.is_empty():
		return
	if anywhere:
		var k := _rng.randf_range(0.1, 0.8)
		g.lon = hb.lon + (dest[0] - hb.lon) * k
		g.lat = hb.lat + (dest[1] - hb.lat) * k
	C.groups.append(g)
	if side == "us":
		_log("%s has sailed from %s (%s), bound for %s." % [g.name, home, _describe(g.ships), dest_name if dest_name != "" else _dest_name(g)])


func _pick_kind(side: String, year: int) -> String:
	var pool: Array
	if side == "us":
		pool = ["convoy", "convoy", "convoy", "patrol", "patrol", "taskforce", "sub"]
		if year >= 1943:
			pool += ["taskforce", "carriers"]
	else:
		pool = ["convoy", "convoy", "express", "express", "taskforce", "sub", "barges"]
		if year <= 1944:
			pool += ["carriers"]
		if year >= 1944:
			pool += ["convoy"]
	return pool[_rng.randi() % pool.size()]


func _make_group(side: String, home: String, dest: Array, to_base: bool, year: int, kind: String) -> Dictionary:
	var hb: Dictionary = War.BASES[home]
	var ships := []
	var kn := 12.0
	if kind == "barges" and (to_base or War.dist_nm(hb.lon, hb.lat, dest[0], dest[1]) > 500.0):
		kind = "express"
	if kind == "express" and side == "ijn" and to_base:
		kind = "convoy"
	var act := 0.5
	for zid in War.ZONES:
		if War.dist_nm(dest[0], dest[1], War.ZONES[zid].lon, War.ZONES[zid].lat) < War.ZONES[zid].r:
			act = maxf(act, War.activity(zid, C.day, C.shift))
	var strength := clampf(act * _rng.randf_range(0.6, 1.6) + (0.4 if year >= 1943 else 0.0), 0.3, 2.5)
	ships = _ships_for(side, kind, strength, year)
	if ships.is_empty():
		return {}
	kn = 99.0
	for sh in ships:
		kn = minf(kn, float(Data.TYPES[sh[0]].max_kn))
	kn *= 0.6 if kind in ["convoy", "barges"] else 0.7
	if kind == "sub":
		kn = 11.0
	var nm := _group_name(side, kind, ships)
	var id := "g%d" % int(C.next_id)
	C.next_id = int(C.next_id) + 1
	return {"id": id, "side": side, "kind": kind, "name": nm, "ships": ships, "lon": hb.lon, "lat": hb.lat, "dest": dest, "kn": kn, "home": home, "leg": 1 if to_base else 0,
		"state": "sail", "seen": -1.0, "seen_lon": 0.0, "seen_lat": 0.0, "fight": "", "born": C.day}


const US_DD_NAMES := ["USS Nicholas", "USS Radford", "USS De Haven", "USS Strong", "USS Chevalier", "USS Taylor", "USS Jenkins", "USS La Vallette", "USS Waller", "USS Saufley", "USS Philip", "USS Renshaw", "USS Conway", "USS Cony", "USS Eaton", "USS Foote", "USS Spence", "USS Thatcher", "USS Dyson", "USS Claxton", "USS Stanly", "USS Pringle", "USS Sigourney", "USS Aulick"]
const US_CL_NAMES := ["USS Honolulu", "USS St. Louis", "USS Nashville", "USS Phoenix", "USS Montpelier", "USS Denver", "USS Columbia", "USS Santa Fe", "USS Birmingham", "USS Mobile"]
const US_CA_NAMES := ["USS Salt Lake City", "USS Pensacola", "USS Louisville", "USS Portland", "USS Indianapolis", "USS Wichita", "USS Canberra", "USS Quincy", "USS Pittsburgh"]
const MARU_NAMES := ["Kinai Maru", "Nissho Maru", "Taiyo Maru", "Hokko Maru", "Toyo Maru", "Yamazuki Maru", "Sado Maru", "Brisbane Maru", "Arizona Maru", "Hirokawa Maru", "Kinugawa Maru", "Azumasan Maru"]
const LIBERTY_NAMES := ["SS John Adams", "SS Alchiba", "SS Fomalhaut", "SS Bellatrix", "SS Betelgeuse", "SS Libra", "SS Zeilin", "SS Crescent City", "SS President Jackson", "SS Hunter Liggett", "SS Neville", "SS Heywood"]

func _pick_names(names: Array, n: int) -> Array:
	var pool := names.duplicate()
	var out := []
	for i in n:
		if pool.is_empty():
			pool = names.duplicate()
		var k := _rng.randi() % pool.size()
		out.append(pool[k])
		pool.remove_at(k)
	return out


## The ships of a group: [type, name] pairs, by side, kind and strength.
func _ships_for(side: String, kind: String, strength: float, year: int) -> Array:
	var out := []
	if side == "us":
		match kind:
			"convoy":
				var n := clampi(int(2 + strength * 2), 2, 5)
				var ln := _pick_names(LIBERTY_NAMES, n)
				for i in n:
					out.append(["liberty", ln[i]])
				var ne := clampi(int(1 + strength), 1, 3)
				var dn := _pick_names(US_DD_NAMES, ne)
				for i in ne:
					out.append([("buckley" if year >= 1943 and _rng.randf() < 0.6 else ("fletcher" if year >= 1942 else "benson")), dn[i]])
			"patrol":
				var n2 := clampi(int(2 + strength * 1.5), 2, 4)
				var dn2 := _pick_names(US_DD_NAMES, n2)
				for i in n2:
					out.append([("fletcher" if year >= 1942 else ("benson" if _rng.randf() < 0.5 else "mahan")), dn2[i]])
			"taskforce":
				var ncl := clampi(int(strength * 1.5), 1, 3)
				var cn := _pick_names(US_CL_NAMES, ncl)
				for i in ncl:
					out.append([("cleveland" if year >= 1943 else "brooklyn"), cn[i]])
				if strength > 1.3:
					out.append([("new_orleans" if year <= 1942 else "baltimore"), _pick_names(US_CA_NAMES, 1)[0]])
				if strength > 1.9 and year >= 1943:
					out.append([("south_dakota" if year <= 1943 else "iowa"), ["USS Massachusetts", "USS Alabama", "USS New Jersey"][_rng.randi() % 3]])
				var nd := clampi(int(2 + strength * 2), 2, 5)
				var dn3 := _pick_names(US_DD_NAMES, nd)
				for i in nd:
					out.append(["fletcher" if year >= 1942 else "benson", dn3[i]])
			"carriers":
				out.append([("essex" if year >= 1943 else "yorktown"), ["USS Essex", "USS Intrepid", "USS Enterprise", "USS Hornet"][_rng.randi() % 4]])
				if strength > 1.2 and year >= 1943:
					out.append(["independence", ["USS Cowpens", "USS Monterey"][_rng.randi() % 2]])
				out.append(["cleveland" if year >= 1943 else "atlanta", _pick_names(US_CL_NAMES, 1)[0]])
				var nd2 := clampi(int(3 + strength), 3, 5)
				var dn4 := _pick_names(US_DD_NAMES, nd2)
				for i in nd2:
					out.append(["fletcher", dn4[i]])
			"sub":
				out.append(["gato", ["USS Wahoo", "USS Flasher", "USS Silversides", "USS Growler", "USS Trigger", "USS Harder"][_rng.randi() % 6]])
	else:
		var dd_names := ["Amagiri", "Hatsuyuki", "Yukikaze", "Hamakaze", "Shigure", "Ayanami", "Uranami", "Nowaki", "Akizuki", "Suzutsuki", "Kagero", "Fubuki", "Shirayuki", "Yudachi", "Murasame", "Harusame", "Samidare", "Kawakaze", "Umikaze", "Asagumo"]
		match kind:
			"convoy":
				var n := clampi(int(2 + strength * 2), 2, 5)
				var mn := _pick_names(MARU_NAMES, n)
				for i in n:
					out.append([("tanker_maru" if i == 1 else "cargo_maru"), mn[i]])
				out.append([("kagero" if strength > 0.7 else "subchaser"), ("Shigure" if strength > 0.7 else "CH-%d" % (12 + _rng.randi() % 40))])
				if strength > 1.1:
					out.append(["subchaser", "CH-%d" % (12 + _rng.randi() % 40)])
			"express":
				var n2 := clampi(int(2 + strength * 3), 2, 6)
				var dn := _pick_names(dd_names, n2)
				for i in n2:
					var tid := "kagero" if _rng.randf() < 0.5 else "fubuki"
					if year >= 1943 and _rng.randf() < 0.2:
						tid = "akizuki"
					out.append([tid, dn[i]])
				if strength > 1.2:
					out.insert(0, ["nagara", ["Jintsu", "Sendai", "Nagara", "Yura"][_rng.randi() % 4]])
			"taskforce":
				var cas := ["takao", "myoko", "mogami", "tone"]
				var ca_names := ["Atago", "Haguro", "Suzuya", "Chikuma", "Nachi", "Chokai", "Maya", "Kumano"]
				if strength > 1.5:
					var k := mini(3, int(strength - 1.0))
					out.append([["kongo", "fuso", "nagato", "yamato"][k], ["Kongo", "Fuso", "Nagato", "Yamato"][k]])
				var nca := clampi(int(strength * 2), 1, 4)
				var cn := _pick_names(ca_names, nca)
				for i in nca:
					out.append([cas[_rng.randi() % cas.size()], cn[i]])
				var nd := clampi(2 + int(strength), 2, 5)
				var dn2 := _pick_names(dd_names, nd)
				for i in nd:
					out.append(["kagero" if _rng.randf() < 0.5 else "fubuki", dn2[i]])
			"carriers":
				out.append([("shokaku" if year <= 1944 else "zuiho"), ["Shokaku", "Zuikaku"][_rng.randi() % 2]])
				if strength > 0.8:
					out.append([("hiryu" if year <= 1942 else "zuiho"), "Hiryu" if year <= 1942 else ["Zuiho", "Chitose"][_rng.randi() % 2]])
				out.append(["tone", "Tone" if _rng.randf() < 0.5 else "Chikuma"])
				var dn3 := _pick_names(dd_names, 3)
				for i in 3:
					out.append(["kagero", dn3[i]])
			"sub":
				out.append(["i_boat", "I-%d" % (15 + _rng.randi() % 160)])
			"barges":
				var n3 := clampi(int(4 + strength * 3), 4, 8)
				for i in n3:
					out.append([("daihatsu_gun" if (i == 0 or i == n3 - 1) else "daihatsu"), "Barge %d" % (i + 1)])
	return out


func _group(id: String):
	if id == "":
		return null
	for g in C.groups:
		if g.id == id:
			return g
	return null


func _fight(id: String):
	if id == "":
		return null
	for f in C.fights:
		if f.id == id:
			return f
	return null


## How far (nm) the player's ship sees the enemy on the map: radar, lookouts and the time of day.
func _detect_range() -> float:
	var T: Dictionary = Data.TYPES[C.ship]
	var r := 45.0
	if T.get("radar", 0.0) > 0.0:
		r = 70.0
	if T.get("cls", "") in ["cv", "cvl", "cve"]:
		r = 160.0          # search planes
	if T.get("cls", "") in ["bb", "ca"] and War.year_of(int(C.day)) >= 1942:
		r = 110.0          # floatplanes
	for sh in C.squadron:
		if Data.TYPES[sh[0]].get("cls", "") in ["cv", "cvl", "cve"]:
			r = maxf(r, 160.0)
	r *= 1.0 + 0.5 * Career.mod("radar")
	var hour := fposmod(C.day, 1.0) * 24.0
	if hour < 6.0 or hour > 18.0:
		r *= 0.6
	return r


## Enemy groups become known when our radar, our friends or shore-based aircraft find them.
func _detect() -> void:
	var pr := _detect_range()
	var hour := fposmod(C.day, 1.0) * 24.0
	var day := hour >= 6.0 and hour <= 18.0
	for g in C.groups:
		if g.side != "ijn":
			continue
		var sub: bool = g.kind == "sub"
		var found := false
		var d: float = War.dist_nm(C.lon, C.lat, g.lon, g.lat)
		if d < pr * (0.4 if sub else 1.0):
			found = true
		if not found:
			for u in C.groups:
				if u.side == "us" and War.dist_nm(u.lon, u.lat, g.lon, g.lat) < (60.0 if not sub else 20.0):
					found = true
					break
		if not found and day and not sub:
			# air search from our bases
			for nm in _active_bases("us"):
				var b: Dictionary = War.BASES[nm]
				if War.dist_nm(b.lon, b.lat, g.lon, g.lat) < 400.0 and _rng.randf() < 0.2:
					found = true
					break
		if not found and not sub:
			# coastwatchers and patrol planes in the contested zones
			for zid in War.ZONES:
				var z: Dictionary = War.ZONES[zid]
				if War.activity(zid, C.day, C.shift) >= 0.6 and War.dist_nm(z.lon, z.lat, g.lon, g.lat) < z.r and _rng.randf() < (0.12 if day else 0.05):
					found = true
					break
		if found:
			var fresh: bool = g.seen < 0.0 or C.day - g.seen > 0.5
			g.seen = C.day
			g.seen_lon = g.lon; g.seen_lat = g.lat
			if fresh and d < 600.0:
				_log("Contact: enemy %s, %s, %.0f nm %s of us." % [_kind_lc(g.kind), _describe(g.ships), d, _compass(C.lon, C.lat, g.lon, g.lat)])
				Audio.ui("radio", 0.5, "Radio")


func _compass(lon1: float, lat1: float, lon2: float, lat2: float) -> String:
	var dx := (lon2 - lon1) * cos(deg_to_rad(lat1))
	var dy := lat2 - lat1
	var a := fposmod(rad_to_deg(atan2(dx, dy)), 360.0)
	return ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][int(round(a / 45.0)) % 8]


## Warships hunt what they can see: our task forces and patrols go for enemy groups nearby,
## Japanese raiders go for our convoys.
func _hunt() -> void:
	for g in C.groups:
		if g.state != "sail" or g.kind in ["convoy", "barges", "sub", "carriers"]:
			continue
		var best = null
		var bd := 150.0
		for o in C.groups:
			if o.side == g.side or o.state != "sail" or o.kind == "sub":
				continue
			if g.side == "us" and o.seen < 0.0:
				continue
			if g.side == "ijn" and not (o.kind in ["convoy", "patrol"]):
				continue
			# pick a fight they can win
			if Missions.group_strength(o.ships) > Missions.group_strength(g.ships) * 1.3:
				continue
			var d: float = War.dist_nm(g.lon, g.lat, o.lon, o.lat)
			if d < bd:
				bd = d; best = o
		if best != null:
			if not g.has("orig_dest"):
				g.orig_dest = g.dest
			g.dest = [best.lon, best.lat]
			g.kn = maxf(g.kn, 20.0)
		elif g.has("orig_dest"):
			g.dest = g.orig_dest
			g.erase("orig_dest")


## Groups of opposite sides within reach fight.
func _meet() -> void:
	for g in C.groups:
		if g.side != "us" or g.state != "sail":
			continue
		for o in C.groups:
			if o.side != "ijn" or o.state != "sail":
				continue
			if g.kind == "sub" and o.kind == "sub":
				continue
			if C.day < g.get("truce", 0.0) or C.day < o.get("truce", 0.0):
				continue
			var d: float = War.dist_nm(g.lon, g.lat, o.lon, o.lat)
			if d > MEET_NM:
				continue
			# submarines only strike at convoys and task forces, and hide otherwise
			if (g.kind == "sub" or o.kind == "sub") and _rng.randf() < 0.5:
				continue
			var f := {"id": "f%d" % int(C.next_id), "lon": (g.lon + o.lon) * 0.5, "lat": (g.lat + o.lat) * 0.5, "us": g.id, "ijn": o.id, "start": C.day, "ends": C.day + _rng.randf_range(2.0, 5.0) / 24.0}
			C.next_id = int(C.next_id) + 1
			C.fights.append(f)
			g.state = "fight"; o.state = "fight"
			g.fight = f.id; o.fight = f.id
			o.seen = C.day; o.seen_lon = o.lon; o.seen_lat = o.lat
			var pd: float = War.dist_nm(C.lon, C.lat, f.lon, f.lat)
			_log("Radio: %s is in action with enemy %s (%s), %.0f nm %s of us." % [g.name, _kind_lc(o.kind), _describe(o.ships), pd, _compass(C.lon, C.lat, f.lon, f.lat)])
			Audio.ui("radio", 0.6, "Radio")
			if C.attached == g.id:
				_offer_fight(f, true)
			elif pd < ENGAGE_NM * 2.5 and _asked_fight != f.id:
				_asked_fight = f.id
				_offer_fight(f, false)
			break


## A battle the player did not join is decided by weight of metal, with luck.
func _resolve_fights() -> void:
	var keep := []
	for f in C.fights:
		if C.day < f.ends:
			keep.append(f)
			continue
		var gu = _group(f.us)
		var gj = _group(f.ijn)
		if gu == null or gj == null:
			continue
		var su := Missions.group_strength(gu.ships)
		var sj := Missions.group_strength(gj.ships)
		var hour: float = fposmod(f.start, 1.0) * 24.0
		var night := hour < 5.5 or hour > 18.5
		# the Japanese were better at night until 1943; radar turned it round
		var year := War.year_of(int(C.day))
		if night and year <= 1942:
			sj *= 1.4
		elif night and year >= 1943:
			su *= 1.2
		var lost_us := _losses(gu, sj / maxf(0.5, su + sj))
		var lost_jp := _losses(gj, su / maxf(0.5, su + sj))
		var txt: String = "Radio: %s broke off action with the enemy %s." % [gu.name, _kind_lc(gj.kind)]
		if not lost_jp.is_empty():
			txt += " Enemy ships sunk: %s." % ", ".join(lost_jp)
		if not lost_us.is_empty():
			txt += " We lost %s." % ", ".join(lost_us)
		_log(txt)
		C.shift += 0.5 * lost_jp.size() - 0.5 * lost_us.size()
		for g in [gu, gj]:
			g.state = "sail"
			g.fight = ""
			g.truce = C.day + 0.6     # they have lost touch; no second round for a while
			if g.has("orig_dest"):
				g.dest = g.orig_dest
				g.erase("orig_dest")
	C.fights = keep
	C.groups = C.groups.filter(func(g): return not g.ships.is_empty())
	if C.attached != "" and _group(C.attached) == null:
		C.attached = ""


## Remove sunk ships from a group; p is the chance each ship is lost (scaled by its size).
func _losses(g: Dictionary, p: float) -> Array:
	var lost := []
	var keep := []
	for sh in g.ships:
		var T: Dictionary = Data.TYPES[sh[0]]
		var tough: float = clampf(float(T.get("displacement", 2000.0)) / 12000.0, 0.0, 0.7)
		if _rng.randf() < p * 0.45 * (1.0 - tough):
			lost.append(sh[1])
		else:
			keep.append(sh)
	g.ships = keep
	return lost


## A battle has started near the player: offer to join.
func _offer_fight(f: Dictionary, attached: bool) -> void:
	var gu = _group(f.us)
	var gj = _group(f.ijn)
	speed_i = 0
	_refresh_top()
	card = Control.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(UI.backdrop(0.45))
	var p := UI.panel(22)
	p.custom_minimum_size.x = 560
	var v := UI.column(8)
	v.add_child(UI.label("RADIO · %s" % War.date_str(int(C.day)), 11, UI.BRASS))
	v.add_child(UI.label("%s under attack" % gu.name if attached else "Action nearby", 26))
	var d: float = War.dist_nm(C.lon, C.lat, f.lon, f.lat)
	var th := Missions.threat(_types(gj.ships), "clear")
	v.add_child(UI.wrap("%s (%s) %s enemy %s: %s. Threat %s.%s" % [gu.name, _describe(gu.ships), "is being attacked by" if gj.kind in ["taskforce", "express", "sub", "carriers"] else "has engaged", _kind_lc(gj.kind), _describe(gj.ships), th[1], "" if attached else " The action is %.0f nm away; it will last a few hours." % d], 520))
	var row := UI.row([])
	if attached or d < ENGAGE_NM:
		row.add_child(UI.big_button("Fight", func(): _close_card(); _join_fight(f)))
	else:
		row.add_child(UI.big_button("Make for the battle", func(): _close_card(); C.attached = ""; C.intercept = ""; _set_dest(f.lon, f.lat); selected = f.id; _refresh_side()))
	row.add_child(UI.big_button("Stand off" if attached else "Carry on", func():
		_close_card()
		if attached:
			C.attached = ""
			_log("Stood off from the action; detached from %s." % gu.name)
			_refresh_side()))
	v.add_child(row)
	p.add_child(v)
	card.add_child(p)
	UI.center(p)
	add_child(card)

## Historical operations arrive on their day (nudged by the player's shift) and are offered once.
func _check_operations() -> void:
	# newsreel cards for the war's big days
	C.done_events = C.get("done_events", [])
	for ev in Story.EVENTS:
		if C.done_events.has(ev.title):
			continue
		if C.day >= ev.day:
			C.done_events.append(ev.title)
			if C.day - ev.day < 20.0:
				_show_card("NEWSREEL · %s" % War.date_str(ev.day), ev.title, ev.text, "Continue")
				_log("News: %s." % ev.title)
				return
	for op in War.OPERATIONS:
		if C.done_ops.has(op.name):
			continue
		if C.day >= op.day - C.shift * 0.5:
			C.done_ops.append(op.name)
			_offer_operation(op)
			return


func _show_card(kicker: String, title: String, text: String, button: String) -> void:
	speed_i = 0
	Audio.ui("radio", 0.7, "Radio")
	_refresh_top()
	card = Control.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(UI.backdrop(0.45))
	var p := UI.panel(22)
	p.custom_minimum_size.x = 560
	var v := UI.column(8)
	v.add_child(UI.label(kicker, 11, UI.BRASS))
	v.add_child(UI.label(title, 26))
	v.add_child(UI.wrap(text, 520))
	v.add_child(UI.big_button(button, _close_card))
	p.add_child(v)
	card.add_child(p)
	UI.center(p)
	add_child(card)


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
			_launch_scenario(op.scenario, op.name, op.zone)))
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

func _weather_now() -> String:
	var hour := fposmod(C.day, 1.0) * 24.0
	var night := hour < 5.5 or hour > 18.5
	return "night" if night else ["clear", "clear", "overcast", "fog"][_rng.randi() % 4]


## Attack an enemy group with the player's ship and squadron (and the friendly group we sail with).
func _engage(g: Dictionary) -> void:
	var friends: Array = C.squadron.duplicate(true)
	var convoy: Array = []
	var ag = _group(C.attached)
	if ag != null:
		for sh in ag.ships:
			if Data.TYPES[sh[0]].get("cls", "") == "merchant":
				convoy.append(sh)
			else:
				friends.append(sh)
	var plan := Missions.encounter(_rng, g, friends, convoy, C.ship, C.name, _weather_now())
	_launch(plan, "group", g.id, g.id, ag.id if ag != null else "")


## Join a battle between a friendly group and an enemy group.
func _join_fight(f: Dictionary) -> void:
	var gu = _group(f.us)
	var gj = _group(f.ijn)
	if gu == null or gj == null:
		return
	var friends: Array = C.squadron.duplicate(true)
	var convoy: Array = []
	for sh in gu.ships:
		if Data.TYPES[sh[0]].get("cls", "") == "merchant":
			convoy.append(sh)
		else:
			friends.append(sh)
	C.lon = f.lon; C.lat = f.lat
	C.dest = null
	C.intercept = ""
	var plan := Missions.encounter(_rng, gj, friends, convoy, C.ship, C.name, _weather_now())
	_launch(plan, "fight", f.id, gj.id, gu.id)


func _launch(plan: Dictionary, kind: String, ref: String, enemy_gid: String, friend_gid: String) -> void:
	var zone := ""
	var bd := 1e9
	for zid in War.ZONES:
		var z: Dictionary = War.ZONES[zid]
		var d := War.dist_nm(C.lon, C.lat, z.lon, z.lat)
		if d < bd:
			bd = d; zone = zid
	Game.mission = {"plan": plan, "weather": plan.weather, "kind": kind, "ref": ref, "zone": zone, "day": C.day, "enemy_gid": enemy_gid, "friend_gid": friend_gid}
	Game.career.year = War.year_of(int(C.day))
	Game.pending_load = -1
	_save()
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


## A historical operation uses one of the hand-built scenarios.
func _launch_scenario(scenario: String, ref: String, zone: String) -> void:
	Game.mission = {"kind": "op", "ref": ref, "zone": zone, "day": C.day, "scenario": scenario}
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
	var sunk: Array = r.get("sunk", [])
	var lost_friends: Array = r.get("lost_friends", [])
	# the enemy group loses what was sunk; the friendly group too; the squadron too
	var eg = _group(m.get("enemy_gid", m.get("ref", "") if m.get("kind", "") == "group" else ""))
	if eg != null:
		eg.ships = eg.ships.filter(func(sh): return not sunk.has(sh[1]))
		if r.get("over", "") == "won" or eg.ships.is_empty():
			C.groups.erase(eg)
		else:
			eg.state = "sail"; eg.fight = ""
	var fg = _group(m.get("friend_gid", ""))
	if fg != null:
		fg.ships = fg.ships.filter(func(sh): return not lost_friends.has(sh[1]))
		fg.state = "sail"; fg.fight = ""
		if fg.ships.is_empty():
			C.groups.erase(fg)
			if C.attached == fg.id:
				C.attached = ""
	var before: int = C.squadron.size()
	C.squadron = C.squadron.filter(func(sh): return not lost_friends.has(sh[1]))
	if C.squadron.size() < before:
		_log("Squadron losses: %s." % ", ".join(lost_friends))
	if m.get("kind", "") == "fight":
		C.fights = C.fights.filter(func(f): return f.id != m.get("ref", ""))
		if _group(m.get("friend_gid", "")) != null and m.get("friend_gid", "") != "":
			_group(m.friend_gid).state = "sail"
	selected = ""
	C.sunk_total += sunk.size()
	match r.get("over", ""):
		"won":
			C.won += 1
			C.shift += 4.0 if m.get("kind", "") != "op" else 12.0
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
	C.attached = ""
	C.intercept = ""
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
	var tid: String = avail[0] if not avail.is_empty() else "pt_elco"
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


# =====================================================================
# the squadron: ships recruited in port with reputation
# =====================================================================

## How many ships the player may have in company, by rank.
func _squadron_cap() -> int:
	return Missions.RANK_CAP[clampi(Game.career.rank, 0, 8)] - 1


func _recruit_menu() -> void:
	var c: Dictionary = Game.career
	var year := War.year_of(int(C.day))
	var cls: String = Data.TYPES[C.ship].get("cls", "dd")
	card = Control.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(UI.backdrop(0.5))
	var p := UI.panel(20)
	p.custom_minimum_size.x = 720
	var v := UI.column(6)
	v.add_child(UI.label("RECRUIT SHIPS · %d reputation · %d of %d places" % [c.reputation, C.squadron.size(), _squadron_cap()], 11, UI.BRASS))
	v.add_child(UI.wrap("Ships that join your squadron sail with you on the map and fight under your orders in every battle, until they are sunk or you release them in port (half the reputation comes back). Your rank sets how many ships you may lead; a bigger ship than your own will not take orders from you.", 680, 12, UI.MUTED))
	if not C.squadron.is_empty():
		v.add_child(UI.label("In company", 14))
		for i in C.squadron.size():
			var sh: Array = C.squadron[i]
			var cost: int = _cost_of(sh[0])
			var row := UI.row([], 8)
			row.add_child(UI.label("%s · %s" % [sh[1], Data.TYPES[sh[0]].name], 13))
			row.add_child(UI.button("Release (+%d)" % int(cost / 2), (func(k): c.reputation += int(_cost_of(C.squadron[k][0]) / 2); _log("%s released from the squadron." % C.squadron[k][1]); C.squadron.remove_at(k); _close_card(); _save(); _refresh_side(); _refresh_top()).bind(i)))
			v.add_child(row)
	v.add_child(UI.label("Available at %s" % _port_here(), 14))
	var own_disp: float = Data.TYPES[C.ship].get("displacement", 1000.0)
	var any := false
	for it in Missions.SUPPORT:
		if it[3] > year:
			continue
		var T: Dictionary = Data.TYPES[it[0]]
		if cls in ["pt", "ss"] and not (T.cls in ["pt", "dd", "de"] if cls == "pt" else false):
			continue
		if float(T.get("displacement", 0.0)) > own_disp * 1.6 and T.cls != cls:
			continue
		any = true
		var nm: String = _free_name(it[0])
		var b := UI.button("%d rep · %s (%s)" % [it[2], nm, it[1]], (func(tid, n2, cost):
			c.reputation -= cost
			C.squadron.append([tid, n2])
			_log("%s (%s) joins the squadron." % [n2, Data.TYPES[tid].name])
			_close_card(); _save(); _refresh_side(); _refresh_top()).bind(it[0], nm, it[2]))
		b.disabled = c.reputation < it[2] or C.squadron.size() >= _squadron_cap()
		b.add_theme_font_size_override("font_size", 12)
		v.add_child(b)
	if cls == "pt":
		# PT boats sail in sections with other boats
		var nm3 := "PT-%d" % (100 + _rng.randi() % 100)
		var b3 := UI.button("40 rep · %s (Elco PT boat)" % nm3, (func(n2): c.reputation -= 40; C.squadron.append(["pt_elco", n2]); _log("%s joins the section." % n2); _close_card(); _save(); _refresh_side(); _refresh_top()).bind(nm3))
		b3.disabled = c.reputation < 40 or C.squadron.size() >= _squadron_cap()
		b3.add_theme_font_size_override("font_size", 12)
		v.add_child(b3)
		any = true
	if not any:
		v.add_child(UI.label("Nothing suitable is available here yet.", 12, UI.MUTED))
	if _squadron_cap() <= 0:
		v.add_child(UI.wrap("A %s may not yet lead other ships; the next rank brings that." % Missions.RANKS[clampi(c.rank, 0, 8)], 680, 12, UI.BRASS))
	v.add_child(UI.row([UI.button("Close", _close_card)]))
	p.add_child(v)
	card.add_child(p)
	UI.center(p)
	add_child(card)


func _cost_of(tid: String) -> int:
	for it in Missions.SUPPORT:
		if it[0] == tid:
			return it[2]
	return 40


func _free_name(tid: String) -> String:
	var names: Array = Career.SHIP_NAMES.get(tid, []) + (US_DD_NAMES if Data.TYPES[tid].get("cls", "") in ["dd", "de"] else (US_CL_NAMES if Data.TYPES[tid].get("cls", "") == "cl" else (US_CA_NAMES if Data.TYPES[tid].get("cls", "") == "ca" else [])))
	var used := [C.name]
	for sh in C.squadron:
		used.append(sh[1])
	for k in Game.career.ships:
		used.append(Game.career.ships[k].name)
	for n in names:
		if not used.has(n):
			return n
	return "USS %s" % Data.TYPES[tid].name.replace(" class", "")


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
	# the player's detection circle
	var pp := _to_px(C.lon, C.lat)
	map.draw_arc(pp, _detect_range() / 60.0 * zoom, 0, TAU, 48, Color(0.55, 0.85, 1.0, 0.18), 1.0)
	# friendly groups: circles with a course tick and a track to their destination
	var blue := Color(0.55, 0.85, 1.0)
	for g in C.groups:
		if g.side != "us":
			continue
		var p := _to_px(g.lon, g.lat)
		var sel: bool = g.id == selected
		if g.dest != null:
			var dp := _to_px(g.dest[0], g.dest[1])
			map.draw_line(p, dp, Color(blue, 0.18 if not sel else 0.5), 1.0)
		var rr: float = 6.0 if g.kind != "convoy" else 7.0
		map.draw_circle(p, rr, Color(blue, 0.9) if not sel else UI.BRASS)
		map.draw_circle(p, rr - 2.5, Color(0.03, 0.10, 0.17))
		if g.kind == "convoy":
			map.draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), blue)
		elif g.kind == "sub":
			map.draw_line(p + Vector2(-3, 0), p + Vector2(3, 0), blue, 2.0)
		else:
			map.draw_circle(p, 2.0, blue)
		var course := _course(g)
		map.draw_line(p, p + Vector2(sin(course), -cos(course)) * 12.0, blue, 1.5)
		if zoom > 5.0 or sel:
			map.draw_string(font, p + Vector2(10, -6), "%s · %d" % [g.name, g.ships.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(blue, 0.9) if not sel else UI.BRASS)
	# enemy groups we know about: diamonds at the last known position
	for g in C.groups:
		if g.side != "ijn" or g.seen < 0.0:
			continue
		var age: float = (C.day - g.seen) * 24.0
		if age > 36.0:
			continue
		var fresh: bool = age < 3.0
		var pos: Vector2 = Vector2(g.lon, g.lat) if fresh else Vector2(g.seen_lon, g.seen_lat)
		var p := _to_px(pos.x, pos.y)
		var sel: bool = g.id == selected
		var col: Color = UI.BRASS if sel else Color(0.95, 0.35, 0.3, 1.0 if fresh else 0.6)
		var pts := PackedVector2Array([p + Vector2(0, -8), p + Vector2(8, 0), p + Vector2(0, 8), p + Vector2(-8, 0)])
		if fresh:
			map.draw_colored_polygon(pts, col)
			var course := _course(g)
			map.draw_line(p, p + Vector2(sin(course), -cos(course)) * 12.0, col, 1.5)
		else:
			map.draw_polyline(pts + PackedVector2Array([pts[0]]), col, 1.5)
		var label: String = "%s · %d" % [KIND_LABEL.get(g.kind, g.kind), g.ships.size()]
		if not fresh:
			label += " · %dh ago" % int(age)
		map.draw_string(font, p + Vector2(11, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	# battles in progress
	for f in C.fights:
		var p := _to_px(f.lon, f.lat)
		var pulse := 10.0 + 4.0 * sin(Time.get_ticks_msec() / 250.0)
		var col: Color = UI.BRASS if f.id == selected else Color(1.0, 0.75, 0.3)
		map.draw_arc(p, pulse, 0, TAU, 24, Color(col, 0.6), 1.5)
		map.draw_line(p + Vector2(-7, -7), p + Vector2(7, 7), col, 2.0)
		map.draw_line(p + Vector2(-7, 7), p + Vector2(7, -7), col, 2.0)
		map.draw_string(font, p + Vector2(14, 4), "Battle: %s" % _gname(f.us), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	# the player
	if C.dest != null and C.attached == "":
		var dp := _to_px(C.dest[0], C.dest[1])
		map.draw_line(pp, dp, Color(blue, 0.7), 1.5)
		map.draw_circle(dp, 4, Color(blue, 0.7))
	map.draw_arc(pp, ENGAGE_NM / 60.0 * zoom, 0, TAU, 32, Color(blue, 0.3), 1.0)
	var tri := PackedVector2Array([pp + Vector2(0, -10), pp + Vector2(7, 8), pp + Vector2(-7, 8)])
	map.draw_colored_polygon(tri, blue)
	var pn: String = C.name if C.squadron.is_empty() else "%s +%d" % [C.name, C.squadron.size()]
	map.draw_string(font, pp + Vector2(10, -8), pn, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, blue)
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
			C.attached = ""
			C.intercept = ""
			_set_dest(w.x, w.y)
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
	# a group or battle under the mouse selects it; otherwise set course
	for f in C.fights:
		if _to_px(f.lon, f.lat).distance_to(pos) < 14.0:
			selected = f.id
			_refresh_side()
			return
	for g in C.groups:
		if g.side == "ijn" and g.seen < 0.0:
			continue
		var age: float = (C.day - g.seen) * 24.0
		var p: Vector2 = Vector2(g.lon, g.lat) if g.side == "us" or age < 3.0 else Vector2(g.seen_lon, g.seen_lat)
		if _to_px(p.x, p.y).distance_to(pos) < 14.0:
			selected = g.id
			_refresh_side()
			return
	var w := _from_px(pos)
	C.attached = ""
	C.intercept = ""
	_set_dest(w.x, w.y)
	_refresh_side()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		if Game.pressed(e, "pause"):
			speed_i = 0 if speed_i > 0 else 1
			_refresh_top()
		elif Game.pressed(e, "menu"):
			_save()
			get_tree().change_scene_to_file("res://scenes/menu.tscn")


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
