class_name Crew
extends Node3D
## The ship is alive: a representative crew of small figures on every deck. Cruising, they
## stroll and work about the deck; at general quarters they run to the open gun mounts and
## the rails, repair parties fight fires, and when the ship goes down they go to the side
## and over. Drawn with two MultiMeshes (bodies and caps) so hundreds cost nothing.
##
## Positions are ship-local (lx forward, lz starboard, y up from the waterline); the deck
## height comes from the gun mounts' bases on the model, which is where the crew stands.

var B                                  # the Battle
var bodies: MultiMeshInstance3D
var caps: MultiMeshInstance3D
var _dbg_done := false
const MAX_FIGS := 1400
const WALK := 1.4                      # m/s strolling
const RUN := 3.2                       # m/s to battle stations

const US_BODY := Color(0.16, 0.22, 0.38)      # dungarees
const US_CAP := Color(0.95, 0.95, 0.9)        # white hat
const IJN_BODY := Color(0.82, 0.8, 0.72)      # whites / khaki
const IJN_CAP := Color(0.9, 0.9, 0.85)
const MERCHANT_BODY := Color(0.35, 0.3, 0.26)


func _ready() -> void:
	bodies = _layer(_body_mesh())
	caps = _layer(_cap_mesh())


func _layer(mesh: Mesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = MAX_FIGS
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mi.material_override = mat
	add_child(mi)
	return mi


## A sailor as a short tapered column (legs, torso, shoulders), about 1.7 m tall.
func _body_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := [[0.0, 0.22], [0.85, 0.28], [1.45, 0.36], [1.55, 0.16]]
	var n := 6
	for r in rings.size() - 1:
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var y0: float = rings[r][0]; var r0: float = rings[r][1]
			var y1: float = rings[r + 1][0]; var r1: float = rings[r + 1][1]
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			for v in [p00, p10, p01, p01, p10, p11]:
				st.set_color(Color.WHITE)
				st.set_normal((v - Vector3(0, v.y, 0)).normalized())
				st.add_vertex(v)
	return st.commit()


## Head and cap: a small sphere-ish lump on top.
func _cap_mesh() -> Mesh:
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.36
	sm.radial_segments = 6
	sm.rings = 3
	var st := SurfaceTool.new()
	st.append_from(sm, 0, Transform3D(Basis(), Vector3(0, 1.68, 0)))
	return st.commit()


# ---------------------------------------------------------------- per ship

## Make the crew for a ship once its model is loaded.
func setup_ship(s: Ship) -> void:
	var T: Dictionary = s.T
	if T.get("ground", false) or T.get("cls", "") == "raft":
		return
	var n: int = clampi(int(float(T.get("crew", 100)) / 24.0), 4, 36)
	if T.get("cls", "") in ["cv", "cvl", "cve"]:
		n = 40          # the flight deck is where the people are
	if T.get("cls", "") in ["barge", "pt"]:
		n = clampi(int(float(T.get("crew", 14)) / 4.0), 3, 8)
	s.crew_figs = []
	for i in n:
		var p := _random_deck_point(s)
		s.crew_figs.append({"lx": p.x, "lz": p.y, "tx": p.x, "tz": p.y, "state": "idle", "wait": randf_range(0.0, 6.0), "phase": randf() * TAU, "station": null, "gq": false, "gone": false})


func _deck_y(s: Ship, lx: float) -> float:
	# the base of the nearest gun mount on the model is the deck there
	var best := 1e9
	var y: float = s.T.get("deck_y", 1.5 if s.T.L < 40.0 else (4.5 if s.T.L < 140.0 else 7.0))
	for m in s.mounts:
		if m.has("deck_y"):
			var d: float = absf(m.x - lx)
			if d < best:
				best = d
				y = m.deck_y
	return y


func _random_deck_point(s: Ship) -> Vector2:
	var L: float = s.T.L
	var Bm: float = s.T.B
	return Vector2(randf_range(-L * 0.42, L * 0.42), randf_range(-Bm * 0.36, Bm * 0.36))


## Battle stations: open gun mounts (light AA and single/twin secondaries), then the rails.
func _stations(s: Ship) -> Array:
	var out := []
	for m in s.mounts:
		if m.hp <= 0.0:
			continue
		var g: Dictionary = m.gun
		var enclosed: bool = g.dmg >= 1.5 or (g.dmg >= 0.9 and s.T.L > 140.0)   # turrets and big twin mounts
		if enclosed:
			continue
		var crew_n := 2 if g.dmg < 0.5 else 4
		var back: float = 1.6 if g.dmg < 0.5 else 3.0
		for k in crew_n:
			var side := (k % 2) * 2 - 1
			out.append({"lx": m.x - back - 0.8 * int(k / 2), "lz": m.get("lz", 0.0) + side * (0.8 + 0.5 * int(k / 2)), "kind": "gun", "mount": m})
	return out


func _fire_stations(s: Ship) -> Array:
	var out := []
	for f in s.fires:
		for k in 3:
			var a := TAU * k / 3.0 + 0.4
			out.append({"lx": f.lx + cos(a) * 4.0, "lz": clampf(f.lz + sin(a) * 3.0, -s.T.B * 0.4, s.T.B * 0.4), "kind": "fire"})
	return out


func step(dt: float) -> void:
	for s in B.ships:
		if s.crew_figs.is_empty() or s.gone:
			continue
		_step_ship(s, dt)


func _step_ship(s: Ship, dt: float) -> void:
	var T: Dictionary = s.T
	var L: float = T.L
	var Bm: float = T.B
	var gq: bool = B.combat_t >= 0.0 or s.target != null or not s.fires.is_empty()
	var sinking: bool = not s.alive and s.sinking > 0.0
	var alive_frac: float = clampf(float(s.crew) / maxf(1.0, float(T.get("crew", 100))), 0.0, 1.0)
	var n_alive: int = int(ceil(s.crew_figs.size() * alive_frac))
	# stations are handed out once when the ship goes to quarters or a fire breaks out
	var changed: bool = s.get_meta("crew_gq", false) != gq or s.get_meta("crew_fires", -1) != s.fires.size() or s.get_meta("crew_sunk", false) != sinking
	if changed:
		s.set_meta("crew_gq", gq); s.set_meta("crew_fires", s.fires.size()); s.set_meta("crew_sunk", sinking)
		var stations: Array = _fire_stations(s) + (_stations(s) if gq else [])
		var i := 0
		for f in s.crew_figs:
			f.station = null
			if sinking:
				# to the rail nearest you, then over the side
				f.station = {"lx": clampf(f.lx, -L * 0.4, L * 0.4), "lz": (Bm * 0.5 + 0.6) * (1.0 if f.lz >= 0.0 else -1.0), "kind": "rail"}
				f.state = "run"
			elif i < stations.size():
				f.station = stations[i]
				f.state = "run"
				i += 1
			elif gq:
				# the rest man the rails as lookouts and ammunition passers
				var side := 1.0 if randf() < 0.5 else -1.0
				f.station = {"lx": randf_range(-L * 0.4, L * 0.4), "lz": side * Bm * 0.42, "kind": "rail"}
				f.state = "run"
			else:
				f.state = "idle"
				f.wait = randf_range(0.0, 3.0)
			if f.station != null:
				f.tx = f.station.lx; f.tz = f.station.lz
	for k in s.crew_figs.size():
		var f: Dictionary = s.crew_figs[k]
		f.gone = k >= n_alive
		if f.gone:
			continue
		f.phase += dt * 6.0
		match f.state:
			"idle":
				f.wait -= dt
				if f.wait <= 0.0:
					var p := _random_deck_point(s)
					f.tx = p.x; f.tz = p.y
					f.state = "walk"
			"walk":
				if _move(f, WALK * dt):
					f.state = "idle"
					f.wait = randf_range(2.0, 9.0)
			"run":
				if _move(f, RUN * dt):
					f.state = "post"
					if sinking:
						f.state = "jump"
						f.wait = randf_range(0.0, 4.0)
			"post":
				# small shuffle at the station
				f.lx = f.tx + sin(f.phase * 0.3) * 0.15
			"jump":
				f.wait -= dt
				if f.wait <= 0.0:
					f.gone = true
					if B.fx and randf() < 0.7:
						var wp := s.to_world_xz(f.lx, f.lz)
						B.fx.splash(wp.x, wp.y, false)
	s.crew_figs = s.crew_figs.filter(func(f): return not (f.gone and f.state == "jump"))


func _move(f: Dictionary, step: float) -> bool:
	var dx: float = f.tx - f.lx
	var dz: float = f.tz - f.lz
	var d := sqrt(dx * dx + dz * dz)
	if d <= step:
		f.lx = f.tx; f.lz = f.tz
		return true
	f.lx += dx / d * step
	f.lz += dz / d * step
	return false


# ---------------------------------------------------------------- drawing

func render(cam_pos: Vector3) -> void:
	var mmb: MultiMesh = bodies.multimesh
	var mmc: MultiMesh = caps.multimesh
	var c := 0
	for s in B.ships:
		if not s.visible or s.crew_figs.is_empty() or s.model == null:
			continue
		# too far to see people: skip the ship entirely
		var d: float = Vector2(s.x - cam_pos.x, s.z - cam_pos.z).length() + cam_pos.y
		if d > 2600.0:
			continue
		var body_col: Color = US_BODY if s.team == "us" else IJN_BODY
		if s.T.get("cls", "") == "merchant":
			body_col = MERCHANT_BODY
		var cap_col: Color = US_CAP if s.team == "us" else IJN_CAP   # white hats read from above; helmets vanish against the deck
		var xf: Transform3D = s.model.global_transform
		for f in s.crew_figs:
			if f.gone or c >= MAX_FIGS:
				continue
			var y := _deck_y(s, f.lx)
			var bobbing := 0.0
			if f.state in ["walk", "run"]:
				bobbing = absf(sin(f.phase * (1.0 if f.state == "walk" else 1.6))) * 0.06
			# model space: forward is -z, starboard is +x
			var local := Transform3D(Basis(Vector3.UP, f.phase * 0.0), Vector3(f.lz, y + bobbing, -f.lx))
			var t := xf * local
			mmb.set_instance_transform(c, t)
			mmb.set_instance_color(c, body_col)
			mmc.set_instance_transform(c, t)
			mmc.set_instance_color(c, cap_col)
			c += 1
	mmb.visible_instance_count = c
	mmc.visible_instance_count = c
	if B._test.has("trace") and not B.ships.is_empty() and not _dbg_done:
		_dbg_done = true
		var s0: Ship = B.player
		for m in s0.mounts:
			print("  mount ", m.g, " x ", m.x, " lz ", m.get("lz"), " deck_y ", m.get("deck_y"))
		print("crew figs drawn ", c, " player figs ", s0.crew_figs.size(), " deck_y ", _deck_y(s0, 0.0), " sample ", (s0.crew_figs[0] if not s0.crew_figs.is_empty() else {}), " model ", s0.model.global_transform.origin, " cam ", cam_pos)
