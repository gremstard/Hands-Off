extends Node

var failures := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  PASS  ", what)
	else:
		failures += 1
		printerr("  FAIL  ", what)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	Net.player_name = "Host"
	check(Net.host(7788) == OK, "host server on 7788")
	Net.players[2] = {"name": "Bob", "skin": "golden"}
	Net.players[3] = {"name": "Cat", "skin": "mannequin"}
	Net.players[4] = {"name": "Dan", "skin": "red"}
	Net.players[5] = {"name": "Eve", "skin": "does-not-exist"}

	Game.wins.clear()
	await _round(Game.Mode.HIDE_AND_SEEK, _play_hide_and_seek)
	check(Game.wins.size() == 1 and Game.wins.values()[0] == 1, "seeker credited with a win: %s" % str(Game.wins))
	await _round(Game.Mode.TAG, _play_tag)
	await _round(Game.Mode.COPS_ROBBERS, _play_cops_robbers)
	var host_before: int = Game.wins.get("Host", 0)
	await _round(Game.Mode.MANHUNT, _play_manhunt)
	check(Game.wins.get("Host", 0) == host_before + 1, "manhunt last-one-standing credited: %s" % str(Game.wins))
	check(FileAccess.file_exists(Game.WINS_FILE), "wins saved to disk")

	print("\n%d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _round(mode: int, play: Callable) -> void:
	print("\n=== %s ===" % Game.make_rules(mode).display_name())
	Game.sync_mode(mode)
	Net.players[2].volunteer = true
	Net.players[2].volunteer_at = 1
	Game.start_game()
	# wait for the arena to load and report
	for i in 120:
		await get_tree().process_frame
		if Game.arena != null:
			break
	check(Game.arena != null, "arena loaded")
	for id in [2, 3, 4, 5]:
		Game._peer_ready(id)
	await get_tree().process_frame
	check(Game.arena.players_root.get_child_count() == 5, "5 players spawned")
	check(Game.phase == Game.Phase.HEADSTART, "head start phase")
	Game.set_phase(Game.Phase.PLAYING, 120.0)
	await play.call()
	check(Game.phase == Game.Phase.ENDED, "round ended: " + Game.winner_text)
	Game.return_to_lobby()
	for i in 10:
		await get_tree().process_frame


func _put_together(a: int, b: int) -> void:
	var na = Game.arena.get_player_node(a)
	var nb = Game.arena.get_player_node(b)
	na.global_position = Vector3(0, 1, 20)
	nb.global_position = Vector3(1, 1, 20)


func _play_hide_and_seek() -> void:
	var seekers: Array = Game.ids_with(Game.Team.SEEKER, -1)
	var hiders: Array = Game.ids_with(Game.Team.HIDER, -1)
	check(seekers.size() == 1 and hiders.size() == 4, "1 seeker / 4 hiders")
	var s: int = seekers[0]
	# far away tag must fail
	Game._do_tag(s, hiders[0])
	check(Game.players[hiders[0]].status == Game.Status.ACTIVE, "tag out of range rejected")
	# hider tagging seeker must fail
	_put_together(hiders[0], s)
	Game._do_tag(hiders[0], s)
	check(Game.players[s].status == Game.Status.ACTIVE, "hider cannot tag seeker")
	for h in hiders:
		_put_together(s, h)
		Game._do_tag(s, h)
		check(Game.players[h].status == Game.Status.OUT, "hider %d knocked out" % h)
	check(Game.winner_text.begins_with("Handers win"), "seekers win when all hiders found")


func _play_tag() -> void:
	# a late joiner arrives mid-round as a spectator
	Net.players[9] = {"name": "Late", "skin": "peach"}
	Game.add_spectator(9, "Late", "peach")
	Game._peer_ready(9)
	await get_tree().process_frame
	check(Game.players.has(9) and Game.players[9].status == Game.Status.OUT and Game.players[9].spectator, "late joiner is a spectator")
	check(Game.arena.get_player_node(9) != null, "late joiner spawned as spectator")
	check(Game.phase == Game.Phase.PLAYING, "phase unchanged by late join")
	var s: int = Game.ids_with(Game.Team.SEEKER, -1)[0]
	var hiders: Array = Game.ids_with(Game.Team.HIDER, -1)
	_put_together(s, hiders[0])
	Game._do_tag(s, hiders[0])
	check(Game.players[hiders[0]].team == Game.Team.SEEKER, "tagged hider becomes seeker")
	# converted player can now tag
	_put_together(hiders[0], hiders[1])
	Game._do_tag(hiders[0], hiders[1])
	check(Game.players[hiders[1]].team == Game.Team.SEEKER, "converted seeker can tag")
	for h in [hiders[2], hiders[3]]:
		_put_together(s, h)
		Game._do_tag(s, h)
	check(Game.winner_text.begins_with("Handers win"), "seekers win when everyone converted")
	check(not Game.last_winners.has(9), "spectator not credited")
	Net.players.erase(9)


func _play_cops_robbers() -> void:
	var cop: int = Game.ids_with(Game.Team.SEEKER, -1)[0]
	var robbers: Array = Game.ids_with(Game.Team.HIDER, -1)
	_put_together(cop, robbers[0])
	Game._do_tag(cop, robbers[0])
	check(Game.players[robbers[0]].status == Game.Status.JAILED, "robber jailed")
	check(Game.is_frozen(robbers[0]), "jailed robber frozen")
	# free them
	var jail: Vector3 = Game.arena.jail_position()
	Game.arena.get_player_node(robbers[0]).global_position = jail
	Game.arena.get_player_node(robbers[1]).global_position = jail + Vector3(1, 0, 0)
	Game._do_tag(robbers[1], robbers[0])
	check(Game.players[robbers[0]].status == Game.Status.ACTIVE, "robber freed by teammate")
	# immunity blocks immediate re-jail
	Game.arena.get_player_node(cop).global_position = jail + Vector3(0, 0, 1)
	Game._do_tag(cop, robbers[0])
	check(Game.players[robbers[0]].status == Game.Status.ACTIVE, "freed robber immune briefly")
	Game._immune_until.clear()
	for r in robbers:
		_put_together(cop, r)
		Game._do_tag(cop, r)
	check(Game.winner_text.begins_with("Cops win"), "cops win when all jailed")


func _play_manhunt() -> void:
	var ids: Array = Game.ids_with(-1, -1)
	check(Game.players[ids[0]].team == Game.Team.ALL, "everyone on team ALL")
	for i in range(1, ids.size()):
		_put_together(ids[0], ids[i])
		Game._do_tag(ids[0], ids[i])
		check(Game.players[ids[i]].status == Game.Status.OUT, "player %d out" % ids[i])
	check(Game.winner_text.ends_with("wins"), "last one standing wins")
