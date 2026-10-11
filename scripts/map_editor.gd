extends Node3D
## Map editor: fly around, place blocks and zones, save/load .hom files.
##
##  WASD / Q E     fly (Shift = fast)      Right mouse (hold)  look around
##  Left click     place                   X / Delete           remove under cursor
##  R              rotate 90 degrees       [ ]                  previous / next shape
##  Ctrl+S         save                    Esc                  back to menu

const FLY := 14.0
const FAST := 36.0
const SENS := 0.0025
const GHOST_COLOR := Color(1, 1, 1, 0.35)

enum Tool { BLOCK, ERASE, JAIL, HANDER, RUNNER, TORCH, PROP }
const TOOL_NAMES := ["Block", "Erase", "Jail", "Hander", "Runner", "Torch", "Prop"]
const MARKER_COLORS := {"jail": Color(0.9, 0.3, 0.3), "hander": Color(0.3, 0.5, 1.0), "runner": Color(0.3, 0.9, 0.4), "torch": Color(1.0, 0.7, 0.2)}

var map: MapData
var cam: Camera3D
var blocks_root: Node3D
var markers_root: Node3D
var ghost: MeshInstance3D
var ghost_mat: StandardMaterial3D
var tool: Tool = Tool.BLOCK
var shape: Blocks.Shape = Blocks.Shape.CUBE
var block_name := "concrete"
var custom_col := 4
var custom_row := 5
var cells := Vector3i.ONE
var rot_steps := 0
var _looking := false
var _yaw := 0.0
var _pitch := -0.4
var _node_to_entry: Dictionary = {}  # StaticBody3D -> block dict
var _prop_nodes: Dictionary = {}     # StaticBody3D (any under the prop) -> prop dict
var _props: Array[Dictionary] = []
var prop_path := ""
var prop_scale := 1.0
var cat_opt: OptionButton
var prop_opt: OptionButton
var _marker_nodes: Dictionary = {}   # Node3D -> marker dict
var _cursor_valid := false
var _cursor_pos := Vector3.ZERO
var _cursor_body: Node = null

# UI
var ui: CanvasLayer
var shape_opt: OptionButton
var color_opt: OptionButton
var col_spin: SpinBox
var row_spin: SpinBox
var cx: SpinBox
var cy: SpinBox
var cz: SpinBox
var name_edit: LineEdit
var load_opt: OptionButton
var status: Label
var tool_buttons: Array[Button] = []
var _maps: Array[Dictionary] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_environment()
	blocks_root = Node3D.new()
	add_child(blocks_root)
	markers_root = Node3D.new()
	add_child(markers_root)
	cam = Camera3D.new()
	cam.position = Vector3(0, 18, 34)
	cam.fov = 65
	add_child(cam)
	cam.current = true
	_apply_cam_rotation()
	ghost = MeshInstance3D.new()
	ghost_mat = StandardMaterial3D.new()
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.albedo_color = GHOST_COLOR
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost.material_override = ghost_mat
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ghost)
	# invisible ground for placing on empty space
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	ground.add_child(cs)
	ground.position.y = -0.01
	ground.name = "Ground"
	add_child(ground)
	_build_ui()
	load_map(MapData.default_map())


func _environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var pano: Texture2D = load("res://assets/skyboxes/skybox-day.png")
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = pano
	sky.sky_material = pm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)


# ---------------------------------------------------------------- map <-> scene

func load_map(m: MapData) -> void:
	map = m
	for c in blocks_root.get_children():
		c.queue_free()
	for c in markers_root.get_children():
		c.queue_free()
	_node_to_entry.clear()
	_marker_nodes.clear()
	for b in map.blocks:
		_spawn_block(b)
	for mk in map.markers:
		_spawn_marker(mk)
	for pr in map.props:
		_spawn_prop(pr)
	name_edit.text = map.name
	_status("Loaded '%s': %d blocks, %d zones" % [map.name, map.blocks.size(), map.markers.size()])


func _spawn_block(b: Dictionary) -> StaticBody3D:
	var n := Vector3i.ONE
	if b.has("n"):
		n = Vector3i(int(b.n[0]), int(b.n[1]), int(b.n[2]))
	var body: StaticBody3D
	if str(b.get("b", "")) == "custom":
		body = Blocks.make_custom(int(b.s) as Blocks.Shape, int(b.get("c", 0)), int(b.get("r", 0)), n)
	else:
		body = Blocks.make(int(b.s) as Blocks.Shape, str(b.get("b", "concrete")), n)
	body.position = MapData.vec(b.p)
	body.rotation.y = float(b.get("ry", 0.0))
	blocks_root.add_child(body)
	_node_to_entry[body] = b
	return body


func _spawn_prop(pr: Dictionary) -> void:
	var inst := MapData.make_prop(str(pr.m), float(pr.get("s", 1.0)))
	if inst == null:
		return
	inst.position = MapData.vec(pr.p)
	inst.rotation.y = float(pr.get("ry", 0.0))
	blocks_root.add_child(inst)
	for b in inst.find_children("*", "StaticBody3D", true, false):
		_prop_nodes[b] = {"entry": pr, "root": inst}


func _spawn_marker(mk: Dictionary) -> void:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.9
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = MARKER_COLORS.get(str(mk.k), Color.WHITE)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mi.material_override = mat
	n.add_child(mi)
	var l := Label3D.new()
	l.text = str(mk.k).to_upper()
	l.position.y = 1.0
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 48
	l.pixel_size = 0.01
	l.outline_size = 8
	n.add_child(l)
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 0.6
	cs.shape = ss
	area.add_child(cs)
	n.add_child(area)
	n.position = MapData.vec(mk.p)
	markers_root.add_child(n)
	_marker_nodes[area] = mk


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_looking = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _looking:
			_act()
	elif event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * SENS
		_pitch = clampf(_pitch - event.relative.y * SENS, -1.5, 1.5)
		_apply_cam_rotation()
	elif event is InputEventKey and event.pressed and not event.echo:
		if name_edit.has_focus():
			return
		match event.keycode:
			KEY_R:
				rot_steps = (rot_steps + 1) % 4
				_status("Rotation: %d degrees" % (rot_steps * 90))
			KEY_BRACKETLEFT:
				_set_shape((int(shape) - 1 + Blocks.SHAPE_NAMES.size()) % Blocks.SHAPE_NAMES.size())
			KEY_BRACKETRIGHT:
				_set_shape((int(shape) + 1) % Blocks.SHAPE_NAMES.size())
			KEY_X, KEY_DELETE:
				_erase_under_cursor()
			KEY_S:
				if event.ctrl_pressed or event.meta_pressed:
					_save()
			KEY_ESCAPE:
				if _looking:
					_looking = false
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _apply_cam_rotation() -> void:
	cam.rotation = Vector3(_pitch, _yaw, 0)


func _process(delta: float) -> void:
	if not name_edit.has_focus():
		var v := Vector3.ZERO
		if Input.is_key_pressed(KEY_W): v.z -= 1
		if Input.is_key_pressed(KEY_S) and not (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)): v.z += 1
		if Input.is_key_pressed(KEY_A): v.x -= 1
		if Input.is_key_pressed(KEY_D): v.x += 1
		if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE): v.y += 1
		if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL): v.y -= 1
		var speed := FAST if Input.is_key_pressed(KEY_SHIFT) else FLY
		if v != Vector3.ZERO:
			var basis := cam.global_transform.basis
			var dir := (basis.x * v.x + basis.z * v.z).normalized() * speed + Vector3.UP * v.y * speed
			cam.position += dir * delta
	_update_cursor()


func _update_cursor() -> void:
	_cursor_valid = false
	ghost.visible = false
	if _looking:
		return
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * 600.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	_cursor_body = hit.collider
	var p: Vector3 = hit.position + hit.normal * 0.5
	var base := Vector3(roundf(p.x / Blocks.CELL) * Blocks.CELL, floorf(p.y / Blocks.CELL) * Blocks.CELL + 1.0, roundf(p.z / Blocks.CELL) * Blocks.CELL)
	_cursor_valid = true
	if tool == Tool.BLOCK:
		var ext := Vector3(cells.x - 1, cells.y - 1, cells.z - 1) * (Blocks.CELL / 2.0)
		if rot_steps % 2 == 1:
			ext = Vector3(ext.z, ext.y, ext.x)
		_cursor_pos = base + Vector3(ext.x, ext.y, ext.z)
		ghost.mesh = Blocks.mesh(shape, cells)
		ghost.position = _cursor_pos
		ghost.rotation.y = rot_steps * PI / 2
		ghost.visible = true
	elif tool == Tool.ERASE:
		_cursor_pos = base
	elif tool == Tool.PROP:
		# props sit on the surface you point at, free placement on the grid's half steps
		_cursor_pos = Vector3(roundf(p.x), hit.position.y, roundf(p.z))
		if prop_path != "":
			ghost.mesh = BoxMesh.new()
			ghost.position = _cursor_pos + Vector3(0, 0.5, 0)
			ghost.rotation.y = rot_steps * PI / 2
			ghost.visible = true
	else:
		_cursor_pos = Vector3(base.x, base.y - 0.5, base.z)
		ghost.mesh = SphereMesh.new()
		ghost.position = _cursor_pos
		ghost.visible = true


func _act() -> void:
	if not _cursor_valid:
		return
	match tool:
		Tool.BLOCK:
			var e := map.add_block(shape, block_name, _cursor_pos, rot_steps * PI / 2, cells, custom_col, custom_row)
			_spawn_block(e)
			Sfx.play("ui_click", -6.0)
		Tool.ERASE:
			_erase_under_cursor()
		Tool.JAIL:
			_place_marker(MapData.JAIL)
		Tool.HANDER:
			_place_marker(MapData.HANDER)
		Tool.RUNNER:
			_place_marker(MapData.RUNNER)
		Tool.TORCH:
			_place_marker(MapData.TORCH)
		Tool.PROP:
			if prop_path != "":
				var e := map.add_prop(prop_path, _cursor_pos, rot_steps * PI / 2, prop_scale)
				_spawn_prop(e)
				Sfx.play("ui_click", -6.0)


func _place_marker(kind: String) -> void:
	map.add_marker(kind, _cursor_pos)
	# rebuild markers (single-instance kinds replace)
	for c in markers_root.get_children():
		c.queue_free()
	_marker_nodes.clear()
	for mk in map.markers:
		_spawn_marker(mk)
	_status("%s placed" % kind.capitalize())


func _erase_under_cursor() -> void:
	if _cursor_body == null:
		return
	if _node_to_entry.has(_cursor_body):
		map.blocks.erase(_node_to_entry[_cursor_body])
		_node_to_entry.erase(_cursor_body)
		_cursor_body.queue_free()
		_cursor_body = null
		Sfx.play("ui_back", -6.0)
	elif _prop_nodes.has(_cursor_body):
		var info: Dictionary = _prop_nodes[_cursor_body]
		map.props.erase(info.entry)
		for k in _prop_nodes.keys():
			if _prop_nodes[k].root == info.root:
				_prop_nodes.erase(k)
		info.root.queue_free()
		_cursor_body = null
		Sfx.play("ui_back", -6.0)
	elif _marker_nodes.has(_cursor_body):
		map.markers.erase(_marker_nodes[_cursor_body])
		_marker_nodes.erase(_cursor_body)
		_cursor_body.get_parent().queue_free()
		_cursor_body = null


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 12
	panel.offset_right = -12
	panel.offset_bottom = -12
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ui.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var row1 := HFlowContainer.new()
	row1.add_theme_constant_override("separation", 6)
	v.add_child(row1)
	for i in TOOL_NAMES.size():
		var b := Button.new()
		b.text = TOOL_NAMES[i]
		b.toggle_mode = true
		b.button_pressed = (i == 0)
		b.pressed.connect(_set_tool.bind(i))
		row1.add_child(b)
		tool_buttons.append(b)
	row1.add_child(VSeparator.new())
	row1.add_child(_lbl("Shape"))
	shape_opt = OptionButton.new()
	for n in Blocks.SHAPE_NAMES:
		shape_opt.add_item(n)
	shape_opt.item_selected.connect(func(i: int) -> void: _set_shape(i))
	row1.add_child(shape_opt)
	row1.add_child(_lbl("Colour"))
	color_opt = OptionButton.new()
	for n in Blocks.TYPES.keys():
		color_opt.add_item(n)
	color_opt.add_item("custom")
	color_opt.item_selected.connect(func(i: int) -> void:
		block_name = color_opt.get_item_text(i)
		col_spin.editable = block_name == "custom"
		row_spin.editable = block_name == "custom")
	row1.add_child(color_opt)
	col_spin = _spin(row1, "col", 0, Blocks.COLS - 1, custom_col, func(val: float) -> void: custom_col = int(val))
	row_spin = _spin(row1, "row", 0, Blocks.ROWS - 1, custom_row, func(val: float) -> void: custom_row = int(val))
	col_spin.editable = false
	row_spin.editable = false
	row1.add_child(VSeparator.new())
	row1.add_child(_lbl("Cells"))
	cx = _spin(row1, "x", 1, 60, 1, func(val: float) -> void: cells.x = int(val))
	cy = _spin(row1, "y", 1, 20, 1, func(val: float) -> void: cells.y = int(val))
	cz = _spin(row1, "z", 1, 60, 1, func(val: float) -> void: cells.z = int(val))

	var rowp := HFlowContainer.new()
	rowp.add_theme_constant_override("separation", 6)
	v.add_child(rowp)
	rowp.add_child(_lbl("Prop"))
	_props = MapData.list_props()
	cat_opt = OptionButton.new()
	var cats := []
	for pr in _props:
		if not cats.has(pr.category):
			cats.append(pr.category)
	for c in cats:
		cat_opt.add_item(c)
	cat_opt.custom_minimum_size.x = 200
	rowp.add_child(cat_opt)
	prop_opt = OptionButton.new()
	prop_opt.custom_minimum_size.x = 240
	rowp.add_child(prop_opt)
	var fill_props := func(ci: int) -> void:
		prop_opt.clear()
		if ci < 0 or cats.is_empty():
			return
		for pr in _props:
			if pr.category == cats[ci]:
				prop_opt.add_item(pr.name)
				prop_opt.set_item_metadata(prop_opt.item_count - 1, pr.path)
		if prop_opt.item_count > 0:
			prop_opt.select(0)
			prop_path = prop_opt.get_item_metadata(0)
	cat_opt.item_selected.connect(fill_props)
	prop_opt.item_selected.connect(func(i: int) -> void:
		prop_path = prop_opt.get_item_metadata(i)
		_set_tool(Tool.PROP))
	if not cats.is_empty():
		fill_props.call(0)
	_spin(rowp, "scale", 1, 400, 100, func(val: float) -> void: prop_scale = val / 100.0)

	var row2 := HFlowContainer.new()
	row2.add_theme_constant_override("separation", 6)
	v.add_child(row2)
	row2.add_child(_lbl("Map name"))
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size.x = 200
	name_edit.text_changed.connect(func(t: String) -> void: map.name = t)
	row2.add_child(name_edit)
	var save := Button.new()
	save.text = "Save .hom"
	save.pressed.connect(_save)
	row2.add_child(save)
	row2.add_child(_lbl("Load"))
	load_opt = OptionButton.new()
	load_opt.custom_minimum_size.x = 180
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
	newb.text = "New (empty)"
	newb.pressed.connect(func() -> void:
		var m := MapData.new()
		m.name = "New map"
		m.add_block(Blocks.Shape.CUBE, "grass", Vector3(0, -1, 0), 0, Vector3i(36, 1, 36))
		load_map(m))
	row2.add_child(newb)
	var folder := Button.new()
	folder.text = "Open maps folder"
	folder.pressed.connect(func() -> void:
		DirAccess.make_dir_recursive_absolute(MapData.USER_DIR)
		OS.shell_open(ProjectSettings.globalize_path(MapData.USER_DIR)))
	row2.add_child(folder)
	var back := Button.new()
	back.text = "Back to menu"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	row2.add_child(back)

	status = Label.new()
	status.add_theme_font_size_override("font_size", 13)
	status.modulate = Color(0.85, 0.9, 1.0)
	v.add_child(status)
	var help := Label.new()
	help.text = "WASD + Q/E fly (Shift fast)   hold Right mouse to look   Left click place   X remove   R rotate   [ ] shape   Ctrl+S save   Esc menu"
	help.add_theme_font_size_override("font_size", 12)
	help.modulate = Color(0.7, 0.7, 0.75)
	v.add_child(help)


func _lbl(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _spin(parent: Control, prefix: String, lo: int, hi: int, val: int, cb: Callable) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.value = val
	sb.prefix = prefix + " "
	sb.value_changed.connect(cb)
	parent.add_child(sb)
	return sb


func _set_tool(i: int) -> void:
	tool = i as Tool
	for k in tool_buttons.size():
		tool_buttons[k].button_pressed = (k == i)
	_status("Tool: " + TOOL_NAMES[i])


func _set_shape(i: int) -> void:
	shape = i as Blocks.Shape
	shape_opt.select(i)
	_status("Shape: " + Blocks.SHAPE_NAMES[i])


func _refresh_maps() -> void:
	_maps = MapData.list_maps()
	load_opt.clear()
	load_opt.add_item("Blockyard (built in)")
	for m in _maps:
		load_opt.add_item(m.name + ("" if m.builtin else "  (yours)"))


func _save() -> void:
	var n := name_edit.text.strip_edges()
	if n == "":
		_status("Give the map a name first.")
		return
	map.name = n
	var path := MapData.user_path(n)
	var err := map.save_file(path)
	if err == OK:
		_status("Saved %s  (%d blocks, %d zones). Share this file with friends." % [ProjectSettings.globalize_path(path), map.blocks.size(), map.markers.size()])
		Sfx.play("ui_confirm")
		_refresh_maps()
	else:
		_status("Save failed: %s" % error_string(err))
		Sfx.play("ui_error")


func _status(t: String) -> void:
	status.text = t
