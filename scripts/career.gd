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

## Decorations (design doc: Medals). Awarded automatically for what is done in action; each
## award gives a small, lasting buff to the holder's own work. A second award is a gold star
## and adds the buff again, up to `max` awards. Draft list, to be refined with Matt.
## id -> {name, who ("captain" or an officer post), how, buff {mod key: value per award}, max, ribbon [base, stripes...]}
const MEDAL_DEFS := {
	# the captain: the ship's whole fight
	"asiatic_pacific": {"name": "Asiatic-Pacific Campaign Medal", "who": "captain", "how": "Served in action in the Pacific (a bronze star for every five actions).", "buff": {}, "max": 6, "ribbon": [Color(0.86, 0.6, 0.18), Color(0.15, 0.25, 0.55), Color(0.95, 0.95, 0.95), Color(0.72, 0.12, 0.16)]},
	"bronze_star": {"name": "Bronze Star", "who": "captain", "how": "Led a successful action against a Serious threat or worse.", "buff": {"solution": 0.04}, "max": 3, "ribbon": [Color(0.72, 0.12, 0.16), Color(0.95, 0.95, 0.95), Color(0.15, 0.25, 0.55)]},
	"silver_star": {"name": "Silver Star", "who": "captain", "how": "Led a successful action against a Severe threat or worse.", "buff": {"agility": 0.04, "solution": 0.03}, "max": 3, "ribbon": [Color(0.2, 0.3, 0.6), Color(0.95, 0.95, 0.95), Color(0.72, 0.12, 0.16)]},
	"navy_cross": {"name": "Navy Cross", "who": "captain", "how": "Sank a battleship or a carrier.", "buff": {"gun_spread": 0.05, "agility": 0.03}, "max": 2, "ribbon": [Color(0.1, 0.15, 0.4), Color(0.95, 0.95, 0.95)]},
	"medal_of_honor": {"name": "Medal of Honor", "who": "captain", "how": "Won the action with a third of the crew lost and two or more enemy ships sunk.", "buff": {"gun_spread": 0.06, "agility": 0.06, "dc_rate": 0.06, "survive": 0.2}, "max": 1, "ribbon": [Color(0.45, 0.65, 0.9), Color(0.97, 0.97, 0.97)]},
	"legion_of_merit": {"name": "Legion of Merit", "who": "captain", "how": "Eight successful missions in command (again at sixteen and twenty-four).", "buff": {"cruise": 0.05, "training": 0.15}, "max": 3, "ribbon": [Color(0.66, 0.1, 0.2), Color(0.95, 0.95, 0.95)]},
	"navy_dsm": {"name": "Navy Distinguished Service Medal", "who": "captain", "how": "Twenty-five successful missions in command.", "buff": {"map_eyes": 0.15, "radar": 0.05}, "max": 1, "ribbon": [Color(0.12, 0.18, 0.45), Color(0.9, 0.75, 0.2)]},
	"purple_heart": {"name": "Purple Heart", "who": "captain", "how": "Fought on with a quarter of the crew lost.", "buff": {"survive": 0.1}, "max": 3, "ribbon": [Color(0.42, 0.16, 0.5), Color(0.95, 0.95, 0.95)]},
	"presidential_unit_citation": {"name": "Presidential Unit Citation", "who": "captain", "how": "The ship won an action against an Extreme threat.", "buff": {"training": 0.2, "fire_fight": 0.05}, "max": 2, "ribbon": [Color(0.15, 0.25, 0.55), Color(0.9, 0.75, 0.2), Color(0.72, 0.12, 0.16)]},
	# the executive officer: running the ship
	"xo_commendation": {"name": "Navy Commendation Ribbon", "who": "Executive officer", "how": "Three successful actions as executive officer.", "buff": {"training": 0.1}, "max": 3, "ribbon": [Color(0.12, 0.4, 0.22), Color(0.95, 0.95, 0.95)]},
	"xo_bronze_star": {"name": "Bronze Star", "who": "Executive officer", "how": "Kept the ship fighting through heavy losses (15% of the crew) to win a Serious action.", "buff": {"dc_rate": 0.04, "fire_fight": 0.04}, "max": 2, "ribbon": [Color(0.72, 0.12, 0.16), Color(0.95, 0.95, 0.95), Color(0.15, 0.25, 0.55)]},
	"xo_legion_of_merit": {"name": "Legion of Merit", "who": "Executive officer", "how": "Twelve actions as executive officer.", "buff": {"training": 0.15}, "max": 1, "ribbon": [Color(0.66, 0.1, 0.2), Color(0.95, 0.95, 0.95)]},
	# gunnery
	"gun_commendation": {"name": "Navy Commendation Ribbon", "who": "Gunnery officer", "how": "Twelve or more shell hits in one action.", "buff": {"gun_spread": 0.03}, "max": 3, "ribbon": [Color(0.12, 0.4, 0.22), Color(0.95, 0.95, 0.95)]},
	"gun_bronze_star": {"name": "Bronze Star", "who": "Gunnery officer", "how": "Sank an enemy ship by gunfire.", "buff": {"gun_reload": 0.04}, "max": 3, "ribbon": [Color(0.72, 0.12, 0.16), Color(0.95, 0.95, 0.95), Color(0.15, 0.25, 0.55)]},
	"gun_silver_star": {"name": "Silver Star", "who": "Gunnery officer", "how": "Sank a cruiser or bigger by gunfire.", "buff": {"solution": 0.06}, "max": 2, "ribbon": [Color(0.2, 0.3, 0.6), Color(0.95, 0.95, 0.95), Color(0.72, 0.12, 0.16)]},
	"gun_navy_cross": {"name": "Navy Cross", "who": "Gunnery officer", "how": "Sank a battleship by gunfire.", "buff": {"gun_spread": 0.06, "long_gun": 0.1}, "max": 1, "ribbon": [Color(0.1, 0.15, 0.4), Color(0.95, 0.95, 0.95)]},
	# torpedoes
	"torp_commendation": {"name": "Navy Commendation Ribbon", "who": "Torpedo officer", "how": "Two or more torpedo hits in one action.", "buff": {"torp_reload": 0.05}, "max": 3, "ribbon": [Color(0.12, 0.4, 0.22), Color(0.95, 0.95, 0.95)]},
	"torp_bronze_star": {"name": "Bronze Star", "who": "Torpedo officer", "how": "Sank an enemy ship with torpedoes.", "buff": {"torp_dud": 0.25}, "max": 2, "ribbon": [Color(0.72, 0.12, 0.16), Color(0.95, 0.95, 0.95), Color(0.15, 0.25, 0.55)]},
	"torp_navy_cross": {"name": "Navy Cross", "who": "Torpedo officer", "how": "Sank a battleship or a carrier with torpedoes.", "buff": {"torp_reload": 0.12}, "max": 1, "ribbon": [Color(0.1, 0.15, 0.4), Color(0.95, 0.95, 0.95)]},
	# engineering
	"eng_commendation": {"name": "Navy Commendation Ribbon", "who": "Engineering officer", "how": "Kept steam up through fifteen minutes or more of action.", "buff": {"speed": 0.02}, "max": 3, "ribbon": [Color(0.12, 0.4, 0.22), Color(0.95, 0.95, 0.95)]},
	"eng_nmcm": {"name": "Navy and Marine Corps Medal", "who": "Engineering officer", "how": "Brought a sinking ship home (flooding past half of what she can take).", "buff": {"pump": 0.1}, "max": 2, "ribbon": [Color(0.12, 0.18, 0.45), Color(0.9, 0.75, 0.2), Color(0.72, 0.12, 0.16)]},
	"eng_legion_of_merit": {"name": "Legion of Merit", "who": "Engineering officer", "how": "Fifteen actions as chief engineer.", "buff": {"speed": 0.03, "cruise": 0.05}, "max": 1, "ribbon": [Color(0.66, 0.1, 0.2), Color(0.95, 0.95, 0.95)]},
	# navigation
	"nav_commendation": {"name": "Navy Commendation Ribbon", "who": "Navigator", "how": "Three or more enemy torpedoes seen coming and none hit.", "buff": {"agility": 0.04}, "max": 3, "ribbon": [Color(0.12, 0.4, 0.22), Color(0.95, 0.95, 0.95)]},
	"nav_bronze_star": {"name": "Bronze Star", "who": "Navigator", "how": "Won an action at night.", "buff": {"lookouts": 0.1, "night_gun": 0.05}, "max": 2, "ribbon": [Color(0.72, 0.12, 0.16), Color(0.95, 0.95, 0.95), Color(0.15, 0.25, 0.55)]},
	"nav_legion_of_merit": {"name": "Legion of Merit", "who": "Navigator", "how": "Fifteen actions as navigator.", "buff": {"map_eyes": 0.1}, "max": 1, "ribbon": [Color(0.66, 0.1, 0.2), Color(0.95, 0.95, 0.95)]},
	# damage control
	"dc_commendation": {"name": "Navy Commendation Ribbon", "who": "Damage control officer", "how": "Patched five or more holes in one action.", "buff": {"pump": 0.06}, "max": 3, "ribbon": [Color(0.12, 0.4, 0.22), Color(0.95, 0.95, 0.95)]},
	"dc_nmcm": {"name": "Navy and Marine Corps Medal", "who": "Damage control officer", "how": "Put out four or more fires in one action.", "buff": {"fire_fight": 0.08}, "max": 3, "ribbon": [Color(0.12, 0.18, 0.45), Color(0.9, 0.75, 0.2), Color(0.72, 0.12, 0.16)]},
	"dc_silver_star": {"name": "Silver Star", "who": "Damage control officer", "how": "Saved the ship from sinking.", "buff": {"dc_rate": 0.08, "magazine": 0.1}, "max": 2, "ribbon": [Color(0.2, 0.3, 0.6), Color(0.95, 0.95, 0.95), Color(0.72, 0.12, 0.16)]},
	# the air group
	"air_medal": {"name": "Air Medal", "who": "Air group commander", "how": "Twelve or more sorties flown in one action.", "buff": {"strike_acc": 0.05}, "max": 3, "ribbon": [Color(0.12, 0.24, 0.6), Color(0.92, 0.6, 0.15)]},
	"dfc": {"name": "Distinguished Flying Cross", "who": "Air group commander", "how": "Three or more bomb or torpedo hits by the air group in one action.", "buff": {"strike_acc": 0.08}, "max": 2, "ribbon": [Color(0.15, 0.25, 0.55), Color(0.95, 0.95, 0.95), Color(0.72, 0.12, 0.16)]},
	"air_navy_cross": {"name": "Navy Cross", "who": "Air group commander", "how": "The air group sank a battleship or a carrier.", "buff": {"strike_acc": 0.12}, "max": 1, "ribbon": [Color(0.1, 0.15, 0.4), Color(0.95, 0.95, 0.95)]},
	# any officer hurt in action
	"officer_purple_heart": {"name": "Purple Heart", "who": "any", "how": "Wounded in action.", "buff": {}, "max": 3, "ribbon": [Color(0.42, 0.16, 0.5), Color(0.95, 0.95, 0.95)]},
}

## What each buff key means, for the medal cards.
const BUFF_LABEL := {
	"solution": "fire-control solutions build faster", "agility": "the ship turns quicker", "gun_spread": "tighter gunnery", "gun_reload": "guns reload faster",
	"long_gun": "better gunnery at long range", "night_gun": "better gunnery at night", "torp_reload": "torpedo tubes reload faster", "torp_dud": "fewer torpedo duds",
	"speed": "more top speed", "cruise": "faster cruising on the map", "pump": "pumps gain on flooding faster", "dc_rate": "holes are patched faster",
	"fire_fight": "fires go out faster", "magazine": "magazines safer from fire", "survive": "less reputation lost if the ship goes down",
	"training": "the crew trains faster", "lookouts": "lookouts see further", "map_eyes": "groups spotted further out on the map", "radar": "longer radar reach",
	"strike_acc": "air strikes hit more often",
}

## Reputation needed for each rank (index into Missions.RANKS). A promotion never goes back.
const RANK_REP := [0, 600, 1500, 2800, 4600, 7000, 10000, 14000, 19000]

## Ships Naval Command offers for the fleet at each promotion (index = the new rank): options,
## each a list of ship types. A class not yet in service is swapped for the nearest older one.
const OFFERS := [
	[],
	[["pt_elco", "pt_elco"], ["gato"]],
	[["fletcher"], ["buckley", "buckley"], ["benson", "mahan"]],
	[["fletcher", "fletcher"], ["atlanta"], ["brooklyn"]],
	[["cleveland"], ["new_orleans"], ["casablanca", "fletcher"]],
	[["baltimore"], ["independence"], ["texas", "fletcher"]],
	[["north_carolina"], ["yorktown"], ["south_dakota"]],
	[["iowa"], ["essex"], ["baltimore", "cleveland", "fletcher"]],
	[["iowa", "fletcher", "fletcher"], ["essex", "atlanta"], ["iowa", "essex"]],
]
const OLDER := {"buckley": "mahan", "fletcher": "benson", "atlanta": "brooklyn", "cleveland": "brooklyn", "casablanca": "northampton", "baltimore": "new_orleans",
	"independence": "yorktown", "iowa": "south_dakota", "south_dakota": "north_carolina", "essex": "yorktown"}

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

## The player's name as the captain (made up once and kept).
static func captain_name(c: Dictionary) -> String:
	if not c.has("captain") or String(c.captain) == "":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		c.captain = "%s %s" % [FIRST[rng.randi() % FIRST.size()], LAST[rng.randi() % LAST.size()]]
	return String(c.captain)

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
	var s := ship(c)
	if not s.is_empty():
		for id in s.refits:
			v += REFITS[id][5].get(key, 0.0)
	# decorations: the captain's apply to the whole ship, each officer's to his own work
	v += medal_mod(c.get("medals", []), key)
	for o in c.officers:
		if o.dead or o.wounded > 0:
			continue
		v += medal_mod(o.get("medals", []), key)
	return v

static func medal_mod(medals: Array, key: String) -> float:
	var v := 0.0
	for m in medals:
		var d: Dictionary = MEDAL_DEFS.get(m.get("id", ""), {})
		if not d.is_empty():
			v += float(d.buff.get(key, 0.0)) * int(m.get("n", 1))
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

## Apply a battle's tallies to officers, crew, rank and medals. Returns a list of lines for the report.
static func apply_battle(c: Dictionary, tally: Dictionary, result: String, level: int, day: int) -> Array:
	var lines := []
	var s := ship(c)
	var diff: Dictionary = DIFFICULTY.get(c.difficulty, DIFFICULTY.officer)
	var won := result == "won"
	c.actions = int(c.get("actions", 0)) + 1
	# officers serve the action; the wounded sit this one out
	for o in c.officers:
		if o.dead:
			continue
		o._sat_out = o.wounded > 0
		if o.wounded > 0:
			o.wounded = maxi(0, o.wounded - 1)
			continue
		o.battles += 1
		if won:
			o.won = int(o.get("won", 0)) + 1
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
					award(o, "officer_purple_heart", day, lines, o.name)
	# the crew still learns their trade by doing it
	var ship_xp: int = int(tally.get("combat_min", 0.0) * 5) + int(tally.get("damage_done", 0.0) * 2) + tally.get("kills", 0) * 150 + int(tally.get("after_min", 0.0) * 3)
	if not s.is_empty():
		s.xp += ship_xp
		var lbl0 := training_label(s.training)
		s.training += ship_xp * 0.12 * (1.0 + mod("training"))
		s.kills += tally.get("kills", 0)
		if training_label(s.training) != lbl0:
			lines.append("The crew of %s is now rated %s." % [s.name, training_label(s.training)])
		s.morale = clampf(s.morale + (0.1 if won else -0.15) - crew_loss_frac * 0.5, 0.1, 1.0)
		if crew_loss_frac > 0.0:
			s.training = maxf(0.0, s.training * (1.0 - crew_loss_frac * 0.6))
	c.supply = c.get("supply", 0) + (level * 30 if won else level * 8)
	_award_medals(c, tally, result, level, day, lines)
	# rank follows reputation (the battle has already added this action's)
	check_promotion(c, lines)
	c.log.append({"day": day, "text": tally.get("summary", ""), "result": result})
	if c.log.size() > 300:
		c.log.pop_front()
	return lines


## Every decoration whose deed was done in this action.
static func _award_medals(c: Dictionary, tally: Dictionary, result: String, level: int, day: int, lines: Array) -> void:
	var won := result == "won"
	var loss: float = tally.get("crew_loss_frac", 0.0)
	var kills: Array = tally.get("kill_list", [])
	var big := func(by: String, classes: Array) -> bool:
		for k in kills:
			if (by == "" or k.by == by) and k.cls in classes:
				return true
		return false
	var any_by := func(by: String) -> bool:
		for k in kills:
			if k.by == by:
				return true
		return false
	var me := "You"
	# the captain
	if int(c.actions) % 5 == 1:
		award(c, "asiatic_pacific", day, lines, me)
	if won and level >= 3:
		award(c, "bronze_star", day, lines, me)
	if won and level >= 4:
		award(c, "silver_star", day, lines, me)
	if big.call("", ["bb", "cv", "cvl"]):
		award(c, "navy_cross", day, lines, me)
	if won and loss >= 0.33 and kills.size() >= 2:
		award(c, "medal_of_honor", day, lines, me)
	if won and int(c.get("won", 0)) > 0 and int(c.won) % 8 == 0:
		award(c, "legion_of_merit", day, lines, me)
	if won and int(c.get("won", 0)) == 25:
		award(c, "navy_dsm", day, lines, me)
	if loss >= 0.25:
		award(c, "purple_heart", day, lines, me)
	if won and level >= 5:
		award(c, "presidential_unit_citation", day, lines, me)
	# the officers, each for his own part
	for o in c.officers:
		if o.dead or o.get("_sat_out", false):
			continue
		match String(o.post):
			"Executive officer":
				if won and int(o.get("won", 0)) % 3 == 0:
					award(o, "xo_commendation", day, lines, o.name)
				if won and level >= 3 and loss >= 0.15:
					award(o, "xo_bronze_star", day, lines, o.name)
				if int(o.battles) == 12:
					award(o, "xo_legion_of_merit", day, lines, o.name)
			"Gunnery officer":
				if int(tally.get("hits", 0)) >= 12:
					award(o, "gun_commendation", day, lines, o.name)
				if any_by.call("gun"):
					award(o, "gun_bronze_star", day, lines, o.name)
				if big.call("gun", ["ca", "cl", "bb", "cv", "cvl"]):
					award(o, "gun_silver_star", day, lines, o.name)
				if big.call("gun", ["bb"]):
					award(o, "gun_navy_cross", day, lines, o.name)
			"Torpedo officer":
				if int(tally.get("torp_hits", 0)) >= 2:
					award(o, "torp_commendation", day, lines, o.name)
				if any_by.call("torp"):
					award(o, "torp_bronze_star", day, lines, o.name)
				if big.call("torp", ["bb", "cv", "cvl"]):
					award(o, "torp_navy_cross", day, lines, o.name)
			"Engineering officer":
				if float(tally.get("combat_min", 0.0)) >= 15.0:
					award(o, "eng_commendation", day, lines, o.name)
				if int(tally.get("saved", 0)) > 0:
					award(o, "eng_nmcm", day, lines, o.name)
				if int(o.battles) == 15:
					award(o, "eng_legion_of_merit", day, lines, o.name)
			"Navigator":
				if int(tally.get("torps_seen", 0)) >= 3 and int(tally.get("torp_hits_taken", 0)) == 0:
					award(o, "nav_commendation", day, lines, o.name)
				if won and tally.get("night", false):
					award(o, "nav_bronze_star", day, lines, o.name)
				if int(o.battles) == 15:
					award(o, "nav_legion_of_merit", day, lines, o.name)
			"Damage control officer":
				if int(tally.get("holes_fixed", 0)) >= 5:
					award(o, "dc_commendation", day, lines, o.name)
				if int(tally.get("fires_out", 0)) >= 4:
					award(o, "dc_nmcm", day, lines, o.name)
				if int(tally.get("saved", 0)) > 0:
					award(o, "dc_silver_star", day, lines, o.name)
			"Air group commander":
				if int(tally.get("sorties", 0)) >= 12:
					award(o, "air_medal", day, lines, o.name)
				if int(tally.get("air_hits", 0)) >= 3:
					award(o, "dfc", day, lines, o.name)
				if big.call("air", ["bb", "cv", "cvl"]):
					award(o, "air_navy_cross", day, lines, o.name)


## Pin a decoration on someone (the career for the captain, or an officer). A repeat award is a
## gold star in lieu of a second medal, up to the medal's maximum.
static func award(holder: Dictionary, id: String, day: int, lines: Array, who: String) -> void:
	var d: Dictionary = MEDAL_DEFS.get(id, {})
	if d.is_empty():
		return
	if not holder.has("medals"):
		holder.medals = []
	for m in holder.medals:
		if m.get("id", "") == id:
			if int(m.get("n", 1)) >= int(d.max):
				return
			m.n = int(m.get("n", 1)) + 1
			m.day = day
			lines.append("%s: a gold star in lieu of a second %s." % [who, d.name] if m.n == 2 else "%s: %s, award number %d." % [who, d.name, m.n])
			return
	holder.medals.append({"id": id, "name": d.name, "day": day, "n": 1})
	lines.append(("You are awarded the %s." % d.name) if who == "You" else ("%s is awarded the %s." % [who, d.name]))


## One line for a medal card: what it was for and what it does now.
static func medal_buff_text(m: Dictionary) -> String:
	var d: Dictionary = MEDAL_DEFS.get(m.get("id", ""), {})
	if d.is_empty():
		return ""
	var n := int(m.get("n", 1))
	var parts := []
	for k in d.buff:
		parts.append("%s (+%d%%)" % [BUFF_LABEL.get(k, k), int(round(float(d.buff[k]) * n * 100.0))])
	var effect := ", ".join(parts)
	if effect == "":
		effect = "a mark of honour"
	return "%s %s" % [d.how, ("Now: " + effect + ".") if not parts.is_empty() else ""]


static func medal_ribbon(id: String) -> Array:
	var d: Dictionary = MEDAL_DEFS.get(id, {})
	return d.get("ribbon", [Color(0.5, 0.5, 0.5), Color(0.9, 0.85, 0.3)])


# ---------- rank from reputation; Naval Command's letters ----------

static func rank_for_rep(rep: int) -> int:
	var r := 0
	for i in RANK_REP.size():
		if rep >= RANK_REP[i]:
			r = i
	return r

## Promote when reputation has reached the next rank; each promotion queues a letter with ships to choose from.
static func check_promotion(c: Dictionary, lines: Array) -> void:
	var r := rank_for_rep(int(c.get("reputation", 0)))
	while int(c.rank) < r:
		c.rank = int(c.rank) + 1
		lines.append("Promoted to %s." % Missions.RANKS[clampi(int(c.rank), 0, Missions.RANKS.size() - 1)])
		if not c.has("offers"):
			c.offers = []
		c.offers.append(int(c.rank))

## The options in a promotion letter for the given rank and year: lists of ship types in service.
static func offer_options(rank: int, year: int) -> Array:
	var out := []
	for opt in OFFERS[clampi(rank, 0, OFFERS.size() - 1)]:
		var o := []
		for tid in opt:
			o.append(in_service(tid, year))
		out.append(o)
	return out

## "two Fletcher-class destroyers and an Atlanta-class AA cruiser" for a letter's option.
static func describe_offer(opt: Array) -> String:
	var counts := {}
	var order := []
	for tid in opt:
		if not counts.has(tid):
			order.append(tid)
		counts[tid] = int(counts.get(tid, 0)) + 1
	var words := ["", "a", "two", "three", "four"]
	var parts := []
	for tid in order:
		var lbl: String = String(Data.TYPES[tid].name)
		for it in Missions.SUPPORT:
			if it[0] == tid:
				lbl = it[1]
		var n: int = counts[tid]
		if n > 1:
			lbl += "s"
		var art: String = words[mini(n, 4)]
		if n == 1 and lbl.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"]:
			art = "an"
		if lbl.begins_with("USS"):
			parts.append(lbl)
			continue
		parts.append("%s %s" % [art, lbl])
	return " and ".join(parts)

static func in_service(tid: String, year: int) -> String:
	var t := tid
	for i in 6:
		var y := 1941
		for it in Missions.SUPPORT:
			if it[0] == t:
				y = it[3]
		if y <= year or not OLDER.has(t):
			return t
		t = OLDER[t]
	return t


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
