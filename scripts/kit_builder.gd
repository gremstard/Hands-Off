extends "res://scripts/map_editor.gd"
## Kit Builder: assemble a map from kit pieces. Thumbnail browser, the real
## model as a ghost, grid snap, and piece-to-piece snapping (walls butt up,
## things stack). Saves the same .hom files as the block editor.
##
##  Left click place    X remove    R rotate    [ ] prev/next piece
##  G grid 0.5/1/2/4    hold Shift: free placement    Ctrl+S save

var grid_steps := [0.5, 1.0, 2.0, 4.0]
var grid_i := 1
var _ghost_model: Node3D = null
var _ghost_path := ""
var _aabb_cache: Dictionary = {}
var _cats: Array = []
var _thumb_grid: GridContainer
var _cat_list: ItemList
var _piece_label: Label
var _grid_label: Label
var _cat_i := 0
var _piece_i := 0


func _ready() -> void:
	super._ready()
	tool = Tool.PROP
	ghost.visible = false


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	_props = MapData.list_props()
	for pr in _props:
		if not _cats.has(pr.category):
			_cats.append(pr.category)

	# left: categories + thumbnails
	var left := PanelContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 10
	left.offset_top = 10
	left.offset_bottom = -10
	left.custom_minimum_size.x = 330
	ui.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	_cat_list = ItemList.new()
	_cat_list.custom_minimum_size.y = 150
	for c in _cats:
		_cat_list.add_item(c)
	_cat_list.item_selected.connect(func(i: int) -> void: _show_category(i))
	lv.add_child(_cat_list)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(sc)
	_thumb_grid = GridContainer.new()
	_thumb_grid.columns = 3
	_thumb_grid.add_theme_constant_override("h_separation", 4)
	_thumb_grid.add_theme_constant_override("v_separation", 4)
	sc.add_child(_thumb_grid)
	_piece_label = Label.new()
	_piece_label.add_theme_font_size_override("font_size", 13)
	lv.add_child(_piece_label)

	# bottom: file + snap
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 350
	panel.offset_right = -10
	panel.offset_bottom = -10
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ui.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	for i in [Tool.PROP, Tool.ERASE, Tool.JAIL, Tool.HANDER, Tool.RUNNER, Tool.TORCH, Tool.BLOCK]:
		var b := Button.new()
		b.text = TOOL_NAMES[i]
		b.toggle_mode = true
		b.button_pressed = (i == Tool.PROP)
		b.pressed.connect(_set_tool.bind(i))
		row.add_child(b)
		tool_buttons.append(b)
	row.add_child(VSeparator.new())
	_grid_label = Label.new()
	row.add_child(_grid_label)
	var gb := Button.new()
	gb.text = "Grid"
	gb.pressed.connect(_cycle_grid)
	row.add_child(gb)
	row.add_child(_lbl("Scale"))
	_spin(row, "", 25, 400, 100, func(val: float) -> void:
		prop_scale = val / 100.0
		_ghost_path = "")
	# block controls for the Block tool
	row.add_child(_lbl("Block"))
	shape_opt = OptionButton.new()
	for n in Blocks.SHAPE_NAMES:
		shape_opt.add_item(n)
	shape_opt.item_selected.connect(func(i: int) -> void: _set_shape(i))
	row.add_child(shape_opt)
	color_opt = OptionButton.new()
	for n in Blocks.TYPES.keys():
		color_opt.add_item(n)
	color_opt.item_selected.connect(func(i: int) -> void: block_name = color_opt.get_item_text(i))
	row.add_child(color_opt)
	cx = _spin(row, "x", 1, 60, 1, func(val: float) -> void: cells.x = int(val))
	cy = _spin(row, "y", 1, 20, 1, func(val: float) -> void: cells.y = int(val))
	cz = _spin(row, "z", 1, 60, 1, func(val: float) -> void: cells.z = int(val))

	var row2 := HFlowContainer.new()
	row2.add_theme_constant_override("separation", 6)
	v.add_child(row2)
	row2.add_child(_lbl("Map"))
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size.x = 180
	name_edit.text_changed.connect(func(t: String) -> void: map.name = t)
	row2.add_child(name_edit)
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(_save)
	row2.add_child(save)
	load_opt = OptionButton.new()
	load_opt.custom_minimum_size.x = 170
	_refresh_maps()
	load_opt.item_selected.connect(func(i: int) -> void:
		if i == 0:
			load_map(MapData.default_map())
		else:
			var m := MapData.load_file(_maps[i - 1].path)
			if m:
				load_map(m))
	row2.add_child(load_opt)
	var newb := Button.new()
	newb.text = "New"
	newb.pressed.connect(func() -> void:
		var m := MapData.new()
		m.name = "Kit map"
		m.add_block(Blocks.Shape.CUBE, "asphalt", Vector3(0, -1, 0), 0, Vector3i(120, 1, 120))
		load_map(m))
	row2.add_child(newb)
	var folder := Button.new()
	folder.text = "Folder"
	folder.pressed.connect(func() -> void:
		DirAccess.make_dir_recursive_absolute(MapData.USER_DIR)
		OS.shell_open(ProjectSettings.globalize_path(MapData.USER_DIR)))
	row2.add_child(folder)
	var back := Button.new()
	back.text = "Menu"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	row2.add_child(back)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 13)
	v.add_child(status)
	var help := Label.new()
	help.text = "WASD Q E fly   right mouse look   click place   X remove   R rotate   [ ] piece   G grid   Shift free   Cmd+Z undo   Shift+Cmd+Z redo   Cmd+S save"
	help.add_theme_font_size_override("font_size", 12)
	help.modulate = Color(0.7, 0.7, 0.75)
	v.add_child(help)
	# the base class expects these to exist
	col_spin = SpinBox.new()
	row_spin = SpinBox.new()
	_update_grid_label()
	if not _cats.is_empty():
		_cat_list.select(0)
		_show_category(0)


func _show_category(i: int) -> void:
	_cat_i = i
	for c in _thumb_grid.get_children():
		c.queue_free()
	var kit_root := MapData.KIT_DIR + "/" + str(_cats[i]).get_slice("/", 0)
	var idx := 0
	for pr in _props:
		if pr.category != _cats[i]:
			continue
		var b := TextureButton.new()
		var thumb := kit_root + "/thumbs/" + str(pr.path).trim_prefix(kit_root + "/").replace("/", "__").get_basename() + ".png"
		if ResourceLoader.exists(thumb):
			b.texture_normal = load(thumb)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_SCALE
		b.custom_minimum_size = Vector2(96, 96)
		b.tooltip_text = pr.name
		b.pressed.connect(_pick.bind(pr.path, idx))
		_thumb_grid.add_child(b)
		idx += 1
	_piece_i = 0
	var first := _props.filter(func(p): return p.category == _cats[i])
	if not first.is_empty():
		_pick(first[0].path, 0)


func _pick(path: String, idx: int) -> void:
	prop_path = path
	_piece_i = idx
	tool = Tool.PROP
	for k in tool_buttons.size():
		tool_buttons[k].button_pressed = (k == 0)
	_piece_label.text = path.get_file().get_basename()
	for c in _thumb_grid.get_children():
		c.modulate = Color(1, 1, 1, 1.0 if c.get_index() == idx else 0.55)


func _cycle_grid() -> void:
	grid_i = (grid_i + 1) % grid_steps.size()
	_update_grid_label()


func _update_grid_label() -> void:
	_grid_label.text = "grid %.1f m" % grid_steps[grid_i]


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and not name_edit.has_focus():
		match event.keycode:
			KEY_G:
				_cycle_grid()
				return
			KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
				var in_cat := _props.filter(func(p): return p.category == _cats[_cat_i])
				if in_cat.is_empty():
					return
				_piece_i = (_piece_i + (1 if event.keycode == KEY_BRACKETRIGHT else -1) + in_cat.size()) % in_cat.size()
				_pick(in_cat[_piece_i].path, _piece_i)
				return
	super._unhandled_input(event)


# ---------------------------------------------------------------- placement

func _piece_aabb(path: String, scale: float) -> AABB:
	var key := path + ":%f" % scale
	if _aabb_cache.has(key):
		return _aabb_cache[key]
	var scene: PackedScene = load(path)
	var box := AABB(Vector3.ZERO, Vector3(1, 1, 1))
	if scene:
		var inst: Node3D = scene.instantiate()
		var first := true
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			var b: AABB = mi.transform * mi.mesh.get_aabb()
			var pnode = mi.get_parent()
			while pnode and pnode != inst:
				b = pnode.transform * b
				pnode = pnode.get_parent()
			box = b if first else box.merge(b)
			first = false
		inst.free()
	box = AABB(box.position * scale, box.size * scale)
	_aabb_cache[key] = box
	return box


func _rotated_aabb(box: AABB, steps: int) -> AABB:
	if steps % 2 == 1:
		return AABB(Vector3(-box.end.z, box.position.y, box.position.x), Vector3(box.size.z, box.size.y, box.size.x)) if steps == 1 \
			else AABB(Vector3(box.position.z, box.position.y, -box.end.x), Vector3(box.size.z, box.size.y, box.size.x))
	if steps == 2:
		return AABB(Vector3(-box.end.x, box.position.y, -box.end.z), box.size)
	return box


func _update_cursor() -> void:
	if tool != Tool.PROP or prop_path == "":
		if _ghost_model:
			_ghost_model.visible = false
		super._update_cursor()
		return
	_cursor_valid = false
	ghost.visible = false
	if _looking:
		if _ghost_model:
			_ghost_model.visible = false
		return
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * 600.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		if _ghost_model:
			_ghost_model.visible = false
		return
	_cursor_body = hit.collider
	var box := _rotated_aabb(_piece_aabb(prop_path, prop_scale), rot_steps)
	var n: Vector3 = hit.normal
	var p: Vector3 = hit.position
	var free := Input.is_key_pressed(KEY_SHIFT)
	var g: float = grid_steps[grid_i]
	var pos := p
	# snap against the face we're pointing at: the piece's bounds touch it
	if absf(n.y) > 0.7:
		pos.y = p.y - box.position.y
		if not free:
			pos.x = roundf(p.x / g) * g
			pos.z = roundf(p.z / g) * g
	else:
		pos.y = p.y - box.position.y if _prop_nodes.has(_cursor_body) or _node_to_entry.has(_cursor_body) else p.y
		# put the near side of the piece on the wall we hit
		if absf(n.x) > 0.7:
			pos.x = p.x + (-box.position.x if n.x > 0 else -box.end.x)
			if not free:
				pos.z = roundf(p.z / g) * g
		else:
			pos.z = p.z + (-box.position.z if n.z > 0 else -box.end.z)
			if not free:
				pos.x = roundf(p.x / g) * g
		if not free:
			pos.y = roundf(pos.y / g) * g
	_cursor_pos = pos
	_cursor_valid = true
	_show_ghost(pos)


func _show_ghost(pos: Vector3) -> void:
	if _ghost_path != prop_path + ":%f" % prop_scale:
		if _ghost_model:
			_ghost_model.queue_free()
		_ghost_model = null
		var scene: PackedScene = load(prop_path)
		if scene:
			_ghost_model = scene.instantiate()
			_ghost_model.scale = Vector3.ONE * prop_scale
			var gm := StandardMaterial3D.new()
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.albedo_color = Color(0.6, 0.85, 1.0, 0.45)
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			for mi in _ghost_model.find_children("*", "MeshInstance3D", true, false):
				mi.material_override = gm
			add_child(_ghost_model)
		_ghost_path = prop_path + ":%f" % prop_scale
	if _ghost_model:
		_ghost_model.visible = true
		_ghost_model.position = pos
		_ghost_model.rotation.y = rot_steps * PI / 2
