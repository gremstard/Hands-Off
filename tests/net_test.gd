extends Node
## Two-process network test. Run two headless instances:
##   godot --headless --path . res://tests/net_test.tscn -- host
##   godot --headless --path . res://tests/net_test.tscn -- client
## Each prints PASS/FAIL lines and exits 0/1.

const PORT := 7790
var role := "host"
var failures := 0
var _t := 0.0


func check(cond: bool, what: String) -> void:
	if cond:
		print("[%s]  PASS  %s" % [role, what])
	else:
		failures += 1
		printerr("[%s]  FAIL  %s" % [role, what])


func _ready() -> void:
	if has_meta("runner"):
		return
	for a in OS.get_cmdline_user_args():
		if a == "client":
			role = "client"
	var runner := Node.new()
	runner.set_script(get_script())
	runner.role = role
	runner.set_meta("runner", true)
	get_tree().root.add_child.call_deferred(runner)


func _process(delta: float) -> void:
	if not has_meta("runner"):
		return
	_t += delta
	if _t > 40.0:
		printerr("[%s]  FAIL  timeout" % role)
		get_tree().quit(1)


func _enter_tree() -> void:
	if has_meta("runner"):
		call_deferred("_run")


func _run() -> void:
	if role == "host":
		await _run_host()
	else:
		await _run_client()
	print("[%s] %d failure(s)" % [role, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _wait(cond: Callable, secs: float = 15.0) -> bool:
	var t := 0.0
	while t < secs:
		if cond.call():
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return false


func _run_host() -> void:
	Net.player_name = "HostPlayer"
	check(Net.host(PORT) == OK, "server listening on %d" % PORT)
	check(await _wait(func(): return Net.players.size() == 2), "client registered in lobby")
	Game.sync_mode(Game.Mode.TAG)
	Game.sync_headstart.rpc(3.0) # keep the test short (lobby offers 1-5 min)
	Net.players[1].volunteer = true # skip the 20 s Hander call
	await get_tree().create_timer(0.5).timeout
	Game.start_game()
	check(await _wait(func(): return Game.arena != null and Game.arena.players_root.get_child_count() == 2),
		"both players spawned on host")
	check(await _wait(func(): return Game.phase == Game.Phase.PLAYING, 15.0), "head start ended, now PLAYING")
	# client moves its player to a known spot; synchroniser must deliver it
	var client_id: int = -1
	for id in Game.players:
		if id != 1:
			client_id = id
	check(await _wait(func():
		var n = Game.arena.get_player_node(client_id)
		return n != null and n.global_position.distance_to(Vector3(5, 1, 5)) < 0.5, 10.0),
		"client position replicated to host")
	# host tags the client (server-side) -> client should see team change
	var me = Game.arena.get_player_node(1)
	me.global_position = Vector3(6, 1, 5)
	var host_p: Dictionary = Game.players[1]
	var cli_p: Dictionary = Game.players[client_id]
	# make sure host is the seeker for a deterministic tag
	host_p.team = Game.Team.SEEKER
	cli_p.team = Game.Team.HIDER
	Game.sync_players.rpc(Game.players)
	await get_tree().create_timer(0.3).timeout
	Game._do_tag(1, client_id)
	check(Game.players[client_id].team == Game.Team.SEEKER, "host tag converted client")
	check(await _wait(func(): return Game.phase == Game.Phase.ENDED, 5.0), "round ended on host")
	await get_tree().create_timer(2.0).timeout
	Net.leave()


func _run_client() -> void:
	Net.player_name = "ClientPlayer"
	await get_tree().create_timer(1.0).timeout # let host come up
	check(Net.join("127.0.0.1:%d" % PORT) == OK, "join call ok")
	check(await _wait(func(): return Net.players.size() == 2), "saw both players in lobby roster")
	check(await _wait(func(): return Game.mode == Game.Mode.TAG, 5.0), "mode synced from host")
	check(await _wait(func(): return Game.arena != null and Game.arena.players_root.get_child_count() == 2),
		"both players spawned on client")
	var my_id := multiplayer.get_unique_id()
	var me = Game.arena.get_player_node(my_id)
	check(me != null and me.is_multiplayer_authority(), "client owns its player node")
	check(await _wait(func(): return Game.phase == Game.Phase.PLAYING, 15.0), "PLAYING phase received")
	me.teleport(Vector3(5, 1, 5))
	check(await _wait(func(): return Game.players.get(my_id, {}).get("team") == Game.Team.SEEKER, 10.0),
		"team change from host tag arrived")
	check(await _wait(func(): return Game.phase == Game.Phase.ENDED, 5.0), "round end received")
	Net.leave()
