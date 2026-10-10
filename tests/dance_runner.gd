extends Node
## Banana man dancing in the arena, three-quarter view, for a GIF.

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/arena.tscn")
	for i in 60:
		await get_tree().process_frame
		if Game.arena != null:
			break
	var arena = Game.arena
	# a small stage of blocks in the open south-east quadrant
	var stage := Blocks.make(Blocks.Shape.PLATFORM, "sunset", Vector3i(3, 1, 3))
	stage.position = Vector3(16, 1, 20)   # top face at y = 0.3
	arena.add_child(stage)
	# backdrop behind him (away from the camera)
	var kinds := ["blueberry", "cherry", "cucumber", "peach", "orange"]
	for i in 5:
		var c := Blocks.make(Blocks.Shape.CUBE if i % 2 == 0 else Blocks.Shape.SLAB, kinds[i])
		c.position = Vector3(10 + i * 2.2, 1, 14.5 - (i % 2) * 0.6)
		arena.add_child(c)
	var pillar := Blocks.make(Blocks.Shape.PILLAR, "metal")
	pillar.position = Vector3(21.5, 1, 15)
	arena.add_child(pillar)
	var m := Node3D.new()
	m.set_script(load("res://scripts/player_model.gd"))
	arena.add_child(m)
	m.position = Vector3(16, 0.3, 20)
	m.rotation.y = deg_to_rad(28)  # rig forward is +Z; turn a little toward the camera
	m.load_skin(OS.get_environment("DANCE_SKIN") if OS.get_environment("DANCE_SKIN") != "" else "banana", Color(0.95, 0.8, 0.2))
	var m2 := Node3D.new()
	m2.set_script(load("res://scripts/player_model.gd"))
	arena.add_child(m2)
	m2.position = Vector3(14.2, 0.3, 19.2)
	m2.rotation.y = deg_to_rad(28)
	m2.load_skin(OS.get_environment("DANCE_SKIN2") if OS.get_environment("DANCE_SKIN2") != "" else "banana", Color(0.95, 0.8, 0.2))
	await get_tree().process_frame
	if OS.get_environment("DANCE_DEBUG") == "notex":
		for mat in m.materials:
			mat.set_shader_parameter("use_texture", false)
			mat.set_shader_parameter("albedo_color", Color(0.8, 0.2, 0.2))
	elif OS.get_environment("DANCE_DEBUG") == "nooutline":
		for mat in m.materials:
			mat.next_pass = null
	m.play(OS.get_environment("DANCE_CLIP") if OS.get_environment("DANCE_CLIP") != "" else "Dance")
	m2.play("Idle")
	# hide the HUD overlay for a clean shot
	for c in arena.get_children():
		if c is CanvasLayer:
			c.visible = false
	var cam := Camera3D.new()
	arena.add_child(cam)
	cam.global_position = Vector3(18.4, 1.9, 23.4)
	cam.look_at(Vector3(16, 1.15, 20))
	if OS.get_environment("DANCE_SIDE") != "":
		m.rotation.y = deg_to_rad(90)
		m2.rotation.y = 0.0
		cam.global_position = Vector3(16, 1.5, 24.5)
		cam.look_at(Vector3(16, 1.0, 20))
		cam.fov = 35
	cam.fov = 42
	cam.current = true
	var length: float = m.anim_player.get_animation("ual/Dance").length
	print("DANCE clip length ", length)
	await get_tree().create_timer(length * 2.0).timeout
	get_tree().quit()
