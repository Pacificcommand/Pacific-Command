class_name CareerPanel
extends Control
## The career screen: captain, officers, crew, skills to spend, medals and the ship's log.

var tabs: TabContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UI.backdrop())
	var p := UI.panel(18)
	p.custom_minimum_size = Vector2(820, 0)
	var v := UI.column(10)
	var c: Dictionary = Game.career
	v.add_child(UI.label("CAREER", 11, UI.BRASS))
	v.add_child(UI.label("%s · captain level %d · %d XP" % [Missions.RANKS[clampi(c.rank, 0, 8)], Career.level_for(c.xp), c.xp], 22))
	var nxt: int = c.rank + 1
	var sub := "Reputation %d · supply points %d · %d missions, %d won" % [c.reputation, c.get("supply", 0), c.missions, c.won]
	if nxt < Career.RANK_XP.size():
		sub += " · next rank (%s) at %d XP" % [Missions.RANKS[nxt], Career.RANK_XP[nxt]]
	v.add_child(UI.label(sub, 13, UI.MUTED))
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(780, 440)
	tabs.add_theme_font_size_override("font_size", 14)
	tabs.add_child(_margin(_ship_tab(), "Ship and crew"))
	tabs.add_child(_margin(_officers_tab(), "Officers"))
	tabs.add_child(_margin(_skills_tab(), "Captain skills"))
	tabs.add_child(_margin(_medals_tab(), "Medals and log"))
	v.add_child(tabs)
	v.add_child(UI.row([UI.button("Close", func(): queue_free())]))
	p.add_child(v)
	add_child(p)
	UI.center(p)


func _margin(v: Control, nm: String) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(v)
	m.add_child(sc)
	m.name = nm
	return m


func _ship_tab() -> Control:
	var v := UI.column(8)
	var c: Dictionary = Game.career
	var s := Career.ship(c)
	if s.is_empty():
		v.add_child(UI.label("No command yet.", 14))
		return v
	var T: Dictionary = Data.TYPES[s.type]
	v.add_child(UI.label("%s, %s" % [s.name, T.name], 18))
	v.add_child(UI.wrap("Crew %d of %d · training %s (%d points) · morale %d%% · %d kills · ship XP %d" % [int(s.crew), int(T.crew), Career.training_label(s.training), int(s.training), int(s.morale * 100), s.get("kills", 0), s.xp], 740, 13))
	if not s.damage.is_empty():
		var parts := []
		for k in s.damage:
			parts.append("%s %d%%" % [k, int(100.0 * float(s.damage[k]) / 4.0)])
		v.add_child(UI.wrap("Unrepaired damage: %s. Repairs are made in port." % ", ".join(parts), 740, 12, UI.RED))
	if not s.refits.is_empty():
		var names := []
		for id in s.refits:
			names.append(Career.REFITS[id][0])
		v.add_child(UI.wrap("Refits: %s." % ", ".join(names), 740, 12))
	var others := []
	for key in c.ships:
		if key != c.current:
			var o: Dictionary = c.ships[key]
			others.append("%s (%s, crew %s)" % [o.name, Data.TYPES[o.type].name.replace(" class", ""), Career.training_label(o.training)])
	if not others.is_empty():
		v.add_child(UI.label("Former commands, held in reserve with their crews:", 13, UI.MUTED))
		v.add_child(UI.wrap(", ".join(others), 740, 12))
	return v


func _officers_tab() -> Control:
	var v := UI.column(6)
	var c: Dictionary = Game.career
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	for h in ["Post", "Officer", "Level", "Status"]:
		grid.add_child(UI.label(h, 11, UI.BRASS))
	for o in c.officers:
		grid.add_child(UI.label(o.post, 13))
		grid.add_child(UI.label(o.name, 13))
		grid.add_child(UI.label("%d (%d XP, %d battles)" % [Career.officer_level(o.xp), o.xp, o.battles], 13))
		var st := "fit for duty"
		if o.dead:
			st = "killed in action"
		elif o.wounded > 0:
			st = "wounded, %d action%s" % [o.wounded, "" if o.wounded == 1 else "s"]
		grid.add_child(UI.label(st, 13, UI.RED if st != "fit for duty" else UI.GREEN))
	v.add_child(grid)
	v.add_child(UI.wrap("Officers earn experience doing their own job: the gunnery officer from salvos and hits, the torpedo officer from fish fired and hits, the damage control officer from fires fought and holes patched. Each level adds 3% to the ship's work in their department. Officers follow you to a new ship; the crew stays with the old one.", 740, 12, UI.MUTED))
	return v


func _skills_tab() -> Control:
	var v := UI.column(6)
	var c: Dictionary = Game.career
	var s := Career.ship(c)
	var cls: String = Data.TYPES[s.type].cls if not s.is_empty() else "dd"
	var pts := Career.skill_points_left(c)
	v.add_child(UI.label("%d skill point%s to spend · ship type: %s" % [pts, "" if pts == 1 else "s", cls.to_upper()], 15))
	for id in Career.skills_for(cls):
		var sk: Array = Career.SKILLS[id]
		var have: bool = c.skills.has(id)
		var row := UI.row([], 10)
		var b := UI.button("Learned" if have else "Learn", (func(sid): c.skills[sid] = true; Game.save_career(); _rebuild()).bind(id))
		b.disabled = have or pts <= 0
		b.custom_minimum_size.x = 90
		row.add_child(b)
		var col := UI.column(0)
		col.add_child(UI.label("%s%s" % [sk[0], "" if sk[1] != "all" else " (any ship)"], 14, UI.GREEN if have else UI.INK))
		col.add_child(UI.label(sk[2], 12, UI.MUTED))
		row.add_child(col)
		v.add_child(row)
	var learned_elsewhere := []
	for id in c.skills:
		if Career.SKILLS[id][1] != cls and Career.SKILLS[id][1] != "all":
			learned_elsewhere.append(Career.SKILLS[id][0])
	if not learned_elsewhere.is_empty():
		v.add_child(UI.wrap("Learned for other ship types (work again when you command one): %s." % ", ".join(learned_elsewhere), 740, 12, UI.MUTED))
	return v


func _medals_tab() -> Control:
	var v := UI.column(6)
	var c: Dictionary = Game.career
	if c.medals.is_empty():
		v.add_child(UI.label("No decorations yet.", 14, UI.MUTED))
	for m in c.medals:
		v.add_child(UI.label("%s · %s" % [m.name, War.date_str(int(m.day))], 14, UI.BRASS))
	v.add_child(UI.label("Ship's log", 11, UI.BRASS))
	var log: Array = c.get("log", [])
	for i in range(log.size() - 1, maxi(-1, log.size() - 25), -1):
		var e: Dictionary = log[i]
		v.add_child(UI.wrap("%s  %s" % [War.date_str(int(e.day)), e.text], 740, 12))
	return v


func _rebuild() -> void:
	var cur := tabs.current_tab
	for ch in get_children():
		ch.queue_free()
	await get_tree().process_frame
	_ready()
	tabs.current_tab = cur
