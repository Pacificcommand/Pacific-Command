class_name War
## The Pacific War as data: sea zones, bases, the 1941-45 timeline of operations, and the
## historical dates each zone changed hands. Positions are longitude (east, 120..205) and
## latitude (north positive). The operations map (ops.gd) draws and moves all of this.

## Sea zones: id -> {name, lon, lat, r (nm), jp_date (day the Japanese took it, or -1 if never),
## us_date (day the Allies took it back, or -1 = held by Japan to the end), activity (0..1 base)}
## Days count from 0 = 7 December 1941.
const ZONES := {
	"hawaii": {"name": "Hawaiian waters", "lon": 202.0, "lat": 21.0, "r": 350, "jp": -1, "us": 0, "act": 0.2},
	"midway": {"name": "Midway", "lon": 182.6, "lat": 28.2, "r": 250, "jp": -1, "us": 0, "act": 0.3},
	"marshalls": {"name": "Marshall Islands", "lon": 168.0, "lat": 8.5, "r": 300, "jp": 0, "us": 790, "act": 0.5},
	"gilberts": {"name": "Gilbert Islands", "lon": 173.0, "lat": 1.5, "r": 240, "jp": 3, "us": 715, "act": 0.4},
	"solomons": {"name": "Solomon Islands", "lon": 160.0, "lat": -9.0, "r": 320, "jp": 150, "us": 430, "act": 1.0},
	"coral": {"name": "Coral Sea", "lon": 154.0, "lat": -16.0, "r": 320, "jp": -1, "us": 0, "act": 0.5},
	"bismarck": {"name": "Bismarck Sea", "lon": 150.0, "lat": -4.0, "r": 280, "jp": 48, "us": 800, "act": 0.9},
	"new_guinea": {"name": "New Guinea", "lon": 147.0, "lat": -8.5, "r": 300, "jp": 110, "us": 870, "act": 0.6},
	"carolines": {"name": "Caroline Islands", "lon": 152.0, "lat": 7.5, "r": 320, "jp": 0, "us": 950, "act": 0.7},
	"marianas": {"name": "Mariana Islands", "lon": 145.5, "lat": 15.5, "r": 260, "jp": 3, "us": 920, "act": 0.6},
	"palau": {"name": "Palau", "lon": 134.5, "lat": 7.5, "r": 220, "jp": 0, "us": 1010, "act": 0.5},
	"philippines": {"name": "Philippine Sea", "lon": 125.0, "lat": 12.0, "r": 400, "jp": 150, "us": 1045, "act": 0.8},
	"formosa": {"name": "Formosa Strait", "lon": 122.0, "lat": 23.5, "r": 260, "jp": 0, "us": -1, "act": 0.6},
	"ryukyus": {"name": "Ryukyu Islands", "lon": 128.0, "lat": 26.5, "r": 260, "jp": 0, "us": 1215, "act": 0.7},
	"bonins": {"name": "Bonin Islands", "lon": 141.5, "lat": 25.5, "r": 240, "jp": 0, "us": 1180, "act": 0.5},
	"home": {"name": "Japanese home waters", "lon": 137.0, "lat": 33.0, "r": 380, "jp": 0, "us": -1, "act": 1.0},
	"java": {"name": "Java Sea", "lon": 112.0, "lat": -4.5, "r": 340, "jp": 60, "us": -1, "act": 0.6},
	"celebes": {"name": "Celebes Sea", "lon": 122.0, "lat": 3.0, "r": 280, "jp": 40, "us": -1, "act": 0.5},
}

## Bases: name -> {lon, lat, side ("us"/"ijn"), zone, from (day available to the Allies, -1 never)}
const BASES := {
	"Pearl Harbor": {"lon": 202.1, "lat": 21.3, "side": "us", "zone": "hawaii", "from": 0},
	"Midway": {"lon": 182.6, "lat": 28.2, "side": "us", "zone": "midway", "from": 0},
	"Noumea": {"lon": 166.4, "lat": -22.3, "side": "us", "zone": "coral", "from": 0},
	"Espiritu Santo": {"lon": 167.2, "lat": -15.5, "side": "us", "zone": "coral", "from": 180},
	"Tulagi": {"lon": 160.1, "lat": -9.1, "side": "us", "zone": "solomons", "from": 245},
	"Brisbane": {"lon": 153.0, "lat": -27.5, "side": "us", "zone": "coral", "from": 0},
	"Milne Bay": {"lon": 150.4, "lat": -10.4, "side": "us", "zone": "new_guinea", "from": 260},
	"Majuro": {"lon": 171.2, "lat": 7.1, "side": "us", "zone": "marshalls", "from": 790},
	"Eniwetok": {"lon": 162.3, "lat": 11.4, "side": "us", "zone": "marshalls", "from": 810},
	"Manus": {"lon": 147.3, "lat": -2.0, "side": "us", "zone": "bismarck", "from": 820},
	"Saipan": {"lon": 145.7, "lat": 15.2, "side": "us", "zone": "marianas", "from": 940},
	"Ulithi": {"lon": 139.7, "lat": 10.0, "side": "us", "zone": "carolines", "from": 1020},
	"Leyte": {"lon": 125.0, "lat": 11.0, "side": "us", "zone": "philippines", "from": 1050},
	"Rabaul": {"lon": 152.2, "lat": -4.2, "side": "ijn", "zone": "bismarck", "from": -1},
	"Truk": {"lon": 151.8, "lat": 7.4, "side": "ijn", "zone": "carolines", "from": -1},
	"Kwajalein": {"lon": 167.7, "lat": 8.7, "side": "ijn", "zone": "marshalls", "from": -1},
	"Tokyo": {"lon": 139.7, "lat": 35.7, "side": "ijn", "zone": "home", "from": -1},
	"Kure": {"lon": 132.6, "lat": 34.2, "side": "ijn", "zone": "home", "from": -1},
	"Manila": {"lon": 121.0, "lat": 14.6, "side": "ijn", "zone": "philippines", "from": -1},
	"Palau": {"lon": 134.5, "lat": 7.3, "side": "ijn", "zone": "palau", "from": -1},
	"Singapore": {"lon": 103.9, "lat": 1.3, "side": "ijn", "zone": "java", "from": -1},
}

## Historical operations the player is offered a part in: day, name, zone, scenario, text.
const OPERATIONS := [
	{"day": 0, "name": "Pearl Harbor", "zone": "hawaii", "scenario": "rescue", "text": "The Japanese carrier force has struck Pearl Harbor. Rescue survivors from the harbor approaches and the outlying patrols."},
	{"day": 60, "name": "Marshalls-Gilberts raid", "zone": "marshalls", "scenario": "carriers", "text": "Enterprise and Yorktown raid the Japanese bases in the Marshalls and Gilberts, the first blows back."},
	{"day": 82, "name": "Battle of the Java Sea", "zone": "java", "scenario": "cruisers", "text": "The ABDA cruiser force meets the Japanese covering force for the Java landings."},
	{"day": 150, "name": "Battle of the Coral Sea", "zone": "coral", "scenario": "carriers", "text": "Carriers fight carriers for the first time: Lexington and Yorktown against Shokaku and Zuikaku, over the Port Moresby invasion."},
	{"day": 181, "name": "Battle of Midway", "zone": "midway", "scenario": "carriers", "text": "Four Japanese carriers come for Midway. Three American carriers wait where the codebreakers said they would."},
	{"day": 244, "name": "Battle of Savo Island", "zone": "solomons", "scenario": "cruisers", "text": "Mikawa's cruisers come down the Slot at night to attack the transports off Guadalcanal."},
	{"day": 258, "name": "Eastern Solomons", "zone": "solomons", "scenario": "carriers", "text": "Carrier battle east of the Solomons as Japan tries to reinforce Guadalcanal."},
	{"day": 309, "name": "Cape Esperance", "zone": "solomons", "scenario": "cruisers", "text": "Night action off Savo: a US cruiser force crosses the T of a Japanese bombardment group."},
	{"day": 323, "name": "Santa Cruz Islands", "zone": "solomons", "scenario": "carriers", "text": "Carrier battle: Hornet and Enterprise against Shokaku, Zuikaku, Zuiho and Junyo."},
	{"day": 341, "name": "Naval Battle of Guadalcanal", "zone": "solomons", "scenario": "bbs", "text": "Washington and South Dakota meet Kirishima's bombardment force in the dark off Savo."},
	{"day": 357, "name": "Tassafaronga", "zone": "solomons", "scenario": "dd", "text": "Tanaka's destroyers, caught by a cruiser force, launch a devastating torpedo counterattack."},
	{"day": 574, "name": "Kula Gulf", "zone": "solomons", "scenario": "cruisers", "text": "Cruisers and destroyers intercept a Tokyo Express run to Kolombangara."},
	{"day": 607, "name": "Vella Gulf", "zone": "solomons", "scenario": "dd", "text": "Six US destroyers ambush four Japanese destroyers with torpedoes first, guns second."},
	{"day": 697, "name": "Empress Augusta Bay", "zone": "solomons", "scenario": "cruisers", "text": "Merrill's cruisers hold off a Japanese cruiser force attacking the Bougainville landings."},
	{"day": 714, "name": "Tarawa", "zone": "gilberts", "scenario": "bombard", "text": "The fleet bombards Betio before the Marines land. The Japanese shore batteries are still firing."},
	{"day": 788, "name": "Kwajalein", "zone": "marshalls", "scenario": "bombard", "text": "Battleships and cruisers pound the Marshalls ahead of the landings."},
	{"day": 920, "name": "Battle of the Philippine Sea", "zone": "marianas", "scenario": "carriers", "text": "The Great Marianas Turkey Shoot: Ozawa's carriers against Task Force 58."},
	{"day": 1049, "name": "Battle off Samar", "zone": "philippines", "scenario": "fleet", "text": "Kurita's battleships and cruisers surprise the escort carriers of Taffy 3 off Samar. Destroyers charge."},
	{"day": 1049, "name": "Surigao Strait", "zone": "philippines", "scenario": "bbs", "text": "Nishimura's force runs into the whole of Oldendorf's battle line at the head of Surigao Strait."},
	{"day": 1170, "name": "Iwo Jima", "zone": "bonins", "scenario": "bombard", "text": "The old battleships, Texas among them, bombard Iwo Jima for three days before the landing."},
	{"day": 1210, "name": "Okinawa", "zone": "ryukyus", "scenario": "bombard", "text": "Operation Iceberg: the fleet shells Okinawa under kamikaze attack."},
	{"day": 1217, "name": "Ten-Go", "zone": "ryukyus", "scenario": "fleet", "text": "Yamato sorties for Okinawa with one light cruiser and eight destroyers, fuel for one way."},
	{"day": 1368, "name": "Surrender", "zone": "home", "scenario": "", "text": "Japan surrenders aboard USS Missouri in Tokyo Bay. The war is over; the Pacific stays open for patrols."},
]

## Day number -> [year, month, day]; day 0 = 7 December 1941.
static func ymd(day: int) -> Array:
	var y := 1941
	var m := 12
	var d := 7 + day
	while true:
		var dim := _days_in_month(y, m)
		if d <= dim:
			break
		d -= dim
		m += 1
		if m > 12:
			m = 1
			y += 1
	return [y, m, d]

static func _days_in_month(y: int, m: int) -> int:
	if m == 2:
		return 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28
	return 30 if m in [4, 6, 9, 11] else 31

## "7 Dec 1941" style date.
static func date_str(day: int) -> String:
	var a := ymd(day)
	return "%d %s %d" % [a[2], ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][a[1] - 1], a[0]]

static func year_of(day: int) -> int:
	return ymd(day)[0]

## Who holds a zone on a given day, with the player's influence (positive = ahead of history).
static func owner(zone_id: String, day: float, shift: float) -> String:
	var z: Dictionary = ZONES[zone_id]
	var jp: int = z.jp
	var us: int = z.us
	if jp < 0:
		return "us"
	if day < jp:
		return "us"
	if us < 0:
		return "ijn" if day < 1368 - shift else "us"
	return "us" if day >= us - shift else "ijn"

## Japanese activity in a zone on a day (0..1): high near the front, low far behind it.
static func activity(zone_id: String, day: float, shift: float) -> float:
	var z: Dictionary = ZONES[zone_id]
	var own := owner(zone_id, day, shift)
	var base: float = z.act
	var us: int = z.us
	if us > 0:
		# busiest in the year before the zone changes hands
		var dt := absf(day - (us - shift))
		base *= clampf(1.3 - dt / 500.0, 0.25, 1.3)
	if own == "us" and (us < 0 or day > us - shift + 200):
		base *= 0.3
	return clampf(base, 0.05, 1.0)

## Great-circle-ish distance in nautical miles (equirectangular, fine at this scale).
static func dist_nm(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
	var dx := (lon2 - lon1) * cos(deg_to_rad((lat1 + lat2) * 0.5)) * 60.0
	var dy := (lat2 - lat1) * 60.0
	return sqrt(dx * dx + dy * dy)
