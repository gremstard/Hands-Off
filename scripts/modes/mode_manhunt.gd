class_name ModeManhunt
extends GameMode
## Everyone is both tagger and runner. Get tagged and you're out.


func _init() -> void:
	headstart_seconds = 90.0 # grace period: everyone runs, nobody can tag yet
	round_seconds = 300.0


func display_name() -> String:
	return "Manhunt (Free-for-all)"


func describe() -> String:
	return "Everyone can tag everyone. Get tagged and you're out. Last one standing wins."


func start_message() -> String:
	return "Scatter."


func go_message() -> String:
	return "Go."


func assign_teams(players: Dictionary) -> void:
	for id in players:
		players[id].team = Game.Team.ALL
		players[id].status = Game.Status.ACTIVE


func is_frozen(_player: Dictionary) -> bool:
	return false # free movement during the grace period


func headstart_text(_player: Dictionary) -> String:
	return "Grace"


func can_tag(tagger: Dictionary, target: Dictionary) -> bool:
	return tagger.status == Game.Status.ACTIVE and target.status == Game.Status.ACTIVE


func on_tag(game: Node, tagger_id: int, target_id: int) -> void:
	game.players[target_id].status = Game.Status.OUT
	game.event("out", target_id)
	game.announce("%s got %s" % [game.players[tagger_id].name, game.players[target_id].name])


func check_winner(game: Node, timer_expired: bool) -> String:
	var alive: Array = game.ids_with(-1, Game.Status.ACTIVE)
	if alive.size() == 0:
		return "Draw"
	if alive.size() == 1 and game.players.size() >= 2:
		return "%s wins" % game.players[alive[0]].name
	if timer_expired:
		return "Time. " + game.names_with(-1, Game.Status.ACTIVE)
	return ""


func scoreboard(game: Node) -> String:
	return "Still in: %d / %d" % [game.count(-1, Game.Status.ACTIVE), game.players.size()]


func team_label(_team: int) -> String:
	return "Everyone"


func winner_ids(game: Node) -> Array:
	return _no_spectators(game, game.ids_with(-1, Game.Status.ACTIVE))
