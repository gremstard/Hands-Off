extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	await get_tree().process_frame
	var props := MapData.list_props()
	var bad := []
	var nomesh := []
	for pr in props:
		var inst := MapData.make_prop(pr.path)
		if inst == null:
			bad.append(pr.path)
			continue
		if inst.find_children("*", "MeshInstance3D", true, false).is_empty():
			nomesh.append(pr.path)
		inst.free()
	print("PROPS total=%d failed=%d nomesh=%d" % [props.size(), bad.size(), nomesh.size()])
	for b in bad.slice(0, 8): print("  FAIL ", b)
	for b in nomesh.slice(0, 8): print("  NOMESH ", b)
	get_tree().quit()
