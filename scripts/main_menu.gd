extends Control
## Host / join screen.

var name_edit: LineEdit
var port_edit: LineEdit
var addr_edit: LineEdit
var status: Label
var host_btn: Button
var join_btn: Button


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
	scroll.custom_minimum_size = Vector2(480, 0)
	panel.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	scroll.add_child(margin)
	_fit_scroll = scroll
	_fit_content = margin
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = "HANDS OFF"
	title.theme_type_variation = "Title"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = ""
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.75, 0.75, 0.8)
	box.add_child(sub)

	box.add_child(_spacer(8))
	name_edit = _field(box, "Your name", _default_name())
	var skin_lbl := Label.new()
	skin_lbl.text = Skins.display_name(Profile.skin)
	skin_lbl.modulate = Color(0.75, 0.75, 0.8)
	skin_lbl.add_theme_font_size_override("font_size", 13)
	box.add_child(skin_lbl)
	name_edit.max_length = 16

	box.add_child(_spacer(8))
	var host_head := Label.new()
	host_head.text = "Host a game"
	host_head.add_theme_font_size_override("font_size", 20)
	box.add_child(host_head)
	var host_row := HBoxContainer.new()
	box.add_child(host_row)
	port_edit = LineEdit.new()
	port_edit.text = str(Net.DEFAULT_PORT)
	port_edit.placeholder_text = "UDP port"
	port_edit.custom_minimum_size.x = 110
	host_row.add_child(port_edit)
	host_btn = Button.new()
	host_btn.text = "Host"
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.pressed.connect(_on_host)
	host_row.add_child(host_btn)

	box.add_child(_spacer(8))
	var join_head := Label.new()
	join_head.text = "Join a game"
	join_head.add_theme_font_size_override("font_size", 20)
	box.add_child(join_head)
	var join_row := HBoxContainer.new()
	box.add_child(join_row)
	addr_edit = LineEdit.new()
	addr_edit.placeholder_text = "address:port"
	addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	addr_edit.text_submitted.connect(func(_t: String) -> void: _on_join())
	join_row.add_child(addr_edit)
	join_btn = Button.new()
	join_btn.text = "Join"
	join_btn.pressed.connect(_on_join)
	join_row.add_child(join_btn)

	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(400, 40)
	status.modulate = Color(1, 0.8, 0.6)
	box.add_child(status)

	var tools_row := HBoxContainer.new()
	tools_row.add_theme_constant_override("separation", 10)
	box.add_child(tools_row)
	var custom := Button.new()
	custom.text = "Customize Hany"
	custom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom.pressed.connect(func() -> void:
		_apply_name()
		get_tree().change_scene_to_file("res://scenes/skin_editor.tscn"))
	tools_row.add_child(custom)
	var editor := Button.new()
	editor.text = "Map editor"
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/map_editor.tscn"))
	tools_row.add_child(editor)
	var settings := Button.new()
	settings.text = "Settings"
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/settings.tscn"))
	tools_row.add_child(settings)

	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)

	Net.joined.connect(_on_joined)
	Net.join_failed.connect(_on_join_failed)


func _default_name() -> String:
	return Profile.player_name


func _field(parent: Control, label_text: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size.x = 110
	row.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(e)
	return e


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c


func _apply_name() -> void:
	var n := name_edit.text.strip_edges()
	Profile.player_name = n if n != "" else "Hany"
	Profile.save_profile()


func _on_host() -> void:
	_apply_name()
	var port := int(port_edit.text) if port_edit.text.is_valid_int() else Net.DEFAULT_PORT
	var err := Net.host(port)
	if err != OK:
		status.text = "Could not open port %d (error %d). Is another instance already hosting?" % [port, err]
		return
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_join() -> void:
	_apply_name()
	var err := Net.join(addr_edit.text)
	if err != OK:
		status.text = "Bad address (error %d)." % err
		return
	status.text = "Connecting to %s..." % addr_edit.text.strip_edges()
	host_btn.disabled = true
	join_btn.disabled = true


func _on_joined() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_join_failed(reason: String) -> void:
	if not is_inside_tree():
		return
	status.text = reason
	host_btn.disabled = false
	join_btn.disabled = false


func _process(_delta: float) -> void:
	if _fit_scroll:
		UiFit.fit(_fit_scroll, _fit_content)
