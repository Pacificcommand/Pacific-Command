class_name Data
## Game data: ship classes, engine telegraph, weather.
## Distances are in meters and use the "semi-realistic" battle scale from the
## design doc: gun, radar and spotting ranges are about half of real life.

const KN := 0.5144   # meters per second in one knot
## Torpedoes run this much faster than their real speed, to match the shortened battle distances.
const TORP_SPEED := 1.6
const YD := 0.9144   # meters in one yard

## Guns. range_max in meters (half of real, see the design doc), reload in seconds per burst,
## per_mount = shells per burst, dmg = damage per hit (5-inch shell = 1.0), size = flash/tracer size.
const GUNS := {
	"us5in38": {"cal": "5-inch/38", "vel": 790.0, "reload": 4.2, "range_max": 8800.0, "per_mount": 1, "dmg": 1.0, "apex": 0.05, "size": 1.0},
	"jp127": {"cal": "12.7 cm", "vel": 910.0, "reload": 5.5, "range_max": 9000.0, "per_mount": 2, "dmg": 1.1, "apex": 0.05, "size": 1.0},
	"bofors40": {"cal": "40 mm Bofors", "vel": 880.0, "reload": 1.3, "range_max": 2600.0, "per_mount": 2, "dmg": 0.32, "apex": 0.02, "size": 0.45},
	"m4_37": {"cal": "37 mm", "vel": 610.0, "reload": 1.4, "range_max": 2000.0, "per_mount": 1, "dmg": 0.26, "apex": 0.025, "size": 0.4},
	"oerlikon20": {"cal": "20 mm Oerlikon", "vel": 830.0, "reload": 0.7, "range_max": 1400.0, "per_mount": 2, "dmg": 0.11, "apex": 0.015, "size": 0.3},
	"browning50": {"cal": ".50 cal", "vel": 890.0, "reload": 0.5, "range_max": 1000.0, "per_mount": 2, "dmg": 0.06, "apex": 0.01, "size": 0.25},
	"jp25": {"cal": "25 mm", "vel": 900.0, "reload": 1.4, "range_max": 1500.0, "per_mount": 2, "dmg": 0.12, "apex": 0.015, "size": 0.3},
	"jp13": {"cal": "13 mm", "vel": 800.0, "reload": 1.0, "range_max": 1000.0, "per_mount": 1, "dmg": 0.06, "apex": 0.01, "size": 0.25},
	"jp77": {"cal": "7.7 mm", "vel": 730.0, "reload": 1.0, "range_max": 700.0, "per_mount": 1, "dmg": 0.03, "apex": 0.01, "size": 0.2},
	"jp8cm": {"cal": "8 cm", "vel": 600.0, "reload": 6.0, "range_max": 5000.0, "per_mount": 1, "dmg": 0.55, "apex": 0.04, "size": 0.7},
	# cruiser, battleship and escort guns (build 0.5). dmg is relative to a 5-inch shell; pen = how well
	# the shell gets through heavy armour (1.0 = 8-inch).
	"us5in38tw": {"cal": "5-inch/38 twin", "vel": 790.0, "reload": 4.2, "range_max": 8800.0, "per_mount": 2, "dmg": 1.0, "apex": 0.05, "size": 1.0},
	"us5in25": {"cal": "5-inch/25", "vel": 660.0, "reload": 4.5, "range_max": 7000.0, "per_mount": 1, "dmg": 0.9, "apex": 0.05, "size": 0.9},
	"us3in50": {"cal": "3-inch/50", "vel": 820.0, "reload": 3.5, "range_max": 6000.0, "per_mount": 1, "dmg": 0.45, "apex": 0.04, "size": 0.7},
	"us6in47": {"cal": "6-inch/47", "vel": 810.0, "reload": 6.5, "range_max": 11500.0, "per_mount": 3, "dmg": 1.8, "apex": 0.06, "size": 1.3, "pen": 0.6},
	"us8in55": {"cal": "8-inch/55", "vel": 760.0, "reload": 12.0, "range_max": 14000.0, "per_mount": 3, "dmg": 3.6, "apex": 0.07, "size": 1.7, "pen": 1.0},
	"us14in45": {"cal": "14-inch/45", "vel": 790.0, "reload": 28.0, "range_max": 16000.0, "per_mount": 2, "dmg": 9.0, "apex": 0.08, "size": 2.3, "pen": 2.2},
	"us16in45": {"cal": "16-inch/45", "vel": 700.0, "reload": 30.0, "range_max": 17500.0, "per_mount": 3, "dmg": 13.0, "apex": 0.09, "size": 2.6, "pen": 3.0},
	"us16in50": {"cal": "16-inch/50", "vel": 760.0, "reload": 30.0, "range_max": 19000.0, "per_mount": 3, "dmg": 13.5, "apex": 0.09, "size": 2.6, "pen": 3.3},
	"bofors40q": {"cal": "40 mm Bofors quad", "vel": 880.0, "reload": 1.3, "range_max": 2600.0, "per_mount": 4, "dmg": 0.32, "apex": 0.02, "size": 0.45},
	"jp100": {"cal": "10 cm", "vel": 1000.0, "reload": 3.2, "range_max": 9000.0, "per_mount": 2, "dmg": 0.7, "apex": 0.05, "size": 0.9},
	"jp140": {"cal": "14 cm", "vel": 850.0, "reload": 7.0, "range_max": 9500.0, "per_mount": 1, "dmg": 1.4, "apex": 0.05, "size": 1.1, "pen": 0.4},
	"jp155": {"cal": "15.5 cm", "vel": 920.0, "reload": 7.0, "range_max": 11500.0, "per_mount": 3, "dmg": 1.8, "apex": 0.06, "size": 1.3, "pen": 0.6},
	"jp203": {"cal": "20.3 cm", "vel": 835.0, "reload": 12.0, "range_max": 14000.0, "per_mount": 2, "dmg": 3.6, "apex": 0.07, "size": 1.7, "pen": 1.0},
	"jp356": {"cal": "35.6 cm", "vel": 775.0, "reload": 30.0, "range_max": 17000.0, "per_mount": 2, "dmg": 9.5, "apex": 0.08, "size": 2.3, "pen": 2.3},
	"jp410": {"cal": "41 cm", "vel": 780.0, "reload": 32.0, "range_max": 18000.0, "per_mount": 2, "dmg": 13.0, "apex": 0.09, "size": 2.6, "pen": 3.1},
	"jp460": {"cal": "46 cm", "vel": 780.0, "reload": 35.0, "range_max": 21000.0, "per_mount": 3, "dmg": 18.0, "apex": 0.1, "size": 3.0, "pen": 4.0},
}

## Firing arcs: [center, half-width] in degrees of relative bearing (+ = starboard).
const ARCS := {"fwd": [0.0, 150.0], "aft": [180.0, 150.0], "port": [-90.0, 135.0], "stbd": [90.0, 135.0], "all": [0.0, 180.0]}

## Ship classes. Positions along the hull (x) are meters from amidships, + is forward.
## Modules: [label, kind, x position, hit points]
## cls = fleet role (pt, dd, de, cl, ca, bb, cv, cve, ss, merchant, barge); doctrine = how the AI
## fights the ship ("ijn_dd": Japanese destroyer tactics, torpedo first, avoid gun duels).
## Hand-built classes (build 0.1-0.2). The rest come from ShipTypes (generated from tools/ship_builder/specs.py).
const BASE_TYPES := {
	"fletcher": {
		"name": "Fletcher class", "nation": "us",
		"models": {"m21": "res://assets/models/fletcher_m21.glb", "m22": "res://assets/models/fletcher_m22.glb"},
		"L": 114.8, "B": 12.0, "max_kn": 36.0, "turn": 3.2, "crew": 329, "displacement": 2500.0,
		"gun": "us5in38", "role": "warship", "cls": "dd", "size_vis": 1.0, "draft": 3.8,
		"mounts": [
			{"g": "Mount51", "x": 40.5, "stow": 0.0, "arc": "fwd"},
			{"g": "Mount52", "x": 31.0, "stow": 0.0, "arc": "fwd"},
			{"g": "Mount53", "x": -27.5, "stow": PI, "arc": "aft"},
			{"g": "Mount54", "x": -36.0, "stow": PI, "arc": "aft"},
			{"g": "Mount55", "x": -45.5, "stow": PI, "arc": "aft"},
		],
		"torps": [{"g": "Torpedo1", "x": 0.5, "n": 5}, {"g": "Torpedo2", "x": -15.0, "n": 5}],
		"torp": {"name": "Mark 15", "speed_kn": 45.0, "range": 3500.0, "dud": 0.12, "flood": 220.0},
		"aa": ["Bofors1", "Bofors2", "Bofors3", "Bofors4", "Bofors5", "Oerlikon1", "Oerlikon2", "Oerlikon3", "Oerlikon4", "Oerlikon5", "Oerlikon6", "Oerlikon7", "Oerlikon8"],
		"radar": 6000.0, "smoke": true, "night_eye": 1.0,
		"funnels": [6.3, -8.3], "funnel_top": 20.0,
		"modules": [["Bridge", "bridge", 22.0, 4.0], ["Director", "director", 21.0, 2.0], ["Forward boilers", "engine", 6.0, 4.0], ["Aft engines", "engine", -9.0, 4.0],
			["Steering", "steering", -53.0, 3.0], ["Forward magazine", "magazine", 35.0, 4.0], ["Aft magazine", "magazine", -40.0, 4.0]],
	},
	"kagero": {
		"name": "Kagero class", "nation": "ijn",
		"models": {"m21": "res://assets/models/kagero.glb", "m22": "res://assets/models/kagero.glb"},
		"L": 118.5, "B": 10.8, "max_kn": 35.5, "turn": 3.6, "crew": 239, "displacement": 2500.0,
		"gun": "jp127", "role": "warship", "cls": "dd", "doctrine": "ijn_dd", "size_vis": 1.0, "draft": 3.8,
		"mounts": [
			{"g": "Mount1", "x": 39.0, "stow": 0.0, "arc": "fwd"},
			{"g": "Mount2", "x": -30.0, "stow": PI, "arc": "aft"},
			{"g": "Mount3", "x": -38.5, "stow": PI, "arc": "aft"},
		],
		"torps": [{"g": "Torpedo1", "x": 1.0, "n": 4}, {"g": "Torpedo2", "x": -17.5, "n": 4}],
		"torp": {"name": "Type 93", "speed_kn": 48.0, "range": 8000.0, "dud": 0.03, "flood": 330.0},
		"aa": ["AA1", "AA2"], "radar": 0.0, "smoke": true, "night_eye": 1.5,
		"funnels": [9.8, -7.1], "funnel_top": 18.0,
		"modules": [["Bridge", "bridge", 26.0, 4.0], ["Director", "director", 26.0, 2.0], ["Forward boilers", "engine", 8.0, 4.0], ["Aft engines", "engine", -8.0, 4.0],
			["Steering", "steering", -55.0, 3.0], ["Forward magazine", "magazine", 36.0, 4.0], ["Aft magazine", "magazine", -35.0, 4.0]],
	},
	"pt_elco": {
		"name": "Elco 80-ft PT boat", "nation": "us",
		"models": {"m21": "res://assets/models/pt_elco.glb", "m22": "res://assets/models/pt_elco.glb"},
		"L": 24.4, "B": 6.3, "max_kn": 40.0, "turn": 11.0, "crew": 11, "displacement": 56.0,
		"gun": "bofors40", "role": "pt", "cls": "pt", "size_vis": 0.5, "draft": 1.6,
		"mounts": [
			{"g": "Gun37", "x": 8.6, "stow": 0.0, "arc": "fwd", "gun": "m4_37"},
			{"g": "Oerlikon", "x": 6.3, "stow": 0.0, "arc": "fwd", "gun": "oerlikon20"},
			{"g": "Twin50Port", "x": 1.8, "stow": -PI / 2, "arc": "port", "gun": "browning50"},
			{"g": "Twin50Stbd", "x": -0.9, "stow": PI / 2, "arc": "stbd", "gun": "browning50"},
			{"g": "Bofors", "x": -9.6, "stow": PI, "arc": "aft", "gun": "bofors40"},
		],
		"torps": [{"g": "Torpedo1", "x": 2.9, "n": 1, "fixed": true}, {"g": "Torpedo2", "x": 2.9, "n": 1, "fixed": true},
			{"g": "Torpedo3", "x": -4.1, "n": 1, "fixed": true}, {"g": "Torpedo4", "x": -4.1, "n": 1, "fixed": true}],
		"torp": {"name": "Mark 13", "speed_kn": 33.5, "range": 2500.0, "dud": 0.1, "flood": 150.0},
		"aa": [], "radar": 3500.0, "smoke": true, "smoke_x": -12.0, "night_eye": 1.0,
		"funnels": [], "funnel_top": 3.0,
		"modules": [["Cockpit", "bridge", 0.5, 2.0], ["Gas tanks", "fuel", -1.5, 2.0], ["Port engine", "engine", -4.5, 1.5], ["Center engine", "engine", -6.0, 1.5],
			["Starboard engine", "engine", -7.5, 1.5], ["Rudders", "steering", -11.5, 1.0]],
	},
	"jp_mtb": {
		# Japanese motor torpedo boat (Type T-14 / T-38): the same hull shape as the Elco, so it
		# borrows the model; slower, lighter guns, two 45 cm torpedoes. Easy prey and good practice.
		"name": "Type T-14 motor torpedo boat", "nation": "ijn",
		"models": {"m21": "res://assets/models/pt_elco.glb", "m22": "res://assets/models/pt_elco.glb"},
		"L": 18.0, "B": 4.3, "max_kn": 33.0, "turn": 11.0, "crew": 7, "displacement": 15.0,
		"gun": "jp25", "role": "pt", "cls": "pt", "size_vis": 0.4, "draft": 1.0, "gunnery": 0.7,
		"mounts": [
			{"g": "Gun37", "x": 8.6, "stow": 0.0, "arc": "fwd", "gun": "jp25"},
			{"g": "Bofors", "x": -9.6, "stow": PI, "arc": "aft", "gun": "jp13"},
		],
		"torps": [{"g": "Torpedo1", "x": 2.9, "n": 1, "fixed": true}, {"g": "Torpedo2", "x": 2.9, "n": 1, "fixed": true}],
		"torp": {"name": "Type 2 (45 cm)", "speed_kn": 39.0, "range": 2000.0, "dud": 0.08, "flood": 120.0},
		"aa": [], "radar": 0.0, "smoke": false, "night_eye": 1.1,
		"funnels": [], "funnel_top": 3.0,
		"modules": [["Cockpit", "bridge", 0.5, 1.5], ["Petrol tanks", "fuel", -1.5, 1.5], ["Engines", "engine", -5.5, 1.5], ["Rudders", "steering", -11.5, 1.0]],
	},
	"daihatsu": {
		"name": "Daihatsu landing barge", "nation": "ijn",
		"models": {"m21": "res://assets/models/daihatsu.glb", "m22": "res://assets/models/daihatsu.glb"},
		"L": 14.9, "B": 3.35, "max_kn": 8.0, "turn": 7.0, "crew": 14, "displacement": 20.0,
		"gun": "jp77", "role": "barge", "cls": "barge", "gunnery": 0.5, "size_vis": 0.45, "draft": 0.8,
		"mounts": [{"g": "MG1", "x": -6.6, "stow": PI, "arc": "all", "gun": "jp77"}, {"g": "MG2", "x": 4.8, "stow": 0.0, "arc": "all", "gun": "jp77"}],
		"torps": [], "torp": {}, "aa": [], "radar": 0.0, "smoke": false, "night_eye": 1.3, "funnels": [], "funnel_top": 2.0,
		"modules": [["Engine", "engine", -4.6, 1.5], ["Steering", "steering", -6.6, 1.0], ["Cargo", "cargo", 0.5, 2.0]],
	},
	"daihatsu_gun": {
		"name": "Armed Daihatsu (gun barge)", "nation": "ijn",
		"models": {"m21": "res://assets/models/daihatsu.glb", "m22": "res://assets/models/daihatsu.glb"},
		"L": 14.9, "B": 3.35, "max_kn": 8.0, "turn": 7.0, "crew": 16, "displacement": 22.0,
		"gun": "jp25", "role": "barge", "cls": "barge", "gunnery": 0.6, "size_vis": 0.45, "draft": 0.8,
		"mounts": [{"g": "MG1", "x": -6.6, "stow": PI, "arc": "all", "gun": "jp13"}, {"g": "MG2", "x": 4.8, "stow": 0.0, "arc": "all", "gun": "jp25"}],
		"torps": [], "torp": {}, "aa": [], "radar": 0.0, "smoke": false, "night_eye": 1.3, "funnels": [], "funnel_top": 2.0,
		"modules": [["Engine", "engine", -4.6, 1.5], ["Steering", "steering", -6.6, 1.0], ["Ammunition", "magazine", 1.0, 1.5]],
	},
	"cargo_maru": {
		"name": "Cargo ship (maru)", "nation": "ijn",
		"models": {"m21": "res://assets/models/cargo_maru.glb", "m22": "res://assets/models/cargo_maru.glb"},
		"L": 110.0, "B": 15.2, "max_kn": 12.0, "turn": 1.4, "crew": 60, "displacement": 8000.0,
		"gun": "jp8cm", "role": "merchant", "cls": "merchant", "gunnery": 0.6, "size_vis": 1.3, "draft": 6.5,
		"mounts": [{"g": "Gun1", "x": -51.5, "stow": PI, "arc": "aft", "gun": "jp8cm"}, {"g": "AA1", "x": 9.5, "stow": 0.0, "arc": "all", "gun": "jp13"}],
		"torps": [], "torp": {}, "aa": [], "radar": 0.0, "smoke": false, "night_eye": 1.0, "funnels": [-3.5], "funnel_top": 19.0,
		"modules": [["Bridge", "bridge", 9.5, 4.0], ["Engine room", "engine", -6.0, 5.0], ["Steering", "steering", -53.0, 3.0],
			["No. 1 hold", "cargo", 36.5, 4.0], ["No. 2 hold", "cargo", 23.5, 4.0], ["No. 3 hold", "cargo", -21.5, 4.0], ["No. 4 hold", "cargo", -34.0, 4.0]],
	},
	"tanker_maru": {
		"name": "Oil tanker (maru)", "nation": "ijn",
		"models": {"m21": "res://assets/models/tanker_maru.glb", "m22": "res://assets/models/tanker_maru.glb"},
		"L": 125.0, "B": 16.4, "max_kn": 11.0, "turn": 1.2, "crew": 50, "displacement": 10000.0,
		"gun": "jp8cm", "role": "merchant", "cls": "merchant", "gunnery": 0.6, "size_vis": 1.3, "draft": 7.5,
		"mounts": [{"g": "Gun1", "x": -59.0, "stow": PI, "arc": "aft", "gun": "jp8cm"}, {"g": "AA1", "x": 5.5, "stow": 0.0, "arc": "all", "gun": "jp13"}],
		"torps": [], "torp": {}, "aa": [], "radar": 0.0, "smoke": false, "night_eye": 1.0, "funnels": [-53.5], "funnel_top": 20.0,
		"modules": [["Bridge", "bridge", 5.0, 4.0], ["Engine room", "engine", -52.0, 5.0], ["Steering", "steering", -60.0, 3.0],
			["Forward tanks", "oil", 30.0, 5.0], ["After tanks", "oil", -22.0, 5.0]],
	},
}

## Every ship class: the hand-built ones plus the generated ones.
static var TYPES: Dictionary = _all_types()

static func _all_types() -> Dictionary:
	var d := {}
	for k in BASE_TYPES:
		d[k] = BASE_TYPES[k]
	for k in ShipTypes.TYPES:
		d[k] = ShipTypes.TYPES[k]
	return d


## Engine telegraph orders.
const TELE := [
	{"n": "Back", "kn": -12.0}, {"n": "Stop", "kn": 0.0}, {"n": "1/3", "kn": 10.0}, {"n": "2/3", "kn": 20.0},
	{"n": "Std", "kn": 25.0}, {"n": "Full", "kn": 31.0}, {"n": "Flank", "kn": 36.0},
]

## Weather and time of day. vis = how far a lookout can see a ship (m).
const WEATHER := {
	"clear": {"name": "Clear day", "vis": 10000.0, "night": false,
		"deep": Color(0.02, 0.13, 0.27), "shallow": Color(0.06, 0.3, 0.45), "sun": Color(1.0, 0.96, 0.88), "sun_energy": 1.15,
		"sky": Color(0.45, 0.58, 0.7), "ambient": 0.32, "fog": Color(0.66, 0.76, 0.84), "fog_k": 0.03, "chop": 0.9, "spec": 0.45,
		"sun_dir": Vector3(-0.45, -0.8, -0.38), "lit": 1.0},
	"overcast": {"name": "Overcast", "vis": 6500.0, "night": false,
		"deep": Color(0.07, 0.15, 0.18), "shallow": Color(0.18, 0.27, 0.29), "sun": Color(0.85, 0.88, 0.92), "sun_energy": 0.7,
		"sky": Color(0.42, 0.45, 0.48), "ambient": 0.65, "fog": Color(0.5, 0.54, 0.57), "fog_k": 0.1, "chop": 1.3, "spec": 0.2,
		"sun_dir": Vector3(-0.2, -0.95, -0.25), "lit": 0.75},
	"fog": {"name": "Fog", "vis": 1400.0, "night": false,
		"deep": Color(0.11, 0.18, 0.2), "shallow": Color(0.22, 0.3, 0.31), "sun": Color(0.85, 0.87, 0.9), "sun_energy": 0.55,
		"sky": Color(0.6, 0.64, 0.66), "ambient": 0.7, "fog": Color(0.62, 0.66, 0.68), "fog_k": 0.6, "chop": 0.5, "spec": 0.08,
		"sun_dir": Vector3(-0.2, -0.95, -0.25), "lit": 0.8},
	"night": {"name": "Night", "vis": 1800.0, "night": true,
		"deep": Color(0.03, 0.09, 0.15), "shallow": Color(0.07, 0.16, 0.23), "sun": Color(0.6, 0.7, 0.95), "sun_energy": 0.6,
		"sky": Color(0.05, 0.07, 0.12), "ambient": 0.4, "fog": Color(0.01, 0.02, 0.035), "fog_k": 0.03, "chop": 0.8, "spec": 0.35,
		"sun_dir": Vector3(0.4, -0.7, -0.5), "lit": 0.5},
}


## Aircraft. speed in knots (real), hp = planes lost per unit of flak, rating = air-to-air strength,
## bomb = damage of one bomb hit in 5-inch-shell units, torp = aerial torpedo.
const AIRCRAFT := {
	"f4f": {"name": "Wildcat", "nation": "us", "kind": "fighter", "speed": 280.0, "rating": 1.0, "model": "res://assets/models/plane_us_fighter.glb"},
	"f6f": {"name": "Hellcat", "nation": "us", "kind": "fighter", "speed": 330.0, "rating": 1.6, "model": "res://assets/models/plane_us_fighter.glb"},
	"sbd": {"name": "Dauntless", "nation": "us", "kind": "dive", "speed": 220.0, "rating": 0.4, "bomb": 4.5, "model": "res://assets/models/plane_us_bomber.glb"},
	"sb2c": {"name": "Helldiver", "nation": "us", "kind": "dive", "speed": 250.0, "rating": 0.45, "bomb": 5.0, "model": "res://assets/models/plane_us_bomber.glb"},
	"tbf": {"name": "Avenger", "nation": "us", "kind": "torpedo", "speed": 240.0, "rating": 0.4, "torp": {"name": "Mark 13 (aerial)", "speed_kn": 33.5, "range": 2200.0, "dud": 0.2, "flood": 200.0}, "model": "res://assets/models/plane_us_bomber.glb"},
	"os2u": {"name": "Kingfisher", "nation": "us", "kind": "scout", "speed": 150.0, "rating": 0.2, "model": "res://assets/models/plane_us_float.glb"},
	"a6m": {"name": "Zero", "nation": "ijn", "kind": "fighter", "speed": 290.0, "rating": 1.3, "model": "res://assets/models/plane_jp_fighter.glb"},
	"d3a": {"name": "Val", "nation": "ijn", "kind": "dive", "speed": 220.0, "rating": 0.35, "bomb": 3.0, "model": "res://assets/models/plane_jp_bomber.glb"},
	"b5n": {"name": "Kate", "nation": "ijn", "kind": "torpedo", "speed": 210.0, "rating": 0.3, "torp": {"name": "Type 91 (aerial)", "speed_kn": 42.0, "range": 2000.0, "dud": 0.05, "flood": 240.0}, "model": "res://assets/models/plane_jp_bomber.glb"},
	"e13a": {"name": "Jake", "nation": "ijn", "kind": "scout", "speed": 200.0, "rating": 0.2, "model": "res://assets/models/plane_jp_float.glb"},
}

## Air groups by carrier size: [type, planes] per squadron. "year" picks the aircraft types.
static func air_group(hangar: String, count: int) -> Array:
	var out := []
	if hangar == "ijn":
		var third := maxi(6, int(count / 3.0))
		out.append(["a6m", third]); out.append(["d3a", third]); out.append(["b5n", count - 2 * third])
	else:
		var fighters := maxi(6, int(count * 0.4))
		var dive := maxi(6, int(count * 0.35))
		out.append(["f6f" if count >= 60 else "f4f", fighters]); out.append(["sb2c" if count >= 80 else "sbd", dive]); out.append(["tbf", maxi(4, count - fighters - dive)])
	# split big squadrons so strikes arrive in waves
	var split := []
	for sq in out:
		var n: int = sq[1]
		while n > 12:
			split.append([sq[0], 12]); n -= 12
		split.append([sq[0], n])
	return split
