class_name Terrain
extends Node3D
## Islands: a few parameters make a hill of sand, scrub and rock rising out of the sea.
## height_at() is the ground truth for grounding, shore targets and shells landing on the beach.

var islands: Array = []      # {x, z, r, h, seed}
var _noise := FastNoiseLite.new()


func setup(list: Array) -> void:
	for c in get_children():
		c.queue_free()
	islands = list.duplicate(true)
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0022
	for isl in islands:
		_build(isl)


func height_at(x: float, z: float) -> float:
	var best := -30.0
	for isl in islands:
		var d: float = U.hyp(x - isl.x, z - isl.z) / isl.r
		if d > 1.3:
			continue
		var core: float = 1.0 - d
		_noise.seed = int(isl.seed)
		var n := _noise.get_noise_2d(x, z)            # -1..1
		var edge := _noise.get_noise_2d(x * 1.6 + 500.0, z * 1.6) * 0.85 + _noise.get_noise_2d(x * 4.0 + 900.0, z * 4.0) * 0.15
		var shape: float = core + 0.26 * edge                 # ragged coastline, bays and points
		var hgt: float = isl.h * clampf(shape, -0.5, 1.0) * (1.0 if shape > 0.0 else 0.6) + n * isl.h * 0.25 * maxf(shape, 0.0)
		if shape < 0.0:
			# the reef shelf: shallow for a way out, then falling to the seabed
			hgt = -1.0 + shape * 18.0 - maxf(d - 1.05, 0.0) * 60.0
		best = maxf(best, hgt)
	return best


func is_land(x: float, z: float) -> bool:
	return height_at(x, z) > 0.0


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
			var hs := [height_at(xa, za), height_at(xa + step, za), height_at(xa + step, za + step), height_at(xa, za + step)]
			if hs.max() < -9.0:
				continue
			var pts := [Vector3(xa, hs[0], za), Vector3(xa + step, hs[1], za), Vector3(xa + step, hs[2], za + step), Vector3(xa, hs[3], za + step)]
			for tri in [[0, 2, 1], [0, 3, 2]]:
				var order: Array = tri
				var nrm: Vector3 = (pts[order[1]] - pts[order[0]]).cross(pts[order[2]] - pts[order[0]]).normalized()
				if nrm.y < 0.0:
					# wind the triangle so its face points up, or the renderer culls it (the
					# island was invisible from above before this)
					order = [tri[0], tri[2], tri[1]]
					nrm = -nrm
				for k in order:
					st.set_normal(nrm)
					st.set_color(_color(pts[k].y, nrm.y, isl.h))
					# the shallows are drawn just above the sea surface (the sea plane is opaque)
					# while height_at keeps their true depth for grounding
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
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # whichever way the grid is wound, the land shows
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA   # the reef shelf fades into the open sea
	mi.material_override = mat
	add_child(mi)


func _color(y: float, slope: float, h: float) -> Color:
	if y < -0.2:
		# the reef and lagoon: turquoise shallows fading to the deep water colour
		var k0 := clampf((-y - 0.2) / 7.5, 0.0, 1.0)
		var c := Color(0.32, 0.72, 0.68).lerp(Color(0.12, 0.4, 0.5), k0)
		c.a = 1.0 - k0
		return c
	if y < 0.4:
		return Color(0.76, 0.70, 0.52)          # wet sand
	if y < 2.2:
		return Color(0.84, 0.78, 0.58)          # beach
	var k := clampf((y - 2.2) / maxf(1.0, h * 0.7), 0.0, 1.0)
	var green := Color(0.22, 0.40, 0.18).lerp(Color(0.16, 0.30, 0.14), k)
	var rock := Color(0.42, 0.40, 0.36)
	return green.lerp(rock, clampf((1.0 - slope) * 2.5 + k * 0.5 - 0.4, 0.0, 1.0))
