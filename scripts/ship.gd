class_name Ship
extends Node3D
## One ship: its state (speed, damage, crew, flooding, guns) and its 3D model.
## The battle simulation (battle.gd) moves and damages ships; this script keeps
## the model in step with the state every frame.

var type_id := ""
var T: Dictionary            # class data from Data.TYPES
var gun: Dictionary          # main battery gun (Data.GUNS)
var objective := false       # a mission objective (sink, capture or drive off)
var escaped := false
var route_h := 0.0           # course the AI steers when it has nothing else to do
var station := Vector2.ZERO  # formation station behind the player (lx, lz)
var torp_run := false
var dest_dist := 0.0         # distance left to the AI ship's destination
var team := "us"             # "us" or "ijn"
var ship_name := ""
var is_player := false

# motion
var x := 0.0
var z := 0.0
var h := 0.0                 # heading, radians clockwise from north
var v := 0.0                 # speed, m/s
var tele := 4                # engine telegraph index into Data.TELE
var rud := 0.0               # rudder angle now (degrees, + = right)
var rud_cmd := 0.0           # rudder ordered
var rud_jam_until := -1.0

# condition
var roll := 0.0
var pitch := 0.0
var sink := 0.0
var sinking := 0.0
var alive := true
var gone := false
var mag_blown := false
var crew := 0
var flood := 0.0
var flood_side := 0.0
var flood_fwd := 0.0
var holes: Array = []        # {lx, side, rate, fix}
var fires: Array = []        # {lx, lz, int}
var crew_figs: Array = []    # the visible crew (scripts/crew.gd)
var order := ""              # player's order to a friendly ship: "", follow, engage, fallback, rescue, attack
var order_target: Ship = null
var modules: Array = []      # {label, kind, x, hp, max, ref}
var mounts: Array = []       # {g, x, stow, arc, ang, reload, hp, recoil, node}
var torps: Array = []        # {g, x, n, ang, left, hp, reload_t, node}
var aa_ang: Array = []
var dir_ang := 0.0
var illum := 0.0             # seconds left lit by an enemy star shell

# fire control
var target: Ship = null
var q := 0.0                 # quality of the fire-control solution, 0..0.95
var q_target: Ship = null
var fire := false
var salvo_busy := false
var last_fired := -99.0
var vis := {}                # ship name -> can see visually
var radar := {}              # ship name -> radar contact
var smoke_on := false
var smoke_acc := 0.0
var star_cd := 15.0
var torp_cd := 10.0
var ai_turn := 0.0
var ai_state := "search"
var side := 1.0              # which way the AI swings when attacking
var spotted_once := false
var bat_last := {}           # gun calibre -> time last fired
var bat_busy := {}
var weave_t := 10.0
var evade_until := -1.0

# fleet and tactics (see ai.gd)
var group := ""              # fleet this ship sails with ("" = on her own)
var leader_flag := false     # named leader of the group in the mission setup
var fstation := Vector2.ZERO # station on the leader (lx, lz)
var detached := false        # left the formation (damaged)
var escort_group := ""       # set when this ship screens a convoy
var protect := false         # a friendly ship the mission is about (convoy escort)
var rescued := false         # survivors picked up (rafts)
var aground := false
var last_hit_by: Ship = null
var tactic := ""             # current solo tactic
var tactic_until := 0.0
var zig := 0.0
var zig_t := 0.0
var ai_note := ""

# submarines and anti-submarine war
var depth := 0               # 0 surfaced, 1 periscope depth, 2 deep
var depth_m := 0.0           # metres below the surface now (visual and for depth charges)
var battery := 1.0           # submerged power left, 0..1
var sonar_contacts := {}     # ship name -> {x, z, t, depth} last sonar fix (shared by the team)
var dc_left := 0             # depth charges left
var dc_cd := 0.0             # seconds until the next pattern can be dropped
var hh_cd := 0.0             # hedgehog reload
var asw_state := ""          # for the HUD / trace

# visuals
var model: Node3D
var parts := {}              # group name -> Node3D
var bob_phase := 0.0
var _dead_mat: StandardMaterial3D


func setup(p_type: String, p_team: String, p_name: String, px: float, pz: float, ph: float, kn: float, scheme: String) -> void:
	type_id = p_type
	T = Data.TYPES[p_type]
	team = p_team
	ship_name = p_name
	name = p_name.replace(" ", "_").replace("'", "")
	x = px; z = pz; h = ph
	v = kn * Data.KN
	crew = T.crew
	bob_phase = randf() * TAU
	tele = 4
	gun = Data.GUNS[T.gun]
	for m in T.mounts:
		var g: Dictionary = Data.GUNS[m.get("gun", T.gun)]
		var hp := 3.0 if g.dmg >= 0.5 else 1.5
		mounts.append({"g": m.g, "x": m.x, "stow": m.stow, "arc": Data.ARCS[m.arc], "ang": m.stow, "reload": randf_range(0.0, 2.0), "hp": hp, "recoil": 0.0, "node": null, "gun": g, "on": false, "bears": false})
	for t in T.torps:
		torps.append({"g": t.g, "x": t.x, "n": t.n, "ang": 0.0, "left": t.n, "hp": 2.0, "reload_t": 0.0, "node": null, "fixed": t.get("fixed", false), "aft": t.get("aft", false)})
	for i in T.aa.size():
		aa_ang.append(0.0)
	for md in T.modules:
		modules.append({"label": md[0], "kind": md[1], "x": md[2], "hp": md[3], "max": md[3], "ref": null})
	dc_left = int(T.get("depth_charges", 0))
	for m in mounts:
		modules.append({"label": m.g, "kind": "mount", "x": m.x, "hp": m.hp, "max": m.hp, "ref": m})
	for t in torps:
		modules.append({"label": t.g, "kind": "torp", "x": t.x, "hp": 2.0, "max": 2.0, "ref": t})
	load_model(scheme)


func load_model(scheme: String) -> void:
	if model:
		model.queue_free()
	var scene: PackedScene = load(T.models[scheme])
	model = scene.instantiate()
	add_child(model)
	parts.clear()
	_collect_parts(model)
	for m in mounts:
		m.node = parts.get(m.g)
		# where the mount stands on the model: its athwartships offset and the deck under it
		if m.node != null:
			var rel: Transform3D = model.global_transform.affine_inverse() * m.node.global_transform
			m.lz = rel.origin.x
			var bottom := 1e9
			if m.node is MeshInstance3D and m.node.mesh:
				bottom = m.node.mesh.get_aabb().position.y
			for c in m.node.get_children():
				if c is MeshInstance3D and c.mesh:
					bottom = minf(bottom, (c.transform * c.mesh.get_aabb()).position.y)
			if bottom < 1e8:
				m.deck_y = rel.origin.y + bottom
	for t in torps:
		t.node = parts.get(t.g)
	_dead_mat = StandardMaterial3D.new()
	_dead_mat.albedo_color = Color(0.05, 0.05, 0.05, 0.6)
	_dead_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dead_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _collect_parts(n: Node) -> void:
	for c in n.get_children():
		if c is Node3D:
			parts[String(c.name)] = c
		_collect_parts(c)


# ---------- ratings ----------

## Crew efficiency: fewer sailors means slower loading, aiming and repairs.
func eff() -> float:
	var e := 0.35 + 0.65 * clampf(float(crew) / float(T.crew), 0.0, 1.0)
	if is_player:
		e *= Career.crew_factor()
	return e

func mod_health(kind: String) -> float:
	var hp := 0.0
	var mx := 0.0
	for m in modules:
		if m.kind == kind:
			hp += m.hp
			mx += m.max
	return hp / mx if mx > 0.0 else 1.0   # no such module: counts as intact

func max_kn() -> float:
	var eng := mod_health("engine")
	var fl := clampf(flood / (T.displacement * 0.36), 0.0, 1.0)
	var top: float = T.max_kn
	if is_sub() and depth > 0:
		top = T.get("dive_kn", 8.0) * (0.3 + 0.7 * clampf(battery * 4.0, 0.0, 1.0))
	return top * (0.15 + 0.85 * eng) * (1.0 - 0.65 * fl)

func is_sub() -> bool:
	return T.get("sub", false)

func submerged() -> bool:
	return is_sub() and depth > 0

## Sonar range of this ship's set (0 = none). Destroyers and escorts carry one.
func sonar_range() -> float:
	if T.has("sonar"):
		return T.sonar
	return 1800.0 if cls() in ["dd", "de"] else 0.0

func flood_cap() -> float:
	return T.displacement * 0.36


# ---------- geometry ----------

## World point -> ship coordinates (lx forward, lz to starboard).
func to_local_xz(wx: float, wz: float) -> Vector2:
	var dx := wx - x
	var dz := wz - z
	var f := U.fwd(h)
	return Vector2(dx * f.x + dz * f.y, dx * cos(h) + dz * sin(h))

## Ship coordinates -> world point (x, z).
func to_world_xz(lx: float, lz: float) -> Vector2:
	var f := U.fwd(h)
	return Vector2(x + f.x * lx + cos(h) * lz, z + f.y * lx + sin(h) * lz)

func half_width_at(lx: float) -> float:
	var L: float = T.L / 2.0
	var b: float = T.B / 2.0
	if absf(lx) > L:
		return 0.0
	var t := absf(lx) / L
	if lx > 0.0:
		return b * sqrt(maxf(0.0, 1.0 - pow(t, 2.4)))
	return b * (1.0 - 0.3 * pow(t, 3.0))

func inside_hull(wx: float, wz: float, pad := 0.0) -> bool:
	var l := to_local_xz(wx, wz)
	return absf(l.y) <= half_width_at(l.x) + pad and absf(l.x) <= T.L / 2.0 + pad

func range_to(o) -> float:
	return U.hyp(o.x - x, o.z - z)

func bearing_to(tx: float, tz: float) -> float:
	return U.bearing(x, z, tx, tz)

func rel_bearing(tx: float, tz: float) -> float:
	return U.ang_d(h, bearing_to(tx, tz))

static func mount_can_bear(m: Dictionary, rb: float) -> bool:
	return absf(U.ang_d(deg_to_rad(m.arc[0]), rb)) <= deg_to_rad(m.arc[1])

## Nearest bearing inside the mount's arc (where it waits when the target is outside it).
static func arc_clamp(m: Dictionary, rb: float) -> float:
	var c := deg_to_rad(m.arc[0])
	var hw := deg_to_rad(m.arc[1])
	var d := U.ang_d(c, rb)
	return c + clampf(d, -hw, hw)

func tof_for(R: float, g = null) -> float:
	if g == null:
		g = gun
	return R / (g.vel * (0.85 - 0.45 * clampf(R / g.range_max, 0.0, 1.0)))

func max_range() -> float:
	var r := 0.0
	for m in mounts:
		if m.hp > 0.0:
			r = maxf(r, m.gun.range_max)
	return r

## Longest range of the guns that are not the main battery (secondaries), 0 if none.
func secondary_range() -> float:
	var r := 0.0
	for m in mounts:
		if m.hp > 0.0 and m.gun != gun and m.gun.dmg >= 0.5:
			r = maxf(r, m.gun.range_max)
	return r

## Reach of the light AA (Bofors, Oerlikons, machine guns), 0 if none.
func aa_range() -> float:
	var r := 0.0
	for m in mounts:
		if m.hp > 0.0 and m.gun.dmg < 0.5:
			r = maxf(r, m.gun.range_max)
	return r

## Torpedo speed in m/s as used in battle.
func torp_speed() -> float:
	return T.torp.speed_kn * Data.KN * Data.TORP_SPEED

## Torpedoes still ready in working tubes.
func torps_left() -> int:
	var n := 0
	for tp in torps:
		if tp.hp > 0.0:
			n += tp.left
	return n

## Where a torpedo fired now from (fx, fz) along a straight run meets the target: [point, run time].
func torp_intercept(tgt, fx: float, fz: float) -> Array:
	var spd := torp_speed()
	var f := U.fwd(tgt.h)
	var tt: float = U.hyp(tgt.x - fx, tgt.z - fz) / spd
	for i in 6:
		tt = U.hyp(tgt.x + f.x * tgt.v * tt - fx, tgt.z + f.y * tgt.v * tt - fz) / spd
	return [Vector2(tgt.x + f.x * tgt.v * tt, tgt.z + f.y * tgt.v * tt), tt]

## Which torpedo mounts can fire along compass bearing brg right now.
## PT boat racks fire ahead but the Mark 13's gyro can be angled up to 30 degrees off the bow.
func torp_mounts_for(brg: float) -> Array:
	var rb := U.ang_d(h, brg)
	var out := []
	for i in torps.size():
		var m: Dictionary = torps[i]
		if m.hp <= 0.0 or m.left <= 0:
			continue
		if m.fixed:
			# bow (or stern) tubes fire ahead (astern) with a little gyro angle
			var rel: float = absf(rb) if not m.get("aft", false) else PI - absf(rb)
			if rel <= deg_to_rad(30.0):
				out.append(i)
		elif absf(rb) >= deg_to_rad(30.0) and absf(rb) <= deg_to_rad(150.0):
			out.append(i)
	return out

func role() -> String:
	return T.get("role", "warship")

## Anti-aircraft strength: light automatic guns count most, dual-purpose guns a little.
func aa_power() -> float:
	var pwr := 0.0
	for m in mounts:
		if m.hp <= 0.0:
			continue
		var g: Dictionary = m.gun
		if g.dmg < 0.5:
			pwr += g.per_mount * g.dmg / g.reload * 4.0
		elif g.cal.begins_with("5-inch") or g.cal.begins_with("12.7") or g.cal.begins_with("10 cm") or g.cal.begins_with("3-inch"):
			pwr += g.per_mount * 0.25
	pwr += 0.15 * T.aa.size()
	return pwr * eff()

## Armour: how much shell a hit must carry to do real damage (0 = unarmoured, 1 = 8-inch belt, 3+ = battleship).
func armor() -> float:
	if T.has("armor"):
		return T.armor
	return {"ca": 0.5, "cl": 0.3, "cv": 0.4, "bb": 1.0, "cvl": 0.3}.get(cls(), 0.0)

## Ship class for fleet roles: pt, dd, de, cl, ca, bb, cv, cve, ss, merchant, barge.
func cls() -> String:
	return T.get("cls", "dd")

## How the AI fights this ship: "usn" or "ijn_dd" (Japanese destroyer doctrine).
func doctrine() -> String:
	return T.get("doctrine", "usn")

func contact(o: Ship) -> bool:
	return vis.get(o.ship_name, false) or radar.get(o.ship_name, false)


# ---------- visuals ----------

func update_visual(t: float) -> void:
	# gentle swell, plus list, trim and settling from flooding
	var bob := sin(t * 0.7 + bob_phase) * 0.25
	var swell_roll := sin(t * 0.55 + bob_phase) * deg_to_rad(1.2)
	if is_sub():
		bob *= 0.3
	if T.get("ground", false):
		# shore targets sit on the island
		var gy: float = Battle.I.terrain.height_at(x, z) if Battle.I and Battle.I.terrain else 0.0
		position = Vector3(x, gy, z)
		transform.basis = Basis(Vector3.UP, -h)
		visible = not gone
		return
	position = Vector3(x, -sink + bob - depth_m, z)
	var trim := 0.0
	if T.get("role", "") == "pt" and alive:
		trim = deg_to_rad(4.5) * clampf(v / (35.0 * Data.KN), 0.0, 1.0)
	var b := Basis(Vector3.UP, -h) * Basis(Vector3.RIGHT, -(pitch - trim)) * Basis(Vector3.BACK, -(roll + swell_roll))
	transform.basis = b
	visible = not gone
	# guns, tubes, director and light AA turn on their pivots
	for m in mounts:
		var n = m.node
		if n == null:
			continue
		var a: float = (m.ang - m.stow) if m.hp > 0.0 else 0.5
		n.rotation.y = -a
		n.material_overlay = _dead_mat if m.hp <= 0.0 else null
	for tp in torps:
		var n2 = tp.node
		if n2 == null:
			continue
		n2.rotation.y = -tp.ang * 0.6
		n2.material_overlay = _dead_mat if tp.hp <= 0.0 else null
	var d: Node3D = parts.get("Director")
	if d:
		d.rotation.y = -dir_ang
	for i in T.aa.size():
		var an: Node3D = parts.get(T.aa[i])
		if an:
			an.rotation.y = -aa_ang[i]


# ---------- save and load ----------

const SAVE_FIELDS := ["type_id", "team", "ship_name", "is_player", "objective", "escaped", "route_h", "dest_dist", "side",
	"group", "leader_flag", "detached", "escort_group", "tactic", "tactic_until", "zig", "zig_t",
	"x", "z", "h", "v", "tele", "rud", "rud_cmd", "rud_jam_until", "roll", "pitch", "sink", "sinking", "alive", "gone", "mag_blown",
	"crew", "flood", "flood_side", "flood_fwd", "dir_ang", "illum", "q", "fire", "smoke_on", "star_cd", "torp_cd",
	"ai_state", "evade_until", "spotted_once", "weave_t", "last_fired", "protect", "rescued", "aground", "depth", "depth_m", "battery", "dc_left", "dc_cd", "hh_cd", "asw_state"]


## Everything about this ship as plain data (ship references become indices in battle.gd).
func save() -> Dictionary:
	var d := {}
	for f in SAVE_FIELDS:
		d[f] = get(f)
	d.station = [station.x, station.y]
	d.fstation = [fstation.x, fstation.y]
	d.holes = holes.duplicate(true)
	var fl := []
	for f in fires:
		fl.append({"lx": f.lx, "lz": f.lz, "int": f.int})
	d.fires = fl
	var mods := []
	for m in modules:
		mods.append(m.hp)
	d.modules = mods
	var mts := []
	for m in mounts:
		mts.append({"ang": m.ang, "reload": m.reload, "hp": m.hp})
	d.mounts = mts
	var tps := []
	for tp in torps:
		tps.append({"ang": tp.ang, "left": tp.left, "hp": tp.hp, "reload_t": tp.reload_t})
	d.torps = tps
	return d


func restore(d: Dictionary) -> void:
	for f in SAVE_FIELDS:
		if d.has(f):
			var cur = get(f)
			var val = d[f]
			if cur is int:
				val = int(val)
			set(f, val)
	station = Vector2(d.station[0], d.station[1])
	fstation = Vector2(d.fstation[0], d.fstation[1])
	holes = d.holes.duplicate(true)
	fires = []
	for f in d.fires:
		fires.append({"lx": f.lx, "lz": f.lz, "int": f.int})
	for i in mini(modules.size(), d.modules.size()):
		modules[i].hp = d.modules[i]
	for i in mini(mounts.size(), d.mounts.size()):
		mounts[i].ang = d.mounts[i].ang
		mounts[i].reload = d.mounts[i].reload
		mounts[i].hp = d.mounts[i].hp
	for i in mini(torps.size(), d.torps.size()):
		torps[i].ang = d.torps[i].ang
		torps[i].left = int(d.torps[i].left)
		torps[i].hp = d.torps[i].hp
		torps[i].reload_t = d.torps[i].reload_t
	for m in modules:
		if m.ref != null:
			m.ref.hp = m.hp
