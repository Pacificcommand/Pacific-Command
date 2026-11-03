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
	v.add_child(UI.label("SERVICE RECORD", 11, UI.BRASS))
	v.add_child(UI.label("%s %s" % [Missions.RANKS[clampi(c.rank, 0, 8)], Career.captain_name(c)], 22))
	var nxt: int = c.rank + 1
	var sub := "Reputation %d · supply points %d · %d missions, %d won" % [c.reputation, c.get("supply", 0), c.missions, c.won]
	if nxt < Career.RANK_REP.size():
		sub += " · promotion to %s at %d reputation" % [Missions.RANKS[nxt], Career.RANK_REP[nxt]]
	v.add_child(UI.label(sub, 13, UI.MUTED))
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(1460, 560)
	tabs.add_theme_font_size_override("font_size", 14)
	tabs.add_child(_margin(_record_tab(), "Decorations"))
	tabs.add_child(_margin(_ship_tab(), "Ship and crew"))
	tabs.add_child(_margin(_officers_tab(), "Officers"))
	tabs.add_child(_margin(_medals_tab(), "Log"))
	tabs.add_child(_margin(_all_medals_tab(), "All medals"))
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
	for h in ["Post", "Officer", "Service", "Status"]:
		grid.add_child(UI.label(h, 11, UI.BRASS))
	for o in c.officers:
		grid.add_child(UI.label(o.post, 13))
		grid.add_child(UI.label(o.name, 13))
		grid.add_child(UI.label("%d action%s · %d decoration%s" % [o.battles, "" if o.battles == 1 else "s", o.get("medals", []).size(), "" if o.get("medals", []).size() == 1 else "s"], 13))
		var st := "fit for duty"
		if o.dead:
			st = "killed in action"
		elif o.wounded > 0:
			st = "wounded, %d action%s" % [o.wounded, "" if o.wounded == 1 else "s"]
		grid.add_child(UI.label(st, 13, UI.RED if st != "fit for duty" else UI.GREEN))
	v.add_child(grid)
	v.add_child(UI.wrap("Officers are decorated for what they do in action: the gunnery officer for hits and ships sunk by gunfire, the torpedo officer for torpedo hits, the damage control officer for fires fought and holes patched. Every decoration makes their department a little better for good. Officers follow you to a new ship; the crew stays with the old one. In port, meet them on the quay.", 740, 12, UI.MUTED))
	return v


## Each person's decorations with what they were for and what they do now.
func _record_tab() -> Control:
	var c: Dictionary = Game.career
	var v := UI.column(10)
	_person_block(v, "CAPTAIN", "%s %s" % [Missions.RANKS[clampi(c.rank, 0, 8)], Career.captain_name(c)], c.get("medals", []))
	for o in c.officers:
		if o.dead:
			continue
		_person_block(v, String(o.post).to_upper(), String(o.name), o.get("medals", []))
	return v


func _person_block(v: VBoxContainer, title: String, name: String, medals: Array) -> void:
	v.add_child(UI.label("%s · %s" % [title, name], 13, UI.BRASS))
	if medals.is_empty():
		v.add_child(UI.label("No decorations yet.", 12, UI.MUTED))
		return
	for m in medals:
		var n := int(m.get("n", 1))
		v.add_child(UI.label("%s%s" % [m.get("name", "?"), (" with %d gold star%s" % [n - 1, "" if n == 2 else "s"]) if n > 1 else ""], 14))
		v.add_child(UI.wrap(Career.medal_buff_text(m), 1300, 12, UI.GREEN))


## Every decoration in the game and how it is won, so the player knows what to aim for.
func _all_medals_tab() -> Control:
	var v := UI.column(6)
	var by := {}
	for id in Career.MEDAL_DEFS:
		var d: Dictionary = Career.MEDAL_DEFS[id]
		var w: String = d.who
		if not by.has(w):
			by[w] = []
		by[w].append(d)
	for w in by:
		v.add_child(UI.label(("CAPTAIN" if w == "captain" else ("ANY OFFICER" if w == "any" else String(w).to_upper())), 11, UI.BRASS))
		for d in by[w]:
			var parts := []
			for k in d.buff:
				parts.append("%s +%d%%" % [Career.BUFF_LABEL.get(k, k), int(round(float(d.buff[k]) * 100.0))])
			v.add_child(UI.wrap("%s: %s %s" % [d.name, d.how, ("(" + ", ".join(parts) + " per award, up to %d)" % int(d.max)) if not parts.is_empty() else ""], 1300, 12))
	return v


func _medals_tab() -> Control:
	var v := UI.column(6)
	var c: Dictionary = Game.career
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
