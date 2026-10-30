class_name SlotPanel
extends Control
## Save and load slots. mode "save": every slot can be written; mode "load": only filled slots open.

signal picked(slot: int)
signal closed

var mode := "load"


func _init(p_mode: String) -> void:
	mode = p_mode


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UI.backdrop())
	var p := UI.panel(18)
	p.custom_minimum_size = Vector2(620, 0)
	var v := UI.column(8)
	v.add_child(UI.label("SAVE BATTLE" if mode == "save" else "LOAD BATTLE", 11, UI.BRASS))
	v.add_child(UI.label("Pick a slot" if mode == "save" else "Pick a saved battle", 22))
	for i in Game.SLOTS:
		v.add_child(_slot_row(i))
	v.add_child(UI.row([UI.button("Cancel", func(): closed.emit(); queue_free())]))
	p.add_child(v)
	add_child(p)
	UI.center(p)


func _slot_row(i: int) -> Control:
	var info := Game.slot_info(i)
	var hb := UI.row([], 10)
	var txt := "Slot %d" % (i + 1)
	var sub := "empty"
	if not info.is_empty():
		txt = "Slot %d: %s" % [i + 1, info.get("title", "Battle")]
		sub = "%s · battle time %s · saved %s" % [info.get("ship", ""), info.get("clock", ""), info.get("date", "")]
	var vb := UI.column(0)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(UI.label(txt, 15))
	vb.add_child(UI.label(sub, 12, UI.MUTED))
	hb.add_child(vb)
	var can := mode == "save" or not info.is_empty()
	var b := UI.button("Save here" if mode == "save" else "Load", func(): picked.emit(i); queue_free())
	b.disabled = not can
	hb.add_child(b)
	if not info.is_empty():
		hb.add_child(UI.button("Delete", func(): Game.delete_slot(i); _rebuild()))
	var pc := UI.panel(8)
	pc.add_child(hb)
	return pc


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	await get_tree().process_frame
	_ready()
