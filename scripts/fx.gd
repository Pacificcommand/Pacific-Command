class_name Fx
extends Node3D
## Visual effects: wakes, foam, smoke, fire, splashes, debris, oil slicks, flashes and
## flickering lights. All particles are drawn with three MultiMeshes so thousands of
## them stay cheap: a sea-surface layer, a smoke/debris layer and a glowing layer.

enum { FOAM, OIL, SMOKE, SPLASH, DEBRIS, FIRE, FLASH }
const CAP := 12000
const FOAM_MAX := 5000          # wakes and splashes on the water; the rest of the budget is smoke and fire
var foam_n := 0
var _frame := 0
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
var top := PackedFloat32Array()        # smoke: how high it can rise

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
## Smoke, fire and flashes turn to face the camera (for low side views such as the title
## screen); set before the node enters the tree. The battle's top-down view keeps them flat.
var billboard := false
const BILLBOARD_VERTEX := """
	if (INSTANCE_CUSTOM.x < 2.5 || INSTANCE_CUSTOM.x > 3.5) {
		// puffs face the camera, keeping their own spin; tracer streaks (shape 3) stay as drawn
		float bs = length(MODEL_MATRIX[0].xyz);
		float ba = atan(MODEL_MATRIX[0].z, MODEL_MATRIX[0].x);
		vec4 br = INV_VIEW_MATRIX[0] * cos(ba) + INV_VIEW_MATRIX[1] * sin(ba);
		vec4 bu = INV_VIEW_MATRIX[1] * cos(ba) - INV_VIEW_MATRIX[0] * sin(ba);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(br * bs, INV_VIEW_MATRIX[2] * bs, -bu * bs, MODEL_MATRIX[3]);
	}
"""

# PYROLUX Lite fire and explosion effects (free to use in the game; the addon files
# themselves may not be shared or resold, see addons/pyrolux_fx/LICENSE.md)
var use_pyro := true
var density := 1.0   # particle density from the quality setting (1 = all)
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
	for arr in [px, py, pz, vx, vy, vz, r, gr, life, age, al, rot, spin, cr, cg, cb, shape, seed, top]:
		arr.resize(CAP)
	kind.resize(CAP)
	var base: Shader = load("res://shaders/particle.gdshader")
	var air_sh := base
	if billboard:
		air_sh = Shader.new()
		air_sh.code = base.code.replace("seed = INSTANCE_CUSTOM.y;", "seed = INSTANCE_CUSTOM.y;" + BILLBOARD_VERTEX)
	var add := Shader.new()
	add.code = air_sh.code.replace("blend_mix", "blend_add")
	mat_water = ShaderMaterial.new(); mat_water.shader = base; mat_water.render_priority = -2
	mat_air = ShaderMaterial.new(); mat_air.shader = air_sh; mat_air.render_priority = 0
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


## Particles alive by kind (for tuning the budget).
func kind_counts() -> Dictionary:
	var names := ["foam", "oil", "smoke", "splash", "debris", "fire", "flash"]
	var out := {}
	for i in n:
		var nm: String = names[kind[i]]
		out[nm] = out.get(nm, 0) + 1
	return out


func set_lit(v: float) -> void:
	mat_air.set_shader_parameter("lit", v)
	mat_water.set_shader_parameter("lit", clampf(v * 1.1, 0.0, 1.0))


func clear() -> void:
	n = 0
	foam_n = 0
	for c in get_children():
		if c.is_in_group("pyro"):
			c.queue_free()
	lights.clear()
	transient.clear()


func add(k: int, x: float, y: float, z: float, pvx: float, pvz: float, pvy: float, rad: float, grow: float,
		lf: float, a: float, col: Color, shp: float, pspin := 0.0, ptop := 30.0) -> void:
	# lower quality: skip a share of the foam and smoke (flashes and splashes always draw)
	if density < 1.0 and (k == FOAM or k == SMOKE) and randf() > density:
		return
	if k == FOAM:
		if foam_n >= FOAM_MAX:
			return
		foam_n += 1
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
	top[i] = ptop


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
	if kind[i] == FOAM:
		foam_n -= 1
	n -= 1
	if i == n:
		return
	kind[i] = kind[n]
	px[i] = px[n]; py[i] = py[n]; pz[i] = pz[n]
	vx[i] = vx[n]; vy[i] = vy[n]; vz[i] = vz[n]
	r[i] = r[n]; gr[i] = gr[n]; life[i] = life[n]; age[i] = age[n]; al[i] = al[n]
	rot[i] = rot[n]; spin[i] = spin[n]; cr[i] = cr[n]; cg[i] = cg[n]; cb[i] = cb[n]
	shape[i] = shape[n]; seed[i] = seed[n]; top[i] = top[n]


# ---------- effect recipes ----------

func foam(x: float, z: float, fvx: float, fvz: float, rad: float, grow: float, lf: float, a: float) -> void:
	add(FOAM, x, 0.15, z, fvx, fvz, 0.0, rad, grow, lf, a * 0.75, Color(0.9, 0.95, 0.97), 1.0)

func smoke(x: float, y: float, z: float, svx: float, svz: float, rad: float, grow: float, lf: float, a: float, col: Color, rise := 0.6, ceiling := 30.0, ages := false) -> void:
	add(SMOKE, x, y, z, svx, svz, rise, rad, grow, lf, a, col, 0.2 if ages else 0.0, 0.0, ceiling)


# ---------- lasting smoke of a battle ----------
# Smoke lingers: it drifts downwind, spreads, thins and (when ageing) greys over minutes, so a
# long action leaves its gun smoke, burning ships and wrecks hanging over the water.

## Cordite smoke from a gun: a cloud blown out ahead of the muzzle that hangs and drifts.
## size: 1 = an 8-inch gun, 2 = a battleship's 16-inch, 0.2 = a 5-inch.
func gun_smoke(x: float, y: float, z: float, dx: float, dz: float, size: float) -> void:
	var k := clampf(size, 0.15, 2.2)
	var n := 2 if k < 0.5 else (4 if k < 1.3 else 6)
	for j in n:
		var out := randf_range(4.0, 14.0) * k
		var sp := randf_range(3.0, 8.0) * k
		var col := Color(0.62, 0.59, 0.52).lerp(Color(0.48, 0.46, 0.42), randf())
		smoke(x + dx * out + randf_range(-2, 2) * k, y + randf_range(-1, 2), z + dz * out + randf_range(-2, 2) * k,
			dx * sp, dz * sp, randf_range(3.0, 5.0) * k, randf_range(0.6, 1.0) * (0.5 + 0.5 * k), randf_range(26.0, 44.0) * (0.6 + 0.4 * k),
			randf_range(0.32, 0.45), col, 0.35, 22.0 + 10.0 * k, true)

## The dark cloud a shell burst leaves on a ship: lingers and drifts off.
func hit_smoke(x: float, y: float, z: float, big: bool) -> void:
	for j in (5 if big else 3):
		var a := randf() * TAU
		var o := randf_range(1.0, 5.0)
		var c := Color(0.14, 0.13, 0.125).lerp(Color(0.26, 0.25, 0.24), randf())
		smoke(x + cos(a) * o, y + 3.0, z + sin(a) * o, cos(a) * 1.5, sin(a) * 1.5, randf_range(5.0, 8.0) * (1.4 if big else 1.0),
			randf_range(1.0, 1.5), randf_range(30.0, 55.0), randf_range(0.36, 0.5), c, randf_range(0.8, 1.6), 55.0, true)

## A burning ship's plume: thick black smoke climbing, leaning downwind and spreading, then
## thinning to grey; a ship on fire for a few minutes trails a long smoke line across the sea.
func plume(x: float, y: float, z: float, intensity: float) -> void:
	var k := clampf(intensity, 0.2, 1.5)
	var c := Color(0.06, 0.055, 0.05).lerp(Color(0.16, 0.15, 0.14), randf())
	smoke(x + randf_range(-2, 2), y, z + randf_range(-2, 2), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5),
		randf_range(4.0, 6.5) * (0.7 + 0.4 * k), randf_range(0.8, 1.2), randf_range(70.0, 120.0), randf_range(0.62, 0.8), c,
		randf_range(1.4, 2.4) * (0.8 + 0.3 * k), randf_range(70.0, 110.0), true)

## Funnel smoke: a light haze cruising, darker at full power, black and heavy from damaged boilers.
func funnel_smoke(x: float, y: float, z: float, power: float, damaged: float, oil_black: bool) -> void:
	var dark := clampf(power * 0.45 + damaged * 0.9, 0.0, 1.0)
	var base := Color(0.46, 0.46, 0.44) if not oil_black else Color(0.34, 0.33, 0.32)
	var c := base.lerp(Color(0.07, 0.065, 0.06), dark)
	smoke(x, y, z, randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(2.0, 3.0) * (1.0 + damaged * 0.8), 1.0 + damaged * 0.9,
		randf_range(16.0, 26.0) * (1.0 + damaged * 1.5), clampf(0.14 + 0.18 * power + 0.45 * damaged, 0.1, 0.75), c, 0.5 + damaged * 0.6,
		35.0 + damaged * 25.0, true)

## Burning oil on the water where a ship went down: low flames and a column of black smoke.
func oil_fire(x: float, z: float, intensity: float) -> void:
	var k := clampf(intensity, 0.1, 1.2)
	fire_puff(x + randf_range(-6, 6), 0.8, z + randf_range(-6, 6), randf_range(2.0, 4.0) * k)
	if randf() < 0.5:
		plume(x + randf_range(-8, 8), 2.0, z + randf_range(-8, 8), k)

func oil(x: float, z: float, rad: float) -> void:
	add(OIL, x, 0.1, z, randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), 0.0, rad, 0.35, randf_range(140, 220), 0.55, Color(0.02, 0.025, 0.03), 0.0)

## Flak. heavy: a 5-inch (US) or 12.7 cm (IJN) time-fuzed shell: a hot flash, a black core that
## bursts open, then a ragged cloud that hangs in the sky for most of a minute, greying as it
## spreads, with wisps flung out. Light: a 40 mm / 25 mm round's self-destruct puff. A long raid
## leaves the sky over the fleet pocked with old bursts.
func flak_burst(x: float, y: float, z: float, heavy: bool, ijn := false) -> void:
	var wx := wind.x * 0.5
	var wz := wind.y * 0.5
	if not heavy:
		flash(x, y, z, 1.6, 9.0, 0.08, Color(1.0, 0.8, 0.5))
		var c0 := Color(0.34, 0.33, 0.31).lerp(Color(0.46, 0.45, 0.43), randf())
		add(SMOKE, x, y, z, wx, wz, 0.05, randf_range(1.6, 2.4), 0.9, randf_range(9.0, 15.0), 0.55, c0, 0.3, 0.0, 400.0)
		return
	flash(x, y, z, 5.0, 34.0, 0.12, Color(1.0, 0.72, 0.38))
	flash(x, y, z, 2.5, 14.0, 0.06, Color(1.0, 0.95, 0.8))
	var dark := Color(0.04, 0.035, 0.03) if not ijn else Color(0.12, 0.1, 0.08)
	var body := Color(0.09, 0.085, 0.08) if not ijn else Color(0.2, 0.18, 0.15)
	# the core: thick and black, snapping open in a second or two
	for j in 3:
		var a := randf() * TAU
		add(SMOKE, x + cos(a) * 1.5, y + randf_range(-1, 1), z + sin(a) * 1.5, wx + cos(a) * 2.0, wz + sin(a) * 2.0, 0.0,
			randf_range(3.5, 5.0), 7.0, randf_range(1.8, 2.6), 0.95, dark, 0.3, 0.0, 400.0)
	# the cloud that stays: lumpy, slowly spreading and drifting downwind
	for j in 5:
		var a := randf() * TAU
		var o := randf_range(1.0, 6.0)
		add(SMOKE, x + cos(a) * o, y + randf_range(-3, 3), z + sin(a) * o, wx + cos(a) * 0.8, wz + sin(a) * 0.8, 0.05,
			randf_range(5.0, 8.0), randf_range(1.1, 1.7), randf_range(32.0, 50.0), randf_range(0.6, 0.78), body.lerp(dark, randf() * 0.5),
			0.3, 0.0, 400.0)
	# ragged wisps thrown out of the burst
	for j in 3:
		var a := randf() * TAU
		var e := randf_range(-0.5, 0.5)
		var sp := randf_range(3.0, 5.0)
		add(SMOKE, x, y, z, wx + cos(a) * sp, wz + sin(a) * sp, e * sp, randf_range(1.8, 2.8), 0.9, randf_range(8.0, 13.0), 0.5, body,
			0.3, 0.0, 400.0)

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
	# the cloud that hangs on after the flash: a column for a big one
	hit_smoke(x, y, z, big)
	if big:
		for j in 4:
			smoke(x + randf_range(-6, 6), y + 6.0 + j * 6.0, z + randf_range(-6, 6), randf_range(-1, 1), randf_range(-1, 1),
				randf_range(8.0, 12.0), randf_range(1.0, 1.5), randf_range(45.0, 75.0), randf_range(0.5, 0.7), Color(0.1, 0.09, 0.085), 2.0, 90.0, true)
	debris(x, y, z, 26 if big else 6, 26.0 if big else 12.0)

## Hit by a light gun (20-40 mm or machine gun): sparks, a puff of smoke, a few splinters.
func small_hit(x: float, y: float, z: float, dmg: float) -> void:
	var k := clampf(dmg * 3.0, 0.3, 1.0)
	flash(x, y + 1.0, z, 2.5 * k, 6.0 * k, 0.15, Color(1.0, 0.8, 0.45))
	add(FIRE, x, y + 1.0, z, 0, 0, 1.0, 1.5 * k, 2.0, 0.3, 0.9, Color(1, 0.7, 0.3), 5.0)
	smoke(x, y + 1.0, z, randf_range(-1, 1), randf_range(-1, 1), 1.5 * k, 1.2, randf_range(8, 14), 0.5, Color(0.25, 0.23, 0.22), 0.8, 30.0, true)
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
				py[i] = minf(py[i] + vy[i] * dt, top[i])
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
			# flak (shape 0.3) pops open at once; other smoke billows in
			a *= minf(1.0, age[i] * (10.0 if (shape[i] > 0.25 and shape[i] < 0.35) else 1.5)) * (1.0 - t) * (1.0 + 0.6 * t)
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
	# one pass over the particles, each written into its layer's buffer
	var b0: PackedFloat32Array = bufs[0]
	var b1: PackedFloat32Array = bufs[1]
	var b2: PackedFloat32Array = bufs[2]
	bufs[0] = PackedFloat32Array(); bufs[1] = PackedFloat32Array(); bufs[2] = PackedFloat32Array()
	var cnt := [0, 0, 0]
	# the sea layer moves slowly: redraw it every third frame; smoke every other frame; fire
	# and flashes every frame. A layer not redrawn keeps last frame's buffer on screen.
	_frame += 1
	var do0 := _frame % 3 == 0
	var do1 := _frame % 2 == 0
	for i in n:
		var k := kind[i]
		var li := 2 if (k == FIRE or k == FLASH) else (1 if (k == SMOKE or k == SPLASH or (k == DEBRIS and py[i] > 0.2)) else 0)
		if (li == 0 and not do0) or (li == 1 and not do1):
			continue
		var a := _alpha(i)
		if a <= 0.003:
			continue
		var c: int = cnt[li]
		cnt[li] = c + 1
		var o := c * FLOATS
		var rr := r[i] * 2.0
		var co := cos(rot[i]) * rr
		var si := sin(rot[i]) * rr
		var red := cr[i]
		var grn := cg[i]
		var blu := cb[i]
		var y := py[i]
		if k == SMOKE:
			y = maxf(y, r[i] * 0.6)
		if shape[i] > 0.1 and shape[i] < 0.5:
			# ageing smoke thins out to a grey haze
			var g := minf(1.0, age[i] / life[i] * 1.3) * 0.55
			red = lerpf(red, 0.55, g); grn = lerpf(grn, 0.56, g); blu = lerpf(blu, 0.57, g)
		if li == 0:
			b0[o] = co; b0[o + 1] = 0.0; b0[o + 2] = si; b0[o + 3] = px[i]
			b0[o + 4] = 0.0; b0[o + 5] = 1.0; b0[o + 6] = 0.0; b0[o + 7] = y
			b0[o + 8] = -si; b0[o + 9] = 0.0; b0[o + 10] = co; b0[o + 11] = pz[i]
			b0[o + 12] = red; b0[o + 13] = grn; b0[o + 14] = blu; b0[o + 15] = a
			b0[o + 16] = shape[i]; b0[o + 17] = seed[i]; b0[o + 18] = 0.0; b0[o + 19] = 0.0
		elif li == 1:
			b1[o] = co; b1[o + 1] = 0.0; b1[o + 2] = si; b1[o + 3] = px[i]
			b1[o + 4] = 0.0; b1[o + 5] = 1.0; b1[o + 6] = 0.0; b1[o + 7] = y
			b1[o + 8] = -si; b1[o + 9] = 0.0; b1[o + 10] = co; b1[o + 11] = pz[i]
			b1[o + 12] = red; b1[o + 13] = grn; b1[o + 14] = blu; b1[o + 15] = a
			b1[o + 16] = shape[i]; b1[o + 17] = seed[i]; b1[o + 18] = 0.0; b1[o + 19] = 0.0
		else:
			b2[o] = co; b2[o + 1] = 0.0; b2[o + 2] = si; b2[o + 3] = px[i]
			b2[o + 4] = 0.0; b2[o + 5] = 1.0; b2[o + 6] = 0.0; b2[o + 7] = y
			b2[o + 8] = -si; b2[o + 9] = 0.0; b2[o + 10] = co; b2[o + 11] = pz[i]
			b2[o + 12] = red; b2[o + 13] = grn; b2[o + 14] = blu; b2[o + 15] = a
			b2[o + 16] = shape[i]; b2[o + 17] = seed[i]; b2[o + 18] = 0.0; b2[o + 19] = 0.0
	# shell tracers: streaks from last position to this one
	var c2: int = cnt[2]
	for tr in transient:
		if c2 >= CAP:
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
		var o2 := c2 * FLOATS
		c2 += 1
		var cc := cos(ang)
		var ss := sin(ang)
		b2[o2] = cc * ln * 2.0; b2[o2 + 1] = 0.0; b2[o2 + 2] = ss * w * 2.0; b2[o2 + 3] = mid.x
		b2[o2 + 4] = 0.0; b2[o2 + 5] = 1.0; b2[o2 + 6] = 0.0; b2[o2 + 7] = mid.y
		b2[o2 + 8] = -ss * ln * 2.0; b2[o2 + 9] = 0.0; b2[o2 + 10] = cc * w * 2.0; b2[o2 + 11] = mid.z
		b2[o2 + 12] = col.r; b2[o2 + 13] = col.g; b2[o2 + 14] = col.b; b2[o2 + 15] = 1.0
		b2[o2 + 16] = 3.0; b2[o2 + 17] = 0.0; b2[o2 + 18] = 0.0; b2[o2 + 19] = 0.0
	cnt[2] = c2
	transient.clear()
	# hand each buffer over and back (a single owner, so writes stay in place)
	if do0:
		var mm0: MultiMesh = layers[0].multimesh
		mm0.buffer = b0; mm0.visible_instance_count = cnt[0]
	if do1:
		var mm1: MultiMesh = layers[1].multimesh
		mm1.buffer = b1; mm1.visible_instance_count = cnt[1]
	var mm2: MultiMesh = layers[2].multimesh
	mm2.buffer = b2; mm2.visible_instance_count = cnt[2]
	bufs[0] = b0; bufs[1] = b1; bufs[2] = b2
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
