extends CanvasLayer
## In-game overlay: timer, role, team counts, announcements, controls.

var timer_label: Label
var phase_label: Label
var role_label: Label
var score_label: Label
var msg_label: Label
var end_label: Label
var hint_label: Label
var _msg_tween: Tween
var _ping_layer: Control


func _ready() -> void:
	var font_big := 44
	# Top centre: timer + phase
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.offset_top = 12
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(top)
	timer_label = _label(font_big)
	timer_label.theme_type_variation = "Title"
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(timer_label)
	phase_label = _label(20)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(phase_label)

	# Top left: role + scoreboard
	var left := VBoxContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	left.offset_left = 16
	left.offset_top = 12
	add_child(left)
	role_label = _label(26)
	left.add_child(role_label)
	score_label = _label(18)
	left.add_child(score_label)

	# Centre: announcement + end screen
	msg_label = _label(30)
	msg_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	msg_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	msg_label.position.y -= 120
	msg_label.modulate.a = 0.0
	add_child(msg_label)

	end_label = _label(56)
	end_label.theme_type_variation = "Title"
	end_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	end_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	end_label.visible = false
	add_child(end_label)

	# Bottom: controls with key prompt icons
	var hints := HBoxContainer.new()
	hints.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hints.offset_bottom = -10
	hints.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hints.alignment = BoxContainer.ALIGNMENT_CENTER
	hints.add_theme_constant_override("separation", 18)
	hints.modulate.a = 0.85
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hints)
	_hint(hints, ["keyboard_w", "keyboard_a", "keyboard_s", "keyboard_d"], "move")
	_hint(hints, ["keyboard_shift"], "sprint")
	_hint(hints, ["keyboard_space"], "jump")
	_hint(hints, ["mouse_left", "keyboard_e"], "tag")
	_hint(hints, ["keyboard_c"], "crouch")
	_hint(hints, ["keyboard_v"], "roll")
	_hint(hints, ["keyboard_f"], "wall stick")
	_hint(hints, ["keyboard_r"], "hold breath")
	_hint(hints, ["keyboard_x"], "talk")
	_hint(hints, ["keyboard_alt"], "orbit cam")
	_hint(hints, ["keyboard_tab"], "menu")
	hint_label = _label(15)
	hint_label.visible = false
	add_child(hint_label)

	# Crosshair
	var cross := TextureRect.new()
	cross.texture = load("res://assets/icons/crosshair/crosshair-005.png")
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.custom_minimum_size = Vector2(28, 28)
	cross.size = Vector2(28, 28)
	cross.position = Vector2(-14, -14)
	cross.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cross.stretch_mode = TextureRect.STRETCH_SCALE
	cross.modulate = Color(1, 1, 1, 0.85)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cross)

	_ping_layer = Control.new()
	_ping_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ping_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ping_layer.draw.connect(_draw_pings)
	add_child(_ping_layer)
	Game.message.connect(_on_message)
	Game.game_over.connect(_on_game_over)
	Game.state_changed.connect(_update)
	_update()


func _hint(parent: Control, keys: Array, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in keys:
		var tr := TextureRect.new()
		tr.texture = load("res://assets/icons/prompts/%s_outline.png" % k)
		tr.custom_minimum_size = Vector2(30, 30)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tr)
	var l := _label(15)
	l.text = " " + text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	parent.add_child(row)


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(_delta: float) -> void:
	timer_label.text = _fmt(Game.time_left)
	_ping_layer.queue_redraw()


## Handers see a circle on every Runner during a ping: bigger when closer.
func _draw_pings() -> void:
	if Game.ping_left <= 0.0 or Game.arena == null:
		return
	var me := Game.me()
	if me.is_empty() or me.team != Game.Team.SEEKER:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var fade := clampf(Game.ping_left / 1.0, 0.0, 1.0)
	for id in Game.ids_with(Game.Team.HIDER, Game.Status.ACTIVE):
		var n = Game.arena.get_player_node(id)
		if n == null:
			continue
		var p: Vector3 = n.global_position + Vector3(0, 1.0, 0)
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		var d := cam.global_position.distance_to(p)
		var r := clampf(420.0 / maxf(d, 1.0), 10.0, 90.0)
		var pulse := 1.0 + 0.08 * sin(Time.get_ticks_msec() / 90.0)
		_ping_layer.draw_arc(sp, r * pulse, 0, TAU, 48, Color(1, 0.25, 0.25, 0.9 * fade), 3.0)
		_ping_layer.draw_arc(sp, r * pulse * 0.6, 0, TAU, 32, Color(1, 0.6, 0.3, 0.6 * fade), 2.0)
		_ping_layer.draw_string(ThemeDB.fallback_font, sp + Vector2(-20, -r * pulse - 6), "%dm" % int(d), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.8, 0.8, fade))


func _fmt(t: float) -> String:
	var s := int(ceil(t))
	return "%d:%02d" % [s / 60, s % 60]


func _update() -> void:
	var me := Game.me()
	var rules := Game.rules
	match Game.phase:
		Game.Phase.HEADSTART:
			phase_label.text = rules.headstart_text(me) if not me.is_empty() else "Get ready"
		Game.Phase.PLAYING:
			phase_label.text = rules.display_name()
		Game.Phase.ENDED:
			phase_label.text = "Round over"
		_:
			phase_label.text = ""
	if me.is_empty():
		role_label.text = ""
	else:
		var color := Game.team_color(me.team)
		match me.status:
			Game.Status.OUT:
				if me.get("spectator", false):
					role_label.text = "Spectating"
				else:
					role_label.text = "Out"
				color = Color(0.8, 0.8, 0.8)
			Game.Status.JAILED:
				role_label.text = "Jailed"
				color = Color(0.7, 0.7, 0.75)
			_:
				role_label.text = Game.team_label(me.team).to_upper()
		role_label.add_theme_color_override("font_color", color)
	score_label.text = rules.scoreboard(Game)


func _on_message(text: String) -> void:
	msg_label.text = text
	msg_label.modulate.a = 1.0
	if _msg_tween:
		_msg_tween.kill()
	_msg_tween = create_tween()
	_msg_tween.tween_interval(2.5)
	_msg_tween.tween_property(msg_label, "modulate:a", 0.0, 1.0)


func _on_game_over(text: String) -> void:
	var w := Game.winners_text()
	end_label.text = text + ("\n" + w if w != "" else "")
	end_label.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
