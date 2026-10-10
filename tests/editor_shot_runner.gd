extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/map_editor.tscn")
	for i in 6: await get_tree().process_frame
	var ed = get_tree().current_scene
	ed.cam.position = Vector3(10, 14, 30)
	ed._yaw = 0.3
	ed._pitch = -0.45
	ed._apply_cam_rotation()
	ed._set_shape(5)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()
