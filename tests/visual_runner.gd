extends Node
## Spawns a round with several skins and parks a camera for frame capture.

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	Net.player_name = "Host"
	Net.skin = "banana"
	Net.host(7791)
	var skins := ["golden", "red", "skyblue", "lime", "purple", "silver", "watermelon"]
	for i in skins.size():
		Net.players[i + 2] = {"name": skins[i].capitalize(), "skin": skins[i]}
	Game.sync_mode(Game.Mode.COPS_ROBBERS)
	Net.players[3].volunteer = true
	Net.players[3].volunteer_at = 1
	Net.players[4].volunteer = true
	Net.players[4].volunteer_at = 2
	Game.start_game()
	for i in 120:
		await get_tree().process_frame
		if Game.arena != null:
			break
	for i in range(2, 2 + skins.size()):
		Game._peer_ready(i)
	await get_tree().process_frame
	# line everyone up in front of the jail so one shot shows them all
	var ids: Array = Game.players.keys()
	ids.sort()
	var k := 0
	for id in ids:
		var n = Game.arena.get_player_node(id)
		n.global_position = Vector3(-14 + k * 2.2, 0.5, 16)
		n.rotation.y = PI
		k += 1
	Game.set_phase(Game.Phase.PLAYING, 120.0)
	for id in ids:
		if id != 1:
			Game.arena.get_player_node(id).anim = ["Idle", "Jog_Fwd", "Sprint", "Dance", "Walk"][id % 5]
	if OS.get_environment("FPVIEW") != "":
		# look through the host's own eyes at the others: arms + tags
		var me = Game.arena.get_player_node(1)
		me.global_position = Vector3(-6, 0.5, 20)
		me.rotation.y = 0.0
		me.anim = "Punch_Jab"
		me.model.play_oneshot("Punch_Jab")
		me.pivot.rotation.x = -0.35
		await get_tree().create_timer(0.35).timeout
		me.model.anim_player.speed_scale = 0.0
		for id in ids:
			if id != 1:
				var n = Game.arena.get_player_node(id)
				n.global_position = Vector3(-14 + (id - 2) * 2.5, 0.5, 14)
				n.rotation.y = PI
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
		return
	# detached camera
	var cam := Camera3D.new()
	Game.arena.add_child(cam)
	cam.global_position = Vector3(-7, 4.5, 26)
	cam.look_at(Vector3(-7, 1.2, 14))
	cam.fov = 60
	cam.current = true
	await get_tree().create_timer(2.5).timeout
	cam.global_position = Vector3(-20, 9, 42)
	cam.look_at(Vector3(-24, 1.5, 27)) # jail + torches
	await get_tree().create_timer(1.5).timeout
	cam.global_position = Vector3(30, 28, 50)
	cam.look_at(Vector3(0, 0, 0)) # overview
	await get_tree().create_timer(1.5).timeout
	get_tree().quit()
