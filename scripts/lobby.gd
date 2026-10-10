extends Control
## Pre-game lobby. Host picks the mode and starts; everyone sees the roster.

var list: ItemList
var mode_option: OptionButton
var mode_desc: Label
var start_btn: Button
var info_label: Label
var volunteer_btn: CheckButton
var map_option: OptionButton
var headstart_option: OptionButton
var round_option: OptionButton
var _maps: Array[Dictionary] = []


var _fit_scroll: ScrollContainer
var _fit_content: Control


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var center := MarginContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		center.add_theme_constant_override("margin_" + side, 16)
	add_child(center)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(580, 0)
	panel.add_child(scroll)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	_fit_scroll = scroll
	_fit_content = margin
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "LOBBY"
	title.add_theme_font_size_override("font_size", 32)
	title.theme_type_variation = "Title"
	box.add_child(title)

	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 13)
	info_label.modulate = Color(0.8, 0.8, 0.8)
	box.add_child(info_label)
	if Net.is_host():
		var ips := Net.local_ips()
		var ip_text := ", ".join(ips) if not ips.is_empty() else "your LAN IP"
		info_label.text = "%s:%d" % [ip_text, Net.DEFAULT_PORT]
	else:
		info_label.text = ""

	var mode_row := HBoxContainer.new()
	box.add_child(mode_row)
	var ml := Label.new()
	ml.text = "Mode:  "
	mode_row.add_child(ml)
	mode_option = OptionButton.new()
	for n in Game.mode_names():
		mode_option.add_item(n)
	mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_option.disabled = not Net.is_host()
	mode_option.item_selected.connect(func(i: int) -> void: Game.set_mode(i))
	mode_row.add_child(mode_option)

	mode_desc = Label.new()
	mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_desc.custom_minimum_size = Vector2(500, 0)
	box.add_child(mode_desc)

	var map_row := HBoxContainer.new()
	box.add_child(map_row)
	var maplbl := Label.new()
	maplbl.text = "Map:  "
	map_row.add_child(maplbl)
	map_option = OptionButton.new()
	map_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_maps = MapData.list_maps()
	map_option.add_item("Blockyard (built in)")
	for mm in _maps:
		map_option.add_item(mm.name + ("" if mm.builtin else "  (yours)"))
	map_option.disabled = not Net.is_host()
	map_option.item_selected.connect(func(i: int) -> void: Game.set_map("" if i == 0 else _maps[i - 1].path))
	map_row.add_child(map_option)

	var hs_row := HBoxContainer.new()
	box.add_child(hs_row)
	var hsl := Label.new()
	hsl.text = "Jail time  "
	hs_row.add_child(hsl)
	headstart_option = OptionButton.new()
	for mnt in [1, 2, 3, 4, 5]:
		headstart_option.add_item("%d min" % mnt)
	headstart_option.disabled = not Net.is_host()
	headstart_option.item_selected.connect(func(i: int) -> void: Game.set_headstart(60.0 * (i + 1)))
	hs_row.add_child(headstart_option)

	var rl_row := HBoxContainer.new()
	box.add_child(rl_row)
	var rll := Label.new()
	rll.text = "Round  "
	rl_row.add_child(rll)
	round_option = OptionButton.new()
	for mnt in [2, 3, 4, 5, 6, 8, 10, 15]:
		round_option.add_item("%d min" % mnt)
	round_option.disabled = not Net.is_host()
	round_option.item_selected.connect(func(i: int) -> void: Game.set_round_length(60.0 * [2, 3, 4, 5, 6, 8, 10, 15][i]))
	rl_row.add_child(round_option)

	volunteer_btn = CheckButton.new()
	volunteer_btn.text = "Hander"
	volunteer_btn.toggled.connect(func(on: bool) -> void: Net.set_volunteer(on))
	box.add_child(volunteer_btn)

	var pl := Label.new()
	pl.text = "Players"
	box.add_child(pl)
	list = ItemList.new()
	list.custom_minimum_size = Vector2(0, 200)
	box.add_child(list)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	box.add_child(btn_row)
	start_btn = Button.new()
	start_btn.text = "Start round"
	start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_btn.visible = Net.is_host()
	start_btn.pressed.connect(func() -> void: Game.start_game())
	btn_row.add_child(start_btn)
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(_leave)
	btn_row.add_child(leave)

	Net.players_changed.connect(_refresh)
	Game.state_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	list.clear()
	var ids := Net.players.keys()
	ids.sort()
	for id in ids:
		var tag := "  (host)" if id == 1 else ""
		if id == multiplayer.get_unique_id():
			tag += "  (you)"
		var entry: Dictionary = Net.players[id]
		var w := Game.wins_of(entry.name)
		var vol := "   [Hander]" if entry.get("volunteer", false) else ""
		list.add_item("%s  -  %s%s%s%s" % [entry.name, Skins.display_name(str(entry.get("skin", ""))), tag, vol, ("   wins: %d" % w) if w > 0 else ""])
	if mode_option.selected != Game.mode:
		mode_option.select(Game.mode)
	mode_desc.text = Game.rules.describe()
	if not Net.is_host():
		map_option.text = Game.map_name_for_lobby
	var rl_i := [2, 3, 4, 5, 6, 8, 10, 15].find(int(Game.round_override / 60.0))
	if rl_i >= 0 and round_option.selected != rl_i:
		round_option.select(rl_i)
	var hs_i := int(Game.headstart_override / 60.0) - 1
	if hs_i >= 0 and hs_i < 5 and headstart_option.selected != hs_i:
		headstart_option.select(hs_i)
	start_btn.disabled = Net.players.size() < 1 or Game.call_seconds_left > 0.0
	if Game.call_seconds_left > 0.0:
		info_label.text = "Handers: %d" % int(ceil(Game.call_seconds_left))
		set_process(true)


func _process(_delta: float) -> void:
	if _fit_scroll:
		UiFit.fit(_fit_scroll, _fit_content)
	if Game.call_seconds_left > 0.0:
		info_label.text = "Handers: %d" % int(ceil(Game.call_seconds_left))
	else:
		set_process(false)


func _leave() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
