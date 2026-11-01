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

const ALT_CRUISE := 170.0
const ALT_LOW := 35.0


func reset() -> void:
	for sq in sqs:
		if sq.node != null and is_instance_valid(sq.node):
			sq.node.queue_free()
	sqs.clear()
	_id = 0
	_ai_t = 0.0
	_enemy_air_msg_t = -99.0
	_scout_msg_t = -99.0


## Give a carrier (or a ship with floatplanes) its air group, all on deck and ready.
func setup_ship(s: Ship) -> void:
	var T: Dictionary = s.T
	if T.has("aircraft"):
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
		"launch_left": 0, "aloft_t": 0.0, "attacked": false, "rearm": 0.0, "hits": 0, "name": "%s squadron %d" % [A.name, _id], "orbit": 0.0, "aim_update_t": -99.0, "warned": false}
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
	sq.x = home.x; sq.z = home.z; sq.h = home.h; sq.alt = 2.0
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
			# planes take off one by one down the deck; the squadron forms up ahead of the ship
			if not home.alive:
				_lose(sq); return
			sq.timer += dt * (0.5 + 0.5 * home.mod_health("deck"))
			var per := 6.0 if home.T.has("aircraft") else 20.0
			if sq.timer > per:
				sq.timer = 0.0
				sq.launch_left -= 1
			sq.x = home.x; sq.z = home.z; sq.h = home.h
			sq.v = home.v
			sq.alt = 6.0
			if sq.launch_left <= 0:
				sq.state = sq.next
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
			sq.x = home.x; sq.z = home.z; sq.h = home.h; sq.v = home.v
			sq.alt = 8.0
			sq.timer += dt * (0.3 + 0.7 * home.mod_health("deck")) if home.T.has("aircraft") else dt * 0.5
			if sq.timer > 6.0 * sq.n:
				sq.state = "ready"
				sq.rearm = 240.0 if home.T.has("aircraft") else 400.0
				if sq.node:
					sq.node.queue_free(); sq.node = null
				if home.is_player:
					B.say("%s recovered: %d of %d planes back aboard." % [sq.name, sq.n, sq.n0], "good")
				return
			_place_node(sq)
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
	for i in sq.n:
		var lx := randf_range(-tgt.T.L * 0.45, tgt.T.L * 0.45)
		var lz := randf_range(-tgt.T.B * 0.4, tgt.T.B * 0.4)
		var w := tgt.to_world_xz(lx, lz)
		if randf() < p:
			hits += 1
			B.fx.boom(w.x, 8.0, w.y, false)
			B.sfx.play("bomb", Vector2(w.x, w.y), B.cam.position, 0.8)
			B.after(0.1 * i, func(): B.damage(tgt, lx, lz, bomb, "bomb", sq.home))
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
		B.torps.append({"x": ox, "z": oz, "h": a, "v": spd, "left": TT.range, "team": sq.team, "owner": sq.home, "dud": randf() < TT.dud, "warned": false, "depth": 3.0})
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
	n.position = Vector3(sq.x, sq.alt, sq.z)
	var bank := clampf(U.ang_d(sq.h, sq.get("prev_h", sq.h)) * 8.0, -0.6, 0.6)
	sq.prev_h = sq.h
	n.transform.basis = Basis(Vector3.UP, -sq.h) * Basis(Vector3.BACK, bank)
	n.visible = sq.state != "ready" and sq.state != "lost"


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
		if sq.state not in ["ready", "lost"]:
			_make_node(sq)
			_place_node(sq)
