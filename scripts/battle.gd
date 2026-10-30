extends Node3D
## The battle: sets up the sea, sky, camera and ships, then runs the simulation.
## Gunnery, torpedoes, damage, flooding, fires, spotting and the enemy AI all live here.
## The HUD (hud.gd) reads this script's state and calls its order functions.

static var I  # the running battle, so other scripts can reach it

# ---------- settings ----------
var scenario := "dd"          # "dd" destroyer action, "barges" PT barge hunt, "convoy" PT convoy attack
var brief := {}                # mission briefing text for the HUD
var weather := "night"
var magazine := "historical"   # player magazine detonations: historical, reduced, off
var aim_mode := "auto"         # "auto" = crew aims, "manual" = point and click
var show_lead := true
var scheme := "m21"
var follow := true
var slow_follow := false

# ---------- state ----------
var t := 0.0                   # battle time in seconds
var speed := 1.0               # 0 = tactical pause, 0.25 slow, 1 normal, 3 fast
var prev_speed := 1.0
var started := false           # false while the briefing is open
var over := ""                 # "", "won", "lost"
var ships: Array = []
var player: Ship
var shells: Array = []
var torps: Array = []
var smokes: Array = []         # smoke screen clouds that block sight lines
var stars: Array = []          # star shells
var events: Array = []         # [time, Callable]
var salvo_n := 0
var shake := 0.0
var report := {}               # where the enemy was last reported
var stats := {"salvos": 0, "shells": 0, "hits": 0, "torps": 0, "torp_hits": 0, "sunk": [], "start_crew": 0}
var mouse_w = null             # world point under the mouse (Vector2) or null
var click_shot = null          # manual-aim click waiting to be fired
var torp_aim := false
var combat_t := -1.0           # when shooting started; friendly boats hold station until then          # torpedo aiming mode (T): mouse sets the bearing, click fires
var vis_timer := 0.0
var _hit_msg_t := {}           # throttle for "no serious damage" messages
var _torp_warn_t := -99.0      # throttle for torpedo wake warnings
var _under_msg := false
var autopilot := false         # test option: the AI also drives the player's ship

# ---------- scene parts ----------
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var ocean: MeshInstance3D
var ocean_mat: ShaderMaterial
var fx: Fx
var sfx: Sfx
var ai: AI
var hud
## Camera: x/z where it looks, h height now, th wanted height. focus = "player" or "target" (the
## ship it tracks); free = true after the player drags the view, until Esc or a view button.
var camst := {"x": 0.0, "z": 0.0, "h": 420.0, "th": 420.0, "ox": 0.0, "oz": 0.0, "salvo": null, "hold": 0.0, "impact": null, "focus": "player", "free": false}
const VIEWS := {"close": 160.0, "ship": 420.0, "wide": 2200.0, "tac": 9000.0}
const FOV := 32.0


func _ready() -> void:
	I = self
	randomize()
	_build_world()
	sfx = Sfx.new()
	add_child(sfx)
	ai = AI.new()
	ai.B = self
	hud = load("res://scripts/hud.gd").new()
	add_child(hud)
	scenario = Game.start_scenario
	Game.graphics_changed.connect(apply_quality)
	apply_quality()
	new_game()
	if Game.pending_load >= 0:
		var d := Game.load_slot(Game.pending_load)
		Game.pending_load = -1
		if not d.is_empty():
			load_state(d)
	_test_args()


## Quality preset from the settings: shadows, glow, particle density, PYROLUX.
func apply_quality() -> void:
	var q: Dictionary = Game.quality_params()
	if sun:
		sun.shadow_enabled = q.shadows
	if env:
		env.glow_enabled = q.glow
	if fx:
		fx.density = q.particles
		fx.use_pyro = Game.settings.pyro and fx.has_pyro()
	if hud and hud.btn.has("pyro"):
		hud.btn.pyro.set_pressed_no_signal(fx.use_pyro)


# ---------- test options (used when running from the command line) ----------
# godot --path . -- --weather=clear --start --close=2500 --run=60 --shot=out.png --quit
var _test := {}
var _dbg := {}

func _test_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=")
		_test[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _test.has("scenario"):
		scenario = _test.scenario
		new_game()
	if _test.has("load"):
		var d := Game.load_slot(int(_test.load))
		if d.is_empty():
			print("slot empty")
		else:
			load_state(d)
			set_speed(1.0)
			print("loaded slot ", _test.load, " t=", t)
	if _test.has("weather"):
		weather = _test.weather
		apply_weather()
	if _test.has("auto"):
		autopilot = true
	if _test.has("nofollow"):
		follow = false
	if _test.has("aim"):
		aim_mode = _test.aim
	if _test.has("close"):
		# move the enemy closer for testing
		var d := float(_test.close)
		for s in ships:
			if not s.is_player:
				var b := player.bearing_to(s.x, s.z)
				var off := Vector2(s.x - ships[1].x, s.z - ships[1].z)
				s.x = sin(b) * d + off.x
				s.z = -cos(b) * d + off.y
	if _test.has("start"):
		hud.brief.visible = false
		begin()
		if _test.has("fire"):
			player.fire = true
	if _test.has("view"):
		set_view(_test.view)
		camst.h = camst.th
	if _test.has("cam"):
		set_focus(_test.cam)
		var fs := focus_ship()
		camst.x = fs.x; camst.z = fs.z
	if _test.has("run"):
		# fast-forward the simulation before the first frame
		var n := int(float(_test.run) / 0.05)
		for i in n:
			if player.target == null:
				for s in ships:
					if not s.is_player and player.contact(s):
						player.target = s
			if _test.has("fire") and aim_mode == "auto":
				player.fire = true
			if aim_mode == "manual" and player.target:
				# aim at the lead point, click every 3 seconds
				var tg: Ship = player.target
				var tf := player.tof_for(player.range_to(tg))
				var fv := U.fwd(tg.h)
				mouse_w = Vector2(tg.x + fv.x * tg.v * tf, tg.z + fv.y * tg.v * tf)
				if i % 60 == 0:
					click_shot = mouse_w
			_step(0.05)
			if _test.has("trace") and i % 300 == 0:
				var line := "t=%d " % t
				for hs in ships:
					line += "| %s %s R=%d crew=%d fl=%d %s " % [hs.ship_name, hs.ai_state, int(player.range_to(hs)), hs.crew, int(hs.flood), "" if hs.alive else ("ESC" if hs.escaped else "SUNK")]
				print(line)
		if _test.has("save"):
			Game.save_slot(int(_test.save), save_state())
			print("saved slot ", _test.save, " at t=", t)
		print("debug ", _dbg)
		print("ran ", _test.run, "s: t=", t, " player crew ", player.crew, " flood ", player.flood, " salvos ", stats.salvos, " hits ", stats.hits, " sunk ", stats.sunk)
		for s in ships:
			print("  ", s.ship_name, " alive=", s.alive, " crew=", s.crew, " flood=", int(s.flood), " fires=", s.fires.size(), " range=", int(player.range_to(s)), " vis=", player.vis.get(s.ship_name, false), " radar=", player.radar.get(s.ship_name, false))
	if _test.has("torpaim"):
		torp_aim = true
		if player.target:
			var ip: Array = player.torp_intercept(player.target, player.x, player.z)
			player.h = player.bearing_to(ip[0].x, ip[0].y) - deg_to_rad(float(_test.torpaim))
			mouse_w = ip[0]
	if _test.has("train"):
		hud.brief.visible = false
		player.h = 0.0
		for m in player.mounts:
			m.ang = deg_to_rad(float(_test.train))
	if _test.has("pause"):
		hud.open_pause()
	if _test.has("shot"):
		_shoot.call_deferred()


func _shoot() -> void:
	for i in int(_test.get("frames", "30")):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(_test.shot)
	print("saved ", _test.shot)
	if _test.has("quit"):
		get_tree().quit()


func _build_world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = FOV
	add_child(cam)
	cam.make_current()
	ocean = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	ocean.mesh = pm
	ocean_mat = ShaderMaterial.new()
	ocean_mat.shader = load("res://shaders/ocean.gdshader")
	ocean_mat.set_shader_parameter("foam_tex", load("res://assets/textures/boujie/foam_2.png"))
	ocean_mat.set_shader_parameter("detail_tex", load("res://assets/textures/boujie/ocean_albedo_2.png"))
	ocean.material_override = ocean_mat
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ocean)
	fx = Fx.new()
	add_child(fx)


func apply_weather() -> void:
	var W: Dictionary = Data.WEATHER[weather]
	env.background_color = W.sky
	env.ambient_light_color = W.sky.lerp(Color(1, 1, 1), 0.3)
	env.ambient_light_energy = W.ambient
	env.fog_light_color = W.fog
	sun.light_color = W.sun
	sun.light_energy = W.sun_energy
	var d: Vector3 = W.sun_dir.normalized()
	sun.look_at_from_position(Vector3.ZERO, d, Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD)
	ocean_mat.set_shader_parameter("deep_color", W.deep)
	ocean_mat.set_shader_parameter("shallow_color", W.shallow)
	ocean_mat.set_shader_parameter("chop", W.chop)
	ocean_mat.set_shader_parameter("spec", W.spec)
	fx.set_lit(W.lit)


# =====================================================================
# setup
# =====================================================================

func new_game() -> void:
	for s in ships:
		s.queue_free()
	ships.clear(); shells.clear(); torps.clear(); smokes.clear(); stars.clear(); events.clear()
	fx.clear()
	t = 0.0; salvo_n = 0; over = ""; shake = 0.0; started = false
	click_shot = null
	_hit_msg_t.clear()
	_torp_warn_t = -99.0
	_under_msg = false
	stats = {"salvos": 0, "shells": 0, "hits": 0, "torps": 0, "torp_hits": 0, "sunk": [], "escaped": [], "start_crew": 0}
	combat_t = -1.0
	ai.reset()
	match scenario:
		"barges":
			_setup_barges()
		"convoy":
			_setup_convoy()
		_:
			_setup_dd()
	player.is_player = true
	stats.start_crew = player.crew
	player.target = null
	camst.x = player.x; camst.z = player.z; camst.ox = 0.0; camst.oz = 0.0; camst.salvo = null
	camst.focus = "player"; camst.free = false
	set_view("close" if player.T.L < 40.0 else "ship")
	camst.h = camst.th
	apply_weather()
	set_speed(1.0)
	update_visibility()
	hud.on_new_game()


## Destroyer action: USS O'Bannon against two Kageros coming down from the northeast.
func _setup_dd() -> void:
	player = _add_ship("fletcher", "us", "USS O'Bannon", 0.0, 0.0, deg_to_rad(10.0), 25.0)
	player.tele = 4
	var brg := deg_to_rad(45.0 + randf_range(-12.0, 12.0))
	var dist := randf_range(11500.0, 13000.0)
	var ex := sin(brg) * dist
	var ez := -cos(brg) * dist
	var eh := deg_to_rad(225.0 + randf_range(-10.0, 10.0))
	var a := _add_ship("kagero", "ijn", "Amagiri", ex, ez, eh, 30.0)
	var f := U.fwd(eh)
	var b := _add_ship("kagero", "ijn", "Hagikaze", ex - f.x * 600.0 + cos(eh) * 250.0, ez - f.y * 600.0 + sin(eh) * 250.0, eh, 30.0)
	for e in [a, b]:
		e.tele = 5
		e.objective = true
		e.group = "DesDiv 11"
	a.leader_flag = true
	b.fstation = Vector2(-600.0, 250.0)
	a.side = 1.0; b.side = -1.0
	report = {"x": ex + randf_range(-900, 900), "z": ez + randf_range(-900, 900), "h": eh + deg_to_rad(randf_range(-8, 8)), "v": 30.0 * Data.KN, "r": 2500.0, "t": 0.0, "active": true}
	brief = {"title": "Intercept the Tokyo Express", "threat": "High (night action; Japanese crews are trained for it)" if weather == "night" else "Moderate",
		"text": "Coastwatchers report two Japanese destroyers bearing %s from you, about %s away, steering %s at high speed. Expect Kagero-class ships armed with Long Lance torpedoes that outrange ours.\n\nYou command USS O'Bannon, a Fletcher-class destroyer with five 5-inch guns, ten torpedoes and SG radar. Find the enemy, stop the run, and bring your ship home." % [U.deg3(U.bearing(0, 0, report.x, report.z)), U.yards(U.hyp(report.x, report.z)), U.deg3(report.h)]}


## Three PT boats (you and two others) hunt a night barge run.
func _setup_pt_section(name0: String) -> void:
	player = _add_ship("pt_elco", "us", name0, 0.0, 0.0, deg_to_rad(15.0), 10.0)
	player.tele = 2
	var n := int(name0.substr(3))
	var offs := [Vector2(-70.0, -55.0), Vector2(-70.0, 55.0)]
	for i in 2:
		var o: Vector2 = offs[i]
		var w := player.to_world_xz(o.x, o.y)
		var f := _add_ship("pt_elco", "us", "PT-%d" % (n + i + 1), w.x, w.y, player.h, 10.0)
		f.station = o
		f.tele = 2
		f.side = -1.0 if i == 0 else 1.0


func _setup_barges() -> void:
	_setup_pt_section("PT-131")
	# a column of Daihatsu barges crossing from east to west, two of them gun barges
	var brg := deg_to_rad(40.0 + randf_range(-15.0, 15.0))
	var dist := randf_range(4200.0, 5200.0)
	var cx := sin(brg) * dist
	var cz := -cos(brg) * dist
	var ch := deg_to_rad(265.0 + randf_range(-10.0, 10.0))
	var f := U.fwd(ch)
	var kinds := ["daihatsu_gun", "daihatsu", "daihatsu", "daihatsu", "daihatsu", "daihatsu_gun"]
	for i in kinds.size():
		var back := i * 140.0
		var side := (60.0 if i % 2 == 0 else -60.0)
		var x := cx - f.x * back + cos(ch) * side
		var z := cz - f.y * back + sin(ch) * side
		var b := _add_ship(kinds[i], "ijn", "Barge %d" % (i + 1), x, z, ch, 7.0)
		b.objective = kinds[i] == "daihatsu"
		b.route_h = ch
		b.tele = 2
		b.dest_dist = 9000.0
		b.side = 1.0 if i % 2 == 0 else -1.0
	report = {"x": cx + randf_range(-500, 500), "z": cz + randf_range(-500, 500), "h": ch, "v": 7.0 * Data.KN, "r": 1500.0, "t": 0.0, "active": true}
	brief = {"title": "Barge hunt", "threat": "Low to moderate (gun barges in the column)",
		"text": "A coastwatcher reports a string of enemy landing barges bearing %s, about %s away, creeping along the coast on course %s at about 7 knots with supplies for the garrison.\n\nYou lead a section of three Elco PT boats: you in %s, with PT-132 and PT-133 following. Your torpedoes run too deep for barges, so this is a gun fight: close in quietly, then rake them with 40 mm, 37 mm, 20 mm and .50 calibre fire. Watch the gun barges, they shoot back. Sink the supply barges before they reach the beach." % [U.deg3(U.bearing(0, 0, report.x, report.z)), U.yards(U.hyp(report.x, report.z)), U.deg3(ch), player.ship_name]}


func _setup_convoy() -> void:
	_setup_pt_section("PT-155")
	# two cargo ships and a tanker with a destroyer escort, heading west
	var brg := deg_to_rad(35.0 + randf_range(-15.0, 15.0))
	var dist := randf_range(6500.0, 7500.0)
	var cx := sin(brg) * dist
	var cz := -cos(brg) * dist
	var ch := deg_to_rad(260.0 + randf_range(-10.0, 10.0))
	var f := U.fwd(ch)
	var r := Vector2(cos(ch), sin(ch))
	var plan := [["cargo_maru", "Nichiyo Maru", 0.0, 0.0], ["tanker_maru", "Hokko Maru", -450.0, 0.0], ["cargo_maru", "Toyo Maru", -900.0, 0.0]]
	for it in plan:
		var x: float = cx + f.x * it[2] + r.x * it[3]
		var z: float = cz + f.y * it[2] + r.y * it[3]
		var m := _add_ship(it[0], "ijn", it[1], x, z, ch, 9.0)
		m.objective = true
		m.route_h = ch
		m.tele = 2
		m.dest_dist = 12000.0
	var ex: float = cx + f.x * 900.0 + r.x * 700.0
	var ez: float = cz + f.y * 900.0 + r.y * 700.0
	var esc := _add_ship("kagero", "ijn", "Hamakaze", ex, ez, ch, 12.0)
	esc.route_h = ch
	esc.tele = 2
	esc.side = 1.0
	esc.escort_group = "convoy"
	report = {"x": cx + randf_range(-700, 700), "z": cz + randf_range(-700, 700), "h": ch, "v": 9.0 * Data.KN, "r": 2000.0, "t": 0.0, "active": true}
	brief = {"title": "Convoy attack", "threat": "High (a destroyer escort)",
		"text": "Search radar has a small convoy bearing %s, about %s away, course %s at 9 knots: two cargo ships and a tanker, with one Kagero-class destroyer screening them.\n\nYou lead three Elco PT boats from %s. Each boat carries four Mark 13 torpedoes that fire straight ahead, so you aim the whole boat: get inside about 2,000 yards, point at the target and press T. Then turn away and lay smoke before the destroyer finds you. Sink the merchant ships." % [U.deg3(U.bearing(0, 0, report.x, report.z)), U.yards(U.hyp(report.x, report.z)), U.deg3(ch), player.ship_name]}


func _add_ship(type_id: String, team: String, nm: String, x: float, z: float, h: float, kn: float) -> Ship:
	var s := Ship.new()
	add_child(s)
	s.setup(type_id, team, nm, x, z, h, kn, scheme)
	ships.append(s)
	return s


func begin() -> void:
	started = true
	say("Battle stations. Enemy reported bearing %s, about %s, course %s." % [U.deg3(player.bearing_to(report.x, report.z)), U.yards(player.range_to(report)), U.deg3(report.h)])


func set_scenario(sc: String) -> void:
	scenario = sc
	Game.start_scenario = sc
	weather = "night" if sc != "dd" or weather == "night" else weather
	new_game()


func set_scheme(sc: String) -> void:
	scheme = sc
	for s in ships:
		s.load_model(sc)


func after(d: float, fn: Callable) -> void:
	events.append([t + d, fn])


func say(txt: String, kind := "") -> void:
	if _test.has("trace"):
		print("  [%d] %s" % [int(t), txt])
	if hud:
		hud.log_msg(txt, kind)


func set_speed(v: float) -> void:
	speed = v
	if hud:
		hud.on_speed(v)


func set_view(mode: String) -> void:
	camst.th = VIEWS[mode]
	camst.ox = 0.0; camst.oz = 0.0
	camst.free = false
	camst.salvo = null


## Which ship the camera tracks: "player" (own ship) or "target" (the selected enemy).
func set_focus(which: String) -> void:
	if which == "target" and (player.target == null or not player.target.alive):
		say("No enemy target selected. Right-click a contact or press Tab.")
		which = "player"
	camst.focus = which
	camst.free = false
	camst.ox = 0.0; camst.oz = 0.0
	camst.salvo = null
	if hud:
		hud.on_focus()


## The ship the camera is tracking right now.
func focus_ship() -> Ship:
	if camst.focus == "target":
		var tg: Ship = player.target
		if tg and not tg.gone and (tg.alive or tg.sink < 12.0):
			return tg
		camst.focus = "player"
		if hud:
			hud.on_focus()
	return player


func mag_chance() -> float:
	match magazine:
		"off":
			return 0.0
		"reduced":
			return 0.25
	return 1.0


# =====================================================================
# save and load
# =====================================================================

## The whole battle as plain data. Shells in flight are not kept (they land within seconds).
func save_state() -> Dictionary:
	var idx := func(sh): return ships.find(sh) if sh != null else -1
	var d := {"v": 1, "scenario": scenario, "weather": weather, "magazine": magazine, "aim_mode": aim_mode, "scheme": scheme,
		"t": t, "over": over, "started": started, "combat_t": combat_t, "salvo_n": salvo_n, "report": report, "stats": stats, "brief": brief,
		"follow": follow, "slow_follow": slow_follow, "show_lead": show_lead, "speed": speed if speed > 0.0 else prev_speed,
		"cam": {"focus": camst.focus, "th": camst.th}}
	var sl := []
	for sh in ships:
		var sd: Dictionary = sh.save()
		sd.target = idx.call(sh.target)
		sl.append(sd)
	d.ships = sl
	var tl := []
	for tp in torps:
		tl.append({"x": tp.x, "z": tp.z, "h": tp.h, "v": tp.v, "left": tp.left, "team": tp.team, "owner": idx.call(tp.owner), "dud": tp.dud, "warned": tp.warned, "depth": tp.get("depth", 3.0)})
	d.torps = tl
	d.smokes = smokes.duplicate(true)
	d.stars = stars.duplicate(true)
	d.info = {"title": brief.get("title", "Battle"), "ship": player.ship_name, "clock": "%d:%02d" % [int(t) / 60, int(t) % 60], "date": Game.stamp()}
	return d


func load_state(d: Dictionary) -> void:
	for sh in ships:
		sh.queue_free()
	ships.clear(); shells.clear(); torps.clear(); smokes.clear(); stars.clear(); events.clear()
	fx.clear()
	ai.reset()
	scenario = d.scenario; weather = d.weather; magazine = d.magazine; aim_mode = d.aim_mode; scheme = d.scheme
	t = d.t; over = d.over; combat_t = d.combat_t; salvo_n = int(d.salvo_n)
	report = d.report; stats = d.stats; brief = d.brief
	for k in ["salvos", "shells", "hits", "torps", "torp_hits", "start_crew"]:
		stats[k] = int(stats[k])
	follow = d.follow; slow_follow = d.slow_follow; show_lead = d.show_lead
	for sd in d.ships:
		var sh := _add_ship(sd.type_id, sd.team, sd.ship_name, sd.x, sd.z, sd.h, 0.0)
		sh.restore(sd)
		if sh.is_player:
			player = sh
	for i in d.ships.size():
		var ti := int(d.ships[i].target)
		ships[i].target = ships[ti] if ti >= 0 else null
	for td in d.torps:
		var oi := int(td.owner)
		torps.append({"x": td.x, "z": td.z, "h": td.h, "v": td.v, "left": td.left, "team": td.team, "owner": ships[oi] if oi >= 0 else null, "dud": td.dud, "warned": td.warned, "depth": td.depth})
	smokes = d.smokes.duplicate(true)
	stars = d.stars.duplicate(true)
	for sh in ships:
		for f in sh.fires:
			f.erase("node")
	camst.focus = d.cam.focus; camst.th = d.cam.th; camst.free = false
	camst.x = player.x; camst.z = player.z; camst.h = camst.th
	apply_weather()
	update_visibility()
	hud.on_new_game()
	hud.brief.visible = false
	started = true
	set_speed(0.0)
	prev_speed = float(d.speed)
	say("Battle resumed. Press %s or pick a time speed to continue." % Game.key_name("pause"))


# =====================================================================
# main loop
# =====================================================================

func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	var sim := delta * speed if started else 0.0
	# small fixed steps keep fast-forward stable
	while sim > 0.0:
		var h := minf(sim, 0.05)
		sim -= h
		_step(h)
	_update_camera(delta)
	var ts := clampf(speed, 0.0, 4.0) if started else 0.0
	for n in get_tree().get_nodes_in_group("pyro"):
		n.time_scale = ts
	for s in ships:
		s.update_visual(t)
	_draw_shells()
	fx.render(cam.position)
	ocean_mat.set_shader_parameter("time_s", t)
	hud.refresh()


func _step(dt: float) -> void:
	t += dt
	if not events.is_empty():
		var due := []
		var keep := []
		for e in events:
			if e[0] <= t:
				due.append(e)
			else:
				keep.append(e)
		events = keep
		for e in due:
			e[1].call()
	vis_timer -= dt
	if vis_timer <= 0.0:
		vis_timer = 0.5
		update_visibility()
	for s in ships:
		if not s.is_player or autopilot:
			step_ai(s, dt)
		step_fire_control(s, dt)
		step_ship(s, dt)
	step_shells(dt)
	step_torps(dt)
	_step_smokes(dt)
	fx.step(dt)
	if report.active:
		var f := U.fwd(report.h)
		report.x += f.x * report.v * dt
		report.z += f.y * report.v * dt
		report.r = minf(report.r + dt * 4.0, 5000.0)
	shake = maxf(0.0, shake - dt * 1.5)
	_check_end()


func _check_end() -> void:
	if over != "":
		return
	if not player.alive:
		over = "lost"
		after(4.0, func(): hud.show_end())
		return
	var left := 0
	var sunk := 0
	var got_away := 0
	for o in ships:
		if not o.objective:
			continue
		if not o.alive and not o.escaped:
			sunk += 1
		elif o.escaped or player.range_to(o) > 16000.0:
			got_away += 1
		else:
			left += 1
	if left == 0:
		over = "won" if sunk > 0 and sunk >= got_away else "escaped"
		after(5.0, func(): hud.show_end())


func _step_smokes(dt: float) -> void:
	for s in smokes:
		s.age += dt
		s.x += fx.wind.x * dt
		s.z += fx.wind.y * dt
		s.r = minf(s.rmax, s.r + dt * 2.2)
	smokes = smokes.filter(func(s): return s.age < s.life)
	for st in stars:
		st.age += dt
	stars = stars.filter(func(s): return s.age < s.life)
	for st in stars:
		fx.light(Vector3(st.x, 300.0 - st.age * 6.0, st.z), 2000.0, Color(1.0, 1.0, 0.88), 3.5, 0.06)


# =====================================================================
# visibility
# =====================================================================

func los_clear(ax: float, az: float, bx: float, bz: float) -> bool:
	var block := 0.0
	var dx := bx - ax
	var dz := bz - az
	var L2 := maxf(dx * dx + dz * dz, 1.0)
	for s in smokes:
		var tt := clampf(((s.x - ax) * dx + (s.z - az) * dz) / L2, 0.0, 1.0)
		var d := U.hyp(s.x - (ax + dx * tt), s.z - (az + dz * tt))
		if d < s.r:
			var fade_in := minf(1.0, s.age / 8.0)
			var fade_out := minf(1.0, (s.life - s.age) / 20.0)
			block += s.density * (1.0 - d / s.r) * fade_in * fade_out
	return block < 0.8


func can_see(obs: Ship, tgt: Ship) -> bool:
	if not obs.alive or tgt.escaped:
		return false
	var W: Dictionary = Data.WEATHER[weather]
	var d := obs.range_to(tgt)
	# small, low craft are harder to see
	var rng: float = W.vis * (obs.T.night_eye if W.night else 1.0) * tgt.T.get("size_vis", 1.0)
	if W.night or weather == "fog":
		if t - tgt.last_fired < 3.0:
			var flash: float = clampf(tgt.gun.size, 0.35, 1.0)
			rng = maxf(rng, (6000.0 if W.night else 2500.0) * flash)
		var fire := 0.0
		for f in tgt.fires:
			fire += f.int
		if fire > 0.0:
			rng = maxf(rng, (2500.0 if W.night else 1600.0) + fire * 1300.0)
		if tgt.illum > 0.0:
			rng = maxf(rng, 4000.0)
	if d > rng:
		return false
	return los_clear(obs.x, obs.z, tgt.x, tgt.z)


func update_visibility() -> void:
	for a in ships:
		for b in ships:
			if a.team == b.team or (not b.alive and b.sink > 12.0) or b.escaped:
				continue
			a.vis[b.ship_name] = can_see(a, b)
			var rr: float = a.T.radar * (0.55 + 0.45 * b.T.get("size_vis", 1.0))
			a.radar[b.ship_name] = a.alive and a.T.radar > 0.0 and a.mod_health("director") > 0.0 and a.range_to(b) < rr
	# ships share contacts by radio (TBS), so a target one ship sees can be engaged by its consorts
	for a in ships:
		if not a.alive:
			continue
		for b in ships:
			if a.team == b.team or not b.alive or b.escaped or a.vis.get(b.ship_name, false) or a.radar.get(b.ship_name, false):
				continue
			for c in ships:
				if c != a and c.team == a.team and c.alive and (c.vis.get(b.ship_name, false) or c.radar.get(b.ship_name, false)):
					a.radar[b.ship_name] = true
					break
	var p := player
	for b in ships:
		if b.team != p.team and b.alive and p.contact(b) and not b.spotted_once:
			b.spotted_once = true
			var how := "Radar contact" if p.radar.get(b.ship_name, false) and not p.vis.get(b.ship_name, false) else "Lookouts report a ship"
			say("%s! Bearing %s, range %s. %s." % [how, U.deg3(p.bearing_to(b.x, b.z)), U.yards(p.range_to(b)), b.T.name], "good")
			if p.target == null or (b.objective and not p.target.objective):
				p.target = b
			report.active = false


# =====================================================================
# gunnery
# =====================================================================

func fire_salvo(s: Ship, tgt: Ship, ready: Array, g: Dictionary) -> void:
	var R := s.range_to(tgt)
	var tof := s.tof_for(R, g)
	var seen: bool = s.vis.get(tgt.ship_name, false)
	var W: Dictionary = Data.WEATHER[weather]
	var dir_ok := 1.0 if s.mod_health("director") > 0.0 else 1.8
	var vis_pen := (1.25 if W.night and tgt.illum <= 0.0 else 1.0) if seen else 1.7
	var e := s.eff()
	var skill: float = s.T.get("gunnery", 1.0)   # crew training: barge and merchant gunners were not navy-trained
	var sig_r: float = R * (0.006 + 0.024 * (1.0 - s.q)) * dir_ok * vis_pen / (e * skill)
	var sig_d: float = R * 0.0025 * dir_ok * vis_pen / (e * skill)
	# aim where the target will be when the shells arrive
	var lead_k := 0.7 + 0.3 * s.q
	var f := U.fwd(tgt.h)
	var ax: float = tgt.x + f.x * tgt.v * tof * lead_k
	var az: float = tgt.z + f.y * tgt.v * tof * lead_k
	var sv := {"n": 0, "shooter": s, "tgt": tgt, "aim": Vector2(ax, az), "manual": false, "shells": 0, "landed": 0, "hits": 0, "over": 0, "short": 0, "gun": g}
	if s.is_player:
		salvo_n += 1
		sv.n = salvo_n
		stats.salvos += 1
	_launch_shells(s, sv, ready, Vector2(ax, az), sig_r, sig_d, R, tof, 0.8, g)
	if s.is_player and g.dmg >= 0.5:
		_follow_salvo(sv)


## Manual fire: shells go where the captain clicked. No automatic lead.
func fire_at(s: Ship, aim: Vector2, ready: Array, g: Dictionary) -> void:
	var R := U.hyp(aim.x - s.x, aim.y - s.z)
	var tof := s.tof_for(R, g)
	var W: Dictionary = Data.WEATHER[weather]
	var e := s.eff()
	var dir_ok := 1.0 if s.mod_health("director") > 0.0 else 1.6
	var sig_r: float = R * 0.007 * dir_ok * (1.2 if W.night else 1.0) / e
	var sig_d: float = R * 0.0022 * dir_ok / e
	var tgt: Ship = null
	var bd := 600.0
	for o in ships:
		if o.team != s.team and o.alive:
			var d := U.hyp(o.x - aim.x, o.z - aim.y)
			if d < bd:
				bd = d; tgt = o
	salvo_n += 1
	stats.salvos += 1
	var sv := {"n": salvo_n, "shooter": s, "tgt": tgt, "aim": aim, "manual": true, "shells": 0, "landed": 0, "hits": 0, "over": 0, "short": 0, "gun": g}
	_launch_shells(s, sv, ready, aim, sig_r, sig_d, R, tof, 0.5, g)
	if g.dmg >= 0.5:
		_follow_salvo(sv)


func _launch_shells(s: Ship, sv: Dictionary, ready: Array, aim: Vector2, sig_r: float, sig_d: float, R: float, tof: float, bias_k: float, g: Dictionary) -> void:
	var brg := s.bearing_to(aim.x, aim.y)
	var Rp := U.hyp(aim.x - s.x, aim.y - s.z)
	var bias_r := U.gauss() * sig_r * bias_k
	var bias_d := U.gauss() * sig_d * bias_k
	var e := s.eff()
	var sz: float = g.size
	var muzzle_y: float = 8.0 if s.T.L > 50.0 else 3.0
	for j in ready.size():
		var m: Dictionary = ready[j]
		after(j * 0.12 * sz, func():
			if not s.alive or m.hp <= 0.0:
				return
			for k in g.per_mount:
				var rr: float = Rp + bias_r + U.gauss() * sig_r * 0.45
				var dd: float = bias_d + U.gauss() * sig_d * 0.6
				var tx: float = s.x + sin(brg) * rr + cos(brg) * dd
				var tz: float = s.z - cos(brg) * rr + sin(brg) * dd
				var side_off: float = (k - 0.5) * 1.5 * sz if g.per_mount > 1 else 0.0
				var mp := s.to_world_xz(m.x + cos(m.ang) * 8.0 * sz, sin(m.ang) * 8.0 * sz + side_off)
				var delay: float = k * 0.15 if sz < 0.5 else 0.0
				shells.append({"sx": mp.x, "sz": mp.y, "sy": muzzle_y, "tx": tx, "tz": tz, "t": -delay, "tof": tof * randf_range(0.98, 1.02),
					"apex": R * g.apex, "salvo": sv, "team": s.team, "pos": Vector3(mp.x, muzzle_y, mp.y), "prev": Vector3(mp.x, muzzle_y, mp.y),
					"dmg": g.dmg, "size": sz})
				sv.shells += 1
			m.recoil = 1.5
			var fp := s.to_world_xz(m.x + cos(m.ang) * 9.0 * sz, sin(m.ang) * 9.0 * sz)
			var wb: float = s.h + m.ang
			fx.flash(fp.x, muzzle_y + 1.0, fp.y, 7.0 * sz, 30.0 * sz, 0.25 * maxf(sz, 0.5), Color(1.0, 0.85, 0.55))
			fx.light(Vector3(fp.x, muzzle_y + 2.0, fp.y), 520.0 * sz, Color(1.0, 0.7, 0.4), 5.0 * sz, 0.28)
			for i in (3 if sz >= 0.5 else 1):
				fx.smoke(fp.x + sin(wb) * 4.0 * sz, muzzle_y + 1.0, fp.y - cos(wb) * 4.0 * sz, sin(wb) * randf_range(4, 9) * sz, -cos(wb) * randf_range(4, 9) * sz, randf_range(2.5, 4) * sz, 1.8 * sz, randf_range(5, 8), 0.4 * maxf(sz, 0.5), Color(0.6, 0.56, 0.48), 0.3)
			sfx.play("gun", fp, cam.position, 0.8 * maxf(sz, 0.35))
		)
	s.last_fired = t
	if combat_t < 0.0 and (s.is_player or s.team != player.team):
		combat_t = t
	for m in ready:
		m.reload = g.reload / e * randf_range(0.95, 1.08)


func _follow_salvo(sv: Dictionary) -> void:
	if follow:
		camst.salvo = sv
		camst.hold = 0.0
		if slow_follow and speed > 0.25:
			prev_speed = speed
			set_speed(0.25)


func step_shells(dt: float) -> void:
	for sh in shells:
		sh.t += dt
		var f: float = clampf(sh.t / sh.tof, 0.0, 1.0)
		sh.prev = sh.pos
		sh.pos = Vector3(lerpf(sh.sx, sh.tx, f), sh.sy * (1.0 - f) + sh.apex * 4.0 * f * (1.0 - f), lerpf(sh.sz, sh.tz, f))
		if f >= 1.0 and not sh.get("done", false):
			sh.done = true
			land_shell(sh)
	shells = shells.filter(func(s): return not s.get("done", false))


func _draw_shells() -> void:
	for sh in shells:
		var p: Vector3 = sh.pos
		var dir: Vector3 = (sh.pos - sh.prev)
		if dir.length() < 0.01:
			dir = Vector3(sh.tx - sh.sx, 0, sh.tz - sh.sz).normalized()
		else:
			dir = dir.normalized()
		var tail := clampf(camst.h * 0.05, 6.0, 120.0)
		var col := Color(1.0, 0.75, 0.4) if sh.team == "us" else Color(1.0, 0.55, 0.35)
		fx.tracer(p - dir * tail, p, col, clampf(camst.h * 0.0025, 0.5, 14.0))


func land_shell(sh: Dictionary) -> void:
	var sv: Dictionary = sh.salvo
	sv.landed += 1
	if _test.has("trace"):
		var k: String = sh.team + ("_hit" if false else "_shell")
		_dbg[k] = _dbg.get(k, 0) + 1
	if sv.shooter.is_player:
		stats.shells += 1
	var hit: Ship = null
	for s in ships:
		if s.team == sh.team or s.sink > 3.0:
			continue
		if s.inside_hull(sh.tx, sh.tz, 0.5):
			hit = s
			break
	if hit:
		sv.hits += 1
		var l := hit.to_local_xz(sh.tx, sh.tz)
		var dmg: float = sh.get("dmg", 1.0)
		var deck := 2.5 if hit.T.L < 40.0 else 6.0
		if dmg >= 0.5 and hit.T.L < 40.0:
			# a heavy shell on a small boat: a sharp blast, not a destroyer-sized cloud
			fx.small_hit(sh.tx, deck, sh.tz, 0.35)
			fx.pyro_explosion(Vector3(sh.tx, deck, sh.tz), 2.5, 2.5)
			sfx.play("boom", Vector2(sh.tx, sh.tz), cam.position, 0.5)
		elif dmg >= 0.5:
			fx.boom(sh.tx, deck, sh.tz, false)
			sfx.play("boom", Vector2(sh.tx, sh.tz), cam.position, 0.5)
		else:
			fx.small_hit(sh.tx, deck, sh.tz, dmg)
		damage(hit, l.x, l.y, dmg, "shell", sv.shooter)
		if sv.shooter.is_player:
			stats.hits += 1
	else:
		var ssz: float = sh.get("size", 1.0)
		if ssz >= 0.5:
			fx.splash(sh.tx, sh.tz, false)
			sfx.play("splash", Vector2(sh.tx, sh.tz), cam.position, 0.4)
		else:
			fx.small_splash(sh.tx, sh.tz, ssz)
		var ref: Vector2 = Vector2(sv.tgt.x, sv.tgt.z) if sv.tgt else sv.aim
		var shooter: Ship = sv.shooter
		var to_shooter := U.hyp(sh.tx - shooter.x, sh.tz - shooter.z) < U.hyp(ref.x - shooter.x, ref.y - shooter.z)
		if to_shooter:
			sv.short += 1
		else:
			sv.over += 1
	if sv.landed == sv.shells:
		var s: Ship = sv.shooter
		# watching the fall of shot (or ranging it by radar) improves the solution
		if sv.tgt and not sv.manual and s.contact(sv.tgt):
			var straddle: bool = sv.short > 0 and sv.over > 0
			s.q = clampf(s.q + (0.28 if straddle else 0.16) * s.eff(), 0.0, 0.95)
		# misses are shown by the splashes; hits speak for themselves in damage()
		if camst.salvo == sv:
			camst.hold = 2.0


# =====================================================================
# damage
# =====================================================================

## Apply one hit at ship coordinates (lx, lz). dmg: 5-inch shell = 1.0. kind: "shell" or "torpedo".
## Builds one message that says what the hit did ("Hit aft: Mount 54 knocked out; fire aft").
func damage(s: Ship, lx: float, lz: float, dmg: float, kind: String, shooter: Ship = null) -> void:
	if not s.alive:
		return
	var isp := s.is_player
	var best = null
	var bd := 1e9
	for m in s.modules:
		var d: float = absf(m.x - lx) + (0.0 if m.kind == "mount" or m.kind == "torp" else 1.5)
		if d < bd:
			bd = d; best = m
	var small = s.T.L < 40.0
	var raw := randf_range(18, 40) if kind == "torpedo" else randf_range(3, 10) * dmg * (0.7 if small else 1.0)
	# light guns barely scratch a big steel ship
	var light_vs_big = kind != "torpedo" and not small and dmg < 0.3
	if light_vs_big:
		raw *= 0.25
	var crew_loss := int(raw) + (1 if randf() < raw - floorf(raw) else 0)
	s.crew = maxi(0, s.crew - crew_loss)
	var seen_by_player: bool = player.contact(s)
	var reach := 14.0 if kind == "torpedo" else (2.5 if small else 7.0)
	var what: Array = []   # what this hit did, in words
	if best and bd < reach:
		var before: float = best.hp
		best.hp = maxf(0.0, best.hp - dmg * (4.0 if kind == "torpedo" else 1.0))
		if best.ref != null:
			best.ref.hp = best.hp   # the mount or tube itself stops working
		if best.hp <= 0.0 and before > 0.0:
			match best.kind:
				"mount": what.append("%s knocked out" % _pretty(best.label))
				"torp": what.append("%s wrecked" % _pretty(best.label))
				"bridge": what.append("bridge wrecked, conning from aft")
				"director": what.append("gun director destroyed, guns in local control")
				"engine": what.append("%s out of action" % best.label.to_lower())
				"steering": what.append("steering gear destroyed, rudder jammed")
				"magazine": what.append("%s flooded to prevent an explosion" % best.label.to_lower())
				"fuel": what.append("gas tanks holed")
				"cargo": what.append("%s wrecked" % best.label.to_lower())
				"oil": what.append("%s ruptured, oil burning" % best.label.to_lower())
			if best.kind == "steering":
				s.rud_jam_until = 1e9
			if best.kind == "torp" and best.ref.left > 0 and randf() < 0.18:
				var mx: float = best.x
				after(0.4, func():
					var wp := s.to_world_xz(mx, 0.0)
					fx.boom(wp.x, 6.0, wp.y, true)
					sfx.play("boom", wp, cam.position, 1.0)
					say(("Our " if isp else s.ship_name + ": ") + "torpedo warheads detonated!", "bad" if isp else "good")
					s.flood += 160.0
					add_hole(s, mx, 1.0 if randf() < 0.5 else -1.0, 6.0)
					s.crew = maxi(0, s.crew - 25)
					add_fire(s, mx, 0.0, 1.0)
				)
				best.ref.left = 0
		elif best.hp > 0.0 and before > best.hp and dmg >= 0.5:
			# damaged, still working
			match best.kind:
				"mount": what.append("%s damaged" % _pretty(best.label))
				"bridge": what.append("bridge damaged")
				"director": what.append("director hit")
				"engine": what.append("%s hit, losing steam" % best.label.to_lower())
				"torp": what.append("%s damaged" % _pretty(best.label))
		if best.kind == "steering" and best.hp > 0.0 and randf() < 0.3:
			s.rud_jam_until = t + 20.0
			what.append("rudder jammed")
		# gasoline on PT boats and oil in tankers catch fire easily
		if best.kind == "fuel" and randf() < 0.5 * minf(1.0, dmg * 3.0):
			var f1 := add_fire(s, best.x, 0.0, 1.0)
			what.append("gasoline fire" + ("" if f1 == "" else " " + f1))
		if best.kind == "oil" and randf() < 0.6 * minf(1.0, dmg * 2.0):
			var f2 := add_fire(s, best.x, 0.0, 1.2)
			if f2 != "":
				what.append("oil fire " + f2)
		if best.kind == "magazine" and randf() < (0.12 if kind == "torpedo" else 0.035) * (mag_chance() if isp else 1.0):
			magazine_boom(s, best.x)
			return
	# shell holes near the waterline and torpedo hits let the sea in
	if kind == "torpedo":
		# a big hole: the first rush of water comes in at once, then it keeps flooding until patched
		what.append(add_hole(s, lx, 1.0 if lz >= 0.0 else -1.0, 12.0 * clampf(s.T.displacement / 2500.0, 0.4, 3.0)))
		s.flood += s.T.displacement * 0.10
	elif randf() < 0.45 * minf(1.0, dmg * 1.5):
		var hole := add_hole(s, lx, 1.0 if lz >= 0.0 else -1.0, randf_range(1.0, 3.0) * dmg * (0.12 if small else 1.0))
		if dmg >= 0.5 or small:
			what.append(hole)   # light shells only nick a big hull; not worth a report
	if randf() < (0.8 if kind == "torpedo" else 0.4 * minf(1.0, dmg * 2.0) * (0.3 if light_vs_big else 1.0)):
		var f3 := add_fire(s, lx, lz, 0.8 if kind == "torpedo" else 0.4)
		if f3 != "":
			what.append("fire started " + f3)
	_hit_report(s, lx, what, dmg, kind, seen_by_player, shooter != null and shooter.is_player)


## One message per hit that mattered. Hits that did nothing are summed up now and then,
## and only for the player's own shooting or hits on the player's ship.
func _hit_report(s: Ship, lx: float, what: Array, dmg: float, kind: String, seen: bool, mine: bool) -> void:
	var isp := s.is_player
	if not isp and not seen:
		return
	var where := "forward" if lx > s.T.L * 0.15 else ("aft" if lx < -s.T.L * 0.15 else "amidships")
	var head := "Torpedo hit" if kind == "torpedo" else "Hit"
	var who := "" if isp else s.ship_name + ": "
	var tone := "bad" if isp else "good"
	if not what.is_empty():
		var txt: String = "%s%s %s: %s." % [who, head, where, "; ".join(what)]
		say(txt[0].to_upper() + txt.substr(1), tone)
		if isp and kind == "torpedo":
			shake = maxf(shake, 2.0)
		return
	# nothing important broke: one line every few seconds so the log stays readable
	if not (isp or mine):
		return
	var key: String = s.ship_name
	var gap := 6.0 if dmg >= 0.5 else 10.0
	if t - _hit_msg_t.get(key, -99.0) < gap:
		return
	_hit_msg_t[key] = t
	if dmg >= 0.5:
		say("%s%s %s, no serious damage." % [who, head, where], tone)
	elif isp:
		say("Under light gunfire %s, no serious damage." % where, tone)
	else:
		say("%shit by our light guns %s." % [who, where], tone)


func _pretty(label: String) -> String:
	# "Mount51" -> "Mount 51"
	var out := ""
	var added := false
	for ch in label:
		if not added and ch >= "0" and ch <= "9":
			out += " "
			added = true
		out += ch
	return out


## Opens a hole; returns words for the hit report ("flooding forward, starboard side").
func add_hole(s: Ship, lx: float, side: float, rate: float) -> String:
	s.holes.append({"lx": lx, "side": side, "rate": rate, "fix": 0.0})
	var where := "forward" if lx > s.T.L * 0.15 else ("aft" if lx < -s.T.L * 0.15 else "amidships")
	return "flooding %s, %s side" % [where, "starboard" if side > 0.0 else "port"]


## Starts (or feeds) a fire; returns where it started for the hit report, "" if it only grew.
func add_fire(s: Ship, lx: float, lz: float, intensity: float) -> String:
	var span := 8.0 if s.T.L > 50.0 else 3.0
	for f in s.fires:
		if absf(f.lx - lx) < span:
			f.int = minf(1.5, f.int + intensity * 0.6)
			return ""
	s.fires.append({"lx": lx, "lz": clampf(lz, -s.T.B * 0.25, s.T.B * 0.25), "int": intensity})
	return "forward" if lx > s.T.L * 0.15 else ("aft" if lx < -s.T.L * 0.15 else "amidships")


func magazine_boom(s: Ship, mx: float) -> void:
	var w := s.to_world_xz(mx, 0.0)
	fx.boom(w.x, 10.0, w.y, true)
	fx.boom(w.x + randf_range(-20, 20), 14.0, w.y + randf_range(-20, 20), true)
	fx.debris(w.x, 12.0, w.y, 70, 45.0)
	fx.pyro_explosion(Vector3(w.x, 8.0, w.y), 22.0, 14.0)
	fx.light(Vector3(w.x, 60.0, w.y), 3200.0, Color(1.0, 0.6, 0.25), 16.0, 2.5)
	for i in 40:
		var c := Color(0.1 + randf() * 0.08, 0.09 + randf() * 0.07, 0.08 + randf() * 0.06)
		fx.smoke(w.x + randf_range(-25, 25), randf_range(10, 40), w.y + randf_range(-25, 25), randf_range(-4, 4), randf_range(-4, 4), randf_range(8, 16), randf_range(1.5, 3), randf_range(40, 70), randf_range(0.5, 0.8), c, 3.0)
	s.mag_blown = true
	s.crew = maxi(0, int(round(s.crew * 0.08)))
	s.flood = s.T.displacement * 2.0
	say("MAGAZINE EXPLOSION! The ship is breaking up!" if s.is_player else "%s has blown up! Magazine explosion!" % s.ship_name, "bad" if s.is_player else "good")
	shake = maxf(shake, 3.0 if s.is_player else 1.0)
	sfx.play("boom", w, cam.position, 1.6)


# =====================================================================
# torpedoes
# =====================================================================

func launch_torps(s: Ship, tgt: Ship, only_mount := -1) -> int:
	# AI: aim at the intercept point
	var ip: Array = s.torp_intercept(tgt, s.x, s.z)
	var p: Vector2 = ip[0]
	var brg := s.bearing_to(p.x, p.y)
	var rb := U.ang_d(s.h, brg)
	var ok: Array = s.torp_mounts_for(brg)
	if only_mount >= 0:
		ok = ok.filter(func(i): return i == only_mount)
	# AI PT boats only fire when the bow is nearly on the mark
	if not ok.is_empty() and s.torps[ok[0]].fixed and absf(rb) > deg_to_rad(12.0):
		return 0
	return fire_torps_along(s, brg, ok)


## Fire torpedoes along a compass bearing from the given mounts.
## Fixed racks (PT boats) fire two at a time, one from each side; trainable mounts fire one
## mount's full load in a fan.
func fire_torps_along(s: Ship, brg: float, mounts: Array) -> int:
	if mounts.is_empty():
		return 0
	var TT: Dictionary = s.T.torp
	var spd := s.torp_speed()
	var e := s.eff()
	var fired := 0
	var fixed: bool = s.torps[mounts[0]].fixed
	var use: Array = mounts.slice(0, 2) if fixed else mounts.slice(0, 1)
	for j in use.size():
		var m: Dictionary = s.torps[use[j]]
		m.ang = 0.0 if m.fixed else U.ang_d(s.h, brg)
		var count: int = m.left
		var spread := deg_to_rad(2.0 if m.fixed else 1.4)
		for k in count:
			var off: float = (k - (count - 1) / 2.0) * spread
			var lz := 0.0
			if m.fixed:
				var sd := -1.0 if j == 0 else 1.0
				off = spread * 0.5 * sd
				lz = s.T.B * 0.4 * sd
			var a: float = brg + off + U.gauss() * deg_to_rad(0.5) / e
			var mp := s.to_world_xz(m.x, lz)
			after(k * 0.6 + j * 0.35, func():
				torps.append({"x": mp.x + sin(a) * 6.0, "z": mp.y - cos(a) * 6.0, "h": a, "v": spd, "left": TT.range, "team": s.team, "owner": s, "dud": randf() < TT.dud, "warned": false, "depth": 3.0})
				sfx.play("torp", mp, cam.position, 0.4)
			)
		m.left = 0
		fired += count
	if s.is_player:
		stats.torps += fired
	if combat_t < 0.0 and fired > 0 and (s.is_player or s.team != player.team):
		combat_t = t
	return fired


func step_torps(dt: float) -> void:
	for tp in torps:
		var d: float = tp.v * dt
		tp.x += sin(tp.h) * d
		tp.z -= cos(tp.h) * d
		tp.left -= d
		if randf() < dt * 18.0:
			fx.foam(tp.x, tp.z, 0, 0, randf_range(0.8, 1.4), 0.5, randf_range(4, 7), 0.6)
		for s in ships:
			if s.team == tp.team or s.sink > 2.0:
				continue
			if s.inside_hull(tp.x, tp.z, 0.8):
				# torpedoes set to run at warship depth pass under shallow craft
				if s.T.get("draft", 4.0) < tp.get("depth", 3.0) * 0.6:
					if not tp.get("under", false):
						tp.under = true
						if tp.team == "us" and not _under_msg:
							_under_msg = true
							say("Our torpedo ran under %s: too shallow for it. Use the guns." % s.ship_name)
					continue
				tp.dead = true
				if tp.dud:
					if s.is_player or tp.team == "us":
						say("Torpedo hit %s, but it was a dud." % s.ship_name if tp.team == "us" else "Torpedo struck us but did not explode!", "" if tp.team == "us" else "good")
					break
				var l = s.to_local_xz(tp.x, tp.z)
				fx.boom(tp.x, 2.0, tp.z, true)
				for i in 20:
					fx.add(Fx.SPLASH, tp.x + randf_range(-6, 6), 3.0, tp.z + randf_range(-6, 6), 0, 0, 0, randf_range(6, 10), 14.0, 3.5, 1.0, Color(0.95, 0.98, 1.0), 1.0)
				sfx.play("boom", Vector2(tp.x, tp.z), cam.position, 1.2)
				if s.is_player:
					shake = maxf(shake, 2.0)
				if tp.team == "us":
					stats.torp_hits += 1
				damage(s, l.x, l.y, 1.0, "torpedo", tp.owner)
				break
		# warn the player about wakes the lookouts can see
		if not tp.warned and tp.team != player.team and player.alive:
			var dist := U.hyp(tp.x - player.x, tp.z - player.z)
			var W: Dictionary = Data.WEATHER[weather]
			var see := 500.0 if W.night else (600.0 if weather == "fog" else 1400.0)
			if dist < see:
				tp.warned = true
				if t - _torp_warn_t > 4.0:
					_torp_warn_t = t
					say("Torpedo wakes! Bearing %s." % U.deg3(player.bearing_to(tp.x, tp.z)), "bad")
					sfx.play("alarm", Vector2(player.x, player.z), cam.position, 0.6)
		if tp.left <= 0.0:
			tp.dead = true
	for tp in torps:
		if tp.get("under", false):
			var still := false
			for o in ships:
				if o.team != tp.team and o.inside_hull(tp.x, tp.z, 1.0):
					still = true
			if not still:
				tp.under = false
	torps = torps.filter(func(tp): return not tp.get("dead", false))


# =====================================================================
# ships
# =====================================================================

func step_ship(s: Ship, dt: float) -> void:
	if s.escaped:
		return
	var TT: Dictionary = s.T
	var e := s.eff()
	if s.alive:
		var target_v: float = Data.TELE[s.tele].kn * Data.KN
		var mx := s.max_kn() * Data.KN
		var want := clampf(target_v, -mx * 0.4, mx)
		s.v += clampf(want - s.v, -0.4 * dt, 0.25 * dt)
		if t > s.rud_jam_until:
			s.rud += clampf(s.rud_cmd - s.rud, -4.0 * dt, 4.0 * dt)
		var turn: float = (s.rud / 35.0) * deg_to_rad(TT.turn) * clampf(s.v / (25.0 * Data.KN), -0.5, 1.15)
		s.h = fposmod(s.h + turn * dt, TAU)
		# flooding, pumping and repairs
		var inflow := 0.0
		var sd := 0.0
		var fw := 0.0
		for hl in s.holes:
			var rate: float = hl.rate * (1.0 - hl.fix)
			inflow += rate
			sd += rate * hl.side
			fw += rate * clampf(hl.lx / 50.0, -1.0, 1.0)
			hl.fix = minf(0.92, hl.fix + dt * 0.012 * e / maxf(1.0, hl.rate / 4.0))
		var pump := 1.6 * e * pow(TT.displacement / 2500.0, 0.7)
		s.flood = maxf(0.0, s.flood + (inflow - pump) * dt)
		s.flood_side = lerpf(s.flood_side, sd / inflow if inflow > 0.0 else s.flood_side * 0.99, dt * 0.2)
		s.flood_fwd = lerpf(s.flood_fwd, fw / inflow if inflow > 0.0 else s.flood_fwd * 0.99, dt * 0.2)
		# fires spread, hurt crew and equipment; damage control fights them
		for f in s.fires:
			f.int += dt * (0.025 - 0.06 * e)
			# casualties from fire scale with how many men are aboard
			if randf() < dt * 0.4 * f.int * clampf(float(TT.crew) / 300.0, 0.04, 1.0):
				s.crew = maxi(0, s.crew - 1)
			for m in s.modules:
				if absf(m.x - f.lx) < 6.0 and m.hp > 0.0:
					m.hp = maxf(0.0, m.hp - dt * 0.02 * f.int)
					if m.ref != null:
						m.ref.hp = m.hp
					if m.hp <= 0.0 and (s.is_player or player.contact(s)):
						say("%s%s burnt out by the fire." % ["" if s.is_player else s.ship_name + ": ", _pretty(m.label)], "bad" if s.is_player else "good")
					if m.kind == "magazine" and f.int > 0.8 and randf() < dt * 0.0015 * (mag_chance() if s.is_player else 1.0):
						magazine_boom(s, m.x)
						return
		var nf := s.fires.size()
		s.fires = s.fires.filter(func(f): return f.int > 0.03)
		if s.is_player and nf > s.fires.size():
			say("Fire extinguished.", "good")
		var cap := s.flood_cap()
		var fl := s.flood / cap
		s.roll = lerpf(s.roll, deg_to_rad(clampf(s.flood_side * fl * 26.0, -40.0, 40.0)), dt * 0.4)
		s.pitch = lerpf(s.pitch, deg_to_rad(clampf(s.flood_fwd * fl * 4.0, -8.0, 8.0)), dt * 0.4)
		s.sink = lerpf(s.sink, fl * 1.3, dt * 0.3)
		if s.flood >= cap or s.crew <= 0:
			s.alive = false
			s.sinking = 0.001
			s.fire = false
			say("Abandon ship! She is going down." if s.is_player else "%s is sinking!" % s.ship_name, "bad" if s.is_player else "good")
			if s.team != player.team:
				stats.sunk.append(s.ship_name)
	else:
		s.sinking += dt
		var fast := 3.0 if s.mag_blown else 1.0
		s.v *= exp(-dt * 0.5)
		s.roll = lerpf(s.roll, (1.0 if s.flood_side >= 0.0 else -1.0) * deg_to_rad(30.0 if s.mag_blown else 70.0), dt * 0.03 * fast)
		s.pitch = lerpf(s.pitch, (1.0 if s.flood_fwd >= 0.0 else -1.0) * deg_to_rad(12.0), dt * 0.03 * fast)
		s.sink += dt * 0.12 * fast
		if randf() < dt * 2.0:
			fx.oil(s.x + randf_range(-20, 20), s.z + randf_range(-20, 20), randf_range(8, 18))
		if randf() < dt * 0.8:
			fx.debris(s.x + randf_range(-30, 30), 2.0, s.z + randf_range(-30, 30), 2, 4.0)
		if s.sink > 16.0:
			s.gone = true
		for f in s.fires:
			f.int *= exp(-dt * 0.1)
	var fv := U.fwd(s.h)
	s.x += fv.x * s.v * dt
	s.z += fv.y * s.v * dt
	if s.illum > 0.0:
		s.illum -= dt
	if s.gone:
		return
	# effects: fires, funnel smoke, smoke screen, oil, wake
	_sync_fire_nodes(s)
	for fr in s.fires:
		var wp := s.to_world_xz(fr.lx, fr.lz)
		if randf() < dt * 9.0 * fr.int:
			fx.fire_puff(wp.x + randf_range(-2, 2), 7.0, wp.y + randf_range(-2, 2), randf_range(2, 4) * (0.6 + fr.int))
		if randf() < dt * 5.0 * fr.int:
			fx.smoke(wp.x, 10.0, wp.y, 0, 0, randf_range(4, 7), 3.5, randf_range(14, 22), 0.75, Color(0.08, 0.075, 0.07), 1.2)
		if fr.int > 0.2 and randf() < dt * 6.0:
			fx.light(Vector3(wp.x, 14.0, wp.y), 320.0 * (0.6 + fr.int), Color(1.0, 0.5, 0.18), 4.0, 0.3)
	if s.alive and randf() < dt * 3.0:
		for fxp in TT.funnels:
			var wp := s.to_world_xz(fxp, 0.0)
			fx.smoke(wp.x, TT.funnel_top, wp.y, 0, 0, randf_range(2.0, 3.0), 1.1, randf_range(7, 10), 0.12 + 0.14 * (s.v / (36.0 * Data.KN)), Color(0.42, 0.42, 0.4), 0.4)
	if s.smoke_on and s.alive:
		if randf() < dt * 5.0:
			for fxp in TT.funnels:
				var wp := s.to_world_xz(fxp, 0.0)
				fx.smoke(wp.x, TT.funnel_top, wp.y, randf_range(-1, 1), randf_range(-1, 1), randf_range(6, 9), randf_range(0.6, 0.9), randf_range(110, 150), 0.5, Color(0.13, 0.13, 0.13), 0.15)
		if TT.has("smoke_x") and randf() < dt * 6.0:
			var sp := s.to_world_xz(TT.smoke_x, 0.0)
			fx.smoke(sp.x, 2.0, sp.y, randf_range(-1, 1), randf_range(-1, 1), randf_range(5, 8), randf_range(0.7, 1.0), randf_range(110, 150), 0.55, Color(0.75, 0.76, 0.76), 0.1)
		s.smoke_acc += dt
		if s.smoke_acc > 1.2:
			s.smoke_acc = 0.0
			var wp := s.to_world_xz(TT.get("smoke_x", -50.0) - 8.0, 0.0)
			smokes.append({"x": wp.x, "z": wp.y, "r": 20.0, "rmax": 95.0, "density": 0.5, "age": 0.0, "life": 150.0})
	if s.alive and s.dest_dist > 0.0:
		s.dest_dist -= absf(s.v) * dt
		if s.dest_dist <= 0.0 and not s.escaped:
			s.escaped = true
			s.gone = true
			s.alive = false
			stats.escaped.append(s.ship_name)
			say("%s has reached safety." % s.ship_name, "bad")
	if (s.flood > TT.displacement * 0.025 or s.mod_health("engine") < 0.6) and randf() < dt * 0.7 and TT.L > 40.0:
		var wp := s.to_world_xz(-TT.L / 2.0 - 5.0, 0.0)
		fx.oil(wp.x, wp.y, randf_range(5, 9))
	_spawn_wake(s, dt)
	for m in s.mounts:
		m.recoil = maxf(0.0, m.recoil - dt * 2.5)
		m.reload = maxf(0.0, m.reload - dt)
	# Japanese destroyers carried reloads for their torpedo tubes
	for tp in s.torps:
		if tp.hp > 0.0 and tp.left == 0 and s.type_id == "kagero":
			tp.reload_t += dt
			if tp.reload_t > 150.0:
				tp.left = tp.n
				tp.reload_t = 0.0


## Keep a PYROLUX fire burning on deck for every fire in the ship's list.
func _sync_fire_nodes(s: Ship) -> void:
	var keep := {}
	for fr in s.fires:
		var n = fr.get("node")
		if n == null or not is_instance_valid(n):
			# ship coordinates: forward is -z, starboard is +x, deck about 6 m up
			n = fx.pyro_fire(s, Vector3(fr.lz, 6.0, -fr.lx), 3.0)
			fr.node = n
		if n:
			n.scale = Vector3.ONE * (2.5 + fr.int * 4.0)
			keep[n] = true
	for c in s.get_children():
		if c.is_in_group("pyro_fire") and not keep.has(c) and c.is_burning():
			c.free_when_done = true
			c.extinguish()


func _emit(rate: float, k: float, dt: float) -> int:
	var nn := rate * k * dt
	var c := 0
	while nn > 0.0:
		if randf() < nn:
			c += 1
		nn -= 1.0
	return c


func _spawn_wake(s: Ship, dt: float) -> void:
	var v := absf(s.v)
	var k := clampf(v / (30.0 * Data.KN), 0.0, 1.3)
	if k < 0.04 or s.sink > 4.0:
		return
	var L: float = s.T.L / 2.0
	var B: float = s.T.B
	var f := U.fwd(s.h)
	var r := Vector2(cos(s.h), sin(s.h))
	# bow wave
	for i in _emit(50, k, dt):
		var lx := randf_range(L - 10.0, L - 1.0)
		var sd := -1.0 if randf() < 0.5 else 1.0
		var wp := s.to_world_xz(lx, sd * (s.half_width_at(lx) + 0.4))
		var o := randf_range(4, 8) * k
		fx.foam(wp.x, wp.y, r.x * sd * o + f.x * o * 0.3, r.y * sd * o + f.y * o * 0.3, randf_range(1.6, 3), 0.7, randf_range(4, 6), 0.9)
	# water along the sides
	for i in _emit(60, k, dt):
		var lx := randf_range(-L + 6.0, L - 10.0)
		var sd := -1.0 if randf() < 0.5 else 1.0
		var wp := s.to_world_xz(lx, sd * (s.half_width_at(lx) + 0.5))
		var o := randf_range(0.5, 2) * k
		fx.foam(wp.x, wp.y, r.x * sd * o, r.y * sd * o, randf_range(1.2, 2.2), 0.35, randf_range(4, 6), 0.5)
	# propeller wash astern
	for i in _emit(45, k, dt):
		var wp := s.to_world_xz(-L - 2.0, randf_range(-1, 1) * B * 0.3)
		var o := randf_range(2, 6) * k
		fx.foam(wp.x, wp.y, -f.x * o + r.x * randf_range(-1, 1), -f.y * o + r.y * randf_range(-1, 1), randf_range(2.5, 4.5), 0.7, randf_range(14, 22), 0.6)
	# Kelvin wake arms
	for i in _emit(25, k, dt):
		var sd := -1.0 if randf() < 0.5 else 1.0
		var d := randf_range(5, 40)
		var wp := s.to_world_xz(-L - d, sd * (B * 0.4 + d * 0.36))
		fx.foam(wp.x, wp.y, r.x * sd * 0.6, r.y * sd * 0.6, randf_range(1.2, 2.2), 0.4, randf_range(10, 16), 0.45)


# =====================================================================
# enemy AI
# =====================================================================

func step_ai(s: Ship, dt: float) -> void:
	if not s.alive or s.escaped:
		return
	s.ai_turn -= dt
	if s.ai_turn > 0.0:
		return
	s.ai_turn = 0.5
	ai.step(s)


func star_shell(x: float, z: float) -> void:
	stars.append({"x": x, "z": z, "age": 0.0, "life": 28.0})
	fx.flash(x, 300.0, z, 4.0, 0.0, 28.0, Color(1.0, 1.0, 0.9))
	if U.hyp(x - player.x, z - player.z) < 1200.0:
		player.illum = 28.0
		say("Star shell bursting overhead. We are lit up!", "bad")


# =====================================================================
# fire control (player and AI)
# =====================================================================

func step_fire_control(s: Ship, dt: float) -> void:
	var tgt: Ship = s.target if s.target and s.target.alive and not s.target.escaped else null
	var has_contact := tgt != null and s.contact(tgt)
	if tgt != s.q_target:
		s.q = 0.0
		s.q_target = tgt
	if absf(s.rud) > 15.0:
		s.q = maxf(0.0, s.q - dt * 0.02)
	if tgt and absf(tgt.rud) > 15.0:
		s.q = maxf(0.0, s.q - dt * 0.015)
	var manual := s.is_player and aim_mode == "manual"
	var R := s.range_to(tgt) if tgt else 1e9
	var f := U.fwd(tgt.h) if tgt else Vector2.ZERO
	var rb_main = null
	var batteries := {}
	for m in s.mounts:
		if m.hp <= 0.0:
			continue
		var g: Dictionary = m.gun
		var rbm = null
		if manual:
			rbm = s.rel_bearing(mouse_w.x, mouse_w.y) if mouse_w != null else null
		elif has_contact:
			var tof := s.tof_for(R, g)
			rbm = s.rel_bearing(tgt.x + f.x * tgt.v * tof, tgt.z + f.y * tgt.v * tof)
		if g == s.gun:
			rb_main = rbm
		var want: float = m.stow
		if rbm != null:
			want = rbm if Ship.mount_can_bear(m, rbm) else Ship.arc_clamp(m, rbm)
		var light: bool = g.dmg < 0.5
		var rate := deg_to_rad(60.0 if light else 15.0) * (0.6 + 0.4 * s.eff())
		m.ang += clampf(U.ang_d(m.ang, want), -rate * dt, rate * dt)
		m.on = rbm != null and Ship.mount_can_bear(m, rbm) and absf(U.ang_d(m.ang, rbm)) < deg_to_rad(4.0 if light else 1.5)
		m.bears = rbm != null and Ship.mount_can_bear(m, rbm)
		if not batteries.has(g.cal):
			batteries[g.cal] = []
		batteries[g.cal].append(m)
	var dir_want: float = rb_main if rb_main != null else 0.0
	s.dir_ang += clampf(U.ang_d(s.dir_ang, dir_want), -deg_to_rad(40.0) * dt, deg_to_rad(40.0) * dt)
	for i in s.aa_ang.size():
		s.aa_ang[i] += clampf(sin(t * 0.2 + i) * 0.6 - s.aa_ang[i], -dt, dt)
	if manual:
		if click_shot != null:
			var aim: Vector2 = click_shot
			click_shot = null
			var Ra := U.hyp(aim.x - s.x, aim.y - s.z)
			var rba := s.rel_bearing(aim.x, aim.y)
			var any_fired := false
			var any_bear := false
			var any_range := false
			for cal in batteries:
				var ok := []
				var g: Dictionary = batteries[cal][0].gun
				for m in batteries[cal]:
					if Ship.mount_can_bear(m, rba):
						any_bear = true
						if Ra <= g.range_max:
							any_range = true
							if m.reload <= 0.0 and absf(U.ang_d(m.ang, rba)) < deg_to_rad(5.0):
								ok.append(m)
				if not ok.is_empty():
					fire_at(s, aim, ok, g)
					any_fired = true
			if not any_fired:
				say("No guns bear on that bearing." if not any_bear else ("Out of gun range." if not any_range else "Guns still training or loading."))
		return
	if not (s.fire and has_contact):
		return
	for cal in batteries:
		var list: Array = batteries[cal]
		var g: Dictionary = list[0].gun
		if R > g.range_max or s.bat_busy.get(cal, false):
			continue
		var ready := []
		var bearing_n := 0
		for m in list:
			if m.bears:
				bearing_n += 1
				if m.on and m.reload <= 0.0:
					ready.append(m)
		if ready.is_empty():
			continue
		if ready.size() == bearing_n or t - s.bat_last.get(cal, -99.0) > g.reload * 2.2:
			s.bat_busy[cal] = true
			s.bat_last[cal] = t
			fire_salvo(s, tgt, ready, g)
			after(minf(0.8, g.reload * 0.5), func(): s.bat_busy[cal] = false)


# =====================================================================
# player orders (called from keys and HUD buttons)
# =====================================================================

func order_tele(i: int) -> void:
	player.tele = clampi(i, 0, Data.TELE.size() - 1)

func order_rudder(deg: float) -> void:
	player.rud_cmd = clampf(deg, -35.0, 35.0)

func toggle_fire() -> void:
	if aim_mode == "manual":
		say("Manual aim: click on the water to fire. Press M for crew aim.")
		return
	if not player.alive:
		return
	if not player.target:
		cycle_target()
	player.fire = not player.fire
	if player.fire and player.target:
		say("Commence firing on %s." % player.target.ship_name)
	elif not player.fire:
		say("Cease fire.")

func set_aim(mode: String) -> void:
	aim_mode = mode
	if mode == "manual":
		player.fire = false
		say("Manual aim. Point and click where the shells should land. Right-click selects a target.")
	else:
		say("Crew aim. The fire-control crew aims at your target. F to open or cease fire.")
	hud.on_aim()

func fire_torpedoes() -> void:
	# T toggles torpedo aiming: the mouse picks the bearing, a click fires
	if not player.alive:
		return
	if player.torps.is_empty() or player.torps_left() == 0:
		say("No torpedoes left.")
		torp_aim = false
		return
	torp_aim = not torp_aim
	if torp_aim:
		say("Torpedo aim. Point the fan at the lead marker and click to fire. T or Esc to cancel.")


## Fire at the bearing the player picked in torpedo aim mode.
func torp_click(w: Vector2) -> void:
	var brg := player.bearing_to(w.x, w.y)
	var ok: Array = player.torp_mounts_for(brg)
	if ok.is_empty():
		if not player.torps.is_empty() and player.torps[0].fixed:
			say("Torpedoes can only be angled 30 degrees off the bow. Turn toward the target.")
		else:
			say("No loaded torpedo mount bears that way. Torpedoes fire off the beam.")
		return
	var n := fire_torps_along(player, brg, ok)
	if n > 0:
		say("Torpedoes away: %d fish running on bearing %s." % [n, U.deg3(brg)])
	if player.torps_left() == 0:
		torp_aim = false


func toggle_smoke() -> void:
	player.smoke_on = not player.smoke_on
	say("Making smoke." if player.smoke_on else "Secure from making smoke.")

func cycle_target() -> void:
	var list := []
	for s in ships:
		if s.team != "us" and s.alive and not s.escaped and player.contact(s):
			list.append(s)
	if list.is_empty():
		say("No contacts to target.")
		return
	var i := list.find(player.target)
	player.target = list[(i + 1) % list.size()]
	say("Target: %s, range %s." % [player.target.ship_name, U.yards(player.range_to(player.target))])

func pick_target_at(w: Vector2) -> bool:
	var best: Ship = null
	var bd := maxf(250.0, camst.h * 0.08)
	for s in ships:
		if s.team != "us" and s.alive and player.contact(s):
			var d := U.hyp(s.x - w.x, s.z - w.y)
			if d < bd:
				bd = d; best = s
	if best:
		player.target = best
		say("Target: %s, range %s." % [best.ship_name, U.yards(player.range_to(best))])
		return true
	return false


# =====================================================================
# camera
# =====================================================================

func screen_to_world(sp: Vector2):
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	if absf(d.y) < 1e-4:
		return null
	var k := -o.y / d.y
	if k < 0.0:
		return null
	var p := o + d * k
	return Vector2(p.x, p.z)


func _update_camera(delta: float) -> void:
	var fs := focus_ship()
	var tx: float = fs.x + camst.ox
	var tz: float = fs.z + camst.oz
	if camst.free:
		tx = camst.ox; tz = camst.oz   # dragged: ox/oz hold an absolute point on the sea
	var sv = camst.salvo
	if sv != null:
		var live := []
		for sh in shells:
			if sh.salvo == sv:
				live.append(sh)
		if not live.is_empty():
			var sx := 0.0
			var sz := 0.0
			for sh in live:
				sx += sh.pos.x; sz += sh.pos.z
			tx = sx / live.size(); tz = sz / live.size()
			# zoom out enough to keep shooter and shells in view
			var need := U.hyp(tx - player.x, tz - player.z)
			camst.h = lerpf(camst.h, maxf(camst.th, need * 1.4), minf(1.0, delta * 1.5))
		elif camst.hold > 0.0:
			camst.hold -= delta * maxf(speed, 0.25)
			var ref: Vector2 = Vector2(sv.tgt.x, sv.tgt.z) if sv.tgt else sv.aim
			tx = ref.x; tz = ref.y
		else:
			camst.salvo = null
			if slow_follow and speed == 0.25:
				set_speed(prev_speed)
	if camst.salvo == null:
		camst.h = lerpf(camst.h, camst.th, minf(1.0, delta * 3.0))
	var k := minf(1.0, delta * (2.5 if camst.salvo != null else 6.0))
	camst.x = lerpf(camst.x, tx, k)
	camst.z = lerpf(camst.z, tz, k)
	var sh_off := Vector2.ZERO
	if shake > 0.0:
		sh_off = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * camst.h * 0.004
	var hgt: float = camst.h
	cam.near = maxf(0.5, hgt * 0.02)
	cam.far = hgt * 4.0 + 2000.0
	cam.look_at_from_position(Vector3(camst.x + sh_off.x, hgt, camst.z + sh_off.y), Vector3(camst.x + sh_off.x, 0.0, camst.z + sh_off.y), Vector3(0, 0, -1))
	# sea plane follows the camera and always fills the view
	var span := hgt * 2.5 + 4000.0
	ocean.position = Vector3(camst.x, 0.0, camst.z)
	ocean.scale = Vector3(span, 1.0, span)
	sun.directional_shadow_max_distance = clampf(hgt * 2.2, 300.0, 6000.0)
	# haze looks the same at every zoom: thicker per meter when the camera is low
	env.fog_density = Data.WEATHER[weather].fog_k / hgt


func zoom(factor: float) -> void:
	camst.th = clampf(camst.th * factor, 90.0, 14000.0)
	camst.salvo = null


## Dragging the view unlocks the camera from the ship it was tracking; Esc or a view button locks it again.
func pan(dx_px: float, dz_px: float) -> void:
	var k = 2.0 * tan(deg_to_rad(FOV) / 2.0) * camst.h / get_viewport().get_visible_rect().size.y
	if not camst.free:
		camst.free = true
		camst.ox = camst.x; camst.oz = camst.z
	camst.ox -= dx_px * k
	camst.oz -= dz_px * k
	camst.salvo = null


## Esc: lock the camera back on the ship it was tracking.
func recenter() -> void:
	camst.free = false
	camst.ox = 0.0; camst.oz = 0.0
