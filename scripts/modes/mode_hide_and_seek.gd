class_name ModeHideAndSeek
extends GameMode
## Handers tag runners; tagged runners are out. Runners win on the clock.


func _init() -> void:
	headstart_seconds = 60.0 # Handers wait in jail; host can set 1-5 min
	round_seconds = 180.0


func display_name() -> String:
	return "Hide & Seek"


func describe() -> String:
	return "Runners get a head start. Handers tag runners to knock them out. Runners win if the clock runs out."


func can_tag(tagger: Dictionary, target: Dictionary) -> bool:
	return tagger.team == Game.Team.SEEKER and tagger.status == Game.Status.ACTIVE \
		and target.team == Game.Team.HIDER and target.status == Game.Status.ACTIVE


func on_tag(game: Node, tagger_id: int, target_id: int) -> void:
	game.players[target_id].status = Game.Status.OUT
	game.event("out", target_id)
	game.announce("%s got %s" % [game.players[tagger_id].name, game.players[target_id].name])


func check_winner(game: Node, timer_expired: bool) -> String:
	if game.count(Game.Team.HIDER, Game.Status.ACTIVE) == 0:
		return "Handers win"
	if timer_expired:
		return "Runners win"
	return ""


func winner_ids(game: Node) -> Array:
	if game.count(Game.Team.HIDER, Game.Status.ACTIVE) == 0:
		return _no_spectators(game, game.ids_with(Game.Team.SEEKER, -1))
	return _no_spectators(game, game.ids_with(Game.Team.HIDER, Game.Status.ACTIVE))
