extends Node3D
## Main menu: a destroyer at sea seen from above, with the menu over it.

var ship: Node3D
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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--menushot="):
			if "--settings" in OS.get_cmdline_user_args():
				_on_settings()
			_shot.call_deferred(a.split("=")[1])


func _shot(path: String) -> void:
	for i in 40:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	get_tree().quit()


func _build_scene() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.58, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.7, 0.8)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.01, 0.02, 0.035)
	env.fog_density = 0.0001
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
	pm.size = Vector2(3000, 3000)
	ocean.mesh = pm
	ocean_mat = ShaderMaterial.new()
	ocean_mat.shader = load("res://shaders/ocean.gdshader")
	ocean_mat.set_shader_parameter("foam_tex", load("res://assets/textures/boujie/foam_2.png"))
	ocean_mat.set_shader_parameter("detail_tex", load("res://assets/textures/boujie/ocean_albedo_2.png"))
	var W: Dictionary = Data.WEATHER.clear
	ocean_mat.set_shader_parameter("deep_color", W.deep)
	ocean_mat.set_shader_parameter("shallow_color", W.shallow)
	ocean_mat.set_shader_parameter("chop", 0.9)
	ocean_mat.set_shader_parameter("spec", 0.45)
	ocean.material_override = ocean_mat
	add_child(ocean)
	var scene: PackedScene = load("res://assets/models/fletcher_m21.glb")
	ship = scene.instantiate()
	ship.position = Vector3(40.0, 0.0, 0.0)
	add_child(ship)
	var cam := Camera3D.new()
	cam.fov = 32.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 230.0, 60.0), Vector3(20.0, 0.0, 0.0), Vector3(0, 0, -1))
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
		ship.rotation.y += delta * 0.03
		ship.position.y = sin(t * 0.7) * 0.25
		ship.rotation.z = sin(t * 0.55) * deg_to_rad(1.2)
	ocean_mat.set_shader_parameter("time_s", t)


## Headless check of the career rules (godot --headless --path . -- --careertest).
func _career_test() -> void:
	var c := Career.fresh("veteran")
	Career.take_command(c, "fletcher", "USS O'Bannon", 240)
	var t := {"salvos": 30, "hits": 9, "torps": 5, "torp_hits": 1, "kills": 2, "combat_min": 12.0, "underway_min": 20.0, "fires_out": 2, "holes_fixed": 3, "contacts": 4, "damage_done": 40.0, "crew_loss_frac": 0.2, "saved": 0, "big_kill": false, "summary": "test"}
	for i in 8:
		var lines := Career.apply_battle(c, t, "won", 3, 240 + i)
		print(i, " xp ", c.xp, " rank ", c.rank, " level ", Career.level_for(c.xp), " ", lines)
	print("gunnery officer level ", Career.officer_level(Career.officer(c, "Gunnery officer").xp), " crew ", Career.training_label(Career.ship(c).training), " medals ", c.medals.size(), " supply ", c.supply)
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
	var ships := [["pt_elco", "PT-109"], ["fletcher", "USS O'Bannon"], ["gato", "USS Wahoo"], ["buckley", "USS England"], ["cleveland", "USS Cleveland"], ["baltimore", "USS Baltimore"], ["essex", "USS Essex"], ["iowa", "USS Iowa"]]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var ship_btns := []
	for it in ships:
		var b2 := UI.button("%s (%s)" % [it[1], Data.TYPES[it[0]].name.replace(" class", "")], func(): pass, true)
		b2.pressed.connect(func(): ship[0] = it[0]; ship[1] = it[1]; for o in ship_btns: o.set_pressed_no_signal(o == b2))
		b2.set_pressed_no_signal(it[0] == "fletcher")
		ship_btns.append(b2)
		grid.add_child(b2)
	v.add_child(grid)
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
	v.add_child(UI.wrap("Ensign: retry lost battles, half reputation losses. Officer: the war goes on. Veteran: five tactical pauses a battle, no lead marker, officers can die, you can be wounded. Ironman: no pause, and the career ends if your ship sinks. Your first command sets your starting rank; a new campaign replaces the saved one.", 560, 12, UI.MUTED))
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
