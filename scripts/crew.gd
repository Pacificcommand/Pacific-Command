class_name Crew
extends Node3D
## The ship is alive: a representative crew of small figures on every deck. Cruising, they
## stroll about the deck; at general quarters they run to the open gun mounts and the rails,
## repair parties fight fires, and when the ship goes down they go to the side and over.
##
## The figures are the dock's cartoon sailors (scripts/dock.gd `_figure`): blue shirt, dark
## trousers, white dixie cup hat for the US Navy; whites and a navy cap for the IJN; work
## clothes for merchant crews. Each look and walking pose is one baked mesh drawn with a
## MultiMesh, so hundreds cost little.
##
## WHERE THEY CAN STAND: for every ship class the model's own triangles are rasterised into a
## 0.5 m height grid (ship-local: lx forward, lz starboard). A cell is open deck when the
## surface round it is flat (within 0.2 m), nothing stands up within a metre (walls, mounts,
## funnels, railings) and the deck does not fall away within a metre (the edge, hatches). Open
## cells that touch form decks; a figure only ever stands on open cells of its own deck and
## walks between them along A* paths, so it can't walk through a turret or off the side.
## Carriers keep the middle of the flight deck clear for the parked aircraft. The grids are
## cached in user://crew_grid (bump GRID_VER after changing the rules or a model).

var B                                  # the Battle
var layers := {}                       # "us0".."merchant2" -> MultiMeshInstance3D
var _dbg_done := false
const MAX_FIGS := 1400
const WALK := 1.4                      # m/s strolling
const RUN := 3.2                       # m/s to battle stations
const CELL := 0.5
const SCALE := 0.9                     # the dock sailor is ~2 m in its cartoon proportions
const GRID_VER := 6
const LOOKS := {
	"us": {"shirt": Color(0.25, 0.36, 0.6), "pants": Color(0.14, 0.18, 0.32), "hat": "dixie", "hat_col": Color(0.97, 0.97, 0.94)},
	"ijn": {"shirt": Color(0.88, 0.87, 0.81), "pants": Color(0.84, 0.83, 0.77), "hat": "flat", "hat_col": Color(0.12, 0.14, 0.22)},
	"merchant": {"shirt": Color(0.46, 0.39, 0.31), "pants": Color(0.22, 0.2, 0.18), "hat": "knit", "hat_col": Color(0.24, 0.24, 0.26)},
}
const SKIN := Color(0.93, 0.76, 0.62)

static var _grids := {}                # model path -> grid Dictionary


func _ready() -> void:
	for look in LOOKS:
		for pose in 3:
			layers["%s%d" % [look, pose]] = _layer(_figure_mesh(LOOKS[look], pose))


func _layer(mesh: Mesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = MAX_FIGS
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mi.material_override = mat
	add_child(mi)
	return mi


# ---------------------------------------------------------------- the figure

## The dock sailor as one mesh: legs, torso, arms with hands, a big round head and the hat.
## Faces +x. pose 0 standing, 1 and 2 the two halves of a stride.
func _figure_mesh(look: Dictionary, pose: int) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sw: float = [0.0, 0.42, -0.42][pose]                 # leg swing, radians
	var shirt: Color = look.shirt
	var pants: Color = look.pants
	var root := Transform3D(Basis().scaled(Vector3.ONE * SCALE), Vector3.ZERO)
	for s in [-1, 1]:
		var hip := root * Transform3D(Basis(Vector3(0, 0, 1), sw * s), Vector3(0, 0.78, 0.12 * s))
		_add(st, _capsule(0.1, 0.72), hip * Transform3D(Basis(), Vector3(0, -0.36, 0)), pants)
		_add(st, _boxm(Vector3(0.24, 0.1, 0.14)), hip * Transform3D(Basis(), Vector3(0.05, -0.74, 0)), Color(0.08, 0.07, 0.06))
	_add(st, _capsule(0.24, 0.72), root * Transform3D(Basis(), Vector3(0, 1.12, 0)), shirt)
	for s in [-1, 1]:
		var sh := root * Transform3D(Basis(Vector3(0, 0, 1), -sw * s * 0.8), Vector3(0, 1.38, 0.3 * s))
		_add(st, _capsule(0.075, 0.6), sh * Transform3D(Basis(), Vector3(0, -0.28, 0)), shirt)
		_add(st, _spherem(0.075), sh * Transform3D(Basis(), Vector3(0, -0.6, 0)), SKIN)
	var head := root * Transform3D(Basis(), Vector3(0, 1.72, 0))
	_add(st, _spherem(0.27), head, SKIN)
	for s in [-1, 1]:
		_add(st, _spherem(0.04), head * Transform3D(Basis(), Vector3(0.24, 0.04, 0.09 * s)), Color(0.08, 0.08, 0.1))
	var hc: Color = look.hat_col
	match String(look.hat):
		"dixie":
			_add(st, _cylm(0.2, 0.14), head * Transform3D(Basis(), Vector3(0, 0.25, 0)), hc)
			_add(st, _cylm(0.27, 0.05), head * Transform3D(Basis(), Vector3(0, 0.2, 0)), hc)
		"flat":
			_add(st, _cylm(0.26, 0.1), head * Transform3D(Basis(), Vector3(0, 0.25, 0)), hc)
			_add(st, _cylm(0.235, 0.05), head * Transform3D(Basis(), Vector3(0, 0.19, 0)), Color(0.9, 0.9, 0.86))
		"knit":
			_add(st, _spherem(0.25), head * Transform3D(Basis().scaled(Vector3(1, 0.7, 1)), Vector3(0, 0.12, 0)), hc)
	st.generate_normals()
	return st.commit()


func _add(st: SurfaceTool, m: Mesh, xf: Transform3D, col: Color) -> void:
	var arr: Array = m.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx = arr[Mesh.ARRAY_INDEX]
	var order: PackedInt32Array
	if idx == null or (idx as PackedInt32Array).is_empty():
		order = PackedInt32Array(range(vs.size()))
	else:
		order = idx
	for i in order:
		st.set_color(col)
		st.add_vertex(xf * vs[i])


func _capsule(r: float, h: float) -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = r; m.height = maxf(h, r * 2.0); m.radial_segments = 8; m.rings = 2
	return m


func _spherem(r: float) -> Mesh:
	var m := SphereMesh.new()
	m.radius = r; m.height = r * 2.0; m.radial_segments = 10; m.rings = 5
	return m


func _cylm(r: float, h: float) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = r; m.bottom_radius = r; m.height = h; m.radial_segments = 10; m.rings = 1
	return m


func _boxm(size: Vector3) -> Mesh:
	var m := BoxMesh.new()
	m.size = size
	return m


# ---------------------------------------------------------------- the deck grid

## The walk grid for a ship's class (built from its model once, then cached).
func grid_for(s: Ship) -> Dictionary:
	var key: String = s.T.models.values()[0] if s.T.has("models") else s.type_id
	if _grids.has(key):
		return _grids[key]
	var g := _load_grid(key)
	if g.is_empty():
		var t0 := Time.get_ticks_msec()
		g = _build_grid(s)
		if B and B._test.has("trace"):
			print("crew grid %s: %d open cells, %d decks, %d ms" % [s.type_id, g.open_n, g.comps.size(), Time.get_ticks_msec() - t0])
		_save_grid(key, g)
	_finish_grid(g)
	_grids[key] = g
	return g


func _cache_path(key: String) -> String:
	return "user://crew_grid/%s_v%d.bin" % [key.get_file().get_basename(), GRID_VER]


## Grids baked with the game (--crewcheck --crewbake writes them), so battles never wait.
func _res_path(key: String) -> String:
	return "res://assets/crew_grid/%s_v%d.bin" % [key.get_file().get_basename(), GRID_VER]


func _load_grid(key: String) -> Dictionary:
	var p := _res_path(key)
	if not FileAccess.file_exists(p):
		p = _cache_path(key)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var v = f.get_var()
	return v if v is Dictionary else {}


func _save_grid(key: String, g: Dictionary) -> void:
	var p := _cache_path(key)
	if B and B._test.has("crewbake"):
		p = ProjectSettings.globalize_path(_res_path(key))
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_var({"x0": g.x0, "z0": g.z0, "nx": g.nx, "nz": g.nz, "hm": g.hm, "open": g.open, "open_n": g.open_n, "comps": g.comps})


func _build_grid(s: Ship) -> Dictionary:
	var L: float = s.T.L
	var Bm: float = s.T.B
	var g := {"x0": -L / 2.0 - 6.0, "z0": -Bm / 2.0 - 4.0}
	g.nx = int(ceil((L + 12.0) / CELL))
	g.nz = int(ceil((Bm + 8.0) / CELL))
	var hm := PackedFloat32Array()
	hm.resize(g.nx * g.nz)
	hm.fill(-99.0)
	g.hm = hm
	var blk := PackedByteArray()
	blk.resize(g.nx * g.nz)
	g.blk = blk
	# parts that turn or come and go are not deck: gun mounts, torpedo tubes, parked aircraft
	var moving := {}
	for m in s.mounts:
		moving[String(m.g)] = true
	for t in s.torps:
		moving[String(t.g)] = true
	g.moving = moving
	if s.model:
		# model space: x starboard, y up, z aft; the grid is (lx forward, lz starboard)
		var to_ship := Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3.ZERO)
		_raster(s.model, to_ship, g)
	var nx: int = g.nx
	var nz: int = g.nz
	var carrier: bool = s.T.get("cls", "") in ["cv", "cvl", "cve"]
	var half_b := Bm / 2.0
	var open := PackedByteArray()
	open.resize(nx * nz)
	var n_open := 0
	for strict in [true, false]:
		n_open = 0
		for iz in nz:
			for ix in nx:
				var h: float = hm[iz * nx + ix]
				var ok := h > 0.3
				for dz2 in range(-1, 2):
					for dx2 in range(-1, 2):
						var bx := ix + dx2
						var bz := iz + dz2
						if bx >= 0 and bz >= 0 and bx < nx and bz < nz and g.blk[bz * nx + bx] == 1:
							ok = false
				if ok and carrier:
					# the flight deck's middle is for aircraft; people keep to the edges
					var lz: float = g.z0 + (iz + 0.5) * CELL
					var top: bool = h > 8.0
					if top and absf(lz) < half_b - 3.5:
						ok = false
				var r := 2 if strict else 1
				if ok:
					for dz in range(-r, r + 1):
						for dx in range(-r, r + 1):
							var jx := ix + dx
							var jz := iz + dz
							if jx < 0 or jz < 0 or jx >= nx or jz >= nz:
								ok = false; break
							var hn: float = hm[jz * nx + jx]
							# half a metre clear of anything standing up or falling away; a metre
							# from an open edge over the water
							var near := absi(dx) <= 1 and absi(dz) <= 1
							if near and absf(hn - h) > 0.22:
								ok = false; break
							if not near and hn < -50.0:
								ok = false; break
						if not ok:
							break
				open[iz * nx + ix] = 1 if ok else 0
				if ok:
					n_open += 1
		if n_open >= 12:
			break
	if s.T.get("cls", "") == "barge":
		# a landing barge's well is full of cargo: the crew rides aft, round the engine house,
		# at the coxswain's position and the machine gun
		n_open = 0
		var aft := []
		for iz in nz:
			for ix in nx:
				var lx: float = g.x0 + (ix + 0.5) * CELL
				var lz: float = g.z0 + (iz + 0.5) * CELL
				var k := iz * nx + ix
				open[k] = 0
				if lx < -L / 2.0 + 4.2 and lx > -L / 2.0 + 0.6 and absf(lz) < Bm / 2.0 - 0.6 and hm[k] > 0.3 and g.blk[k] == 0:
					aft.append(hm[k])
		aft.sort()
		var floor_y: float = aft[aft.size() / 3] if not aft.is_empty() else 1.0
		for iz in nz:
			for ix in nx:
				var lx2: float = g.x0 + (ix + 0.5) * CELL
				var lz2: float = g.z0 + (iz + 0.5) * CELL
				var k2 := iz * nx + ix
				if lx2 < -L / 2.0 + 4.2 and lx2 > -L / 2.0 + 0.6 and absf(lz2) < Bm / 2.0 - 0.6 and g.blk[k2] == 0 and absf(hm[k2] - floor_y) < 0.25:
					open[k2] = 1
					n_open += 1
	g.open = open
	g.open_n = n_open
	# decks: open cells that touch (4-way); the flatness rule keeps levels apart
	var comp := PackedInt32Array()
	comp.resize(nx * nz)
	comp.fill(-1)
	var comps := []
	for start in nx * nz:
		if open[start] == 0 or comp[start] >= 0:
			continue
		var id := comps.size()
		var cells := PackedInt32Array()
		var stack := [start]
		comp[start] = id
		var ysum := 0.0
		while not stack.is_empty():
			var k: int = stack.pop_back()
			cells.append(k)
			ysum += hm[k]
			var kx := k % nx
			var kz := k / nx
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var jx: int = kx + d.x
				var jz: int = kz + d.y
				if jx < 0 or jz < 0 or jx >= nx or jz >= nz:
					continue
				var j := jz * nx + jx
				if open[j] == 1 and comp[j] < 0:
					comp[j] = id
					stack.append(j)
		comps.append({"cells": cells, "y": ysum / cells.size()})
	g.comps = comps
	return g


## Lookups that are not worth caching: cell -> deck, the A* grid, the rail cells of each deck.
func _finish_grid(g: Dictionary) -> void:
	var nx: int = g.nx
	var nz: int = g.nz
	var comp := PackedInt32Array()
	comp.resize(nx * nz)
	comp.fill(-1)
	for id in g.comps.size():
		for k in g.comps[id].cells:
			comp[k] = id
	g.comp = comp
	var a := AStarGrid2D.new()
	a.region = Rect2i(0, 0, nx, nz)
	a.cell_size = Vector2.ONE
	a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	a.update()
	for k in nx * nz:
		if g.open[k] == 0:
			a.set_point_solid(Vector2i(k % nx, k / nx), true)
	g.astar = a
	# rails: on each deck, the outermost open cell of every row on each side
	for c in g.comps:
		var best := {}
		for k in c.cells:
			var ix: int = k % nx
			var iz: int = k / nx
			var lz: float = g.z0 + (iz + 0.5) * CELL
			var key := ix * 2 + (1 if lz >= 0.0 else 0)
			if not best.has(key) or absf(lz) > absf(g.z0 + (best[key] / nx + 0.5) * CELL):
				best[key] = k
		var rails := PackedInt32Array()
		for key in best:
			rails.append(best[key])
		c.rails = rails


func _raster(n: Node, xf: Transform3D, g: Dictionary, blocked := false) -> void:
	for c in n.get_children():
		if not c is Node3D:
			continue
		var nm := String(c.name)
		var blk_here: bool = blocked or g.moving.has(nm) or nm.begins_with("Park") or nm.begins_with("Float")
		g.cur_blk = blk_here
		var cx: Transform3D = xf * (c as Node3D).transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and (c as MeshInstance3D).visible:
			var mesh: Mesh = (c as MeshInstance3D).mesh
			for si in mesh.get_surface_count():
				var arr: Array = mesh.surface_get_arrays(si)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var idx = arr[Mesh.ARRAY_INDEX]
				var w := PackedVector3Array()
				w.resize(vs.size())
				for i in vs.size():
					w[i] = cx * vs[i]
				if idx == null or (idx as PackedInt32Array).is_empty():
					for i in range(0, w.size() - 2, 3):
						_tri(w[i], w[i + 1], w[i + 2], g)
				else:
					var ix: PackedInt32Array = idx
					for i in range(0, ix.size() - 2, 3):
						_tri(w[ix[i]], w[ix[i + 1]], w[ix[i + 2]], g)
		_raster(c, cx, g, blk_here)


func _tri(a: Vector3, b: Vector3, c: Vector3, g: Dictionary) -> void:
	var x0: float = g.x0
	var z0: float = g.z0
	var nx: int = g.nx
	var nz: int = g.nz
	var hm: PackedFloat32Array = g.hm
	var minx := minf(a.x, minf(b.x, c.x))
	var maxx := maxf(a.x, maxf(b.x, c.x))
	var minz := minf(a.z, minf(b.z, c.z))
	var maxz := maxf(a.z, maxf(b.z, c.z))
	var ix0 := maxi(0, int((minx - x0) / CELL))
	var ix1 := mini(nx - 1, int((maxx - x0) / CELL))
	var iz0 := maxi(0, int((minz - z0) / CELL))
	var iz1 := mini(nz - 1, int((maxz - z0) / CELL))
	if ix1 < ix0 or iz1 < iz0:
		return
	var den := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(den) < 1e-6:
		# seen edge-on from above (a wall, a railing): it still stands up where it is
		var top := maxf(a.y, maxf(b.y, c.y))
		for iz in range(iz0, iz1 + 1):
			for ix in range(ix0, ix1 + 1):
				var k0 := iz * nx + ix
				if top > hm[k0]:
					hm[k0] = top
				if g.cur_blk:
					g.blk[k0] = 1
		return
	for iz in range(iz0, iz1 + 1):
		var pz := z0 + (iz + 0.5) * CELL
		for ix in range(ix0, ix1 + 1):
			var px := x0 + (ix + 0.5) * CELL
			var w1 := ((b.z - c.z) * (px - c.x) + (c.x - b.x) * (pz - c.z)) / den
			var w2 := ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / den
			var w3 := 1.0 - w1 - w2
			if w1 < -0.001 or w2 < -0.001 or w3 < -0.001:
				continue
			var y := w1 * a.y + w2 * b.y + w3 * c.y
			var k := iz * nx + ix
			if y > hm[k]:
				hm[k] = y
			if g.cur_blk:
				g.blk[k] = 1
	g.hm = hm


func _cell_xz(g: Dictionary, k: int) -> Vector2:
	return Vector2(g.x0 + (k % g.nx + 0.5) * CELL, g.z0 + (k / g.nx + 0.5) * CELL)


func _cell_of(g: Dictionary, lx: float, lz: float) -> int:
	var ix := clampi(int((lx - g.x0) / CELL), 0, g.nx - 1)
	var iz := clampi(int((lz - g.z0) / CELL), 0, g.nz - 1)
	return iz * g.nx + ix


## The open cell of deck `cid` nearest (lx, lz); -1 if the deck has none.
func _nearest_on(g: Dictionary, cid: int, lx: float, lz: float) -> int:
	var best := -1
	var bd := 1e18
	for k in g.comps[cid].cells:
		var p := _cell_xz(g, k)
		var d := (p.x - lx) * (p.x - lx) + (p.y - lz) * (p.y - lz)
		if d < bd:
			bd = d; best = k
	return best


## The open cell (any deck) nearest (lx, lz) within `rad` m; -1 if none.
func _nearest_open(g: Dictionary, lx: float, lz: float, rad: float) -> int:
	var c0 := _cell_of(g, lx, lz)
	var r := int(rad / CELL)
	var cx: int = c0 % g.nx
	var cz: int = c0 / g.nx
	var best := -1
	var bd := 1e9
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var jx: int = cx + dx
			var jz: int = cz + dz
			if jx < 0 or jz < 0 or jx >= g.nx or jz >= g.nz:
				continue
			var k: int = jz * g.nx + jx
			if g.open[k] == 1:
				var d := float(dx * dx + dz * dz)
				if d < bd:
					bd = d; best = k
	return best


# ---------------------------------------------------------------- per ship

## Make the crew for a ship once its model is loaded.
func setup_ship(s: Ship) -> void:
	var T: Dictionary = s.T
	s.crew_figs = []
	if T.get("ground", false) or T.get("cls", "") == "raft" or s.model == null:
		return
	var g := grid_for(s)
	if g.comps.is_empty():
		return
	var n: int = clampi(int(float(T.get("crew", 100)) / 24.0), 4, 36)
	if T.get("cls", "") in ["cv", "cvl", "cve"]:
		n = 40
	if T.get("cls", "") in ["barge", "pt"]:
		n = clampi(int(float(T.get("crew", 14)) / 4.0), 3, 8)
	# decks big enough to walk on, weighted by size; every deck with a gun station gets someone
	var decks := []
	var total := 0
	var want := []
	for st in _stations(s, g):
		if not want.has(st.comp):
			want.append(st.comp)
	# a deck is a flat walkable area of 30 cells (7.5 m2) or more, or a gun platform; smaller flat
	# patches are roofs of lockers and tops of cargo, not where sailors go
	var biggest := 0
	for id in g.comps.size():
		if g.comps[id].cells.size() > g.comps[biggest].cells.size():
			biggest = id
	for id in g.comps.size():
		if g.comps[id].cells.size() >= (8 if s.T.L < 40.0 else 30) or want.has(id):
			decks.append(id)
			total += g.comps[id].cells.size()
	if decks.is_empty():
		decks.append(biggest)
		total = g.comps[biggest].cells.size()
	for i in n:
		var cid: int
		if i < want.size() and i < n / 2:
			cid = want[i]
		else:
			var r := randi() % total
			cid = decks[0]
			for id in decks:
				r -= g.comps[id].cells.size()
				if r < 0:
					cid = id
					break
		var cells: PackedInt32Array = g.comps[cid].cells
		var k: int = cells[randi() % cells.size()]
		var p := _cell_xz(g, k)
		s.crew_figs.append({"lx": p.x, "lz": p.y, "comp": cid, "path": PackedVector2Array(), "state": "idle", "wait": randf_range(0.0, 6.0),
			"phase": randf() * TAU, "yaw": randf() * TAU, "station": null, "gone": false})


## Battle stations, snapped onto open deck: behind the open gun mounts (light AA and single or
## twin secondaries; turrets and big mounts are crewed inside).
func _stations(s: Ship, g: Dictionary) -> Array:
	var out := []
	for m in s.mounts:
		if m.hp <= 0.0:
			continue
		var gn: Dictionary = m.gun
		var enclosed: bool = gn.dmg >= 1.5 or (gn.dmg >= 0.9 and s.T.L > 140.0)
		if enclosed:
			continue
		var crew_n := 2 if gn.dmg < 0.5 else 3
		var taken := {}
		for k in crew_n:
			var side := (k % 2) * 2 - 1
			var c := _nearest_open(g, m.x - 1.5 - 0.6 * int(k / 2), m.get("lz", 0.0) + side * 1.0, 4.0)
			if c < 0 or taken.has(c):
				continue
			taken[c] = true
			var p := _cell_xz(g, c)
			out.append({"lx": p.x, "lz": p.y, "comp": g.comp[c], "kind": "gun", "face": Vector2(m.x, m.get("lz", 0.0))})
	return out


func _fire_stations(s: Ship, g: Dictionary) -> Array:
	var out := []
	for f in s.fires:
		for k in 3:
			var a := TAU * k / 3.0 + 0.4
			var c := _nearest_open(g, f.lx + cos(a) * 4.0, f.lz + sin(a) * 3.0, 6.0)
			if c >= 0:
				var p := _cell_xz(g, c)
				out.append({"lx": p.x, "lz": p.y, "comp": g.comp[c], "kind": "fire", "face": Vector2(f.lx, f.lz)})
	return out


func step(dt: float) -> void:
	for s in B.ships:
		if s.crew_figs.is_empty() or s.gone:
			continue
		_step_ship(s, dt)


## Send a figure along a path over its own deck to the cell nearest (tx, tz).
func _go(g: Dictionary, f: Dictionary, tx: float, tz: float) -> void:
	var to := _nearest_on(g, f.comp, tx, tz)
	var from := _cell_of(g, f.lx, f.lz)
	if to < 0:
		f.path = PackedVector2Array()
		return
	var a: AStarGrid2D = g.astar
	var ids: Array[Vector2i] = a.get_id_path(Vector2i(from % g.nx, from / g.nx), Vector2i(to % g.nx, to / g.nx))
	var pts := PackedVector2Array()
	for id in ids:
		pts.append(Vector2(g.x0 + (id.x + 0.5) * CELL, g.z0 + (id.y + 0.5) * CELL))
	if pts.is_empty():
		pts.append(_cell_xz(g, to))
	f.path = pts


func _step_ship(s: Ship, dt: float) -> void:
	var T: Dictionary = s.T
	var g := grid_for(s)
	var gq: bool = B.combat_t >= 0.0 or s.target != null or not s.fires.is_empty()
	var sinking: bool = not s.alive and s.sinking > 0.0
	var alive_frac: float = clampf(float(s.crew) / maxf(1.0, float(T.get("crew", 100))), 0.0, 1.0)
	var n_alive: int = int(ceil(s.crew_figs.size() * alive_frac))
	# stations are handed out when the ship goes to quarters, a fire breaks out, or she sinks
	var changed: bool = s.get_meta("crew_gq", false) != gq or s.get_meta("crew_fires", -1) != s.fires.size() or s.get_meta("crew_sunk", false) != sinking
	if changed:
		s.set_meta("crew_gq", gq); s.set_meta("crew_fires", s.fires.size()); s.set_meta("crew_sunk", sinking)
		var stations: Array = _fire_stations(s, g) + (_stations(s, g) if gq else [])
		for f in s.crew_figs:
			f.station = null
		if not sinking:
			# each station goes to the nearest free figure on the same deck
			for st in stations:
				var best = null
				var bd := 1e9
				for f in s.crew_figs:
					if f.station != null or f.comp != st.comp:
						continue
					var d: float = (f.lx - st.lx) * (f.lx - st.lx) + (f.lz - st.lz) * (f.lz - st.lz)
					if d < bd:
						bd = d; best = f
				if best != null:
					best.station = st
		for f in s.crew_figs:
			if sinking or (gq and f.station == null):
				# to the rail of your deck (lookouts, ammunition passers; or to abandon ship)
				var rails: PackedInt32Array = g.comps[f.comp].rails
				if not rails.is_empty():
					var best := -1
					var bd := 1e9
					for k in 6:
						var c: int = rails[randi() % rails.size()]
						var p := _cell_xz(g, c)
						var d: float = absf(p.x - f.lx) + absf(p.y - f.lz) * 0.3
						if d < bd:
							bd = d; best = c
					var rp := _cell_xz(g, best)
					f.station = {"lx": rp.x, "lz": rp.y, "comp": f.comp, "kind": "rail", "face": Vector2(rp.x, rp.y * 3.0)}
			if f.station != null:
				_go(g, f, f.station.lx, f.station.lz)
				f.state = "run"
			elif f.state in ["run", "post"]:
				f.state = "idle"
				f.wait = randf_range(0.0, 3.0)
	for k in s.crew_figs.size():
		var f: Dictionary = s.crew_figs[k]
		f.gone = k >= n_alive
		if f.gone:
			continue
		match f.state:
			"idle":
				f.wait -= dt
				if f.wait <= 0.0:
					# a stroll to somewhere on the same deck, not too far
					var cells: PackedInt32Array = g.comps[f.comp].cells
					var tgt := _cell_xz(g, cells[randi() % cells.size()])
					if tgt.distance_to(Vector2(f.lx, f.lz)) > 25.0:
						tgt = Vector2(f.lx, f.lz) + (tgt - Vector2(f.lx, f.lz)).normalized() * 25.0
					_go(g, f, tgt.x, tgt.y)
					f.state = "walk"
			"walk":
				f.phase += dt * 7.0
				if _move(f, WALK * dt):
					f.state = "idle"
					f.wait = randf_range(2.0, 9.0)
			"run":
				f.phase += dt * 11.0
				if _move(f, RUN * dt):
					f.state = "post"
					if f.station != null:
						var fc: Vector2 = f.station.face
						f.yaw = atan2(fc.x - f.lx, fc.y - f.lz)
					if sinking:
						f.state = "jump"
						f.wait = randf_range(0.0, 4.0)
			"post":
				pass
			"jump":
				f.wait -= dt
				if f.wait <= 0.0:
					f.gone = true
					if B.fx and randf() < 0.7:
						var wp := s.to_world_xz(f.lx, (absf(f.lz) + 2.0) * signf(f.lz + 0.001))
						B.fx.splash(wp.x, wp.y, false)
	s.crew_figs = s.crew_figs.filter(func(f): return not (f.gone and f.state == "jump"))


## Walk along the path; true when it ends. Turns the figure to face where it walks.
func _move(f: Dictionary, step: float) -> bool:
	var path: PackedVector2Array = f.path
	while step > 0.0 and not path.is_empty():
		var tgt: Vector2 = path[0]
		var dx: float = tgt.x - f.lx
		var dz: float = tgt.y - f.lz
		var d := sqrt(dx * dx + dz * dz)
		if d > 0.001:
			f.yaw = atan2(dx, dz)
		if d <= step:
			f.lx = tgt.x; f.lz = tgt.y
			step -= d
			path.remove_at(0)
		else:
			f.lx += dx / d * step
			f.lz += dz / d * step
			step = 0.0
	f.path = path
	return path.is_empty()


## Deck height under a figure (the grid's top surface where it stands).
func deck_y(g: Dictionary, lx: float, lz: float) -> float:
	return g.hm[_cell_of(g, lx, lz)]


# ---------------------------------------------------------------- drawing

func render(cam_pos: Vector3) -> void:
	var counts := {}
	for key in layers:
		counts[key] = 0
	var total := 0
	for s in B.ships:
		if not s.visible or s.crew_figs.is_empty() or s.model == null:
			continue
		# too far to see people: skip the ship entirely
		var d: float = Vector2(s.x - cam_pos.x, s.z - cam_pos.z).length() + cam_pos.y
		if d > 2600.0:
			continue
		var g := grid_for(s)
		var look := "us" if s.team == "us" else "ijn"
		if s.T.get("cls", "") == "merchant":
			look = "merchant"
		var xf: Transform3D = s.model.global_transform
		for f in s.crew_figs:
			if f.gone or total >= MAX_FIGS:
				continue
			var pose := 0
			if f.state in ["walk", "run"]:
				pose = 1 + (int(f.phase / PI) % 2)
			var key := "%s%d" % [look, pose]
			var y: float = deck_y(g, f.lx, f.lz)
			# ship-local (lx fwd, lz stbd) to model space (x stbd, z aft); the figure faces +x
			var basis := Basis(Vector3.UP, f.yaw - PI / 2.0)
			var local := Transform3D(basis, Vector3(f.lz, y, -f.lx))
			layers[key].multimesh.set_instance_transform(counts[key], xf * local)
			counts[key] += 1
			total += 1
	for key in layers:
		layers[key].multimesh.visible_instance_count = counts[key]


# ---------------------------------------------------------------- test

## --crewgrid=TYPE,PNG: draw a class's deck grid (heights in grey, open deck green, turning
## parts red) four pixels a cell, bow to the right.
func grid_png(tid: String, path: String) -> void:
	var s: Ship = B._add_ship(tid, "us", "Grid " + tid, 0.0, 0.0, 0.0, 0.0)
	var g := grid_for(s)
	var img := Image.create(g.nx * 4, g.nz * 4, false, Image.FORMAT_RGB8)
	var top := 1.0
	for v in g.hm:
		top = maxf(top, v)
	for k in g.nx * g.nz:
		var h: float = g.hm[k]
		var c := Color(0.05, 0.1, 0.2)
		if h > -50.0:
			var v := clampf(h / top, 0.0, 1.0)
			c = Color(0.25 + 0.6 * v, 0.25 + 0.6 * v, 0.25 + 0.6 * v)
		if g.open[k] == 1:
			c = Color(0.2, 0.8, 0.3)
		img.fill_rect(Rect2i((k % g.nx) * 4, (g.nz - 1 - k / g.nx) * 4, 4, 4), c)
	img.save_png(path)
	print("grid ", tid, " -> ", path)


## --crewcheck: every ship class, its deck grid and a crew run for two minutes of quarters,
## stations and sinking; counts any figure that stood on a cell that is not open deck.
func clip_check() -> void:
	var bad_total := 0
	for tid in Data.TYPES:
		var T: Dictionary = Data.TYPES[tid]
		if T.get("ground", false) or T.get("cls", "") == "raft" or not T.has("models"):
			continue
		var s: Ship = B._add_ship(tid, "us", "Check " + tid, 0.0, 0.0, 0.0, 0.0)
		var g := grid_for(s)
		var bad := 0
		var steps := 0
		for i in 1200:
			if i == 300:
				s.target = s      # general quarters
			if i == 900:
				s.alive = false; s.sinking = 1.0
			_step_ship(s, 0.1)
			for f in s.crew_figs:
				steps += 1
				if g.open[_cell_of(g, f.lx, f.lz)] == 0:
					bad += 1
		print("crewcheck %-14s L %5.0f  open %5d  decks %2d  figs %2d  off-deck %d" % [tid, T.L, g.open_n, g.comps.size(), s.crew_figs.size(), bad])
		bad_total += bad
		B.ships.erase(s)
		s.queue_free()
	print("crewcheck total off-deck: ", bad_total)
