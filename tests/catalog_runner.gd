extends Node
## Renders every block shape and every named colour for a visual check.

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	var root := Node3D.new()
	get_tree().root.add_child(root)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.85, 0.9, 1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.85)
	e.ambient_light_energy = 0.6
	env.environment = e
	root.add_child(env)
	root.add_child(Blocks.make(Blocks.Shape.CUBE, "grey_light", Vector3i(16, 1, 12)))
	root.get_child(-1).position.y = -2
	# row 1: all shapes in concrete
	for i in Blocks.SHAPE_NAMES.size():
		var b := Blocks.make(i as Blocks.Shape, "sand")
		b.position = Vector3(-11 + i * 2.6, 0, -4)
		root.add_child(b)
	# rows 2-3: all named colours as cubes
	var names: Array = Blocks.TYPES.keys()
	for i in names.size():
		var b := Blocks.make(Blocks.Shape.CUBE, names[i])
		b.position = Vector3(-13.2 + (i % 13) * 2.2, 0, 1 + (i / 13) * 3.0)
		root.add_child(b)
		var l := Label3D.new()
		l.text = names[i]
		l.position = b.position + Vector3(0, 1.6, 0)
		l.font_size = 40
		l.pixel_size = 0.01
		l.outline_size = 10
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(l)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 14, 16)
	cam.look_at(Vector3(0, 0, 0))
	cam.current = true
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()
