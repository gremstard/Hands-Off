extends Node
## Game state autoload. The server is authoritative: it owns `players`,
## phase, timer and tag resolution. Clients mirror the state via RPC.

enum Mode { MANHUNT, HIDE_AND_SEEK, TAG, COPS_ROBBERS }
enum Team { ALL, HIDER, SEEKER }
enum Status { ACTIVE, OUT, JAILED }
enum Phase { LOBBY, HEADSTART, PLAYING, ENDED }

const ARENA_SCENE := "res://scenes/arena.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const END_DELAY := 8.0
const TAG_DISTANCE := 3.2 # server-side tolerance (client uses a tighter reach)
const TIME_SYNC_INTERVAL := 0.5
const WINS_FILE := "user://handsoff_wins.json"

signal state_changed
signal message(text: String)
signal game_over(text: String)
## Gameplay event for sound/vfx: kind is "tag", "out", "jailed", "freed",
## "converted", "start", "go", "end"; id is the affected peer or -1.
signal fx(kind: String, id: int)

var mode: Mode = Mode.HIDE_AND_SEEK
var phase: Phase = Phase.LOBBY
var time_left: float = 0.0
## peer_id -> { name: String, team: Team, status: Status }
var players: Dictionary = {}
var rules: GameMode = ModeHideAndSeek.new()
var arena: Node = null
var winner_text := ""
## Map chosen by the host (path) and its JSON, shipped to clients at round start.
var map_path := ""
var map_json := ""
var _map_cache: MapData = null
## Round wins per player name, kept by the host across rounds and saved to disk.
var wins: Dictionary = {}
var last_winners: Array = []
var _spawned := false

var _ready_peers: Dictionary = {}
var _immune_until: Dictionary = {} # server only: peer_id -> seconds (ticks)
var _sync_acc := 0.0


func _ready() -> void:
	_setup_input()
	rules = make_rules(mode)
	_load_wins()


func _load_wins() -> void:
	if FileAccess.file_exists(WINS_FILE):
		var f := FileAccess.open(WINS_FILE, FileAccess.READ)
		var data = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			wins = data


func _save_wins() -> void:
	var f := FileAccess.open(WINS_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(wins))


func wins_of(pname: String) -> int:
	return int(wins.get(pname, 0))


func _process(delta: float) -> void:
	if call_seconds_left > 0.0:
		call_seconds_left = maxf(0.0, call_seconds_left - delta)
	if phase == Phase.HEADSTART or phase == Phase.PLAYING:
		time_left = maxf(0.0, time_left - delta)
	ping_left = maxf(0.0, ping_left - delta)
	if not _is_server():
		return
	if phase == Phase.PLAYING and mode != Mode.MANHUNT:
		_next_ping -= delta
		if _next_ping <= 0.0:
			start_ping.rpc(PING_SECONDS)
			_next_ping = _ping_interval()
	if phase == Phase.HEADSTART or phase == Phase.PLAYING:
		_sync_acc += delta
		if _sync_acc >= TIME_SYNC_INTERVAL:
			_sync_acc = 0.0
			sync_time.rpc(time_left)
		if time_left <= 0.0:
			_timer_expired()


func _is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


static func make_rules(m: int) -> GameMode:
	var r: GameMode
	match m:
		Mode.MANHUNT:
			r = ModeManhunt.new()
		Mode.HIDE_AND_SEEK:
			r = ModeHideAndSeek.new()
		Mode.TAG:
			r = ModeTag.new()
		Mode.COPS_ROBBERS:
			r = ModeCopsRobbers.new()
		_:
			r = ModeHideAndSeek.new()
	var loop := Engine.get_main_loop()
	var g = loop.root.get_node_or_null("Game") if loop is SceneTree else null
	if g and g.headstart_override > 0.0 and m != Mode.MANHUNT:
		r.headstart_seconds = g.headstart_override
	if g and g.round_override > 0.0:
		r.round_seconds = g.round_override
	return r


static func mode_names() -> Array[String]:
	var out: Array[String] = []
	for m in Mode.values():
		out.append(make_rules(m).display_name())
	return out


func reset() -> void:
	phase = Phase.LOBBY
	players.clear()
	arena = null
	winner_text = ""
	time_left = 0.0
	_ready_peers.clear()
	_immune_until.clear()
	state_changed.emit()


# ---------------------------------------------------------------- queries

func me() -> Dictionary:
	if not multiplayer.has_multiplayer_peer():
		return {}
	return players.get(multiplayer.get_unique_id(), {})


func count(team: int, status: int) -> int:
	return ids_with(team, status).size()


## team / status of -1 means "any"
func ids_with(team: int, status: int) -> Array:
	var out := []
	for id in players:
		var p: Dictionary = players[id]
		if (team == -1 or p.team == team) and (status == -1 or p.status == status):
			out.append(id)
	return out


func names_with(team: int, status: int) -> String:
	var names := []
	for id in ids_with(team, status):
		names.append(players[id].name)
	return ", ".join(names)


## Tags only count once the head start is over (also the FFA grace period).
func tags_allowed() -> bool:
	return phase == Phase.PLAYING


## Host-chosen head start (Handers wait in jail); 0 = the mode's default.
var headstart_override := 0.0
## Host-chosen round length in seconds; 0 = the mode's default.
var round_override := 0.0
## Ping: every so often Handers see where every Runner is for a few seconds,
## with a siren over the whole map. More often towards the end of the round.
const PING_SECONDS := 5.0
var ping_left := 0.0
var _next_ping := 0.0


func is_frozen(id: int) -> bool:
	if not players.has(id):
		return true
	var p: Dictionary = players[id]
	if p.status == Status.JAILED:
		return true
	if phase == Phase.HEADSTART:
		return rules.is_frozen(p)
	return phase != Phase.PLAYING


func team_color(team: int) -> Color:
	return rules.team_color(team)


func team_label(team: int) -> String:
	return rules.team_label(team)


# ---------------------------------------------------------------- lobby

func current_map() -> MapData:
	if _map_cache == null:
		if map_json != "":
			_map_cache = MapData.from_json(map_json)
		else:
			_map_cache = MapData.default_map()
	return _map_cache


## Host picks a map (path to a .hom, or "" for the built-in default).
func set_map(path: String) -> void:
	if not _is_server() or phase != Phase.LOBBY:
		return
	map_path = path
	if path.ends_with(".glb"):
		map_json = ""
		_map_cache = null
		sync_map_name.rpc(path.get_file().get_basename())
		return
	var m: MapData = MapData.load_file(path) if path != "" else null
	map_json = m.to_json() if m else ""
	_map_cache = null
	sync_map_name.rpc(current_map().name)


@rpc("authority", "call_local", "reliable")
func sync_map_name(n: String) -> void:
	map_name_for_lobby = n
	state_changed.emit()

var map_name_for_lobby := "Blockyard"


func set_mode(m: int) -> void:
	if _is_server() and phase == Phase.LOBBY:
		sync_mode.rpc(m)


@rpc("authority", "call_local", "reliable")
func sync_mode(m: int) -> void:
	mode = m as Mode
	rules = make_rules(m)
	state_changed.emit()


func set_round_length(seconds: float) -> void:
	if _is_server() and phase == Phase.LOBBY:
		sync_round_length.rpc(seconds)


@rpc("authority", "call_local", "reliable")
func sync_round_length(seconds: float) -> void:
	round_override = seconds
	rules = make_rules(mode)
	state_changed.emit()


func set_headstart(seconds: float) -> void:
	if _is_server() and phase == Phase.LOBBY:
		sync_headstart.rpc(seconds)


@rpc("authority", "call_local", "reliable")
func sync_headstart(seconds: float) -> void:
	headstart_override = seconds
	rules = make_rules(mode)
	state_changed.emit()


## Seconds the lobby waits for Hander volunteers after Start is pressed.
const HANDER_CALL_SECONDS := 20.0
var call_deadline_msec := 0


## Host pressed Start: open the Hander call, then really start.
func start_game() -> void:
	if not _is_server() or phase != Phase.LOBBY:
		return
	if mode == Mode.MANHUNT or call_deadline_msec > 0:
		_start_round()
		return
	var needed := maxi(1, Net.players.size() / 4)
	if _volunteer_count() >= needed:
		_start_round()
		return
	call_deadline_msec = Time.get_ticks_msec() + int(HANDER_CALL_SECONDS * 1000)
	hander_call.rpc(HANDER_CALL_SECONDS)
	get_tree().create_timer(HANDER_CALL_SECONDS).timeout.connect(func() -> void:
		if phase == Phase.LOBBY and call_deadline_msec > 0:
			_start_round())


func _volunteer_count() -> int:
	var n := 0
	for id in Net.players:
		if Net.players[id].get("volunteer", false):
			n += 1
	return n


## Called by Net when a volunteer toggles: enough hands up ends the call early.
func volunteers_changed() -> void:
	if _is_server() and phase == Phase.LOBBY and call_deadline_msec > 0:
		if _volunteer_count() >= maxi(1, Net.players.size() / 4):
			_start_round()


var call_seconds_left := 0.0

@rpc("authority", "call_local", "reliable")
func hander_call(seconds: float) -> void:
	call_seconds_left = seconds
	state_changed.emit()


func _start_round() -> void:
	if not _is_server() or phase != Phase.LOBBY:
		return
	call_deadline_msec = 0
	call_seconds_left = 0.0
	var p := {}
	for id in Net.players:
		var entry: Dictionary = Net.players[id]
		p[id] = {"name": entry.name, "skin": entry.get("skin", Skins.DEFAULT), "team": Team.HIDER, "status": Status.ACTIVE,
			"volunteer": entry.get("volunteer", false), "volunteer_at": entry.get("volunteer_at", 0)}
	var r := make_rules(mode)
	r.assign_teams(p)
	for id in p:
		p[id].origin_team = p[id].team
		p[id].wins = wins_of(p[id].name)
	_ready_peers.clear()
	_immune_until.clear()
	_spawned = false
	last_winners = []
	load_arena.rpc(mode, p, map_json, map_path if map_path.ends_with(".glb") else "")


## Server: someone connected while a round is running. They join as a
## spectator (out, free-fly) and become a normal player next round.
func add_spectator(id: int, pname: String, skin: String) -> void:
	if not _is_server() or phase == Phase.LOBBY:
		return
	var team := Team.ALL if mode == Mode.MANHUNT else Team.HIDER
	players[id] = {"name": pname, "skin": skin, "team": team, "origin_team": team,
		"status": Status.OUT, "spectator": true, "wins": wins_of(pname)}
	sync_players.rpc(players)
	sync_wins.rpc_id(id, wins)
	load_arena.rpc_id(id, mode, players, map_json, map_path if map_path.ends_with(".glb") else "")
	# load_arena resets their phase to HEADSTART; the real phase follows once
	# they report the arena ready (see _peer_ready).


@rpc("authority", "call_local", "reliable")
func load_arena(m: int, p: Dictionary, mjson: String = "", glb: String = "") -> void:
	map_json = mjson
	map_path = glb
	_map_cache = null
	mode = m as Mode
	rules = make_rules(m)
	players = p
	phase = Phase.HEADSTART
	time_left = rules.headstart_seconds
	winner_text = ""
	arena = null
	get_tree().change_scene_to_file(ARENA_SCENE)
	state_changed.emit()


## Called by the arena scene once it has built itself.
func arena_ready(a: Node) -> void:
	arena = a
	if _is_server():
		_peer_ready(1)
	else:
		report_ready.rpc_id(1)


@rpc("any_peer", "reliable")
func report_ready() -> void:
	if _is_server():
		_peer_ready(multiplayer.get_remote_sender_id())


func _peer_ready(id: int) -> void:
	if _spawned:
		# late joiner: everyone adds their node, they add everyone's
		spawn_all.rpc(players)
		set_phase.rpc_id(id, phase, time_left)
		if phase == Phase.ENDED:
			end_game.rpc_id(id, winner_text)
		return
	_ready_peers[id] = true
	_check_all_ready()


func _check_all_ready() -> void:
	if phase != Phase.HEADSTART or arena == null:
		return
	for pid in players:
		if not _ready_peers.has(pid):
			return
	_ready_peers.clear()
	_spawned = true
	spawn_all.rpc(players)
	set_phase.rpc(Phase.HEADSTART, rules.headstart_seconds)
	broadcast_message.rpc(rules.start_message())
	broadcast_fx.rpc("start", -1)


# ---------------------------------------------------------------- in game

@rpc("authority", "call_local", "reliable")
func spawn_all(p: Dictionary) -> void:
	players = p
	if arena:
		arena.spawn_players(p)
	state_changed.emit()


@rpc("authority", "call_local", "reliable")
func set_phase(ph: int, t: float) -> void:
	phase = ph as Phase
	time_left = t
	if phase == Phase.PLAYING:
		_next_ping = _ping_interval()
	state_changed.emit()


## Pings every minute, every 30 s in the last quarter, every 15 s in the last tenth.
func _ping_interval() -> float:
	var frac := time_left / maxf(rules.round_seconds, 1.0)
	if frac < 0.1:
		return 15.0
	if frac < 0.25:
		return 30.0
	return 60.0


@rpc("authority", "call_local", "reliable")
func start_ping(seconds: float) -> void:
	ping_left = seconds
	fx.emit("ping", -1)
	message.emit("PING")


@rpc("authority", "unreliable")
func sync_time(t: float) -> void:
	time_left = t


@rpc("authority", "call_local", "reliable")
func broadcast_message(t: String) -> void:
	message.emit(t)


@rpc("authority", "call_local", "reliable")
func broadcast_fx(kind: String, id: int) -> void:
	fx.emit(kind, id)


@rpc("authority", "call_local", "reliable")
func sync_players(p: Dictionary) -> void:
	players = p
	state_changed.emit()


@rpc("authority", "call_local", "reliable")
func teleport_player(id: int, pos: Vector3) -> void:
	if arena:
		var n = arena.get_player_node(id)
		if n:
			n.teleport(pos)


@rpc("authority", "call_local", "reliable")
func remove_player(id: int) -> void:
	players.erase(id)
	if arena:
		arena.remove_player(id)
	state_changed.emit()


## Client entry point for tagging.
func try_tag(target_id: int) -> void:
	if _is_server():
		_do_tag(1, target_id)
	else:
		request_tag.rpc_id(1, target_id)


## Fell off the map: out of the round (jailed in Cops & Robbers).
func report_fall() -> void:
	if _is_server():
		_fell(1)
	else:
		request_fall.rpc_id(1)


@rpc("any_peer", "reliable")
func request_fall() -> void:
	if _is_server():
		_fell(multiplayer.get_remote_sender_id())


func _fell(id: int) -> void:
	if phase == Phase.LOBBY or not players.has(id):
		return
	var p: Dictionary = players[id]
	if p.status != Status.ACTIVE:
		return
	if mode == Mode.COPS_ROBBERS and p.team == Team.HIDER:
		p.status = Status.JAILED
		jail(id)
		broadcast_fx.rpc("jailed", id)
		announce("%s fell off the map - straight to jail!" % p.name)
	else:
		p.status = Status.OUT
		broadcast_fx.rpc("out", id)
		announce("%s fell off the map!" % p.name)
	sync_players.rpc(players)
	_check_winner(false)


@rpc("any_peer", "reliable")
func request_tag(target_id: int) -> void:
	if not _is_server():
		return
	_do_tag(multiplayer.get_remote_sender_id(), target_id)


func _do_tag(tagger_id: int, target_id: int) -> void:
	if phase != Phase.PLAYING or tagger_id == target_id:
		return
	if not players.has(tagger_id) or not players.has(target_id):
		return
	if _now() < float(_immune_until.get(target_id, 0.0)):
		return
	if not rules.can_tag(players[tagger_id], players[target_id]):
		return
	if arena:
		var a = arena.get_player_node(tagger_id)
		var b = arena.get_player_node(target_id)
		if a == null or b == null:
			return
		if a.global_position.distance_to(b.global_position) > TAG_DISTANCE:
			return
	broadcast_fx.rpc("tag", target_id)
	rules.on_tag(self, tagger_id, target_id)
	sync_players.rpc(players)
	_check_winner(false)


# -- helpers used by rules (server side)

func announce(text: String) -> void:
	broadcast_message.rpc(text)


func event(kind: String, id: int = -1) -> void:
	broadcast_fx.rpc(kind, id)


func give_immunity(id: int, seconds: float) -> void:
	_immune_until[id] = _now() + seconds


func jail(id: int) -> void:
	if arena:
		teleport_player.rpc(id, arena.jail_position())


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---------------------------------------------------------------- flow

func _timer_expired() -> void:
	if phase == Phase.HEADSTART:
		set_phase.rpc(Phase.PLAYING, rules.round_seconds)
		broadcast_message.rpc(rules.go_message())
		broadcast_fx.rpc("go", -1)
	elif phase == Phase.PLAYING:
		_check_winner(true)


func _check_winner(timer_expired: bool) -> void:
	if phase != Phase.PLAYING:
		return
	if players.size() < 2 and not timer_expired:
		return # solo testing: never end on a tag
	var w := rules.check_winner(self, timer_expired)
	if w == "" and timer_expired:
		w = "Time's up!"
	if w != "":
		_end_game(w)


func _end_game(text: String) -> void:
	last_winners = rules.winner_ids(self)
	for id in last_winners:
		if players.has(id):
			var n: String = players[id].name
			wins[n] = wins_of(n) + 1
			players[id].wins = wins[n]
	_save_wins()
	sync_wins.rpc(wins)
	sync_players.rpc(players)
	sync_last_winners.rpc(last_winners)
	end_game.rpc(text)
	broadcast_fx.rpc("end", -1)
	get_tree().create_timer(END_DELAY).timeout.connect(func() -> void:
		if phase == Phase.ENDED and _is_server():
			return_to_lobby.rpc())


@rpc("authority", "call_local", "reliable")
func sync_last_winners(ids: Array) -> void:
	last_winners = ids


@rpc("authority", "call_local", "reliable")
func sync_wins(w: Dictionary) -> void:
	wins = w
	state_changed.emit()


func is_spectator(id: int) -> bool:
	return players.has(id) and players[id].get("spectator", false)


## Names + totals of the players who won the last round, for the end screen.
func winners_text() -> String:
	var parts := []
	for id in last_winners:
		if players.has(id):
			parts.append("%s (%d)" % [players[id].name, int(players[id].get("wins", 0))])
	return ", ".join(parts)


@rpc("authority", "call_local", "reliable")
func end_game(text: String) -> void:
	phase = Phase.ENDED
	winner_text = text
	state_changed.emit()
	game_over.emit(text)


@rpc("authority", "call_local", "reliable")
func return_to_lobby() -> void:
	phase = Phase.LOBBY
	_spawned = false
	call_deadline_msec = 0
	call_seconds_left = 0.0
	players.clear()
	arena = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(LOBBY_SCENE)
	state_changed.emit()


## Server: a peer dropped.
func on_player_left(id: int) -> void:
	if not players.has(id):
		return
	_ready_peers.erase(id)
	remove_player.rpc(id)
	if phase == Phase.HEADSTART:
		_check_all_ready()
	elif phase == Phase.PLAYING:
		_check_winner(false)


# ---------------------------------------------------------------- input map
# Bindings live in the Settings autoload (user-rebindable). Nothing to do here.
func _setup_input() -> void:
	pass
