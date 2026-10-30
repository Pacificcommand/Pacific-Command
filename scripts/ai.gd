class_name AI
extends RefCounted
## Ship AI: enemy fleets, lone warships, Japanese destroyer doctrine, PT boats and transports.
##
## Every half second each AI ship gets a heading to steer and an engine order. Ships that
## belong to a group ("fleet") keep station on their leader and play the role of their class:
## destroyers screen and make torpedo attacks, cruisers hold a battle line at gun range,
## battleships fight at long range, carriers stay back. A ship on its own (or detached from
## its fleet) picks tactics from a list and changes them every so often, so a fight to the
## finish is never a straight charge.

var B                       # the battle (battle.gd)
var fleets := {}            # group name -> {leader, mode, tgt, plan_t, attack_t, msg}

const TACTICS := ["close", "open", "zigzag", "cross", "circle_torp", "hide"]


func reset() -> void:
	fleets.clear()


# =====================================================================
# entry point
# =====================================================================

## Decide where ship s steers and how fast. Called every 0.5 s of battle time.
func step(s: Ship) -> void:
	var tgt := pick_target(s)
	var want := s.h
	if s.is_sub():
		want = submarine(s, tgt)
	else:
		match s.role():
			"barge", "merchant":
				want = transport(s, tgt)
			"pt":
				want = pt_boat(s, tgt)
			_:
				want = warship(s, tgt)
	s.torp_cd -= 0.5
	# ships turn toward torpedo wakes they can see, to comb them
	if s.T.L > 40.0:
		for tp in B.torps:
			if tp.team != s.team and U.hyp(tp.x - s.x, tp.z - s.z) < 900.0:
				want = tp.h
				s.ai_note = "combing torpedoes"
				break
	if not B.terrain.islands.is_empty() and not s.T.get("ground", false) and s.role() != "survivors":
		want = avoid_land(s, want)
	s.rud_cmd = clampf(rad_to_deg(U.ang_d(s.h, want)) * 1.5, -35.0, 35.0)


func _clear_ahead(s: Ship, hdg: float, look: float, draft: float) -> bool:
	for k in [0.5, 1.0]:
		var f := U.fwd(hdg)
		if B.terrain.height_at(s.x + f.x * look * k, s.z + f.y * look * k) > -draft * 1.5:
			return false
	return true


## Steer clear of the beach: if the course ahead runs onto land, try turns of growing size.
func avoid_land(s: Ship, want: float) -> float:
	var look: float = maxf(900.0, s.v * 60.0) + s.T.L
	var draft: float = s.T.get("draft", 4.0)
	if _clear_ahead(s, want, look, draft):
		return want
	for off in [40.0, -40.0, 80.0, -80.0, 120.0, -120.0, 180.0]:
		var h2 := want + deg_to_rad(off) * s.side
		if _clear_ahead(s, h2, look, draft):
			s.ai_note = "avoiding shoal water"
			return h2
	return want + PI


## Who this ship should fight: friendlies support the player's target; others take the
## nearest contact (or the fleet's shared target).
func pick_target(s: Ship) -> Ship:
	var p: Ship = B.player
	if s.team == p.team and p.alive and p.target and p.target.alive and s.contact(p.target) \
			and (p.target.objective or p.fire or B.t - p.last_fired < 10.0):
		return p.target
	# friendly boats follow the player's lead: they hold station until the shooting starts
	if s.team == p.team and p.alive and B.combat_t < 0.0:
		return null
	var F = fleet_of(s)
	if F != null and F.tgt != null and F.tgt.alive and not F.tgt.escaped and s.contact(F.tgt) and s != F.leader:
		# the division follows the leader's choice unless something is much closer
		var near := nearest_noticed(s, s.role() == "pt" and s.team == p.team)
		if near == null or s.range_to(near) > s.range_to(F.tgt) * 0.6:
			return F.tgt
		return near
	return nearest_noticed(s, s.role() == "pt" and s.team == p.team)


## Submarines go for the fat targets: merchants and carriers first, warships only when close.
func sub_target(s: Ship) -> Ship:
	var best: Ship = null
	var bv := 1e9
	for o in B.ships:
		if o.team == s.team or not o.alive or o.escaped or o.is_sub():
			continue
		if not s.contact(o):
			continue
		var v := s.range_to(o)
		if o.role() in ["merchant", "barge"] or o.cls() in ["cv", "cvl", "cve", "bb"]:
			v -= 4000.0
		elif o.cls() in ["dd", "de", "pt"]:
			v += 3000.0
		if v < bv:
			bv = v; best = o
	return best


func nearest_noticed(s: Ship, prefer_obj: bool) -> Ship:
	var best: Ship = null
	var bd := 1e9
	for o in B.ships:
		if o.team == s.team or not o.alive or o.escaped:
			continue
		if o.role() == "survivors":
			continue
		var d := s.range_to(o)
		if prefer_obj and not o.objective:
			d += 2500.0   # go for the transports, not the escort
		if o.protect:
			d -= 2500.0   # raiders go for the convoy
		# a ship that just fired nearby gives itself away even if unseen
		var noticed: bool = s.contact(o) or (B.t - o.last_fired < 4.0 and d < 7000.0 * clampf(o.gun.size, 0.3, 1.0))
		if noticed and d < bd:
			bd = d; best = o
	return best


# =====================================================================
# fleets
# =====================================================================

func fleet_of(s: Ship):
	if s.group == "":
		return null
	if not fleets.has(s.group):
		fleets[s.group] = {"leader": null, "mode": "approach", "tgt": null, "plan_t": -99.0, "attack_t": -99.0, "msg": false}
	var F: Dictionary = fleets[s.group]
	if F.leader == null or not F.leader.alive or F.leader.escaped or F.leader.detached:
		F.leader = pick_leader(s.group)
	return F


## The senior surviving ship leads: biggest first, then the one named leader in setup.
func pick_leader(group: String) -> Ship:
	var best: Ship = null
	var bv := -1.0
	for o in B.ships:
		if o.group != group or not o.alive or o.escaped or o.detached:
			continue
		var v: float = o.T.displacement + (1e6 if o.leader_flag else 0.0) + (1e7 if o.is_player else 0.0)
		if v > bv:
			bv = v; best = o
	return best


func members(group: String) -> Array:
	var out := []
	for o in B.ships:
		if o.group == group and o.alive and not o.escaped:
			out.append(o)
	return out


## Fleet-level plan, refreshed every 2 seconds by the leader: what the group is doing.
func plan_fleet(F: Dictionary, leader: Ship, tgt: Ship) -> void:
	if B.t - F.plan_t < 2.0:
		return
	F.plan_t = B.t
	# the fleet fights what its leader fights, or what any member can see
	if tgt == null:
		for m in members(leader.group):
			var c := nearest_noticed(m, false)
			if c:
				tgt = c
				break
	F.tgt = tgt
	var cls := leader.cls()
	var night: bool = Data.WEATHER[B.weather].night
	if tgt == null:
		F.mode = "approach"
		return
	var R := leader.range_to(tgt)
	match cls:
		"dd":
			# a destroyer division: close for torpedoes, launch, break away, come back when reloaded
			var tubes := 0
			for m in members(leader.group):
				tubes += m.torps_left()
			if F.mode == "withdraw":
				if B.t - F.attack_t > (70.0 if tubes > 0 else 45.0):
					F.mode = "attack" if tubes > 0 else "engage"
			elif tubes > 0 and R < (9000.0 if night else 7500.0) and tgt.T.get("draft", 4.0) > 2.0:
				F.mode = "attack"
			else:
				F.mode = "engage" if tubes == 0 or R < 6000.0 else "approach"
		"cv":
			F.mode = "avoid"
		_:
			F.mode = "engage" if R < leader.max_range() * 1.15 else "approach"


# =====================================================================
# warships
# =====================================================================

func warship(s: Ship, tgt: Ship) -> float:
	# escorts with a sonar contact and no surface fight on their hands go hunting
	if s.sonar_range() > 0.0 and not s.sonar_contacts.is_empty() and (tgt == null or tgt.is_sub() or s.range_to(tgt) > 6000.0):
		return hunt(s)
	s.asw_state = ""
	var hurt: bool = s.eff() < 0.5 or s.flood > s.T.displacement * 0.18 or s.mod_health("mount") < 0.3
	var F = fleet_of(s)
	# the last ship of a division fights on her own
	if F != null and members(s.group).size() <= 1:
		s.detached = true
		F = null
	var leader: Ship = F.leader if F != null else null
	if hurt and not s.detached and F != null:
		s.detached = true
		fleet_of(s)   # a new leader if this was it
	if hurt:
		return retreat(s, tgt)
	if F != null and leader == s:
		plan_fleet(F, s, tgt)
		if tgt == null and F.tgt != null and F.tgt.alive and not F.tgt.escaped:
			tgt = F.tgt
	elif F != null and leader != null and leader.is_player:
		# the player leads this group: the plan follows the player's target
		plan_fleet(F, leader, leader.target if leader.target and leader.target.alive else tgt)
	if tgt == null:
		return search(s, F, leader)
	s.target = tgt
	s.fire = true
	var R := s.range_to(tgt)
	night_illumination(s, tgt, R)
	# torpedoes: any warship with a shot takes it; Japanese destroyers live for it
	if torpedo_chance(s, tgt, R):
		return s.h
	if B.t < s.evade_until:
		return evade(s, tgt)
	if F != null and leader != null and leader != s and not s.detached:
		return in_formation(s, F, leader, tgt, R)
	if F != null and leader == s:
		return lead_fleet(s, F, tgt, R)
	return solo(s, tgt, R)


func retreat(s: Ship, tgt: Ship) -> float:
	s.ai_state = "retreat"
	s.tele = 6
	s.fire = tgt != null
	if s.T.smoke:
		s.smoke_on = true
	var away := s.h
	if tgt:
		away = fposmod(s.bearing_to(tgt.x, tgt.z) + PI, TAU)
	elif s.route_h != 0.0:
		away = s.route_h
	return away


func search(s: Ship, F, leader: Ship) -> float:
	s.ai_state = "search"
	s.fire = false
	s.smoke_on = false
	if F != null and leader != null and leader != s and not s.detached:
		return keep_station(s, leader)
	if s.escort_group != "":
		return escort_station(s)
	if s.route_h != 0.0 or s.dest_dist > 0.0:
		s.tele = 3
		return s.route_h
	s.tele = 5
	var near: Ship = null
	var bd := 1e9
	for o in B.ships:
		if o.team != s.team and o.alive and s.range_to(o) < bd:
			bd = s.range_to(o); near = o
	return s.bearing_to(near.x, near.z) + s.side * deg_to_rad(8.0) if near else s.h


func night_illumination(s: Ship, tgt: Ship, R: float) -> void:
	if Data.WEATHER[B.weather].night and R < 4000.0 and s.T.L > 60.0 and s.fire:
		s.star_cd -= 0.5
		if s.star_cd <= 0.0:
			s.star_cd = 26.0
			B.star_shell(tgt.x + randf_range(-400, 400), tgt.z + randf_range(-400, 400))


## Fire torpedoes when the geometry is right. Returns true if a spread was launched.
func torpedo_chance(s: Ship, tgt: Ship, R: float) -> bool:
	if s.torps.is_empty() or s.torps_left() == 0 or s.torp_cd > 0.0:
		return false
	if tgt.T.get("draft", 4.0) <= 2.0:
		return false
	var reach: float = s.T.torp.range * 0.85
	# Japanese crews fired from long range at night, before they were seen; Americans closer in
	var ijn: bool = s.doctrine() == "ijn_dd"
	if R > (reach if ijn else minf(reach, 5500.0)):
		return false
	var rb := absf(rad_to_deg(s.rel_bearing(tgt.x, tgt.z)))
	if rb < 40.0 or rb > 140.0:
		return false
	var n: int = B.launch_torps(s, tgt)
	if n <= 0:
		return false
	s.torp_cd = 40.0
	if B.player.contact(s):
		B.say("%s is launching torpedoes!" % s.ship_name, "bad")
	if ijn:
		# turn away at speed, hidden by smoke, and let the fish do the work
		s.evade_until = B.t + 45.0
		var F = fleet_of(s)
		if F != null:
			F.mode = "withdraw"
			F.attack_t = B.t
	return true


func evade(s: Ship, tgt: Ship) -> float:
	s.ai_state = "turning away"
	s.tele = 6
	if s.T.smoke:
		s.smoke_on = true
	# Japanese destroyers held their fire while running so the flashes did not give them away
	s.fire = s.doctrine() != "ijn_dd" or s.contact(tgt) and s.range_to(tgt) < 3000.0
	return fposmod(s.bearing_to(tgt.x, tgt.z) + PI + s.side * deg_to_rad(30.0), TAU)


## Followers hold their station on the leader unless the fleet sends them in.
func in_formation(s: Ship, F: Dictionary, leader: Ship, tgt: Ship, R: float) -> float:
	s.smoke_on = false
	var cls := s.cls()
	match F.mode:
		"attack":
			if cls == "dd":
				return torpedo_run(s, tgt, R)
		"withdraw":
			if cls == "dd" and s.torps_left() == 0:
				s.ai_state = "breaking off"
				s.tele = 6
				if s.T.smoke:
					s.smoke_on = true
				return fposmod(s.bearing_to(tgt.x, tgt.z) + PI + s.side * deg_to_rad(25.0), TAU)
		"engage":
			if cls == "dd" and leader.cls() != "dd" and R < 6500.0 and s.torps_left() > 0:
				# the screen goes in when the enemy closes on the main body
				return torpedo_run(s, tgt, R)
	s.ai_state = "in formation"
	return keep_station(s, leader)


## Steer for the station point in the leader's frame, matching speed when close to it.
func keep_station(s: Ship, leader: Ship) -> float:
	var st := leader.to_world_xz(s.fstation.x, s.fstation.y)
	var d := U.hyp(st.x - s.x, st.y - s.z)
	var ahead := leader.to_local_xz(s.x, s.z).x > s.fstation.x
	if d < s.T.L * 0.5:
		s.tele = leader.tele
		return leader.h
	s.tele = clampi(leader.tele + (0 if ahead else (2 if d > s.T.L * 3.0 else 1)), 1, 6)
	if ahead and d < s.T.L * 2.5:
		s.tele = maxi(1, leader.tele - 1)
	# far out of station: steer straight for it; near it: blend toward the leader's course
	var to_st := s.bearing_to(st.x, st.y)
	if d > s.T.L * 2.0:
		return to_st
	return leader.h + U.ang_d(leader.h, to_st) * clampf(d / (s.T.L * 2.0), 0.0, 1.0)


## The leader's behaviour sets the fleet's: a destroyer division runs in, a cruiser line
## holds gun range, a battleship fights far off, a carrier keeps away.
func lead_fleet(s: Ship, F: Dictionary, tgt: Ship, R: float) -> float:
	s.smoke_on = false
	match F.mode:
		"attack":
			return torpedo_run(s, tgt, R)
		"withdraw":
			s.ai_state = "breaking off"
			s.tele = 6
			if s.T.smoke:
				s.smoke_on = true
			return fposmod(s.bearing_to(tgt.x, tgt.z) + PI + s.side * deg_to_rad(25.0), TAU)
		"avoid":
			return keep_away(s, tgt, R)
		"approach":
			s.ai_state = "approaching"
			s.tele = 5
			return s.bearing_to(tgt.x, tgt.z) + s.side * deg_to_rad(15.0)
	return battle_line(s, tgt, R)


## A gun line: stay inside a range band and keep the enemy near the beam so every turret bears.
func battle_line(s: Ship, tgt: Ship, R: float) -> float:
	var mr := s.max_range()
	var band := Vector2(0.55, 0.75)
	match s.cls():
		"bb":
			band = Vector2(0.6, 0.8)
		"dd":
			band = Vector2(0.45, 0.7)
	# a long stand-off is no battle: the line creeps closer the longer the action lasts
	if B.combat_t >= 0.0:
		band *= clampf(1.0 - (B.t - B.combat_t) / 1800.0 * 0.45, 0.55, 1.0)
	var to_t := s.bearing_to(tgt.x, tgt.z)
	s.tele = 5
	if R > mr * band.y:
		s.ai_state = "closing the range"
		return to_t + s.side * deg_to_rad(35.0)
	if R < mr * band.x:
		s.ai_state = "opening the range"
		return to_t + s.side * deg_to_rad(125.0)
	s.ai_state = "battle line"
	# run a course parallel to the target so the range holds and the broadside bears
	var par := tgt.h if absf(U.ang_d(tgt.h, s.h)) < PI / 2.0 else fposmod(tgt.h + PI, TAU)
	var beam := to_t + s.side * deg_to_rad(90.0)
	return par + U.ang_d(par, beam) * 0.5


## Carriers: stay well outside gun range but inside strike range, running from anything that closes.
func keep_away(s: Ship, tgt: Ship, R: float) -> float:
	s.fire = R < s.max_range()
	var to_t := s.bearing_to(tgt.x, tgt.z)
	if R < 16000.0:
		s.ai_state = "running from surface ships"
		s.tele = 6
		return fposmod(to_t + PI + s.side * deg_to_rad(20.0), TAU)
	s.ai_state = "flight operations"
	s.tele = 5
	if R > 26000.0:
		return to_t + s.side * deg_to_rad(30.0)
	# steam across the enemy's bearing (into the wind, as carriers do) to hold the range
	return to_t + s.side * deg_to_rad(95.0)


## Run in at flank speed to a torpedo firing position off the target's bow.
func torpedo_run(s: Ship, tgt: Ship, R: float) -> float:
	s.ai_state = "torpedo attack"
	s.tele = 6
	var night: bool = Data.WEATHER[B.weather].night
	# Japanese doctrine: hold fire on the run-in so the flashes don't give the attack away
	if s.doctrine() == "ijn_dd" and night and not B.player.vis.get(s.ship_name, false):
		s.fire = R < 2500.0
	var ip: Array = s.torp_intercept(tgt, s.x, s.z)
	var to_ip := s.bearing_to(ip[0].x, ip[0].y)
	var want_R: float = s.T.torp.range * 0.6
	# approach on a bow-and-quarter line, then put the target on the beam to fire
	if R > want_R:
		return to_ip + s.side * deg_to_rad(30.0)
	return to_ip + s.side * deg_to_rad(80.0)


# =====================================================================
# lone warships: a changing mix of tactics
# =====================================================================

func solo(s: Ship, tgt: Ship, R: float) -> float:
	var escorting: bool = (s.route_h != 0.0 and s.dest_dist > 0.0) or s.escort_group != ""
	if escorting:
		return escort(s, tgt, R)
	if s.detached and s.torps_left() > 0 and R < s.T.torp.range * 0.9 and s.cls() == "dd":
		return torpedo_run(s, tgt, R)
	if B.t >= s.tactic_until or s.tactic == "":
		pick_tactic(s, tgt, R)
	s.smoke_on = s.tactic == "hide" and s.T.smoke
	var to_t := s.bearing_to(tgt.x, tgt.z)
	var mr := s.max_range()
	s.tele = 6
	match s.tactic:
		"close":
			s.ai_state = "closing"
			return to_t + s.side * deg_to_rad(25.0)
		"open":
			s.ai_state = "opening range"
			s.tele = 6
			return to_t + s.side * deg_to_rad(145.0)
		"zigzag":
			s.ai_state = "zigzagging"
			s.zig_t -= 0.5
			if s.zig_t <= 0.0:
				s.zig_t = randf_range(10.0, 16.0)
				s.zig = -s.zig if s.zig != 0.0 else 1.0
			var base := to_t + s.side * deg_to_rad(60.0 if R < mr * 0.7 else 20.0)
			return base + s.zig * deg_to_rad(35.0)
		"cross":
			s.ai_state = "crossing ahead"
			var f := U.fwd(tgt.h)
			var lead := clampf(R * 0.7, 800.0, 4000.0)
			return s.bearing_to(tgt.x + f.x * lead, tgt.z + f.y * lead)
		"circle_torp":
			s.ai_state = "working for a torpedo shot"
			return torpedo_run(s, tgt, R)
		"hide":
			s.ai_state = "making smoke"
			# steer so the smoke lies between us; squalls and existing smoke count too
			var best = null
			var bd := 1e9
			for sm in B.smokes:
				var d := U.hyp(sm.x - s.x, sm.z - s.z)
				if d < bd and d > 150.0:
					bd = d; best = sm
			if best != null and bd < 3000.0:
				return s.bearing_to(best.x, best.z)
			return to_t + s.side * deg_to_rad(150.0)
	return to_t


## Weighted choice of the next tactic from what the ship is, how the fight is going and
## what the enemy is. Japanese destroyers avoid gun duels and look for torpedo shots.
func pick_tactic(s: Ship, tgt: Ship, R: float) -> void:
	var mr := s.max_range()
	var ijn := s.doctrine() == "ijn_dd"
	var night: bool = Data.WEATHER[B.weather].night
	var torps: bool = s.torps_left() > 0 and tgt.T.get("draft", 4.0) > 2.0
	var tgt_hurt: bool = tgt.eff() < 0.75 or tgt.flood > tgt.T.displacement * 0.08 or not tgt.fires.is_empty()
	var me_hurt: bool = s.eff() < 0.8 or not s.fires.is_empty() or s.flood > s.T.displacement * 0.05
	var w := {"close": 1.0, "open": 1.0, "zigzag": 1.5, "cross": 1.0, "circle_torp": 0.0, "hide": 0.0}
	if R > mr * 0.8:
		w.close += 2.0; w.open = 0.2
	if R < mr * 0.35:
		w.open += 2.0; w.close = 0.2
	if tgt_hurt:
		w.close += 1.5
	if me_hurt:
		w.open += 1.0
		w.hide += 1.5 if s.T.smoke else 0.0
	if torps:
		w.circle_torp += 2.0 if R < s.T.torp.range * 1.1 else 0.8
	if tgt.v > 20.0 * Data.KN and absf(rad_to_deg(U.ang_d(tgt.h, tgt.bearing_to(s.x, s.z)))) < 50.0:
		w.cross += 1.5   # the enemy is coming at us: cross his bow
	if ijn:
		# light guns, thin plating, superb torpedoes: don't trade salvos with a US destroyer
		w.open += 1.5
		w.zigzag += 1.0
		w.close *= 0.4 if not tgt_hurt else 1.0
		w.circle_torp *= 2.0 if torps else 1.0
		if night:
			w.circle_torp += 1.0
		if s.T.smoke:
			w.hide += 0.8
	# never repeat the same tactic twice in a row
	if s.tactic != "":
		w[s.tactic] *= 0.2
	var total := 0.0
	for k in w:
		total += w[k]
	var r := randf() * total
	for k in w:
		r -= w[k]
		if r <= 0.0:
			s.tactic = k
			break
	s.tactic_until = B.t + randf_range(20.0, 40.0)
	s.zig = 0.0


## Centre of the ships this escort protects, or null if none are left.
func convoy_centre(s: Ship):
	var cx := 0.0
	var cz := 0.0
	var n := 0
	for o in B.ships:
		if o.team == s.team and o != s and o.alive and not o.escaped and (o.role() == "merchant" or o.role() == "barge" or o.cls() in ["cve", "cv", "cvl"]):
			cx += o.x; cz += o.z; n += 1
	if n == 0:
		return null
	return Vector2(cx / n, cz / n)


## No enemy in sight: zigzag ahead of the convoy at its speed.
func escort_station(s: Ship) -> float:
	var c = convoy_centre(s)
	if c == null:
		s.escort_group = ""
		return s.route_h
	s.ai_state = "screening the convoy"
	var f := U.fwd(s.route_h)
	var r := Vector2(cos(s.route_h), sin(s.route_h))
	s.zig_t -= 0.5
	if s.zig_t <= 0.0:
		s.zig_t = randf_range(40.0, 70.0)
		s.zig = -s.zig if s.zig != 0.0 else 1.0
	var st := Vector2(c.x + f.x * 1200.0 + r.x * 500.0 * s.zig, c.y + f.y * 1200.0 + r.y * 500.0 * s.zig)
	var d := U.hyp(st.x - s.x, st.y - s.z)
	s.tele = 2 if d < 300.0 else (3 if d < 1500.0 else 5)
	return s.bearing_to(st.x, st.y) if d > 150.0 else s.route_h


## A convoy escort: stays with its charges, runs at attackers that get close, comes back.
func escort(s: Ship, tgt: Ship, R: float) -> float:
	var c = convoy_centre(s)
	if c == null:
		s.escort_group = ""
		return solo(s, tgt, R)
	var cx: float = c.x
	var cz: float = c.y
	var leash := U.hyp(cx - s.x, cz - s.z)
	var threat := U.hyp(cx - tgt.x, cz - tgt.z)
	if leash > 3500.0:
		s.ai_state = "returning to the convoy"
		s.tele = 6
		return s.bearing_to(cx, cz)
	if threat < 5000.0 or R < 3000.0:
		s.ai_state = "driving off the attacker"
		s.tele = 6
		var to_t := s.bearing_to(tgt.x, tgt.z)
		if R < 1500.0 and tgt.T.L < 40.0:
			return to_t + s.side * deg_to_rad(90.0)   # small fast boats: keep them on the beam
		return to_t if R > 2500.0 else to_t + s.side * deg_to_rad(60.0)
	s.ai_state = "screening the convoy"
	s.tele = 3
	return s.bearing_to(cx, cz) if leash > 1200.0 else s.route_h


# =====================================================================
# PT boats
# =====================================================================

## PT boats: close at speed, rake the target from the beam, weave, and make torpedo runs on
## ships worth a torpedo.
func pt_boat(s: Ship, tgt: Ship) -> float:
	var p: Ship = B.player
	if tgt == null:
		s.fire = false
		s.torp_run = false
		if s.team == p.team and p.alive:
			s.ai_state = "in formation"
			return keep_station(s, p) if s.fstation != Vector2.ZERO else keep_station_pt(s, p)
		s.tele = 3
		return s.h
	s.target = tgt
	var R := s.range_to(tgt)
	var to_t := s.bearing_to(tgt.x, tgt.z)
	var worth: bool = tgt.T.get("draft", 4.0) > 2.0 and s.torps_left() > 0
	# hold fire on the approach to a torpedo target: gun flashes give the boat away
	s.fire = not worth or R < 700.0 or B.t < s.evade_until
	s.weave_t -= 0.5
	if s.weave_t <= 0.0:
		s.weave_t = randf_range(15.0, 30.0)
		s.side = -s.side
	if B.t < s.evade_until:
		s.ai_state = "evade"
		s.tele = 6
		if s.T.smoke and R < 2500.0:
			s.smoke_on = true
		return fposmod(to_t + PI + s.side * deg_to_rad(35.0), TAU)
	s.smoke_on = false
	if worth and R < 2600.0:
		# torpedo run: point the boat at the intercept point and fire at about 1,500 m
		s.ai_state = "torpedo run"
		s.tele = 6
		var ip: Array = s.torp_intercept(tgt, s.x, s.z)
		var brg := s.bearing_to(ip[0].x, ip[0].y)
		if R < 1700.0 and absf(U.ang_d(s.h, brg)) < deg_to_rad(10.0):
			var n: int = B.launch_torps(s, tgt)
			if n > 0:
				s.evade_until = B.t + 25.0
				if p.contact(tgt) or s.team == p.team:
					B.say("%s: torpedoes away at %s!" % [s.ship_name, tgt.ship_name], "good" if s.team == p.team else "bad")
		return brg
	# PT boats fought barges at a few hundred yards; bigger ships from a little farther off
	var stand := 600.0 if tgt.T.L < 40.0 else 1000.0
	if R > stand + 300.0:
		s.ai_state = "closing"
		s.tele = 6
		return to_t + s.side * deg_to_rad(10.0)
	# strafing run: keep the target on the beam at close range, weaving
	s.ai_state = "strafing"
	s.tele = 5
	var off := 70.0 if R > stand * 0.6 else 115.0
	return to_t + s.side * deg_to_rad(off)


func keep_station_pt(s: Ship, p: Ship) -> float:
	var st := p.to_world_xz(s.station.x, s.station.y)
	var d := U.hyp(st.x - s.x, st.y - s.z)
	var ahead := p.to_local_xz(s.x, s.z).x > s.station.x
	if d < 25.0:
		s.tele = p.tele
		return p.h
	s.tele = clampi(p.tele + (0 if ahead else (2 if d > 150.0 else 1)), 1, 6)
	if ahead and d < 120.0:
		s.tele = maxi(1, p.tele - 1)
	return s.bearing_to(st.x, st.y)


# =====================================================================
# transports
# =====================================================================

## Barges and merchant ships: keep to their route; turn away from attackers and run.
func transport(s: Ship, tgt: Ship) -> float:
	if tgt and s.range_to(tgt) < 3000.0:
		s.ai_state = "evading"
		s.target = tgt
		s.fire = true
		s.tele = 6
		var away := s.bearing_to(tgt.x, tgt.z) + PI
		# turn away, but not so far that they abandon the run
		var d := clampf(U.ang_d(s.route_h, away), deg_to_rad(-70.0), deg_to_rad(70.0))
		return s.route_h + d
	s.ai_state = "underway"
	s.fire = tgt != null
	s.target = tgt
	s.tele = 2
	return s.route_h


# =====================================================================
# submarines and their hunters
# =====================================================================

## A submarine: creep to a firing position at periscope depth, shoot, go deep and slip away.
func submarine(s: Ship, tgt: Ship) -> float:
	var hunted := false
	var hunter: Ship = null
	var hd := 1e9
	for o in B.ships:
		if o.team != s.team and o.alive and o.sonar_range() > 0.0:
			var d := s.range_to(o)
			if d < hd:
				hd = d; hunter = o
			if d < 2500.0 and o.sonar_contacts.has(s.ship_name):
				hunted = true
	s.fire = false
	if s.battery < 0.08 and not hunted:
		s.depth = 0
	if hunted or B.t < s.evade_until:
		# deep, slow and twisting away from the hunter
		s.ai_state = "evading deep"
		s.depth = 2
		s.tele = 2 if B.t - s.evade_until > -60.0 else 3
		if hunted:
			s.evade_until = B.t + 90.0
		s.zig_t -= 0.5
		if s.zig_t <= 0.0:
			s.zig_t = randf_range(20.0, 40.0)
			s.zig = -s.zig if s.zig != 0.0 else 1.0
		var away: float = fposmod(s.bearing_to(hunter.x, hunter.z) + PI, TAU) if hunter else s.h
		return away + s.zig * deg_to_rad(35.0)
	if tgt == null:
		s.ai_state = "patrolling"
		# surfaced on patrol at night, periscope depth by day
		s.depth = 0 if (Data.WEATHER[B.weather].night and hd > 6000.0) else 1
		s.tele = 3 if s.depth == 0 else 2
		if s.route_h != 0.0:
			return s.route_h
		var near := nearest_noticed(s, true)
		return s.bearing_to(near.x, near.z) if near else s.h
	s.target = tgt
	var R := s.range_to(tgt)
	s.depth = 1
	s.ai_state = "approaching"
	if s.torps_left() == 0:
		s.ai_state = "tubes empty, withdrawing"
		s.depth = 2 if hd < 5000.0 else 1
		s.tele = 2
		return fposmod(s.bearing_to(tgt.x, tgt.z) + PI, TAU)
	# firing position: about 90 degrees on the target's bow, 1,200-1,800 m off
	var ip: Array = s.torp_intercept(tgt, s.x, s.z)
	var brg := s.bearing_to(ip[0].x, ip[0].y)
	if R < 1800.0 and absf(U.ang_d(s.h, brg)) < deg_to_rad(12.0):
		var n: int = B.launch_torps(s, tgt)
		if n > 0:
			s.evade_until = B.t + 150.0
			s.torp_cd = 60.0
			if B.player.contact(s) or tgt.is_player or tgt.team == B.player.team:
				B.say("Torpedo wakes from a submarine! %s is under attack." % ("Our ship" if tgt.is_player else tgt.ship_name), "bad")
			return fposmod(brg + PI, TAU)
	s.tele = 3 if R > 4000.0 else 2
	if R > 2500.0:
		# get ahead of the target's track
		var f := U.fwd(tgt.h)
		var lead := clampf(R * 0.8, 1500.0, 6000.0)
		return s.bearing_to(tgt.x + f.x * lead, tgt.z + f.y * lead)
	return brg


## An escort hunting a submarine: run to the last sonar fix, drop a pattern over it, circle back.
func hunt(s: Ship) -> float:
	var key := ""
	var best_t := -1.0
	for k in s.sonar_contacts:
		if s.sonar_contacts[k].t > best_t:
			best_t = s.sonar_contacts[k].t; key = k
	var c: Dictionary = s.sonar_contacts[key]
	var d := U.hyp(c.x - s.x, c.z - s.z)
	s.fire = false
	s.target = null
	s.smoke_on = false
	if d > 1500.0:
		s.asw_state = "closing a sonar contact"
		s.ai_state = s.asw_state
		s.tele = 5
		return s.bearing_to(c.x, c.z)
	# attack run at moderate speed so the set still hears
	s.tele = 4
	s.asw_state = "depth charge run"
	s.ai_state = s.asw_state
	var ahead := s.to_local_xz(c.x, c.z)
	if s.T.get("hedgehog", s.type_id == "buckley") and ahead.x > 180.0 and ahead.x < 280.0 and absf(ahead.y) < 40.0:
		B.fire_hedgehog(s)
	if ahead.x < 0.0 and ahead.x > -60.0 and absf(ahead.y) < 50.0:
		B.drop_charges(s, c.depth == 2)
	if ahead.x < -60.0:
		# passed over: swing round for another run
		return s.bearing_to(c.x, c.z) + s.side * deg_to_rad(60.0)
	return s.bearing_to(c.x, c.z)
