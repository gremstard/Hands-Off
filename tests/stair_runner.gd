extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	await get_tree().process_frame
	var root := Node3D.new()
	get_tree().root.add_child(root)
	var floor := Blocks.make(Blocks.Shape.CUBE, "grass", Vector3i(10, 1, 10))
	floor.position.y = -1
	root.add_child(floor)
	var stairs := Blocks.make(Blocks.Shape.STAIRS, "concrete")
	stairs.position = Vector3(0, 1, -3) # rises toward -Z, first step at z = -2
	root.add_child(stairs)
	Net.player_name = "T"
	Net.host(7798)
	Game.players = {1: {"name": "T", "skin": "red", "team": Game.Team.HIDER, "status": Game.Status.ACTIVE}}
	Game.phase = Game.Phase.PLAYING
	var p = load("res://scenes/player.tscn").instantiate()
	p.name = "1"
	root.add_child(p)
	p.global_position = Vector3(0, 0.1, -0.9)
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("STAIR start y=%.2f on_floor=%s" % [p.global_position.y, p.is_on_floor()])
	for i in 30:
		# push forward like the player holding W
		p.velocity.x = 0
		p.velocity.z = -4.0
		p._stair_step(Vector3(0, 0, -1))
		p.move_and_slide()
		await get_tree().physics_frame
	print("STAIR end y=%.2f z=%.2f" % [p.global_position.y, p.global_position.z])
	get_tree().quit()
