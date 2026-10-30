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
	buttons.add_child(UI.big_button("New battle", _on_new))
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
	t += delta
	if ship:
		ship.rotation.y += delta * 0.03
		ship.position.y = sin(t * 0.7) * 0.25
		ship.rotation.z = sin(t * 0.55) * deg_to_rad(1.2)
	ocean_mat.set_shader_parameter("time_s", t)


func _on_new() -> void:
	Game.pending_load = -1
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


func _on_load() -> void:
	var sp := SlotPanel.new("load")
	ui.add_child(sp)
	sp.picked.connect(func(i):
		Game.pending_load = i
		get_tree().change_scene_to_file("res://scenes/battle.tscn"))


func _on_settings() -> void:
	ui.add_child(SettingsPanel.new())
