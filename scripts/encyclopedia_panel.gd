class_name EncyclopediaPanel
extends Control
## The encyclopedia screen: categories on the left, entries in the middle, the article on the
## right with a turning 3D model for ships. Text comes from Encyclopedia; ship numbers from
## Data.TYPES; aircraft numbers from Data.AIRCRAFT.

const CATS := ["US ships", "Japanese ships", "Battles", "Aircraft", "Weapons and gear"]

var cat := 0
var list_box: VBoxContainer
var article: VBoxContainer
var view: SubViewport
var view_root: Node3D
var model: Node3D
var view_box: SubViewportContainer
var cat_btns: Array = []
var item_btns: Array = []
var t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UI.backdrop())
	var p := UI.panel(18)
	var v := UI.column(10)
	v.add_child(UI.label("ENCYCLOPEDIA", 11, UI.BRASS))
	v.add_child(UI.label("Ships, aircraft, weapons and battles of the Pacific war", 20))
	var cats := UI.row([], 6)
	for i in CATS.size():
		var b := UI.button(CATS[i], (func(k): _pick_cat(k)).bind(i), true)
		cats.add_child(b)
		cat_btns.append(b)
	v.add_child(cats)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	# entries
	var lsc := ScrollContainer.new()
	lsc.custom_minimum_size = Vector2(250, 520)
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_box = UI.column(2)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lsc.add_child(list_box)
	body.add_child(lsc)
	# article
	var asc := ScrollContainer.new()
	asc.custom_minimum_size = Vector2(760, 520)
	asc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	article = UI.column(8)
	article.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asc.add_child(article)
	body.add_child(asc)
	v.add_child(body)
	v.add_child(UI.row([UI.button("Close", func(): queue_free()), UI.label("The grey line under each article gives the game's values; the text gives the historical ones.", 11, UI.MUTED)]))
	p.add_child(v)
	add_child(p)
	UI.center(p)
	_build_view()
	_pick_cat(0)


func _input(e: InputEvent) -> void:
	if Game.pressed(e, "menu"):
		accept_event()
		queue_free()


## A small 3D world of its own to show a ship model turning slowly.
func _build_view() -> void:
	view_box = SubViewportContainer.new()
	view_box.stretch = true
	view_box.custom_minimum_size = Vector2(740, 300)
	view = SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = false
	view.msaa_3d = Viewport.MSAA_2X
	view_box.add_child(view)
	view_root = Node3D.new()
	view.add_child(view_root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.14, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.78, 0.85)
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	view_root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.2
	view_root.add_child(sun)
	sun.look_at_from_position(Vector3(60, 90, 40), Vector3.ZERO, Vector3.UP)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1200, 1200)
	sea.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.2, 0.3)
	mat.roughness = 0.35
	mat.metallic = 0.2
	sea.material_override = mat
	view_root.add_child(sea)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.name = "Cam"
	view_root.add_child(cam)
	cam.make_current()


func _show_model(type_id: String) -> void:
	var T: Dictionary = Data.TYPES.get(type_id, {})
	var models: Dictionary = T.get("models", {})
	if models.is_empty():
		return
	_show_glb(models.values()[0], T.get("L", 100.0), 0.0)


## Load a .glb into the viewer and frame it for a thing about `L` metres long.
func _show_glb(path: String, L: float, lift: float) -> void:
	if model:
		model.queue_free()
		model = null
	if not ResourceLoader.exists(path):
		return
	var scene: PackedScene = load(path)
	model = scene.instantiate()
	model.position.y = lift
	view_root.add_child(model)
	var cam: Camera3D = view_root.get_node("Cam")
	cam.look_at_from_position(Vector3(L * 0.55, lift + L * 0.42, L * 0.75), Vector3(0, lift + L * 0.03, 0), Vector3.UP)


func _process(dt: float) -> void:
	t += dt
	if model:
		model.rotation.y = t * 0.25


func _pick_cat(i: int) -> void:
	cat = i
	for k in cat_btns.size():
		cat_btns[k].set_pressed_no_signal(k == i)
	for c in list_box.get_children():
		c.queue_free()
	item_btns.clear()
	var items: Array = _items()
	for k in items.size():
		var b := UI.button(items[k].label, (func(j): _pick_item(j)).bind(k), true, 12)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_box.add_child(b)
		item_btns.append(b)
	if not items.is_empty():
		_pick_item(0)


## The entries of the current category: [{label, key}]
func _items() -> Array:
	var out: Array = []
	match cat:
		0, 1:
			var nation := "us" if cat == 0 else "ijn"
			var order := ["pt", "de", "dd", "ss", "cl", "ca", "bb", "cvl", "cve", "cv", "barge", "merchant"]
			var keys: Array = []
			for id in Data.TYPES:
				var T: Dictionary = Data.TYPES[id]
				if T.get("nation", "") == nation and Encyclopedia.has_ship(id):
					keys.append(id)
			keys.sort_custom(func(a, b):
				var ca: int = order.find(Data.TYPES[a].get("cls", "aux")); var cb: int = order.find(Data.TYPES[b].get("cls", "aux"))
				if ca != cb: return ca < cb
				return float(Data.TYPES[a].get("displacement", 0)) < float(Data.TYPES[b].get("displacement", 0)))
			for id in keys:
				out.append({"label": Data.TYPES[id].name, "key": id})
		2:
			for i in Encyclopedia.BATTLES.size():
				out.append({"label": Encyclopedia.BATTLES[i].title, "key": i})
		3:
			for id in Data.AIRCRAFT:
				if Encyclopedia.AIRCRAFT.has(id):
					var A: Dictionary = Data.AIRCRAFT[id]
					out.append({"label": "%s %s" % [A.get("name", id), "(US)" if A.get("nation", "us") == "us" else "(Japan)"], "key": id})
		4:
			for i in Encyclopedia.WEAPONS.size():
				out.append({"label": Encyclopedia.WEAPONS[i].title, "key": i})
	return out


func _pick_item(k: int) -> void:
	for j in item_btns.size():
		item_btns[j].set_pressed_no_signal(j == k)
	for c in article.get_children():
		if c != view_box:
			c.queue_free()
	if view_box.get_parent():
		view_box.get_parent().remove_child(view_box)
	var it: Dictionary = _items()[k]
	match cat:
		0, 1:
			_ship_article(it.key)
		2:
			var b: Dictionary = Encyclopedia.BATTLES[it.key]
			article.add_child(UI.label(b.title, 22))
			article.add_child(UI.label(b.date, 13, UI.BRASS))
			article.add_child(UI.wrap(b.text, 740, 14))
		3:
			var A: Dictionary = Data.AIRCRAFT[it.key]
			var E: Dictionary = Encyclopedia.AIRCRAFT[it.key]
			article.add_child(UI.label(A.get("name", it.key), 22))
			article.add_child(UI.wrap(E.real, 740, 12, UI.BRASS))
			if A.has("model"):
				article.add_child(view_box)
				_show_glb(A.model, 14.0, 6.0)
			article.add_child(UI.wrap(E.text, 740, 14))
			article.add_child(UI.wrap("In the game: %s · speed %d kn · rating %.1f%s" % [A.get("kind", ""), int(A.get("speed", 0)), float(A.get("rating", 0)), (" · bomb %.1f" % float(A.bomb)) if A.has("bomb") else ""], 740, 12, UI.MUTED))
		4:
			var w: Dictionary = Encyclopedia.WEAPONS[it.key]
			article.add_child(UI.label(w.title, 22))
			article.add_child(UI.wrap(w.text, 740, 14))


func _ship_article(id: String) -> void:
	var T: Dictionary = Data.TYPES[id]
	var E: Dictionary = Encyclopedia.SHIPS[id]
	article.add_child(UI.label(T.name, 22))
	article.add_child(UI.wrap(E.real, 740, 12, UI.BRASS))
	article.add_child(view_box)
	_show_model(id)
	article.add_child(UI.wrap(E.text, 740, 14))
	if E.get("ships", "") != "":
		article.add_child(UI.wrap("Ships of the class: %s." % E.ships, 740, 12, UI.MUTED))
	# the game's figures
	var guns := {}
	for m in T.get("mounts", []):
		var g: String = m.get("gun", T.get("gun", ""))
		if g != "" and Data.GUNS.has(g):
			var cal: String = Data.GUNS[g].cal
			guns[cal] = guns.get(cal, 0) + 1
	var gparts := []
	for cal in guns:
		gparts.append("%d x %s" % [guns[cal], cal])
	var tubes := 0
	for tb in T.get("torps", []):
		tubes += int(tb.get("n", 0))
	var line := "In the game: %s tons · %d m · %d kn · %d crew" % [str(int(T.get("displacement", 0))), int(T.get("L", 0)), int(T.get("max_kn", 0)), int(T.get("crew", 0))]
	if not gparts.is_empty():
		line += " · " + ", ".join(gparts)
	if tubes > 0:
		line += " · %d torpedo tubes (%s)" % [tubes, T.get("torp", {}).get("name", "")]
	if T.has("armor"):
		line += " · armour %.1f" % float(T.armor)
	if T.get("radar", 0.0) > 0.0:
		line += " · radar"
	if T.has("hangar"):
		line += " · carrier (%s air group)" % T.hangar
	if T.get("dive_kn", 0.0) > 0.0:
		line += " · submarine"
	article.add_child(UI.wrap(line, 740, 12, UI.MUTED))
