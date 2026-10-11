extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/kit_builder.tscn")
	for i in 8: await get_tree().process_frame
	var kb = get_tree().current_scene
	kb.cam.position = Vector3(6, 6, 16)
	kb._yaw = 0.2
	kb._pitch = -0.35
	kb._apply_cam_rotation()
	var m := MapData.new()
	m.name = "Kit demo"
	m.add_block(Blocks.Shape.CUBE, "asphalt", Vector3(0, -1, 0), 0, Vector3i(20, 1, 20))
	var picks := {}
	for pr in MapData.list_props():
		for want in ["busstop", "dumpster_diagonal_closed", "block_foot_wall", "cone"]:
			if want in pr.name.to_lower() and not picks.has(want):
				picks[want] = pr.path
	m.add_prop(picks.get("busstop", ""), Vector3(0, 0, 0))
	m.add_prop(picks.get("dumpster_diagonal_closed", ""), Vector3(5, 0, 1), PI / 2)
	m.add_prop(picks.get("block_foot_wall", ""), Vector3(-5, 0, -2))
	m.add_prop(picks.get("cone", ""), Vector3(3, 0, 5))
	kb.load_map(m)
	kb._cat_list.select(1)
	kb._show_category(1)
	await get_tree().create_timer(1.2).timeout
	get_tree().quit()
