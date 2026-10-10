extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await get_tree().create_timer(0.6).timeout
	Net.player_name = "Hany"
	Net.host(7797)
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
	await get_tree().create_timer(0.6).timeout
	get_tree().change_scene_to_file("res://scenes/settings.tscn")
	await get_tree().create_timer(0.6).timeout
	get_tree().quit()
