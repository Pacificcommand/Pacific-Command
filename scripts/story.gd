class_name Story
## The story layer: briefings as naval dispatches, newsreel-style event cards on the timeline,
## letters and diary entries from the officers between battles, after-action reports written like
## the real ones, and the ship's log. Period voice; the cost of the war shown plainly.

## Historical events shown as cards on the map (day = days since 7 Dec 1941).
const EVENTS := [
	{"day": 0, "title": "Pearl Harbor attacked", "text": "At 0755 this morning carrier aircraft bearing the rising sun struck the Pacific Fleet at its moorings. Arizona, Oklahoma, West Virginia and California are sunk or sinking. Over two thousand men are dead. The United States is at war."},
	{"day": 3, "title": "Force Z lost", "text": "Off Malaya, HMS Prince of Wales and Repulse have been sunk by Japanese land-based aircraft. For the first time, capital ships under way at sea have been destroyed by air attack alone."},
	{"day": 132, "title": "The Doolittle Raid", "text": "Sixteen Army B-25 bombers flew off the carrier Hornet this morning and struck Tokyo, Yokohama and Nagoya. The damage is small; the shock in Japan, and the lift at home, are not."},
	{"day": 151, "title": "Coral Sea", "text": "Lexington is lost and Yorktown damaged, but the Japanese have turned back from Port Moresby and lost the light carrier Shoho. It is the first naval battle in which the ships never saw each other."},
	{"day": 182, "title": "Midway", "text": "Four Japanese fleet carriers, Akagi, Kaga, Soryu and Hiryu, are on the bottom off Midway, with the cream of their air groups. Yorktown is lost. Six months after Pearl Harbor the tide has turned."},
	{"day": 243, "title": "Marines land on Guadalcanal", "text": "The First Marine Division is ashore on Guadalcanal and Tulagi and holds the unfinished airfield the Japanese were building. The Navy must now keep them supplied, in waters the enemy means to contest every night."},
	{"day": 341, "title": "Juneau lost", "text": "The cruiser Juneau was torpedoed and blew up after the night action off Savo; among the hundreds lost are the five Sullivan brothers of Waterloo, Iowa, who had asked to serve together."},
	{"day": 430, "title": "Guadalcanal secured", "text": "The last Japanese troops have been evacuated from Guadalcanal under cover of darkness. Six months of fighting ashore, afloat and in the air have cost both navies dearly; the Solomons road north is open."},
	{"day": 497, "title": "Yamamoto shot down", "text": "Army P-38s from Guadalcanal have intercepted and destroyed the aircraft carrying Admiral Isoroku Yamamoto over Bougainville. The architect of Pearl Harbor is dead."},
	{"day": 716, "title": "Tarawa", "text": "Betio has been taken in seventy-six hours at a cost of more than a thousand Marines dead. The landing craft grounded on the reef and the men waded in under fire. The lessons will be learned, at that price."},
	{"day": 912, "title": "Normandy", "text": "Allied forces have landed in France. The war in Europe enters its last year; in the Pacific the fleet is off the Marianas, where the Japanese carriers must come out to fight."},
	{"day": 921, "title": "The Marianas Turkey Shoot", "text": "Task Force 58's fighters have destroyed the better part of three Japanese air groups in a single day; submarines sank Shokaku and the new carrier Taiho. Saipan is being taken. Tokyo is within range of the B-29."},
	{"day": 1052, "title": "Leyte Gulf", "text": "In four days of fighting from Surigao Strait to Cape Engano the Japanese Navy has lost four carriers, three battleships, ten cruisers and eleven destroyers, and has ceased to exist as a fleet. The Philippines are being liberated. A new weapon appeared off Leyte: pilots who do not come back."},
	{"day": 1172, "title": "Iwo Jima", "text": "The flag is up on Mount Suribachi. The Marines have paid for every yard of the island's black sand, and the bombers that fall short of Japan now have somewhere to land."},
	{"day": 1221, "title": "Yamato sunk", "text": "The largest battleship ever built sortied for Okinawa with fuel for one way and no air cover, and was sunk by carrier aircraft in two hours. Three thousand of her crew went with her."},
	{"day": 1222, "title": "The President is dead", "text": "Franklin Delano Roosevelt died today at Warm Springs, Georgia. Harry S. Truman has been sworn in. The fleet flies its colors at half-mast off Okinawa, under the kamikazes."},
	{"day": 1248, "title": "Victory in Europe", "text": "Germany has surrendered unconditionally. The whole weight of the Allied war effort now turns to the Pacific."},
	{"day": 1338, "title": "Hiroshima", "text": "A single bomb of a new kind has destroyed the city of Hiroshima. Three days later a second falls on Nagasaki."},
	{"day": 1356, "title": "Japan surrenders", "text": "The Emperor has broadcast Japan's acceptance of the Allied terms. The ceremony aboard USS Missouri in Tokyo Bay is set for 2 September. The war is over."},
]

## A briefing written as a naval dispatch.
static func dispatch(brief: Dictionary, day: int, ship_name: String, rank: String, zone_name := "") -> String:
	var from := "COMSOPAC" if day < 800 else ("COMFIFTHFLT" if day < 1040 else "COMTHIRDFLT")
	if day < 180:
		from = "CINCPAC"
	var hour := 6 + (day * 7) % 12
	var dtg := "%02d%02d00" % [War.ymd(day)[2], hour]
	var head := "FROM: %s\nTO: COMMANDING OFFICER %s\nDTG %s %s\nPRIORITY · OPERATIONAL" % [from, ship_name.to_upper(), dtg, War.date_str(day).to_upper()]
	var threat: String = brief.get("threat", "")
	var body: String = brief.get("text", "")
	var tail := "THREAT ASSESSMENT %s. %sACKNOWLEDGE." % [threat.to_upper(), ("AREA %s. " % zone_name.to_upper()) if zone_name != "" else ""]
	return "%s\n\n%s\n\n%s" % [head, body, tail]

## After-action report in the style of the originals, from the battle's log and figures.
static func after_action(brief: Dictionary, stats: Dictionary, log_lines: Array, day: int, ship_name: String, over: String, crew_start: int, crew_end: int, duration: float) -> String:
	var subj: String = brief.get("title", "Action").to_upper()
	var result: String = {"won": "Objective accomplished.", "escaped": "Enemy withdrew out of reach.", "lost_convoy": "Objective not accomplished.", "lost": "Ship lost."}.get(over, "Ship lost.")
	var lines := []
	lines.append("U.S.S. %s" % ship_name.to_upper().replace("USS ", ""))
	lines.append("ACTION REPORT · %s" % War.date_str(day).to_upper())
	lines.append("SUBJECT: %s — REPORT OF" % subj)
	lines.append("")
	lines.append("1. GENERAL. %s Action lasted %d minutes." % [result, int(duration / 60.0)])
	lines.append("")
	lines.append("2. CHRONOLOGY.")
	var n := 0
	for ln in log_lines:
		if n >= 28:
			lines.append("   (further entries omitted)")
			break
		lines.append("   %s  %s" % [ln[0], ln[1]])
		n += 1
	lines.append("")
	var sunk: Array = stats.get("sunk", [])
	lines.append("3. ENEMY. %s" % ("Sunk: %s." % ", ".join(sunk) if not sunk.is_empty() else "No enemy vessels sunk."))
	lines.append("")
	lines.append("4. AMMUNITION EXPENDED. %d salvos and bursts, %d rounds; %d hits observed (%.0f%%). %d torpedoes fired, %d hits." % [stats.get("salvos", 0), stats.get("shells", 0), stats.get("hits", 0), 100.0 * stats.get("hits", 0) / maxf(1.0, stats.get("shells", 0)), stats.get("torps", 0), stats.get("torp_hits", 0)])
	lines.append("")
	var lost := crew_start - crew_end
	lines.append("5. CASUALTIES. %s" % ("None." if lost <= 0 else "%d officers and men killed or missing out of %d aboard. Next of kin are being notified." % [lost, crew_start]))
	if stats.get("rescued", 0) > 0:
		lines.append("   %d survivors recovered from the water." % stats.rescued)
	lines.append("")
	lines.append("6. REMARKS. %s" % _remark(over, stats, lost, crew_start))
	lines.append("")
	lines.append("                                        Commanding Officer")
	return "\n".join(lines)

static func _remark(over: String, stats: Dictionary, lost: int, crew: int) -> String:
	if over == "lost":
		return "The ship was lost. The conduct of the crew to the end was in keeping with the highest traditions of the naval service."
	var parts := []
	if stats.get("hits", 0) > 0 and stats.get("shells", 0) > 0 and float(stats.hits) / stats.shells > 0.2:
		parts.append("Gunnery was excellent; the fire-control party is commended.")
	elif stats.get("shells", 0) > 20:
		parts.append("Gunnery was below the standard expected and additional practice has been ordered.")
	if stats.get("torp_hits", 0) > 0:
		parts.append("Torpedo attack pressed home with good results.")
	if lost > crew * 0.15:
		parts.append("Damage control parties fought fires and flooding under heavy fire and kept the ship in action.")
	if parts.is_empty():
		parts.append("The ship performed as expected. No further remarks.")
	return " ".join(parts)

## Letters and diary entries between battles: who writes, and what they say about what happened.
static func letter(c: Dictionary, result: String, lines: Array, day: int, ship_name: String, sunk: Array, lost: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = day * 31 + c.xp
	var officers: Array = c.officers.filter(func(o): return not o.dead)
	if officers.is_empty():
		return {}
	var o: Dictionary = officers[rng.randi() % officers.size()]
	var first: String = o.name.split(" ")[1]
	var kind: String = ["letter", "diary"][rng.randi() % 2]
	var body := ""
	match result:
		"won":
			if not sunk.is_empty():
				body = ["We got one of theirs last night. I won't say more than that, the censor would only cut it. The gun crews were magnificent. I keep thinking of the men on the other ship; they were sailors too.",
					"Another one on the scoreboard. The Old Man had us in exactly the right place and the fish ran straight for once. There was a lot of cheering until somebody reminded us there were still men in the water over there.",
					"We fought and won. That is the whole of what I may tell you, except that I am well and the ship is sound. Your last letter reached me the day after and I have read it four times."][rng.randi() % 3]
			else:
				body = ["The job got done without much shooting, which suits me. The men are tired but in good spirits. The coffee has run out again.",
					"Mission accomplished, as they say. Nobody hurt. I slept eleven hours afterwards and woke up thinking I was home."][rng.randi() % 2]
		"escaped":
			body = ["They got away from us in the dark. The Captain said nothing for an hour. We'll have another chance; there is always another night in these waters.",
				"We missed them. It happens more than the newspapers let on. The lookouts blame the radar and the radar men blame the lookouts and the truth is the sea is very large."][rng.randi() % 2]
		_:
			body = ["It was a bad night. I have written the letters a division officer has to write and I hope never to write another. The ship will be repaired. Some things will not.",
				"We took a beating and came home, which is more than some can say. I am not hurt. Please tell Mother I am not hurt; she reads things into what I don't write."][rng.randi() % 2]
	if lost > 0 and result != "lost" and rng.randf() < 0.6:
		body += " We buried %s at sea this morning. The Captain read the service and the whole ship's company stood to." % ("%d of our shipmates" % lost if lost > 1 else "one of our shipmates")
	for ln in lines:
		if "Promoted" in ln:
			body += " You will laugh: the Captain has been promoted, and we are all very grand about it."
		if "wounded" in ln and first in ln:
			body = "I am writing this from the sick bay, so excuse the hand. I am told I will be fit again in a few weeks. " + body
	var head: String = ("Dear Margaret,\n\n" if kind == "letter" else "%s. At sea.\n\n" % War.date_str(day))
	var sign: String = ("\n\nAll my love,\n%s" % first) if kind == "letter" else ""
	return {"day": day, "from": o.name, "post": o.post, "kind": kind, "text": head + body + sign, "title": ("Letter home from %s" % o.name) if kind == "letter" else ("Diary of %s" % o.name)}
