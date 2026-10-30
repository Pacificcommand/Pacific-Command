class_name Missions
## Mission types, threat ratings and reputation-bought support ships (design doc: Missions).
## The hand-written missions live in battle.gd (_setup_*); the three new types here (convoy
## escort, shore bombardment, rescue) are built from a plan dictionary by build(), which the
## operations map will also use to make missions from the war's state.

## Points per ship class for the threat rating.
const THREAT_PTS := {"pt": 0.3, "barge": 0.15, "merchant": 0.3, "de": 1.0, "dd": 1.5, "ss": 1.5, "cl": 4.0, "ca": 6.0, "bb": 12.0, "cv": 12.0, "cvl": 7.0, "cve": 4.0, "fort": 2.0, "raft": 0.0}

## Threat from a list of enemy class ids (plus weather and air cover): [level 1-5, label].
static func threat(enemy_types: Array, weather: String, air_cover := false) -> Array:
	var pts := 0.0
	for tid in enemy_types:
		var T: Dictionary = Data.TYPES.get(tid, {})
		pts += THREAT_PTS.get(T.get("cls", "dd"), 1.0)
	if weather == "night":
		pts *= 1.25
	if air_cover:
		pts *= 1.3
	var level := 1
	if pts >= 3.0: level = 2
	if pts >= 8.0: level = 3
	if pts >= 16.0: level = 4
	if pts >= 32.0: level = 5
	return [level, ["Low", "Moderate", "High", "Severe", "Extreme"][level - 1]]

## Reputation earned for a won mission of a given threat level.
static func reward(level: int, sunk_tons: float) -> int:
	return level * 80 + int(sunk_tons / 400.0)

## Ranks and how many ships you may bring into a battle at each (design doc: Fleet command).
const RANKS := ["Lieutenant", "Lieutenant Commander", "Commander", "Captain", "Commodore", "Rear Admiral", "Vice Admiral", "Admiral", "Fleet Admiral"]
const RANK_CAP := [1, 3, 4, 6, 8, 10, 14, 18, 24]

## Support ships that reputation can buy: [type, label, cost, year available]. Only ships in
## service at the mission's date can come, and the total is capped by rank.
const SUPPORT := [
	["fletcher", "Fletcher-class destroyer", 140, 1942], ["benson", "Benson-class destroyer", 110, 1941], ["mahan", "Mahan-class destroyer", 90, 1941],
	["buckley", "Buckley-class destroyer escort", 80, 1943], ["atlanta", "Atlanta-class AA cruiser", 320, 1942], ["cleveland", "Cleveland-class light cruiser", 420, 1942],
	["brooklyn", "Brooklyn-class light cruiser", 380, 1941], ["northampton", "Northampton-class heavy cruiser", 460, 1941], ["new_orleans", "New Orleans-class heavy cruiser", 500, 1941],
	["baltimore", "Baltimore-class heavy cruiser", 620, 1943], ["north_carolina", "North Carolina-class battleship", 1100, 1941], ["south_dakota", "South Dakota-class battleship", 1200, 1942],
	["iowa", "Iowa-class battleship", 1500, 1943], ["texas", "USS Texas (old battleship)", 700, 1941], ["casablanca", "Casablanca-class escort carrier", 600, 1943],
	["independence", "Independence-class light carrier", 900, 1943], ["yorktown", "Yorktown-class carrier", 1300, 1941], ["essex", "Essex-class carrier", 1700, 1943],
]

static func support_available(year: int, player_cls: String) -> Array:
	var out := []
	for it in SUPPORT:
		if it[3] > year:
			continue
		# PT boats and submarines work alone; destroyers can't call battleships
		if player_cls in ["pt", "ss"]:
			continue
		var T: Dictionary = Data.TYPES[it[0]]
		if player_cls in ["dd", "de"] and T.cls in ["bb", "cv", "cvl", "essex"]:
			continue
		out.append(it)
	return out


# =====================================================================
# mission plans
# =====================================================================

## A plan: {id, title, kind (sink|protect|rescue|bombard), weather, choices [[type, name]], friends [[type, name, back, side]],
##  enemies [{group, x, z, h, kn, ships [[type, name, back, side]], objective, route, dest, escort}], islands, report, text, escape_r}

static func convoy_escort(rng: RandomNumberGenerator) -> Dictionary:
	var ch := deg_to_rad(300.0 + rng.randf_range(-15.0, 15.0))
	var brg := deg_to_rad(330.0 + rng.randf_range(-25.0, 25.0))
	var dist := rng.randf_range(11000.0, 13000.0)
	return {"id": "escort", "title": "Convoy escort", "kind": "protect", "weather": "night",
		"choices": [["fletcher", "USS Nicholas (Fletcher)"], ["benson", "USS Woodworth (Benson)"], ["buckley", "USS England (Buckley)"]],
		"friends": [["buckley", "USS Raby", 2400.0, 2200.0]],
		"convoy": {"ships": [["liberty", "SS John Adams", 0.0, 0.0], ["liberty", "SS Daniel Boone", -700.0, 600.0], ["liberty", "SS Meriwether Lewis", -700.0, -600.0], ["liberty", "SS Star of Oregon", -1400.0, 0.0]],
			"x": -1800.0, "z": 1400.0, "h": ch, "kn": 10.0, "dest": 15000.0},
		"enemies": [{"group": "Raiders", "x": sin(brg) * dist, "z": -cos(brg) * dist, "h": fposmod(brg + PI + rng.randf_range(-0.2, 0.2), TAU), "kn": 28.0,
			"ships": [["fubuki", "Shirakumo", 0.0, 0.0], ["fubuki", "Murakumo", 700.0, 300.0], ["kagero", "Arashi", 1400.0, -300.0]], "objective": false},
			{"group": "", "x": sin(ch) * 6000.0 - 1800.0, "z": -cos(ch) * 6000.0 + 1400.0, "h": fposmod(ch + PI, TAU), "kn": 3.0, "ships": [["i_boat", "I-19", 0.0, 0.0]], "sub": true}],
		"report": {"brg": brg, "dist": dist, "h": fposmod(brg + PI, TAU), "kn": 28.0, "r": 3000.0},
		"escape_r": 24000.0,
		"text": "Four Liberty ships with supplies for the Marines are steaming %s at 10 knots. A coastwatcher reports three Japanese destroyers bearing %s, about %s away, coming to get them, and there may be a submarine on the route.\n\nYou command %s with USS Raby on the convoy's other flank. Keep between the raiders and the merchantmen, use your radar to open fire first, lay smoke to hide the convoy, and listen on sonar. The convoy must reach safety; the mission is won when it gets through or the raiders are sunk or driven off."}


static func shore_bombardment(rng: RandomNumberGenerator) -> Dictionary:
	var ib := deg_to_rad(20.0 + rng.randf_range(-20.0, 20.0))
	var idist := 11000.0
	var ix := sin(ib) * idist
	var iz := -cos(ib) * idist
	var r := 2600.0
	var shore := []
	for i in 3:
		var a := ib + PI + deg_to_rad(-40.0 + i * 40.0)   # on the side facing us
		shore.append([["shore_battery", "shore_battery", "supply_dump"][i], ["Battery A", "Battery B", "Supply dump"][i], ix + sin(a) * r * (0.78 if i < 2 else 0.5), iz - cos(a) * r * (0.78 if i < 2 else 0.5)])
	return {"id": "bombard", "title": "Shore bombardment", "kind": "bombard", "weather": "clear",
		"choices": [["cleveland", "USS Columbia (Cleveland)"], ["brooklyn", "USS Honolulu (Brooklyn)"], ["texas", "USS Texas"], ["north_carolina", "USS Washington (North Carolina)"]],
		"friends": [["fletcher", "USS Charles Ausburne", 900.0, -700.0], ["fletcher", "USS Dyson", 900.0, 700.0]],
		"islands": [{"x": ix, "z": iz, "r": r, "h": 140.0, "seed": rng.randi() % 1000}],
		"shore": shore,
		"enemies": [{"group": "", "x": ix + sin(ib + PI / 2) * (r * 1.45), "z": iz - cos(ib + PI / 2) * (r * 1.45), "h": fposmod(ib + PI, TAU), "kn": 7.0,
			"ships": [["daihatsu", "Barge 1", 0.0, 0.0], ["daihatsu", "Barge 2", 120.0, 60.0], ["daihatsu_gun", "Barge 3", 240.0, -60.0]], "objective": false, "route": true, "dest": 6000.0}],
		"report": {"brg": ib, "dist": idist, "h": 0.0, "kn": 0.0, "r": 2000.0, "fixed": true},
		"escape_r": 30000.0,
		"text": "The landing goes in at dawn. Our troops want the two coastal batteries on the island bearing %s, about %s away, silenced, and the supply dump behind the beach destroyed. The batteries are 14 cm guns in concrete; they will shoot back, and the water shoals close inshore.\n\nYou command %s with two destroyers. Steam in to gun range, pick each battery as your target and pound it; the destroyers will deal with any barges. Watch your depth: ground the ship and you are a sitting target."}


static func rescue(rng: RandomNumberGenerator) -> Dictionary:
	var b := deg_to_rad(60.0 + rng.randf_range(-20.0, 20.0))
	var rafts := []
	for i in 3:
		var a := b + rng.randf_range(-0.12, 0.12)
		var d := rng.randf_range(5500.0, 7500.0)
		rafts.append(["raft", ["Raft 1", "Raft 2", "Raft 3"][i], sin(a) * d, -cos(a) * d])
	var eb := deg_to_rad(20.0 + rng.randf_range(-10.0, 10.0))
	return {"id": "rescue", "title": "Rescue", "kind": "rescue", "weather": "clear",
		"choices": [["fletcher", "USS Taylor (Fletcher)"], ["pt_elco", "PT-109 (Elco)"], ["mahan", "USS Dunlap (Mahan)"]],
		"friends": [],
		"rafts": rafts,
		"islands": [{"x": sin(b) * 11000.0, "z": -cos(b) * 11000.0, "r": 3200.0, "h": 220.0, "seed": rng.randi() % 1000}],
		"enemies": [{"group": "", "x": sin(eb) * 15000.0, "z": -cos(eb) * 15000.0, "h": fposmod(eb + PI, TAU), "kn": 24.0, "ships": [["fubuki", "Ushio", 0.0, 0.0]], "objective": false, "delay": 240.0}],
		"report": {"brg": b, "dist": 6500.0, "h": 0.0, "kn": 0.0, "r": 1500.0, "fixed": true},
		"escape_r": 30000.0,
		"text": "A PBY has spotted survivors in the water bearing %s, about %s away, off an enemy-held island: the crew of a bomber and men from the destroyer sunk here last night. A Japanese destroyer patrols these waters.\n\nYou command %s. Find the rafts (they drift), come alongside each one slowly (under 5 knots, within 60 yards) to take the men aboard, and get them home. If the Japanese destroyer turns up, decide whether to fight or run with the men you have."}


## Build a plan into a battle. B is battle.gd.
static func build(B, plan: Dictionary, choice: String) -> void:
	var pc: Array = plan.choices[0]
	for c in plan.choices:
		if c[0] == choice:
			pc = c
	var team_plan: Array = [[pc[0], pc[1].split(" (")[0], 0.0, 0.0]] + plan.friends
	var tf: Array = B._formation(team_plan, "us", "TF", 0.0, 0.0, deg_to_rad(0.0), 20.0)
	B.player = tf[0]
	if plan.has("convoy"):
		var cv: Dictionary = plan.convoy
		var ships: Array = B._formation(cv.ships, "us", "Convoy", cv.x, cv.z, cv.h, cv.kn, true)
		for sh in ships:
			sh.group = ""
			sh.route_h = cv.h
			sh.dest_dist = cv.dest
			sh.tele = 2
			sh.protect = true
		for f in tf:
			if f != B.player:
				f.group = ""
				f.escort_group = "convoy"
				f.route_h = cv.h
	if plan.has("islands"):
		B.terrain.setup(plan.islands)
	for sd in plan.get("shore", []):
		var s: Ship = B._add_ship(sd[0], "ijn", sd[1], sd[2], sd[3], 0.0, 0.0)
		s.objective = true
		s.tele = 1
	for rd in plan.get("rafts", []):
		var r: Ship = B._add_ship(rd[0], "us", rd[1], rd[2], rd[3], 0.0, 0.0)
		r.objective = true
		r.tele = 1
	for e in plan.enemies:
		if e.get("delay", 0.0) > 0.0:
			var ee: Dictionary = e
			B.after(e.delay, func(): _spawn_group(B, ee))
		else:
			_spawn_group(B, e)
	var rp: Dictionary = plan.report
	B.report = {"x": sin(rp.brg) * rp.dist + randf_range(-800, 800), "z": -cos(rp.brg) * rp.dist + randf_range(-800, 800), "h": rp.h, "v": rp.kn * Data.KN, "r": rp.r, "t": 0.0, "active": true}
	var enemy_types := []
	for e in plan.enemies:
		for sh in e.ships:
			enemy_types.append(sh[0])
	for sd in plan.get("shore", []):
		enemy_types.append(sd[0])
	var th := threat(enemy_types, B.weather)
	var args := [U.deg3(rp.brg), U.yards(rp.dist), B.player.ship_name]
	if plan.id == "escort":
		args = [U.deg3(plan.convoy.h)] + args
	B.brief = {"title": plan.title, "escape_r": plan.escape_r, "threat": th[1], "level": th[0], "goal": plan.kind, "ships": plan.choices, "text": plan.text % args}


static func _spawn_group(B, e: Dictionary) -> void:
	var ships: Array = B._formation(e.ships, "ijn", e.group, e.x, e.z, e.h, e.kn, e.get("objective", true))
	for sh in ships:
		if e.get("route", false):
			sh.route_h = e.h
			sh.dest_dist = e.get("dest", 10000.0)
			sh.tele = 2
		if e.get("sub", false):
			sh.depth = 1
			sh.depth_m = B.DEPTHS[1]
			sh.route_h = e.h
			sh.tele = 2
		if e.group == "":
			sh.group = ""
	if B.started and not ships.is_empty():
		B.say("New contact reported: %s bearing %s." % [ships[0].T.name, U.deg3(B.player.bearing_to(ships[0].x, ships[0].z))], "bad")
