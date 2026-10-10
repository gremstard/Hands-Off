extends Control
## Settings screen: click a key to rebind it, toggle talk mode, mouse speed.

var _waiting: String = ""
var _buttons: Dictionary = {}
var status: Label


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
	scroll.custom_minimum_size = Vector2(560, 0)
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.custom_minimum_size = Vector2(520, 0)
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	_fit_scroll = scroll
	_fit_content = v
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 30)
	v.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for a in Settings.ACTIONS:
		var l := Label.new()
		l.text = Settings.ACTIONS[a][0]
		grid.add_child(l)
		var b := Button.new()
		b.text = Settings.key_name(a)
		b.custom_minimum_size.x = 110
		b.pressed.connect(_start_rebind.bind(a))
		grid.add_child(b)
		_buttons[a] = b
	var talk := CheckButton.new()
	talk.text = "Talk key toggles instead of hold"
	talk.button_pressed = Settings.talk_toggle
	talk.toggled.connect(func(on: bool) -> void:
		Settings.talk_toggle = on
		Settings.save_settings())
	v.add_child(talk)
	var sens_row := HBoxContainer.new()
	v.add_child(sens_row)
	var sl := Label.new()
	sl.text = "Mouse speed"
	sens_row.add_child(sl)
	var slider := HSlider.new()
	slider.min_value = 0.2
	slider.max_value = 3.0
	slider.step = 0.1
	slider.value = Settings.mouse_sens
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(val: float) -> void:
		Settings.mouse_sens = val
		Settings.save_settings())
	sens_row.add_child(slider)
	status = Label.new()
	status.modulate = Color(0.95, 0.85, 0.5)
	v.add_child(status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var reset := Button.new()
	reset.text = "Reset keys"
	reset.pressed.connect(func() -> void:
		for a in Settings.ACTIONS:
			Settings.keys[a] = Settings.ACTIONS[a][1]
		Settings.save_settings()
		_refresh())
	row.add_child(reset)
	var back := Button.new()
	back.text = "Back"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	row.add_child(back)


func _start_rebind(action: String) -> void:
	_waiting = action
	_buttons[action].text = "press a key..."
	status.text = "Press the new key for %s (Esc cancels)" % Settings.ACTIONS[action][0]


func _unhandled_input(event: InputEvent) -> void:
	if _waiting == "" or not (event is InputEventKey) or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	if event.keycode == KEY_ESCAPE:
		status.text = "Cancelled."
	else:
		Settings.rebind(_waiting, event.physical_keycode)
		status.text = "%s is now %s" % [Settings.ACTIONS[_waiting][0], Settings.key_name(_waiting)]
	_waiting = ""
	_refresh()


func _refresh() -> void:
	for a in _buttons:
		_buttons[a].text = Settings.key_name(a)


func _process(_delta: float) -> void:
	if _fit_scroll:
		UiFit.fit(_fit_scroll, _fit_content)
