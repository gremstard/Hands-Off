extends Node
## Shows the banana rig in several clips next to the mannequin.

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	var root := Node3D.new()
	get_tree().root.add_child(root)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.82, 0.88, 0.98)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.8, 0.9)
	e.ambient_light_energy = 0.7
	env.environment = e
	root.add_child(env)
	var floor := Blocks.make(Blocks.Shape.CUBE, "grey_light", Vector3i(10, 1, 6))
	floor.position.y = -1
	root.add_child(floor)
	var pairs := [["banana", "A_TPose"], ["mannequin", "A_TPose"], ["banana", "Jog_Fwd"], ["mannequin", "Jog_Fwd"], ["banana", "Idle"]]
	var models := []
	for i in pairs.size():
		var m := Node3D.new()
		m.set_script(load("res://scripts/player_model.gd"))
		m.position = Vector3(-4.4 + i * 2.2, 0, 0)
		root.add_child(m)
		m.load_skin(pairs[i][0], Color.YELLOW)
		models.append(m)
	await get_tree().process_frame
	for i in pairs.size():
		var m = models[i]
		m.play(pairs[i][1])
		m.anim_player.seek(0.4, true)
		m.anim_player.speed_scale = 0.0
		var sk: Skeleton3D = m.skeleton
		var bi := sk.find_bone("upperarm_l")
		print("RIG %s %s current=%s upperarm pose rot=%s pos=%s remapped_path=%s" % [pairs[i][0], pairs[i][1], m.anim_player.current_animation, sk.get_bone_pose_rotation(bi), sk.get_bone_pose_position(bi), m.anim_player.get_animation("ual/A_TPose").track_get_path(0)])
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 1.3, 6.5)
	cam.look_at(Vector3(0, 0.9, 0))
	cam.fov = 55
	cam.current = true
	await get_tree().create_timer(0.8).timeout
	get_tree().quit()
