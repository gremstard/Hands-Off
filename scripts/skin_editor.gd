extends Control
## Customize Hany: name and skin with a live 3D preview. Hat and costume
## slots are wired for later models. Saves to the profile on disk.

var name_edit: LineEdit
var skin_list: ItemList
var preview_model: Node3D
var preview_root: Node3D
var status: Label
var _skins: Array[String] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", 16)
	h.offset_left = 24
	h.offset_right = -24
	h.offset_top = 24
	h.offset_bottom = -24
	add_child(h)

	# 3D preview
	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vpc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(vpc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	vpc.add_child(vp)
	preview_root = Node3D.new()
	vp.add_child(preview_root)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	preview_root.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.9)
	e.ambient_light_energy = 0.7
	env.environment = e
	preview_root.add_child(env)
	var stage := Blocks.make(Blocks.Shape.COLUMN, "grey_light")
	stage.position.y = -1.0
	stage.scale = Vector3(1.2, 0.1, 1.2)
	preview_root.add_child(stage)
	preview_model = Node3D.new()
	preview_model.set_script(load("res://scripts/player_model.gd"))
	preview_root.add_child(preview_model)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.3, 4.2)
	cam.look_at_from_position(cam.position, Vector3(0, 0.95, 0))
	cam.fov = 40
	preview_root.add_child(cam)

	# side panel
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	h.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)
	var title := Label.new()
	title.text = "CUSTOMIZE HANY"
	title.add_theme_font_size_override("font_size", 28)
	title.theme_type_variation = "Title"
	v.add_child(title)
	var nl := Label.new()
	nl.text = "Name"
	v.add_child(nl)
	name_edit = LineEdit.new()
	name_edit.text = Profile.player_name
	name_edit.max_length = 16
	v.add_child(name_edit)
	var sl := Label.new()
	sl.text = "Skin"
	v.add_child(sl)
	skin_list = ItemList.new()
	skin_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skin_list.custom_minimum_size = Vector2(0, 260)
	_skins = Skins.list()
	for sk in _skins:
		skin_list.add_item(Skins.display_name(sk))
	var cur := _skins.find(Profile.skin)
	if cur >= 0:
		skin_list.select(cur)
	skin_list.item_selected.connect(func(i: int) -> void: _show(_skins[i]))
	v.add_child(skin_list)
	var later := Label.new()
	later.text = ""
	later.modulate = Color(0.7, 0.7, 0.75)
	later.add_theme_font_size_override("font_size", 13)
	v.add_child(later)
	status = Label.new()
	status.modulate = Color(0.6, 0.95, 0.6)
	v.add_child(status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var save := Button.new()
	save.text = "Save"
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(_save)
	row.add_child(save)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	row.add_child(back)

	_show(Profile.skin)


func _show(skin: String) -> void:
	preview_model.load_skin(Skins.valid(skin), Color(0.25, 0.85, 0.35))
	preview_model.rotation.y = 0.0
	preview_model.play(preview_model.ANIM_IDLE)
	status.text = ""


func _process(delta: float) -> void:
	preview_model.rotation.y += delta * 0.6


func _save() -> void:
	var n := name_edit.text.strip_edges()
	Profile.player_name = n if n != "" else "Hany"
	var sel := skin_list.get_selected_items()
	if sel.size() > 0:
		Profile.skin = _skins[sel[0]]
	Profile.save_profile()
	status.text = "Saved."
