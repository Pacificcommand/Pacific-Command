class_name Data
## Game data: ship classes, engine telegraph, weather.
## Distances are in meters and use the "semi-realistic" battle scale from the
## design doc: gun, radar and spotting ranges are about half of real life.

const KN := 0.5144   # meters per second in one knot
const YD := 0.9144   # meters in one yard

## Ship classes. Positions along the hull (x) are meters from amidships, + is forward.
## Modules: [label, kind, x position, hit points]
const TYPES := {
	"fletcher": {
		"name": "Fletcher class", "nation": "us",
		"models": {"m21": "res://assets/models/fletcher_m21.glb", "m22": "res://assets/models/fletcher_m22.glb"},
		"L": 114.8, "B": 12.0, "max_kn": 36.0, "turn": 3.2, "crew": 329, "displacement": 2500.0,
		"gun": {"cal": "5-inch/38", "vel": 790.0, "reload": 4.2, "range_max": 8000.0, "per_mount": 1, "dmg": 1.0, "apex": 0.05},
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
		"gun": {"cal": "12.7 cm", "vel": 910.0, "reload": 5.5, "range_max": 9000.0, "per_mount": 2, "dmg": 1.1, "apex": 0.05},
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
