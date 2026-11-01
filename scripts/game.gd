extends Node
## Autoload "Game": settings (graphics, sound, keys), save slots, and hand-over between the
## main menu and the battle scene. Settings live in user://settings.cfg, saves in user://saves/.

signal graphics_changed

const CFG := "user://settings.cfg"
const SAVE_DIR := "user://saves"
const SLOTS := 5
const VERSION := "0.13"

## Graphics and sound settings with their defaults.
var settings := {
	"quality": "high",          # low, medium, high
	"fullscreen": true,
	"resolution": "1920x1080",
	"vsync": true,
	"ui_scale": 1.0,
	"pyro": true,               # PYROLUX fire and explosion addon, when installed
	"vol_master": 1.0, "vol_music": 0.7, "vol_fx": 1.0, "vol_radio": 1.0,
	"pan_left": false,          # drag the camera with the left button instead of the right
}
const RESOLUTIONS := ["1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"]

## Rebindable actions: name -> [label, default key]. Order matters for the settings list.
const ACTIONS := [
	["tele_up", "Engines up", KEY_W], ["tele_down", "Engines down", KEY_S],
	["rudder_left", "Rudder left", KEY_A], ["rudder_right", "Rudder right", KEY_D], ["rudder_center", "Rudder amidships", KEY_Q],
	["fire", "Open / cease fire", KEY_F], ["aim_mode", "Crew / manual aim", KEY_M], ["torpedo", "Torpedo aim", KEY_T],
	["smoke", "Lay smoke", KEY_Z], ["star", "Fire a star shell", KEY_I], ["next_target", "Next target", KEY_TAB],
	["follow", "Follow salvos", KEY_V], ["camera", "Camera: own ship / target", KEY_C], ["recenter", "Lock camera back on", KEY_HOME],
	["pause", "Tactical pause", KEY_SPACE], ["slow", "Slow ¼×", KEY_1], ["normal", "Normal speed", KEY_2], ["fast", "Fast 3×", KEY_3],
	["strike", "Launch air strike", KEY_L],
	["dive", "Submarine: dive (periscope depth, then deep)", KEY_X], ["surface", "Submarine: come up", KEY_E],
	["charges", "Drop depth charges", KEY_G], ["hedgehog", "Fire hedgehog", KEY_H],
	["menu", "Pause menu", KEY_ESCAPE],
]
var keys := {}                 # action -> keycode

## Career (sandbox until the career build): rank index into Missions.RANKS, reputation to spend on support.
const CAREER_FILE := "user://career.json"
var career := {"rank": 3, "reputation": 900, "xp": 0, "year": 1943, "missions": 0, "won": 0}

## True while a campaign battle is being fought or set up (career modifiers apply).
func campaign_active() -> bool:
	return not mission.is_empty() and not campaign.is_empty()

## Campaign (operations map) state, saved with the career. Empty = no campaign started.
const CAMPAIGN_FILE := "user://campaign.json"
var campaign := {}
## The mission the operations map sent the battle scene to fight: {plan, weather, kind, contact, zone, op}.
## Empty for sandbox battles. last_result carries the outcome back to the map.
var mission := {}
var last_result := {}
var last_result_letter := {}

var pending_load := -1         # save slot the battle scene should load when it opens
var start_scenario := "dd"     # mission the battle scene should set up

var _bus := {}


func _ready() -> void:
	for a in ACTIONS:
		keys[a[0]] = a[2]
	_make_buses()
	load_settings()
	load_career()
	load_campaign()
	apply_all()


func load_career() -> void:
	if FileAccess.file_exists(CAREER_FILE):
		var f := FileAccess.open(CAREER_FILE, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for k in d:
				career[k] = d[k]
			for k in ["rank", "reputation", "xp", "year", "missions", "won", "supply", "spent_points", "pause_uses"]:
				if career.has(k):
					career[k] = int(career[k])
	# older saves: fill in the career systems' fields
	var fresh := Career.fresh()
	for k in fresh:
		if not career.has(k):
			career[k] = fresh[k]
	for o in career.get("officers", []):
		if not o.has("skills"):
			o.skills = []


func load_campaign() -> void:
	campaign = {}
	if FileAccess.file_exists(CAMPAIGN_FILE):
		var f := FileAccess.open(CAMPAIGN_FILE, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			campaign = d


func save_campaign() -> void:
	var f := FileAccess.open(CAMPAIGN_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(campaign))


func save_career() -> void:
	var f := FileAccess.open(CAREER_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(career))


# =====================================================================
# settings file
# =====================================================================

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG) != OK:
		return
	for k in settings:
		settings[k] = cf.get_value("settings", k, settings[k])
	for a in ACTIONS:
		keys[a[0]] = int(cf.get_value("keys", a[0], a[2]))


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("settings", k, settings[k])
	for a in keys:
		cf.set_value("keys", a, keys[a])
	cf.save(CFG)


func apply_all() -> void:
	apply_window()
	apply_graphics()
	apply_audio()
	apply_keys()


# =====================================================================
# window and graphics
# =====================================================================

func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var parts: PackedStringArray = String(settings.resolution).split("x")
	var size := Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i(1920, 1080)
	var win := get_window()
	if settings.fullscreen:
		win.mode = Window.MODE_FULLSCREEN
	else:
		if win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
			win.mode = Window.MODE_WINDOWED
		win.size = size
		var screen := DisplayServer.screen_get_size()
		win.position = (screen - size) / 2
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	win.content_scale_factor = float(settings.ui_scale)


## Quality presets: anti-aliasing, shadows and how many particles the battle may draw.
func quality_params() -> Dictionary:
	match settings.quality:
		"low":
			return {"msaa": Viewport.MSAA_DISABLED, "shadows": false, "shadow_size": 1024, "particles": 0.4, "glow": false}
		"medium":
			return {"msaa": Viewport.MSAA_2X, "shadows": true, "shadow_size": 2048, "particles": 0.7, "glow": true}
	return {"msaa": Viewport.MSAA_4X, "shadows": true, "shadow_size": 4096, "particles": 1.0, "glow": true}


func apply_graphics() -> void:
	var q := quality_params()
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = q.msaa
	RenderingServer.directional_shadow_atlas_set_size(q.shadow_size, true)
	graphics_changed.emit()


# =====================================================================
# sound
# =====================================================================

func _make_buses() -> void:
	for nm in ["Music", "Effects", "Radio"]:
		var i := AudioServer.get_bus_index(nm)
		if i < 0:
			AudioServer.add_bus()
			i = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, nm)
			AudioServer.set_bus_send(i, "Master")
		_bus[nm] = i


func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(settings.vol_master))))
	AudioServer.set_bus_volume_db(_bus.Music, linear_to_db(maxf(0.0001, float(settings.vol_music))))
	AudioServer.set_bus_volume_db(_bus.Effects, linear_to_db(maxf(0.0001, float(settings.vol_fx))))
	AudioServer.set_bus_volume_db(_bus.Radio, linear_to_db(maxf(0.0001, float(settings.vol_radio))))


# =====================================================================
# keys
# =====================================================================

func apply_keys() -> void:
	for a in ACTIONS:
		var nm: String = a[0]
		if not InputMap.has_action(nm):
			InputMap.add_action(nm)
		InputMap.action_erase_events(nm)
		var ev := InputEventKey.new()
		ev.keycode = keys[nm]
		InputMap.action_add_event(nm, ev)


func rebind(action: String, keycode: int) -> void:
	# a key already used elsewhere is taken away from that action
	for a in keys:
		if a != action and keys[a] == keycode:
			keys[a] = KEY_NONE
	keys[action] = keycode
	apply_keys()
	save_settings()


func reset_keys() -> void:
	for a in ACTIONS:
		keys[a[0]] = a[2]
	apply_keys()
	save_settings()


func key_name(action: String) -> String:
	var k: int = keys.get(action, KEY_NONE)
	if k == KEY_NONE:
		return "—"
	return OS.get_keycode_string(k)


## Pressed one of our actions? Checked against the key map so rebinding works everywhere.
static func pressed(e: InputEvent, action: String) -> bool:
	return e is InputEventKey and e.pressed and InputMap.has_action(action) and e.is_action_pressed(action)


# =====================================================================
# save slots
# =====================================================================

func slot_path(i: int) -> String:
	return "%s/slot%d.json" % [SAVE_DIR, i]


func slot_info(i: int) -> Dictionary:
	var path := slot_path(i)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if d == null or not (d is Dictionary):
		return {}
	return d.get("info", {})


func save_slot(i: int, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(slot_path(i), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	return true


func load_slot(i: int) -> Dictionary:
	var path := slot_path(i)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func delete_slot(i: int) -> void:
	if FileAccess.file_exists(slot_path(i)):
		DirAccess.remove_absolute(slot_path(i))


func stamp() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]
