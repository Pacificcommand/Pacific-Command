class_name Air
extends Node3D
## The air war: carrier and floatplane squadrons fly as units, attack ships, fight each other,
## are shot at by flak and come home to rearm. Owned by battle.gd (B).
##
## A squadron is a Dictionary: team, type (Data.AIRCRAFT key), kind, n (planes), x/z/h/alt/v,
## state: ready, launching, outbound, attacking, returning, landing, cap, scouting, lost;
## home (Ship), target (Ship or null), aim (Vector2 search point), node (the 3D planes).

var B
var sqs: Array = []             # squadrons in the air or on deck
var _id := 0
var _ai_t := 0.0
var _enemy_air_msg_t := -99.0
var _scout_msg_t := -99.0
var _cache := {}                # model path -> PackedScene
var aa_mode := "self"           # player's AA priority: self, carrier, bombers
var decks := {}                 # carrier Ship -> flight deck state (see the deck section)

const ALT_CRUISE := 170.0
const ALT_FORM := 120.0         # where a launching squadron forms up
const ALT_LOW := 35.0


func reset() -> void:
	for sq in sqs:
		if sq.node != null and is_instance_valid(sq.node):
			sq.node.queue_free()
		for so in sq.get("solos", []):
			if so.node != null and is_instance_valid(so.node):
				so.node.queue_free()
	sqs.clear()
	for dk in decks.values():
		for p in dk.planes:
			if p.node != null and is_instance_valid(p.node):
				p.node.queue_free()
	decks.clear()
	_id = 0
	_ai_t = 0.0
	_enemy_air_msg_t = -99.0
	_scout_msg_t = -99.0


## Give a carrier (or a ship with floatplanes) its air group, all on deck and ready.
func setup_ship(s: Ship) -> void:
	var T: Dictionary = s.T
	if T.has("aircraft") and T.has("fdeck"):
		# the whole air group is parked on the flight deck: as many as the deck can hold
		var dk := _deck_new(s)
		var group: Array = Data.air_group(T.get("hangar", "us"), int(T.aircraft))
		var total := 0
		for g in group:
			total += int(g[1])
		var k := minf(1.0, float(dk.cap) / float(maxi(total, 1)))
		var made := []
		for g in group:
			var n: int = maxi(1, int(floor(g[1] * k)))
			made.append(_new_sq(s, g[0], n, "ready"))
		_deck_spot_initial(dk, made)
	elif T.has("aircraft"):
		for g in Data.air_group(T.get("hangar", "us"), int(T.aircraft)):
			_new_sq(s, g[0], g[1], "ready")
	elif T.has("floatplanes") or _has_catapult(s):
		var n: int = int(T.get("floatplanes", 2))
		_new_sq(s, "e13a" if s.team == "ijn" else "os2u", n, "ready")


func _has_catapult(s: Ship) -> bool:
	for m in s.modules:
		if m.label == "Aviation gasoline":
			return true
	return false


func _new_sq(home: Ship, type: String, n: int, state: String) -> Dictionary:
	_id += 1
	var A: Dictionary = Data.AIRCRAFT[type]
	var sq := {"id": _id, "team": home.team, "type": type, "kind": A.kind, "n": n, "n0": n, "x": home.x, "z": home.z, "h": home.h, "alt": 0.0,
		"v": A.speed * Data.KN, "state": state, "home": home, "target": null, "aim": Vector2(home.x, home.z), "node": null, "timer": 0.0,
		"launch_left": 0, "aloft_t": 0.0, "attacked": false, "rearm": 0.0, "hits": 0, "name": "%s squadron %d" % [A.name, _id], "orbit": 0.0, "aim_update_t": -99.0, "warned": false,
		"solos": [], "landed": 0, "show_n": -1}
	sqs.append(sq)
	return sq


# =====================================================================
# orders
# =====================================================================

func ready_squadrons(home: Ship, kinds := ["fighter", "dive", "torpedo", "scout"]) -> Array:
	var out := []
	for sq in sqs:
		if sq.home == home and sq.state == "ready" and sq.n > 0 and kinds.has(sq.kind):
			out.append(sq)
	return out


## Launch a strike from home at a target (a ship) or toward a point. Returns the squadrons sent.
func launch_strike(home: Ship, target: Ship, aim: Vector2, with_fighters := true) -> Array:
	var sent := []
	var kinds := ["dive", "torpedo"]
	for sq in ready_squadrons(home, kinds):
		_launch(sq, "outbound", target, aim)
		sent.append(sq)
	if with_fighters and not sent.is_empty():
		var fs := ready_squadrons(home, ["fighter"])
		# keep one fighter squadron back for combat air patrol
		for i in range(0, maxi(0, fs.size() - 1)):
			_launch(fs[i], "outbound", target, aim)
			sent.append(fs[i])
	return sent


func launch_cap(home: Ship) -> Dictionary:
	var fs := ready_squadrons(home, ["fighter"])
	if fs.is_empty():
		return {}
	_launch(fs[0], "cap", null, Vector2(home.x, home.z))
	return fs[0]


func launch_scout(home: Ship, aim: Vector2) -> Dictionary:
	var ss := ready_squadrons(home, ["scout"])
	if ss.is_empty():
		return {}
	_launch(ss[0], "scouting", null, aim)
	return ss[0]


func recall(home: Ship) -> void:
	for sq in sqs:
		if sq.home == home and sq.state in ["outbound", "attacking", "cap", "scouting"]:
			sq.state = "returning"


func _launch(sq: Dictionary, state: String, target: Ship, aim: Vector2) -> void:
	var home: Ship = sq.home
	sq.state = "launching"
	sq.next = state
	sq.target = target
	sq.aim = aim
	sq.launch_left = sq.n
	sq.timer = 0.0
	sq.landed = 0
	sq.show_n = 0
	# the squadron forms up ahead of the ship while the planes come off the deck one by one
	var f0 := U.fwd(home.h)
	sq.x = home.x + f0.x * 900.0; sq.z = home.z + f0.y * 900.0; sq.h = home.h; sq.alt = ALT_FORM
	sq.v = home.v
	sq.attacked = false
	sq.aloft_t = 0.0
	sq.hits = 0
	_make_node(sq)


# =====================================================================
# simulation
# =====================================================================

func step(dt: float) -> void:
	for sq in sqs:
		if sq.state == "ready" or sq.state == "lost":
			if sq.state == "ready" and sq.rearm > 0.0:
				var home: Ship = sq.home
				var k: float = home.mod_health("hangar") * 0.5 + 0.5 if home.alive else 0.0
				sq.rearm = maxf(0.0, sq.rearm - dt * k)
			continue
		_step_sq(sq, dt)
	for dk in decks.values():
		_step_deck(dk, dt)
	_sync_decks()
	_radar_warnings()
	_flak(dt)
	_dogfights(dt)
	_loss_reports()
	_ai_t -= dt
	if _ai_t <= 0.0:
		_ai_t = 5.0
		_ai_carriers()
	# dead squadrons
	for sq in sqs:
		if sq.n <= 0 and sq.state != "lost" and sq.state != "ready":
			_lose(sq)


## Losses are reported a few at a time: "Enemy fighters: 3 Helldivers shot down".
func _loss_reports() -> void:
	for sq in sqs:
		var lf: int = sq.get("lost_f", 0)
		var la: int = sq.get("lost_aa", 0)
		if lf + la == 0 or B.t - sq.get("loss_t", -99.0) < 8.0:
			continue
		sq.loss_t = B.t
		sq.lost_f = 0; sq.lost_aa = 0
		var nm: String = Data.AIRCRAFT[sq.type].name + "s"
		if sq.team == B.player.team:
			var parts := []
			if lf > 0:
				parts.append("%d %s shot down by enemy fighters" % [lf, nm])
			if la > 0:
				parts.append("%d %s lost to flak" % [la, nm])
			B.say("%s%s." % [sq.name + ": ", "; ".join(parts)], "bad")
		else:
			var seen := false
			for fs in B.ships:
				if fs.team == B.player.team and fs.alive and U.hyp(fs.x - sq.x, fs.z - sq.z) < 7000.0:
					seen = true
			if seen:
				B.say("Enemy %s: %d shot down." % [nm, lf + la], "good")


## Air-search radar on the player's ship picks up incoming enemy squadrons.
func _radar_warnings() -> void:
	var p: Ship = B.player
	if not p.alive or p.T.radar <= 0.0:
		return
	for sq in sqs:
		if sq.team == p.team or sq.warned or sq.state not in ["outbound", "attacking", "scouting"]:
			continue
		var d := U.hyp(sq.x - p.x, sq.z - p.z)
		if d < p.T.radar * 1.6:
			sq.warned = true
			B.say("Air-search radar: aircraft bearing %s, %s, closing. About %d planes." % [U.deg3(p.bearing_to(sq.x, sq.z)), U.yards(d), sq.n], "bad")
			B.sfx.play("alarm", Vector2(p.x, p.z), B.cam.position, 0.5)


func _step_sq(sq: Dictionary, dt: float) -> void:
	var home: Ship = sq.home
	var A: Dictionary = Data.AIRCRAFT[sq.type]
	var spd: float = A.speed * Data.KN
	sq.aloft_t += dt
	if sq.state in ["outbound", "attacking", "cap", "scouting"]:
		_scout_report(sq)
	var want_h: float = sq.h
	var want_alt: float = ALT_CRUISE
	match sq.state:
		"launching":
			# planes take off one by one down the deck (or off the catapult) and fly up to the
			# squadron forming ahead of the ship
			if not home.alive:
				_lose(sq); return
			if decks.has(home):
				# planes come off the deck one by one (_step_deck); the rendezvous rides ahead
				var fd0 := U.fwd(home.h)
				sq.x = home.x + fd0.x * 900.0; sq.z = home.z + fd0.y * 900.0; sq.h = home.h
				sq.alt = ALT_FORM
				sq.v = home.v
				_step_solos(sq, dt, spd)
				if _deck_count(decks[home], sq) == 0 and sq.solos.is_empty():
					sq.state = sq.next
					sq.show_n = -1
					sq.v = spd
					sq.launched_t = B.t
					if home.is_player:
						_airborne_summary(home)
				_place_node(sq)
				return
			var carrier := home.T.has("aircraft")
			sq.timer += dt * (0.5 + 0.5 * home.mod_health("deck"))
			var per := 3.0 if carrier else 20.0
			# two planes can be rolling at once on a carrier deck; a catapult takes one
			if sq.launch_left > 0 and sq.timer > per and _deck_busy(home, ["roll", "cat"]) < (3 if carrier else 1):
				sq.timer = 0.0
				sq.launch_left -= 1
				_solo_takeoff(sq, carrier)
			# the rendezvous point rides 900 m ahead of the ship
			var f0 := U.fwd(home.h)
			sq.x = home.x + f0.x * 900.0; sq.z = home.z + f0.y * 900.0; sq.h = home.h
			sq.alt = ALT_FORM
			sq.v = home.v
			_step_solos(sq, dt, spd)
			if sq.launch_left <= 0 and sq.solos.is_empty():
				sq.state = sq.next
				sq.show_n = -1
				sq.v = spd
				sq.launched_t = B.t
				if home.is_player:
					_airborne_summary(home)
			_place_node(sq)
			return
		"outbound":
			sq.v = spd
			var tgt: Ship = sq.target if sq.target and sq.target.alive and not sq.target.escaped else null
			if tgt == null:
				tgt = _find_target(sq)
				sq.target = tgt
			if tgt and B.t - sq.get("retarget_t", -99.0) > 3.0:
				sq.retarget_t = B.t
				var better := _find_target(sq)
				if better and better != tgt and _target_value(better, sq) > _target_value(tgt, sq) * 1.4:
					tgt = better
					sq.target = tgt
			var goal: Vector2 = Vector2(tgt.x, tgt.z) if tgt else sq.aim
			want_h = U.bearing(sq.x, sq.z, goal.x, goal.y)
			var d := U.hyp(goal.x - sq.x, goal.y - sq.z)
			if tgt and d < (3500.0 if sq.kind == "torpedo" else 2500.0):
				sq.state = "attacking"
				sq.timer = 0.0
				if B.player.team != sq.team and B.t - _enemy_air_msg_t > 15.0:
					_enemy_air_msg_t = B.t
					B.say("Enemy aircraft attacking %s! %d %s." % [tgt.ship_name if not tgt.is_player else "us", sq.n, _kind_word(sq.kind)], "bad")
			elif tgt == null and d < 1500.0:
				# nothing at the search point: circle for a while, then go home
				sq.orbit += dt
				want_h = sq.h + deg_to_rad(25.0) * dt * 2.0
				if sq.orbit > 90.0:
					sq.state = "returning"
			if sq.kind == "fighter" and tgt == null and sq.orbit > 60.0:
				sq.state = "returning"
		"attacking":
			var tgt: Ship = sq.target
			if tgt == null or not tgt.alive or (tgt.is_sub() and tgt.depth == 2):
				sq.state = "returning"
			else:
				_attack(sq, tgt, dt, spd)
				return
		"returning":
			sq.v = spd
			if not home.alive:
				var alt_home := _nearest_carrier(sq)
				if alt_home:
					sq.home = alt_home; home = alt_home
				else:
					sq.aloft_t += dt
					if sq.aloft_t > 600.0:
						if B.player.team == sq.team:
							B.say("%s ditched: no deck to land on." % sq.name, "bad")
						_lose(sq); return
			want_h = U.bearing(sq.x, sq.z, home.x, home.z)
			if U.hyp(home.x - sq.x, home.z - sq.z) < 700.0:
				sq.state = "landing"
				sq.timer = 0.0
		"landing":
			# the squadron circles astern while the planes peel off and land one at a time
			var carrier := home.T.has("aircraft")
			var f0 := U.fwd(home.h)
			var wx: float = home.x - f0.x * 1100.0
			var wz: float = home.z - f0.y * 1100.0
			var dh := U.hyp(wx - sq.x, wz - sq.z)
			want_h = U.bearing(sq.x, sq.z, wx, wz) + (deg_to_rad(70.0) if dh < 500.0 else 0.0)
			want_alt = ALT_FORM * 0.7
			sq.v = spd * 0.6
			var queued: int = sq.n - sq.landed - sq.solos.size()
			sq.show_n = maxi(queued, 0)
			sq.timer += dt * (0.3 + 0.7 * home.mod_health("deck")) if carrier else dt * 0.5
			var per := 5.0 if carrier else 12.0
			var deck_ok := true
			if decks.has(home):
				# the deck must be spotted forward and the landing area clear of the last plane
				deck_ok = _deck_can_land(decks[home])
				per = 4.0
			# one plane in the groove at a time, the deck clear before the next comes down
			if queued > 0 and sq.timer > per and dh < 700.0 and deck_ok and _deck_busy(home, ["rollout", "taxi"]) == 0 and _deck_busy(home, ["approach"]) < 1:
				sq.timer = 0.0
				_solo_land(sq, carrier)
			_step_solos(sq, dt, spd)
			if decks.has(home) and _deck_count(decks[home], sq, ["rollout", "taxi_in"]) > 0:
				_place_node(sq)
				return
			if sq.landed >= sq.n and sq.solos.is_empty():
				sq.state = "ready"
				sq.show_n = -1
				sq.rearm = 240.0 if carrier else 400.0
				if sq.node:
					sq.node.queue_free(); sq.node = null
				if home.is_player:
					B.say("%s recovered: %d of %d planes back aboard." % [sq.name, sq.n, sq.n0], "good")
				return
		"cap":
			sq.v = spd * 0.8
			var intr = _nearest_enemy_sq(sq, 7000.0, ["dive", "torpedo", "fighter"])
			var leash := U.hyp(home.x - sq.x, home.z - sq.z)
			if intr != null and leash < 9000.0:
				want_h = U.bearing(sq.x, sq.z, intr.x, intr.z)
				sq.v = spd
			else:
				# orbit the carrier at about 2 km
				var d := U.hyp(home.x - sq.x, home.z - sq.z)
				want_h = U.bearing(sq.x, sq.z, home.x, home.z) + deg_to_rad(80.0 if d < 2200.0 else 30.0)
			if sq.aloft_t > 1500.0:
				sq.state = "returning"
		"scouting":
			sq.v = spd
			var d := U.hyp(sq.aim.x - sq.x, sq.aim.y - sq.z)
			want_h = U.bearing(sq.x, sq.z, sq.aim.x, sq.aim.y)
			if d < 1500.0:
				want_h = sq.h + deg_to_rad(20.0) * dt * 2.0
				sq.orbit += dt
			var found := _scout_report(sq)
			if found and sq.aim_update_t < B.t - 20.0:
				sq.aim_update_t = B.t
			if sq.aloft_t > 1200.0 or sq.orbit > 400.0:
				sq.state = "returning"
	# fly
	var turn := deg_to_rad(28.0) * dt
	sq.h = fposmod(sq.h + clampf(U.ang_d(sq.h, want_h), -turn, turn), TAU)
	sq.alt = lerpf(sq.alt, want_alt, dt * 0.6)
	var f := U.fwd(sq.h)
	sq.x += f.x * sq.v * dt
	sq.z += f.y * sq.v * dt
	_place_node(sq)


## One line when the last squadron of a launch is up: "Strike airborne: 31 Helldivers, 23 Avengers, 24 Hellcats."
func _airborne_summary(home: Ship) -> void:
	var counts := {}
	for o in sqs:
		if o.home != home:
			continue
		if o.state == "launching":
			return
		if B.t - o.get("launched_t", -999.0) < 150.0:
			var nm: String = Data.AIRCRAFT[o.type].name + "s"
			counts[nm] = counts.get(nm, 0) + o.n
	if counts.is_empty():
		return
	var parts := []
	for nm in counts:
		parts.append("%d %s" % [counts[nm], nm])
	B.say("Aircraft airborne: %s." % ", ".join(parts), "good")
	for o in sqs:
		if o.home == home:
			o.launched_t = -999.0


func _attack(sq: Dictionary, tgt: Ship, dt: float, spd: float) -> void:
	sq.v = spd * (1.15 if sq.kind == "dive" else 1.0)
	var to_t := U.bearing(sq.x, sq.z, tgt.x, tgt.z)
	var d := U.hyp(tgt.x - sq.x, tgt.z - sq.z)
	var A: Dictionary = Data.AIRCRAFT[sq.type]
	var want_h := to_t
	var want_alt := ALT_CRUISE
	match sq.kind:
		"dive":
			# straight in and down; bombs away over the target
			want_alt = lerpf(ALT_LOW, ALT_CRUISE, clampf(d / 2500.0, 0.0, 1.0))
			if d < 150.0 and not sq.attacked:
				sq.attacked = true
				_drop_bombs(sq, tgt, A.bomb)
				sq.state = "returning"
		"torpedo":
			# come in low on the beam and drop at about 1,000 m
			want_alt = ALT_LOW
			var f := U.fwd(tgt.h)
			var lead: float = tgt.v * (d / (A.torp.speed_kn * Data.KN * Data.TORP_SPEED))
			want_h = U.bearing(sq.x, sq.z, tgt.x + f.x * lead, tgt.z + f.y * lead)
			if d < 1100.0 and not sq.attacked:
				sq.attacked = true
				_drop_torps(sq, tgt, A.torp)
				sq.state = "returning"
		"fighter":
			# strafe once, then cover the bombers until they turn for home
			want_alt = 90.0
			if d < 300.0 and not sq.attacked:
				sq.attacked = true
				_strafe(sq, tgt)
			var others := false
			for o in sqs:
				if o.team == sq.team and o != sq and o.state in ["outbound", "attacking"] and o.kind != "fighter":
					others = true
			if sq.attacked and not others:
				sq.state = "returning"
			elif sq.attacked:
				want_h = sq.h + deg_to_rad(40.0) * dt * 2.0
		_:
			sq.state = "returning"
	var turn := deg_to_rad(35.0) * dt
	sq.h = fposmod(sq.h + clampf(U.ang_d(sq.h, want_h), -turn, turn), TAU)
	sq.alt = lerpf(sq.alt, want_alt, dt * 1.2)
	var fv := U.fwd(sq.h)
	sq.x += fv.x * sq.v * dt
	sq.z += fv.y * sq.v * dt
	_place_node(sq)


func _drop_bombs(sq: Dictionary, tgt: Ship, bomb: float) -> void:
	var hits := 0
	# hit chance: ship size, how hard she is turning, and the attackers' nerve under flak
	var p: float = 0.12 * clampf(tgt.T.get("size_vis", 1.0), 0.5, 2.2) * (0.6 if absf(tgt.rud) > 15.0 else 1.0) * (1.0 - minf(0.5, tgt.aa_power() / 24.0))
	if sq.home == B.player:
		p *= 1.0 + Career.mod("strike_acc")
	for i in sq.n:
		var lx := randf_range(-tgt.T.L * 0.45, tgt.T.L * 0.45)
		var lz := randf_range(-tgt.T.B * 0.4, tgt.T.B * 0.4)
		var w := tgt.to_world_xz(lx, lz)
		if randf() < p:
			hits += 1
			B.fx.boom(w.x, 8.0, w.y, false)
			B.sfx.play("bomb", Vector2(w.x, w.y), B.cam.position, 0.8)
			B.after(0.1 * i, func(): B.damage(tgt, lx, lz, bomb, "bomb", sq.home))
			if sq.home == B.player:
				B.tally.air_hits = int(B.tally.get("air_hits", 0)) + 1
		else:
			var miss := tgt.to_world_xz(lx + randf_range(-60, 60), lz + randf_range(-50, 50) * (1.0 if randf() < 0.5 else -1.0))
			B.fx.splash(miss.x, miss.y, true)
			B.sfx.play("splash", miss, B.cam.position, 0.4)
	sq.hits = hits
	var mine: bool = sq.team == B.player.team
	if mine or B.player.contact(tgt) or tgt.is_player:
		if hits > 0:
			B.say("%d bomb %s on %s from %s." % [hits, "hit" if hits == 1 else "hits", "us" if tgt.is_player else tgt.ship_name, sq.name], "good" if mine else "bad")
		elif mine:
			B.say("%s: all bombs missed %s." % [sq.name, tgt.ship_name])


func _drop_torps(sq: Dictionary, tgt: Ship, TT: Dictionary) -> void:
	var spd: float = TT.speed_kn * Data.KN * Data.TORP_SPEED
	var f := U.fwd(tgt.h)
	var d := U.hyp(tgt.x - sq.x, tgt.z - sq.z)
	var tt := d / spd
	var aim := Vector2(tgt.x + f.x * tgt.v * tt, tgt.z + f.y * tgt.v * tt)
	var brg := U.bearing(sq.x, sq.z, aim.x, aim.y)
	for i in sq.n:
		var a := brg + U.gauss() * deg_to_rad(3.0)
		var ox: float = sq.x + cos(sq.h) * (i - sq.n / 2.0) * 25.0
		var oz: float = sq.z + sin(sq.h) * (i - sq.n / 2.0) * 25.0
		B.torps.append({"x": ox, "z": oz, "h": a, "v": spd, "left": TT.range, "team": sq.team, "owner": sq.home, "dud": randf() < TT.dud, "warned": false, "depth": 3.0, "air": true})
		B.fx.splash(ox, oz, false)
	if sq.team == B.player.team or tgt.is_player or B.player.contact(tgt):
		B.say("%s: %d torpedoes dropped at %s." % [sq.name, sq.n, "us" if tgt.is_player else tgt.ship_name], "good" if sq.team == B.player.team else "bad")


func _strafe(sq: Dictionary, tgt: Ship) -> void:
	B.sfx.play("mg", Vector2(tgt.x, tgt.z), B.cam.position, 0.6)
	for i in sq.n:
		var lx := randf_range(-tgt.T.L * 0.4, tgt.T.L * 0.4)
		B.damage(tgt, lx, randf_range(-2, 2), 0.12, "strafe", null)
	if tgt.T.L < 60.0 and (tgt.is_player or sq.team == B.player.team):
		B.say("%s strafing %s." % [sq.name, "us" if tgt.is_player else tgt.ship_name], "bad" if tgt.is_player else "good")


## Scouts and strike squadrons report what they can see to their own side (shared by radio).
func _scout_report(sq: Dictionary) -> bool:
	var found := false
	for o in B.ships:
		if o.team == sq.team or not o.alive or o.escaped or (o.is_sub() and o.depth == 2):
			continue
		if U.hyp(o.x - sq.x, o.z - sq.z) < (7000.0 if not o.is_sub() else 1500.0):
			found = true
			for a in B.ships:
				if a.team == sq.team and a.alive:
					a.radar[o.ship_name] = true
			if sq.team != B.player.team and o.is_player and sq.kind == "scout" and B.t - _scout_msg_t > 120.0:
				_scout_msg_t = B.t
				B.say("Enemy scout plane overhead. They know where we are.", "bad")
	return found


func _find_target(sq: Dictionary) -> Ship:
	# the biggest enemy ship this side knows about near the aim point; carriers first
	var best: Ship = null
	var bv := -1.0
	for o in B.ships:
		if o.team == sq.team or not o.alive or o.escaped:
			continue
		if o.is_sub() and (o.depth == 2 or sq.get("kind", "") == "torpedo"):
			continue   # a deep boat can't be seen; torpedoes can't be used on a submarine
		var known := false
		for a in B.ships:
			if a.team == sq.team and a.alive and a.contact(o):
				known = true
				break
		if not known:
			continue
		if U.hyp(o.x - sq.x, o.z - sq.z) > 25000.0:
			continue
		var v := _target_value(o, sq)
		if v > bv:
			bv = v; best = o
	return best


func _target_value(o: Ship, sq: Dictionary) -> float:
	var d := U.hyp(o.x - sq.x, o.z - sq.z)
	return o.T.displacement * (3.0 if o.cls() in ["cv", "cvl", "cve"] else 1.0) - d * 0.5


func _nearest_carrier(sq: Dictionary) -> Ship:
	var best: Ship = null
	var bd := 1e9
	for o in B.ships:
		if o.team == sq.team and o.alive and o.T.has("aircraft") and not o.escaped:
			var d := U.hyp(o.x - sq.x, o.z - sq.z)
			if d < bd:
				bd = d; best = o
	return best


func _nearest_enemy_sq(sq: Dictionary, rng: float, kinds: Array):
	var best = null
	var bd := rng
	for o in sqs:
		if o.team == sq.team or o.state in ["ready", "lost", "launching", "landing"] or not kinds.has(o.kind):
			continue
		var d := U.hyp(o.x - sq.x, o.z - sq.z)
		if d < bd:
			bd = d; best = o
	return best


# =====================================================================
# flak and dogfights
# =====================================================================

## Light and heavy AA of every ship fires at enemy squadrons in range.
func _flak(dt: float) -> void:
	for s in B.ships:
		if not s.alive or s.escaped:
			continue
		var power: float = s.aa_power()
		if power <= 0.0:
			continue
		var tgt = _flak_target(s)
		if tgt == null:
			continue
		var d := U.hyp(tgt.x - s.x, tgt.z - s.z)
		var k := 1.0 - clampf(d / 2800.0, 0.0, 0.9)
		var kills: float = power * 0.0045 * k * dt * (1.25 if tgt.state == "attacking" else 1.0)
		if randf() < kills:
			tgt.n -= 1
			tgt.lost_aa = tgt.get("lost_aa", 0) + 1
			if s == B.player:
				B.tally.aa_kills = int(B.tally.get("aa_kills", 0)) + 1
			var ang := randf() * TAU
			B.fx.boom(tgt.x + cos(ang) * 30.0, tgt.alt, tgt.z + sin(ang) * 30.0, false)
			B.fx.debris(tgt.x, tgt.alt, tgt.z, 6, 12.0)
		# what you see and hear: tracer streams from the light guns, black bursts from the heavy
		var light: float = minf(1.0, power / 4.0)
		var to := Vector3(tgt.x, tgt.alt, tgt.z)
		if d < 2600.0 and randf() < dt * 1.6 * light:
			# a Bofors clip: four rounds a tenth of a second apart, arcing out to the planes
			var mp: Vector2 = s.to_world_xz(randf_range(-s.T.L * 0.3, s.T.L * 0.3), randf_range(-s.T.B * 0.3, s.T.B * 0.3))
			var from := Vector3(mp.x, 8.0, mp.y)
			var col := Color(1.0, 0.85, 0.5) if s.team == "us" else Color(1.0, 0.5, 0.3)
			for ri in 4:
				B.after(0.11 * ri, func(): _fire_round(from, to, 650.0, col, 1.0, 12.0))
			B.sfx.play("aa_bofors", mp, B.cam.position, 0.6)
		if d < 1400.0 and randf() < dt * 2.2 * light:
			# machine guns: a quick stream of small tracers
			var mp2: Vector2 = s.to_world_xz(randf_range(-s.T.L * 0.3, s.T.L * 0.3), randf_range(-s.T.B * 0.3, s.T.B * 0.3))
			var from2 := Vector3(mp2.x, 7.0, mp2.y)
			var col2 := Color(1.0, 0.75, 0.45) if s.team == "us" else Color(1.0, 0.45, 0.3)
			for ri in 7:
				B.after(0.06 * ri, func(): _fire_round(from2, to, 820.0, col2, 0.6, 25.0))
			B.sfx.play("aa_mg", mp2, B.cam.position, 0.5)
		if s.T.L > 60.0 and d > 900.0 and randf() < dt * 0.9 * light:
			# heavy flak: 5-inch time-fuzed shells burst in black puffs around the formation
			var bp := to + Vector3(randf_range(-110, 110), randf_range(-30, 30), randf_range(-110, 110))
			_flak_burst(bp)
			B.sfx.play("flak", Vector2(bp.x, bp.z), B.cam.position, 0.7)
	_step_rounds(dt)


## A tracer round in flight: a glowing streak that climbs out to where the planes are.
var rounds: Array = []
func _fire_round(from: Vector3, to: Vector3, speed: float, col: Color, width: float, spread: float) -> void:
	var aim := to + Vector3(randf_range(-spread, spread), randf_range(-spread * 0.5, spread * 0.5), randf_range(-spread, spread))
	var dirv := (aim - from)
	var dist := dirv.length()
	if dist < 1.0:
		return
	rounds.append({"pos": from, "vel": dirv / dist * speed, "life": dist / speed + 0.4, "col": col, "w": width})


func _step_rounds(dt: float) -> void:
	for r in rounds:
		r.life -= dt
		var prev: Vector3 = r.pos
		r.pos += r.vel * dt
		# gravity bends the long shots over; a tracer burns out after its run
		r.vel.y -= 9.8 * dt * 0.6
		var tail: Vector3 = r.pos - r.vel.normalized() * 28.0
		B.fx.tracer(tail, r.pos, r.col, r.w)
		if r.life < 0.3 and randf() < dt * 8.0:
			r.life = 0.0
	rounds = rounds.filter(func(r): return r.life > 0.0 and r.pos.y > 0.0)


## A time-fuzed burst: orange flash, then a dark puff that hangs and drifts.
func _flak_burst(p: Vector3) -> void:
	B.fx.flash(p.x, p.y, p.z, 6.0, 20.0, 0.12, Color(1.0, 0.75, 0.4))
	for k in 3:
		B.fx.smoke(p.x + randf_range(-4, 4), p.y + randf_range(-3, 3), p.z + randf_range(-4, 4), B.fx.wind.x * 0.5, B.fx.wind.y * 0.5, randf_range(7, 10), 4.0, randf_range(5, 8), 0.75, Color(0.1, 0.1, 0.1), 0.05)


## Which squadron a ship shoots at: by default the nearest enemy planes threatening itself;
## the player's ships can be told to protect the carrier or go for bombers first.
func _flak_target(s: Ship):
	var mode := aa_mode if s.team == B.player.team else "self"
	var best = null
	var bv := 1e9
	for sq in sqs:
		if sq.team == s.team or sq.state in ["ready", "lost", "launching", "landing"]:
			continue
		var d := U.hyp(sq.x - s.x, sq.z - s.z)
		if d > 2800.0:
			continue
		var v := d
		match mode:
			"carrier":
				var cv := _nearest_carrier({"team": s.team, "x": s.x, "z": s.z})
				if cv and sq.target == cv:
					v -= 5000.0
			"bombers":
				if sq.kind != "fighter":
					v -= 5000.0
		if sq.target == s:
			v -= 1500.0
		if v < bv:
			bv = v; best = sq
	return best


func _dogfights(dt: float) -> void:
	for f in sqs:
		if f.kind != "fighter" or f.state in ["ready", "lost", "launching", "landing", "returning"] or f.n <= 0:
			continue
		var e = _nearest_enemy_sq(f, 1500.0, ["fighter", "dive", "torpedo", "scout"])
		if e == null:
			continue
		var fa: float = Data.AIRCRAFT[f.type].rating * (f.n / 12.0)
		var ea: float = Data.AIRCRAFT[e.type].rating * (e.n / 12.0)
		# a full fighter squadron downs a bomber every 15-20 seconds, a fighter every half minute or so
		var k_f: float = fa * (0.03 if e.kind == "fighter" else 0.06) * dt
		var k_e: float = ea * 0.03 * dt
		if randf() < k_f:
			e.n -= 1
			e.lost_f = e.get("lost_f", 0) + 1
			B.fx.boom(e.x + randf_range(-30, 30), e.alt, e.z + randf_range(-30, 30), false)
		if randf() < k_e:
			f.n -= 1
			f.lost_f = f.get("lost_f", 0) + 1
			B.fx.boom(f.x + randf_range(-30, 30), f.alt, f.z + randf_range(-30, 30), false)
		# bombers under fighter attack jettison and run
		if e.kind != "fighter" and e.state == "outbound" and randf() < dt * 0.02 * fa:
			e.state = "returning"


func _lose(sq: Dictionary) -> void:
	sq.state = "lost"
	sq.n = 0
	if sq.node != null and is_instance_valid(sq.node):
		sq.node.queue_free()
	sq.node = null
	_clear_solos(sq)


# =====================================================================
# carrier AI
# =====================================================================

func _ai_carriers() -> void:
	for s in B.ships:
		if not s.alive or s.escaped or s.is_player or not s.T.has("aircraft"):
			continue
		# a scout out first, then combat air patrol, then the strike when a target is known
		if not ready_squadrons(s, ["scout"]).is_empty():
			pass
		var cap_up := false
		for sq in sqs:
			if sq.home == s and sq.state == "cap":
				cap_up = true
		if not cap_up and ready_squadrons(s, ["fighter"]).size() >= 1:
			launch_cap(s)
		var tgt := _find_target({"team": s.team, "x": s.x, "z": s.z})
		if tgt == null:
			# send a bomber squadron to search toward where the enemy was last reported
			continue
		var strike_up := false
		for sq in sqs:
			if sq.home == s and sq.state in ["launching", "outbound", "attacking"] and sq.kind != "fighter":
				strike_up = true
		if not strike_up and not ready_squadrons(s, ["dive", "torpedo"]).is_empty():
			var sent := launch_strike(s, tgt, Vector2(tgt.x, tgt.z))
			if not sent.is_empty() and B.player.contact(s):
				B.say("%s is launching aircraft!" % s.ship_name, "bad")
	# floatplane scouts from AI cruisers and battleships
	for s in B.ships:
		if not s.alive or s.is_player or s.T.has("aircraft"):
			continue
		if B.t > 30.0 and not ready_squadrons(s, ["scout"]).is_empty() and B.report.get("active", false) == false:
			continue
		if B.t > 30.0 and not ready_squadrons(s, ["scout"]).is_empty():
			var any_contact := false
			for o in B.ships:
				if o.team != s.team and o.alive and s.contact(o):
					any_contact = true
			if not any_contact:
				launch_scout(s, Vector2(B.player.x + randf_range(-3000, 3000), B.player.z + randf_range(-3000, 3000)))


# =====================================================================
# visuals
# =====================================================================

func _make_node(sq: Dictionary) -> void:
	if sq.node != null and is_instance_valid(sq.node):
		sq.node.queue_free()
	var root := Node3D.new()
	add_child(root)
	sq.node = root
	var path: String = Data.AIRCRAFT[sq.type].model
	if not _cache.has(path):
		_cache[path] = load(path)
	var scene: PackedScene = _cache[path]
	for i in sq.n:
		var p: Node3D = scene.instantiate()
		# V formation: leader ahead, pairs stepped back and out
		var row: int = (i + 1) / 2
		var side := 1 if i % 2 == 1 else -1
		p.position = Vector3(side * row * 16.0, -row * 1.5, row * 14.0) if i > 0 else Vector3.ZERO
		root.add_child(p)


func _place_node(sq: Dictionary) -> void:
	var n = sq.node
	if n == null or not is_instance_valid(n):
		return
	# drop planes that were shot down
	while n.get_child_count() > sq.n and n.get_child_count() > 0:
		var c: Node = n.get_child(n.get_child_count() - 1)
		n.remove_child(c)
		c.queue_free()
	var show: int = sq.get("show_n", -1)
	for i in n.get_child_count():
		n.get_child(i).visible = show < 0 or i < show
	n.position = Vector3(sq.x, sq.alt, sq.z)
	var bank := clampf(U.ang_d(sq.h, sq.get("prev_h", sq.h)) * 8.0, -0.6, 0.6)
	sq.prev_h = sq.h
	n.transform.basis = Basis(Vector3.UP, -sq.h) * Basis(Vector3.BACK, bank)
	n.visible = sq.state != "ready" and sq.state != "lost"


# ---------- single planes on the deck: take-off and landing ----------

func _plane_scene(sq: Dictionary) -> PackedScene:
	var path: String = Data.AIRCRAFT[sq.type].model
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


## Ship-local deck geometry: the flight deck height and where the roll starts and ends.
func _deck_y(home: Ship) -> float:
	if not home.park.is_empty():
		return home.park[0].ly
	if not home.floats.is_empty():
		return home.floats[0].ly
	return 12.0


func _solo_takeoff(sq: Dictionary, carrier: bool) -> void:
	var home: Ship = sq.home
	var p: Node3D = _plane_scene(sq).instantiate()
	add_child(p)
	var so := {"node": p, "phase": "roll", "t": 0.0, "lx": 0.0, "ly": _deck_y(home), "lz": 0.0, "v": 0.0,
		"x": 0.0, "z": 0.0, "y": 0.0, "h": home.h}
	if carrier:
		so.lx = -home.T.L * 0.18          # from the deck park, rolling forward to the bow
		so.v = 4.0
	else:
		# off the catapult: a short, hard shove
		var cat: Dictionary = home.floats[0] if not home.floats.is_empty() else {"lx": -home.T.L * 0.3, "lz": 0.0}
		so.lx = cat.lx; so.lz = cat.lz
		so.phase = "cat"
		so.v = 10.0
	sq.solos.append(so)


func _solo_land(sq: Dictionary, carrier: bool) -> void:
	var p: Node3D = _plane_scene(sq).instantiate()
	add_child(p)
	var so := {"node": p, "phase": "approach", "t": 0.0, "lx": 0.0, "ly": 0.0, "lz": 0.0, "v": 0.0,
		"x": sq.x, "z": sq.z, "y": sq.alt, "h": sq.h, "carrier": carrier}
	sq.solos.append(so)


## How many single planes of this ship are in the given phases (all its squadrons).
func _deck_busy(home: Ship, phases: Array) -> int:
	var n := 0
	for sq in sqs:
		if sq.home != home:
			continue
		for so in sq.solos:
			if so.phase in phases:
				n += 1
	return n


func _clear_solos(sq: Dictionary) -> void:
	for so in sq.solos:
		if so.node != null and is_instance_valid(so.node):
			so.node.queue_free()
	sq.solos.clear()


func _step_solos(sq: Dictionary, dt: float, spd: float) -> void:
	var home: Ship = sq.home
	var L: float = home.T.L
	var done := []
	for so in sq.solos:
		so.t += dt
		match so.phase:
			"roll":
				# down the deck, throttle up, wheels off near the bow
				so.v = minf(so.v + 14.0 * dt, 42.0)
				so.lx += (so.v - home.v * 0.0) * dt
				so.h = home.h
				var w := home.to_world_xz(so.lx, so.lz)
				so.x = w.x; so.z = w.y; so.y = home.global_position.y + so.ly + (maxf(so.lx - L * 0.3, 0.0) * 0.08)
				if so.lx > L * 0.47:
					so.phase = "climb"
			"cat":
				so.v = minf(so.v + 60.0 * dt, 38.0)
				so.lx += so.v * dt
				so.h = home.h
				var w := home.to_world_xz(so.lx, so.lz)
				so.x = w.x; so.z = w.y; so.y = home.global_position.y + so.ly
				if so.t > 1.4:
					so.phase = "climb"
			"climb":
				# up and away to the squadron forming ahead
				so.v = minf(so.v + 12.0 * dt, spd * 0.85)
				var want := U.bearing(so.x, so.z, sq.x, sq.z)
				var turn := deg_to_rad(30.0) * dt
				so.h = fposmod(so.h + clampf(U.ang_d(so.h, want), -turn, turn), TAU)
				var f := U.fwd(so.h)
				so.x += f.x * so.v * dt; so.z += f.y * so.v * dt
				so.y = minf(so.y + 9.0 * dt, sq.alt)
				var d := U.hyp(sq.x - so.x, sq.z - so.z)
				if d < 90.0 or so.t > 60.0:
					sq.show_n = mini(int(sq.show_n) + 1, sq.n)
					done.append(so)
			"approach":
				# down the glide path to the stern (carrier) or the water alongside (floatplane)
				var aim: Vector2
				var aim_y: float
				if so.carrier and decks.has(home):
					aim = home.to_world_xz(decks[home].x_touch, 0.0)
					aim_y = home.global_position.y + decks[home].y + 0.6
				elif so.carrier:
					aim = home.to_world_xz(-L * 0.46, 0.0)
					aim_y = home.global_position.y + _deck_y(home) + 1.0
				else:
					aim = home.to_world_xz(-L * 0.2, 70.0)
					aim_y = 0.4
				so.v = maxf(so.v - 10.0 * dt, spd * 0.45) if so.v > spd * 0.45 else spd * 0.45
				var want := U.bearing(so.x, so.z, aim.x, aim.y)
				var turn := deg_to_rad(32.0) * dt
				so.h = fposmod(so.h + clampf(U.ang_d(so.h, want), -turn, turn), TAU)
				var f := U.fwd(so.h)
				so.x += f.x * so.v * dt; so.z += f.y * so.v * dt
				var d := U.hyp(aim.x - so.x, aim.y - so.z)
				# glide: height proportional to distance, never below the aim point
				so.y = maxf(aim_y, minf(so.y, aim_y + d * 0.09))
				if d < 25.0 or so.t > 90.0:
					if so.carrier and decks.has(home):
						# wheels down: the plane becomes part of the deck
						_deck_touchdown(decks[home], sq, so)
						sq.landed += 1
						done.append(so)
						so.node = null
						continue
					if so.carrier:
						so.phase = "rollout"
						so.lx = -L * 0.46; so.lz = 0.0; so.ly = _deck_y(home)
					else:
						so.phase = "taxi"
						var lp := home.to_local_xz(so.x, so.z)
						so.lx = lp.x; so.lz = lp.y; so.ly = 0.4
					so.v = 30.0
					so.t = 0.0
			"rollout":
				# wire caught: a hard stop up the deck
				so.v = maxf(so.v - 14.0 * dt, 0.0)
				so.lx += so.v * dt
				so.h = home.h
				var w := home.to_world_xz(so.lx, so.lz)
				so.x = w.x; so.z = w.y; so.y = home.global_position.y + so.ly
				if so.v <= 0.0 or so.lx > L * 0.1:
					sq.landed += 1
					done.append(so)
			"taxi":
				# on the water, taxiing in to the crane
				so.v = 6.0
				var tgt := Vector2(-L * 0.2, home.half_width_at(-L * 0.2) + 10.0)
				var dd := tgt - Vector2(so.lx, so.lz)
				if dd.length() < 6.0 or so.t > 40.0:
					sq.landed += 1
					done.append(so)
				else:
					var step: Vector2 = dd.normalized() * so.v * dt
					so.lx += step.x; so.lz += step.y
					so.h = home.h + atan2(dd.y, dd.x)
					var w := home.to_world_xz(so.lx, so.lz)
					so.x = w.x; so.z = w.y; so.y = 0.4
		if so.node != null and is_instance_valid(so.node):
			so.node.position = Vector3(so.x, so.y, so.z)
			so.node.transform.basis = Basis(Vector3.UP, -so.h)
	for so in done:
		if so.node != null and is_instance_valid(so.node):
			so.node.queue_free()
		sq.solos.erase(so)


## Parked planes on each deck: as many hidden as are away from the ship.
func _sync_decks() -> void:
	for sh in B.ships:
		if decks.has(sh) or (sh.park.is_empty() and sh.floats.is_empty()):
			continue
		var away := 0
		for sq in sqs:
			if sq.home != sh:
				continue
			match sq.state:
				"ready", "lost": pass
				"launching": away += sq.n - int(sq.launch_left)
				"landing": away += sq.n - int(sq.landed)
				_: away += sq.n
		var slots: Array = sh.park if not sh.park.is_empty() else sh.floats
		for i in slots.size():
			slots[slots.size() - 1 - i].node.visible = i >= away


## Take a team's aircraft out of the battle entirely (deck planes too).
func clear_team(team: String) -> void:
	for sq in sqs:
		if sq.team == team and sq.node != null and is_instance_valid(sq.node):
			sq.node.queue_free()
	sqs = sqs.filter(func(q): return q.team != team)
	for sh in decks.keys():
		if sh.team == team:
			for p in decks[sh].planes:
				if p.node != null and is_instance_valid(p.node):
					p.node.queue_free()
			decks.erase(sh)


func _kind_word(kind: String) -> String:
	match kind:
		"fighter": return "fighters"
		"dive": return "dive bombers"
		"torpedo": return "torpedo bombers"
	return "scout planes"


## Squadrons in the air for the HUD list, newest first.
func aloft(team: String) -> Array:
	var out := []
	for sq in sqs:
		if sq.team == team and sq.state not in ["ready", "lost"]:
			out.append(sq)
	return out


# ---------- save / load ----------

func save() -> Array:
	var out := []
	for sq in sqs:
		var d := {}
		for k in ["id", "team", "type", "kind", "n", "n0", "x", "z", "h", "alt", "v", "state", "timer", "launch_left", "aloft_t", "attacked", "rearm", "hits", "name", "orbit"]:
			d[k] = sq[k]
		d.next = sq.get("next", "outbound")
		d.aim = [sq.aim.x, sq.aim.y]
		d.home = B.ships.find(sq.home)
		d.target = B.ships.find(sq.target) if sq.target != null else -1
		out.append(d)
	return out


func restore(data: Array) -> void:
	reset()
	for d in data:
		var home: Ship = B.ships[int(d.home)] if int(d.home) >= 0 else null
		if home == null:
			continue
		var sq := _new_sq(home, d.type, int(d.n), d.state)
		for k in ["x", "z", "h", "alt", "v", "timer", "aloft_t", "attacked", "rearm", "hits", "name", "orbit"]:
			sq[k] = d[k]
		sq.n0 = int(d.n0); sq.launch_left = int(d.launch_left); sq.id = int(d.id)
		sq.next = d.next
		sq.aim = Vector2(d.aim[0], d.aim[1])
		sq.target = B.ships[int(d.target)] if int(d.target) >= 0 else null
		if home.T.has("aircraft") and home.T.has("fdeck"):
			# a save made mid-launch or mid-recovery: those planes are put aloft or aboard
			if sq.state == "launching":
				sq.state = sq.next
			elif sq.state == "landing":
				sq.state = "returning"
		if sq.state not in ["ready", "lost"]:
			_make_node(sq)
			_place_node(sq)
	for sh in B.ships:
		if sh.T.has("aircraft") and sh.T.has("fdeck") and not decks.has(sh):
			var dk := _deck_new(sh)
			var mine := []
			for sq in sqs:
				if sq.home == sh and sq.state == "ready":
					mine.append(sq)
			_deck_spot_initial(dk, mine)


# =====================================================================
# the flight deck: every plane of a carrier's air group is parked on deck in rows (wings
# folded), fighters forward, dive bombers, torpedo planes aft. Planes take off from the front
# of the pack one at a time: taxi to the centreline, spread the wings, roll and lift off over
# the bow. For recovery the deck crew pushes the parked rows forward (row by row, so nothing
# passes through anything), planes land over the stern, catch a wire, fold and taxi forward to
# park behind the others; before the next launch the rows are pushed aft again. Planes lost in
# action are replaced from the hangar on a timer. Ship-local coordinates: lx forward, lz to
# starboard; deck planes are children of the Ship node so they ride its roll and heave.
# =====================================================================

const DECK_COL := 6.0           # athwartships spacing of parked planes (folded tails are ~5.8 m)
const DECK_ROW := 13.0          # fore-and-aft spacing of the rows
const ROLL_V := 36.0            # take-off speed relative to the deck, m/s
const RESPOT_V := 6.0           # the deck crew pushing a row of planes, m/s
const TAXI_V := 5.0
const TAXI_OUT_V := 9.0          # deck crews hurry a plane to the launch spot
const REPLACE_T := 45.0         # seconds per replacement plane from the hangar (full health)

func _deck_new(s: Ship) -> Dictionary:
	var fd: Dictionary = s.T.fdeck
	var w: float = fd.zmax - fd.zmin
	var nc: int = maxi(1, int(floor((w + 0.5) / DECK_COL)))
	var zc: float = (fd.zmin + fd.zmax) * 0.5
	var cols := []
	for i in nc:
		cols.append(zc + (i - (nc - 1) * 0.5) * DECK_COL)
	var length: float = fd.front - fd.back
	var nr: int = maxi(1, int(floor(length * 0.6 / DECK_ROW)))
	# launch order inside a row: the planes nearest the centreline first; landing fills the
	# other way round (outboard first) so a plane never taxis through a parked one
	var launch_order := range(nc)
	launch_order.sort_custom(func(a, b): return absf(cols[a]) < absf(cols[b]))
	var fill_order := launch_order.duplicate()
	fill_order.reverse()
	var dk := {"ship": s, "cols": cols, "nc": nc, "nr": nr, "cap": nc * nr, "y": float(fd.y),
		"x_bow": float(fd.front) - 10.0, "x_stern": float(fd.back) + 8.0, "x_touch": float(fd.back) + 14.0, "x_end": float(fd.front),
		"rows": [], "planes": [], "mode": "aft", "moving": false, "fill_row": null, "launch_t": 0.0, "rep_t": 0.0,
		"launch_order": launch_order, "fill_order": fill_order}
	decks[s] = dk
	return dk


## Park the air group in the launch spot aft, rows from the front: fighters, dive, torpedo.
func _deck_spot_initial(dk: Dictionary, squads: Array) -> void:
	var order := {"fighter": 0, "scout": 0, "dive": 1, "torpedo": 2}
	var list := squads.duplicate()
	list.sort_custom(func(a, b): return order.get(a.kind, 3) < order.get(b.kind, 3))
	var planes := []
	for sq in list:
		for i in sq.n:
			planes.append(sq)
	var nrow: int = int(ceil(float(planes.size()) / dk.nc))
	dk.rows.clear()
	for r in nrow:
		var row := {"x": dk.x_stern + (nrow - 1 - r) * DECK_ROW, "tx": 0.0, "cells": []}
		row.cells.resize(dk.nc)
		dk.rows.append(row)
	var i := 0
	for r in nrow:
		for c in dk.launch_order:
			if i >= planes.size():
				break
			_deck_add_plane(dk, planes[i], dk.rows[r], c, false)
			i += 1
	dk.mode = "aft"


func _deck_add_plane(dk: Dictionary, sq: Dictionary, row: Dictionary, c: int, lift: bool) -> Dictionary:
	var p := {"sq": sq, "node": null, "phase": "lift" if lift else "parked", "row": row, "col": c,
		"lx": row.x, "lz": dk.cols[c], "ly": dk.y, "psi": 0.0, "v": 0.0, "acc": 0.0, "path": [], "t": 0.0, "folded": true}
	row.cells[c] = p
	_deck_node(dk, p, true)
	if lift:
		p.ly = dk.y - 6.0
	dk.planes.append(p)
	_deck_place(dk, p)
	return p


func _folded_scene(sq: Dictionary) -> PackedScene:
	var path: String = Data.AIRCRAFT[sq.type].model.replace(".glb", "_folded.glb")
	if not ResourceLoader.exists(path):
		path = Data.AIRCRAFT[sq.type].model
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


## Give a deck plane its model, wings folded (parked, taxiing) or spread (take-off run).
func _deck_node(dk: Dictionary, p: Dictionary, folded: bool) -> void:
	if p.node != null and is_instance_valid(p.node):
		p.node.queue_free()
	var n: Node3D = (_folded_scene(p.sq) if folded else _plane_scene(p.sq)).instantiate()
	dk.ship.add_child(n)
	p.node = n
	p.folded = folded


func _deck_place(dk: Dictionary, p: Dictionary) -> void:
	if p.node == null or not is_instance_valid(p.node):
		return
	p.node.position = Vector3(p.lz, p.ly, -p.lx)
	p.node.transform.basis = Basis(Vector3.UP, -p.psi)


## Planes of a squadron on this deck (optionally only in some phases).
func _deck_count(dk: Dictionary, sq: Dictionary, phases := []) -> int:
	var n := 0
	for p in dk.planes:
		if p.sq == sq and (phases.is_empty() or phases.has(p.phase)):
			n += 1
	return n


func _deck_phase_count(dk: Dictionary, phases: Array) -> int:
	var n := 0
	for p in dk.planes:
		if phases.has(p.phase):
			n += 1
	return n


func _deck_parked(dk: Dictionary) -> int:
	return _deck_phase_count(dk, ["parked", "lift"])


func _deck_can_land(dk: Dictionary) -> bool:
	if dk.moving or (dk.mode != "fwd" and _deck_parked(dk) > 0):
		return false
	if _deck_phase_count(dk, ["taxi_out", "hold", "roll"]) > 0:
		return false
	for p in dk.planes:
		# the last plane down must have rolled out and cleared the landing area
		if p.phase == "rollout" or (p.phase == "taxi_in" and p.lx < dk.x_touch + 45.0):
			return false
	return true


## Push the parked rows forward (for recovery) or aft (to spot a launch), each row in a straight
## line so the rows keep their order and nothing passes through anything.
func _deck_respot(dk: Dictionary, mode: String) -> void:
	dk.rows = dk.rows.filter(func(r): return r.cells.any(func(c): return c != null))
	var n: int = dk.rows.size()
	for i in n:
		dk.rows[i].tx = dk.x_bow - i * DECK_ROW if mode == "fwd" else dk.x_stern + (n - 1 - i) * DECK_ROW
	dk.mode = mode
	dk.fill_row = null
	dk.moving = n > 0
	if dk.ship.is_player and n > 0 and B.t > 5.0:
		B.say("Flight deck: respotting the deck %s." % ("forward for recovery" if mode == "fwd" else "aft for the launch"))


func _step_deck(dk: Dictionary, dt: float) -> void:
	var sh: Ship = dk.ship
	if not is_instance_valid(sh) or not sh.alive:
		return
	var k: float = 0.4 + 0.6 * sh.mod_health("deck")
	# rows being pushed
	if dk.moving:
		var still := false
		for r in dk.rows:
			var d: float = r.tx - r.x
			var st: float = RESPOT_V * k * dt
			if absf(d) > st:
				r.x += signf(d) * st
				still = true
			else:
				r.x = r.tx
			for c in r.cells:
				if c != null and c.phase in ["parked", "lift"]:
					c.lx = r.x
					_deck_place(dk, c)
		dk.moving = still
	# what the deck is wanted for
	var want_launch := false
	var want_land := false
	for sq in sqs:
		if sq.home != sh:
			continue
		if sq.state == "launching" and _deck_count(dk, sq, ["parked", "lift"]) > 0:
			want_launch = true
		if sq.state == "landing" and sq.n - sq.landed - sq.solos.size() > 0:
			want_land = true
		# a squadron on its way home and close: start clearing the landing area now
		if sq.state == "returning" and U.hyp(sq.x - sh.x, sq.z - sh.z) < 9000.0:
			want_land = true
	var landing_now := _deck_phase_count(dk, ["rollout", "taxi_in"]) > 0 or _deck_busy(sh, ["approach"]) > 0
	var launching_now := _deck_phase_count(dk, ["taxi_out", "hold", "roll"]) > 0
	if not dk.moving:
		if want_launch and not landing_now:
			if dk.mode != "aft" and _deck_parked(dk) > 0:
				_deck_respot(dk, "aft")
			else:
				_deck_launch_next(dk, dt, k)
		elif want_land and not launching_now:
			if dk.mode != "fwd" and _deck_parked(dk) > 0:
				_deck_respot(dk, "fwd")
			elif _deck_parked(dk) == 0 and dk.mode != "fwd":
				dk.mode = "fwd"
				dk.fill_row = null
				_deck_compact(dk)
		elif not want_launch and not want_land and not launching_now and not landing_now:
			_deck_replace(dk, dt)
	if B._test.has("decktrace") and sh.is_player and int(B.t * 20.0) % 400 == 0:
		var ph := {}
		for p in dk.planes:
			ph[p.phase] = ph.get(p.phase, 0) + 1
		var st := []
		for sq in sqs:
			if sq.home == sh:
				st.append("%s:%s n%d l%d s%d" % [sq.type, sq.state, sq.n, sq.landed, sq.solos.size()])
		print("deck t=%d mode=%s moving=%s rows=%d %s | %s" % [B.t, dk.mode, dk.moving, dk.rows.size(), ph, ", ".join(st)])
	# move every plane that is doing something
	var gone := []
	for p in dk.planes:
		if _deck_step_plane(dk, p, dt, k):
			gone.append(p)
	for p in gone:
		dk.planes.erase(p)


func _deck_launch_next(dk: Dictionary, dt: float, k: float) -> void:
	dk.launch_t -= dt * k
	# one plane taxiing up while the one ahead waits on the launch spot
	if dk.launch_t > 0.0 or _deck_phase_count(dk, ["taxi_out"]) > 0 or _deck_phase_count(dk, ["hold"]) > 1:
		return
	# the front row that still has planes in it
	for r in dk.rows:
		var row_has := false
		for c in dk.launch_order:
			var p = r.cells[c]
			if p == null or p.phase != "parked":
				continue
			row_has = true
			var sq: Dictionary = p.sq
			if sq.state != "launching":
				# parked in front of the planes that are going: it goes first, with them
				_deck_blocker(dk, sq)
			r.cells[c] = null
			p.phase = "taxi_out"
			p.t = 0.0
			p.path = [Vector2(p.lx + DECK_ROW * 0.5, p.lz * 0.45), Vector2(p.lx + DECK_ROW, 0.0)]
			dk.launch_t = 0.4
			return
		if row_has:
			return


## A plane parked ahead of a launching squadron launches with it: fighters fly combat air
## patrol, bombers join the strike (or search if only fighters were ordered up).
func _deck_blocker(dk: Dictionary, sq: Dictionary) -> void:
	var waiting = null
	for o in sqs:
		if o.home == dk.ship and o.state == "launching":
			waiting = o
			break
	if waiting == null:
		return
	var nxt: String = waiting.get("next", "outbound")
	var cap_up := false
	for o in sqs:
		if o.home == dk.ship and (o.state == "cap" or (o.state == "launching" and o.get("next", "") == "cap")):
			cap_up = true
	if sq.kind == "fighter" and not cap_up:
		nxt = "cap"
	elif sq.kind != "fighter" and nxt == "cap":
		nxt = "scouting"
	_launch(sq, nxt, waiting.target, waiting.aim)
	if nxt == "scouting":
		var f := U.fwd(dk.ship.h)
		sq.aim = Vector2(dk.ship.x + f.x * 15000.0, dk.ship.z + f.y * 15000.0)


## A plane from the landing pattern touches down: it becomes a deck plane rolling out.
func _deck_touchdown(dk: Dictionary, sq: Dictionary, so: Dictionary) -> void:
	var p := {"sq": sq, "node": so.node, "phase": "rollout", "row": null, "col": 0,
		"lx": dk.x_touch, "lz": 0.0, "ly": dk.y, "psi": 0.0, "v": 26.0, "acc": 0.0, "path": [], "t": 0.0, "folded": false}
	if p.node != null and is_instance_valid(p.node):
		p.node.reparent(dk.ship, false)
	else:
		_deck_node(dk, p, false)
	# its parking place: the next free spot behind the parked rows, outboard spots first
	_deck_compact(dk)
	var row = dk.fill_row
	var col := -1
	if row != null:
		for c in dk.fill_order:
			if row.cells[c] == null:
				col = c
				break
	if col < 0:
		var last_x: float = dk.rows[dk.rows.size() - 1].x if not dk.rows.is_empty() else dk.x_bow + DECK_ROW
		row = {"x": maxf(last_x - DECK_ROW, dk.x_touch + 50.0), "tx": 0.0, "cells": []}
		row.cells.resize(dk.nc)
		dk.rows.append(row)
		dk.fill_row = row
		col = dk.fill_order[0]
	row.cells[col] = p
	p.row = row
	p.col = col
	dk.planes.append(p)
	_deck_place(dk, p)


## Drop rows with nobody in them (the row being filled by landing planes stays).
func _deck_compact(dk: Dictionary) -> void:
	dk.rows = dk.rows.filter(func(r): return r == dk.fill_row or r.cells.any(func(c): return c != null))


## Replacement planes come up from the hangar, one at a time, until each squadron is full.
func _deck_replace(dk: Dictionary, dt: float) -> void:
	var sh: Ship = dk.ship
	var need = null
	for sq in sqs:
		if sq.home == sh and sq.state in ["ready", "lost"] and sq.n < sq.n0:
			need = sq
			break
	if need == null:
		dk.rep_t = 0.0
		return
	dk.rep_t += dt * (0.25 + 0.75 * sh.mod_health("hangar"))
	if dk.rep_t < REPLACE_T:
		return
	# a free spot in the parked rows (the plane rises into it on the elevator), or a new row
	_deck_compact(dk)
	var row = null
	var col := -1
	for r in range(dk.rows.size() - 1, -1, -1):
		for c in dk.fill_order:
			if dk.rows[r].cells[c] == null:
				row = dk.rows[r]; col = c
				break
		if row != null:
			break
	if row == null:
		var x: float
		if dk.rows.is_empty():
			x = dk.x_stern if dk.mode == "aft" else dk.x_bow
		elif dk.mode == "aft":
			x = dk.rows[0].x + DECK_ROW
			if x > dk.x_end - 90.0:
				return
		else:
			x = dk.rows[dk.rows.size() - 1].x - DECK_ROW
			if x < dk.x_touch + 50.0:
				return
		row = {"x": x, "tx": x, "cells": []}
		row.cells.resize(dk.nc)
		if dk.mode == "aft" and not dk.rows.is_empty():
			dk.rows.push_front(row)
		else:
			dk.rows.append(row)
		col = dk.fill_order[0]
	dk.rep_t = 0.0
	_deck_add_plane(dk, need, row, col, true)
	need.n += 1
	if need.state == "lost":
		need.state = "ready"
		need.rearm = 60.0
	if sh.is_player and need.n >= need.n0:
		B.say("%s back to full strength: %d planes, replacements up from the hangar." % [need.name, need.n], "good")


## One deck plane's motion; true when it has left the deck (airborne).
func _deck_step_plane(dk: Dictionary, p: Dictionary, dt: float, k: float) -> bool:
	var sh: Ship = dk.ship
	p.t += dt
	match p.phase:
		"parked":
			return false
		"lift":
			# coming up on the elevator
			p.ly = minf(dk.y, p.ly + 2.0 * dt)
			p.lx = p.row.x
			if p.ly >= dk.y:
				p.phase = "parked"
		"taxi_out", "taxi_in":
			if p.path.is_empty():
				if p.phase == "taxi_out":
					p.phase = "hold"
					p.t = 0.0
				else:
					p.phase = "parked"
					p.lx = p.row.x
					p.lz = dk.cols[p.col]
					p.psi = 0.0
			else:
				var goal: Vector2 = p.path[0]
				if p.phase == "taxi_out":
					# stop short while another plane is still on the launch spot
					var blocked := false
					for o in dk.planes:
						if o != p and o.phase == "hold" and Vector2(o.lx - p.lx, o.lz - p.lz).length() < 12.0:
							blocked = true
					if blocked:
						_deck_place(dk, p)
						return false
				var dv := goal - Vector2(p.lx, p.lz)
				var st: float = (TAXI_OUT_V if p.phase == "taxi_out" else TAXI_V) * k * dt
				if dv.length() <= st:
					p.lx = goal.x; p.lz = goal.y
					p.path.pop_front()
				else:
					var u := dv.normalized()
					p.lx += u.x * st; p.lz += u.y * st
					p.psi = lerp_angle(p.psi, atan2(u.y, u.x), minf(1.0, dt * 4.0))
		"hold":
			# on the centreline: turn into the wind, wait for the plane ahead, spread the wings
			p.psi = lerp_angle(p.psi, 0.0, minf(1.0, dt * 6.0))
			var clear := true
			for o in dk.planes:
				if o != p and o.phase == "roll" and o.lx < p.lx + 25.0:
					clear = false
			if clear and absf(p.psi) < 0.08 and p.t > 0.3:
				_deck_node(dk, p, false)
				p.phase = "roll"
				p.psi = 0.0
				p.v = 3.0
				var run := maxf(30.0, dk.x_end - p.lx)
				p.acc = (ROLL_V * ROLL_V - 9.0) / (2.0 * run)
		"roll":
			p.v = minf(p.v + p.acc * k * dt, ROLL_V + 4.0)
			p.lx += p.v * dt
			p.lz = lerpf(p.lz, 0.0, minf(1.0, dt * 3.0))
			p.ly = dk.y + maxf(0.0, p.lx - (dk.x_end - 25.0)) * 0.06
			if p.lx >= dk.x_end - 2.0:
				# off the bow: from here the plane flies in the world
				var sq: Dictionary = p.sq
				_deck_place(dk, p)
				var gp: Vector3 = p.node.global_position
				p.node.reparent(self, true)
				var so := {"node": p.node, "phase": "climb", "t": 0.0, "lx": 0.0, "ly": 0.0, "lz": 0.0,
					"v": sh.v + p.v, "x": gp.x, "z": gp.z, "y": gp.y, "h": sh.h}
				sq.solos.append(so)
				p.node = null
				return true
		"rollout":
			# the hook catches a wire: a hard stop, then the wings fold
			p.v = maxf(0.0, p.v - 9.0 * dt)
			p.lx += p.v * dt
			if p.v <= 2.5:
				_deck_node(dk, p, true)
				p.phase = "taxi_in"
				p.path = [Vector2(p.row.x - 2.0, 0.0), Vector2(p.row.x, dk.cols[p.col])]
	_deck_place(dk, p)
	return false
