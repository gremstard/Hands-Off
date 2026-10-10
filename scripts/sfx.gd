extends Node
## Sound autoload. Hooks UI buttons automatically and plays gameplay
## events from Game.fx. All clips are Kenney (CC0).

## Drop-in sound files (see CREDITS.md). When present they replace the
## built-in versions: breath.ogg (loop), siren.ogg (loop), tag.ogg.
const BREATH_FILE := "res://assets/audio/sfx/breath.ogg"
const SIREN_FILE := "res://assets/audio/sfx/siren.ogg"
const TAG_FILE := "res://assets/audio/sfx/tag.ogg"
const UI := "res://assets/audio/ui/"
const SFX := "res://assets/audio/sfx/"

const BANK := {
	"ui_click": ["click_001.ogg", "click_002.ogg", "click_003.ogg"],
	"ui_hover": ["rollover1.ogg", "rollover2.ogg", "rollover3.ogg"],
	"ui_confirm": ["confirmation_001.ogg"],
	"ui_back": ["back_001.ogg"],
	"ui_error": ["error_001.ogg"],
	"ui_tick": ["tick_001.ogg"],
	"tag": ["impactPunch_medium_000.ogg", "impactPunch_medium_001.ogg", "impactPunch_medium_002.ogg", "impactPunch_medium_003.ogg"],
	"out": ["lowDown.ogg"],
	"jailed": ["doorClose_1.ogg", "metalLatch.ogg"],
	"freed": ["powerUp1.ogg", "doorOpen_1.ogg"],
	"converted": ["phaserUp1.ogg"],
	"start": ["threeTone1.ogg"],
	"go": ["highUp.ogg"],
	"end": ["twoTone1.ogg"],
	"jump": ["cloth1.ogg", "cloth2.ogg"],
	"roll": ["cloth2.ogg", "cloth1.ogg"],
	"gasp": ["highUp.ogg"],
	"step_concrete": ["footstep_concrete_000.ogg", "footstep_concrete_001.ogg", "footstep_concrete_002.ogg", "footstep_concrete_003.ogg", "footstep_concrete_004.ogg"],
	"step_grass": ["footstep_grass_000.ogg", "footstep_grass_001.ogg", "footstep_grass_002.ogg", "footstep_grass_003.ogg", "footstep_grass_004.ogg"],
	"step_wood": ["footstep_wood_000.ogg", "footstep_wood_001.ogg", "footstep_wood_002.ogg", "footstep_wood_003.ogg", "footstep_wood_004.ogg"],
	"step_metal": ["metalClick.ogg", "footstep_concrete_001.ogg", "footstep_concrete_003.ogg"],
	"step_dirt": ["footstep00.ogg", "footstep01.ogg", "footstep02.ogg", "footstep03.ogg", "footstep04.ogg"],
	"land_concrete": ["impactSoft_medium_000.ogg", "impactSoft_medium_001.ogg"],
	"land_grass": ["impactSoft_medium_001.ogg", "impactSoft_medium_002.ogg"],
	"land_wood": ["impactSoft_heavy_000.ogg", "impactSoft_heavy_001.ogg"],
	"land_metal": ["impactMetal_heavy_000.ogg", "impactMetal_heavy_001.ogg"],
	"land_dirt": ["impactSoft_medium_002.ogg", "impactSoft_heavy_002.ogg"],
}

var _streams: Dictionary = {}
var _ui_players: Array[AudioStreamPlayer] = []
var _ui_i := 0
var _last_tick := -1


func _ready() -> void:
	for k in BANK:
		var arr: Array[AudioStream] = []
		for f in BANK[k]:
			var dir := UI if k.begins_with("ui_") else SFX
			var st: AudioStream = load(dir + f)
			if st:
				arr.append(st)
		_streams[k] = arr
	if ResourceLoader.exists(TAG_FILE):
		_streams["tag"] = [load(TAG_FILE)]
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_ui_players.append(p)
	get_tree().node_added.connect(_on_node_added)
	Game.fx.connect(_on_fx)


func _process(_delta: float) -> void:
	_siren_fill(_delta)
	# countdown ticks in the last seconds of head start
	if Game.phase == Game.Phase.HEADSTART and Game.time_left <= 3.5:
		var t := int(ceil(Game.time_left))
		if t != _last_tick and t > 0:
			_last_tick = t
			play("ui_tick")
	else:
		_last_tick = -1


## 2D (non-positional) sound.
func play(kind: String, volume_db: float = 0.0, pitch_jitter: float = 0.08) -> void:
	var st := _pick(kind)
	if st == null:
		return
	var p := _ui_players[_ui_i % _ui_players.size()]
	_ui_i += 1
	p.stream = st
	p.volume_db = volume_db
	p.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.play()


## Positional sound at a world position; the player is freed when done.
func play_at(kind: String, pos: Vector3, volume_db: float = 0.0) -> void:
	var st := _pick(kind)
	if st == null or get_tree().current_scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.volume_db = volume_db
	p.unit_size = 6.0
	p.max_distance = 60.0
	p.pitch_scale = randf_range(0.92, 1.08)
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _pick(kind: String) -> AudioStream:
	var arr: Array = _streams.get(kind, [])
	if arr.is_empty():
		return null
	return arr[randi() % arr.size()]


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		n.pressed.connect(func() -> void: play("ui_click"))
		n.mouse_entered.connect(func() -> void: play("ui_hover", -8.0))


var _siren: AudioStreamPlayer
var _siren_gen: AudioStreamGenerator
var _siren_t := 0.0
var _siren_phase := 0.0


## Rising-falling siren heard across the whole map during a ping.
func siren(seconds: float) -> void:
	if _siren == null:
		_siren = AudioStreamPlayer.new()
		if ResourceLoader.exists(SIREN_FILE):
			_siren.stream = load(SIREN_FILE)
		else:
			_siren_gen = AudioStreamGenerator.new()
			_siren_gen.mix_rate = 22050
			_siren_gen.buffer_length = 0.2
			_siren.stream = _siren_gen
		_siren.volume_db = -10.0
		add_child(_siren)
	_siren_t = seconds
	if not _siren.playing:
		_siren.play()


static func breath_stream() -> AudioStream:
	return load(BREATH_FILE) if ResourceLoader.exists(BREATH_FILE) else null


func _siren_fill(delta: float) -> void:
	if _siren == null or _siren_t <= 0.0:
		if _siren and _siren.playing and _siren_t <= 0.0:
			_siren.stop()
		return
	_siren_t -= delta
	if _siren_gen == null:
		return # real siren file is playing
	var pb: AudioStreamGeneratorPlayback = _siren.get_stream_playback()
	if pb == null:
		return
	var rate := _siren_gen.mix_rate
	for i in pb.get_frames_available():
		var tsec := Time.get_ticks_msec() / 1000.0
		var f := 520.0 + 300.0 * (0.5 + 0.5 * sin(tsec * TAU * 0.6))
		_siren_phase += f / rate
		var v := sin(_siren_phase * TAU) * 0.35
		pb.push_frame(Vector2(v, v))


func _on_fx(kind: String, id: int) -> void:
	var pos := Vector3.ZERO
	var positional := false
	if id > 0 and Game.arena:
		var n = Game.arena.get_player_node(id)
		if n:
			pos = n.global_position
			positional = true
	match kind:
		"tag":
			if positional:
				play_at("tag", pos, 2.0)
			else:
				play("tag")
		"out", "jailed", "freed", "converted":
			if positional:
				play_at(kind, pos)
			else:
				play(kind)
			if id == multiplayer.get_unique_id():
				play(kind, -4.0) # make sure the victim hears it clearly
		"start", "go", "end":
			play(kind)
		"ping":
			siren(Game.PING_SECONDS)
