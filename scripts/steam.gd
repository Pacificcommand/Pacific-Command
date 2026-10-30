extends Node
## Autoload `SteamHook`: achievements and Steam integration.
##
## The game does not depend on Steam. Achievements are always tracked and stored in the
## career (`Game.career.achievements`) and shown in the Career panel; when the GodotSteam
## GDExtension is installed (addons/godotsteam, see docs/STEAM.md) and the game was started
## from Steam (or steam_appid.txt is next to the executable), the same unlocks are also sent
## to Steam, and the Steam overlay / rich presence work. Nothing here calls Steam directly
## by name at parse time, so the project runs without the extension.

const APP_ID := 480     # Spacewar test app; replace with the real App ID from Steamworks

## id -> [name, description]. Keep in step with the Steamworks "Achievements" page.
const ACHIEVEMENTS := {
	"first_blood": ["First Blood", "Sink an enemy ship."],
	"tin_can": ["Tin Can Sailor", "Win a destroyer action."],
	"convoy_through": ["The Convoy Got Through", "Deliver a convoy without losing a merchant."],
	"big_game": ["Big Game", "Sink a battleship or an aircraft carrier."],
	"sub_hunter": ["Sub Hunter", "Sink a submarine with depth charges or hedgehog."],
	"silent_service": ["Silent Service", "Sink a ship with a submarine."],
	"ten_kills": ["Ace of the Slot", "Sink ten enemy ships in one career."],
	"navy_cross": ["Navy Cross", "Be awarded the Navy Cross."],
	"four_stripes": ["Four Stripes", "Reach the rank of Captain."],
	"flag_rank": ["Flag Rank", "Reach the rank of Rear Admiral."],
	"survivor": ["Survivor", "Bring a ship home with more than half her crew lost."],
	"rescuer": ["Shipmates", "Rescue survivors from the water."],
	"night_fighter": ["Night Fighter", "Win a night battle."],
	"home_by_christmas": ["Home by Christmas", "Be at sea on Christmas Day."],
	"to_tokyo_bay": ["Tokyo Bay", "Serve until the surrender in September 1945."],
	"ironman": ["Ironman", "Finish a campaign on Ironman difficulty."],
}

var steam = null           # the Steam singleton when GodotSteam is present
var online := false


func _ready() -> void:
	if Engine.has_singleton("Steam"):
		steam = Engine.get_singleton("Steam")
		var r = steam.call("steamInitEx", APP_ID, true)
		online = r is Dictionary and int(r.get("status", 1)) == 0
		if online:
			print("Steam: signed in as ", steam.call("getPersonaName"))
			steam.call("setRichPresence", "steam_display", "#Status_Menu")
		else:
			print("Steam: not running (", r, "); achievements are tracked locally")


func _process(_dt: float) -> void:
	if online:
		steam.call("run_callbacks")


## Unlock an achievement (idempotent). Returns true the first time.
func unlock(id: String) -> bool:
	if not ACHIEVEMENTS.has(id):
		return false
	var c: Dictionary = Game.career
	if c.is_empty():
		return false
	if not c.has("achievements"):
		c.achievements = []
	for a in c.achievements:
		if a.id == id:
			return false
	c.achievements.append({"id": id, "day": int(Game.campaign.get("day", 0)) if not Game.campaign.is_empty() else 0})
	if online:
		steam.call("setAchievement", id)
		steam.call("storeStats")
	return true


## Rich presence shown to Steam friends.
func presence(text: String) -> void:
	if online:
		steam.call("setRichPresence", "steam_display", "#Status_Custom")
		steam.call("setRichPresence", "text", text)


## Called by the battle when it settles. Looks at what happened and unlocks what applies.
func check_battle(B) -> Array:
	var got: Array = []
	var c: Dictionary = Game.career
	if c.is_empty():
		return got
	var tally: Dictionary = B.tally
	var stats: Dictionary = B.stats
	var won: bool = B.over == "won"
	var p = B.player
	if tally.get("kills", 0) > 0 and unlock("first_blood"):
		got.append("first_blood")
	if tally.get("big_kill", false) and unlock("big_game"):
		got.append("big_game")
	if won and p.cls() == "dd" and unlock("tin_can"):
		got.append("tin_can")
	if won and B.brief.get("goal", "") == "protect" and stats.get("protect_lost", 0) == 0 and unlock("convoy_through"):
		got.append("convoy_through")
	if won and B.weather == "night" and unlock("night_fighter"):
		got.append("night_fighter")
	if stats.get("rescued", 0) > 0 and unlock("rescuer"):
		got.append("rescuer")
	if p.alive and stats.get("start_crew", 0) > 0 and p.crew < stats.start_crew * 0.5 and unlock("survivor"):
		got.append("survivor")
	if p.is_sub() and tally.get("kills", 0) > 0 and unlock("silent_service"):
		got.append("silent_service")
	if stats.get("sub_kill", false) and unlock("sub_hunter"):
		got.append("sub_hunter")
	var total := 0
	for k in c.ships:
		total += int(c.ships[k].get("kills", 0))
	if total >= 10 and unlock("ten_kills"):
		got.append("ten_kills")
	for m in c.get("medals", []):
		if m.id == "navy_cross" and unlock("navy_cross"):
			got.append("navy_cross")
	if int(c.rank) >= 5 and unlock("four_stripes"):
		got.append("four_stripes")
	if int(c.rank) >= 7 and unlock("flag_rank"):
		got.append("flag_rank")
	return got


## Called by the operations map once a day.
func check_day(day: int) -> Array:
	var got: Array = []
	var ymd: Array = War.ymd(day)
	if ymd[1] == 12 and ymd[2] == 25 and unlock("home_by_christmas"):
		got.append("home_by_christmas")
	if ymd[0] > 1945 or (ymd[0] == 1945 and (ymd[1] > 9 or (ymd[1] == 9 and ymd[2] >= 2))):
		if unlock("to_tokyo_bay"):
			got.append("to_tokyo_bay")
		if Game.career.get("difficulty", "") == "ironman" and unlock("ironman"):
			got.append("ironman")
	return got


func name_of(id: String) -> String:
	return ACHIEVEMENTS.get(id, [id, ""])[0]
