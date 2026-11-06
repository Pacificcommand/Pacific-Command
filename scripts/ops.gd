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
const KIND_LABEL := {"convoy": "Convoy", "express": "Tokyo Express", "taskforce": "Task force", "carriers": "Carrier force", "barges": "Barge traffic", "sub": "Submarine", "patrol": "Patrol", "boats": "Torpedo boats", "picket": "Picket boats"}

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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fresh="):
			# test: a new campaign from that day (overwrites the saved one)
			Game.campaign = new_campaign(int(a.split("=")[1]), "fletcher", "USS Fletcher")
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
	_check_offers.call_deferred()
	_log("Operations map. Click the sea to set a course. Blue: our groups; red: enemy groups our radar, aircraft or friends have found.")
	# a few groups are already at sea when the campaign opens
	if C.groups.is_empty():
		for i in 8:
			_spawn_group("us" if i % 2 == 0 else "ijn", true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ops="):
			speed_i = 3
			_test_shot(a.split("=")[1])
		if a.begins_with("--dock="):
			_test_dock(a.split("=")[1])
		if a.begins_with("--campaigntest="):
			_campaign_test.call_deferred(float(a.split("=")[1]))


## Older campaign saves get the new fields.
func _migrate() -> void:
	for k in ["groups", "fights", "squadron"]:
		if not C.has(k):
			C[k] = []
	if not C.has("attached"):
		C.attached = ""
	if not C.has("intercept"):
		C.intercept = ""
	if not C.has("next_id"):
		C.next_id = 1
	C.erase("contacts")
	for k in ["zone_owner", "base_owner", "islands"]:
		if not C.has(k):
			C[k] = {}
	if not C.has("sieges"):
		C.sieges = []
	# islands start with their historical holder
	for iid in Geo.ISLANDS:
		if not C.islands.has(iid):
			var isl: Dictionary = Geo.ISLANDS[iid]
			var side := War.owner(isl.zone, C.day, C.shift)
			if isl.base != "" and War.BASES[isl.base].side == "us" and War.BASES[isl.base].from >= 0 and C.day >= War.BASES[isl.base].from:
				side = "us"
			if isl.base != "" and War.BASES[isl.base].side == "ijn" and side == "us" and War.ZONES[isl.zone].us > C.day:
				side = "ijn"
			C.islands[iid] = {"side": side, "garrison": isl.garrison if side == "ijn" else maxi(1, isl.garrison - 1), "grow": C.day}


## Test: go alongside at the nearest friendly port and take a picture (--dock=PNG [--docksel=N] [--frames=N]).
func _test_dock(path: String) -> void:
	if _port_here() == "":
		var best := ""
		var bd := 1e9
		for nm in War.BASES:
			if _base_side(nm) == "us":
				var b: Dictionary = War.BASES[nm]
				var d := War.dist_nm(C.lon, C.lat, b.lon, b.lat)
				if d < bd:
					bd = d; best = nm
		C.lon = War.BASES[best].lon; C.lat = War.BASES[best].lat; C.dest = null
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dockship="):
			var tid: String = a.split("=")[1]
			Career.take_command(Game.career, tid, "USS Test", int(C.day))
			C.ship = tid
	if "--medals" in OS.get_cmdline_user_args():
		var c: Dictionary = Game.career
		var ln := []
		for id in ["navy_cross", "silver_star", "bronze_star", "bronze_star", "asiatic_pacific"]:
			Career.award(c, id, int(C.day), ln, "You")
		for o in c.officers:
			for id in Career.MEDAL_DEFS:
				if Career.MEDAL_DEFS[id].who == o.post:
					Career.award(o, id, int(C.day), ln, o.name)
					Career.award(o, id, int(C.day), ln, o.name)
	var selv := -1
	var frames := 120
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--docksel="):
			selv = int(a.split("=")[1])
		if a.begins_with("--frames="):
			frames = int(a.split("=")[1])
	await get_tree().process_frame
	open_dock(selv)
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	get_tree().quit()


var _print_log := "--oplog" in OS.get_cmdline_user_args()


## Test: run the war fast without drawing (--campaigntest=DAYS [--give=id,id] islands start ours,
## [--jpstrong] Japan always finds the ships), printing the log and the islands at the end.
func _shot_now(path: String) -> void:
	for i in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	get_tree().quit()


## Test: --squad=type,type,... puts those ships in the player's squadron.
func _test_squad() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--squad="):
			C.squadron = []
			var k := 0
			for t in a.split("=")[1].split(","):
				k += 1
				C.squadron.append([t, "USS Test %d" % k])


func _campaign_test(days: float) -> void:
	_print_log = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--give="):
			for iid in a.split("=")[1].split(","):
				if C.islands.has(iid):
					_capture(iid, "us", "Test")
	var end: float = C.day + days
	while C.day < end:
		var d0 := int(C.day)
		C.day += 1.0 / 24.0
		_move_groups(1.0)
		_tick_hour()
		if int(C.day) != d0:
			_tick_day()
			_reinforce_islands()
			_jp_counterattack()
			_radar_islands()
		if card != null:
			_close_card()
	for iid in C.islands:
		var st: Dictionary = C.islands[iid]
		print("%-13s %-3s tier %d  batteries %d  fleet %s  airfield %s/%d  %s" % [iid, st.side, island_tier(iid), int(st.garrison), _describe(st.get("fleet", [])),
			str(st.get("af", "-")), int(st.get("planes", 0)), "radar" if st.get("radar_on", false) else ""])
	print("sieges ", C.sieges)
	get_tree().quit()


func _test_shot(path: String) -> void:
	var days := 0.3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--days="):
			days = float(a.split("=")[1])
	var start_day: float = C.day
	var start_pos := {}
	for g in C.groups:
		start_pos[g.id] = [g.lon, g.lat]
	var frames := 0
	while C.day < start_day + days and frames < 6000:
		frames += 1
		await get_tree().process_frame
		if card != null:
			_close_card()
			speed_i = 3
	speed_i = 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--offer="):
			Game.career.offers = [int(a.split("=")[1])]
			_close_card()
			_check_offers()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mapisland="):
			# test: centre the map on an island, zoomed in, and select it
			var iid: String = a.split("=")[1]
			if Geo.ISLANDS.has(iid):
				cam_lon = Geo.ISLANDS[iid].lon; cam_lat = Geo.ISLANDS[iid].lat
				zoom = 40.0
				selected = iid
				_refresh_side()
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
		var moved := -1.0
		if start_pos.has(g.id):
			moved = War.dist_nm(start_pos[g.id][0], start_pos[g.id][1], g.lon, g.lat)
		print("  %s %s %s [%s] at %.1f,%.1f -> %s %s (moved %d nm)" % [g.side, g.kind, g.name, _describe(g.ships), g.lon, g.lat, _dest_name(g), g.state, int(moved)])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--assaultat="):
			# test: assault that island with its full defence (--squad=type,type adds ships)
			var iid: String = a.split("=")[1]
			if C.islands[iid].side != "ijn":
				_capture(iid, "ijn", "Test")
				C.islands[iid].erase("fleet")
			_test_squad()
			C.lon = Geo.ISLANDS[iid].lon + 0.3; C.lat = Geo.ISLANDS[iid].lat
			var st := _island_def(iid)
			print("assaulting ", iid, " tier ", island_tier(iid), " batteries ", st.garrison, " fleet ", _describe(st.fleet), " planes ", st.planes, " strength ", _def_strength(iid), " vs ", Missions.group_strength(_our_force()))
			if "--bop" in OS.get_cmdline_user_args():
				_balance_card(iid, "assault")
				_shot_now(path)
				return
			_assault(iid)
			return
		if a.begins_with("--give="):
			for gi in a.split("=")[1].split(","):
				if C.islands.has(gi) and C.islands[gi].side != "us":
					_capture(gi, "us", "Test")
		if a.begins_with("--defendat="):
			# test: the Japanese land on an island of ours; join the defence (or --bop: show the card)
			var iid2: String = a.split("=")[1]
			if C.islands[iid2].side != "us":
				_capture(iid2, "us", "Test")
			_test_squad()
			var isl2: Dictionary = Geo.ISLANDS[iid2]
			var g := _make_group("ijn", _base_weighted("ijn", isl2.lon, isl2.lat), [isl2.lon, isl2.lat], false, War.year_of(int(C.day)), "taskforce")
			g.lon = isl2.lon + 0.2; g.lat = isl2.lat
			g.assault = iid2
			C.groups.append(g)
			C.lon = isl2.lon + 0.3; C.lat = isl2.lat
			_start_siege(iid2, g)
			var sg = _siege_of(iid2)
			print("defending ", iid2, " against ", _describe(g.ships))
			if "--bop" in OS.get_cmdline_user_args():
				_shot_now(path)
				return
			if "--mapshot" in OS.get_cmdline_user_args():
				# the map with the invasion on it (and radar rings): centred on the island
				_close_card()
				for iid3 in C.islands:
					if C.islands[iid3].side == "us" and C.islands[iid3].has("radar_t"):
						C.islands[iid3].radar_t = C.day - 1.0
				_radar_islands()
				cam_lon = isl2.lon; cam_lat = isl2.lat
				zoom = 26.0
				selected = iid2
				_refresh_side()
				_shot_now(path)
				return
			_close_card()
			_defend_island(sg)
			return
	if "--assault" in OS.get_cmdline_user_args():
		var best := ""
		var bd := 1e9
		for iid in C.islands:
			if C.islands[iid].side == "ijn":
				var isl: Dictionary = Geo.ISLANDS[iid]
				var d := War.dist_nm(C.lon, C.lat, isl.lon, isl.lat)
				if d < bd:
					bd = d; best = iid
		C.lon = Geo.ISLANDS[best].lon + 0.3; C.lat = Geo.ISLANDS[best].lat
		print("assaulting ", best, " garrison ", C.islands[best].garrison)
		_assault(best)
		return
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
		if _base_side(nm) == "us" and War.dist_nm(C.lon, C.lat, b.lon, b.lat) < PORT_NM:
			return nm
	return ""


func _refresh_side() -> void:
	for c in side.get_children():
		c.queue_free()
	side.add_child(UI.label("OPERATIONS", 11, UI.BRASS))
	side.add_child(UI.row([UI.button("Career", _open_career), UI.button("Encyclopedia", func(): add_child(EncyclopediaPanel.new())), UI.button("Mail (%d)" % Game.career.get("mail", []).size(), _show_mail)]))
	# squadron
	if not C.squadron.is_empty():
		side.add_child(UI.wrap("Squadron: %s." % _describe(C.squadron), 350, 12, Color(0.55, 0.85, 1.0)))
	var port := _port_here()
	if port != "":
		side.add_child(UI.label("In port: %s" % port, 16))
		side.add_child(UI.big_button("Go to the dock", func(): open_dock()))
		var cs := Career.ship(Game.career)
		var repair_days := _repair_days(cs)
		if repair_days > 0:
			var rb := UI.button("Repair (%d day%s in the yard)" % [repair_days, "" if repair_days == 1 else "s"], func(): _repair(repair_days))
			side.add_child(rb)
		else:
			side.add_child(UI.label("Ship in good order, crew at full strength.", 12, UI.GREEN))
		side.add_child(UI.row([UI.button("Request a new command", _request_command), UI.button("Refit (%d supply)" % Game.career.get("supply", 0), _refit_menu)]))
	# attached to a friendly group
	if C.attached != "":
		var ag = _group(C.attached)
		if ag != null:
			side.add_child(UI.wrap("Sailing with %s (%s) toward %s. You fight if they are attacked." % [ag.name, _describe(ag.ships), _dest_name(ag)], 350, 12, Color(0.55, 0.85, 1.0)))
			side.add_child(UI.button("Detach and sail on your own", func(): C.attached = ""; _log("Detached from %s." % ag.name); _refresh_side()))
	# the selected thing
	var g = _group(selected)
	var f = _fight(selected)
	if Geo.ISLANDS.has(selected):
		_island_side_panel(selected)
	elif f != null:
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
		"boats": return "torpedo boat section"
		"picket": return "picket boats"
	return kind


func _island_side_panel(iid: String) -> void:
	var isl: Dictionary = Geo.ISLANDS[iid]
	var st: Dictionary = C.islands[iid]
	var ours: bool = st.side == "us"
	var d := War.dist_nm(C.lon, C.lat, isl.lon, isl.lat)
	side.add_child(UI.label(isl.name, 18))
	var gtxt := "%d coastal batter%s" % [int(st.garrison), "y" if int(st.garrison) == 1 else "ies"]
	side.add_child(UI.wrap("%s · %s · %.0f nm away%s%s." % ["Held by us" if ours else "Held by Japan", gtxt, d, " · key to %s" % War.ZONES[isl.zone].name if isl.key else "", " · base: %s" % isl.base if isl.base != "" else ""], 350, 12))
	var guards := _guards_near(iid, "ijn" if ours else "us")
	var own_guards := _guards_near(iid, "us" if ours else "ijn")
	if not own_guards.is_empty():
		side.add_child(UI.wrap("%s near the island: %s." % ["Our ships" if ours else "Enemy guard", ", ".join(own_guards.map(func(g): return g.name if g.side == "us" else _kind_lc(g.kind) + " (" + _describe(g.ships) + ")"))], 350, 12, Color(0.55, 0.85, 1.0) if ours else Color(0.95, 0.45, 0.4)))
	if not guards.is_empty():
		side.add_child(UI.wrap("%s threatening it: %s." % ["Enemy ships" if ours else "Our ships", ", ".join(guards.map(func(g): return g.name if g.side == "us" else _kind_lc(g.kind)))], 350, 12, UI.BRASS))
	var go := UI.button("Set course", func(): C.attached = ""; C.intercept = ""; _set_dest(isl.lon + 0.2, isl.lat); _refresh_side())
	side.add_child(go)
	var dst := _island_def(iid)
	var sg = _siege_of(iid)
	if not ours:
		side.add_child(UI.wrap("%s. Guard force: %s. Airfield: %s." % [TIER_NAME[island_tier(iid)], _describe(dst.get("fleet", [])) if not dst.get("fleet", []).is_empty() else "none",
			("%d planes" % int(dst.planes)) if dst.get("af", false) and Missions.has_airfield(iid) else ("wrecked" if Missions.has_airfield(iid) else "none")], 350, 12, Color(0.95, 0.6, 0.5)))
	if sg != null:
		var left: float = maxf(0.0, float(sg.ends) - C.day)
		side.add_child(UI.wrap(("INVASION: the Japanese are landing. The garrison holds for about %.1f more days." if sg.side == "ijn" else "Our troops are ashore: the fight for the island lasts about %.1f more days.") % left, 350, 12, UI.BRASS))
		side.add_child(UI.button("Balance of power: %s" % ("join the defence" if sg.side == "ijn" else "join the landing"), func(): _balance_card(iid, "defend" if sg.side == "ijn" else "support", sg)))
	elif not ours:
		var blocked := not own_guards.is_empty()
		var txt := "Assault: balance of power" if not blocked else "Assault: drive off the guard first"
		var b := UI.button(txt, func(): _balance_card(iid, "assault"))
		b.disabled = blocked and d < ENGAGE_NM
		side.add_child(b)
		side.add_child(UI.wrap("Taking an island: sink its guard force, silence its coastal guns, burn the supply dump and wreck the airfield; the landing force does the rest. The island then gets a radar station (%d nm of warning), its base is ours, and a key island brings the whole zone with it. Take every island to win the war." % int(RADAR_NM), 350, 11, UI.MUTED))
	elif dst.has("radar_t"):
		side.add_child(UI.wrap("Radar station: %s." % ("operating, %d nm" % int(RADAR_NM) if C.day >= float(dst.radar_t) else "being set up"), 350, 12, Color(0.55, 0.85, 1.0)))


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
	if _print_log:
		print("[%s] %s" % [War.date_str(int(C.day)), txt])
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
		_reinforce_islands()
		_jp_counterattack()
		_radar_islands()
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
	var kn: float = _squadron_speed()
	var step := kn * hours
	if _advance(C, C.dest, step):
		if C.intercept == "":
			C.dest = null
			speed_i = mini(speed_i, 1)
			_log("Arrived. %s." % _where().capitalize())
			_refresh_side()
			if _port_here() != "":
				# making port: go alongside, the home base
				speed_i = 0
				open_dock()


## Cruising speed of the player and squadron: the slowest ship sets it; small craft push
## harder than fleets, so a PT boat outruns anything on the map and a battle fleet nothing.
func _squadron_speed() -> float:
	return _cruise_kn([[C.ship, C.name]] + C.squadron, "player") * (1.0 + Career.mod("cruise"))


static func _cruise_kn(ships: Array, kind: String) -> float:
	var kn := 99.0
	var biggest := 0.0
	for sh in ships:
		var T: Dictionary = Data.TYPES[sh[0]]
		kn = minf(kn, float(T.max_kn))
		biggest = maxf(biggest, float(T.get("displacement", 1000.0)))
	if kind == "sub":
		return 11.0
	var k := 0.85
	if biggest > 100.0: k = 0.75      # destroyers and escorts
	if biggest > 5000.0: k = 0.65     # cruisers
	if biggest > 20000.0: k = 0.55    # battleships and carriers
	if kind in ["convoy", "barges"]:
		k = 0.55
	return kn * k


func _move_groups(hours: float) -> void:
	for g in C.groups:
		if g.state == "fight" or g.dest == null:
			continue
		var step: float = float(g.kn) * hours
		if _advance(g, g.dest, step):
			g.dest = null
			g.arrived = true


## Move something with lon/lat toward a destination, steering round land. Returns true on arrival.
## Harbours sit on the coast, so the last 40 nm to a destination may cross the shoreline.
func _advance(o: Dictionary, dest: Array, step: float) -> bool:
	var d := War.dist_nm(o.lon, o.lat, dest[0], dest[1])
	if d <= step:
		o.lon = dest[0]; o.lat = dest[1]
		return true
	var dx: float = (dest[0] - o.lon) * cos(deg_to_rad(o.lat))
	var dy: float = dest[1] - o.lat
	var course := atan2(dx, dy)
	var step_deg := step / 60.0
	var near_port := d < 40.0
	var turns := [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.1, -2.1, 2.6, -2.6, PI]
	# Harbours sit on the coast, so a group leaving port can start inside the land outline.
	# Steer for the nearest open water first (looking a few miles ahead), then carry on.
	if not near_port and Geo.on_land(o.lon, o.lat):
		for probe in [0.1, 0.25, 0.5]:
			for turn in turns:
				var a0: float = course + float(turn)
				if not Geo.on_land(o.lon + sin(a0) * probe / cos(deg_to_rad(o.lat)), o.lat + cos(a0) * probe):
					o.lon += sin(a0) * step_deg / cos(deg_to_rad(o.lat))
					o.lat += cos(a0) * step_deg
					return false
		o.lon += sin(course) * step_deg / cos(deg_to_rad(o.lat))   # deep inland: head straight out
		o.lat += cos(course) * step_deg
		return false
	for turn in turns:
		var a: float = course + float(turn)
		var nlon: float = o.lon + sin(a) * step_deg / cos(deg_to_rad(o.lat))
		var nlat: float = o.lat + cos(a) * step_deg
		if near_port or not Geo.on_land(nlon, nlat):
			o.lon = nlon; o.lat = nlat
			return false
	return false      # boxed in: wait


# ---------------------------------------------------------------- the island campaign
# Every island Japan holds has a defence: a guard fleet, coastal batteries and (where there is
# one) an airfield with its planes. The further from Japan, the lighter it is held. Before any
# island battle the balance-of-power card shows how the two sides stack up; the player always
# fights it out (no auto-resolve). An attack on an island is a siege lasting days, so the player
# has time to sail there and join in, on either side. Islands we take get radar stations; Japan
# counterattacks when it has the ships. Take every island to win.

const TOKYO := [139.7, 35.7]
const FORTRESS := ["rabaul", "truk"]            # Japan's great bases: one tier harder
const RADAR_NM := 300.0                        # what a radar station on a captured island sees
const TIER_NAME := ["", "Outer island: lightly held", "Forward base: a cruiser and destroyers", "Fortified base: heavy cruisers", "Inner defence ring: battleships", "The last line before Japan"]
const JP_CLASS_NAMES := {
	"kagero": ["Kagero", "Shiranui", "Kuroshio", "Oyashio", "Hatsukaze", "Yukikaze", "Amatsukaze", "Tokitsukaze", "Urakaze", "Isokaze", "Hamakaze", "Tanikaze", "Nowaki", "Arashi", "Hagikaze", "Maikaze", "Akigumo"],
	"fubuki": ["Fubuki", "Shirayuki", "Hatsuyuki", "Miyuki", "Murakumo", "Shinonome", "Usugumo", "Shirakumo", "Isonami", "Uranami", "Ayanami", "Shikinami", "Amagiri", "Sagiri", "Oboro", "Akebono", "Ushio", "Sazanami"],
	"akizuki": ["Akizuki", "Teruzuki", "Suzutsuki", "Hatsuzuki", "Niizuki", "Wakatsuki", "Shimotsuki", "Fuyutsuki"],
	"nagara": ["Nagara", "Isuzu", "Yura", "Natori", "Kinu", "Abukuma", "Sendai", "Jintsu", "Naka"],
	"myoko": ["Myoko", "Nachi", "Haguro", "Ashigara"], "takao": ["Takao", "Atago", "Maya", "Chokai"],
	"mogami": ["Mogami", "Mikuma", "Suzuya", "Kumano"], "tone": ["Tone", "Chikuma"],
	"kongo": ["Kongo", "Haruna", "Kirishima", "Hiei"], "fuso": ["Fuso", "Yamashiro"], "ise": ["Ise", "Hyuga"],
	"nagato": ["Nagato", "Mutsu"], "yamato": ["Yamato", "Musashi"],
}


## How hard an island is to take: 1 (the outer islands) to 5 (the last ring round Japan).
static func island_tier(iid: String) -> int:
	var isl: Dictionary = Geo.ISLANDS[iid]
	var d := War.dist_nm(TOKYO[0], TOKYO[1], isl.lon, isl.lat)
	var t := 1
	if d < 2600.0: t = 2
	if d < 2150.0: t = 3
	if d < 1650.0: t = 4
	if d < 1000.0: t = 5
	if FORTRESS.has(iid):
		t = mini(5, t + 1)
	return t


## What Japan keeps at an island of a tier: the guard fleet's classes, batteries and planes.
func _jp_template(iid: String) -> Dictionary:
	var tier := island_tier(iid)
	var year := War.year_of(int(C.day))
	var dd := "akizuki" if year >= 1943 else "kagero"
	var fleet: Array = []
	match tier:
		1: fleet = ["kagero", "jp_mtb", "jp_mtb"]
		2: fleet = ["nagara", "kagero", "fubuki"]
		3: fleet = ["myoko", "nagara", "kagero", "fubuki", "kagero"]
		4: fleet = ["kongo", "takao", "mogami", "nagara", dd, "kagero", "fubuki"]
		_: fleet = ["yamato" if iid == "okinawa" else "nagato", "ise", "takao", "tone", "nagara", dd, "kagero", "kagero", "fubuki"]
	var planes: int = [0, 9, 18, 24, 30, 36][tier]
	return {"fleet": fleet, "batteries": mini(6, tier + 1), "planes": planes if Missions.has_airfield(iid) else 0}


func _jp_ship(tid: String, used: Array) -> Array:
	if tid == "jp_mtb":
		var nm := "T-%d" % (1 + _rng.randi() % 60)
		used.append(nm)
		return [tid, nm]
	var pool: Array = JP_CLASS_NAMES.get(tid, [Data.TYPES[tid].name])
	var free: Array = pool.filter(func(x): return not used.has(x))
	var name: String = free[_rng.randi() % free.size()] if not free.is_empty() else "%s %d" % [pool[0], used.size() + 2]
	used.append(name)
	return [tid, name]


## The island's defence state (made on first use): fleet, planes, airfield intact.
func _island_def(iid: String) -> Dictionary:
	var st: Dictionary = C.islands[iid]
	if st.side == "ijn" and not st.has("fleet"):
		var tp := _jp_template(iid)
		var used := []
		var fl := []
		for t in tp.fleet:
			fl.append(_jp_ship(t, used))
		st.fleet = fl
		st.planes = tp.planes
		st.af = Missions.has_airfield(iid)
		st.garrison = maxi(int(st.garrison), int(tp.batteries) - 1)
	elif st.side == "us" and not st.has("planes"):
		st.fleet = []
		st.planes = 12 if Missions.has_airfield(iid) else 0
		st.af = Missions.has_airfield(iid)
	return st


## Strength points of what holds the island: its ships, guns and planes.
func _def_strength(iid: String) -> float:
	var st := _island_def(iid)
	var pts: float = Missions.group_strength(st.get("fleet", [])) + 2.0 * int(st.garrison)
	if st.get("af", false):
		pts += float(st.get("planes", 0)) / 12.0 * 2.5
	return pts


## Our side: the player's ship, the squadron and the warships of the group we escort.
func _our_force() -> Array:
	var out: Array = [[C.ship, C.name]] + C.squadron.duplicate(true)
	var ag = _group(C.attached)
	if ag != null:
		for sh in ag.ships:
			if Data.TYPES[sh[0]].get("cls", "") != "merchant":
				out.append(sh)
	return out


## Island fleets come back to strength slowly, planes are flown in, wrecked airfields repaired.
func _reinforce_islands() -> void:
	for iid in C.islands:
		var st: Dictionary = C.islands[iid]
		if not st.has("planes"):
			continue
		if not st.get("af", true) and Missions.has_airfield(iid) and C.day >= float(st.get("af_fix", 0.0)):
			st.af = true
			st.planes = maxi(int(st.planes), 6)
			if st.side == "us":
				_log("The airfield on %s is back in action." % Geo.ISLANDS[iid].name)
		var cap: int = int(_jp_template(iid).planes) if st.side == "ijn" else (24 if Missions.has_airfield(iid) else 0)
		if st.get("af", false) and int(st.planes) < cap and C.day - float(st.get("plane_t", 0.0)) > 6.0:
			st.planes = mini(cap, int(st.planes) + 6)
			st.plane_t = C.day
		if st.side == "ijn" and C.day - float(st.get("ref_t", C.day)) > 20.0:
			st.ref_t = C.day
			var want: Array = _jp_template(iid).fleet
			var have: Array = st.fleet.map(func(sh): return sh[0])
			for t in want:
				if have.has(t):
					have.erase(t)
				else:
					var used: Array = st.fleet.map(func(sh): return sh[1])
					st.fleet.append(_jp_ship(t, used))
					break
		if not st.has("ref_t"):
			st.ref_t = C.day


# ---------------------------------------------------------------- the balance of power card

func _verdict(us: float, them: float) -> Array:
	var r := us / maxf(0.5, them)
	if r >= 2.0: return ["Overwhelming advantage", Color(0.45, 0.85, 0.55)]
	if r >= 1.3: return ["The advantage is ours", Color(0.6, 0.85, 0.55)]
	if r >= 0.8: return ["Evenly matched", UI.BRASS]
	if r >= 0.5: return ["Outnumbered", Color(0.95, 0.6, 0.35)]
	return ["Hopeless odds", Color(0.95, 0.4, 0.35)]


func _side_lines(ships: Array, batteries: int, af: bool, planes: int, iid: String, ijn: bool) -> String:
	var lines := []
	lines.append("Ships: %s" % (_describe(ships) if not ships.is_empty() else "none"))
	var cv_air := 0
	for sh in ships:
		var T: Dictionary = Data.TYPES[sh[0]]
		if T.has("aircraft") and not T.get("ground", false):
			cv_air += int(T.aircraft)
	if cv_air > 0:
		lines.append("Carrier aircraft: about %d" % cv_air)
	if batteries > 0:
		lines.append("Coastal batteries: %d (%s guns in concrete)" % [batteries, "14 cm" if ijn else "5-inch and 6-inch"])
	if Missions.has_airfield(iid) and iid != "":
		if af and planes > 0:
			lines.append("%s: %d aircraft (%s)" % [Missions.airfield_name(iid), planes, "Zeros, Vals and Kates" if ijn else "Wildcats, Dauntlesses and Avengers"])
		elif not af:
			lines.append("%s: wrecked, under repair" % Missions.airfield_name(iid))
	return "\n".join(lines)


## The card before an island battle. mode "assault" (we attack), "support" (help our landing
## force at a siege), "defend" (the Japanese are landing on our island).
func _balance_card(iid: String, mode: String, sg = null) -> void:
	if card != null and is_instance_valid(card):
		_close_card()
	speed_i = 0
	_refresh_top()
	var isl: Dictionary = Geo.ISLANDS[iid]
	var st := _island_def(iid)
	var d := War.dist_nm(C.lon, C.lat, isl.lon, isl.lat)
	var ours: Array = _our_force()
	var their_ships: Array = []
	var us_txt := ""
	var them_txt := ""
	var us_pts := 0.0
	var them_pts := 0.0
	var ag = _group(sg.gid) if sg != null else null
	if mode == "defend":
		their_ships = ag.ships if ag != null else []
		var guards := _guards_near(iid, "us")
		for gg in guards:
			for sh in gg.ships:
				if Data.TYPES[sh[0]].get("cls", "") != "merchant":
					ours.append(sh)
		us_pts = Missions.group_strength(ours) + _def_strength(iid)
		them_pts = Missions.group_strength(their_ships)
		us_txt = _side_lines(ours, int(st.garrison), st.get("af", false), int(st.get("planes", 0)), iid, false)
		them_txt = _side_lines(their_ships, 0, false, 0, "", true) + "\nTroop transports behind them"
	else:
		if mode == "support" and ag != null:
			for sh in ag.ships:
				if Data.TYPES[sh[0]].get("cls", "") != "merchant":
					ours.append(sh)
		their_ships = st.get("fleet", [])
		us_pts = Missions.group_strength(ours)
		them_pts = _def_strength(iid)
		us_txt = _side_lines(ours, 0, false, 0, "", false)
		them_txt = _side_lines(their_ships, int(st.garrison), st.get("af", false), int(st.get("planes", 0)), iid, true)
	card = Control.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(UI.backdrop(0.5))
	var p := UI.panel(24)
	p.custom_minimum_size.x = 720
	var psb: StyleBoxFlat = p.get_theme_stylebox("panel").duplicate()
	psb.bg_color = Color(0.035, 0.07, 0.10, 0.97)       # solid: the map must not show through the figures
	psb.border_color = UI.BRASS
	p.add_theme_stylebox_override("panel", psb)
	var v := UI.column(10)
	var kick: String = {"assault": "BALANCE OF POWER · ASSAULT", "support": "BALANCE OF POWER · LANDING IN PROGRESS", "defend": "BALANCE OF POWER · INVASION"}[mode]
	v.add_child(UI.label("%s · %s" % [kick, War.date_str(int(C.day))], 11, UI.BRASS))
	v.add_child(UI.label(isl.name, 28))
	var sub: String = TIER_NAME[island_tier(iid)] if mode != "defend" else "Held by us"
	if sg != null:
		sub += " · %s, %.1f days left" % ["the garrison holds" if mode == "defend" else "our troops are ashore", maxf(0.0, float(sg.ends) - C.day)]
	v.add_child(UI.label(sub, 13, UI.MUTED))
	# the two sides, side by side
	var cols := UI.row([], 24)
	var left := UI.column(4)
	left.add_child(UI.label("YOUR FORCE", 12, Color(0.55, 0.85, 1.0)))
	left.add_child(UI.wrap(us_txt, 330, 13))
	var right := UI.column(4)
	right.add_child(UI.label("THE ENEMY", 12, Color(0.95, 0.45, 0.35)))
	right.add_child(UI.wrap(them_txt, 330, 13))
	cols.add_child(left)
	cols.add_child(right)
	v.add_child(cols)
	# the strength bar
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 0)
	var tot := maxf(0.5, us_pts + them_pts)
	var w_us := clampf(us_pts / tot, 0.04, 0.96) * 672.0
	var b1 := ColorRect.new(); b1.color = Color(0.35, 0.65, 0.95); b1.custom_minimum_size = Vector2(w_us, 16)
	var b2 := ColorRect.new(); b2.color = Color(0.85, 0.32, 0.27); b2.custom_minimum_size = Vector2(672.0 - w_us, 16)
	bar.add_child(b1); bar.add_child(b2)
	v.add_child(bar)
	var vd := _verdict(us_pts, them_pts)
	v.add_child(UI.row([UI.label("Strength %.0f" % us_pts, 12, Color(0.55, 0.85, 1.0)), UI.label(vd[0], 18, vd[1]), UI.label("Strength %.0f" % them_pts, 12, Color(0.95, 0.45, 0.35))], 150))
	var how := ""
	match mode:
		"assault", "support":
			how = "To take the island: sink or drive off the guard force, silence every battery, burn the supply dump and wreck the airfield. While the airfield stands its planes keep taking off against you: gunfire or dive bombers will finish it."
		"defend":
			how = "Sink the transports and beat off the warships. If you stay away, the garrison fights on alone until the siege ends, and may fall."
	v.add_child(UI.wrap(how + " There is no auto-resolve: you fight this battle yourself.", 672, 12, UI.MUTED))
	var row := UI.row([])
	var near := d < ENGAGE_NM
	var blocked := mode == "assault" and not _guards_near(iid, "ijn").is_empty()
	if near and not blocked:
		var label: String = {"assault": "Attack", "support": "Join the landing", "defend": "Join the defence"}[mode]
		row.add_child(UI.big_button(label, func():
			_close_card()
			if mode == "defend":
				_defend_island(sg)
			else:
				_assault(iid, sg)))
	elif blocked and near:
		row.add_child(UI.wrap("An enemy guard group is near the island: drive it off first.", 360, 12, UI.BRASS))
	else:
		row.add_child(UI.big_button("Set course (%.0f nm)" % d, func():
			_close_card()
			C.attached = ""; C.intercept = ""
			_set_dest(isl.lon + 0.2, isl.lat)
			_refresh_side()))
	row.add_child(UI.big_button("Not yet", _close_card))
	v.add_child(row)
	p.add_child(v)
	card.add_child(p)
	UI.center(p)
	add_child(card)


# ---------------------------------------------------------------- sieges

func _siege_of(iid: String):
	for sg in C.sieges:
		if sg.iid == iid:
			return sg
	return null


## A landing force has reached its island: the fighting ashore goes on for days.
func _start_siege(iid: String, g: Dictionary) -> void:
	var isl: Dictionary = Geo.ISLANDS[iid]
	var dur := _rng.randf_range(4.0, 6.0) if g.side == "ijn" else _rng.randf_range(3.0, 5.0)
	var sg := {"id": "s%d" % int(C.next_id), "iid": iid, "gid": g.id, "side": g.side, "start": C.day, "ends": C.day + dur}
	C.next_id = int(C.next_id) + 1
	C.sieges.append(sg)
	g.state = "siege"
	g.siege = sg.id
	g.dest = null
	g.seen = C.day; g.seen_lon = g.lon; g.seen_lat = g.lat      # an invasion is no secret
	_island_def(iid)
	Audio.ui("radio", 0.8, "Radio")
	if g.side == "ijn":
		_log("INVASION: a Japanese landing force (%s) is off %s. The garrison can hold for about %d days." % [_describe(g.ships), isl.name, int(dur)])
		_balance_card(iid, "defend", sg)
	else:
		_log("%s has put troops ashore on %s. The fighting will last about %d days: join it to make sure." % [g.name, isl.name, int(dur)])


## Sieges nobody joined are decided when their time is up: weight of metal, with luck.
func _resolve_sieges() -> void:
	var keep := []
	for sg in C.sieges:
		var iid: String = sg.iid
		var g = _group(sg.gid)
		if g == null or g.ships.is_empty() or _island_side(iid) == sg.side:
			if g != null:
				g.state = "sail"; g.erase("siege")
			continue
		if C.day < float(sg.ends):
			keep.append(sg)
			continue
		var isl: Dictionary = Geo.ISLANDS[iid]
		var st := _island_def(iid)
		var holder: String = st.side
		var A: float = Missions.group_strength(g.ships) * _rng.randf_range(0.75, 1.3)
		var D: float = _def_strength(iid)
		for gg in _guards_near(iid, holder):
			D += Missions.group_strength(gg.ships)
		D *= _rng.randf_range(0.75, 1.3)
		var lost_att := _losses(g, D / maxf(0.5, A + D))
		var tmp := {"ships": st.get("fleet", [])}
		var lost_def := _losses(tmp, A / maxf(0.5, A + D))
		st.fleet = tmp.ships
		st.garrison = maxi(1, int(st.garrison) - int(round(2.0 * A / maxf(0.5, A + D))))
		g.state = "sail"
		g.erase("siege"); g.erase("assault")
		# a landing against a dug-in garrison needs clear superiority
		if A > D * 1.25 and not g.ships.is_empty():
			_capture(iid, sg.side, g.name if sg.side == "us" else "A Japanese landing force")
		else:
			_log("The %s landing on %s has been thrown back.%s" % ["Japanese" if sg.side == "ijn" else "American", isl.name, (" Ships lost: %s." % ", ".join(lost_att)) if not lost_att.is_empty() else ""])
		if not lost_def.is_empty():
			_log("Lost in the fighting off %s: %s." % [isl.name, ", ".join(lost_def)])
		var hb: Dictionary = War.BASES.get(g.get("home", ""), {})
		if not hb.is_empty():
			g.dest = [hb.lon, hb.lat]; g.leg = 1
	C.sieges = keep
	C.groups = C.groups.filter(func(gg): return not gg.ships.is_empty())


## Join the defence of an island we hold against a landing.
func _defend_island(sg: Dictionary) -> void:
	var iid: String = sg.iid
	var g = _group(sg.gid)
	if g == null:
		return
	var isl: Dictionary = Geo.ISLANDS[iid]
	var st := _island_def(iid)
	var friends: Array = C.squadron.duplicate(true)
	var ag = _group(C.attached)
	if ag != null:
		for sh in ag.ships:
			if Data.TYPES[sh[0]].get("cls", "") != "merchant":
				friends.append(sh)
	for gg in _guards_near(iid, "us"):
		if gg.id != C.attached:
			for sh in gg.ships:
				if Data.TYPES[sh[0]].get("cls", "") != "merchant" and friends.size() < 10:
					friends.append(sh)
	var planes: int = int(st.get("planes", 0)) if st.get("af", false) else 0
	var plan := Missions.island_defence(_rng, isl, g.ships, int(st.garrison), planes, friends, C.ship, C.name, _weather_now())
	_launch(plan, "defend", iid, g.id, ag.id if ag != null else "", {"siege": sg.id})


# ---------------------------------------------------------------- Japanese counterattacks

## Now and then Japan gathers a force to retake an island we hold: the nearest one it can beat.
func _jp_counterattack() -> void:
	if C.get("war_over", false) or C.day < float(C.get("jp_counter_t", 0.0)):
		return
	C.jp_counter_t = C.day + _rng.randf_range(18.0, 30.0)
	for g in C.groups:
		if g.side == "ijn" and g.has("assault"):
			return               # one at a time
	var year := War.year_of(int(C.day))
	var best := ""
	var best_d := 1e9
	var best_base := ""
	for iid in C.islands:
		var st: Dictionary = C.islands[iid]
		# Japan goes for the islands we took from it, not America's own bases
		if st.side != "us" or not st.get("won_t", -1.0) >= 0.0 or _siege_of(iid) != null:
			continue
		var isl: Dictionary = Geo.ISLANDS[iid]
		var home := _base_weighted("ijn", isl.lon, isl.lat)
		if home == "":
			continue
		var d := War.dist_nm(War.BASES[home].lon, War.BASES[home].lat, isl.lon, isl.lat)
		if d < 1600.0 and d < best_d:
			best_d = d; best = iid; best_base = home
	if best == "":
		return
	var need := _def_strength(best) * 1.3
	var isl2: Dictionary = Geo.ISLANDS[best]
	var g := {}
	for k in 4:
		var tf := _make_group("ijn", best_base, [isl2.lon, isl2.lat], false, year, "taskforce")
		if tf.is_empty():
			return
		g = tf
		if Missions.group_strength(tf.ships) >= need:
			break
	# Japan is running out of ships late in the war: no force strong enough, no counterattack
	if g.is_empty() or Missions.group_strength(g.ships) < need * (0.8 if year <= 1943 else 1.0):
		return
	g.assault = best
	g.name = "%s Invasion Force" % String(isl2.name).get_slice(" (", 0).get_slice(" and ", 0)
	C.groups.append(g)
	_log("Radio intelligence: a Japanese invasion force (%s) has sailed from %s. Its target may be %s." % [_describe(g.ships), best_base, isl2.name])
	Audio.ui("radio", 0.6, "Radio")


# ---------------------------------------------------------------- radar and victory

## Radar stations on the islands we have taken: they see surface ships out to RADAR_NM, day and night.
func _radar_islands() -> Array:
	var out := []
	for iid in C.islands:
		var st: Dictionary = C.islands[iid]
		if st.side == "us" and st.has("radar_t") and C.day >= float(st.radar_t):
			out.append(iid)
			if not st.get("radar_on", false):
				st.radar_on = true
				_log("The radar station on %s is operating: %d nm of warning." % [Geo.ISLANDS[iid].name, int(RADAR_NM)])
	return out


func _check_victory() -> void:
	if C.get("victory", false):
		return
	for iid in C.islands:
		if C.islands[iid].side != "us":
			return
	C.victory = true
	C.war_over = true
	_show_card("VICTORY · %s" % War.date_str(int(C.day)), "The Pacific is ours",
		"Every island from Midway to Okinawa flies the Stars and Stripes. The Japanese fleet has been driven back to its home waters and the way to Japan lies open.\n\n%s led the way: %d battles won, %d enemy ships sunk. The war is won." % [C.name, int(C.get("won", 0)), int(C.get("sunk_total", 0))], "Carry on")


# ---------------------------------------------------------------- islands and captures

func _island_side(iid: String) -> String:
	return C.islands.get(iid, {}).get("side", "ijn")


## Enemy warship groups guarding an island (within 60 nm of it).
func _guards_near(iid: String, side: String) -> Array:
	var isl: Dictionary = Geo.ISLANDS[iid]
	var out := []
	for g in C.groups:
		if g.side != side or g.kind in ["convoy", "barges", "sub"]:
			continue
		if War.dist_nm(g.lon, g.lat, isl.lon, isl.lat) < 60.0:
			out.append(g)
	return out


## The flag changes hands. Bases, zones (for key islands), spotting and spawning follow.
func _capture(iid: String, side: String, who: String) -> void:
	var isl: Dictionary = Geo.ISLANDS[iid]
	var st: Dictionary = C.islands[iid]
	st.side = side
	st.capt = true
	st.garrison = 1
	st.grow = C.day
	for k in ["fleet", "planes", "af", "af_fix", "ref_t", "plane_t", "radar_t", "radar_on"]:
		st.erase(k)
	_island_def(iid)
	if side == "us":
		# the Marines dig in at once and the Seabees have the strip working in days
		st.won_t = C.day
		st.garrison = 2
		st.radar_t = C.day + 2.0
		st.planes = 12 if Missions.has_airfield(iid) else 0
	else:
		# a force that has just landed has not brought the whole garrison: half the guard fleet
		st.fleet = st.fleet.slice(0, maxi(1, int(st.fleet.size() / 2)))
		st.planes = int(int(st.planes) / 2)
	var sgc = _siege_of(iid)
	if sgc != null:
		C.sieges.erase(sgc)
	if isl.base != "":
		C.base_owner[isl.base] = side
	if isl.key:
		C.zone_owner[isl.zone] = side
	_log("%s took %s%s." % [who, isl.name, (" and with it %s" % War.ZONES[isl.zone].name) if isl.key and War.ZONES[isl.zone].name != isl.name else ""])
	Audio.ui("radio", 0.7, "Radio")
	if side == "us":
		C.shift += 6.0 if isl.key else 2.0
		_check_victory()
	else:
		C.shift -= 6.0 if isl.key else 2.0
	# guards with nothing left to guard go home
	for g in C.groups:
		if g.get("guard", "") == iid and g.side != side:
			g.erase("guard")
			var hb: Dictionary = War.BASES.get(g.home, {})
			if not hb.is_empty() and _base_side(g.home) == g.side:
				g.dest = [hb.lon, hb.lat]
				g.leg = 1


## Garrisons dig in over time (one battery a month, up to the island's full strength).
func _grow_garrisons() -> void:
	for iid in C.islands:
		var st: Dictionary = C.islands[iid]
		var mx: int = maxi(int(Geo.ISLANDS[iid].garrison), mini(6, island_tier(iid) + 1)) if st.side == "ijn" else mini(4, 1 + int(island_tier(iid) / 2))
		if st.garrison < mx and C.day - float(st.get("grow", C.day)) > 30.0:
			st.garrison += 1
			st.grow = C.day


## Both sides' task forces go for weakly held enemy islands at the front, and take them when
## they arrive unopposed; the other side's guards or a passing fleet can stop them.
## History runs on where the player has not changed it: an island nobody has fought over falls to
## Japan on the day its zone did (Wake on 23 December 1941, the Gilberts, the Solomons ...).
func _history_captures() -> void:
	for iid in Geo.ISLANDS:
		var st: Dictionary = C.islands[iid]
		if st.side != "us" or st.get("capt", false):
			continue
		var isl: Dictionary = Geo.ISLANDS[iid]
		var z: Dictionary = War.ZONES[isl.zone]
		if isl.base != "" and War.BASES[isl.base].side == "us" and War.BASES[isl.base].from >= 0 and C.day >= War.BASES[isl.base].from:
			continue
		if int(z.jp) >= 0 and C.day >= int(z.jp) and (int(z.us) < 0 or C.day < int(z.us) - C.shift) and not C.zone_owner.has(isl.zone):
			_capture(iid, "ijn", "The Japanese")
			st.garrison = isl.garrison


func _ai_captures() -> void:
	var fronts := _front_zones()
	for g in C.groups:
		if g.state != "sail" or not (g.kind in ["taskforce", "carriers", "patrol"]):
			continue
		if g.has("assault") or g.side == "ijn":
			continue          # Japan's landings are its counterattacks (_jp_counterattack)
		if Missions.group_strength(g.ships) < 8.0 or _rng.randf() > 0.08:
			continue
		var best := ""
		var bd := 900.0
		for iid in Geo.ISLANDS:
			var isl: Dictionary = Geo.ISLANDS[iid]
			if _island_side(iid) == g.side or not fronts.has(isl.zone):
				continue
			if Missions.group_strength(g.ships) < _def_strength(iid) * 1.3 or _siege_of(iid) != null:
				continue
			if not _guards_near(iid, "us" if g.side == "ijn" else "ijn").is_empty():
				continue
			var d := War.dist_nm(g.lon, g.lat, isl.lon, isl.lat)
			if d < bd:
				bd = d; best = iid
		if best != "":
			g.assault = best
			g.orig_dest = g.dest
			g.dest = [Geo.ISLANDS[best].lon, Geo.ISLANDS[best].lat]
			if g.side == "us":
				_log("%s is making for %s to put a landing force ashore." % [g.name, Geo.ISLANDS[best].name])


## A group that has reached the island it meant to take.
func _assault_arrived(g: Dictionary) -> bool:
	var iid: String = g.get("assault", "")
	if iid == "":
		return false
	var isl: Dictionary = Geo.ISLANDS[iid]
	if _island_side(iid) == g.side:
		g.erase("assault")
		return false
	if _siege_of(iid) == null:
		_start_siege(iid, g)
	return true


func _tick_hour() -> void:
	if int(C.day) != _ach_day:
		_ach_day = int(C.day)
		SteamHook.check_day(_ach_day)
	# groups that have arrived go into port (or turn for home from a patrol area)
	var keep := []
	for g in C.groups:
		if g.get("arrived", false) and g.has("assault"):
			g.arrived = false
			if _assault_arrived(g):
				keep.append(g)
				continue
		if g.get("arrived", false) and g.has("guard"):
			# guards loiter around their island
			g.arrived = false
			var gi: Dictionary = Geo.ISLANDS[g.guard]
			var a := _rng.randf() * TAU
			g.dest = [gi.lon + cos(a) * 0.5, gi.lat + sin(a) * 0.5]
			keep.append(g)
			continue
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
	_resolve_sieges()
	if int(C.day * 24.0) % 6 == 0:
		_ai_captures()
		_history_captures()

	_grow_garrisons()
	_spawn_guards()


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
				"boats": nm = "Torpedo Boat Section %d" % (1 + _rng.randi() % 20)
				"picket": nm = "Picket Unit %d" % (1 + _rng.randi() % 30)
				_: nm = "Escort Unit %d" % (1 + _rng.randi() % 20)
		if not used.has(nm):
			return nm
	return "%s group" % side.to_upper()

func _active_bases(side: String) -> Array:
	var out := []
	for nm in War.BASES:
		if _base_side(nm) == side:
			out.append(nm)
	return out


## Who holds a base today: a capture on the map overrides history.
func _base_side(nm: String) -> String:
	if C.base_owner.has(nm):
		return C.base_owner[nm]
	var b: Dictionary = War.BASES[nm]
	if b.side == "us":
		return "us" if (b.from >= 0 and C.day >= b.from) else "ijn"
	return "ijn" if War.owner(b.zone, C.day, C.shift) == "ijn" else "us"


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


## Pick a base of a side at random, the ones nearer a point more often (so the fleet
## works out of the forward bases but convoys still come up from the rear).
func _base_weighted(side: String, lon: float, lat: float, exclude := "") -> String:
	var bases := _active_bases(side)
	var weights := []
	var total := 0.0
	for nm in bases:
		if nm == exclude:
			weights.append(0.0)
			continue
		var d := War.dist_nm(lon, lat, War.BASES[nm].lon, War.BASES[nm].lat)
		var w := 1.0 / (1.0 + d / 700.0)
		weights.append(w)
		total += w
	if total <= 0.0:
		return ""
	var r := _rng.randf() * total
	for i in bases.size():
		r -= weights[i]
		if r <= 0.0:
			return bases[i]
	return bases[bases.size() - 1]


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
	var home := _base_weighted(side, z.lon, z.lat)
	if home == "":
		return
	var hb: Dictionary = War.BASES[home]
	# destination: a point in the front zone, or another of our bases (convoys mostly run
	# base to base, bringing supplies up from the rear; warships mostly go to the front)
	var dest := []
	var dest_name := ""
	var base_chance := 0.7 if kind in ["convoy", "sub"] else (0.3 if kind == "patrol" else 0.2)
	var to_base: bool = _rng.randf() < base_chance and bases.size() > 1
	if to_base:
		var other := _base_weighted(side, z.lon, z.lat, home)
		if other == "":
			to_base = false
		else:
			dest = [War.BASES[other].lon, War.BASES[other].lat]
			dest_name = other
	if not to_base:
		var a := _rng.randf() * TAU
		var r: float = z.r * _rng.randf_range(0.1, 0.7) / 60.0
		dest = [z.lon + cos(a) * r / cos(deg_to_rad(z.lat)), z.lat + sin(a) * r]
		# convoys and barges do not sail into waters the other side holds
		if kind in ["convoy", "barges"] and War.owner(zid, C.day, C.shift) != side:
			var other2 := _base_weighted(side, z.lon, z.lat, home)
			if other2 != "":
				dest = [War.BASES[other2].lon, War.BASES[other2].lat]
				dest_name = other2
				to_base = true
			else:
				kind = "express" if side == "ijn" else "patrol"
	var route := War.dist_nm(hb.lon, hb.lat, dest[0], dest[1])
	if route > 3200.0 or route < 30.0:
		return
	if kind in ["barges", "boats", "picket"] and route > 500.0:
		kind = "express"
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
		# small fry (torpedo boats, pickets, barges) are the most common and the easiest prey
		pool = ["convoy", "convoy", "express", "express", "taskforce", "sub", "barges", "barges", "boats", "boats", "picket", "picket"]
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
	# both sides field bigger groups as the war goes on (the challenge keeps pace with the career)
	var progress: float = clampf(C.day / 1368.0, 0.0, 1.0)
	var strength := clampf(act * _rng.randf_range(0.6, 1.6) + progress * (1.3 if side == "us" else 1.0), 0.3, 3.0)
	ships = _ships_for(side, kind, strength, year)
	if ships.is_empty():
		return {}
	kn = _cruise_kn(ships, kind)
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
			"boats":
				var nb := clampi(int(2 + strength * 1.5), 2, 4)
				var base_no := 1 + _rng.randi() % 60
				for i in nb:
					out.append(["jp_mtb", "T-%d" % (base_no + i)])
			"picket":
				out.append(["subchaser", "CH-%d" % (12 + _rng.randi() % 40)])
				if strength > 0.8:
					out.append(["subchaser", "CH-%d" % (12 + _rng.randi() % 40)])
				var ng := clampi(int(1 + strength), 1, 2)
				for i in ng:
					out.append(["daihatsu_gun", "Gun barge %d" % (i + 1)])
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
	var r := 80.0
	if T.get("radar", 0.0) > 0.0:
		r = 120.0
	if T.get("cls", "") in ["cv", "cvl", "cve"]:
		r = 240.0          # search planes
	if T.get("cls", "") in ["bb", "ca"] and War.year_of(int(C.day)) >= 1942:
		r = 170.0          # floatplanes
	for sh in C.squadron:
		var c2: String = Data.TYPES[sh[0]].get("cls", "")
		if c2 in ["cv", "cvl", "cve"]:
			r = maxf(r, 240.0)
		elif c2 in ["bb", "ca"]:
			r = maxf(r, 170.0)
		elif Data.TYPES[sh[0]].get("radar", 0.0) > 0.0:
			r = maxf(r, 120.0)
	r *= 1.0 + 0.5 * Career.mod("radar") + Career.mod("map_eyes")
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
				if u.side == "us" and War.dist_nm(u.lon, u.lat, g.lon, g.lat) < (90.0 if not sub else 25.0):
					found = true
					break
		if not found and not sub:
			for iid in _radar_islands():
				if War.dist_nm(Geo.ISLANDS[iid].lon, Geo.ISLANDS[iid].lat, g.lon, g.lat) < RADAR_NM:
					found = true
					break
		if not found and day and not sub:
			# air search from our bases and the islands we hold
			for pt in _spot_points("us"):
				if War.dist_nm(pt[0], pt[1], g.lon, g.lat) < pt[2] and _rng.randf() < 0.2:
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


## Points that watch the sea for a side: bases (400 nm of air search) and held islands (250 nm).
func _spot_points(side: String) -> Array:
	var out := []
	for nm in _active_bases(side):
		out.append([War.BASES[nm].lon, War.BASES[nm].lat, 400.0])
	for iid in C.islands:
		if C.islands[iid].side == side:
			out.append([Geo.ISLANDS[iid].lon, Geo.ISLANDS[iid].lat, 250.0])
	return out


## Islands at the front get a guard group of their holder's side now and then.
func _spawn_guards() -> void:
	if _rng.randf() > 0.04:
		return
	var fronts := _front_zones()
	var cands := []
	for iid in C.islands:
		var isl: Dictionary = Geo.ISLANDS[iid]
		if not fronts.has(isl.zone):
			continue
		var side: String = C.islands[iid].side
		var has_guard := false
		for g in C.groups:
			if g.get("guard", "") == iid:
				has_guard = true
		if not has_guard:
			cands.append(iid)
	if cands.is_empty():
		return
	var iid: String = cands[_rng.randi() % cands.size()]
	var side: String = C.islands[iid].side
	var n_side := 0
	for g in C.groups:
		if g.side == side:
			n_side += 1
	if n_side >= MAX_GROUPS + 2:
		return
	var isl: Dictionary = Geo.ISLANDS[iid]
	var year := War.year_of(int(C.day))
	var home := _base_weighted(side, isl.lon, isl.lat)
	if home == "":
		return
	var kind: String = "patrol" if side == "us" else (["express", "picket", "boats"][_rng.randi() % 3])
	var g := _make_group(side, home, [isl.lon + 0.3, isl.lat], false, year, kind)
	if g.is_empty():
		return
	g.guard = iid
	g.lon = isl.lon + 0.4; g.lat = isl.lat - 0.2
	# a short place name for the guard or patrol (the full one is on the island itself)
	var short: String = isl.base if isl.base != "" else isl.name.get_slice(" (", 0).get_slice(" and ", 0)
	g.name = "%s guard" % short if side == "ijn" else "%s patrol" % short
	C.groups.append(g)


func _compass(lon1: float, lat1: float, lon2: float, lat2: float) -> String:
	var dx := (lon2 - lon1) * cos(deg_to_rad(lat1))
	var dy := lat2 - lat1
	var a := fposmod(rad_to_deg(atan2(dx, dy)), 360.0)
	return ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][int(round(a / 45.0)) % 8]


## Warships hunt what they can see: our task forces and patrols go for enemy groups nearby,
## Japanese raiders go for our convoys.
func _hunt() -> void:
	for g in C.groups:
		if g.state != "sail" or g.kind in ["convoy", "barges", "sub", "carriers", "picket"]:
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


## A promotion brings a letter from Naval Command offering ships for the fleet; the player picks one.
func _check_offers() -> void:
	var c: Dictionary = Game.career
	# older careers: rank already earned from experience stays, reputation takes over from here
	Career.check_promotion(c, [])
	var offers: Array = c.get("offers", [])
	if offers.is_empty() or card != null:
		return
	var rank: int = int(offers[0])
	var year := War.year_of(int(C.day))
	var opts := Career.offer_options(rank, year)
	speed_i = 0
	Audio.ui("radio", 0.7, "Radio")
	card = Control.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(UI.backdrop(0.5))
	var p := UI.panel(22)
	p.custom_minimum_size.x = 640
	var v := UI.column(8)
	v.add_child(UI.label("LETTER FROM COMMANDER IN CHIEF, PACIFIC FLEET · %s" % War.date_str(int(C.day)), 11, UI.BRASS))
	v.add_child(UI.label("Promoted to %s" % Missions.RANKS[clampi(rank, 0, 8)], 26))
	v.add_child(UI.wrap("%s %s,\n\nIn recognition of your conduct in command, you are promoted to the rank of %s with effect from this date. The service has asked a great deal of you and your ship's company, and you have given it.\n\nWith the rank comes a larger command. The following are available to join your force; signal your choice and they will report to you at once." % [Missions.RANKS[clampi(rank, 0, 8)], Career.captain_name(c), Missions.RANKS[clampi(rank, 0, 8)]], 600))
	for opt in opts:
		var b := UI.big_button("Take %s" % Career.describe_offer(opt), (func(o2): _accept_offer(o2)).bind(opt))
		v.add_child(b)
	v.add_child(UI.wrap("Ships that join sail with you on the map and fight under your orders until they are lost.", 600, 12, UI.MUTED))
	p.add_child(v)
	card.add_child(p)
	UI.center(p)
	add_child(card)


func _accept_offer(opt: Array) -> void:
	var c: Dictionary = Game.career
	var offers: Array = c.get("offers", [])
	if not offers.is_empty():
		offers.pop_front()
	var joined := []
	for tid in opt:
		var nm: String = _free_name(tid)
		C.squadron.append([tid, nm])
		joined.append("%s (%s)" % [nm, Data.TYPES[tid].name])
	_log("Reporting for duty: %s." % ", ".join(joined))
	_close_card()
	Game.save_career()
	_save()
	_refresh_side()
	_refresh_top()
	_check_offers.call_deferred()


## Career: in port it is the officers on the quay; at sea the career screen.
func _open_career() -> void:
	if _port_here() != "":
		open_dock(0)
	else:
		add_child(CareerPanel.new())


## The home base: the ship alongside the quay, the officers, the yard's business.
func open_dock(select := -1) -> void:
	var port := _port_here()
	if port == "" or get_node_or_null("Dock") != null:
		return
	speed_i = 0
	var d := DockPanel.new(self, port)
	d.name = "Dock"
	add_child(d)
	if select != -1:
		d._select.call_deferred(select)


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


## Assault an enemy-held island: a bombardment action against its batteries.
func _assault(iid: String, sg = null) -> void:
	var isl: Dictionary = Geo.ISLANDS[iid]
	var st := _island_def(iid)
	var friends: Array = C.squadron.duplicate(true)
	var ag = _group(C.attached)
	if ag != null:
		for sh in ag.ships:
			if Data.TYPES[sh[0]].get("cls", "") != "merchant":
				friends.append(sh)
	var sgid := ""
	if sg != null:
		# our landing force already at the island fights alongside
		var lg = _group(sg.gid)
		if lg != null and lg != ag:
			for sh in lg.ships:
				if Data.TYPES[sh[0]].get("cls", "") != "merchant" and friends.size() < 12:
					friends.append(sh)
		sgid = sg.id
	var defence := {"fleet": st.get("fleet", []), "af": st.get("af", false), "planes": int(st.get("planes", 0))}
	var plan := Missions.island_assault(_rng, isl, int(st.garrison), friends, C.ship, C.name, "clear" if _rng.randf() < 0.7 else "overcast", st.side, defence)
	_launch(plan, "assault", iid, "", ag.id if ag != null else "", {"siege": sgid, "siege_gid": sg.gid if sg != null else ""})


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


func _launch(plan: Dictionary, kind: String, ref: String, enemy_gid: String, friend_gid: String, extra := {}) -> void:
	var zone := ""
	var bd := 1e9
	for zid in War.ZONES:
		var z: Dictionary = War.ZONES[zid]
		var d := War.dist_nm(C.lon, C.lat, z.lon, z.lat)
		if d < bd:
			bd = d; zone = zid
	Game.mission = {"plan": plan, "weather": plan.weather, "kind": kind, "ref": ref, "zone": zone, "day": C.day, "enemy_gid": enemy_gid, "friend_gid": friend_gid}
	Game.mission.merge(extra)
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
	if m.get("kind", "") == "assault" and Geo.ISLANDS.has(m.get("ref", "")):
		var iid: String = m.ref
		var st := _island_def(iid)
		var land: Array = r.get("land", [])
		# the defences lose what was destroyed, whether or not the island falls
		var g_n: int = int(st.garrison)
		st.fleet = st.get("fleet", []).filter(func(sh): return not sunk.has(sh[1]))
		var bat_lost := land.filter(func(n): return String(n).begins_with("Battery")).size()
		st.garrison = maxi(1, int(st.garrison) - bat_lost)
		if land.has(Missions.airfield_name(iid)):
			st.af = false
			st.af_fix = C.day + 12.0
			st.planes = 0
		var lg = _group(m.get("siege_gid", ""))
		if lg != null:
			lg.ships = lg.ships.filter(func(sh): return not lost_friends.has(sh[1]))
		var tier := island_tier(iid)
		if r.get("over", "") == "won":
			_capture(iid, "us", "Our landing force")
			var rep: int = 60 * g_n + 80 * tier + (120 if Geo.ISLANDS[iid].key else 0)
			Game.career.reputation += rep
			_log("Reputation +%d for %s." % [rep, Geo.ISLANDS[iid].name])
			if lg != null:
				lg.state = "sail"; lg.erase("siege"); lg.erase("assault")
		else:
			var left := []
			if not st.fleet.is_empty():
				left.append("%d warships" % st.fleet.size())
			left.append("%d batter%s" % [int(st.garrison), "y" if int(st.garrison) == 1 else "ies"])
			if st.get("af", false) and Missions.has_airfield(iid):
				left.append("the airfield")
			_log("The assault on %s failed. Still holding out: %s." % [Geo.ISLANDS[iid].name, ", ".join(left)])
			if lg != null and _siege_of(iid) != null:
				lg.state = "siege"
	if m.get("kind", "") == "defend" and Geo.ISLANDS.has(m.get("ref", "")):
		var iid2: String = m.ref
		var st2 := _island_def(iid2)
		var lost_land: Array = r.get("lost_land", [])
		st2.garrison = maxi(1, int(st2.garrison) - lost_land.filter(func(n): return String(n).begins_with("Battery")).size())
		if lost_land.has(Missions.airfield_name(iid2)):
			st2.af = false
			st2.af_fix = C.day + 10.0
			st2.planes = 0
		var sg2 = _siege_of(iid2)
		var ig = _group(m.get("enemy_gid", ""))
		if r.get("over", "") == "won":
			if sg2 != null:
				C.sieges.erase(sg2)
			if ig != null:
				C.groups.erase(ig)
			Game.career.reputation += 100 + 60 * island_tier(iid2)
			_log("The invasion of %s has been beaten off. The island is still ours. Reputation +%d." % [Geo.ISLANDS[iid2].name, 100 + 60 * island_tier(iid2)])
		elif ig != null and sg2 != null:
			ig.state = "siege"
			_log("The Japanese are still landing on %s; the garrison fights on." % Geo.ISLANDS[iid2].name)
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
	c.reputation = maxi(0, c.reputation - int(150 * (1.0 - Career.mod("survive"))))
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


func _draw_map() -> void:
	var font = ThemeDB.fallback_font
	var vs := map.size
	# zones first, tinted by owner
	# one name per place: islands and bases carry their own labels, so a zone or base
	# that shares the name keeps quiet
	var named := {}
	for iid in Geo.ISLANDS:
		named[Geo.ISLANDS[iid].name] = true
		if Geo.ISLANDS[iid].base != "":
			named[Geo.ISLANDS[iid].base] = true
	for zid in War.ZONES:
		var z: Dictionary = War.ZONES[zid]
		var c := _to_px(z.lon, z.lat)
		var r: float = z.r / 60.0 * zoom
		var own := War.owner(zid, C.day, C.shift)
		var act := War.activity(zid, C.day, C.shift)
		var col := Color(0.85, 0.3, 0.25, 0.10 + 0.12 * act) if own == "ijn" else Color(0.35, 0.65, 0.95, 0.06 + 0.06 * act)
		map.draw_circle(c, r, col)
		map.draw_arc(c, r, 0, TAU, 48, Color(col, 0.5), 1.0)
		if not named.has(z.name) and not War.BASES.has(z.name):
			map.draw_string(font, c + Vector2(-r * 0.5, -r * 0.7), z.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.55))
	# land: a pale shelf, then the coast
	for nm in Geo.LAND:
		var pts := PackedVector2Array()
		for p in Geo.LAND[nm]:
			pts.append(_to_px(Geo.lon_fix(p[0]), p[1]))
		if pts.size() >= 3:
			map.draw_colored_polygon(pts, Color(0.30, 0.36, 0.24))
			map.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.62, 0.66, 0.5, 0.9), 1.5)
	for d in Geo.DOTS:
		var pd := _to_px(Geo.lon_fix(d[0]), d[1])
		var rr: float = maxf(2.0, d[2] / 60.0 * zoom)
		map.draw_circle(pd, rr + 1.5, Color(0.5, 0.62, 0.62, 0.35))   # reef
		map.draw_circle(pd, rr, Color(0.32, 0.38, 0.26))
	# islands that can be taken: a flag in the holder's colour, pips for the garrison
	for iid in Geo.ISLANDS:
		var isl: Dictionary = Geo.ISLANDS[iid]
		var st: Dictionary = C.islands.get(iid, {})
		var p := _to_px(isl.lon, isl.lat)
		var us_held: bool = st.get("side", "ijn") == "us"
		var col := Color(0.55, 0.85, 1.0) if us_held else Color(0.95, 0.45, 0.35)
		if iid == selected:
			col = UI.BRASS
		map.draw_line(p + Vector2(-5, 6), p + Vector2(-5, -12), Color(0.9, 0.9, 0.85), 1.5)
		map.draw_colored_polygon(PackedVector2Array([p + Vector2(-5, -12), p + Vector2(6, -9), p + Vector2(-5, -5)]), col)
		var g: int = int(st.get("garrison", isl.garrison))
		for k in g:
			map.draw_rect(Rect2(p + Vector2(-5 + k * 4, 8), Vector2(3, 3)), col)
		if zoom > 6.0 or iid == selected:
			map.draw_string(font, p + Vector2(9, -2), isl.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col, 0.9))
	# bases
	for nm in War.BASES:
		var b: Dictionary = War.BASES[nm]
		var us: bool = _base_side(nm) == "us"
		var p := _to_px(b.lon, b.lat)
		var col := Color(0.55, 0.85, 1.0) if us else Color(0.95, 0.45, 0.35)
		map.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), col)
		if zoom > 7.0 and not named.has(nm):
			map.draw_string(font, p + Vector2(7, 4), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col, 0.9))
	# radar stations on the islands we have taken: a faint ring of what they watch
	for iid in C.islands:
		var rst: Dictionary = C.islands[iid]
		if rst.side == "us" and rst.get("radar_on", false):
			var rp := _to_px(Geo.ISLANDS[iid].lon, Geo.ISLANDS[iid].lat)
			var rr: float = RADAR_NM / 60.0 * zoom
			map.draw_circle(rp, rr, Color(0.45, 0.9, 0.85, 0.035))
			map.draw_arc(rp, rr, 0, TAU, 64, Color(0.45, 0.9, 0.85, 0.35), 1.2)
			# the sweep
			var sw := fposmod(Time.get_ticks_msec() / 1400.0 + iid.hash() % 7, TAU)
			map.draw_line(rp, rp + Vector2(sin(sw), -cos(sw)) * rr, Color(0.45, 0.9, 0.85, 0.25), 1.0)
	# islands under attack: a pulsing ring and the days the garrison has left
	for sg in C.sieges:
		var ip := _to_px(Geo.ISLANDS[sg.iid].lon, Geo.ISLANDS[sg.iid].lat)
		var pulse := 16.0 + 5.0 * sin(Time.get_ticks_msec() / 220.0)
		var scol := Color(1.0, 0.45, 0.3) if sg.side == "ijn" else Color(1.0, 0.8, 0.35)
		map.draw_arc(ip, pulse, 0, TAU, 32, Color(scol, 0.85), 2.0)
		map.draw_arc(ip, pulse + 6.0, 0, TAU, 32, Color(scol, 0.35), 1.0)
		var lt := "INVASION · %.1f days" % maxf(0.0, float(sg.ends) - C.day) if sg.side == "ijn" else "LANDING · %.1f days" % maxf(0.0, float(sg.ends) - C.day)
		map.draw_string(font, ip + Vector2(14, 18), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, scol)
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
			if not Geo.on_land(w.x, w.y):
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
	# a group, battle or island under the mouse selects it; otherwise set course
	for iid in Geo.ISLANDS:
		var isl: Dictionary = Geo.ISLANDS[iid]
		if _to_px(isl.lon, isl.lat).distance_to(pos + Vector2(0, 4)) < 12.0:
			selected = iid
			_refresh_side()
			return
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
	if Geo.on_land(w.x, w.y):
		_log("That is land. Click the sea to set a course.")
		return
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
