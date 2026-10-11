extends Node
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
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = load("res://assets/skyboxes/skybox-day.png")
	sky.sky_material = pm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	env.environment = e
	root.add_child(env)
	var road := MapData.make_prop("res://assets/kits/urban/Roads/Road type 1/road_1_Tjunction.glb")
	root.add_child(road)
	var items := ["Bus stops/busstop.glb", "Litter/Dumpsters/dumpster_diagonal_closed.glb", "Building Parts/block_foot_wall.glb", "Traffic lights/" ]
	var props := MapData.list_props()
	var picks := []
	for want in ["busstop", "dumpster_diagonal_closed", "block_foot_wall", "trafficlight", "traffic_light", "cone", "barrier", "pipe", "metal_trashcan", "bench"]:
		for pr in props:
			if want in pr.name.to_lower():
				picks.append(pr.path)
				break
	var x := -8.0
	for path in picks:
		var inst := MapData.make_prop(path)
		if inst:
			inst.position = Vector3(x, 0.32, -2)
			root.add_child(inst)
			x += 3.0
	var m := Node3D.new()
	m.set_script(load("res://scripts/player_model.gd"))
	root.add_child(m)
	m.position = Vector3(-3, 0.32, 2)
	m.rotation.y = deg_to_rad(20)
	m.load_skin("red", Color.WHITE)
	m.play("Idle")
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(1, 4.5, 11)
	cam.look_at(Vector3(0, 1.2, -1))
	cam.fov = 55
	cam.current = true
	print("KIT picks ", picks.size())
	await get_tree().create_timer(0.8).timeout
	get_tree().quit()
