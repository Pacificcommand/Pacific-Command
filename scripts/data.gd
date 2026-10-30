class_name Data
## Game data: ship classes, engine telegraph, weather.
## Distances are in meters and use the "semi-realistic" battle scale from the
## design doc: gun, radar and spotting ranges are about half of real life.

const KN := 0.5144   # meters per second in one knot
const YD := 0.9144   # meters in one yard

## Guns. range_max in meters (half of real, see the design doc), reload in seconds per burst,
## per_mount = shells per burst, dmg = damage per hit (5-inch shell = 1.0), size = flash/tracer size.
const GUNS := {
	"us5in38": {"cal": "5-inch/38", "vel": 790.0, "reload": 4.2, "range_max": 8000.0, "per_mount": 1, "dmg": 1.0, "apex": 0.05, "size": 1.0},
	"jp127": {"cal": "12.7 cm", "vel": 910.0, "reload": 5.5, "range_max": 9000.0, "per_mount": 2, "dmg": 1.1, "apex": 0.05, "size": 1.0},
	"bofors40": {"cal": "40 mm Bofors", "vel": 880.0, "reload": 1.3, "range_max": 2600.0, "per_mount": 2, "dmg": 0.32, "apex": 0.02, "size": 0.45},
	"m4_37": {"cal": "37 mm", "vel": 610.0, "reload": 1.4, "range_max": 2000.0, "per_mount": 1, "dmg": 0.26, "apex": 0.025, "size": 0.4},
	"oerlikon20": {"cal": "20 mm Oerlikon", "vel": 830.0, "reload": 0.7, "range_max": 1400.0, "per_mount": 2, "dmg": 0.11, "apex": 0.015, "size": 0.3},
	"browning50": {"cal": ".50 cal", "vel": 890.0, "reload": 0.5, "range_max": 1000.0, "per_mount": 2, "dmg": 0.06, "apex": 0.01, "size": 0.25},
	"jp25": {"cal": "25 mm", "vel": 900.0, "reload": 1.4, "range_max": 1500.0, "per_mount": 2, "dmg": 0.12, "apex": 0.015, "size": 0.3},
	"jp13": {"cal": "13 mm", "vel": 800.0, "reload": 1.0, "range_max": 1000.0, "per_mount": 1, "dmg": 0.06, "apex": 0.01, "size": 0.25},
	"jp77": {"cal": "7.7 mm", "vel": 730.0, "reload": 1.0, "range_max": 700.0, "per_mount": 1, "dmg": 0.03, "apex": 0.01, "size": 0.2},
	"jp8cm": {"cal": "8 cm", "vel": 600.0, "reload": 6.0, "range_max": 5000.0, "per_mount": 1, "dmg": 0.55, "apex": 0.04, "size": 0.7},
}

## Firing arcs: [center, half-width] in degrees of relative bearing (+ = starboard).
const ARCS := {"fwd": [0.0, 150.0], "aft": [180.0, 150.0], "port": [-90.0, 135.0], "stbd": [90.0, 135.0], "all": [0.0, 180.0]}

## Ship classes. Positions along the hull (x) are meters from amidships, + is forward.
## Modules: [label, kind, x position, hit points]
const TYPES := {
	"fletcher": {
		"name": "Fletcher class", "nation": "us",
		"models": {"m21": "res://assets/models/fletcher_m21.glb", "m22": "res://assets/models/fletcher_m22.glb"},
		"L": 114.8, "B": 12.0, "max_kn": 36.0, "turn": 3.2, "crew": 329, "displacement": 2500.0,
		"gun": "us5in38", "role": "warship", "size_vis": 1.0, "draft": 3.8,
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
		"L": 118.5, "B": 10.8, "max_kn": 35.0, "turn": 3.0, "crew": 239, "displacement": 2500.0,
		"gun": "jp127", "role": "warship", "size_vis": 1.0, "draft": 3.8,
		"mounts": [
			{"g": "Mount1", "x": 39.0, "stow": 0.0, "arc": "fwd"},
			{"g": "Mount2", "x": -30.0, "stow": PI, "arc": "aft"},
			{"g": "Mount3", "x": -38.5, "stow": PI, "arc": "aft"},
		],
		"torps": [{"g": "Torpedo1", "x": 1.0, "n": 4}, {"g": "Torpedo2", "x": -17.5, "n": 4}],
		"torp": {"name": "Type 93", "speed_kn": 48.0, "range": 8000.0, "dud": 0.03, "flood": 330.0},
		"aa": ["AA1", "AA2"], "radar": 0.0, "smoke": false, "night_eye": 1.5,
		"funnels": [9.8, -7.1], "funnel_top": 18.0,
		"modules": [["Bridge", "bridge", 26.0, 4.0], ["Director", "director", 26.0, 2.0], ["Forward boilers", "engine", 8.0, 4.0], ["Aft engines", "engine", -8.0, 4.0],
			["Steering", "steering", -55.0, 3.0], ["Forward magazine", "magazine", 36.0, 4.0], ["Aft magazine", "magazine", -35.0, 4.0]],
	},
	"pt_elco": {
		"name": "Elco 80-ft PT boat", "nation": "us",
		"models": {"m21": "res://assets/models/pt_elco.glb", "m22": "res://assets/models/pt_elco.glb"},
		"L": 24.4, "B": 6.3, "max_kn": 40.0, "turn": 11.0, "crew": 11, "displacement": 56.0,
		"gun": "bofors40", "role": "pt", "size_vis": 0.5, "draft": 1.6,
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
	"daihatsu": {
		"name": "Daihatsu landing barge", "nation": "ijn",
		"models": {"m21": "res://assets/models/daihatsu.glb", "m22": "res://assets/models/daihatsu.glb"},
		"L": 14.9, "B": 3.35, "max_kn": 8.0, "turn": 7.0, "crew": 14, "displacement": 20.0,
		"gun": "jp77", "role": "barge", "gunnery": 0.5, "size_vis": 0.45, "draft": 0.8,
		"mounts": [{"g": "MG1", "x": -6.6, "stow": PI, "arc": "all", "gun": "jp77"}, {"g": "MG2", "x": 4.8, "stow": 0.0, "arc": "all", "gun": "jp77"}],
		"torps": [], "torp": {}, "aa": [], "radar": 0.0, "smoke": false, "night_eye": 1.3, "funnels": [], "funnel_top": 2.0,
		"modules": [["Engine", "engine", -4.6, 1.5], ["Steering", "steering", -6.6, 1.0], ["Cargo", "cargo", 0.5, 2.0]],
	},
	"daihatsu_gun": {
		"name": "Armed Daihatsu (gun barge)", "nation": "ijn",
		"models": {"m21": "res://assets/models/daihatsu.glb", "m22": "res://assets/models/daihatsu.glb"},
		"L": 14.9, "B": 3.35, "max_kn": 8.0, "turn": 7.0, "crew": 16, "displacement": 22.0,
		"gun": "jp25", "role": "barge", "gunnery": 0.6, "size_vis": 0.45, "draft": 0.8,
		"mounts": [{"g": "MG1", "x": -6.6, "stow": PI, "arc": "all", "gun": "jp13"}, {"g": "MG2", "x": 4.8, "stow": 0.0, "arc": "all", "gun": "jp25"}],
		"torps": [], "torp": {}, "aa": [], "radar": 0.0, "smoke": false, "night_eye": 1.3, "funnels": [], "funnel_top": 2.0,
		"modules": [["Engine", "engine", -4.6, 1.5], ["Steering", "steering", -6.6, 1.0], ["Ammunition", "magazine", 1.0, 1.5]],
	},
	"cargo_maru": {
		"name": "Cargo ship (maru)", "nation": "ijn",
		"models": {"m21": "res://assets/models/cargo_maru.glb", "m22": "res://assets/models/cargo_maru.glb"},
		"L": 110.0, "B": 15.2, "max_kn": 12.0, "turn": 1.4, "crew": 60, "displacement": 8000.0,
		"gun": "jp8cm", "role": "merchant", "gunnery": 0.6, "size_vis": 1.3, "draft": 6.5,
		"mounts": [{"g": "Gun1", "x": -51.5, "stow": PI, "arc": "aft", "gun": "jp8cm"}, {"g": "AA1", "x": 9.5, "stow": 0.0, "arc": "all", "gun": "jp13"}],
		"torps": [], "torp": {}, "aa": [], "radar": 0.0, "smoke": false, "night_eye": 1.0, "funnels": [-3.5], "funnel_top": 19.0,
		"modules": [["Bridge", "bridge", 9.5, 4.0], ["Engine room", "engine", -6.0, 5.0], ["Steering", "steering", -53.0, 3.0],
			["No. 1 hold", "cargo", 36.5, 4.0], ["No. 2 hold", "cargo", 23.5, 4.0], ["No. 3 hold", "cargo", -21.5, 4.0], ["No. 4 hold", "cargo", -34.0, 4.0]],
	},
	"tanker_maru": {
		"name": "Oil tanker (maru)", "nation": "ijn",
		"models": {"m21": "res://assets/models/tanker_maru.glb", "m22": "res://assets/models/tanker_maru.glb"},
		"L": 125.0, "B": 16.4, "max_kn": 11.0, "turn": 1.2, "crew": 50, "displacement": 10000.0,
		"gun": "jp8cm", "role": "merchant", "gunnery": 0.6, "size_vis": 1.3, "draft": 7.5,
		"mounts": [{"g": "Gun1", "x": -59.0, "stow": PI, "arc": "aft", "gun": "jp8cm"}, {"g": "AA1", "x": 5.5, "stow": 0.0, "arc": "all", "gun": "jp13"}],
		"torps": [], "torp": {}, "aa": [], "radar": 0.0, "smoke": false, "night_eye": 1.0, "funnels": [-53.5], "funnel_top": 20.0,
		"modules": [["Bridge", "bridge", 5.0, 4.0], ["Engine room", "engine", -52.0, 5.0], ["Steering", "steering", -60.0, 3.0],
			["Forward tanks", "oil", 30.0, 5.0], ["After tanks", "oil", -22.0, 5.0]],
	},
}

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
