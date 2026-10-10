class_name ModeCopsRobbers
extends GameMode
## Cops jail robbers. Robbers free jailed teammates by tagging them.

const FREED_IMMUNITY := 3.0


func _init() -> void:
	headstart_seconds = 60.0 # Handers wait in jail; host can set 1-5 min
	round_seconds = 240.0


func display_name() -> String:
	return "Cops & Robbers"


func describe() -> String:
	return "Cops tag robbers to send them to jail. Robbers tag jailed friends to free them. Cops win when every robber is locked up."


func start_message() -> String:
	return "Run."


func go_message() -> String:
	return "Cops out."


func can_tag(tagger: Dictionary, target: Dictionary) -> bool:
	if tagger.status != Game.Status.ACTIVE:
		return false
	if tagger.team == Game.Team.SEEKER:
		return target.team == Game.Team.HIDER and target.status == Game.Status.ACTIVE
	if tagger.team == Game.Team.HIDER:
		return target.team == Game.Team.HIDER and target.status == Game.Status.JAILED
	return false


func on_tag(game: Node, tagger_id: int, target_id: int) -> void:
	var target: Dictionary = game.players[target_id]
	var tn: String = game.players[tagger_id].name
	if target.status == Game.Status.JAILED:
		target.status = Game.Status.ACTIVE
		game.give_immunity(target_id, FREED_IMMUNITY)
		game.event("freed", target_id)
		game.announce("%s freed %s" % [tn, target.name])
	else:
		target.status = Game.Status.JAILED
		game.jail(target_id)
		game.event("jailed", target_id)
		game.announce("%s jailed %s" % [tn, target.name])


func check_winner(game: Node, timer_expired: bool) -> String:
	if game.count(Game.Team.HIDER, Game.Status.ACTIVE) == 0 and game.count(Game.Team.HIDER, Game.Status.JAILED) > 0:
		return "Cops win"
	if timer_expired:
		return "Robbers win"
	return ""


func scoreboard(game: Node) -> String:
	return "Robbers free: %d   Jailed: %d   Cops: %d" % [
		game.count(Game.Team.HIDER, Game.Status.ACTIVE),
		game.count(Game.Team.HIDER, Game.Status.JAILED),
		game.count(Game.Team.SEEKER, -1)]


func team_label(team: int) -> String:
	match team:
		Game.Team.HIDER:
			return "Robber"
		Game.Team.SEEKER:
			return "Cop"
	return "Player"


func team_color(team: int) -> Color:
	match team:
		Game.Team.HIDER:
			return Color(0.25, 0.85, 0.35)
		Game.Team.SEEKER:
			return Color(0.25, 0.45, 0.95)
	return Color.WHITE


func winner_ids(game: Node) -> Array:
	if game.count(Game.Team.HIDER, Game.Status.ACTIVE) == 0 and game.count(Game.Team.HIDER, Game.Status.JAILED) > 0:
		return _no_spectators(game, game.ids_with(Game.Team.SEEKER, -1))
	return _no_spectators(game, game.ids_with(Game.Team.HIDER, -1))
