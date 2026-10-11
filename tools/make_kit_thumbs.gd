extends Node
## Renders a 96px thumbnail for every kit piece into assets/kits/<kit>/thumbs/.
## Run (needs a window):  Godot --path . res://tools/kit_thumbs.tscn

var _vp: SubViewport
var _cam: Camera3D
var _holder: Node3D

func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(96, 96)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	_vp.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.17, 0.18, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.9)
	e.ambient_light_energy = 0.7
	env.environment = e
	_vp.add_child(env)
	_holder = Node3D.new()
	_vp.add_child(_holder)
	_cam = Camera3D.new()
	_cam.fov = 35
	_vp.add_child(_cam)
	_cam.current = true
	call_deferred("_run")

func _run() -> void:
	var props := MapData.list_props()
	var n := 0
	for pr in props:
		var dir: String = pr.path.get_base_dir()
		var kit_root := dir
		while kit_root.get_base_dir() != MapData.KIT_DIR and kit_root != MapData.KIT_DIR:
			kit_root = kit_root.get_base_dir()
		var out_dir := kit_root + "/thumbs"
		DirAccess.make_dir_recursive_absolute(out_dir)
		var out: String = out_dir + "/" + pr.path.trim_prefix(kit_root + "/").replace("/", "__").get_basename() + ".png"
		if FileAccess.file_exists(out):
			continue
		for c in _holder.get_children():
			c.free()
		var scene: PackedScene = load(pr.path)
		if scene == null:
			continue
		var inst: Node3D = scene.instantiate()
		_holder.add_child(inst)
		var aabb := _bounds(inst)
		var center := aabb.get_center()
		var radius := maxf(aabb.size.length() * 0.5, 0.2)
		var dir3 := Vector3(1, 0.8, 1.3).normalized()
		_cam.position = center + dir3 * radius * 2.6
		_cam.look_at(center)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_vp.get_texture().get_image().save_png(out)
		n += 1
	print("thumbs: ", n)
	get_tree().quit()

func _bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
