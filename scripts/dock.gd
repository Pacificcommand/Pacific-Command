class_name DockPanel
extends Control
## In port: the home base. A 3D harbour with your ship moored alongside the quay, sailors
## hauling stores and ammunition aboard, mopping the deck and sighting the guns, a crane
## swinging cargo over. Along the quay the captain and the officers stand in a line; picking
## one pans the camera to them, they salute, and their medals show over their heads.
## The port's business (repair, refit, a new command, recruiting) is done from here.
##
## World: the ship lies at the origin with her bow toward +x, starboard toward +z; the quay
## runs along her port side (negative z). Metres, y up from the waterline.

var ops                                  # the operations map that opened us
var port_name := ""
var view: SubViewport
var root3d: Node3D
var cam: Camera3D
var ship_root: Node3D
var model: Node3D
var T: Dictionary
var L := 100.0
var Bm := 11.0
var t := 0.0

# deck height map (ship footprint, 0.5 m cells)
const CELL := 0.5
var hm := PackedFloat32Array()
var hm_x0 := 0.0
var hm_z0 := 0.0
var hm_nx := 0
var hm_nz := 0
var deck_y := 3.0
var walk_cells: Array = []               # Vector2 (x, z) of open main-deck cells

# quay layout
const QUAY_Y := 2.0
var quay_z := -8.0                       # z of the quay edge
var gang_top := Vector3.ZERO
var gang_bot := Vector3.ZERO
var into_side := false                   # the brow ends at a door in the ship's side

var mounts: Array = []                   # [node, stow, phase]
var crane_jib: Node3D
var crane_load: Node3D
var crane_cable: MeshInstance3D
var crew: Array = []                     # {node, parts, task, ...}
var lineup: Array = []                   # {node, parts, who: "captain" or officer Dictionary, pos}

# camera
var sel := -1                            # -1 = the ship, 0 = captain, 1.. = officers
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO
var cam_pos_t := Vector3.ZERO
var cam_look_t := Vector3.ZERO
var salute_t := 0.0

# UI
var info_box: VBoxContainer
var actions_box: VBoxContainer
var person_box: VBoxContainer
var person_panel: PanelContainer
var sel_buttons: Array = []
var overlay: Control
var bar_ref: Control

var _mats := {}
static var _hm_cache := {}


func _init(p_ops = null, p_port := "") -> void:
	ops = p_ops
	port_name = p_port


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var c: Dictionary = Game.career
	var cs := Career.ship(c)
	var type_id: String = cs.get("type", "fletcher")
	if not Data.TYPES.has(type_id):
		type_id = "fletcher"
	T = Data.TYPES[type_id]
	L = float(T.L)
	Bm = float(T.get("B", L * 0.1))
	_build_view()
	_build_world()
	_load_ship()
	_build_heightmap(type_id)
	_build_quay()
	_build_crew()
	_build_lineup()
	_build_ui()
	_select(-1, true)
	Audio.ui("radio", 0.4, "Radio")


func _input(e: InputEvent) -> void:
	if Game.pressed(e, "menu"):
		accept_event()
		close()


func close() -> void:
	if ops and ops.has_method("_refresh_side"):
		ops._refresh_side()
	queue_free()


# =====================================================================
# the 3D world
# =====================================================================

func _build_view() -> void:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	view = SubViewport.new()
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_4X
	box.add_child(view)
	root3d = Node3D.new()
	view.add_child(root3d)
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.2
	cam.far = 6000.0
	root3d.add_child(cam)
	cam.make_current()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.52, 0.78)
	sm.sky_horizon_color = Color(0.72, 0.8, 0.86)
	sm.ground_horizon_color = Color(0.6, 0.68, 0.72)
	sm.ground_bottom_color = Color(0.2, 0.3, 0.36)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.7, 0.78)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.8, 0.86)
	env.fog_density = 0.0009
	var we := WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = clampf(L * 1.8, 200.0, 480.0)
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.0
	root3d.add_child(sun)
	sun.look_at_from_position(Vector3(-40, 80, -70), Vector3.ZERO, Vector3.UP)
	# harbour water: the battle sea shader, calm
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(5000, 5000)
	pm.subdivide_width = 2
	pm.subdivide_depth = 2
	sea.mesh = pm
	var om := ShaderMaterial.new()
	om.shader = load("res://shaders/ocean.gdshader")
	om.set_shader_parameter("foam_tex", load("res://assets/textures/boujie/foam_2.png"))
	om.set_shader_parameter("detail_tex", load("res://assets/textures/boujie/ocean_albedo_2.png"))
	om.set_shader_parameter("deep_color", Color(0.03, 0.13, 0.19))
	om.set_shader_parameter("shallow_color", Color(0.07, 0.24, 0.3))
	om.set_shader_parameter("chop", 0.3)
	om.set_shader_parameter("spec", 0.4)
	sea.material_override = om
	sea.set_meta("ocean", om)
	sea.name = "Sea"
	root3d.add_child(sea)
	# distant hills and the far shore
	for i in 9:
		var hill := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 1.0
		sp.height = 2.0
		hill.mesh = sp
		var hx := -900.0 + i * 230.0 + randf_range(-60, 60)
		hill.position = Vector3(hx, -20.0, -900.0 - randf_range(0, 300))
		hill.scale = Vector3(randf_range(220, 380), randf_range(90, 190), randf_range(120, 220))
		hill.material_override = _mat(Color(0.32, 0.42, 0.3).lerp(Color(0.45, 0.5, 0.42), randf()), 1.0)
		root3d.add_child(hill)


func _load_ship() -> void:
	ship_root = Node3D.new()
	ship_root.transform.basis = Basis(Vector3.UP, -PI / 2.0)      # bow to +x
	root3d.add_child(ship_root)
	var models: Dictionary = T.get("models", {})
	if models.is_empty():
		return
	var path: String = models.values()[0]
	if not ResourceLoader.exists(path):
		return
	model = (load(path) as PackedScene).instantiate()
	ship_root.add_child(model)
	var parts := {}
	_collect(model, parts)
	for m in T.get("mounts", []):
		var n = parts.get(m.g)
		if n != null:
			mounts.append([n, float(m.get("stow", 0.0)), randf() * TAU])


func _collect(n: Node, out: Dictionary) -> void:
	for c in n.get_children():
		if c is Node3D:
			out[String(c.name)] = c
		_collect(c, out)


# ---------- deck heights from the model's triangles ----------

func _build_heightmap(type_id: String) -> void:
	hm_x0 = -L / 2.0 - 4.0
	hm_z0 = -Bm / 2.0 - 4.0
	hm_nx = int(ceil((L + 8.0) / CELL))
	hm_nz = int(ceil((Bm + 8.0) / CELL))
	if _hm_cache.has(type_id):
		hm = _hm_cache[type_id]
	else:
		hm = PackedFloat32Array()
		hm.resize(hm_nx * hm_nz)
		hm.fill(-99.0)
		if model:
			var t0 := Time.get_ticks_msec()
			_raster(model, ship_root.transform * model.transform)
			print("dock: deck heights for %s in %d ms" % [type_id, Time.get_ticks_msec() - t0])
		_hm_cache[type_id] = hm
	# the main deck: the commonest height on the ship's footprint
	var hist := {}
	for v in hm:
		if v > 0.3:
			var k := int(round(v * 4.0))
			hist[k] = hist.get(k, 0) + 1
	var best := 0
	var bk := int(round(3.0 * 4.0))
	for k in hist:
		if hist[k] > best:
			best = hist[k]; bk = k
	deck_y = float(bk) / 4.0
	walk_cells.clear()
	for iz in hm_nz:
		for ix in hm_nx:
			var v: float = hm[iz * hm_nx + ix]
			if absf(v - deck_y) < 0.35:
				walk_cells.append(Vector2(hm_x0 + (ix + 0.5) * CELL, hm_z0 + (iz + 0.5) * CELL))


func _raster(n: Node, xf: Transform3D) -> void:
	for c in n.get_children():
		if not c is Node3D:
			continue
		var cx: Transform3D = xf * (c as Node3D).transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
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
						_tri(w[i], w[i + 1], w[i + 2])
				else:
					var ix: PackedInt32Array = idx
					for i in range(0, ix.size() - 2, 3):
						_tri(w[ix[i]], w[ix[i + 1]], w[ix[i + 2]])
		_raster(c, cx)


func _tri(a: Vector3, b: Vector3, c: Vector3) -> void:
	var minx := minf(a.x, minf(b.x, c.x))
	var maxx := maxf(a.x, maxf(b.x, c.x))
	var minz := minf(a.z, minf(b.z, c.z))
	var maxz := maxf(a.z, maxf(b.z, c.z))
	var den := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(den) < 1e-6:
		return
	var ix0 := maxi(0, int((minx - hm_x0) / CELL))
	var ix1 := mini(hm_nx - 1, int((maxx - hm_x0) / CELL))
	var iz0 := maxi(0, int((minz - hm_z0) / CELL))
	var iz1 := mini(hm_nz - 1, int((maxz - hm_z0) / CELL))
	for iz in range(iz0, iz1 + 1):
		var pz := hm_z0 + (iz + 0.5) * CELL
		for ix in range(ix0, ix1 + 1):
			var px := hm_x0 + (ix + 0.5) * CELL
			var w1 := ((b.z - c.z) * (px - c.x) + (c.x - b.x) * (pz - c.z)) / den
			var w2 := ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / den
			var w3 := 1.0 - w1 - w2
			if w1 < -0.001 or w2 < -0.001 or w3 < -0.001:
				continue
			var y := w1 * a.y + w2 * b.y + w3 * c.y
			var k := iz * hm_nx + ix
			if y > hm[k]:
				hm[k] = y


## Height of the ship's top surface at (x, z); the main deck where nothing is there.
func height_at(x: float, z: float) -> float:
	var ix := int((x - hm_x0) / CELL)
	var iz := int((z - hm_z0) / CELL)
	if ix < 0 or iz < 0 or ix >= hm_nx or iz >= hm_nz:
		return deck_y
	var v: float = hm[iz * hm_nx + ix]
	if v < 0.0 or v > deck_y + 2.5:
		return deck_y
	return v


func _deck_spot(x_target: float, z_target: float, rng: float) -> Vector2:
	var best := Vector2(x_target, 0.0)
	var bd := 1e9
	for i in 40:
		if walk_cells.is_empty():
			break
		var c: Vector2 = walk_cells[randi() % walk_cells.size()]
		var d := absf(c.x - x_target) + absf(c.y - z_target) * 0.5 + randf() * rng
		if d < bd:
			bd = d; best = c
	return best


# ---------- the quay ----------

func _build_quay() -> void:
	quay_z = -Bm / 2.0 - 2.2
	var qlen := maxf(L * 1.6, 160.0)
	var shed_back := maxf(66.0, L * 0.5 + 20.0)
	var qdepth := shed_back + 14.0
	_box(Vector3(qlen, QUAY_Y + 3.0, qdepth), Vector3(0, (QUAY_Y - 3.0) / 2.0, quay_z - qdepth / 2.0), Color(0.4, 0.39, 0.36))
	# expansion joints in the concrete
	for i in int(qlen / 8.0):
		_box(Vector3(0.08, 0.02, qdepth), Vector3(-qlen / 2.0 + i * 8.0, QUAY_Y + 0.01, quay_z - qdepth / 2.0), Color(0.3, 0.29, 0.27))
	# rail tracks for the crane along the edge
	for rz in [quay_z - 1.9, quay_z - 7.1]:
		_box(Vector3(qlen, 0.08, 0.14), Vector3(0, QUAY_Y + 0.04, rz), Color(0.3, 0.28, 0.26))
	# a darker strip of wet stone at the waterline and a curb
	_box(Vector3(qlen, 0.25, 0.5), Vector3(0, QUAY_Y + 0.12, quay_z - 0.25), Color(0.72, 0.7, 0.62))
	# fenders (timber) and bollards with mooring lines
	var nf := int(qlen / 9.0)
	for i in nf:
		var fx := -qlen / 2.0 + 4.5 + i * 9.0
		_box(Vector3(0.6, 2.4, 0.5), Vector3(fx, QUAY_Y - 1.1, quay_z + 0.2), Color(0.32, 0.24, 0.16))
	for fx in [L * 0.42, L * 0.18, -L * 0.22, -L * 0.44]:
		var bp := Vector3(fx + (6.0 if fx > 0 else -6.0), QUAY_Y, quay_z - 1.4)
		_cyl(0.32, 0.8, bp + Vector3(0, 0.4, 0), Color(0.12, 0.12, 0.13))
		var on_ship := Vector3(fx, height_at(fx, -Bm * 0.35) + 0.4, -Bm * 0.36)
		_rope(bp + Vector3(0, 0.7, 0), on_ship)
	# gangway from the quay up (or down) to the deck, abreast the after superstructure
	var gx := -L * 0.12
	var top := _deck_spot(gx, -Bm / 2.0, 0.0)
	var edge_z := top.y
	for c in walk_cells:
		if absf(c.x - gx) < 1.2 and c.y < edge_z:
			edge_z = c.y
	gang_top = Vector3(gx, deck_y, edge_z + 0.6)
	if deck_y > QUAY_Y + 6.0:
		# a carrier or a big ship: the brow runs to a door in the side, not up to the flight deck
		gang_top = Vector3(gx, QUAY_Y + 5.0, -Bm / 2.0 + 0.2)
		into_side = true
	gang_bot = Vector3(gx - 5.0, QUAY_Y, quay_z - 3.0)
	_plank(gang_bot, gang_top, 1.3, Color(0.45, 0.35, 0.24))
	# sheds behind the quay
	for i in 3:
		var sx := -qlen * 0.33 + i * qlen * 0.33
		var sz := quay_z - shed_back
		_box(Vector3(qlen * 0.28, 9.0, 16.0), Vector3(sx, QUAY_Y + 4.5, sz), Color(0.52, 0.48, 0.4).lerp(Color(0.46, 0.44, 0.4), i * 0.4))
		_box(Vector3(qlen * 0.29, 0.6, 17.0), Vector3(sx, QUAY_Y + 9.3, sz), Color(0.34, 0.2, 0.15))
		for d in 3:
			_box(Vector3(4.0, 5.0, 0.2), Vector3(sx - qlen * 0.09 + d * qlen * 0.09, QUAY_Y + 2.5, sz + 8.05), Color(0.28, 0.32, 0.3))
	# stores and ammunition waiting on the quay
	_stack(Vector3(gx - 16.0, QUAY_Y, quay_z - 12.0), Color(0.55, 0.45, 0.3), 4, 3)
	_stack(Vector3(gx + 18.0, QUAY_Y, quay_z - 13.0), Color(0.48, 0.5, 0.36), 3, 2)
	for i in 6:
		var p := Vector3(gx - 4.0 + (i % 3) * 1.3, QUAY_Y, quay_z - 9.0 - int(i / 3.0) * 1.3)
		_box(Vector3(1.1, 0.15, 1.1), p + Vector3(0, 0.08, 0), Color(0.5, 0.4, 0.28))
		for s in 4:
			_cyl(0.16, 0.9, p + Vector3(-0.3 + (s % 2) * 0.6, 0.6, -0.3 + int(s / 2.0) * 0.6), Color(0.58, 0.5, 0.25))
	for i in 8:
		_cyl(0.32, 0.9, Vector3(gx + 30.0 + (i % 4) * 0.75, QUAY_Y + 0.45, quay_z - 6.0 - int(i / 4.0) * 0.75), Color(0.35, 0.4, 0.3).lerp(Color(0.6, 0.2, 0.15), float(i % 3 == 0)))
	# lamp posts
	for i in 6:
		var lx := -qlen / 2.0 + 15.0 + i * (qlen - 30.0) / 5.0
		_cyl(0.12, 7.0, Vector3(lx, QUAY_Y + 3.5, quay_z - 5.0), Color(0.15, 0.17, 0.16))
		_box(Vector3(0.6, 0.35, 0.6), Vector3(lx, QUAY_Y + 7.1, quay_z - 5.0), Color(0.2, 0.22, 0.2))
	# palms at the shore end
	for i in 7:
		_palm(Vector3(-qlen / 2.0 + 8.0 + i * 13.0 + randf_range(-3, 3), QUAY_Y, quay_z - shed_back + 16.0 - randf_range(0, 4)))
		_palm(Vector3(qlen / 2.0 - 8.0 - i * 11.0 + randf_range(-3, 3), QUAY_Y, quay_z - shed_back + 14.0 - randf_range(0, 4)))
	_build_crane(Vector3(maxf(L * 0.36, 34.0), QUAY_Y, quay_z - 4.5))


func _build_crane(base: Vector3) -> void:
	# a portal crane on rails: four legs, a tower, a turning cab with the jib
	for dx in [-2.6, 2.6]:
		for dz in [-2.6, 2.6]:
			_box(Vector3(0.5, 9.0, 0.5), base + Vector3(dx, 4.5, dz), Color(0.62, 0.42, 0.12))
	_box(Vector3(6.0, 0.8, 6.0), base + Vector3(0, 9.2, 0), Color(0.62, 0.42, 0.12))
	var cab := Node3D.new()
	cab.position = base + Vector3(0, 9.6, 0)
	root3d.add_child(cab)
	crane_jib = cab
	var body := _box(Vector3(4.0, 3.0, 3.6), Vector3(0, 1.5, 0), Color(0.68, 0.48, 0.15), cab)
	body.name = "Cab"
	var jl := maxf(22.0, Bm + 14.0)
	var jib := _box(Vector3(jl, 0.7, 0.9), Vector3(jl / 2.0, 3.4, 0), Color(0.66, 0.46, 0.14), cab)
	jib.rotation.z = deg_to_rad(10.0)
	cab.set_meta("tip", Vector3(cos(deg_to_rad(10.0)) * jl, 3.4 + sin(deg_to_rad(10.0)) * jl, 0))
	crane_load = Node3D.new()
	root3d.add_child(crane_load)
	_box(Vector3(2.2, 0.15, 2.2), Vector3(0, 0, 0), Color(0.45, 0.36, 0.24), crane_load)
	for i in 4:
		_box(Vector3(0.95, 0.75, 0.95), Vector3(-0.5 + (i % 2), 0.45, -0.5 + int(i / 2.0)), Color(0.58, 0.47, 0.3), crane_load)
	crane_cable = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.04
	cm.height = 1.0
	crane_cable.mesh = cm
	crane_cable.material_override = _mat(Color(0.1, 0.1, 0.1), 0.6)
	root3d.add_child(crane_cable)


func _step_crane(dt: float) -> void:
	if crane_jib == null:
		return
	# swing between the quay stores and the ship's deck, the load riding up and down
	# hoist at the quay, swing over, lower onto the deck, hoist, swing back, lower
	var cyc := fmod(t * 0.045, 1.0)
	var swing := smoothstep(0.1, 0.4, cyc) - smoothstep(0.6, 0.9, cyc)      # 0 over the quay, 1 over the ship
	var up := smoothstep(0.0, 0.1, cyc) - smoothstep(0.4, 0.5, cyc) + smoothstep(0.5, 0.6, cyc) - smoothstep(0.9, 1.0, cyc)
	crane_jib.rotation.y = lerpf(deg_to_rad(110.0), deg_to_rad(-72.0), swing)
	var tip: Vector3 = crane_jib.global_transform * (crane_jib.get_meta("tip") as Vector3)
	var low: float = lerpf(QUAY_Y + 0.1, deck_y + 0.2, swing)
	var ly: float = lerpf(low, tip.y - 4.0, up)
	crane_load.position = Vector3(tip.x, ly, tip.z)
	var mid := (tip + crane_load.position + Vector3(0, 1.0, 0)) / 2.0
	crane_cable.position = mid
	crane_cable.scale = Vector3(1, maxf(0.1, tip.y - crane_load.position.y - 1.0), 1)


# =====================================================================
# the sailors
# =====================================================================

## A cartoon sailor: big round head, short body, swinging arms and legs.
## look: shirt, pants, skin, hat ("dixie", "officer", "garrison", "helmet", "dc_helmet",
## "ballcap", "flight", "none"), hat_col, prop ("crate", "shell", "mop", "clipboard",
## "binoculars", "wrench", "chart", "axe", "torpedo", "phones", "goggles", ""), scale.
func _figure(look: Dictionary) -> Dictionary:
	var n := Node3D.new()
	root3d.add_child(n)
	var sc: float = look.get("scale", 1.0)
	n.scale = Vector3(sc, sc, sc)
	var shirt: Color = look.get("shirt", Color(0.25, 0.36, 0.6))
	var pants: Color = look.get("pants", Color(0.14, 0.18, 0.32))
	var skin: Color = look.get("skin", Color(0.93, 0.76, 0.62))
	var parts := {}
	for s in [-1, 1]:
		var hip := Node3D.new()
		hip.position = Vector3(0, 0.78, 0.12 * s)
		n.add_child(hip)
		_capsule(0.1, 0.72, Vector3(0, -0.36, 0), pants, hip)
		_box(Vector3(0.24, 0.1, 0.14), Vector3(0.05, -0.74, 0), look.get("shoes", Color(0.08, 0.07, 0.06)), hip)
		parts["leg%d" % s] = hip
	var body := Node3D.new()
	n.add_child(body)
	parts.body = body
	_capsule(0.24, 0.72, Vector3(0, 1.12, 0), shirt, body)
	if look.get("collar", false):
		_box(Vector3(0.3, 0.12, 0.42), Vector3(-0.12, 1.42, 0), Color(0.14, 0.2, 0.42), body)
	for s in [-1, 1]:
		var sh := Node3D.new()
		sh.position = Vector3(0, 1.38, 0.3 * s)
		body.add_child(sh)
		_capsule(0.075, 0.6, Vector3(0, -0.28, 0), shirt, sh)
		_sphere(0.075, Vector3(0, -0.6, 0), skin, sh)
		parts["arm%d" % s] = sh
	if look.has("uniform"):
		_uniform(String(look.uniform), look, parts)
	var head := Node3D.new()
	head.position = Vector3(0, 1.72, 0)
	body.add_child(head)
	parts.head = head
	_sphere(0.27, Vector3.ZERO, skin, head)
	# a face looking forward (+x): eyes, nose, a small smile, ears
	for s in [-1, 1]:
		_sphere(0.035, Vector3(0.24, 0.04, 0.09 * s), Color(0.08, 0.08, 0.1), head)
		_sphere(0.06, Vector3(0.0, 0.0, 0.26 * s), skin.darkened(0.08), head)
	_sphere(0.045, Vector3(0.27, -0.03, 0), skin.darkened(0.1), head)
	var smile := _sphere(0.05, Vector3(0.235, -0.12, 0), Color(0.45, 0.18, 0.16), head)
	smile.scale = Vector3(0.4, 0.35, 1.4)
	_hat(look.get("hat", "dixie"), look.get("hat_col", Color(0.97, 0.97, 0.94)), head)
	var prop: String = look.get("prop", "")
	if prop != "":
		_prop(prop, parts)
	return {"node": n, "parts": parts, "prop": prop, "ph": randf() * TAU}


## Low-detail uniform touches on the torso and arms (the figure faces +x, its right is +z).
## style: "khaki" officers' working khakis, "coveralls", "flight" (leather jacket and Mae West),
## "kapok" (khakis under a grey life jacket); extras by look: "rank" (silver bars or eagle),
## "ribbons" (colours for a small rack over the left pocket), "gasbag", "pencils".
func _uniform(style: String, look: Dictionary, parts: Dictionary) -> void:
	var body: Node3D = parts.body
	var shirt: Color = look.get("shirt", KHAKI)
	var dark := shirt.darkened(0.22)
	var silver := Color(0.82, 0.84, 0.86)
	var brass := Color(0.9, 0.72, 0.25)
	# rolled sleeves: a cuff band above each hand
	for s in [-1, 1]:
		_cyl(0.082, 0.06, Vector3(0, -0.47, 0), shirt.darkened(0.12), parts["arm%d" % s])
	match style:
		"khaki", "kapok":
			# collar points, a black tie, two breast pockets with flaps, a belt with a brass buckle
			for s in [-1, 1]:
				var cp := _box(Vector3(0.03, 0.09, 0.1), Vector3(0.2, 1.47, 0.075 * s), dark, body)
				cp.rotation.x = 0.5 * s
				if look.get("rank", "") != "":
					var ins := _box(Vector3(0.02, 0.025, 0.04 if look.rank == "eagle" else 0.022), Vector3(0.215, 1.45, 0.085 * s), silver, body)
					ins.rotation.x = 0.5 * s
			_box(Vector3(0.02, 0.3, 0.05), Vector3(0.245, 1.28, 0), Color(0.06, 0.06, 0.07), body)
			_box(Vector3(0.022, 0.05, 0.06), Vector3(0.247, 1.42, 0), Color(0.06, 0.06, 0.07), body)
			for s in [-1, 1]:
				_box(Vector3(0.025, 0.11, 0.1), Vector3(0.232, 1.3, 0.12 * s), shirt.darkened(0.06), body)
				_box(Vector3(0.032, 0.035, 0.11), Vector3(0.236, 1.355, 0.12 * s), dark, body)
			_cyl(0.247, 0.055, Vector3(0, 0.9, 0), look.get("pants", KHAKI_D).darkened(0.25), body)
			_box(Vector3(0.025, 0.06, 0.07), Vector3(0.25, 0.9, 0), brass, body)
			if style == "kapok":
				# the grey kapok life jacket over the shirt, open at the front
				var kap := _cyl(0.275, 0.4, Vector3(-0.03, 1.2, 0), Color(0.42, 0.46, 0.44), body)
				kap.scale = Vector3(1.0, 1.0, 1.0)
				for yy in [1.08, 1.3]:
					_box(Vector3(0.03, 0.035, 0.14), Vector3(0.245, yy, 0), Color(0.3, 0.33, 0.32), body)
		"coveralls":
			# zip down the front, a chest pocket, a grease smudge, knee patches
			_box(Vector3(0.015, 0.6, 0.025), Vector3(0.245, 1.12, 0), Color(0.72, 0.74, 0.76), body)
			_box(Vector3(0.025, 0.12, 0.11), Vector3(0.232, 1.3, -0.12), shirt.darkened(0.12), body)
			var smudge := _sphere(0.045, Vector3(0.235, 1.02, 0.11), shirt.darkened(0.45), body)
			smudge.scale = Vector3(0.2, 0.6, 1.0)
			for s in [-1, 1]:
				_box(Vector3(0.03, 0.12, 0.13), Vector3(0.09, -0.38, 0), shirt.darkened(0.18), parts["leg%d" % s])
		"flight":
			# leather jacket with a fleece collar, the yellow Mae West, a squadron patch
			_cyl(0.21, 0.09, Vector3(0, 1.47, 0), Color(0.86, 0.8, 0.66), body)
			_box(Vector3(0.015, 0.55, 0.02), Vector3(0.247, 1.14, 0), Color(0.25, 0.17, 0.1), body)
			for s in [-1, 1]:
				_box(Vector3(0.07, 0.24, 0.13), Vector3(0.225, 1.28, 0.115 * s), Color(0.96, 0.78, 0.15), body)
			_cyl(0.25, 0.06, Vector3(0, 1.15, 0), Color(0.9, 0.72, 0.13), body)
			var patch := _cyl(0.045, 0.02, Vector3(0.0, 1.22, -0.25), Color(0.2, 0.3, 0.65), body)
			patch.rotation.x = PI / 2.0
	# medal ribbons over the left breast pocket: the holder's real decorations
	var rib: Array = look.get("ribbons", [])
	for i in mini(rib.size(), 6):
		var cols: Array = rib[i]
		var row := int(i / 3)
		var col_i := i % 3
		var cz := -0.12 + (col_i - 1) * 0.045
		_box(Vector3(0.012, 0.022, 0.042), Vector3(0.247, 1.405 + row * 0.026, cz), cols[0], body)
		if cols.size() > 1:
			_box(Vector3(0.014, 0.022, 0.01), Vector3(0.248, 1.405 + row * 0.026, cz), cols[1], body)
	if look.get("gasbag", false):
		# gas mask bag on a strap over the right shoulder
		_box(Vector3(0.14, 0.16, 0.09), Vector3(0.08, 0.98, -0.29), Color(0.38, 0.4, 0.28), body)
		var strap := _box(Vector3(0.02, 0.7, 0.04), Vector3(0.2, 1.2, 0.0), Color(0.34, 0.36, 0.25), body)
		strap.rotation.x = -0.55
	if look.get("pencils", false):
		for k in 2:
			_cyl(0.008, 0.09, Vector3(0.238, 1.38, 0.1 + k * 0.025), Color(0.95, 0.8, 0.2) if k == 0 else Color(0.2, 0.3, 0.6), body)


func _hat(kind: String, col: Color, head: Node3D) -> void:
	match kind:
		"dixie":
			_cyl(0.2, 0.14, Vector3(0, 0.25, 0), col, head)
			_cyl(0.27, 0.05, Vector3(0, 0.2, 0), col, head)
		"officer":
			_cyl(0.3, 0.1, Vector3(0, 0.27, 0), col, head)
			_cyl(0.25, 0.12, Vector3(0, 0.19, 0), Color(0.1, 0.1, 0.12), head)
			_box(Vector3(0.18, 0.03, 0.34), Vector3(0.26, 0.15, 0), Color(0.08, 0.08, 0.08), head)
			_sphere(0.05, Vector3(0.29, 0.22, 0), Color(0.95, 0.78, 0.25), head)
			if col.v > 0.9:
				# a commander's "scrambled eggs": gold oak leaves on the visor
				_box(Vector3(0.12, 0.012, 0.3), Vector3(0.29, 0.168, 0), Color(0.92, 0.74, 0.22), head)
		"garrison":
			_box(Vector3(0.44, 0.12, 0.22), Vector3(0, 0.24, 0), col, head)
		"helmet", "dc_helmet":
			var hm2 := _sphere(0.31, Vector3(0, 0.08, 0), col, head)
			hm2.scale = Vector3(1, 0.75, 1)
			_cyl(0.36, 0.03, Vector3(0, 0.04, 0), col.darkened(0.15), head)
			if kind == "dc_helmet":
				_cyl(0.315, 0.05, Vector3(0, 0.12, 0), Color(0.8, 0.12, 0.1), head)
		"ballcap":
			var bc := _sphere(0.28, Vector3(0, 0.12, 0), col, head)
			bc.scale = Vector3(1, 0.6, 1)
			_box(Vector3(0.24, 0.03, 0.28), Vector3(0.28, 0.1, 0), col.darkened(0.2), head)
		"flight":
			var fl := _sphere(0.295, Vector3(0, 0.05, 0), col, head)
			fl.scale = Vector3(1, 0.9, 1)
			for s in [-1, 1]:
				var gg := _cyl(0.08, 0.05, Vector3(0.19, 0.18, 0.09 * s), Color(0.6, 0.75, 0.8), head)
				gg.rotation.z = PI / 2.0
		"civil":
			_cyl(0.22, 0.12, Vector3(0, 0.25, 0), col, head)
			_box(Vector3(0.2, 0.03, 0.3), Vector3(0.24, 0.2, 0), col, head)


func _prop(kind: String, parts: Dictionary) -> void:
	var r: Node3D = parts["arm1"]
	var l: Node3D = parts["arm-1"]
	match kind:
		"crate":
			var b := _box(Vector3(0.5, 0.42, 0.5), Vector3(0.38, 1.18, 0), Color(0.6, 0.48, 0.3), parts.body)
			b.name = "Carry"
		"shell":
			var s := _cyl(0.13, 0.75, Vector3(0.36, 1.2, 0), Color(0.68, 0.58, 0.25), parts.body)
			s.rotation.z = PI / 2.0
			s.name = "Carry"
		"mop":
			var stick := _cyl(0.025, 1.5, Vector3(0.0, -0.75, 0), Color(0.55, 0.42, 0.25), r)
			stick.name = "Mop"
			_box(Vector3(0.12, 0.08, 0.45), Vector3(0.0, -1.5, 0), Color(0.92, 0.9, 0.8), r)
		"clipboard":
			_box(Vector3(0.05, 0.34, 0.26), Vector3(0.12, -0.6, 0), Color(0.45, 0.32, 0.2), l)
		"binoculars":
			for s in [-1, 1]:
				var bn := _cyl(0.045, 0.15, Vector3(0.06, -0.66, 0.05 * s), Color(0.1, 0.1, 0.1), l)
				bn.rotation.z = PI / 2.0
		"wrench":
			_box(Vector3(0.06, 0.55, 0.06), Vector3(0.0, -0.85, 0), Color(0.55, 0.55, 0.58), r)
			_box(Vector3(0.06, 0.12, 0.16), Vector3(0.0, -1.1, 0), Color(0.55, 0.55, 0.58), r)
		"chart":
			var ch := _cyl(0.05, 0.6, Vector3(0.05, -0.62, 0), Color(0.93, 0.9, 0.78), l)
			ch.rotation.x = PI / 2.0
		"axe":
			_cyl(0.025, 0.8, Vector3(0.0, -0.8, 0), Color(0.55, 0.4, 0.22), r)
			_box(Vector3(0.05, 0.16, 0.22), Vector3(0.0, -1.18, 0.08), Color(0.8, 0.12, 0.1), r)
		"torpedo":
			var tp := _cyl(0.07, 0.75, Vector3(0.08, -0.5, 0), Color(0.3, 0.32, 0.3), l)
			tp.rotation.x = PI / 2.0
			_box(Vector3(0.02, 0.16, 0.16), Vector3(0.08, -0.5, -0.4), Color(0.3, 0.32, 0.3), l)
		"phones":
			for s in [-1, 1]:
				var ph2 := _cyl(0.09, 0.06, Vector3(0, 0.02, 0.27 * s), Color(0.12, 0.12, 0.12), parts.head)
				ph2.rotation.x = PI / 2.0
			_box(Vector3(0.18, 0.08, 0.12), Vector3(0.24, -0.12, 0.0), Color(0.12, 0.12, 0.12), parts.head)


## Walk cycle, carrying pose, mopping, standing, saluting. `mode`: walk, carry, mop, stand, salute, sight.
func _pose(f: Dictionary, mode: String, ph: float, amt := 1.0) -> void:
	var p: Dictionary = f.parts
	var sw := sin(ph) * 0.55 * amt
	var walking := mode in ["walk", "carry"]
	(p["leg1"] as Node3D).rotation.z = sw if walking else 0.0
	(p["leg-1"] as Node3D).rotation.z = -sw if walking else 0.0
	(p.body as Node3D).position.y = absf(sin(ph)) * 0.05 * amt if walking else sin(ph * 0.3) * 0.008
	var ar: Node3D = p["arm1"]
	var al: Node3D = p["arm-1"]
	match mode:
		"walk":
			ar.rotation = Vector3(0, 0, -sw * 0.8)
			al.rotation = Vector3(0, 0, sw * 0.8)
		"carry":
			ar.rotation = Vector3(0.2, 0, 1.25)
			al.rotation = Vector3(-0.2, 0, 1.25)
		"mop":
			var m := sin(ph * 0.8)
			ar.rotation = Vector3(0.3 * m, 0, 0.55 + 0.25 * m)
			al.rotation = Vector3(-0.2, 0, 0.75 + 0.25 * m)
			(p.body as Node3D).rotation.z = -0.25 + 0.05 * m
			(p.body as Node3D).rotation.x = 0.06 * m
		"salute":
			ar.rotation = Vector3(-0.15, 0.0, 2.55)
			al.rotation = Vector3.ZERO
		"sight":
			ar.rotation = Vector3(0.25, 0, 1.55)
			al.rotation = Vector3(-0.25, 0, 1.55)
			(p.head as Node3D).rotation.y = sin(ph * 0.2) * 0.3
		_:
			var b := sin(ph * 0.5) * 0.04
			ar.rotation = Vector3(0, 0, b)
			al.rotation = Vector3(0, 0, -b)


const DUNGAREE := {"shirt": Color(0.42, 0.55, 0.74), "pants": Color(0.16, 0.2, 0.36), "hat": "dixie"}
const SKIN := [Color(0.95, 0.78, 0.64), Color(0.88, 0.68, 0.52), Color(0.72, 0.52, 0.38), Color(0.55, 0.38, 0.27), Color(0.97, 0.82, 0.7)]


func _sailor(extra: Dictionary) -> Dictionary:
	var look: Dictionary = DUNGAREE.duplicate()
	look.skin = SKIN[randi() % SKIN.size()]
	for k in extra:
		look[k] = extra[k]
	return _figure(look)


func _build_crew() -> void:
	# how many figures: a handful for a PT boat, a crowd for a carrier
	var budget := clampi(int(float(T.crew) / 10.0), 4, 42)
	var nb := clampi(int(budget * 0.3), 1, 10)
	var n_ammo := clampi(int(budget * 0.18), 1, 7)
	var n_mop := clampi(int(budget * 0.15), 1, 8)
	var n_gun := clampi(int(budget * 0.3), 1, 16)
	# stores party: from the crates up the gangway and back
	for i in nb:
		var f := _sailor({"prop": "crate"})
		f.task = "haul"
		f.src = Vector3(gang_bot.x - 14.0 + randf_range(-2, 2), QUAY_Y, quay_z - 10.5 + randf_range(-1, 1))
		var ds := _deck_spot(gang_top.x + randf_range(-8, 8), 0.0, 6.0)
		f.dst = Vector3(ds.x, 0, ds.y)
		f.u = float(i) / nb
		crew.append(f)
	# ammunition party: white skivvy shirts, shells on the shoulder
	for i in n_ammo:
		var f2 := _sailor({"shirt": Color(0.93, 0.93, 0.9), "prop": "shell"})
		f2.task = "haul"
		f2.src = Vector3(gang_bot.x + 1.0 + randf_range(-1, 1), QUAY_Y, quay_z - 9.5)
		var ds2 := _deck_spot(gang_top.x + randf_range(-6, 14), 0.0, 6.0)
		f2.dst = Vector3(ds2.x, 0, ds2.y)
		f2.u = float(i) / float(n_ammo) + 0.07
		crew.append(f2)
	# deck hands mopping fore and aft
	for i in n_mop:
		var f3 := _sailor({"prop": "mop", "shirt": Color(0.38, 0.5, 0.7)})
		f3.task = "mop"
		var at := _deck_spot(L * (0.32 if i % 2 == 0 else -0.36) + randf_range(-L * 0.06, L * 0.06), randf_range(-Bm * 0.2, Bm * 0.2), 2.0)
		f3.home = Vector3(at.x, 0, at.y)
		f3.dir = 1.0 if randf() < 0.5 else -1.0
		crew.append(f3)
	# gun crews sighting their mounts
	var gm := 0
	for m in mounts:
		if gm >= n_gun:
			break
		var mn: Node3D = m[0]
		var mp: Vector3 = mn.global_position
		for s in ([-1, 1] if n_gun >= mounts.size() * 2 else [-1]):
			var f4 := _sailor({"hat": "dixie"})
			f4.task = "sight"
			var off := Vector3(randf_range(-1.5, 1.5), 0, 2.2 * s)
			f4.home = Vector3(mp.x + off.x, 0, clampf(mp.z + off.z, -Bm * 0.42, Bm * 0.42))
			f4.face = mp
			crew.append(f4)
			gm += 1
	# lookouts and idlers at the rail, a dockyard man or two
	for i in (1 if budget < 10 else 3):
		var f5 := _sailor({"hat": "civil", "hat_col": Color(0.4, 0.32, 0.22), "shirt": Color(0.6, 0.52, 0.36), "pants": Color(0.4, 0.34, 0.24)})
		f5.task = "stroll"
		f5.home = Vector3(randf_range(-L * 0.5, L * 0.5), QUAY_Y, quay_z - randf_range(5, 18))
		f5.tgt = f5.home
		crew.append(f5)
	for f in crew:
		_place_static(f)


func _place_static(f: Dictionary) -> void:
	var n: Node3D = f.node
	match f.task:
		"mop", "sight":
			var h: Vector3 = f.home
			n.position = Vector3(h.x, height_at(h.x, h.z), h.z)
			if f.task == "sight":
				var fc: Vector3 = f.face
				n.rotation.y = atan2(-(fc.z - h.z), fc.x - h.x)
		_:
			pass


func _step_crew(dt: float) -> void:
	for f in crew:
		var n: Node3D = f.node
		f.ph += dt * 6.0
		match f.task:
			"haul":
				# one round trip: quay pile -> gangway foot -> top -> drop spot -> back
				f.u = fmod(f.u + dt * 1.3 / _trip_len(f), 1.0)
				var u: float = f.u
				var out := u < 0.5
				var k: float = u * 2.0 if out else (1.0 - u) * 2.0     # 0 at the pile, 1 at the drop
				var pts := [f.src, gang_bot, gang_top, Vector3(f.dst.x, deck_y, f.dst.z)]
				if into_side:
					pts = [f.src, gang_bot, gang_top]
				var p := _along(pts, k)
				n.visible = not (into_side and k > 0.97)
				var ahead := _along(pts, clampf(k + (0.01 if out else -0.01), 0.0, 1.0))
				if p.distance_to(gang_bot) > 0.3 and p.distance_to(gang_top) > 0.3 and _on_deck(p):
					p.y = height_at(p.x, p.z)
				n.position = p
				var d := ahead - p
				if Vector2(d.x, d.z).length() > 0.001:
					n.rotation.y = atan2(-d.z, d.x)
				var carry: Node3D = (f.parts.body as Node3D).get_node_or_null("Carry")
				if carry:
					carry.visible = out
				_pose(f, "carry" if out else "walk", f.ph)
			"mop":
				var h: Vector3 = f.home
				var x: float = h.x + sin(t * 0.25 + f.ph * 0.01) * 3.0 * f.dir
				n.position = Vector3(x, height_at(x, h.z), h.z)
				n.rotation.y = 0.0 if cos(t * 0.25) * f.dir > 0.0 else PI
				_pose(f, "mop", f.ph * 0.5)
			"sight":
				_pose(f, "sight", f.ph * 0.3)
			"stroll":
				var tg: Vector3 = f.tgt
				var dd := tg - n.position
				if dd.length() < 0.5:
					var hm3: Vector3 = f.home
					f.tgt = hm3 + Vector3(randf_range(-10, 10), 0, randf_range(-4, 4))
					f.wait = randf_range(1.0, 5.0)
				elif f.get("wait", 0.0) > 0.0:
					f.wait -= dt
					_pose(f, "stand", f.ph)
				else:
					n.position += dd.normalized() * minf(dd.length(), 1.1 * dt)
					n.rotation.y = atan2(-dd.z, dd.x)
					_pose(f, "walk", f.ph)
	# the guns traverse slowly as the crews sight them
	for m in mounts:
		var mn: Node3D = m[0]
		m[2] += dt * 0.15
		mn.rotation.y = sin(m[2]) * 0.6


func _on_deck(p: Vector3) -> bool:
	return absf(p.z) < Bm * 0.5 + 0.5 and absf(p.x) < L * 0.5


func _trip_len(f: Dictionary) -> float:
	var pts := [f.src, gang_bot, gang_top, Vector3(f.dst.x, deck_y, f.dst.z)]
	if into_side:
		pts = [f.src, gang_bot, gang_top]
	var d := 0.0
	for i in pts.size() - 1:
		d += (pts[i] as Vector3).distance_to(pts[i + 1])
	return maxf(d * 2.0, 1.0)


func _along(pts: Array, k: float) -> Vector3:
	var seg := []
	var tot := 0.0
	for i in pts.size() - 1:
		var l: float = (pts[i] as Vector3).distance_to(pts[i + 1])
		seg.append(l)
		tot += l
	var d := k * tot
	for i in seg.size():
		if d <= seg[i] or i == seg.size() - 1:
			return (pts[i] as Vector3).lerp(pts[i + 1], clampf(d / maxf(seg[i], 0.001), 0.0, 1.0))
		d -= seg[i]
	return pts[pts.size() - 1]


# =====================================================================
# the captain and officers on the quay
# =====================================================================

const KHAKI := Color(0.6, 0.54, 0.38)
const KHAKI_D := Color(0.5, 0.44, 0.3)
const LOOKS := {
	"captain": {"shirt": KHAKI, "pants": KHAKI_D, "hat": "officer", "hat_col": Color(0.98, 0.98, 0.96), "prop": "binoculars", "scale": 1.06, "uniform": "khaki", "rank": "eagle", "shoes": Color(0.3, 0.18, 0.1)},
	"Executive officer": {"shirt": KHAKI, "pants": KHAKI_D, "hat": "garrison", "hat_col": KHAKI_D, "prop": "clipboard", "uniform": "khaki", "rank": "bars", "shoes": Color(0.3, 0.18, 0.1)},
	"Gunnery officer": {"shirt": KHAKI, "pants": KHAKI_D, "hat": "helmet", "hat_col": Color(0.42, 0.45, 0.46), "prop": "phones", "uniform": "kapok", "rank": "bars", "shoes": Color(0.3, 0.18, 0.1)},
	"Torpedo officer": {"shirt": KHAKI, "pants": KHAKI_D, "hat": "ballcap", "hat_col": Color(0.14, 0.18, 0.32), "prop": "torpedo", "uniform": "khaki", "rank": "bars", "shoes": Color(0.3, 0.18, 0.1)},
	"Engineering officer": {"shirt": Color(0.3, 0.4, 0.58), "pants": Color(0.3, 0.4, 0.58), "hat": "garrison", "hat_col": KHAKI_D, "prop": "wrench", "uniform": "coveralls"},
	"Navigator": {"shirt": KHAKI, "pants": KHAKI_D, "hat": "officer", "hat_col": KHAKI, "prop": "chart", "uniform": "khaki", "rank": "bars", "pencils": true, "shoes": Color(0.3, 0.18, 0.1)},
	"Damage control officer": {"shirt": KHAKI, "pants": KHAKI_D, "hat": "dc_helmet", "hat_col": Color(0.92, 0.92, 0.9), "prop": "axe", "uniform": "khaki", "rank": "bars", "gasbag": true, "shoes": Color(0.3, 0.18, 0.1)},
	"Air group commander": {"shirt": Color(0.42, 0.28, 0.17), "pants": KHAKI_D, "hat": "flight", "hat_col": Color(0.36, 0.24, 0.15), "prop": "", "uniform": "flight", "shoes": Color(0.22, 0.14, 0.08)},
}



## Officers serving now (the air group post only on carriers).
func _serving() -> Array:
	var out := []
	var c: Dictionary = Game.career
	for o in c.get("officers", []):
		if o.post == "Air group commander" and T.get("cls", "") != "cv":
			continue
		out.append(o)
	return out


func _build_lineup() -> void:
	var people: Array = ["captain"] + _serving()
	var gap := 1.6
	var x0 := gang_bot.x + 6.0
	for i in people.size():
		var who = people[i]
		var key: String = "captain" if typeof(who) == TYPE_STRING else String(who.post)
		var look: Dictionary = LOOKS.get(key, LOOKS["Executive officer"]).duplicate()
		look.skin = SKIN[(i * 3 + 1) % SKIN.size()]
		var meds: Array = Game.career.get("medals", []) if key == "captain" else (who as Dictionary).get("medals", [])
		var rib := []
		for m in meds:
			rib.append(Career.medal_ribbon(String(m.get("id", ""))))
		look.ribbons = rib
		var f := _figure(look)
		var pos := Vector3(x0 + i * gap, QUAY_Y, quay_z - 5.5)
		(f.node as Node3D).position = pos
		(f.node as Node3D).rotation.y = PI / 2.0        # facing the sheds, where the camera stands
		f.who = who
		f.pos = pos
		f.key = key
		if typeof(who) == TYPE_DICTIONARY and (who.get("dead", false)):
			(f.node as Node3D).visible = false
		lineup.append(f)


func _step_lineup(dt: float) -> void:
	for i in lineup.size():
		var f: Dictionary = lineup[i]
		f.ph += dt * 4.0
		if i == sel and salute_t > 0.0:
			_pose(f, "salute", f.ph)
		else:
			_pose(f, "stand", f.ph)
	salute_t = maxf(0.0, salute_t - dt)


# =====================================================================
# camera
# =====================================================================

func _select(i: int, snap := false) -> void:
	sel = i
	if i < 0:
		var span := maxf(L, 40.0)
		cam_pos_t = Vector3(L * 0.1, maxf(6.5, span * 0.09) + QUAY_Y + deck_y * 0.5, quay_z - clampf(span * 0.38, 17.0, 115.0))
		cam_look_t = Vector3(-L * 0.06, deck_y * 0.8 + span * 0.03, 0)
	else:
		var f: Dictionary = lineup[i]
		var p: Vector3 = f.pos
		cam_pos_t = p + Vector3(0.7, 1.7, -5.8)
		cam_look_t = p + Vector3(0.0, 1.35, 0.0)
		salute_t = 2.2
	if snap:
		cam_pos = cam_pos_t
		cam_look = cam_look_t
	for j in sel_buttons.size():
		(sel_buttons[j] as Button).set_pressed_no_signal(j == i + 1)
	_refresh_person()


func _step_camera(dt: float) -> void:
	var k := 1.0 - exp(-dt * 2.2)
	var drift := Vector3.ZERO
	if sel < 0:
		drift = Vector3(sin(t * 0.05) * L * 0.08, 0, 0)
	cam_pos = cam_pos.lerp(cam_pos_t + drift, k)
	cam_look = cam_look.lerp(cam_look_t, k)
	cam.look_at_from_position(cam_pos, cam_look, Vector3.UP)


var _had_card := false

func _process(dt: float) -> void:
	t += dt
	# a port menu from the map (refit, recruit) was open: show what changed
	if ops:
		var has_card: bool = ops.card != null
		if _had_card and not has_card:
			_refresh_info()
			_refresh_person()
		_had_card = has_card
	_step_crew(dt)
	_step_lineup(dt)
	_step_crane(dt)
	_step_camera(dt)
	var sea: MeshInstance3D = root3d.get_node_or_null("Sea")
	if sea:
		(sea.get_meta("ocean") as ShaderMaterial).set_shader_parameter("time_s", t)
	overlay.queue_redraw()
	if bar_ref:
		bar_ref.position = Vector2((size.x - bar_ref.size.x) / 2.0, size.y - bar_ref.size.y - 16)
	if person_panel:
		person_panel.position = Vector2(size.x - person_panel.size.x - 16, 16)


# =====================================================================
# UI
# =====================================================================

func _build_ui() -> void:
	var c: Dictionary = Game.career
	var cs := Career.ship(c)
	# top left: where we are
	var tl := UI.panel(14)
	tl.position = Vector2(16, 16)
	info_box = UI.column(4)
	tl.add_child(info_box)
	add_child(tl)
	# left: the port's business
	var lp := UI.panel(14)
	lp.position = Vector2(16, 170)
	actions_box = UI.column(6)
	lp.add_child(actions_box)
	add_child(lp)
	# right: the selected person
	person_panel = UI.panel(16)
	person_panel.custom_minimum_size = Vector2(380, 0)
	person_box = UI.column(6)
	person_panel.add_child(person_box)
	add_child(person_panel)
	# bottom: who to look at
	var bar := UI.panel(10)
	var row := UI.row([], 6)
	var names := ["The ship", "Captain"]
	for o in _serving():
		names.append(String(o.post).replace(" officer", "").replace("Air group commander", "Air group"))
	for i in names.size():
		var b := UI.button(names[i], _select.bind(i - 1), true)
		sel_buttons.append(b)
		row.add_child(b)
	bar.add_child(row)
	add_child(bar)
	bar_ref = bar
	_refresh_info()


func _refresh_info() -> void:
	for ch in info_box.get_children():
		ch.queue_free()
	for ch in actions_box.get_children():
		ch.queue_free()
	var c: Dictionary = Game.career
	var cs := Career.ship(c)
	info_box.add_child(UI.label("IN PORT · %s" % port_name.to_upper(), 11, UI.BRASS))
	info_box.add_child(UI.label(String(cs.get("name", "Your ship")), 26))
	var day := 0
	if ops and ops.get("C") != null:
		day = int(ops.C.day)
	info_box.add_child(UI.label("%s · %s" % [T.get("name", ""), War.date_str(day)], 13, UI.MUTED))
	var T2: Dictionary = T
	var crew_n: int = int(cs.get("crew", T2.crew))
	info_box.add_child(UI.label("Crew %d / %d · %s · morale %d%%" % [crew_n, int(T2.crew), Career.training_label(float(cs.get("training", 40.0))), int(float(cs.get("morale", 0.8)) * 100.0)], 13))
	actions_box.add_child(UI.label("THE YARD", 11, UI.BRASS))
	if ops:
		var rd: int = ops._repair_days(cs)
		if rd > 0:
			actions_box.add_child(UI.button("Repair (%d day%s in the yard)" % [rd, "" if rd == 1 else "s"], func(): ops._repair(rd); _refresh_info()))
		else:
			actions_box.add_child(UI.label("Ship in good order, crew at full strength.", 12, UI.GREEN))
		actions_box.add_child(UI.button("Refit (%d supply)" % int(c.get("supply", 0)), func(): ops._refit_menu()))
		actions_box.add_child(UI.button("Request a new command", func(): ops._request_command(); close()))
		if not ops.C.squadron.is_empty():
			actions_box.add_child(UI.label("IN COMPANY", 11, UI.BRASS))
			actions_box.add_child(UI.wrap(ops._describe(ops.C.squadron), 300, 12, Color(0.55, 0.85, 1.0)))
		var nxt := int(c.get("rank", 0)) + 1
		if nxt < Career.RANK_REP.size():
			actions_box.add_child(UI.wrap("Reputation %d. Promotion to %s at %d brings more ships." % [int(c.get("reputation", 0)), Missions.RANKS[nxt], Career.RANK_REP[nxt]], 300, 12, UI.MUTED))
	actions_box.add_child(UI.big_button("Back to sea", close))


func _refresh_person() -> void:
	if person_box == null:
		return
	for ch in person_box.get_children():
		ch.queue_free()
	var c: Dictionary = Game.career
	if sel < 0:
		person_panel.visible = false
		return
	person_panel.visible = true
	var f: Dictionary = lineup[sel]
	if typeof(f.who) == TYPE_STRING:
		person_box.add_child(UI.label("COMMANDING OFFICER", 11, UI.BRASS))
		person_box.add_child(UI.label("%s %s" % [Missions.RANKS[clampi(int(c.get("rank", 0)), 0, Missions.RANKS.size() - 1)], Career.captain_name(c)], 22))
		person_box.add_child(UI.label("%d missions · %d won · %d reputation" % [int(c.get("missions", 0)), int(c.get("won", 0)), int(c.get("reputation", 0))], 13, UI.MUTED))
		_medal_list(c.get("medals", []))
	else:
		var o: Dictionary = f.who
		person_box.add_child(UI.label(String(o.post).to_upper(), 11, UI.BRASS))
		person_box.add_child(UI.label(String(o.name), 22))
		var st := "%d action%s" % [int(o.get("battles", 0)), "" if int(o.get("battles", 0)) == 1 else "s"]
		if int(o.get("wounded", 0)) > 0:
			st += " · wounded, back in %d action%s" % [int(o.wounded), "" if int(o.wounded) == 1 else "s"]
		person_box.add_child(UI.label(st, 13, UI.MUTED))
		_medal_list(o.get("medals", []))


func _medal_list(medals: Array) -> void:
	if medals.is_empty():
		person_box.add_child(UI.wrap("No decorations yet. Medals are awarded for what is done in action.", 340, 12, UI.MUTED))
		return
	person_box.add_child(UI.label("DECORATIONS", 11, UI.BRASS))
	for m in medals:
		var nm: String = m.get("name", m.get("id", "?"))
		if int(m.get("n", 1)) > 1:
			nm += " with %d gold star%s" % [int(m.n) - 1, "" if int(m.n) == 2 else "s"]
		var buff: String = Career.medal_buff_text(m)
		person_box.add_child(UI.label(nm, 14))
		if buff != "":
			person_box.add_child(UI.wrap(buff, 340, 12, UI.GREEN))


## Ribbon colours: [base, stripes...] painted as a ribbon bar over the person's head.
const RIBBONS := {
	"navy_cross": [Color(0.1, 0.15, 0.4), Color(0.95, 0.95, 0.95)],
	"silver_star": [Color(0.2, 0.3, 0.6), Color(0.95, 0.95, 0.95), Color(0.75, 0.1, 0.15)],
	"bronze_star": [Color(0.72, 0.12, 0.16), Color(0.15, 0.25, 0.55), Color(0.95, 0.95, 0.95)],
	"purple_heart": [Color(0.42, 0.16, 0.5), Color(0.95, 0.95, 0.95)],
}


func _draw_overlay() -> void:
	if sel < 0 or sel >= lineup.size():
		return
	var f: Dictionary = lineup[sel]
	var medals: Array = Game.career.get("medals", []) if typeof(f.who) == TYPE_STRING else (f.who as Dictionary).get("medals", [])
	var head: Vector3 = (f.pos as Vector3) + Vector3(0, 2.45, 0)
	if cam.is_position_behind(head):
		return
	var sp := cam.unproject_position(head)
	var sx := overlay.size.x / maxf(1.0, view.size.x)
	var sy := overlay.size.y / maxf(1.0, view.size.y)
	sp = Vector2(sp.x * sx, sp.y * sy)
	var font := ThemeDB.fallback_font
	if medals.is_empty():
		return
	var w := 46.0
	var h := 14.0
	var n := medals.size()
	var per_row := mini(n, 4)
	var rows := int(ceil(n / 4.0))
	for i in n:
		var r := int(i / 4)
		var cidx := i % 4
		var in_row := mini(4, n - r * 4)
		var x := sp.x - in_row * (w + 3) / 2.0 + cidx * (w + 3)
		var y := sp.y - (rows - r) * (h + 3)
		var cols: Array = Career.medal_ribbon(String(medals[i].get("id", "")))
		overlay.draw_rect(Rect2(x, y, w, h), cols[0])
		var ns := cols.size() - 1
		for s in ns:
			var sw := w * 0.12
			overlay.draw_rect(Rect2(x + w / 2.0 - sw / 2.0 + (s - (ns - 1) / 2.0) * sw * 1.4, y, sw, h), cols[s + 1])
		overlay.draw_rect(Rect2(x, y, w, h), Color(0, 0, 0, 0.6), false, 1.0)
		# gold stars for repeat awards
		for st in int(medals[i].get("n", 1)) - 1:
			overlay.draw_circle(Vector2(x + w / 2.0 + (st - (int(medals[i].get("n", 1)) - 2) / 2.0) * 9.0, y + h / 2.0), 3.2, Color(1.0, 0.82, 0.25))
	overlay.draw_string(font, Vector2(sp.x - 120, sp.y - rows * (h + 3) - 8), "%d decoration%s" % [n, "" if n == 1 else "s"], HORIZONTAL_ALIGNMENT_CENTER, 240, 14, Color(1, 0.92, 0.7))


# =====================================================================
# small builders
# =====================================================================

func _mat(col: Color, rough := 0.85) -> StandardMaterial3D:
	var key := "%s|%.2f" % [col.to_html(), rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	_mats[key] = m
	return m


func _box(size: Vector3, pos: Vector3, col: Color, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mat(col)
	(parent if parent else root3d).add_child(mi)
	return mi


func _cyl(r: float, h: float, pos: Vector3, col: Color, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	mi.material_override = _mat(col)
	(parent if parent else root3d).add_child(mi)
	return mi


func _sphere(r: float, pos: Vector3, col: Color, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.position = pos
	mi.material_override = _mat(col, 0.7)
	(parent if parent else root3d).add_child(mi)
	return mi


func _capsule(r: float, h: float, pos: Vector3, col: Color, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = maxf(h, r * 2.0)
	cm.radial_segments = 10
	cm.rings = 3
	mi.mesh = cm
	mi.position = pos
	mi.material_override = _mat(col, 0.8)
	parent.add_child(mi)
	return mi


func _rope(a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.05
	cm.height = a.distance_to(b)
	cm.radial_segments = 6
	mi.mesh = cm
	mi.material_override = _mat(Color(0.55, 0.48, 0.36))
	root3d.add_child(mi)
	mi.position = (a + b) / 2.0
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform.basis = Basis(side, up, side.cross(up))


func _plank(a: Vector3, b: Vector3, width: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(a.distance_to(b), 0.12, width)
	mi.mesh = bm
	mi.material_override = _mat(col)
	root3d.add_child(mi)
	var fwd := (b - a).normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	var up := side.cross(fwd).normalized()
	mi.transform = Transform3D(Basis(fwd, up, -side), (a + b) / 2.0)
	# hand ropes on stanchions
	for s in [-1, 1]:
		_rope(a + side * width * 0.5 * s + Vector3(0, 1.0, 0), b + side * width * 0.5 * s + Vector3(0, 1.0, 0))


func _stack(at: Vector3, col: Color, nx: int, nz: int) -> void:
	for i in nx:
		for k in nz:
			var hgt := 1 + (i + k) % 3
			for j in hgt:
				_box(Vector3(1.4, 1.1, 1.4), at + Vector3(i * 1.5, 0.55 + j * 1.12, -k * 1.5), col.lerp(Color(0.4, 0.33, 0.22), randf() * 0.3))


func _palm(at: Vector3) -> void:
	var lean := randf_range(-0.25, 0.25)
	var trunk := _cyl(0.22, 9.0, at + Vector3(sin(lean) * 4.5, 4.5, 0), Color(0.45, 0.36, 0.26))
	trunk.rotation.z = -lean
	var top := at + Vector3(sin(lean) * 9.0, 9.0, 0)
	for i in 7:
		var lf := _box(Vector3(4.0, 0.08, 0.8), top, Color(0.14, 0.3, 0.13).lerp(Color(0.22, 0.36, 0.15), randf()))
		lf.rotation = Vector3(0, i * TAU / 7.0, -0.35)
		lf.position = top + Vector3(cos(i * TAU / 7.0) * 1.8, -0.5, -sin(i * TAU / 7.0) * 1.8)
