extends Node
## Networking autoload. ENet (UDP) - works on LAN directly and over the
## internet through a UDP tunnel like Playit.gg. Swap for EOS later.

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 16

signal joined
signal join_failed(reason: String)
signal left_server
signal players_changed

var player_name := "Player"
var skin := Skins.DEFAULT
## peer_id -> {name, skin} (lobby roster, server authoritative)
var players: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func is_online() -> bool:
	return multiplayer.has_multiplayer_peer()


func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players.clear()
	players[1] = {"name": player_name, "skin": skin, "volunteer": false, "volunteer_at": 0}
	players_changed.emit()
	return OK


## address may be "ip", "ip:port", or a hostname like "xyz.playit.gg:12345"
func join(address: String) -> Error:
	var host_part := address.strip_edges()
	var port := DEFAULT_PORT
	var idx := host_part.rfind(":")
	if idx > 0 and host_part.substr(idx + 1).is_valid_int():
		port = int(host_part.substr(idx + 1))
		host_part = host_part.substr(0, idx)
	if host_part.is_empty():
		host_part = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host_part, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	Game.reset()
	players_changed.emit()
	left_server.emit()


func local_ips() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.begins_with("192.168.") or s.begins_with("10.") or s.begins_with("172."):
			out.append(s)
	return out


# ---------------------------------------------------------------- callbacks

func _on_peer_connected(_id: int) -> void:
	pass # client registers itself once connected_to_server fires


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	players.erase(id)
	sync_players.rpc(players)
	players_changed.emit()
	Game.on_player_left(id)


func _on_connected_to_server() -> void:
	register_player.rpc_id(1, player_name, skin)
	joined.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	join_failed.emit("Could not connect. Check the address and that the host is running.")


func _on_server_disconnected() -> void:
	leave()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ---------------------------------------------------------------- rpcs

@rpc("any_peer", "reliable")
func register_player(pname: String, pskin: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var clean := pname.strip_edges().substr(0, 16)
	var final_name := clean if clean != "" else "Player %d" % id
	# avoid two players sharing a name (wins are tracked by name)
	var taken := []
	for pid in players:
		taken.append(players[pid].name)
	var base := final_name
	var k := 2
	while taken.has(final_name):
		final_name = "%s %d" % [base, k]
		k += 1
	players[id] = {"name": final_name, "skin": Skins.valid(pskin), "volunteer": false, "volunteer_at": 0}
	sync_players.rpc(players)
	Game.sync_wins.rpc_id(id, Game.wins)
	if Game.phase != Game.Phase.LOBBY:
		# Round in progress: join as a spectator, play from the next round.
		Game.add_spectator(id, final_name, Skins.valid(pskin))
	Game.sync_mode.rpc_id(id, Game.mode)
	Game.sync_headstart.rpc_id(id, Game.headstart_override)
	Game.sync_round_length.rpc_id(id, Game.round_override)
	players_changed.emit()


## Put your hand up to be a Hander next round. Earliest volunteers go first.
func set_volunteer(on: bool) -> void:
	if is_host():
		_set_volunteer(1, on)
	elif is_online():
		rpc_set_volunteer.rpc_id(1, on)


@rpc("any_peer", "reliable")
func rpc_set_volunteer(on: bool) -> void:
	if is_host():
		_set_volunteer(multiplayer.get_remote_sender_id(), on)


func _set_volunteer(id: int, on: bool) -> void:
	if players.has(id):
		players[id].volunteer = on
		players[id].volunteer_at = Time.get_ticks_msec() if on else 0
		sync_players.rpc(players)
		players_changed.emit()
		Game.volunteers_changed()


## Change your own skin while in the lobby.
func choose_skin(new_skin: String) -> void:
	skin = Skins.valid(new_skin)
	if is_host():
		_set_skin(1, skin)
	elif is_online():
		set_skin.rpc_id(1, skin)


@rpc("any_peer", "reliable")
func set_skin(new_skin: String) -> void:
	if is_host():
		_set_skin(multiplayer.get_remote_sender_id(), new_skin)


func _set_skin(id: int, new_skin: String) -> void:
	if players.has(id) and Game.phase == Game.Phase.LOBBY:
		players[id].skin = Skins.valid(new_skin)
		sync_players.rpc(players)
		players_changed.emit()


@rpc("authority", "reliable")
func sync_players(p: Dictionary) -> void:
	players = p
	players_changed.emit()


@rpc("authority", "reliable")
func kick(reason: String) -> void:
	leave()
	join_failed.emit(reason)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
