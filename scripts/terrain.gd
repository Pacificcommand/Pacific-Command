class_name Terrain
extends Node3D
## Islands in battle. Real islands are baked maps (tools/island_builder, IslandMaps): a coast,
## heights, reefs, airfields and vegetation drawn on the graphics card, with palms and jungle
## trees near the shore. height_at() is the ground truth for grounding, shore targets and shells
## landing on the beach. The old round procedural islands are still drawn when a plan asks for one.

var islands: Array = []      # what is in the battle: {map, x, z, r} (baked) or {x, z, r, h, seed} (procedural)
var _maps: Array = []        # baked islands: {id, x, z, half, n, px, h: PackedFloat32Array, img, meta}
var _noise := FastNoiseLite.new()
var _lut := PackedFloat32Array()

const SD := 200.0            # signed distance range of the map's R channel (metres)


func _ready() -> void:
	_lut.resize(256)
	for e in 256:
		_lut[e] = _dec(float(e))


static func _dec(e: float) -> float:
	if e >= 64.0:
		return 2.0 * (exp((e - 64.0) / 191.0 * log(1501.0)) - 1.0)
	return -2.0 * (exp((64.0 - e) / 64.0 * log(41.0)) - 1.0)


## list: [{map: id, x, z}] places a baked island with its window centre at (x, z); old entries
## {x, z, r, h, seed} make the procedural round islands.
func setup(list: Array) -> void:
	for c in get_children():
		c.queue_free()
	islands = []
	_maps = []
	if _lut.is_empty():
		_ready()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0022
	for isl in list:
		if isl.has("map"):
			_add_map(isl)
		else:
			islands.append(isl.duplicate(true))
			_build(isl)


## What setup() needs to rebuild the same islands (saved with the battle).
func save() -> Array:
	return islands.duplicate(true)


func map_meta(i := 0) -> Dictionary:
	return _maps[i].meta if i < _maps.size() else {}


func height_at(x: float, z: float) -> float:
	var best := -60.0
	for m in _maps:
		var lx: float = x - m.x
		var lz: float = z - m.z
		var half: float = m.half
		if absf(lx) >= half or absf(lz) >= half:
			continue
		# bilinear between the four map pixels round the point
		var n: int = m.n
		var fx: float = (lx + half) / m.px - 0.5
		var fz: float = (lz + half) / m.px - 0.5
		var i0 := clampi(int(floor(fx)), 0, n - 2)
		var j0 := clampi(int(floor(fz)), 0, n - 2)
		var tx := clampf(fx - i0, 0.0, 1.0)
		var tz := clampf(fz - j0, 0.0, 1.0)
		var hh: PackedFloat32Array = m.h
		var a := hh[j0 * n + i0]
		var b := hh[j0 * n + i0 + 1]
		var c := hh[(j0 + 1) * n + i0]
		var d := hh[(j0 + 1) * n + i0 + 1]
		best = maxf(best, lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz))
	for isl in islands:
		if isl.has("map"):
			continue
		best = maxf(best, _proc_height(isl, x, z))
	return best


func is_land(x: float, z: float) -> bool:
	return height_at(x, z) > 0.0


# =====================================================================
# baked real islands
# =====================================================================

func _add_map(isl: Dictionary) -> void:
	var id: String = isl.map
	if not IslandMaps.MAPS.has(id):
		push_warning("no baked island %s" % id)
		return
	var meta: Dictionary = IslandMaps.MAPS[id]
	var img: Image = load("res://assets/islands/%s.png" % id)
	if img == null:
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var n: int = img.get_width()
	var half: float = float(meta.half)
	var px: float = 2.0 * half / n
	# heights at 16 bits (<id>_h.png: high byte R, low byte G), decoded once for height_at and
	# handed to the shaders as a float texture so slopes are smooth, not terraced
	var hraw: PackedByteArray
	var himg: Image = load("res://assets/islands/%s_h.png" % id)
	var hh := PackedFloat32Array()
	hh.resize(n * n)
	if himg != null and himg.get_width() == n:
		if himg.get_format() != Image.FORMAT_RGB8:
			himg.convert(Image.FORMAT_RGB8)
		hraw = himg.get_data()
		for k in n * n:
			hh[k] = (hraw[k * 3] * 256.0 + hraw[k * 3 + 1]) / 65535.0 * 3080.0 - 80.0
	else:
		var raw := img.get_data()
		for k in n * n:
			hh[k] = _lut[raw[k * 4 + 1]]
	var fimg := Image.create_from_data(n, n, false, Image.FORMAT_RF, hh.to_byte_array())
	fimg.convert(Image.FORMAT_RH)
	var m := {"id": id, "x": float(isl.x), "z": float(isl.z), "half": half, "n": n, "px": px, "h": hh, "img": img, "meta": meta,
		"htex": ImageTexture.create_from_image(fimg)}
	_maps.append(m)
	islands.append({"map": id, "x": float(isl.x), "z": float(isl.z), "r": half})
	_draw_map(m)
	_plant(m)


func _draw_map(m: Dictionary) -> void:
	var tex := ImageTexture.create_from_image(m.img)
	var half: float = m.half
	var meta: Dictionary = m.meta
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0 * half, 2.0 * half)
	var div := clampi(int(2.0 * half / 14.0), 200, 511)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--islanddiv="):
			div = int(a.split("=")[1])
	pm.subdivide_width = div
	pm.subdivide_depth = div
	var kind: int = {"atoll": 0, "coral": 1, "volcanic": 2, "ash": 3}.get(String(meta.kind), 2)
	var vtype: int = {"palm": 0, "jungle": 1, "scrub": 2, "cane": 3}.get(String(meta.vtype), 1)
	for pass_i in 2:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/island_land.gdshader" if pass_i == 0 else "res://shaders/island_water.gdshader")
		mat.set_shader_parameter("map", tex)
		mat.set_shader_parameter("hmap", m.htex)
		mat.set_shader_parameter("half", half)
		mat.set_shader_parameter("texel", 1.0 / float(m.n))
		mat.set_shader_parameter("kind", kind)
		mat.set_shader_parameter("vtype", vtype)
		mat.set_shader_parameter("sd", SD)
		mat.set_shader_parameter("lagoon_all", meta.get("deep_lagoon", false) or String(m.id) == "truk")
		var fws := Vector3.ZERO
		var flist: Array = meta.get("fields", [])
		for fi in mini(3, flist.size()):
			var fd: Array = flist[fi]
			mat.set_shader_parameter("field%d" % fi, Vector4(float(fd[0]), float(fd[1]), deg_to_rad(float(fd[2])), float(fd[3])))
			fws[fi] = float(fd[4])
		mat.set_shader_parameter("field_w", fws)
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = mat
		mi.position = Vector3(m.x, 0.0, m.z)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if pass_i == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 3000.0       # the vertex shader raises the land well above the flat plane
		add_child(mi)
		if pass_i == 1:
			mi.set_meta("water", true)


## Palms on the low ground and jungle or scrub trees, near the beach and the airfields where the
## fighting is; drawn in chunks that fade out with distance.
func _plant(m: Dictionary) -> void:
	var meta: Dictionary = m.meta
	var img: Image = m.img
	var raw := img.get_data()
	var n: int = m.n
	var half: float = m.half
	var px: float = m.px
	var vtype := String(meta.vtype)
	var kind := String(meta.kind)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(m.id)
	var centres: Array = [Vector2(meta.beach[0], meta.beach[1])]
	for f in meta.get("fields", []):
		centres.append(Vector2(f[0], f[1]))
	var R := 3800.0
	var palm_n := 0
	var tree_n := 0
	var chunks := {}           # Vector2i -> {palm: [Transform3D, ...], tree: [...], col: [...]}
	var step := 14.0 if vtype == "palm" else 20.0
	var cap := 9000
	for c in centres:
		var gx0 := int((c.x - R + half) / step)
		var gx1 := int((c.x + R + half) / step)
		var gz0 := int((c.y - R + half) / step)
		var gz1 := int((c.y + R + half) / step)
		for gz in range(maxi(0, gz0), mini(int(2.0 * half / step), gz1)):
			for gx in range(maxi(0, gx0), mini(int(2.0 * half / step), gx1)):
				var x: float = -half + (gx + rng.randf()) * step
				var z: float = -half + (gz + rng.randf()) * step
				if Vector2(x, z).distance_to(c) > R:
					continue
				var i := int((x + half) / px)
				var j := int((z + half) / px)
				if i < 1 or j < 1 or i >= n - 1 or j >= n - 1:
					continue
				var o := (j * n + i) * 4
				var veg := raw[o + 2] / 255.0
				if raw[o] < 132 or veg < 0.2 or raw[o + 3] > 60:
					continue
				var hgt: float = _lut[raw[o + 1]]
				if rng.randf() > veg * (0.85 if vtype != "scrub" else 0.45):
					continue
				var is_palm := vtype == "palm" or (kind != "ash" and hgt < 12.0 and raw[o] < 170 and vtype != "scrub")
				if vtype == "cane" and not is_palm and rng.randf() < 0.6:
					continue
				var key := Vector2i(int(floor(x / 1500.0)), int(floor(z / 1500.0)))
				if not chunks.has(key):
					chunks[key] = {"palm": [], "tree": [], "col": []}
				var basis := Basis(Vector3.UP, rng.randf() * TAU)
				if is_palm:
					if palm_n >= cap:
						continue
					palm_n += 1
					var s := rng.randf_range(0.8, 1.25)
					var lean := rng.randf_range(-0.16, 0.16)
					chunks[key].palm.append(Transform3D(basis * Basis(Vector3.RIGHT, lean).scaled(Vector3(s, s, s)), Vector3(x + m.x, hgt - 0.3, z + m.z)))
				else:
					if tree_n >= cap:
						continue
					tree_n += 1
					var s2 := rng.randf_range(4.5, 8.5) if vtype == "jungle" or vtype == "cane" else rng.randf_range(1.6, 3.2)
					var t := Transform3D(basis.scaled(Vector3(s2, s2 * rng.randf_range(0.7, 1.0), s2)), Vector3(x + m.x, hgt - 0.4, z + m.z))
					chunks[key].tree.append(t)
					var cc := Color(0.12, 0.27, 0.10).lerp(Color(0.2, 0.36, 0.14), rng.randf()) if vtype != "scrub" else Color(0.30, 0.36, 0.20).lerp(Color(0.40, 0.42, 0.26), rng.randf())
					chunks[key].col.append(cc)
	# buildings: houses and sheds in the towns, huts, barracks and hangars round the airfields
	var houses := []
	var hcols := []
	var hstep := 24.0
	for gz in range(0, int(2.0 * half / hstep)):
		for gx in range(0, int(2.0 * half / hstep)):
			var x: float = -half + (gx + 0.5) * hstep
			var z: float = -half + (gz + 0.5) * hstep
			var i := int((x + half) / px)
			var j := int((z + half) / px)
			var o := (j * n + i) * 4
			if raw[o] < 134 or raw[o + 3] < 90 or raw[o + 3] > 170:
				continue
			if _on_field(meta, x, z, 120.0):
				continue      # the soft edge of an airfield's cleared ground is not a town
			if rng.randf() > 0.5:
				continue
			var hgt: float = _lut[raw[o + 1]]
			var big := rng.randf() < 0.08
			var sx := rng.randf_range(16.0, 30.0) if big else rng.randf_range(6.0, 12.0)
			var sz := rng.randf_range(12.0, 22.0) if big else rng.randf_range(5.0, 9.0)
			var sy := rng.randf_range(6.0, 9.0) if big else rng.randf_range(3.0, 5.0)
			var fl: Array = meta.get("fields", [])
			var fh: float = float(fl[0][2]) if fl.size() > 0 and fl[0].size() > 2 and fl[0][2] != null else 0.0
			var yaw: float = fh * PI / 180.0 + (PI / 2.0 if rng.randf() < 0.5 else 0.0) + rng.randf_range(-0.08, 0.08)
			houses.append(Transform3D(Basis(Vector3.UP, -yaw).scaled(Vector3(sx, sy, sz)), Vector3(x + rng.randf_range(-5, 5) + m.x, hgt - 0.2, z + rng.randf_range(-5, 5) + m.z)))
			hcols.append([Color(0.62, 0.32, 0.24), Color(0.48, 0.47, 0.45), Color(0.55, 0.50, 0.40), Color(0.40, 0.42, 0.36)][rng.randi() % 4])
	if not houses.is_empty():
		var hm := MultiMesh.new()
		hm.transform_format = MultiMesh.TRANSFORM_3D
		hm.use_colors = true
		hm.mesh = _house_mesh()
		hm.instance_count = houses.size()
		for k in houses.size():
			hm.set_instance_transform(k, houses[k])
			hm.set_instance_color(k, hcols[k])
		var hmi := MultiMeshInstance3D.new()
		hmi.multimesh = hm
		hmi.visibility_range_end = 9000.0
		add_child(hmi)
	var palm_mesh := _palm_mesh()
	var tree_mesh := _tree_mesh()
	for key in chunks:
		var ch: Dictionary = chunks[key]
		for kind_i in 2:
			var list: Array = ch.palm if kind_i == 0 else ch.tree
			if list.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = kind_i == 1
			mm.mesh = palm_mesh if kind_i == 0 else tree_mesh
			mm.instance_count = list.size()
			for k in list.size():
				mm.set_instance_transform(k, list[k])
				if kind_i == 1:
					mm.set_instance_color(k, ch.col[k])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_end = 5200.0
			mmi.visibility_range_end_margin = 600.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mmi)


## A coconut palm about 11 m tall: a curved, tapering trunk and drooping fronds.
func _palm_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_c := Color(0.42, 0.35, 0.26)
	var segs := 5
	var sides := 5
	var pts := []
	for k in segs + 1:
		var t := float(k) / segs
		pts.append(Vector3(1.2 * t * t, 11.0 * t, 0.0))
	for k in segs:
		var r0 := lerpf(0.26, 0.15, float(k) / segs)
		var r1 := lerpf(0.26, 0.15, float(k + 1) / segs)
		for sd in sides:
			var a0 := TAU * sd / sides
			var a1 := TAU * (sd + 1) / sides
			var p00: Vector3 = pts[k] + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
			var p01: Vector3 = pts[k] + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
			var p10: Vector3 = pts[k + 1] + Vector3(cos(a0) * r1, 0, sin(a0) * r1)
			var p11: Vector3 = pts[k + 1] + Vector3(cos(a1) * r1, 0, sin(a1) * r1)
			for v in [p00, p10, p11, p00, p11, p01]:
				st.set_color(trunk_c)
				st.set_normal((v - pts[k]).normalized())
				st.add_vertex(v)
	var top: Vector3 = pts[segs]
	var fronds := 9
	for f in fronds:
		var a := TAU * f / fronds + 0.3 * sin(f * 2.1)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var col := Color(0.20, 0.36, 0.13).lerp(Color(0.32, 0.45, 0.18), fmod(f * 0.37, 1.0))
		var prev := top
		var wprev := 0.15
		for s in 4:
			var t := float(s + 1) / 4.0
			var p: Vector3 = top + dir * (4.6 * t) + Vector3(0, 0.9 * t - 2.6 * t * t, 0)
			var w := 0.75 * sin(PI * t) + 0.12
			var q := [prev - side * wprev, prev + side * wprev, p + side * w, p - side * w]
			var nrm: Vector3 = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(col)
				st.set_normal(nrm)
				st.add_vertex(q[idx])
			prev = p
			wprev = w
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.9
	mesh.surface_set_material(0, mat)
	return mesh


## A broadleaf jungle tree (or a bush when scaled small): a lumpy canopy on a short trunk, 1 m
## across before the instance scale; its colour comes from the instance.
func _tree_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 4
	var segs := 7
	var cy := 1.15
	var verts := []
	for r in rings + 1:
		var phi := PI * float(r) / rings
		var row := []
		for s in segs:
			var th := TAU * float(s) / segs
			var bump := 1.0 + 0.18 * sin(th * 3.0 + r * 1.7)
			row.append(Vector3(sin(phi) * cos(th) * 0.62 * bump, cy + cos(phi) * 0.42, sin(phi) * sin(th) * 0.62 * bump))
		verts.append(row)
	for r in rings:
		for s in segs:
			var a: Vector3 = verts[r][s]
			var b: Vector3 = verts[r][(s + 1) % segs]
			var c: Vector3 = verts[r + 1][(s + 1) % segs]
			var d: Vector3 = verts[r + 1][s]
			for v in [a, c, b, a, d, c]:
				st.set_color(Color(1, 1, 1))
				st.set_normal((v - Vector3(0, cy, 0)).normalized())
				st.add_vertex(v)
	# trunk
	for s in 4:
		var a0 := TAU * s / 4.0
		var a1 := TAU * (s + 1) / 4.0
		var q := [Vector3(cos(a0) * 0.07, 0, sin(a0) * 0.07), Vector3(cos(a1) * 0.07, 0, sin(a1) * 0.07), Vector3(cos(a1) * 0.05, 0.85, sin(a1) * 0.05), Vector3(cos(a0) * 0.05, 0.85, sin(a0) * 0.05)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(0.45, 0.4, 0.35))
			st.set_normal(Vector3(cos(a0), 0, sin(a0)))
			st.add_vertex(q[idx])
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mesh.surface_set_material(0, mat)
	return mesh


## Is the map point (x, z) on or within `pad` metres of one of the island's airfields?
static func _on_field(meta: Dictionary, x: float, z: float, pad: float) -> bool:
	for fd in meta.get("fields", []):
		var a := deg_to_rad(float(fd[2]))
		var dx: float = x - float(fd[0])
		var dz: float = z - float(fd[1])
		var along: float = dx * sin(a) - dz * cos(a)
		var across: float = dx * cos(a) + dz * sin(a)
		if absf(along) < float(fd[3]) * 0.5 + pad and absf(across) < float(fd[4]) * 0.5 + pad + 60.0:
			return true
	return false


## A house, shed or hangar 1 x 1 x 1 m before the instance scale: pale walls, a gable roof whose
## colour comes from the instance (rust-red iron, grey, thatch, green paint).
func _house_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := Color(0.80, 0.77, 0.70)
	var hw := 0.5
	var eave := 0.7
	var c := [Vector3(-hw, 0, -hw), Vector3(hw, 0, -hw), Vector3(hw, 0, hw), Vector3(-hw, 0, hw)]
	for k in 4:
		var a: Vector3 = c[k]
		var b: Vector3 = c[(k + 1) % 4]
		var nrm := (b - a).cross(Vector3.UP).normalized() * -1.0
		for v in [a, b, b + Vector3(0, eave, 0), a, b + Vector3(0, eave, 0), a + Vector3(0, eave, 0)]:
			st.set_color(wall)
			st.set_normal(nrm)
			st.add_vertex(v)
	# gable ends and roof (ridge along x)
	var ridge := 1.0
	for sx in [-1.0, 1.0]:
		var p0 := Vector3(sx * hw, eave, -hw)
		var p1 := Vector3(sx * hw, eave, hw)
		var p2 := Vector3(sx * hw, ridge, 0)
		for v in [p0, p1, p2]:
			st.set_color(wall)
			st.set_normal(Vector3(sx, 0, 0))
			st.add_vertex(v)
	var roof := Color(1, 1, 1)
	for sz in [-1.0, 1.0]:
		var q := [Vector3(-hw - 0.05, eave - 0.03, sz * (hw + 0.06)), Vector3(hw + 0.05, eave - 0.03, sz * (hw + 0.06)), Vector3(hw + 0.05, ridge, 0), Vector3(-hw - 0.05, ridge, 0)]
		var nrm2 := Vector3(0, hw, sz * (ridge - eave)).normalized()
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(roof)
			st.set_normal(nrm2)
			st.add_vertex(q[idx])
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	return mesh


# =====================================================================
# the old procedural islands (round, from a few parameters)
# =====================================================================

func _proc_height(isl: Dictionary, x: float, z: float) -> float:
	var d: float = U.hyp(x - isl.x, z - isl.z) / isl.r
	if d > 1.3:
		return -60.0
	var core: float = 1.0 - d
	_noise.seed = int(isl.seed)
	var nn := _noise.get_noise_2d(x, z)
	var edge := _noise.get_noise_2d(x * 1.6 + 500.0, z * 1.6) * 0.85 + _noise.get_noise_2d(x * 4.0 + 900.0, z * 4.0) * 0.15
	var shape: float = core + 0.26 * edge
	var hgt: float = isl.h * clampf(shape, -0.5, 1.0) * (1.0 if shape > 0.0 else 0.6) + nn * isl.h * 0.25 * maxf(shape, 0.0)
	if shape < 0.0:
		hgt = -1.0 + shape * 18.0 - maxf(d - 1.05, 0.0) * 60.0
	return hgt


func _build(isl: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := maxf(10.0, isl.r / 60.0)
	var n := int(isl.r * 1.3 * 2.0 / step)
	var x0: float = isl.x - isl.r * 1.3
	var z0: float = isl.z - isl.r * 1.3
	for i in n:
		for j in n:
			var xa := x0 + i * step
			var za := z0 + j * step
			var hs := [_proc_height(isl, xa, za), _proc_height(isl, xa + step, za), _proc_height(isl, xa + step, za + step), _proc_height(isl, xa, za + step)]
			if hs.max() < -9.0:
				continue
			var pts := [Vector3(xa, hs[0], za), Vector3(xa + step, hs[1], za), Vector3(xa + step, hs[2], za + step), Vector3(xa, hs[3], za + step)]
			for tri in [[0, 2, 1], [0, 3, 2]]:
				var order: Array = tri
				var nrm: Vector3 = (pts[order[1]] - pts[order[0]]).cross(pts[order[2]] - pts[order[0]]).normalized()
				if nrm.y < 0.0:
					order = [tri[0], tri[2], tri[1]]
					nrm = -nrm
				for k in order:
					st.set_normal(nrm)
					st.set_color(_color(pts[k].y, nrm.y, isl.h))
					var v: Vector3 = pts[k]
					if v.y < 0.0:
						v.y = 0.08 - (0.0 - v.y) * 0.004
					st.add_vertex(v)
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	add_child(mi)


func _color(y: float, slope: float, h: float) -> Color:
	if y < -0.2:
		var k0 := clampf((-y - 0.2) / 7.5, 0.0, 1.0)
		var c := Color(0.32, 0.72, 0.68).lerp(Color(0.12, 0.4, 0.5), k0)
		c.a = 1.0 - k0
		return c
	if y < 0.4:
		return Color(0.76, 0.70, 0.52)
	if y < 2.2:
		return Color(0.84, 0.78, 0.58)
	var k := clampf((y - 2.2) / maxf(1.0, h * 0.7), 0.0, 1.0)
	var green := Color(0.22, 0.40, 0.18).lerp(Color(0.16, 0.30, 0.14), k)
	var rock := Color(0.42, 0.40, 0.36)
	return green.lerp(rock, clampf((1.0 - slope) * 2.5 + k * 0.5 - 0.4, 0.0, 1.0))
