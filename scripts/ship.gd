class_name Ship
extends Node3D
## One ship: its state (speed, damage, crew, flooding, guns) and its 3D model.
## The battle simulation (battle.gd) moves and damages ships; this script keeps
## the model in step with the state every frame.

var type_id := ""
var T: Dictionary            # class data from Data.TYPES
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
	for m in T.mounts:
		mounts.append({"g": m.g, "x": m.x, "stow": m.stow, "arc": m.arc, "ang": m.stow, "reload": randf_range(0.0, 2.0), "hp": 3.0, "recoil": 0.0, "node": null})
	for t in T.torps:
		torps.append({"g": t.g, "x": t.x, "n": t.n, "ang": 0.0, "left": t.n, "hp": 2.0, "reload_t": 0.0, "node": null})
	for i in T.aa.size():
		aa_ang.append(0.0)
	for md in T.modules:
		modules.append({"label": md[0], "kind": md[1], "x": md[2], "hp": md[3], "max": md[3], "ref": null})
	for m in mounts:
		modules.append({"label": m.g, "kind": "mount", "x": m.x, "hp": 3.0, "max": 3.0, "ref": m})
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
	return 0.35 + 0.65 * clampf(float(crew) / float(T.crew), 0.0, 1.0)

func mod_health(kind: String) -> float:
	var hp := 0.0
	var mx := 0.0
	for m in modules:
		if m.kind == kind:
			hp += m.hp
			mx += m.max
	return hp / mx if mx > 0.0 else 0.0

func max_kn() -> float:
	var eng := mod_health("engine")
	var fl := clampf(flood / (T.displacement * 0.36), 0.0, 1.0)
	return T.max_kn * (0.15 + 0.85 * eng) * (1.0 - 0.65 * fl)

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
	var d := absf(rad_to_deg(rb))
	return d <= 150.0 if m.arc == "fwd" else d >= 30.0

func tof_for(R: float) -> float:
	var g: Dictionary = T.gun
	return R / (g.vel * (0.85 - 0.45 * clampf(R / g.range_max, 0.0, 1.0)))

func contact(o: Ship) -> bool:
	return vis.get(o.ship_name, false) or radar.get(o.ship_name, false)


# ---------- visuals ----------

func update_visual(t: float) -> void:
	# gentle swell, plus list, trim and settling from flooding
	var bob := sin(t * 0.7 + bob_phase) * 0.25
	var swell_roll := sin(t * 0.55 + bob_phase) * deg_to_rad(1.2)
	position = Vector3(x, -sink + bob, z)
	var b := Basis(Vector3.UP, -h) * Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.BACK, -(roll + swell_roll))
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
