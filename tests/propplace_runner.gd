extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/kit_builder.tscn")
	for i in 8: await get_tree().process_frame
	var kb = get_tree().current_scene
	kb.cam.position = Vector3(0, 12, 20)
	kb._yaw = 0.0
	kb._pitch = -0.6
	kb._apply_cam_rotation()
	get_viewport().warp_mouse(get_viewport().get_visible_rect().size / 2.0)
	await get_tree().process_frame
	var failed := []
	var n := 0
	for pr in MapData.list_props():
		kb.prop_path = pr.path
		kb.tool = kb.Tool.PROP
		kb._update_cursor()
		var before: int = kb.map.props.size()
		if not kb._cursor_valid:
			failed.append(pr.name + " (no cursor)")
			continue
		kb._act()
		if kb.map.props.size() != before + 1:
			failed.append(pr.name + " (not added)")
			continue
		n += 1
		# remove it again so the next one hits the ground
		var e = kb.map.props.back()
		kb.map.props.erase(e)
		for k in kb._prop_nodes.keys():
			if kb._prop_nodes[k].entry == e:
				kb._prop_nodes[k].root.queue_free()
				kb._prop_nodes.erase(k)
		await get_tree().process_frame
	print("PLACE ok=%d failed=%d" % [n, failed.size()])
	for f in failed.slice(0, 12): print("  ", f)
	get_tree().quit()
