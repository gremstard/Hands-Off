class_name GameMode
extends RefCounted
## Base class for a game mode. Subclasses decide team assignment, who may
## tag whom, what a tag does, and when the round ends. All of this runs on
## the server; clients only use the label/colour helpers.

var headstart_seconds: float = 10.0
var round_seconds: float = 180.0


func display_name() -> String:
	return "Mode"


func describe() -> String:
	return ""


func start_message() -> String:
	return "Run."


func go_message() -> String:
	return "Handers out."


func assign_teams(players: Dictionary) -> void:
	pick_seekers(players)


## Who stays frozen during the head-start phase.
func is_frozen(player: Dictionary) -> bool:
	return player.team == Game.Team.SEEKER


func can_tag(_tagger: Dictionary, _target: Dictionary) -> bool:
	return false


func on_tag(_game: Node, _tagger_id: int, _target_id: int) -> void:
	pass


## Return "" while the round continues, otherwise the end-of-round text.
func check_winner(_game: Node, _timer_expired: bool) -> String:
	return ""


## Peer ids credited with the win when the round ends (after check_winner
## returned text). Spectators are never credited.
func winner_ids(game: Node) -> Array:
	return []


func _no_spectators(game: Node, ids: Array) -> Array:
	var out := []
	for id in ids:
		if not game.players[id].get("spectator", false):
			out.append(id)
	return out


## One-line team summary for the HUD.
func scoreboard(game: Node) -> String:
	return "%ss: %d   %ss: %d" % [
		team_label(Game.Team.HIDER), game.count(Game.Team.HIDER, Game.Status.ACTIVE),
		team_label(Game.Team.SEEKER), game.count(Game.Team.SEEKER, Game.Status.ACTIVE)]


## HUD text for the local player during head start.
func headstart_text(player: Dictionary) -> String:
	if is_frozen(player):
		return "Jailed"
	return "Hide"


func team_label(team: int) -> String:
	match team:
		Game.Team.HIDER:
			return "Runner"
		Game.Team.SEEKER:
			return "Hander"
	return "Runner"


func team_color(team: int) -> Color:
	match team:
		Game.Team.HIDER:
			return Color(0.25, 0.85, 0.35)
		Game.Team.SEEKER:
			return Color(0.9, 0.25, 0.25)
	return Color(0.95, 0.8, 0.2)


## Everyone becomes a hider, then roughly one in four becomes a seeker.
func pick_seekers(players: Dictionary) -> void:
	var ids := players.keys()
	ids.sort()
	for id in ids:
		players[id].team = Game.Team.HIDER
		players[id].status = Game.Status.ACTIVE
	if ids.size() < 2:
		return
	var n := maxi(1, ids.size() / 4)
	# volunteers first (earliest first), then random fill
	var vols := ids.filter(func(id): return players[id].get("volunteer", false))
	vols.sort_custom(func(a, b): return players[a].get("volunteer_at", 0) < players[b].get("volunteer_at", 0))
	var rest := ids.filter(func(id): return not players[id].get("volunteer", false))
	rest.shuffle()
	var order := vols + rest
	for i in n:
		players[order[i]].team = Game.Team.SEEKER
