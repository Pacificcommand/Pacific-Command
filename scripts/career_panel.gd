class_name CareerPanel
extends Control
## The career screen: captain, officers, crew, skills to spend, medals and the ship's log.

var tabs: TabContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UI.backdrop())
	var p := UI.panel(18)
	p.custom_minimum_size = Vector2(1500, 0)
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
	tabs.custom_minimum_size = Vector2(1460, 560)
	tabs.add_theme_font_size_override("font_size", 14)
	tabs.add_child(_margin(_tree_tab(), "Skill tree"))
	tabs.add_child(_margin(_ship_tab(), "Ship and crew"))
	tabs.add_child(_margin(_officers_tab(), "Officers"))
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


## The skill tree: the captain's column first, then one column per department head. Each
## column shows level and XP, the points to spend, and the skills in tiers.
func _tree_tab() -> Control:
	var c: Dictionary = Game.career
	var ship := Career.ship(c)
	var cls: String = Data.TYPES[ship.type].cls if not ship.is_empty() else "dd"
	var v := UI.column(6)
	v.add_child(UI.wrap("Experience comes from doing the job: the captain's from every battle, each officer's from their own department. A level is a skill point for the captain; officers get one every two levels. Higher tiers open with level and with a skill from the tier below. Wounded or dead officers give nothing until replaced.", 1400, 12, UI.MUTED))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1440, 470)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	# the captain
	row.add_child(_tree_column("CAPTAIN", "You · %s" % Missions.RANKS[clampi(c.rank, 0, 8)], Career.level_for(c.xp), c.xp, _xp_next_captain(c.xp), Career.skill_points_left(c), _captain_skill_rows(c, cls)))
	for o in c.officers:
		var sub: String = o.name + (" · killed" if o.dead else (" · wounded" if o.wounded > 0 else ""))
		var pts: int = Career.officer_points_left(o)
		var skills: Array = Career.OFFICER_SKILLS.get(o.post, [])
		var rows := []
		for sk in skills:
			var have: bool = o.get("skills", []).has(sk[0])
			var ok := Career.officer_can_learn(o, sk[0])
			rows.append({"name": sk[1], "desc": sk[2], "tier": sk[4], "have": have, "ok": ok, "cb": (func(off, sid): off.skills.append(sid); Game.save_career(); _rebuild()).bind(o, sk[0])})
		row.add_child(_tree_column(o.post.to_upper(), sub, Career.officer_level(o.xp), o.xp, _xp_next_officer(o.xp), pts, rows))
	sc.add_child(row)
	v.add_child(sc)
	return v


func _xp_next_captain(xp: int) -> int:
	var lvl := Career.level_for(xp) + 1
	return lvl * lvl * 120

func _xp_next_officer(xp: int) -> int:
	var lvl := mini(Career.officer_level(xp) + 1, 10)
	return lvl * lvl * 60

func _captain_skill_rows(c: Dictionary, cls: String) -> Array:
	var rows := []
	for id in Career.skills_for(cls):
		var sk: Array = Career.SKILLS[id]
		rows.append({"name": sk[0] + ("" if sk[1] != "all" else " (any ship)"), "desc": sk[2], "tier": Career.skill_tier(id), "have": c.skills.has(id), "ok": Career.can_learn(c, id),
			"cb": (func(sid): c.skills[sid] = true; Game.save_career(); _rebuild()).bind(id)})
	rows.sort_custom(func(a, b): return a.tier < b.tier)
	return rows


func _tree_column(title: String, sub: String, level: int, xp: int, next_xp: int, pts: int, rows: Array) -> Control:
	var p := UI.panel(8)
	p.custom_minimum_size = Vector2(170, 0)
	var v := UI.column(4)
	v.add_child(UI.label(title, 10, UI.BRASS))
	var nm := UI.wrap(sub, 160, 12)
	v.add_child(nm)
	v.add_child(UI.label("Level %d · %d XP" % [level, xp], 11, UI.MUTED))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(160, 6)
	bar.show_percentage = false
	bar.max_value = maxf(1.0, float(next_xp))
	bar.value = float(xp)
	v.add_child(bar)
	v.add_child(UI.label("%d point%s to spend" % [pts, "" if pts == 1 else "s"], 12, UI.BRASS if pts > 0 else UI.MUTED))
	var tier := 0
	for r in rows:
		if r.tier != tier:
			tier = r.tier
			v.add_child(UI.label("Tier %d" % tier, 10, UI.MUTED))
		var b := UI.button(r.name, r.cb if r.ok else Callable(), false, 12)
		b.custom_minimum_size.x = 160
		b.disabled = not r.ok
		if r.have:
			b.set_pressed_no_signal(true)
			b.toggle_mode = true
			b.disabled = true
			b.add_theme_color_override("font_disabled_color", UI.BRASS_INK)
		b.tooltip_text = r.desc
		v.add_child(b)
		var d := UI.wrap(r.desc, 160, 10, UI.MUTED)
		v.add_child(d)
	p.add_child(v)
	return p


func _medals_tab() -> Control:
	var v := UI.column(6)
	var c: Dictionary = Game.career
	if c.medals.is_empty():
		v.add_child(UI.label("No decorations yet.", 14, UI.MUTED))
	for m in c.medals:
		v.add_child(UI.label("%s · %s" % [m.name, War.date_str(int(m.day))], 14, UI.BRASS))
	var ach: Array = c.get("achievements", [])
	if not ach.is_empty():
		v.add_child(UI.label("Achievements", 11, UI.BRASS))
		for a in ach:
			v.add_child(UI.label("%s · %s" % [SteamHook.name_of(a.id), War.date_str(int(a.day))], 13, UI.INK))
	v.add_child(UI.label("Ship's log", 11, UI.BRASS))
	var log: Array = c.get("log", [])
	for i in range(log.size() - 1, maxi(-1, log.size() - 25), -1):
		var e: Dictionary = log[i]
		var row := UI.row([], 8)
		row.add_child(UI.wrap("%s  %s" % [War.date_str(int(e.day)), e.text], 600, 12))
		if e.has("aar"):
			row.add_child(UI.button("Report", (func(txt): _show_text(txt)).bind(e.aar)))
		v.add_child(row)
	return v


func _show_text(txt: String) -> void:
	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(UI.backdrop(0.6))
	var p := UI.panel(20)
	var v := UI.column(8)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(760, 560)
	sc.add_child(UI.label(txt, 13))
	v.add_child(sc)
	v.add_child(UI.row([UI.button("Close", func(): panel.queue_free())]))
	p.add_child(v)
	panel.add_child(p)
	UI.center(p)
	add_child(panel)


func _rebuild() -> void:
	var cur := tabs.current_tab
	for ch in get_children():
		ch.queue_free()
	await get_tree().process_frame
	_ready()
	tabs.current_tab = cur
