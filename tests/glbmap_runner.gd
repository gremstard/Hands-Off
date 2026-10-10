extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	await get_tree().process_frame
	Net.player_name = "Host"
	Net.host(7796)
	Net.players[2] = {"name": "Bob", "skin": "red", "volunteer": true, "volunteer_at": 1}
	Game.sync_mode(Game.Mode.HIDE_AND_SEEK)
	Game.set_map("res://assets/maps/_reference.glb")
	Game.start_game()
	for i in 120:
		await get_tree().process_frame
		if Game.arena != null:
			break
	Game._peer_ready(2)
	await get_tree().process_frame
	var bodies := Game.arena.find_children("*", "StaticBody3D", true, false).size()
	print("GLBMAP arena=%s bodies=%d jail=%s hander=%s runners=%d players=%d" % [Game.arena != null, bodies, Game.arena._jail, Game.arena._seeker_pos, Game.arena._hider_spawns.size(), Game.arena.players_root.get_child_count()])
	get_tree().quit(0 if bodies >= 2 and Game.arena._hider_spawns.size() == 1 else 1)
