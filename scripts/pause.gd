extends CanvasLayer
## In-game pause overlay. Esc releases the mouse; Esc again opens this.
## Click anywhere in the game recaptures the mouse.

var panel: Control
var is_open := false


var _fit_scroll: ScrollContainer
var _fit_content: Control


func _ready() -> void:
	layer = 50
	visible = false
	panel = CenterContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	add_child(panel)
	var box := PanelContainer.new()
	panel.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(320, 0)
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)
	_fit_scroll = scroll
	_fit_content = v
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_button(v, "Resume", close)
	_button(v, "Leave game", func() -> void:
		close()
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	_button(v, "Quit to desktop", func() -> void: get_tree().quit())


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func open() -> void:
	is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	is_open = false
	visible = false
	if Game.phase != Game.Phase.LOBBY and Game.arena != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("menu"):
		return
	if Game.arena == null or Game.phase == Game.Phase.LOBBY:
		return
	if is_open:
		close()
	else:
		open()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _fit_scroll:
		UiFit.fit(_fit_scroll, _fit_content)
