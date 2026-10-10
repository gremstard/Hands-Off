extends Node
## Proximity voice chat. Hold V to talk; your voice plays from your Hany on
## everyone else's game, so it fades with distance and hides behind walls
## like any other sound. Audio goes mic -> 16 kHz mono mu-law -> unreliable
## RPC -> AudioStreamGenerator on the speaker's player node.

const RATE := 16000
const CHUNK := 640 # 40 ms

var enabled := false
var talking := false
var _toggled := false
var _mic: AudioStreamPlayer
var _capture: AudioEffectCapture
var _bus_idx := -1
var _accum: PackedFloat32Array = PackedFloat32Array()
var _players: Dictionary = {} # peer_id -> AudioStreamPlayer3D


func _ready() -> void:
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		return
	_bus_idx = AudioServer.bus_count
	AudioServer.add_bus(_bus_idx)
	AudioServer.set_bus_name(_bus_idx, "Mic")
	AudioServer.set_bus_mute(_bus_idx, true)
	_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(_bus_idx, _capture)
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = "Mic"
	add_child(_mic)
	_mic.play()
	enabled = true


func _process(_delta: float) -> void:
	if not enabled or not Net.is_online():
		return
	var want: bool
	if Settings.talk_toggle:
		if Input.is_action_just_pressed("talk") and not Pause.is_open:
			_toggled = not _toggled
		want = _toggled and Game.arena != null
	else:
		want = Input.is_action_pressed("talk") and not Pause.is_open and Game.arena != null
	if want != talking:
		talking = want
		_capture.clear_buffer()
		_accum.clear()
	if not talking:
		return
	var avail := _capture.get_frames_available()
	if avail <= 0:
		return
	var buf := _capture.get_buffer(avail)
	var mix := AudioServer.get_mix_rate()
	var ratio := mix / float(RATE)
	# downsample by averaging windows
	var i := 0.0
	while i + ratio <= buf.size():
		var s := 0.0
		var n := 0
		var j := int(i)
		while j < int(i + ratio) and j < buf.size():
			s += (buf[j].x + buf[j].y) * 0.5
			n += 1
			j += 1
		_accum.append(s / maxf(n, 1))
		i += ratio
	while _accum.size() >= CHUNK:
		var chunk := _accum.slice(0, CHUNK)
		_accum = _accum.slice(CHUNK)
		send.rpc(_encode(chunk))


@rpc("any_peer", "unreliable")
func send(data: PackedByteArray) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0 or id == multiplayer.get_unique_id():
		return
	var p := _player_for(id)
	if p == null:
		return
	var pb: AudioStreamGeneratorPlayback = p.get_stream_playback()
	if pb == null:
		return
	var frames := _decode(data)
	for f in frames:
		if pb.get_frames_available() <= 0:
			break
		pb.push_frame(Vector2(f, f))


func _player_for(id: int) -> AudioStreamPlayer3D:
	if Game.arena == null:
		return null
	var node = Game.arena.get_player_node(id)
	if node == null:
		return null
	var p: AudioStreamPlayer3D = node.get_node_or_null("Voice")
	if p == null:
		p = AudioStreamPlayer3D.new()
		p.name = "Voice"
		var g := AudioStreamGenerator.new()
		g.mix_rate = RATE
		g.buffer_length = 0.3
		p.stream = g
		p.position.y = 1.5
		p.unit_size = 4.0
		p.max_distance = 30.0
		node.add_child(p)
		p.play()
	return p


# mu-law, 8 bits per sample
static func _encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size())
	for i in samples.size():
		var x := clampf(samples[i], -1.0, 1.0)
		var sign := 0 if x >= 0.0 else 0x80
		var mag := absf(x)
		var y := log(1.0 + 255.0 * mag) / log(256.0)
		out[i] = sign | int(y * 127.0)
	return out


static func _decode(data: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(data.size())
	for i in data.size():
		var b := data[i]
		var sign := -1.0 if (b & 0x80) != 0 else 1.0
		var y := float(b & 0x7F) / 127.0
		out[i] = sign * (pow(256.0, y) - 1.0) / 255.0
	return out
