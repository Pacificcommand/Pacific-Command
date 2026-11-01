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
		if e.get("escort", false):
			sh.escort_group = "convoy"
			sh.route_h = e.h
			sh.tele = 2
		if e.group == "":
			sh.group = ""
	if B.started and not ships.is_empty():
		B.say("New contact reported: %s bearing %s." % [ships[0].T.name, U.deg3(B.player.bearing_to(ships[0].x, ships[0].z))], "bad")


# =====================================================================
# plans generated for the operations map
# =====================================================================

static func _enemy_dds(rng: RandomNumberGenerator, n: int, year: int) -> Array:
	var names := ["Amagiri", "Hatsuyuki", "Yukikaze", "Hamakaze", "Shigure", "Ayanami", "Uranami", "Nowaki", "Akizuki", "Suzutsuki", "Kagero", "Fubuki", "Shirayuki"]
	var out := []
	for i in n:
		var tid := "kagero" if rng.randf() < 0.5 else "fubuki"
		if year >= 1943 and rng.randf() < 0.2:
			tid = "akizuki"
		out.append([tid, names[(rng.randi() % names.size() + i) % names.size()], 800.0 * i, (300.0 if i % 2 == 1 else -300.0) * (1 if i > 0 else 0)])
	return out

static func _choices(ship_type: String, ship_name: String) -> Array:
	return [[ship_type, ship_name]]

static func _report(brg: float, dist: float, h: float, kn: float, r: float) -> Dictionary:
	return {"brg": brg, "dist": dist, "h": h, "kn": kn, "r": r}

## Tokyo Express: destroyers (a light cruiser leading when strong) on a night supply run.
static func tokyo_express(rng: RandomNumberGenerator, strength: float, year: int, ship_type: String, ship_name: String) -> Dictionary:
	var brg := rng.randf_range(0.0, TAU)
	var dist := rng.randf_range(12000.0, 15000.0)
	var n := clampi(int(2 + strength * 3), 2, 6)
	var ships := _enemy_dds(rng, n, year)
	if strength > 1.2:
		ships.insert(0, ["nagara", "Jintsu", 0.0, 0.0])
		for i in range(1, ships.size()):
			ships[i][2] += 800.0
	var h := fposmod(brg + PI + rng.randf_range(-0.4, 0.4), TAU)
	return {"id": "express", "title": "Tokyo Express interception", "kind": "sink", "weather": "night", "choices": _choices(ship_type, ship_name), "friends": [],
		"enemies": [{"group": "Reinforcement Group", "x": sin(brg) * dist, "z": -cos(brg) * dist, "h": h, "kn": 28.0, "ships": ships, "objective": true, "route": true, "dest": 30000.0}],
		"report": _report(brg, dist, h, 28.0, 3000.0), "escape_r": 26000.0,
		"text": "Coastwatchers report a Tokyo Express run bearing %s, about %s away: destroyers at high speed with troops and supplies for the garrison. Stop them.\n\nYou command %s. The run is over if they pass out of reach; the night is theirs if their torpedoes find you first."}

## A merchant convoy with escorts to sink.
static func convoy_attack(rng: RandomNumberGenerator, strength: float, year: int, ship_type: String, ship_name: String) -> Dictionary:
	var brg := rng.randf_range(0.0, TAU)
	var dist := rng.randf_range(8000.0, 11000.0)
	var h := fposmod(brg + PI + rng.randf_range(-0.5, 0.5), TAU)
	var marus := []
	var mn := ["Kinai Maru", "Nissho Maru", "Taiyo Maru", "Hokko Maru", "Toyo Maru", "Yamazuki Maru"]
	var n := clampi(int(2 + strength * 2), 2, 5)
	for i in n:
		marus.append(["tanker_maru" if i == 1 else "cargo_maru", mn[i], -500.0 * i, (250.0 if i % 2 == 1 else -250.0)])
	var escorts := []
	escorts.append(["kagero" if strength > 0.6 else "subchaser", "Shigure" if strength > 0.6 else "CH-18", 900.0, -900.0])
	if strength > 1.0:
		escorts.append(["subchaser", "CH-24", -1800.0, 800.0])
	return {"id": "convoy", "title": "Convoy attack", "kind": "sink", "weather": "night" if rng.randf() < 0.6 else "overcast", "choices": _choices(ship_type, ship_name), "friends": [],
		"enemies": [{"group": "", "x": sin(brg) * dist, "z": -cos(brg) * dist, "h": h, "kn": 9.0, "ships": marus, "objective": true, "route": true, "dest": 20000.0},
			{"group": "", "x": sin(brg) * dist, "z": -cos(brg) * dist, "h": h, "kn": 9.0, "ships": escorts, "objective": false, "escort": true}],
		"report": _report(brg, dist, h, 9.0, 2500.0), "escape_r": 24000.0,
		"text": "A convoy of Japanese merchant ships bearing %s, about %s away, is carrying fuel and supplies to the front, with an escort.\n\nYou command %s. Sink the merchantmen; the escort will try to drive you off."}

## A surface task force: cruisers, with battleships when strong.
static func task_force(rng: RandomNumberGenerator, strength: float, year: int, ship_type: String, ship_name: String) -> Dictionary:
	var brg := rng.randf_range(0.0, TAU)
	var dist := rng.randf_range(16000.0, 20000.0)
	var h := fposmod(brg + PI + rng.randf_range(-0.5, 0.5), TAU)
	var ships := []
	var cas := ["takao", "myoko", "mogami", "tone"]
	var ca_names := ["Atago", "Haguro", "Suzuya", "Chikuma", "Nachi", "Chokai"]
	if strength > 1.4:
		ships.append([["kongo", "fuso", "nagato", "yamato"][mini(3, int(strength - 1.0))], ["Kongo", "Fuso", "Nagato", "Yamato"][mini(3, int(strength - 1.0))], 0.0, 0.0])
	var nca := clampi(int(strength * 2), 1, 4)
	for i in nca:
		ships.append([cas[rng.randi() % cas.size()], ca_names[i], 1200.0 * (i + ships.size()), (600.0 if i % 2 == 0 else -600.0)])
	for d in _enemy_dds(rng, 2 + int(strength), year):
		ships.append([d[0], d[1], -2500.0 - d[2] * 0.5, d[3] * 2.5])
	return {"id": "taskforce", "title": "Task force action", "kind": "sink", "weather": ["clear", "overcast", "night"][rng.randi() % 3], "choices": _choices(ship_type, ship_name), "friends": [],
		"enemies": [{"group": "Striking Force", "x": sin(brg) * dist, "z": -cos(brg) * dist, "h": h, "kn": 24.0, "ships": ships, "objective": true}],
		"report": _report(brg, dist, h, 24.0, 4500.0), "escape_r": 34000.0,
		"text": "Scout planes report a Japanese surface force bearing %s, about %s away: cruisers with a destroyer screen, perhaps a battleship. Fleet command wants it brought to action.\n\nYou command %s. Bring the support you have paid for, form a line, and fight at the range that suits your guns."}

## A carrier group to strike (for carrier captains).
static func carrier_force(rng: RandomNumberGenerator, strength: float, year: int, ship_type: String, ship_name: String) -> Dictionary:
	var brg := rng.randf_range(0.0, TAU)
	var dist := rng.randf_range(28000.0, 34000.0)
	var h := fposmod(brg + PI + rng.randf_range(-0.5, 0.5), TAU)
	var ships := [["shokaku", "Shokaku", 0.0, 0.0]]
	if strength > 0.8:
		ships.append(["hiryu" if year <= 1942 else "zuiho", "Hiryu" if year <= 1942 else "Zuiho", 1500.0, 1800.0])
	if strength > 1.3:
		ships.append(["kaga" if year <= 1942 else "shokaku", "Kaga" if year <= 1942 else "Zuikaku", 1500.0, -1800.0])
	ships.append(["tone", "Tone", -2500.0, -1500.0])
	for d in _enemy_dds(rng, 2, year):
		ships.append([d[0], d[1], -3500.0 - d[2] * 0.5, d[3] * 3.0])
	return {"id": "cvstrike", "title": "Carrier strike", "kind": "sink", "weather": "clear", "choices": _choices(ship_type, ship_name), "friends": [["cleveland", "USS Santa Fe", 1200.0, -1500.0], ["fletcher", "USS Dewey", -2200.0, 1000.0]],
		"enemies": [{"group": "Carrier Division", "x": sin(brg) * dist, "z": -cos(brg) * dist, "h": h, "kn": 20.0, "ships": ships, "objective": true}],
		"report": _report(brg, dist, h, 20.0, 6000.0), "escape_r": 60000.0,
		"text": "A search plane has found Japanese carriers bearing %s, about %s away. They will have seen it too; the first strike home wins.\n\nYou command %s. Launch (L) at the reported position, keep fighters up, and set the AA guns to protect the carrier."}

## One or two submarines on the route (for escorts and destroyers).
static func sub_contact(rng: RandomNumberGenerator, strength: float, year: int, ship_type: String, ship_name: String) -> Dictionary:
	var subs := []
	var n := 2 if strength > 0.8 else 1
	for i in n:
		var brg := rng.randf_range(0.0, TAU)
		var d := rng.randf_range(5000.0, 8000.0)
		subs.append({"group": "", "x": sin(brg) * d, "z": -cos(brg) * d, "h": fposmod(brg + PI, TAU), "kn": 3.0, "ships": [["i_boat", ["I-175", "I-26", "I-19"][i], 0.0, 0.0]], "objective": true, "sub": true})
	return {"id": "subhunt", "title": "Submarine hunt", "kind": "sink", "weather": "clear", "choices": _choices(ship_type, ship_name), "friends": [["buckley", "USS Raby", 2200.0, 2200.0]],
		"enemies": subs, "report": _report(subs[0].h + PI, 6500.0, 0.0, 3.0, 4000.0), "escape_r": 30000.0,
		"text": "Direction-finding puts a Japanese submarine roughly bearing %s, about %s away, on the convoy route.\n\nYou command %s with USS Raby. Find it on sonar and sink it with hedgehog and depth charges."}

## A barge column hugging the coast (for PT boats and destroyers).
static func barge_hunt(rng: RandomNumberGenerator, strength: float, year: int, ship_type: String, ship_name: String) -> Dictionary:
	var brg := rng.randf_range(0.0, TAU)
	var dist := rng.randf_range(4500.0, 6000.0)
	var h := fposmod(brg + PI / 2 + rng.randf_range(-0.3, 0.3), TAU)
	var ships := []
	var n := clampi(int(4 + strength * 3), 4, 8)
	for i in n:
		ships.append(["daihatsu_gun" if (i == 0 or i == n - 1) else "daihatsu", "Barge %d" % (i + 1), 140.0 * i, (60.0 if i % 2 == 0 else -60.0)])
	return {"id": "barges", "title": "Barge hunt", "kind": "sink", "weather": "night", "choices": _choices(ship_type, ship_name), "friends": [],
		"enemies": [{"group": "", "x": sin(brg) * dist, "z": -cos(brg) * dist, "h": h, "kn": 7.0, "ships": ships, "objective": true, "route": true, "dest": 9000.0}],
		"report": _report(brg, dist, h, 7.0, 1500.0), "escape_r": 16000.0,
		"text": "A coastwatcher reports landing barges bearing %s, about %s away, creeping along the coast with supplies for the garrison. Some are gun barges.\n\nYou command %s. Sink the supply barges before they reach the beach; torpedoes run under them, so this is a gun fight."}

## Pick a plan for a contact kind.
static func for_contact(kind: String, rng: RandomNumberGenerator, strength: float, year: int, ship_type: String, ship_name: String) -> Dictionary:
	match kind:
		"express": return tokyo_express(rng, strength, year, ship_type, ship_name)
		"convoy": return convoy_attack(rng, strength, year, ship_type, ship_name)
		"taskforce": return task_force(rng, strength, year, ship_type, ship_name)
		"carriers": return carrier_force(rng, strength, year, ship_type, ship_name)
		"sub": return sub_contact(rng, strength, year, ship_type, ship_name)
		"barges": return barge_hunt(rng, strength, year, ship_type, ship_name)
		"bombard":
			var p := shore_bombardment(rng); p.choices = _choices(ship_type, ship_name); p.friends = []; return p
		"rescue":
			var p2 := rescue(rng); p2.choices = _choices(ship_type, ship_name); return p2
		"escort":
			var p3 := convoy_escort(rng); p3.choices = _choices(ship_type, ship_name); return p3
	return tokyo_express(rng, strength, year, ship_type, ship_name)


# =====================================================================
# encounters between groups on the operations map
# =====================================================================

## Threat points of a list of [type, name] ships (for resolving fights the player is not in).
static func group_strength(ships: Array) -> float:
	var pts := 0.0
	for sh in ships:
		var T: Dictionary = Data.TYPES.get(sh[0], {})
		pts += THREAT_PTS.get(T.get("cls", "dd"), 1.0)
	return pts

## Lay out a list of [type, name] ships as a formation: warships in a column, merchants in two
## columns, with escorts to the flanks. Returns [[type, name, back, side], ...].
static func layout(ships: Array, rng: RandomNumberGenerator) -> Array:
	var war := []
	var soft := []
	for sh in ships:
		var T: Dictionary = Data.TYPES.get(sh[0], {})
		if T.get("cls", "dd") in ["merchant", "barge"]:
			soft.append(sh)
		else:
			war.append(sh)
	# biggest ships lead
	war.sort_custom(func(a, b): return float(Data.TYPES[a[0]].get("displacement", 0)) > float(Data.TYPES[b[0]].get("displacement", 0)))
	var out := []
	if soft.is_empty():
		for i in war.size():
			var L: float = Data.TYPES[war[i][0]].get("L", 100.0)
			out.append([war[i][0], war[i][1], 650.0 * i + L * 2.0, 0.0])
	else:
		for i in soft.size():
			out.append([soft[i][0], soft[i][1], 450.0 * int(i / 2), 300.0 if i % 2 == 0 else -300.0])
		for i in war.size():
			var ang := TAU * float(i) / maxf(1.0, war.size())
			out.append([war[i][0], war[i][1], -900.0 + 600.0 * int(i / 2) + 200.0 * soft.size(), (1100.0 if i % 2 == 0 else -1100.0)])
	return out

const GROUP_LABEL := {"convoy": "convoy", "express": "Tokyo Express run", "taskforce": "task force", "carriers": "carrier force", "barges": "barge column", "sub": "submarine", "patrol": "destroyer patrol", "escort": "convoy with escort"}

## A battle between the player's side and an enemy group met on the map.
## `friends`: [type, name] ships sailing with the player (squadron plus any friendly group joined).
## `convoy`: friendly merchant ships to protect (when the player joins a convoy under attack), or [].
static func encounter(rng: RandomNumberGenerator, enemy: Dictionary, friends: Array, convoy: Array, player_type: String, player_name: String, weather: String) -> Dictionary:
	var brg := rng.randf_range(0.0, TAU)
	var ekind: String = enemy.get("kind", "taskforce")
	var eships: Array = enemy.ships
	var big := group_strength(eships) >= 16.0 or ekind == "carriers"
	var dist := rng.randf_range(9000.0, 12000.0)
	if big:
		dist = rng.randf_range(15000.0, 20000.0)
	if ekind == "barges":
		dist = rng.randf_range(4500.0, 6000.0)
	if ekind == "sub":
		dist = rng.randf_range(5000.0, 8000.0)
	var h := fposmod(brg + PI + rng.randf_range(-0.5, 0.5), TAU)
	var kn := 9.0 if ekind in ["convoy"] else (7.0 if ekind == "barges" else (3.0 if ekind == "sub" else 24.0))
	var fl := []
	var fr_ships := layout([[player_type, player_name]] + friends, rng)
	for i in range(1, fr_ships.size()):
		fl.append(fr_ships[i])
	# enemy groups: merchants (objective, routed) and escorts, or one warship group
	var groups := []
	var merch := []
	var esc := []
	for sh in eships:
		if Data.TYPES[sh[0]].get("cls", "dd") in ["merchant", "barge"]:
			merch.append(sh)
		else:
			esc.append(sh)
	var ex := sin(brg) * dist
	var ez := -cos(brg) * dist
	if ekind == "sub":
		for i in esc.size():
			var b2 := rng.randf_range(0.0, TAU)
			var d2 := rng.randf_range(5000.0, 8000.0)
			groups.append({"group": "", "x": sin(b2) * d2, "z": -cos(b2) * d2, "h": fposmod(b2 + PI, TAU), "kn": 3.0, "ships": [[esc[i][0], esc[i][1], 0.0, 0.0]], "objective": true, "sub": true})
	elif not merch.is_empty():
		groups.append({"group": "", "x": ex, "z": ez, "h": h, "kn": kn, "ships": layout(merch, rng), "objective": true, "route": true, "dest": 20000.0})
		if not esc.is_empty():
			var el := []
			for i in esc.size():
				el.append([esc[i][0], esc[i][1], -900.0 + 600.0 * i, 1100.0 if i % 2 == 0 else -1100.0])
			groups.append({"group": "", "x": ex, "z": ez, "h": h, "kn": kn, "ships": el, "objective": false, "escort": true})
	else:
		groups.append({"group": enemy.get("name", "Enemy force"), "x": ex, "z": ez, "h": h, "kn": kn, "ships": layout(esc, rng), "objective": true, "route": ekind == "express", "dest": 30000.0})
	var plan := {"id": "encounter", "title": "%s: %s" % [enemy.get("name", "Enemy"), GROUP_LABEL.get(ekind, ekind)], "kind": "sink", "weather": weather,
		"choices": [[player_type, player_name]], "friends": fl, "enemies": groups,
		"report": _report(brg, dist, h, kn, 2500.0 if not big else 5000.0), "escape_r": 26000.0 if not big else 36000.0,
		"text": "Contact bearing %s, about %s away: " + _enemy_text(ekind) + "\n\nYou command %s" + (" with %d other ship%s in company" % [fl.size(), "" if fl.size() == 1 else "s"] if not fl.is_empty() else "") + "."}
	if not convoy.is_empty():
		# the player's side has merchants to protect: they come under attack from the enemy group
		var ch := rng.randf_range(0.0, TAU)
		plan.kind = "protect"
		plan.title = "Convoy under attack"
		plan.convoy = {"ships": layout(convoy, rng), "x": -sin(ch) * 2500.0, "z": cos(ch) * 2500.0, "h": ch, "kn": 9.0, "dest": 24000.0}
		plan.escape_r = 20000.0
		plan.text = "Enemy ships bearing %s, about %s away, are closing the convoy. Keep them off the merchantmen until the convoy is clear.\n\nYou command %s."
	return plan

static func _enemy_text(kind: String) -> String:
	match kind:
		"convoy": return "a Japanese convoy with escort. Sink the merchantmen."
		"express": return "destroyers at high speed on a Tokyo Express run. Stop them before they pass out of reach."
		"barges": return "landing barges creeping along the coast, some of them gun barges. Torpedoes run under them."
		"sub": return "a Japanese submarine on the route. Find it on sonar and sink it."
		"carriers": return "Japanese carriers with their screen. The first strike home wins."
	return "a Japanese surface force. Fleet command wants it brought to action."


## Assault on a held island (operations map): silence its coastal batteries and the supply
## dump to raise the flag. `isl` is a Geo.ISLANDS entry, `garrison` the number of batteries,
## `friends` the ships in company, `boats` any small craft the defenders have in the lagoon.
static func island_assault(rng: RandomNumberGenerator, isl: Dictionary, garrison: int, friends: Array, player_type: String, player_name: String, weather: String, enemy_side: String) -> Dictionary:
	var ib := rng.randf_range(0.0, TAU)
	var idist := 10000.0
	var ix := sin(ib) * idist
	var iz := -cos(ib) * idist
	var islands := []
	var biggest := 0.0
	for c in isl.shape:
		islands.append({"x": ix + c[0], "z": iz + c[1], "r": float(c[2]), "h": float(c[3]), "seed": rng.randi() % 1000})
		biggest = maxf(biggest, float(c[2]))
	# batteries on the shore facing the sea the player comes from, the dump behind the beach
	var shore := []
	var face := ib + PI
	for i in garrison:
		var a := face + deg_to_rad(-50.0 + 100.0 * float(i) / maxf(1.0, garrison - 1)) if garrison > 1 else face
		var c0: Array = isl.shape[i % isl.shape.size()]
		var r0: float = float(c0[2])
		shore.append(["shore_battery", "Battery %s" % char(65 + i), ix + c0[0] + sin(a) * r0 * 0.78, iz + c0[1] - cos(a) * r0 * 0.78])
	var c1: Array = isl.shape[0]
	shore.append(["supply_dump", "Supply dump", ix + c1[0] + sin(face) * float(c1[2]) * 0.45, iz + c1[1] - cos(face) * float(c1[2]) * 0.45])
	var fl := []
	var fr_ships := layout([[player_type, player_name]] + friends, rng)
	for i in range(1, fr_ships.size()):
		fl.append(fr_ships[i])
	var enemies := []
	if enemy_side == "ijn":
		var boats := [["daihatsu_gun", "Gun barge 1", 0.0, 0.0], ["daihatsu", "Barge 2", 120.0, 60.0]]
		if garrison >= 3:
			boats.append(["jp_mtb", "T-%d" % (1 + rng.randi() % 50), 240.0, -60.0])
		enemies.append({"group": "", "x": ix + sin(ib + PI / 2) * (biggest * 1.5), "z": iz - cos(ib + PI / 2) * (biggest * 1.5), "h": fposmod(ib + PI, TAU), "kn": 7.0, "ships": boats, "objective": false, "route": true, "dest": 6000.0})
	else:
		enemies.append({"group": "", "x": ix + sin(ib + PI / 2) * (biggest * 1.5), "z": iz - cos(ib + PI / 2) * (biggest * 1.5), "h": fposmod(ib + PI, TAU), "kn": 20.0, "ships": [["pt_elco", "PT-%d" % (100 + rng.randi() % 99), 0.0, 0.0]], "objective": false})
	return {"id": "assault", "title": "Assault on %s" % isl.name, "kind": "bombard", "weather": weather,
		"choices": [[player_type, player_name]], "friends": fl, "islands": islands, "shore": shore, "enemies": enemies,
		"report": {"brg": ib, "dist": idist, "h": 0.0, "kn": 0.0, "r": biggest, "fixed": true}, "escape_r": 30000.0,
		"text": "%s lies bearing %%s, about %%s away, held by the enemy with %d coastal batter%s and a supply dump behind the beach. Silence the guns and burn the dump and the landing force raises the flag.\n\nYou command %%s. The batteries shoot back and the water shoals close inshore; pick each one as your target and pound it." % [isl.name, garrison, "y" if garrison == 1 else "ies"]}
