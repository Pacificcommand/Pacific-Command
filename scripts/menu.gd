extends Node3D
## Main menu: a close, low side view of a battleship (USS Washington, North Carolina
## class) at sea, her turrets trained out to starboard and firing rippling salvos.

var ship: Node3D
var fx: Fx
var cam: Camera3D
var cam_base := Vector3.ZERO
var shake := 0.0
var next_salvo := 1.2
var turrets := []        # [{node, x, y, ang}] trained main turrets
const SHIP_MODEL := "res://assets/models/north_carolina.glb"
## main turrets: name, x along the hull (m, + forward), height of the guns, training angle (rad, + to starboard)
const TURRETS := [["Turret1", 74.0, 9.0, 1.05], ["Turret2", 54.0, 11.0, 1.15], ["Turret3", -70.0, 7.6, 2.05]]
var ocean_mat: ShaderMaterial
var t := 0.0
var ui: Control
var buttons: VBoxContainer


func _ready() -> void:
	# command-line test runs (see CLAUDE.md) go straight to the battle
	for a in OS.get_cmdline_user_args():
		if a == "--careertest":
			_career_test()
			return
		if a.begins_with("--ops"):
			if Game.campaign.is_empty():
				Game.campaign = load("res://scripts/ops.gd").new_campaign(240, "fletcher", "USS O'Bannon")
			get_tree().change_scene_to_file.call_deferred("res://scenes/ops.tscn")
			return
		if a.begins_with("--scenario") or a.begins_with("--start") or a.begins_with("--load"):
			for b in OS.get_cmdline_user_args():
				if b.begins_with("--scenario="):
					Game.start_scenario = b.split("=")[1]
			get_tree().change_scene_to_file.call_deferred("res://scenes/battle.tscn")
			return
	_build_scene()
	_build_ui()
	Audio.music("menu")
	Audio.ambience("clear", 0.6)
	Audio.loop("fire", 0.0)
	Audio.loop("plane", 0.0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--menushot="):
			if "--settings" in OS.get_cmdline_user_args():
				_on_settings()
			if "--encyclopedia" in OS.get_cmdline_user_args():
				var ep := EncyclopediaPanel.new()
				ui.add_child(ep)
				for c in OS.get_cmdline_user_args():
					if c.begins_with("--cat="):
						ep.call_deferred("_pick_cat", int(c.split("=")[1]))
			_shot.call_deferred(a.split("=")[1])


func _shot(path: String) -> void:
	for i in 40:
		await get_tree().process_frame
	if "--menufire" in OS.get_cmdline_user_args() and fx:
		# screenshots of the salvo: one just after each turret fires
		next_salvo = 99.0
		_salvo()
		for k in 4:
			await get_tree().create_timer(0.1 + (0.35 if k > 0 else 0.0)).timeout
			get_viewport().get_texture().get_image().save_png(path.replace(".png", "_%d.png" % k))
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	get_tree().quit()


func _build_scene() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.38, 0.62)
	sm.sky_horizon_color = Color(0.66, 0.72, 0.78)
	sm.ground_horizon_color = Color(0.6, 0.66, 0.7)
	sm.ground_bottom_color = Color(0.2, 0.3, 0.36)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.7, 0.78)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.77, 0.8)
	env.fog_density = 0.00022
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.45, -0.8, -0.38), Vector3.UP)
	var ocean := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000, 9000)
	ocean.mesh = pm
	ocean_mat = ShaderMaterial.new()
	ocean_mat.shader = load("res://shaders/ocean.gdshader")
	ocean_mat.set_shader_parameter("foam_tex", load("res://assets/textures/boujie/foam_2.png"))
	ocean_mat.set_shader_parameter("detail_tex", load("res://assets/textures/boujie/ocean_albedo_2.png"))
	var W: Dictionary = Data.WEATHER.clear
	ocean_mat.set_shader_parameter("deep_color", W.deep.darkened(0.35))
	ocean_mat.set_shader_parameter("shallow_color", W.shallow.darkened(0.45))
	ocean_mat.set_shader_parameter("chop", 0.9)
	ocean_mat.set_shader_parameter("spec", 0.45)
	ocean.material_override = ocean_mat
	add_child(ocean)
	var scene: PackedScene = load(SHIP_MODEL)
	ship = scene.instantiate()
	# bow to +x (east), starboard side (+z) towards the camera
	ship.rotation.y = -PI / 2.0
	add_child(ship)
	for tt in TURRETS:
		var nd := ship.find_child(tt[0], true, false) as Node3D
		var stow := PI if tt[1] < 0.0 else 0.0
		if nd:
			nd.rotation.y = -(tt[3] - stow)
		turrets.append({"node": nd, "x": tt[1], "y": tt[2], "ang": tt[3]})
	fx = Fx.new()
	fx.billboard = true
	add_child(fx)
	fx.set_lit(1.0)
	cam = Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	# low over the water abeam, the bow and both forward turrets right of the menu
	cam_base = Vector3(36.0, 5.0, 165.0)
	cam.look_at_from_position(cam_base, Vector3(36.0, 15.0, 0.0), Vector3.UP)
	cam.make_current()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var v := UI.column(6)
	v.add_child(UI.label("UNITED STATES PACIFIC FLEET", 13, UI.BRASS))
	v.add_child(UI.label("Pacific Command", 56))
	v.add_child(UI.label("A naval war game, 1941 to 1945 · build %s" % Game.VERSION, 14, UI.MUTED))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 24
	v.add_child(spacer)
	buttons = UI.column(8)
	var cont := UI.big_button("Continue campaign", func(): get_tree().change_scene_to_file("res://scenes/ops.tscn"))
	cont.disabled = Game.campaign.is_empty()
	buttons.add_child(cont)
	buttons.add_child(UI.big_button("New campaign", _on_campaign))
	buttons.add_child(UI.big_button("Single battle", _on_new))
	var any_save := false
	for i in Game.SLOTS:
		if not Game.slot_info(i).is_empty():
			any_save = true
	var lb := UI.big_button("Load battle", _on_load)
	lb.disabled = not any_save
	buttons.add_child(lb)
	buttons.add_child(UI.big_button("Encyclopedia", func(): ui.add_child(EncyclopediaPanel.new())))
	buttons.add_child(UI.big_button("Settings", _on_settings))
	buttons.add_child(UI.big_button("Quit", func(): get_tree().quit()))
	v.add_child(buttons)
	var p := UI.panel(28)
	p.add_child(v)
	ui.add_child(p)
	p.anchor_left = 0.0; p.anchor_right = 0.0; p.anchor_top = 0.5; p.anchor_bottom = 0.5
	p.offset_left = 80; p.offset_right = 80; p.offset_top = -40; p.offset_bottom = -40
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.grow_horizontal = Control.GROW_DIRECTION_END
	var foot := UI.label("Design document and build log: claude.ai/artifact/6DsTxwe8UHnRugVtDqbLH2  ·  Godot 4.7", 11, UI.MUTED)
	ui.add_child(foot)
	foot.anchor_top = 1.0; foot.anchor_bottom = 1.0
	foot.offset_left = 16; foot.offset_top = -30; foot.offset_right = 900; foot.offset_bottom = -10


func _process(delta: float) -> void:
	if ocean_mat == null:
		return
	t += delta
	if ship:
		# a gentle roll and heave; she steams slowly so the bow wave stays alive
		ship.position.y = sin(t * 0.7) * 0.35
		ship.rotation.x = sin(t * 0.37) * deg_to_rad(0.35)
		ship.rotation.z = sin(t * 0.5) * deg_to_rad(0.9)
		_bow_wave(delta)
	next_salvo -= delta
	if next_salvo <= 0.0:
		_salvo()
		next_salvo = randf_range(5.5, 8.0)
	if fx:
		fx.step(delta)
		shake = maxf(shake - delta * 2.5, 0.0)
		cam.position = cam_base + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * shake * 0.6
		fx.render(cam.position)
	ocean_mat.set_shader_parameter("time_s", t)


## World point beside the hull: lx metres forward of amidships, lz to starboard, at height y.
func _hull_pt(lx: float, lz: float, y: float) -> Vector3:
	return Vector3(lx, y + ship.position.y, lz)


var _foam_t := 0.0
func _bow_wave(delta: float) -> void:
	_foam_t -= delta
	if _foam_t > 0.0:
		return
	_foam_t = 0.12
	for side in [-1.0, 1.0]:
		fx.foam(108.0 + randf_range(-2, 2), side * randf_range(4, 8), randf_range(-3, -1), side * randf_range(2, 4), randf_range(3, 5), 2.5, randf_range(3, 5), 0.6)
		fx.foam(randf_range(-100, 100), side * randf_range(15, 17), -1.5, side * 0.6, randf_range(2, 3.5), 1.2, 3.0, 0.3)


## One broadside: the three turrets ripple-fire, each with a flash, a light, a smoke cloud.
func _salvo() -> void:
	# the two forward turrets are in the picture; the aft one is off the left edge
	var order := [0, 1] if randf() < 0.5 else [1, 0]
	for j in 2:
		var tr: Dictionary = turrets[order[j]]
		get_tree().create_timer(j * 0.35).timeout.connect(func(): _fire(tr))


func _fire(tr: Dictionary) -> void:
	var a: float = tr.ang
	var dir := Vector3(cos(a), 0.0, sin(a))     # bow is +x, starboard +z
	var mz := _hull_pt(tr.x, 0.0, tr.y) + dir * 22.0
	# one burst per barrel, an orange core and a white-hot centre
	var side := Vector3(-dir.z, 0.0, dir.x)
	for b in [-1, 0, 1]:
		var bp: Vector3 = mz + side * (b * 2.4)
		fx.fire_puff(bp.x + dir.x * 4.0, bp.y, bp.z + dir.z * 4.0, 7.0)
		fx.flash(bp.x + dir.x * 6.0, bp.y, bp.z + dir.z * 6.0, 7.0, 22.0, 0.35, Color(1.0, 0.7, 0.35))
	fx.flash(mz.x + dir.x * 3.0, mz.y, mz.z + dir.z * 3.0, 5.0, 12.0, 0.16, Color(1.0, 0.95, 0.8))
	fx.light(mz + Vector3(0, 3, 0), 260.0, Color(1.0, 0.7, 0.4), 6.0, 0.3)
	for i in 5:
		var d := dir * randf_range(6, 26) + Vector3(randf_range(-4, 4), randf_range(-1, 3), randf_range(-4, 4))
		var p := mz + d * 0.4
		fx.smoke(p.x, p.y, p.z, d.x * 0.9, d.z * 0.9, randf_range(4, 7), 3.2, randf_range(5, 8), 0.6, Color(0.5, 0.47, 0.42), 0.5)
	# the blast flattens the sea under the muzzles
	for i in 5:
		fx.foam(mz.x + randf_range(-8, 8), mz.z + randf_range(-8, 8), dir.x * 6.0, dir.z * 6.0, randf_range(6, 10), 4.0, 3.0, 0.5)
	if tr.node:
		var n: Node3D = tr.node
		var base_y: float = n.position.y
		var tw := create_tween()
		tw.tween_property(n, "position:y", base_y - 0.25, 0.05)
		tw.tween_property(n, "position:y", base_y, 0.5)
	shake = maxf(shake, 1.0)
	Audio.ui("gun_large", 0.55)


## Headless check of the career rules (godot --headless --path . -- --careertest).
func _career_test() -> void:
	var c := Career.fresh("veteran")
	Career.take_command(c, "fletcher", "USS O'Bannon", 240)
	var t := {"salvos": 30, "hits": 9, "torps": 5, "torp_hits": 1, "kills": 2, "combat_min": 12.0, "underway_min": 20.0, "fires_out": 2, "holes_fixed": 3, "contacts": 4, "damage_done": 40.0, "crew_loss_frac": 0.2, "saved": 0, "big_kill": false, "summary": "test"}
	for i in 8:
		var lines := Career.apply_battle(c, t, "won", 3, 240 + i)
		print(i, " rank ", c.rank, " ", lines)
	print("crew ", Career.training_label(Career.ship(c).training), " medals ", c.medals.size(), " supply ", c.supply)
	for r in range(1, 9):
		for y in [1942, 1944]:
			var offs := []
			for o in Career.offer_options(r, y):
				offs.append(Career.describe_offer(o))
			print("offer rank ", r, " ", y, ": ", " | ".join(offs))
	get_tree().quit()


func _on_new() -> void:
	Game.pending_load = -1
	Game.mission = {}
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


func _on_load() -> void:
	var sp := SlotPanel.new("load")
	ui.add_child(sp)
	sp.picked.connect(func(i):
		Game.pending_load = i
		get_tree().change_scene_to_file("res://scenes/battle.tscn"))


func _on_campaign() -> void:
	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(UI.backdrop())
	var p := UI.panel(20)
	var v := UI.column(10)
	v.add_child(UI.label("NEW CAMPAIGN", 11, UI.BRASS))
	v.add_child(UI.label("Where do you join the war?", 22))
	var start := [0]
	var ship := ["fletcher", "USS O'Bannon"]
	var starts := [[0, "December 1941 · Pearl Harbor"], [240, "August 1942 · Guadalcanal"], [700, "November 1943 · Central Pacific"], [1040, "October 1944 · Philippines"]]
	var sb := UI.row([], 4)
	var start_btns := []
	for it in starts:
		var b := UI.button(it[1], func(): pass, true)
		b.pressed.connect(func(): start[0] = it[0]; for o in start_btns: o.set_pressed_no_signal(o == b))
		b.set_pressed_no_signal(it[0] == 0)
		start_btns.append(b)
		sb.add_child(b)
	v.add_child(sb)
	v.add_child(UI.label("Your first command", 16))
	var pt_no := 100 + randi() % 100
	ship = ["pt_elco", "PT-%d" % pt_no]
	v.add_child(UI.wrap("Every career starts at the bottom: an 80-foot Elco PT boat, %s, with a crew of fourteen. Fight well and the Navy gives you bigger ships: at each new rank, call at a friendly port and request a new command (destroyer escorts and destroyers first, then cruisers, carriers and battleships). Reputation earned in battle also buys other ships to sail with you." % ship[1], 560, 12, UI.MUTED))
	v.add_child(UI.label("Difficulty", 16))
	var diff := ["officer"]
	var drow := UI.row([], 4)
	var dbtns := []
	for did in ["ensign", "officer", "veteran", "ironman"]:
		var db := UI.button(Career.DIFFICULTY[did].name, func(): pass, true)
		db.pressed.connect(func(): diff[0] = did; for o in dbtns: o.set_pressed_no_signal(o == db))
		db.set_pressed_no_signal(did == "officer")
		dbtns.append(db)
		drow.add_child(db)
	v.add_child(drow)
	v.add_child(UI.wrap("Ensign: retry lost battles, half reputation losses. Officer: the war goes on. Veteran: five tactical pauses a battle, no lead marker, officers can die, you can be wounded. Ironman: no pause, and the career ends if your ship sinks. A new campaign replaces the saved one.", 560, 12, UI.MUTED))
	v.add_child(UI.row([UI.big_button("Begin", func():
		Game.campaign = load("res://scripts/ops.gd").new_campaign(start[0], ship[0], ship[1])
		Game.career = Career.fresh(diff[0])
		# starting rank fits the first command
		for u in Career.UNLOCKS:
			if u[0] == ship[0]:
				Game.career.rank = u[1]
				Game.career.xp = Career.RANK_XP[u[1]]
		Game.career.reputation = 300 + Game.career.rank * 150
		Game.career.year = War.year_of(start[0])
		Career.take_command(Game.career, ship[0], ship[1], start[0])
		Game.save_career()
		Game.save_campaign()
		get_tree().change_scene_to_file("res://scenes/ops.tscn")), UI.button("Cancel", func(): panel.queue_free())]))
	p.add_child(v)
	panel.add_child(p)
	UI.center(p)
	ui.add_child(panel)


func _on_settings() -> void:
	ui.add_child(SettingsPanel.new())
