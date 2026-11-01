class_name Career
## Officers, crew, captain XP, rank, skills, refits, medals and difficulty (design doc: Career,
## Upgrades, Crew and officers, Difficulty). State lives in Game.career; this class holds the
## rules and the modifiers the battle reads through Career.mod().

const POSTS := ["Executive officer", "Gunnery officer", "Torpedo officer", "Engineering officer", "Navigator", "Damage control officer", "Air group commander"]
const FIRST := ["John", "William", "James", "Robert", "Charles", "George", "Frank", "Edward", "Thomas", "Henry", "Walter", "Arthur", "Harold", "Paul", "Raymond", "Richard", "Joseph", "Samuel", "Daniel", "Ernest"]
const LAST := ["Miller", "Kowalski", "O'Brien", "Hanson", "Delgado", "Carter", "Russo", "Lindqvist", "Brooks", "Moreau", "Walsh", "Schneider", "Hayes", "Nakamura", "Fitzgerald", "Powell", "Sorensen", "Baker", "Cole", "Hughes"]

## Captain XP needed for each rank (index into Missions.RANKS).
const RANK_XP := [0, 1200, 3200, 6500, 11000, 17000, 26000, 38000, 54000]
## Captain level: XP per level grows slowly; each level = one skill point.
static func level_for(xp: int) -> int:
	return int(sqrt(maxf(0.0, xp) / 120.0))

## Officer level from XP.
static func officer_level(xp: int) -> int:
	return clampi(int(sqrt(maxf(0.0, xp) / 60.0)), 0, 10)

## Crew training label from training points.
static func training_label(tp: float) -> String:
	if tp < 100.0: return "green"
	if tp < 400.0: return "trained"
	if tp < 1000.0: return "veteran"
	return "elite"

static func training_factor(tp: float) -> float:
	return 0.85 + 0.30 * clampf(tp / 1200.0, 0.0, 1.0)

## Captain skills by ship type: id -> [name, type, description, modifiers]
const SKILLS := {
	"pt_silent": ["Silent approach", "pt", "Lower wake and engine noise at low speed: harder to spot on the run-in.", {"stealth": 0.25}],
	"pt_quick": ["Quick shot", "pt", "Faster torpedo launch.", {"torp_reload": 0.3}],
	"pt_hitrun": ["Hit and run", "pt", "Faster acceleration and turning after firing.", {"agility": 0.2}],
	"pt_island": ["Island hugger", "pt", "Harder to spot near coastlines.", {"stealth": 0.15}],
	"ss_sound": ["Sound listener", "ss", "Hear ships at longer range.", {"periscope": 0.3}],
	"ss_deep": ["Deep runner", "ss", "Dive faster and deeper.", {"dive": 0.4}],
	"ss_silent": ["Silent running", "ss", "Harder to find with sonar.", {"stealth": 0.3}],
	"ss_scope": ["Periscope sense", "ss", "Shorter periscope exposure.", {"stealth": 0.15, "periscope": 0.1}],
	"de_hunter": ["Sub hunter", "de", "Sonar detects submarines sooner.", {"sonar": 0.3}],
	"de_wide": ["Wide pattern", "de", "Bigger depth charge radius.", {"dc": 0.35}],
	"de_hedgehog": ["Hedgehog drill", "de", "Faster ahead-thrown weapon reload.", {"hedgehog": 0.4}],
	"de_shepherd": ["Convoy shepherd", "de", "Escorted ships take fewer losses.", {"shepherd": 0.3}],
	"dd_subkiller": ["Sub killer", "dd", "Detect submarines sooner, bigger depth charge radius.", {"sonar": 0.25, "dc": 0.25}],
	"dd_torprun": ["Torpedo run", "dd", "Faster torpedo reload, tighter spreads.", {"torp_reload": 0.3, "torp_spread": 0.3}],
	"dd_smoke": ["Smoke master", "dd", "Longer and thicker smoke screens.", {"smoke": 0.5}],
	"dd_radar": ["Radar picket", "dd", "Longer radar range.", {"radar": 0.25}],
	"dd_knife": ["Knife fighter", "dd", "Better gunnery at close range at night.", {"night_gun": 0.3}],
	"cl_rapid": ["Rapid fire", "cl", "Faster main battery reload.", {"gun_reload": 0.2}],
	"cl_night": ["Night action", "cl", "Better spotting and accuracy at night.", {"night_spot": 0.3, "night_gun": 0.2}],
	"cl_aa": ["AA screen", "cl", "Stronger anti-aircraft fire.", {"aa": 0.35}],
	"cl_flotilla": ["Flotilla leader", "cl", "Destroyers in your group fight better.", {"flotilla": 0.2}],
	"ca_long": ["Long gunner", "ca", "Better accuracy at long range.", {"long_gun": 0.3}],
	"ca_armored": ["Armored stance", "ca", "Less damage when angled toward the enemy.", {"angle": 0.25}],
	"ca_float": ["Floatplane spotter", "ca", "Spotting aircraft improve your accuracy.", {"spotter": 0.3}],
	"ca_night": ["Night duel", "ca", "Better star shell and searchlight use.", {"night_gun": 0.25}],
	"cve_turn": ["Quick turnaround", "cve", "Faster plane rearm and refuel.", {"rearm": 0.35}],
	"cve_asw": ["Anti-sub patrol", "cve", "Planes find submarines sooner.", {"air_asw": 0.4}],
	"cve_close": ["Close support", "cve", "Better ground and shore attacks.", {"strike_acc": 0.2}],
	"cve_deck": ["Tight deck", "cve", "Fewer deck accidents.", {"deck": 0.3}],
	"cv_strike": ["Strike coordinator", "cv", "Dive and torpedo bombers attack together for more hits.", {"strike_acc": 0.3}],
	"cv_fighter": ["Fighter director", "cv", "Better combat air patrol against incoming raids.", {"cap": 0.4}],
	"cv_deck": ["Deck crew", "cv", "Faster launch and recovery.", {"deck": 0.4}],
	"cv_reach": ["Long reach", "cv", "Longer strike range.", {"reach": 0.3}],
	"cv_aces": ["Ace pilots", "cv", "Aircrew survive and gain experience faster.", {"aircrew": 0.3}],
	"bb_biggun": ["Big gun master", "bb", "Tighter main battery spread.", {"gun_spread": 0.25}],
	"bb_fc": ["Fire control expert", "bb", "Faster firing solution.", {"solution": 0.4}],
	"bb_armor": ["Armor discipline", "bb", "Better damage control under heavy fire.", {"dc_rate": 0.35}],
	"bb_flag": ["Fleet flagship", "bb", "All ships in your fleet fight better.", {"flotilla": 0.2}],
	"bb_shore": ["Shore bombardment", "bb", "Stronger fire against land targets.", {"shore": 0.4}],
	"gen_steady": ["Steady under fire", "all", "Morale holds longer.", {"morale": 0.3}],
	"gen_night": ["Night fighter", "all", "Better night spotting.", {"night_spot": 0.2}],
	"gen_lookouts": ["Sharp lookouts", "all", "Torpedo wakes are spotted farther out.", {"lookouts": 1.0}],
	"gen_handler": ["Ship handler", "all", "Faster engine and rudder response.", {"agility": 0.15}],
}

## Officer skills (the department heads' own tree): post -> [[id, name, description, modifiers, tier], ...].
## An officer earns a skill point every two levels; tier 2 needs level 4 and a tier-1 skill,
## tier 3 needs level 7 and a tier-2 skill.
const OFFICER_SKILLS := {
	"Executive officer": [
		["xo_drill", "Drill schedule", "The crew trains faster between battles.", {"training": 0.3}, 1],
		["xo_steady", "Steady hand", "Morale holds longer under fire.", {"morale": 0.2}, 1],
		["xo_parties", "Repair parties", "Faster damage control.", {"dc_rate": 0.15}, 2],
		["xo_lookouts", "Lookout rota", "Better spotting by day and night.", {"night_spot": 0.15, "lookouts": 0.5}, 2],
		["xo_second", "Second in command", "The ship fights on steadily when hurt: morale and damage control.", {"morale": 0.2, "dc_rate": 0.1}, 3],
		["xo_tight", "Tight ship", "Every department works 5% better.", {"gun_reload": 0.05, "torp_reload": 0.05, "dc_rate": 0.05, "agility": 0.05}, 3],
	],
	"Gunnery officer": [
		["gun_ready", "Ready ammunition", "Faster main battery reload.", {"gun_reload": 0.12}, 1],
		["gun_plot", "Plotting room", "Faster firing solution.", {"solution": 0.25}, 1],
		["gun_spot", "Spotting corrections", "Tighter salvos once on target.", {"gun_spread": 0.15}, 2],
		["gun_aa", "AA director", "Stronger anti-aircraft fire.", {"aa": 0.25}, 2],
		["gun_long", "Long-range gunnery", "Better accuracy beyond 60% of range.", {"long_gun": 0.3}, 3],
		["gun_night", "Night gunnery", "Better shooting by star shell and flash.", {"night_gun": 0.3}, 3],
	],
	"Torpedo officer": [
		["torp_fast", "Fast reload", "Torpedo tubes reload faster.", {"torp_reload": 0.2}, 1],
		["torp_spread", "Spread doctrine", "Tighter, better-aimed spreads.", {"torp_spread": 0.2}, 1],
		["torp_depth", "Depth setting", "Fewer duds and deep runners.", {"torp_dud": 0.4}, 2],
		["torp_wakes", "Wake watch", "Enemy torpedo wakes spotted farther out.", {"lookouts": 0.6}, 2],
		["torp_night", "Night attack", "Torpedo runs are harder to spot.", {"stealth": 0.2}, 3],
		["torp_asw", "Depth charge drill", "Bigger depth charge pattern, faster hedgehog.", {"dc": 0.25, "hedgehog": 0.25}, 3],
	],
	"Engineering officer": [
		["eng_boilers", "Boilers at pressure", "Faster acceleration and a knot more at flank.", {"agility": 0.1, "speed": 0.05}, 1],
		["eng_smoke", "Smoke on demand", "Thicker, longer smoke screens.", {"smoke": 0.3}, 1],
		["eng_pumps", "Pumps and shoring", "Flooding is pumped out faster.", {"pump": 0.25}, 2],
		["eng_splice", "Splice the mains", "Steam and pumps kept up when the ship is hurt.", {"speed": 0.05, "pump": 0.15}, 2],
		["eng_flank", "Flank speed", "Two knots more at flank, longer.", {"speed": 0.1}, 3],
		["eng_cruise", "Economical cruising", "Faster passages on the operations map.", {"cruise": 0.15}, 3],
	],
	"Navigator": [
		["nav_helm", "Helmsmanship", "Quicker rudder response.", {"agility": 0.15}, 1],
		["nav_chart", "Chart work", "Better plotting of contacts: radar and night spotting.", {"radar": 0.1, "night_spot": 0.1}, 1],
		["nav_radar", "Radar plot", "Longer radar range.", {"radar": 0.2}, 2],
		["nav_eyes", "Eyes on the horizon", "Farther spotting on the operations map.", {"map_eyes": 0.3}, 2],
		["nav_night", "Night navigator", "Better night spotting and star-shell use.", {"night_spot": 0.25}, 3],
		["nav_intercept", "Interception course", "Faster passages and better intercepts on the map.", {"cruise": 0.1, "map_eyes": 0.2}, 3],
	],
	"Damage control officer": [
		["dc_fire", "Fire main", "Fires are put out faster.", {"fire_fight": 0.3}, 1],
		["dc_shoring", "Shoring timbers", "Holes are plugged faster.", {"dc_rate": 0.2}, 1],
		["dc_counter", "Counter-flooding", "Less list, smaller flooding penalties.", {"pump": 0.2}, 2],
		["dc_mag", "Magazine discipline", "Fewer magazine explosions.", {"magazine": 0.5}, 2],
		["dc_hero", "Hold the line", "Damage control keeps working under heavy fire.", {"dc_rate": 0.25, "morale": 0.15}, 3],
		["dc_saved", "Saved from the sea", "If the ship is lost, less reputation is lost with her and the crew keeps heart.", {"survive": 0.5, "morale": 0.1}, 3],
	],
	"Air group commander": [
		["air_deck", "Deck spotting", "Faster launch and recovery.", {"deck": 0.25}, 1],
		["air_cap", "CAP doctrine", "Better combat air patrol.", {"cap": 0.25}, 1],
		["air_strike", "Coordinated strike", "Dive and torpedo bombers arrive together.", {"strike_acc": 0.2}, 2],
		["air_rearm", "Rearm drill", "Faster rearm and refuel.", {"rearm": 0.3}, 2],
		["air_reach", "Long search", "Longer strike and search range.", {"reach": 0.25, "map_eyes": 0.2}, 3],
		["air_aces", "Fighter aces", "Aircrew survive and learn faster.", {"aircrew": 0.3}, 3],
	],
}

static func officer_points_left(o: Dictionary) -> int:
	return int(officer_level(o.xp) / 2) - o.get("skills", []).size()

## Can this officer take this skill now?
static func officer_can_learn(o: Dictionary, id: String) -> bool:
	var sk := officer_skill(o.post, id)
	if sk.is_empty() or o.get("skills", []).has(id) or officer_points_left(o) <= 0:
		return false
	var tier: int = sk[4]
	var lvl := officer_level(o.xp)
	if tier == 2 and lvl < 4: return false
	if tier == 3 and lvl < 7: return false
	if tier > 1:
		var has_prev := false
		for s2 in OFFICER_SKILLS[o.post]:
			if s2[4] == tier - 1 and o.get("skills", []).has(s2[0]):
				has_prev = true
		if not has_prev:
			return false
	return true

static func officer_skill(post: String, id: String) -> Array:
	for sk in OFFICER_SKILLS.get(post, []):
		if sk[0] == id:
			return sk
	return []

## Captain skills come in tiers too: the n-th pair for a ship type needs n-1 skills of that type.
static func skill_tier(id: String) -> int:
	var cls: String = SKILLS[id][1]
	if cls == "all":
		return 1
	var i := 0
	for k in SKILLS:
		if SKILLS[k][1] == cls:
			if k == id:
				return int(i / 2) + 1
			i += 1
	return 1

static func can_learn(c: Dictionary, id: String) -> bool:
	if c.skills.has(id) or skill_points_left(c) <= 0:
		return false
	var cls: String = SKILLS[id][1]
	var tier := skill_tier(id)
	if tier > 1:
		var have := 0
		for k in c.skills:
			if SKILLS[k][1] == cls:
				have += 1
		if have < tier - 1:
			return false
	return true


## Refits: id -> [name, category, cost (supply), year, days in the yard, modifiers, description]
const REFITS := {
	"drill": ["Faster loading drill", "Main battery", 60, 1941, 2, {"gun_reload": 0.1}, "More ready ammunition and a well-drilled battery."],
	"shells": ["Improved shells", "Main battery", 90, 1943, 2, {"gun_dmg": 0.12}, "Better armour-piercing and high-capacity rounds."],
	"mk37": ["Mk 37 director", "Fire control", 120, 1942, 6, {"solution": 0.3, "gun_spread": 0.1}, "The best dual-purpose director of the war."],
	"fcradar": ["FC/FH fire-control radar", "Fire control", 160, 1943, 7, {"night_gun": 0.4, "solution": 0.2}, "Blind-fire gunnery at night and in fog."],
	"sc": ["SC air-search radar", "Radar and sensors", 80, 1942, 4, {"air_warn": 0.5}, "Warning of raids far out."],
	"sg": ["SG surface-search radar", "Radar and sensors", 140, 1942, 6, {"radar": 0.4}, "The set that found the Tokyo Express."],
	"sonar2": ["Improved sonar", "Radar and sensors", 70, 1942, 3, {"sonar": 0.3}, "A longer reach under water."],
	"bofors": ["40 mm Bofors and 20 mm Oerlikon", "Anti-aircraft", 110, 1942, 6, {"aa": 0.5}, "Replaces the 1.1-inch and .50 calibre."],
	"vt": ["Proximity-fuzed shells", "Anti-aircraft", 100, 1943, 2, {"aa": 0.4}, "Shells that burst when they pass a plane."],
	"mk14": ["Fixed Mark 14 torpedoes", "Torpedoes", 60, 1943, 1, {"torp_dud": 0.8}, "The duds are finally fixed."],
	"reloads": ["Extra torpedo reloads", "Torpedoes", 50, 1942, 2, {"torp_reload": 0.25}, "Spare fish stowed on deck."],
	"boilers": ["Boiler overhaul", "Engineering", 90, 1941, 8, {"speed": 0.05}, "A knot or two back."],
	"steering": ["Backup steering", "Engineering", 50, 1942, 3, {"steering": 0.5}, "A jammed rudder recovers faster."],
	"dc_train": ["Damage control training", "Protection", 60, 1942, 1, {"dc_rate": 0.3}, "Repair parties that know the ship."],
	"pumps": ["Extra pumps", "Protection", 70, 1942, 3, {"pump": 0.35}, "Flooding gains more slowly."],
	"splinter": ["Splinter shields", "Protection", 50, 1942, 3, {"splinter": 0.25}, "Fewer casualties from near misses."],
	"airgroup": ["Hellcats, Helldivers and Avengers", "Aircraft", 200, 1943, 10, {"airgroup": 1.0}, "A late-war air group."],
}

const MEDALS := {"navy_cross": "Navy Cross", "silver_star": "Silver Star", "bronze_star": "Bronze Star", "purple_heart": "Purple Heart"}

const DIFFICULTY := {
	"ensign": {"name": "Ensign (easy)", "retry": true, "rep_loss": 0.5, "pause": -1, "lead": true, "officers_die": false, "ironman": false, "wound": false},
	"officer": {"name": "Officer (normal)", "retry": false, "rep_loss": 1.0, "pause": -1, "lead": true, "officers_die": false, "ironman": false, "wound": false},
	"veteran": {"name": "Veteran (hard)", "retry": false, "rep_loss": 1.5, "pause": 5, "lead": false, "officers_die": true, "ironman": false, "wound": true},
	"ironman": {"name": "Ironman", "retry": false, "rep_loss": 1.5, "pause": 0, "lead": false, "officers_die": true, "ironman": true, "wound": true},
}

## Ship classes unlocked at each rank and the year they enter service (design doc: Career table).
const UNLOCKS := [
	["pt_elco", 0, 1941], ["gato", 0, 1941], ["buckley", 1, 1943], ["mahan", 1, 1941], ["benson", 1, 1941], ["fletcher", 1, 1942],
	["atlanta", 2, 1942], ["cleveland", 2, 1942], ["brooklyn", 2, 1941], ["northampton", 3, 1941], ["new_orleans", 3, 1941], ["baltimore", 3, 1943],
	["casablanca", 3, 1943], ["independence", 4, 1943], ["texas", 4, 1941], ["north_carolina", 5, 1941], ["south_dakota", 5, 1942], ["iowa", 5, 1943],
	["yorktown", 5, 1941], ["essex", 5, 1943],
]
const SHIP_NAMES := {"pt_elco": ["PT-109", "PT-157", "PT-171"], "gato": ["USS Wahoo", "USS Tang", "USS Barb"], "buckley": ["USS England", "USS Raby"], "mahan": ["USS Cushing", "USS Dunlap"],
	"benson": ["USS Laffey", "USS Woodworth"], "fletcher": ["USS O'Bannon", "USS Nicholas", "USS Fletcher", "USS Johnston"], "atlanta": ["USS Atlanta", "USS San Diego"], "cleveland": ["USS Cleveland", "USS Columbia"],
	"brooklyn": ["USS Helena", "USS Boise"], "northampton": ["USS Northampton", "USS Chicago"], "new_orleans": ["USS San Francisco", "USS Minneapolis"], "baltimore": ["USS Baltimore", "USS Boston"],
	"casablanca": ["USS Gambier Bay", "USS White Plains"], "independence": ["USS Bataan", "USS Princeton"], "texas": ["USS Texas"], "north_carolina": ["USS Washington", "USS North Carolina"],
	"south_dakota": ["USS South Dakota", "USS Massachusetts"], "iowa": ["USS Iowa", "USS New Jersey"], "yorktown": ["USS Enterprise", "USS Hornet"], "essex": ["USS Essex", "USS Lexington"]}


# =====================================================================
# state
# =====================================================================

static func fresh(difficulty := "officer") -> Dictionary:
	var c := {"rank": 0, "reputation": 300, "xp": 0, "spent_points": 0, "skills": {}, "year": 1941, "missions": 0, "won": 0,
		"officers": [], "ships": {}, "current": "", "supply": 100, "medals": [], "difficulty": difficulty, "magazine": "historical", "log": [], "pause_uses": 0}
	for post in POSTS:
		c.officers.append(new_officer(post))
	return c

static func new_officer(post: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return {"post": post, "name": "Lt. %s %s" % [FIRST[rng.randi() % FIRST.size()], LAST[rng.randi() % LAST.size()]], "xp": 0, "wounded": 0, "dead": false, "battles": 0, "skills": []}

## Give the career a ship (new crew, green) and make it the current command.
static func take_command(c: Dictionary, type_id: String, name: String, day: int) -> void:
	var key := "%s|%s" % [type_id, name]
	if not c.ships.has(key):
		c.ships[key] = {"type": type_id, "name": name, "training": 40.0, "morale": 0.8, "xp": 0, "refits": [], "damage": {}, "crew": int(Data.TYPES[type_id].crew), "since": day, "kills": 0}
	c.current = key
	# an officer who was wounded reports back aboard; the air group post only matters on carriers
	for o in c.officers:
		if o.dead:
			var o2 := new_officer(o.post)
			for k in o2:
				o[k] = o2[k]

static func ship(c: Dictionary) -> Dictionary:
	if c.current == "" or not c.ships.has(c.current):
		return {}
	return c.ships[c.current]

static func officer(c: Dictionary, post: String) -> Dictionary:
	for o in c.officers:
		if o.post == post:
			return o
	return {}

static func rank_for_xp(xp: int) -> int:
	var r := 0
	for i in RANK_XP.size():
		if xp >= RANK_XP[i]:
			r = i
	return r

static func skill_points_left(c: Dictionary) -> int:
	return level_for(c.xp) - c.skills.size()

static func skills_for(cls: String) -> Array:
	var out := []
	for id in SKILLS:
		if SKILLS[id][1] == cls or SKILLS[id][1] == "all":
			out.append(id)
	return out

## Commands open to this rank in this year.
static func available_commands(c: Dictionary, year: int) -> Array:
	var out := []
	for u in UNLOCKS:
		if u[1] <= c.rank and u[2] <= year:
			out.append(u[0])
	return out

static func refits_for(c: Dictionary, year: int) -> Array:
	var s := ship(c)
	var out := []
	for id in REFITS:
		var r: Array = REFITS[id]
		if r[3] > year or (s.has("refits") and s.refits.has(id)):
			continue
		if r[1] == "Aircraft" and not Data.TYPES[s.type].has("aircraft"):
			continue
		if r[1] == "Torpedoes" and Data.TYPES[s.type].torps.is_empty():
			continue
		out.append(id)
	return out


# =====================================================================
# modifiers read by the battle
# =====================================================================

## Combined modifier for a key from captain skills, refits and officers: 0 = none.
static func mod(key: String) -> float:
	var c: Dictionary = Game.career
	if c.is_empty() or not Game.campaign_active():
		return 0.0
	var v := 0.0
	for id in c.skills:
		var m: Dictionary = SKILLS[id][3]
		v += m.get(key, 0.0)
	var s := ship(c)
	if not s.is_empty():
		for id in s.refits:
			v += REFITS[id][5].get(key, 0.0)
	# officers: each level of the right post adds a little to its own keys
	var post_keys := {"Gunnery officer": ["gun_spread", "gun_reload", "solution"], "Torpedo officer": ["torp_reload", "torp_spread"], "Engineering officer": ["speed", "pump"],
		"Damage control officer": ["dc_rate", "pump"], "Navigator": ["agility"], "Executive officer": ["morale"], "Air group commander": ["strike_acc", "aircrew"]}
	for o in c.officers:
		if o.dead or o.wounded > 0:
			continue
		if post_keys.get(o.post, []).has(key):
			v += 0.03 * officer_level(o.xp)
		for id in o.get("skills", []):
			var sk := officer_skill(o.post, id)
			if not sk.is_empty():
				v += sk[3].get(key, 0.0)
	return v

## Crew efficiency factor for the player's ship (training and morale).
static func crew_factor() -> float:
	var c: Dictionary = Game.career
	if c.is_empty() or not Game.campaign_active():
		return 1.0
	var s := ship(c)
	if s.is_empty():
		return 1.0
	return training_factor(s.training) * (0.85 + 0.15 * s.morale)


# =====================================================================
# after a battle
# =====================================================================

## Apply a battle's tallies to officers, crew, captain, rank and medals. Returns a list of lines for the report.
static func apply_battle(c: Dictionary, tally: Dictionary, result: String, level: int, day: int) -> Array:
	var lines := []
	var s := ship(c)
	var diff: Dictionary = DIFFICULTY.get(c.difficulty, DIFFICULTY.officer)
	# officer XP by post
	var gains := {
		"Gunnery officer": tally.get("salvos", 0) * 2 + tally.get("hits", 0) * 6 + tally.get("gun_kills", 0) * 60,
		"Torpedo officer": tally.get("torps", 0) * 5 + tally.get("torp_hits", 0) * 40 + tally.get("torp_kills", 0) * 80,
		"Engineering officer": int(tally.get("combat_min", 0.0) * 4) + tally.get("saved", 0) * 80,
		"Damage control officer": tally.get("fires_out", 0) * 15 + tally.get("holes_fixed", 0) * 10 + tally.get("saved", 0) * 100,
		"Navigator": int(tally.get("underway_min", 0.0) * 2) + tally.get("contacts", 0) * 8,
		"Executive officer": tally.get("took_command", 0) * 80 + (40 if result == "won" else 10),
		"Air group commander": tally.get("sorties", 0) * 4 + tally.get("air_hits", 0) * 25 + tally.get("air_kills", 0) * 80,
	}
	var total := 0
	for o in c.officers:
		if o.dead:
			continue
		if o.wounded > 0:
			o.wounded = maxi(0, o.wounded - 1)
			continue
		var g: int = gains.get(o.post, 0)
		var before := officer_level(o.xp)
		o.xp += g
		o.battles += 1
		total += g
		if officer_level(o.xp) > before:
			lines.append("%s (%s) is now level %d." % [o.name, o.post, officer_level(o.xp)])
	# wounds and deaths
	var crew_loss_frac: float = tally.get("crew_loss_frac", 0.0)
	if crew_loss_frac > 0.15:
		for o in c.officers:
			if o.dead or o.wounded > 0:
				continue
			if randf() < crew_loss_frac * 0.5:
				if diff.officers_die and randf() < 0.3:
					o.dead = true
					lines.append("%s, %s, was killed in action." % [o.name, o.post])
				else:
					o.wounded = 2
					lines.append("%s, %s, was wounded and will miss the next two actions." % [o.name, o.post])
	# ship and crew
	var ship_xp: int = int(tally.get("combat_min", 0.0) * 5) + int(tally.get("damage_done", 0.0) * 2) + tally.get("kills", 0) * 150 + int(tally.get("after_min", 0.0) * 3)
	if not s.is_empty():
		s.xp += ship_xp
		s.training += ship_xp * 0.12 * (1.0 + mod("training"))
		s.kills += tally.get("kills", 0)
		var lbl0 := training_label(s.training - ship_xp * 0.12)
		if training_label(s.training) != lbl0:
			lines.append("The crew of %s is now rated %s." % [s.name, training_label(s.training)])
		s.morale = clampf(s.morale + (0.1 if result == "won" else -0.15) - crew_loss_frac * 0.5 + mod("morale") * 0.1, 0.1, 1.0)
		# losses bring green replacements
		if crew_loss_frac > 0.0:
			s.training = maxf(0.0, s.training * (1.0 - crew_loss_frac * 0.6))
		total += ship_xp
	# the captain's cut of everything
	var captain_xp := int(total * 0.3) + (level * 60 if result == "won" else 0)
	var old_rank: int = c.rank
	var old_level := level_for(c.xp)
	c.xp += captain_xp
	c.rank = maxi(c.rank, rank_for_xp(c.xp))
	if c.rank > old_rank:
		lines.append("Promoted to %s." % Missions.RANKS[c.rank])
	if level_for(c.xp) > old_level:
		lines.append("Captain level %d: %d skill point%s to spend." % [level_for(c.xp), skill_points_left(c), "" if skill_points_left(c) == 1 else "s"])
	c.supply = c.get("supply", 0) + (level * 30 if result == "won" else level * 8)
	# medals
	if result == "won":
		if tally.get("big_kill", false) and not _has_medal(c, "navy_cross"):
			_medal(c, "navy_cross", day, lines)
		elif level >= 4 and randf() < 0.5 and _medals_since(c, day) == 0:
			_medal(c, "silver_star", day, lines)
		elif level >= 3 and randf() < 0.4 and _medals_since(c, day) == 0:
			_medal(c, "bronze_star", day, lines)
	if crew_loss_frac > 0.25 and diff.wound and not _has_medal(c, "purple_heart"):
		_medal(c, "purple_heart", day, lines)
	c.log.append({"day": day, "text": tally.get("summary", ""), "result": result})
	if c.log.size() > 300:
		c.log.pop_front()
	return lines

static func _medals_since(c: Dictionary, day: int) -> int:
	var n := 0
	for m in c.medals:
		if day - int(m.day) < 45:
			n += 1
	return n

static func _has_medal(c: Dictionary, id: String) -> bool:
	for m in c.medals:
		if m.id == id:
			return true
	return false

static func _medal(c: Dictionary, id: String, day: int, lines: Array) -> void:
	c.medals.append({"id": id, "name": MEDALS[id], "day": day})
	lines.append("Awarded the %s." % MEDALS[id])
