class_name Fx
extends Node3D
## Visual effects: wakes, foam, smoke, fire, splashes, debris, oil slicks, flashes and
## flickering lights. All particles are drawn with three MultiMeshes so thousands of
## them stay cheap: a sea-surface layer, a smoke/debris layer and a glowing layer.

enum { FOAM, OIL, SMOKE, SPLASH, DEBRIS, FIRE, FLASH }
const CAP := 7000
const FLOATS := 20   # per instance: 12 transform + 4 color + 4 custom

# particle arrays (structure of arrays keeps GDScript fast)
var n := 0
var kind := PackedInt32Array()
var px := PackedFloat32Array(); var py := PackedFloat32Array(); var pz := PackedFloat32Array()
var vx := PackedFloat32Array(); var vy := PackedFloat32Array(); var vz := PackedFloat32Array()
var r := PackedFloat32Array(); var gr := PackedFloat32Array()
var life := PackedFloat32Array(); var age := PackedFloat32Array()
var al := PackedFloat32Array(); var rot := PackedFloat32Array(); var spin := PackedFloat32Array()
var cr := PackedFloat32Array(); var cg := PackedFloat32Array(); var cb := PackedFloat32Array()
var shape := PackedFloat32Array(); var seed := PackedFloat32Array()

var layers := []          # [MultiMeshInstance3D] water, air, glow
var bufs := []            # PackedFloat32Array per layer
var counts := [0, 0, 0]
var mat_air: ShaderMaterial
var mat_water: ShaderMaterial

# transient sprites drawn for one frame only (shell tracers)
var transient: Array = []

# lights: short flashes and fires
var lights: Array = []    # {pos, r, col, life, age, energy}
var light_nodes: Array = []
const LIGHT_POOL := 14

var wind := Vector2(-1.4, 1.1)

# PYROLUX Lite fire and explosion effects (free to use in the game; the addon files
# themselves may not be shared or resold, see addons/pyrolux_fx/LICENSE.md)
var use_pyro := true
const PYRO_EXPLOSION := "res://addons/pyrolux_fx/nodes_3d/pyrolux_explosion_3d.gd"
const PYRO_FIRE := "res://addons/pyrolux_fx/nodes_3d/pyrolux_fire_3d.gd"
var _pyro_exp: Script
var _pyro_fire: Script

## True when the PYROLUX addon is in the project (the game also runs without it).
func has_pyro() -> bool:
	if _pyro_exp == null and ResourceLoader.exists(PYRO_EXPLOSION):
		_pyro_exp = load(PYRO_EXPLOSION)
		_pyro_fire = load(PYRO_FIRE)
	return _pyro_exp != null


func _ready() -> void:
	for arr in [px, py, pz, vx, vy, vz, r, gr, life, age, al, rot, spin, cr, cg, cb, shape, seed]:
		arr.resize(CAP)
	kind.resize(CAP)
	var base: Shader = load("res://shaders/particle.gdshader")
	var add := Shader.new()
	add.code = base.code.replace("blend_mix", "blend_add")
	mat_water = ShaderMaterial.new(); mat_water.shader = base; mat_water.render_priority = -2
	mat_air = ShaderMaterial.new(); mat_air.shader = base; mat_air.render_priority = 0
	var mat_glow := ShaderMaterial.new(); mat_glow.shader = add; mat_glow.render_priority = 1
	mat_glow.set_shader_parameter("additive", true)
	var atlas: Texture2D = load("res://assets/fx/kenney/smoke_atlas.png")
	var foam_t: Texture2D = load("res://assets/textures/boujie/foam_2.png")
	for m in [mat_water, mat_air, mat_glow]:
		m.set_shader_parameter("atlas", atlas)
		m.set_shader_parameter("foam_tex", foam_t)
	for m in [mat_water, mat_air, mat_glow]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var pm := PlaneMesh.new()
		pm.size = Vector2(1, 1)
		mm.mesh = pm
		mm.instance_count = CAP
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-1e6, -100, -1e6), Vector3(2e6, 2000, 2e6))
		add_child(mi)
		layers.append(mi)
		var b := PackedFloat32Array()
		b.resize(CAP * FLOATS)
		bufs.append(b)
	for i in LIGHT_POOL:
		var l := OmniLight3D.new()
		l.visible = false
		l.shadow_enabled = false
		l.omni_attenuation = 1.6
		add_child(l)
		light_nodes.append(l)


func set_lit(v: float) -> void:
	mat_air.set_shader_parameter("lit", v)
	mat_water.set_shader_parameter("lit", clampf(v * 1.1, 0.0, 1.0))


func clear() -> void:
	n = 0
	for c in get_children():
		if c.is_in_group("pyro"):
			c.queue_free()
	lights.clear()
	transient.clear()


func add(k: int, x: float, y: float, z: float, pvx: float, pvz: float, pvy: float, rad: float, grow: float,
		lf: float, a: float, col: Color, shp: float, pspin := 0.0) -> void:
	if n >= CAP:
		if k == FOAM:
			return
		_remove_oldest(200)
	var i := n
	n += 1
	kind[i] = k
	px[i] = x; py[i] = y; pz[i] = z
	vx[i] = pvx; vy[i] = pvy; vz[i] = pvz
	r[i] = rad; gr[i] = grow
	life[i] = lf; age[i] = 0.0; al[i] = a
	rot[i] = randf() * TAU; spin[i] = pspin
	cr[i] = col.r; cg[i] = col.g; cb[i] = col.b
	shape[i] = shp; seed[i] = randf() * 10.0


func _remove_oldest(count: int) -> void:
	# drop foam first (it is the most plentiful)
	var removed := 0
	var i := 0
	while i < n and removed < count:
		if kind[i] == FOAM:
			_kill(i)
			removed += 1
		else:
			i += 1


func _kill(i: int) -> void:
	n -= 1
	if i == n:
		return
	kind[i] = kind[n]
	px[i] = px[n]; py[i] = py[n]; pz[i] = pz[n]
	vx[i] = vx[n]; vy[i] = vy[n]; vz[i] = vz[n]
	r[i] = r[n]; gr[i] = gr[n]; life[i] = life[n]; age[i] = age[n]; al[i] = al[n]
	rot[i] = rot[n]; spin[i] = spin[n]; cr[i] = cr[n]; cg[i] = cg[n]; cb[i] = cb[n]
	shape[i] = shape[n]; seed[i] = seed[n]


# ---------- effect recipes ----------

func foam(x: float, z: float, fvx: float, fvz: float, rad: float, grow: float, lf: float, a: float) -> void:
	add(FOAM, x, 0.15, z, fvx, fvz, 0.0, rad, grow, lf, a * 0.75, Color(0.9, 0.95, 0.97), 1.0)

func smoke(x: float, y: float, z: float, svx: float, svz: float, rad: float, grow: float, lf: float, a: float, col: Color, rise := 0.6) -> void:
	add(SMOKE, x, y, z, svx, svz, rise, rad, grow, lf, a, col, 0.0)

func oil(x: float, z: float, rad: float) -> void:
	add(OIL, x, 0.1, z, randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), 0.0, rad, 0.35, randf_range(140, 220), 0.55, Color(0.02, 0.025, 0.03), 0.0)

func flash(x: float, y: float, z: float, rad: float, grow: float, lf: float, col: Color) -> void:
	add(FLASH, x, y, z, 0, 0, 0, rad, grow, lf, 1.0, col, 2.0)

func fire_puff(x: float, y: float, z: float, rad: float) -> void:
	add(FIRE, x, y, z, 0, 0, 1.0, rad, 2.0, randf_range(0.4, 0.8), 0.9, Color(1.0, randf_range(0.45, 0.7), 0.15), 5.0)

func splash(x: float, z: float, big: bool) -> void:
	add(SPLASH, x, 3.0, z, 0, 0, 0, 5.0 if big else 2.5, 7.0 if big else 3.5, 3.0 if big else 2.0, 0.9, Color(0.95, 0.98, 1.0), 1.0)
	add(SPLASH, x, 3.5, z, 0, 0, 0, 2.5 if big else 1.6, 2.0, 1.4, 0.6, Color(0.95, 0.97, 1.0), 0.0)
	for i in (16 if big else 9):
		var a := randf() * TAU
		var o := randf_range(2.0, 9.0)
		foam(x + cos(a) * 2.0, z + sin(a) * 2.0, cos(a) * o, sin(a) * o, randf_range(2, 5), 1.5, randf_range(8, 16), 0.85)

## Shader-built explosion from PYROLUX: radius in meters.
func pyro_explosion(pos: Vector3, radius: float, smoke_s: float) -> void:
	if not use_pyro or not has_pyro():
		return
	var e = _pyro_exp.new()
	e.style = 1  # AIR: no ground dust or scorch mark
	e.radius = radius
	e.smoke_time = smoke_s
	e.fireball = 30
	e.smoke = 24
	e.sparks = 40
	e.debris = 16
	e.light_range = radius * 8.0
	e.light_energy = 8.0
	e.free_when_done = true
	e.autoplay = false
	e.add_to_group("pyro")
	add_child(e)
	e.explode_at(pos)


## A burning fire from PYROLUX, attached to a ship. Size 1 = small, 2 = big.
func pyro_fire(parent: Node3D, local_pos: Vector3, size: float) -> Node3D:
	if not use_pyro or not has_pyro():
		return null
	var f = _pyro_fire.new()
	f.add_to_group("pyro")
	f.add_to_group("pyro_fire")
	f.position = local_pos
	f.scale = Vector3.ONE * size
	parent.add_child(f)
	return f


func boom(x: float, y: float, z: float, big: bool) -> void:
	pyro_explosion(Vector3(x, y + 1.0, z), 9.0 if big else 3.5, 6.0 if big else 3.0)
	var rad := 26.0 if big else 10.0
	flash(x, y + 2.0, z, rad, rad * 2.5, 0.7 if big else 0.35, Color(1.0, 0.75, 0.4))
	add(FIRE, x, y + 3.0, z, 0, 0, 2.0, rad * 0.7, rad * 0.8, 1.2 if big else 0.6, 1.0, Color(1, 0.7, 0.3), 5.0)
	light(Vector3(x, y + 8.0, z), 900.0 if big else 380.0, Color(1.0, 0.6, 0.25), 8.0 if big else 4.0, 0.8 if big else 0.35)
	for i in (14 if big else 5):
		var a := randf() * TAU
		var o := randf_range(2.0, 10.0)
		smoke(x, y + 4.0, z, cos(a) * o, sin(a) * o, randf_range(5, 9) * (1.6 if big else 1.0), 5.0 if big else 3.0, randf_range(7, 12), 0.7, Color(0.16, 0.14, 0.13), 1.5)
	debris(x, y, z, 26 if big else 6, 26.0 if big else 12.0)

## Hit by a light gun (20-40 mm or machine gun): sparks, a puff of smoke, a few splinters.
func small_hit(x: float, y: float, z: float, dmg: float) -> void:
	var k := clampf(dmg * 3.0, 0.3, 1.0)
	flash(x, y + 1.0, z, 2.5 * k, 6.0 * k, 0.15, Color(1.0, 0.8, 0.45))
	add(FIRE, x, y + 1.0, z, 0, 0, 1.0, 1.5 * k, 2.0, 0.3, 0.9, Color(1, 0.7, 0.3), 5.0)
	smoke(x, y + 1.0, z, randf_range(-1, 1), randf_range(-1, 1), 1.5 * k, 1.2, randf_range(3, 5), 0.5, Color(0.25, 0.23, 0.22), 0.8)
	debris(x, y, z, int(3 * k) + 1, 8.0 * k)
	if randf() < 0.3:
		light(Vector3(x, y + 4.0, z), 60.0 * k, Color(1.0, 0.7, 0.35), 2.0, 0.12)


## Splash from a light gun: small spout and a ring of foam.
func small_splash(x: float, z: float, size: float) -> void:
	add(SPLASH, x, 1.0, z, 0, 0, 0, 0.8 + size * 2.0, 2.0 * size + 0.5, 0.9, 0.8, Color(0.95, 0.98, 1.0), 1.0)
	for i in 3:
		var a := randf() * TAU
		foam(x, z, cos(a) * 2.0, sin(a) * 2.0, randf_range(0.6, 1.2), 0.6, randf_range(3, 6), 0.6)


func debris(x: float, y: float, z: float, count: int, speed: float) -> void:
	for i in count:
		var a := randf() * TAU
		var sp := randf_range(0.3, 1.0) * speed
		var c := Color(0.18, 0.17, 0.16) if randf() < 0.5 else Color(0.32, 0.3, 0.27)
		add(DEBRIS, x, y + 2.0, z, cos(a) * sp, sin(a) * sp, randf_range(0.4, 1.2) * speed, randf_range(0.5, 1.6), 0.0, randf_range(60, 110), 1.0, c, 4.0, randf_range(-6, 6))

func light(pos: Vector3, rad: float, col: Color, energy: float, lf: float) -> void:
	lights.append({"pos": pos, "r": rad, "col": col, "energy": energy, "life": lf, "age": 0.0})

func tracer(from: Vector3, to: Vector3, col: Color, width: float) -> void:
	transient.append([from, to, col, width])


# ---------- per-frame ----------

func step(dt: float) -> void:
	var damp_smoke := exp(-dt * 0.25)
	var damp := exp(-dt * 0.6)
	var i := 0
	while i < n:
		age[i] += dt
		if age[i] >= life[i]:
			_kill(i)
			continue
		var k := kind[i]
		if k == DEBRIS:
			if py[i] > 0.15:
				vy[i] -= 9.8 * dt
				px[i] += vx[i] * dt; py[i] += vy[i] * dt; pz[i] += vz[i] * dt
				rot[i] += spin[i] * dt
				if py[i] <= 0.15:
					py[i] = 0.16; vy[i] = 0.0; vx[i] *= 0.04; vz[i] *= 0.04
					if randf() < 0.6:
						foam(px[i], pz[i], 0, 0, 1.6, 1.2, 4.0, 0.7)
			else:
				# floats away on the current
				px[i] += (vx[i] + 0.15) * dt; pz[i] += (vz[i] + 0.1) * dt
				rot[i] += spin[i] * 0.03 * dt
		else:
			var d := damp_smoke if k == SMOKE else damp
			vx[i] *= d; vz[i] *= d
			if k == SMOKE or k == FIRE:
				vx[i] += (wind.x - vx[i]) * dt * 0.15
				vz[i] += (wind.y - vz[i]) * dt * 0.15
				# smoke stays low: from straight above, tall columns would fill the camera
				py[i] = minf(py[i] + vy[i] * dt, 30.0)
			px[i] += vx[i] * dt; pz[i] += vz[i] * dt
			r[i] += gr[i] * dt
		i += 1
	for l in lights:
		l.age += dt
	lights = lights.filter(func(l): return l.age < l.life)


var _buf := PackedFloat32Array()

## Which layer a particle draws in (0 sea surface, 1 air, 2 glow) and its alpha now; -1 = skip.
func _alpha(i: int) -> float:
	var k := kind[i]
	var t := age[i] / life[i]
	var a := al[i]
	match k:
		FOAM, OIL:
			a *= minf(1.0, age[i] * 4.0) * (1.0 - t) * (1.0 - t * 0.3)
		SMOKE:
			a *= minf(1.0, age[i] * 1.5) * (1.0 - t)
		SPLASH:
			a *= (1.0 - t) * (1.0 - t)
		FIRE, FLASH:
			a *= 1.0 - t
		DEBRIS:
			a *= minf(1.0, (life[i] - age[i]) / 8.0)
	return a

func _layer(i: int) -> int:
	var k := kind[i]
	if k == FIRE or k == FLASH:
		return 2
	if k == SMOKE or k == SPLASH or (k == DEBRIS and py[i] > 0.2):
		return 1
	return 0

func render(cam_pos: Vector3) -> void:
	for li in 3:
		# take the buffer out of the array so this script is its only owner (writes stay in place)
		_buf = bufs[li]
		bufs[li] = PackedFloat32Array()
		var c := 0
		for i in n:
			if _layer(i) != li:
				continue
			var a := _alpha(i)
			if a <= 0.003:
				continue
			var o := c * FLOATS
			c += 1
			var rr := r[i] * 2.0
			var co := cos(rot[i]) * rr
			var si := sin(rot[i]) * rr
			_buf[o] = co; _buf[o + 1] = 0.0; _buf[o + 2] = si; _buf[o + 3] = px[i]
			_buf[o + 4] = 0.0; _buf[o + 5] = 1.0; _buf[o + 6] = 0.0; _buf[o + 7] = py[i]
			_buf[o + 8] = -si; _buf[o + 9] = 0.0; _buf[o + 10] = co; _buf[o + 11] = pz[i]
			_buf[o + 12] = cr[i]; _buf[o + 13] = cg[i]; _buf[o + 14] = cb[i]; _buf[o + 15] = a
			_buf[o + 16] = shape[i]; _buf[o + 17] = seed[i]; _buf[o + 18] = 0.0; _buf[o + 19] = 0.0
		if li == 2:
			# shell tracers: streaks from last position to this one
			for tr in transient:
				if c >= CAP:
					break
				var p0: Vector3 = tr[0]
				var p1: Vector3 = tr[1]
				var col: Color = tr[2]
				var w: float = tr[3]
				var mid := (p0 + p1) * 0.5
				var dx := p1.x - p0.x
				var dz := p1.z - p0.z
				var ln := maxf(sqrt(dx * dx + dz * dz), w * 2.0) * 0.5
				var ang := atan2(-dz, dx)
				var o2 := c * FLOATS
				c += 1
				var cc := cos(ang)
				var ss := sin(ang)
				_buf[o2] = cc * ln * 2.0; _buf[o2 + 1] = 0.0; _buf[o2 + 2] = ss * w * 2.0; _buf[o2 + 3] = mid.x
				_buf[o2 + 4] = 0.0; _buf[o2 + 5] = 1.0; _buf[o2 + 6] = 0.0; _buf[o2 + 7] = mid.y
				_buf[o2 + 8] = -ss * ln * 2.0; _buf[o2 + 9] = 0.0; _buf[o2 + 10] = cc * w * 2.0; _buf[o2 + 11] = mid.z
				_buf[o2 + 12] = col.r; _buf[o2 + 13] = col.g; _buf[o2 + 14] = col.b; _buf[o2 + 15] = 1.0
				_buf[o2 + 16] = 3.0; _buf[o2 + 17] = 0.0; _buf[o2 + 18] = 0.0; _buf[o2 + 19] = 0.0
			transient.clear()
		var mm: MultiMesh = layers[li].multimesh
		mm.buffer = _buf
		mm.visible_instance_count = c
		bufs[li] = _buf
	_buf = PackedFloat32Array()
	_update_lights(cam_pos)


func _update_lights(cam_pos: Vector3) -> void:
	# use the brightest lights nearest the camera
	var scored := []
	for l in lights:
		var fade: float = 1.0 - l.age / l.life
		var d := Vector2(l.pos.x - cam_pos.x, l.pos.z - cam_pos.z).length()
		scored.append([l.energy * fade / (1.0 + d / 1500.0), l, fade])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	for i in LIGHT_POOL:
		var ln: OmniLight3D = light_nodes[i]
		if i < scored.size():
			var l: Dictionary = scored[i][1]
			ln.visible = true
			ln.position = l.pos
			ln.omni_range = l.r
			ln.light_color = l.col
			ln.light_energy = l.energy * scored[i][2]
		else:
			ln.visible = false
