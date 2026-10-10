extends SceneTree
## Exports assets/maps/_reference.glb: Hany at 1.8 m next to a 2 m block
## and a 1 m cube, so maps modelled in Blender come out at game scale.
func _init() -> void:
	var root := Node3D.new()
	root.name = "Reference"
	get_root().add_child(root)
	var m := Node3D.new()
	m.name = "Hany_1_8m"
	m.set_script(load("res://scripts/player_model.gd"))
	root.add_child(m)
	m.load_skin("red", Color.WHITE)
	var b := Blocks.make(Blocks.Shape.CUBE, "concrete")
	b.name = "Block_2m"
	b.position = Vector3(2.5, 1, 0)
	root.add_child(b)
	var c := MeshInstance3D.new()
	c.name = "Cube_1m"
	c.mesh = BoxMesh.new()
	c.position = Vector3(-2, 0.5, 0)
	root.add_child(c)
	for n in ["JailCenter", "HanderSpawn", "RunnerSpawn1", "Torch1"]:
		var e := Node3D.new()
		e.name = n
		e.position = Vector3(5 + (["JailCenter", "HanderSpawn", "RunnerSpawn1", "Torch1"].find(n)) * 1.5, 0, 0)
		root.add_child(e)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(root, state)
	var err := doc.write_to_filesystem(state, "res://assets/maps/_reference.glb")
	print("reference: ", error_string(err))
	quit(0 if err == OK else 1)
