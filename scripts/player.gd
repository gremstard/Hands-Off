extends CharacterBody3D
## Hany. The owning peer runs input and physics; position, rotation and a
## small state bitfield replicate to everyone, who then render animation,
## footsteps and breathing locally from that state.

# ---- tuning
const WALK_SPEED := 6.0
const SPRINT_SPEED := 9.5
const CROUCH_SPEED := 3.0
const JUMP_VELOCITY := 5.5
const GRAVITY := 14.0
const FLY_SPEED := 14.0
const MOUSE_SENS := 0.0025
const TAG_RANGE := 2.6
const TAG_COOLDOWN := 0.6
const ORBIT_DISTANCE := 4.0
const FP_PITCH_LIMIT := 1.35
# bunny hop: manual taps on landing stack slowly; bad timing bleeds speed;
# holding Space keeps hopping but bleeds speed fast
const HOP_PERFECT := 0.08
const HOP_WINDOW := 0.18
const HOP_MAX := 1.6
const HOP_GAIN_PERFECT := 0.07
const HOP_GAIN_OK := 0.03
const HOP_LOSS_BAD := 0.10
const HOP_LOSS_AUTO := 0.12
const AIR_CONTROL := 0.06
# climbing: in the air, catch a ledge whose top is between your waist and
# shoulder, hang for a beat, then pull up and over (a real motion, no teleport)
const CLIMB_MIN := 0.85
const CLIMB_MAX := 1.35
const CLIMB_REACH := 0.6
const CLIMB_HANG := 0.22
const CLIMB_RISE := 0.32
const CLIMB_OVER := 0.16
const NO_CONTROL_AFTER_WALL := 0.35
# wall jump: once per airtime; timed press gives more; S+Space kicks back
const WALL_JUMP_UP := 5.0
const WALL_JUMP_OUT := 4.0
const WALL_JUMP_TIMED := 1.35
const WALL_KICK_OUT := 6.0
const WALL_KICK_UP := 6.5
const TURN_TIME := 0.14
const WALL_TIMING := 0.12
const ROLL_TIME := 0.6
const ROLL_SPEED := 1.6
const ROLL_COOLDOWN := 1.0
# landing: hard impacts stop you for a moment; a roll on landing keeps you going
const IMPACT_SOFT := 8.0
const IMPACT_HARD := 17.0
const ROLL_LAND_WINDOW := 0.18
# breath
const BREATH_HOLD_MAX := 8.0
const GASP_TIME := 2.2
const BREATH_COOLDOWN := 4.0

enum F { CROUCH = 1, STUCK = 2, HOLDING = 4, GASPING = 8, ROLLING = 16, TALKING = 32 }

var peer_id: int = 1
## replicated
var anim := "Idle"
var punch_seq := 0
var state_flags := 0

var orbiting := false
var hop_boost := 1.0
var _since_land := 99.0
var _was_on_floor := true
var _seen_punch := 0
var _tag_cd := 0.0
var _roll_t := 0.0
var _roll_cd := 0.0
var _roll_dir := Vector3.ZERO
var _wall_jumped := false
var _wall_touch_t := 99.0
var _climb_t := 0.0
var _climb_target := Vector3.ZERO
var _climb_from := Vector3.ZERO
var _climb_mid := Vector3.ZERO
var _no_control_t := 0.0
var _wall_n := Vector3.ZERO
var _turn_t := 0.0
var _prev_vy := 0.0
var _stun_t := 0.0
var _roll_buffer := 0.0
var _land_t := 99.0
var _turn_target := 0.0
var _wall_mem_t := 0.0
var _wind: AudioStreamPlayer
var _wind_gen: AudioStreamGenerator
var _wind_last := 0.0
var _lines: CPUParticles2D
var _fell := false
var _hold_t := 0.0
var _gasp_t := 0.0
var _breath_cd := 0.0
var _stamina := 1.0 # 1 = fresh, 0 = winded
# local rendering (all peers)
var _step_t := 0.0
var _last_pos := Vector3.ZERO
var _prev_anim := ""
var _breath_player: AudioStreamPlayer3D
var _breath_gen: AudioStreamGenerator
var _breath_phase := 0.0
var _breath_rate := 0.3
var _tag_bg: MeshInstance3D
var _tag_mat: StandardMaterial3D

@onready var pivot: Node3D = $CamPivot
@onready var spring: SpringArm3D = $CamPivot/SpringArm3D
@onready var cam: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var model: Node3D = $Model
@onready var label: Label3D = $NameLabel
@onready var col: CollisionShape3D = $Collision
@onready var floor_ray: RayCast3D = $FloorRay
@onready var chest_ray: RayCast3D = $ChestRay
@onready var head_ray: RayCast3D = $HeadRay


func _enter_tree() -> void:
	peer_id = name.to_int()
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	var p := info()
	var color := Game.team_color(p.get("team", Game.Team.HIDER)) if not p.is_empty() else Color.WHITE
	model.load_skin(Skins.valid(str(p.get("skin", Skins.DEFAULT))), color)
	model.rotation.y = PI # rigged skins face +Z; we move along -Z
	_build_tag(color)
	_build_breath()
	if is_multiplayer_authority():
		_build_speed_feel()
	spring.add_excluded_object(get_rid())
	cam.current = is_multiplayer_authority()
	if is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_orbit(false)
	_last_pos = global_position
	Game.state_changed.connect(_refresh)
	_refresh()


func info() -> Dictionary:
	return Game.players.get(peer_id, {})


func has_flag(f: int) -> bool:
	return state_flags & f != 0


func _set_flag(f: int, on: bool) -> void:
	state_flags = (state_flags | f) if on else (state_flags & ~f)


# ---------------------------------------------------------------- visuals

func _refresh() -> void:
	var p := info()
	if p.is_empty():
		return
	var color := Game.team_color(p.team)
	if p.status == Game.Status.JAILED:
		color = Color(0.55, 0.55, 0.6)
	model.set_team_color(color)
	_tag_mat.albedo_color = color
	label.text = "%s\n%s" % [p.name, Game.team_label(p.team)]
	var out: bool = p.status == Game.Status.OUT
	col.disabled = out
	collision_layer = 0 if out else 1
	collision_mask = 0 if out else 1
	_apply_visibility()


func _apply_visibility() -> void:
	var p := info()
	var out: bool = not p.is_empty() and p.status == Game.Status.OUT
	var first_person := is_multiplayer_authority() and not orbiting
	model.visible = not out
	model.set_head_hidden(first_person)
	label.visible = not out and not first_person
	_tag_bg.visible = label.visible


func _set_orbit(on: bool) -> void:
	orbiting = on
	if not is_multiplayer_authority():
		return
	spring.spring_length = ORBIT_DISTANCE if on else 0.0
	_update_pivot()
	if not on:
		pivot.rotation.y = 0.0
		pivot.rotation.x = clampf(pivot.rotation.x, -FP_PITCH_LIMIT, FP_PITCH_LIMIT)
	_apply_visibility()


func _update_pivot() -> void:
	var eye := 0.95 if has_flag(F.CROUCH) else 1.55
	# SpringArm3D overwrites its child's position, so the eye offset lives here
	pivot.position = Vector3(0.0, eye + 0.05, 0.0) if orbiting else Vector3(0.0, eye, -0.3)


func _build_tag(color: Color) -> void:
	# Coloured pill behind the name. Hidden by walls (depth-tested).
	_tag_bg = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.15, 0.4)
	_tag_bg.mesh = qm
	_tag_mat = StandardMaterial3D.new()
	_tag_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tag_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_tag_mat.albedo_color = color
	_tag_mat.render_priority = -1
	_tag_bg.material_override = _tag_mat
	_tag_bg.position = label.position
	_tag_bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tag_bg)
	label.fixed_size = false
	label.no_depth_test = false
	label.pixel_size = 0.0035
	label.font_size = 40
	label.outline_size = 6
	label.render_priority = 1


func _build_breath() -> void:
	_breath_player = AudioStreamPlayer3D.new()
	_breath_gen = AudioStreamGenerator.new()
	_breath_gen.mix_rate = 22050
	_breath_gen.buffer_length = 0.25
	_breath_player.stream = _breath_gen
	_breath_player.position.y = 1.5
	_breath_player.unit_size = 2.0
	_breath_player.max_distance = 14.0
	_breath_player.volume_db = -18.0
	add_child(_breath_player)
	_breath_player.play()


func _build_speed_feel() -> void:
	_wind = AudioStreamPlayer.new()
	_wind_gen = AudioStreamGenerator.new()
	_wind_gen.mix_rate = 22050
	_wind_gen.buffer_length = 0.2
	_wind.stream = _wind_gen
	_wind.volume_db = -80.0
	add_child(_wind)
	_wind.play()
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	# warp-style burst: streaks shoot outward from the centre of the screen
	_lines = CPUParticles2D.new()
	_lines.emitting = false
	_lines.one_shot = true
	_lines.explosiveness = 1.0
	_lines.amount = 90
	_lines.lifetime = 0.4
	_lines.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_lines.emission_sphere_radius = 120.0
	_lines.direction = Vector2(0, 0)
	_lines.spread = 180
	_lines.gravity = Vector2.ZERO
	_lines.initial_velocity_min = 0
	_lines.initial_velocity_max = 0
	_lines.radial_accel_min = 2500
	_lines.radial_accel_max = 4500
	_lines.particle_flag_align_y = true
	_lines.scale_amount_min = 0.8
	_lines.scale_amount_max = 1.6
	_lines.color = Color(0.85, 0.9, 1.0, 0.8)
	var tex := GradientTexture2D.new()
	tex.width = 3
	tex.height = 90
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 1))
	tex.gradient = g
	_lines.texture = tex
	layer.add_child(_lines)


var _boost_env := 0.0

## Fired only when a hop or wall jump really gains speed.
func _boost_burst(strength: float) -> void:
	if _lines == null:
		return
	_boost_env = clampf(strength, 0.3, 1.0)
	_lines.position = get_viewport().get_visible_rect().size / 2.0
	_lines.amount = int(50 + 70 * _boost_env)
	_lines.restart()
	_lines.emitting = true


func _speed_feel(delta: float) -> void:
	# a quick FOV kick and a whoosh that decay after each boost
	_boost_env = move_toward(_boost_env, 0.0, delta * 1.6)
	cam.fov = lerpf(cam.fov, 72.0 + _boost_env * 14.0, delta * 8.0)
	_wind.volume_db = lerpf(_wind.volume_db, -30.0 + _boost_env * 26.0 if _boost_env > 0.02 else -80.0, delta * 6.0)
	var pb: AudioStreamGeneratorPlayback = _wind.get_stream_playback()
	if pb:
		for i in pb.get_frames_available():
			_wind_last = _wind_last * 0.96 + (randf() * 2.0 - 1.0) * 0.04
			pb.push_frame(Vector2(_wind_last, _wind_last) * 3.0)


func teleport(pos: Vector3) -> void:
	if is_multiplayer_authority():
		global_position = pos
		velocity = Vector3.ZERO
		_fell = false


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if orbiting:
			pivot.rotation.y -= event.relative.x * MOUSE_SENS
			pivot.rotation.x = clampf(pivot.rotation.x - event.relative.y * MOUSE_SENS, -1.2, 0.9)
		elif not has_flag(F.STUCK):
			rotate_y(-event.relative.x * MOUSE_SENS * Settings.mouse_sens)
			pivot.rotation.x = clampf(pivot.rotation.x - event.relative.y * MOUSE_SENS * Settings.mouse_sens, -FP_PITCH_LIMIT, FP_PITCH_LIMIT)
		else:
			pivot.rotation.x = clampf(pivot.rotation.x - event.relative.y * MOUSE_SENS * Settings.mouse_sens, -FP_PITCH_LIMIT, FP_PITCH_LIMIT)
	if event.is_action_pressed("orbit"):
		_set_orbit(true)
	elif event.is_action_released("orbit"):
		_set_orbit(false)
	if event.is_action_pressed("mouse_free"):
		if Pause.is_open:
			return
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("menu"):
		if not Pause.is_open:
			Pause.open()
	elif event.is_action_pressed("tag"):
		if Pause.is_open:
			return
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		_try_tag()
	elif event.is_action_pressed("roll"):
		_try_roll()


# ---------------------------------------------------------------- physics (authority)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_tag_cd = maxf(0.0, _tag_cd - delta)
	_roll_cd = maxf(0.0, _roll_cd - delta)
	var p := info()
	if p.is_empty():
		return
	if p.status == Game.Status.OUT:
		_fly(delta)
		return
	var frozen := Game.is_frozen(peer_id) or Pause.is_open
	var input := Vector2.ZERO if frozen else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	_breath_logic(delta, frozen)
	_speed_feel(delta)

	# fell off the map: out
	if global_position.y < -12.0:
		if not _fell:
			_fell = true
			Game.report_fall()
			velocity = Vector3.ZERO
			global_position = Vector3(0, 2, 0)
		return

	# climbing a ledge: hang, pull up, step over
	if _climb_t > 0.0:
		_climb_t -= delta
		velocity = Vector3.ZERO
		var total := CLIMB_HANG + CLIMB_RISE + CLIMB_OVER
		var e := total - _climb_t
		if e < CLIMB_HANG:
			anim = "Crouch_Idle"
			global_position = _climb_from
		elif e < CLIMB_HANG + CLIMB_RISE:
			var t := (e - CLIMB_HANG) / CLIMB_RISE
			t = t * t * (3.0 - 2.0 * t)
			global_position = _climb_from.lerp(_climb_mid, t)
			anim = "Jump"
		else:
			var t := (e - CLIMB_HANG - CLIMB_RISE) / CLIMB_OVER
			global_position = _climb_mid.lerp(_climb_target, clampf(t, 0.0, 1.0))
			anim = "Crouch_Fwd"
		if _climb_t <= 0.0:
			global_position = _climb_target
			anim = "Idle"
		return

	# wall stick: hold F against a wall, freeze flat to it
	if not frozen and Input.is_action_pressed("wall_stick") and _wall_contact():
		_set_flag(F.STUCK, true)
		velocity = Vector3.ZERO
		var n := get_wall_normal() if is_on_wall() else _wall_normal_ray()
		if n != Vector3.ZERO:
			global_position = global_position + n * 0.02
		anim = "Idle"
		return
	_set_flag(F.STUCK, false)

	# crouch (hold); can't stand up under a ceiling
	var want_crouch := not frozen and Input.is_action_pressed("crouch")
	if want_crouch != has_flag(F.CROUCH):
		if want_crouch or not _ceiling_blocked():
			_set_crouch(want_crouch)

	var on_floor := is_on_floor()
	_roll_buffer = maxf(0.0, _roll_buffer - delta)
	_land_t += delta
	if on_floor and not _was_on_floor:
		_since_land = 0.0
		_land_t = 0.0
		_wall_jumped = false
		_set_flag(F.ROLLING, false)
		_on_landed(-_prev_vy, dir)
	_was_on_floor = on_floor
	_since_land += delta
	_prev_vy = velocity.y
	# stunned by a hard landing: planted until it wears off (a roll cancels it)
	if _stun_t > 0.0:
		_stun_t -= delta
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		if Input.is_action_just_pressed("roll") and _land_t <= ROLL_LAND_WINDOW:
			_stun_t = 0.0
			_landing_roll(dir)
		else:
			move_and_slide()
			anim = "Crouch_Idle"
			return
	if not on_floor:
		velocity.y -= GRAVITY * delta
	if is_on_wall():
		_wall_touch_t += delta
		_wall_n = get_wall_normal()
		_wall_mem_t = 0.18 # remember the wall briefly: S pulls you off it before the tap lands
	else:
		_wall_touch_t = 0.0
		_wall_mem_t = maxf(0.0, _wall_mem_t - delta)

	# roll: short dash, low profile
	if _roll_t > 0.0:
		_roll_t -= delta
		velocity.x = _roll_dir.x * SPRINT_SPEED * ROLL_SPEED
		velocity.z = _roll_dir.z * SPRINT_SPEED * ROLL_SPEED
		move_and_slide()
		anim = "Roll"
		if _roll_t <= 0.0:
			_set_flag(F.ROLLING, false)
			if not Input.is_action_pressed("crouch") and not _ceiling_blocked():
				_set_crouch(false)
		return

	var sprinting := Input.is_action_pressed("sprint") and not has_flag(F.CROUCH) and _stamina > 0.05
	var base := CROUCH_SPEED if has_flag(F.CROUCH) else (SPRINT_SPEED if sprinting else WALK_SPEED)
	var speed := base * hop_boost
	if on_floor:
		if dir != Vector3.ZERO:
			velocity.x = dir.x * speed
			velocity.z = dir.z * speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, speed)
			velocity.z = move_toward(velocity.z, 0.0, speed)
	elif dir != Vector3.ZERO and _no_control_t <= 0.0:
		velocity.x = lerpf(velocity.x, dir.x * speed, AIR_CONTROL)
		velocity.z = lerpf(velocity.z, dir.z * speed, AIR_CONTROL)
	_no_control_t = maxf(0.0, _no_control_t - delta)
	if _turn_t > 0.0:
		_turn_t -= delta
		var k := clampf(delta / maxf(_turn_t + delta, 0.001), 0.0, 1.0)
		rotation.y = lerp_angle(rotation.y, _turn_target, k)

	var tapped := Input.is_action_just_pressed("jump") and not frozen
	var held := Input.is_action_pressed("jump") and not frozen and not tapped
	# climb: only in the air, not while pressing jump (wall jumps win), moving
	# into a wall whose top is between your waist and your shoulder
	var ledge: Variant = null
	if not on_floor and not tapped and not held and velocity.y < 2.0 and is_on_wall() and not has_flag(F.CROUCH):
		ledge = _ledge_top(dir)
	if ledge != null:
		_climb_from = global_position
		_climb_mid = Vector3(global_position.x, ledge.y + 0.05, global_position.z)
		_climb_target = Vector3(ledge.x, ledge.y + 0.05, ledge.z)
		_climb_t = CLIMB_HANG + CLIMB_RISE + CLIMB_OVER
		velocity = Vector3.ZERO
		hop_boost = 1.0 # you hit the wall; momentum is gone
		Sfx.play_at("land_" + _surface(), global_position, -4.0)
		anim = "Crouch_Idle"
		return
	if on_floor and (tapped or held) and not has_flag(F.CROUCH):
		if dir != Vector3.ZERO:
			if tapped:
				if _since_land <= HOP_PERFECT:
					hop_boost += HOP_GAIN_PERFECT
					_boost_burst(0.6 + (hop_boost - 1.0))
				elif _since_land <= HOP_WINDOW:
					hop_boost += HOP_GAIN_OK
					_boost_burst(0.35)
				else:
					hop_boost -= HOP_LOSS_BAD
			else:
				hop_boost -= HOP_LOSS_AUTO # auto hops bleed speed fast
		hop_boost = clampf(hop_boost, 1.0, HOP_MAX)
		if held and dir != Vector3.ZERO:
			# auto hop: low and long
			velocity.y = JUMP_VELOCITY * 0.72
			velocity.x = dir.x * speed * 1.18
			velocity.z = dir.z * speed * 1.18
		else:
			velocity.y = JUMP_VELOCITY
		Sfx.play_at("jump", global_position, -10.0)
	elif not on_floor and tapped and _wall_mem_t > 0.0 and not _wall_jumped:
		_wall_jump(input)
	elif on_floor and _since_land > 0.25:
		hop_boost = move_toward(hop_boost, 1.0, delta * 1.5)

	_stair_step(dir)
	move_and_slide()

	var hspeed := Vector2(velocity.x, velocity.z).length()
	if has_flag(F.CROUCH):
		anim = "Crouch_Fwd" if hspeed > 0.3 else "Crouch_Idle"
	else:
		anim = model.locomotion(hspeed, is_on_floor(), sprinting)
	if sprinting and hspeed > 1.0:
		_stamina = maxf(0.0, _stamina - delta * 0.08)
	else:
		_stamina = minf(1.0, _stamina + delta * 0.05)



## Stairs: on the ground, blocked by a near-vertical face no taller than
## one step, with room above it: lift onto it this frame, no pause. Slopes
## don't block, so they never trigger it; in the air it never runs.
const STAIR_MAX := 0.55
func _stair_step(dir: Vector3) -> void:
	if dir == Vector3.ZERO or not is_on_floor() or _climb_t > 0.0:
		return
	var probe := dir * 0.3
	var params := PhysicsTestMotionParameters3D.new()
	params.from = global_transform.translated(Vector3.UP * 0.06)
	params.motion = probe
	var res := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(get_rid(), params, res):
		return # nothing ahead
	if res.get_collision_normal().y > 0.3:
		return # a slope
	if test_move(global_transform, Vector3.UP * STAIR_MAX):
		return
	var up := global_transform.translated(Vector3.UP * STAIR_MAX)
	if test_move(up, probe):
		return # taller than a step
	# how high is the step really: drop a ray just past the riser we hit
	var cp: Vector3 = res.get_collision_point() + dir * 0.15
	var top := Vector3(cp.x, global_position.y + STAIR_MAX + 0.05, cp.z)
	var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * (STAIR_MAX + 0.2))
	q.exclude = [get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return
	var rise: float = r.position.y - global_position.y
	if rise <= 0.02 or rise > STAIR_MAX:
		return
	global_position.y += rise + 0.01
	velocity.y = maxf(velocity.y, 0.0)


## One wall jump per airtime. Timed press (right as you touch the wall, W
## held) kicks harder; S + Space kicks you backwards and spins you around.
func _wall_jump(input: Vector2) -> void:
	var n := _wall_n
	n.y = 0.0
	n = n.normalized()
	_wall_jumped = true
	_wall_mem_t = 0.0
	_no_control_t = NO_CONTROL_AFTER_WALL # keep the kick; S after the spin must not cancel it
	if input.y > 0.5:
		# S + Space: diagonal kick away from the wall, face away from it
		velocity = n * WALL_KICK_OUT + Vector3.UP * WALL_KICK_UP
		_turn_target = atan2(-n.x, -n.z) # face away from the wall, quick turn
		_turn_t = TURN_TIME
		Sfx.play_at("jump", global_position, 0.0)
		_boost_burst(0.8)
		return
	var timed := _wall_touch_t <= WALL_TIMING and input.y < -0.5
	var mult := WALL_JUMP_TIMED if timed else 1.0
	velocity = n * WALL_JUMP_OUT * mult + Vector3.UP * WALL_JUMP_UP * mult + Vector3(velocity.x, 0, velocity.z) * 0.25
	Sfx.play_at("jump", global_position, -4.0 if not timed else 0.0)
	if timed:
		_boost_burst(0.6)


## Top of a ledge in front of us that can be climbed, or null.
func _ledge_top(dir: Vector3) -> Variant:
	if dir == Vector3.ZERO:
		return null
	var basis := Basis.looking_at(dir, Vector3.UP)
	# shoulder ray must be clear, waist ray must hit: the top is between them
	head_ray.position.y = CLIMB_MAX
	head_ray.global_transform.basis = basis
	head_ray.target_position = Vector3(0, 0, -CLIMB_REACH)
	head_ray.force_raycast_update()
	if head_ray.is_colliding():
		return null
	chest_ray.position.y = CLIMB_MIN
	chest_ray.global_transform.basis = basis
	chest_ray.target_position = Vector3(0, 0, -CLIMB_REACH)
	chest_ray.force_raycast_update()
	if not chest_ray.is_colliding():
		return null
	# find the top: cast down from above the ledge, just past the wall
	var wall_p: Vector3 = chest_ray.get_collision_point()
	var from := Vector3(wall_p.x, global_position.y + CLIMB_MAX + 0.05, wall_p.z) + dir * 0.45
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (CLIMB_MAX + 0.1))
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var top: Vector3 = hit.position
	var h := top.y - global_position.y
	if h < CLIMB_MIN or h > CLIMB_MAX:
		return null
	return top


func _wall_contact() -> bool:
	return is_on_wall() or _wall_normal_ray() != Vector3.ZERO


func _wall_normal_ray() -> Vector3:
	chest_ray.position.y = 1.0
	chest_ray.global_transform.basis = global_transform.basis
	chest_ray.target_position = Vector3(0, 0, -0.75)
	chest_ray.force_raycast_update()
	return chest_ray.get_collision_normal() if chest_ray.is_colliding() else Vector3.ZERO


func _ceiling_blocked() -> bool:
	return test_move(global_transform, Vector3.UP * 0.9)


func _set_crouch(on: bool) -> void:
	_set_flag(F.CROUCH, on)
	var shape: CapsuleShape3D = col.shape
	shape.height = 1.0 if on else 1.8
	col.position.y = 0.5 if on else 0.9
	_update_pivot()


## Landed with speed `impact`. Soft: nothing. Harder: a planted stop that
## scales with the fall. A roll buffered just before landing turns it into a
## boost instead.
func _on_landed(impact: float, dir: Vector3) -> void:
	if _roll_buffer > 0.0:
		_landing_roll(dir)
		return
	if impact < IMPACT_SOFT:
		return
	var k := clampf((impact - IMPACT_SOFT) / (IMPACT_HARD - IMPACT_SOFT), 0.0, 1.0)
	_stun_t = 0.12 + 0.6 * k
	hop_boost = 1.0
	velocity.x *= 0.15
	velocity.z *= 0.15
	Sfx.play_at("land_" + _surface(), global_position, 2.0 + 6.0 * k)
	pivot.position.y -= 0.25 * k # camera dip; _update_pivot restores it
	get_tree().create_timer(0.2).timeout.connect(_update_pivot)


func _landing_roll(dir: Vector3) -> void:
	_roll_buffer = 0.0
	var d := dir if dir != Vector3.ZERO else -global_transform.basis.z
	_roll_dir = d.normalized()
	_roll_t = ROLL_TIME
	_roll_cd = ROLL_COOLDOWN
	hop_boost = minf(hop_boost + 0.08, HOP_MAX)
	_set_flag(F.ROLLING, true)
	_set_crouch(true)
	Sfx.play_at("roll", global_position, -2.0)
	_boost_burst(0.4)


func _try_roll() -> void:
	if not is_multiplayer_authority() or Game.is_frozen(peer_id):
		return
	if not is_on_floor():
		# mid-air roll: tuck and drop straight down; also buffers a landing roll
		if not has_flag(F.ROLLING):
			velocity = Vector3(0.0, minf(velocity.y, 0.0), 0.0)
			_set_flag(F.ROLLING, true)
			model.play_oneshot("Roll")
			Sfx.play_at("roll", global_position, -6.0)
		_roll_buffer = ROLL_LAND_WINDOW
		return
	if _roll_cd > 0.0:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO:
		input = Vector2(0, -1)
	_roll_dir = (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	_roll_t = ROLL_TIME
	_roll_cd = ROLL_COOLDOWN
	_set_flag(F.ROLLING, true)
	_set_crouch(true)
	Sfx.play_at("roll", global_position, -4.0)


func _breath_logic(delta: float, frozen: bool) -> void:
	_breath_cd = maxf(0.0, _breath_cd - delta)
	if _gasp_t > 0.0:
		_gasp_t -= delta
		_set_flag(F.GASPING, _gasp_t > 0.0)
		_set_flag(F.HOLDING, false)
		return
	var want := Input.is_action_pressed("hold_breath") and not frozen and _breath_cd <= 0.0
	if want:
		_hold_t += delta
		if _hold_t >= BREATH_HOLD_MAX:
			# held too long: loud gasp, everyone nearby hears it
			_hold_t = 0.0
			_gasp_t = GASP_TIME
			_breath_cd = BREATH_COOLDOWN
			_set_flag(F.HOLDING, false)
			_set_flag(F.GASPING, true)
			Sfx.play_at("gasp", global_position, 4.0)
			return
		_set_flag(F.HOLDING, true)
	else:
		if has_flag(F.HOLDING) and _hold_t > 3.0:
			_breath_cd = 1.5 # a quick recovery breath after a long hold
		_hold_t = 0.0
		_set_flag(F.HOLDING, false)


## Spectator free-fly for players who are out.
func _fly(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis := cam.global_transform.basis
	var dir := (basis * Vector3(input.x, 0.0, input.y))
	if Input.is_action_pressed("jump"):
		dir.y += 1.0
	if Input.is_action_pressed("sprint"):
		dir.y -= 1.0
	velocity = dir.normalized() * FLY_SPEED if dir != Vector3.ZERO else Vector3.ZERO
	global_position += velocity * delta


func _try_tag() -> void:
	if _tag_cd > 0.0 or Game.phase != Game.Phase.PLAYING or not Game.tags_allowed():
		return
	_tag_cd = TAG_COOLDOWN
	punch_seq += 1
	var fwd := -global_transform.basis.z
	var best: Node3D = null
	var best_d := TAG_RANGE
	for n in get_tree().get_nodes_in_group("players"):
		if n == self or not (n is Node3D):
			continue
		var to: Vector3 = n.global_position - global_position
		var d := to.length()
		if d < best_d and fwd.dot(to.normalized()) > 0.25:
			best = n
			best_d = d
	if best:
		Game.try_tag(best.get("peer_id"))


# ---------------------------------------------------------------- every peer: animation + sound

func _process(delta: float) -> void:
	if punch_seq != _seen_punch:
		_seen_punch = punch_seq
		model.play_oneshot(model.ANIM_PUNCH)
	model.play(anim)
	_footsteps(delta)
	_breath_audio(delta)
	_prev_anim = anim


func _surface() -> String:
	floor_ray.force_raycast_update()
	if floor_ray.is_colliding():
		var c := floor_ray.get_collider()
		if c and c.has_meta("surface"):
			return str(c.get_meta("surface"))
	return "concrete"


func _footsteps(delta: float) -> void:
	var moved := global_position - _last_pos
	_last_pos = global_position
	var hspeed := Vector2(moved.x, moved.z).length() / maxf(delta, 0.0001)
	var stepping := anim in ["Walk", "Jog_Fwd", "Sprint", "Crouch_Fwd"] and hspeed > 0.5
	if _prev_anim == "Jump" and anim != "Jump":
		Sfx.play_at("land_" + _surface(), global_position, -6.0 if has_flag(F.CROUCH) else 0.0)
		_step_t = 0.2
	if not stepping:
		_step_t = 0.0
		return
	_step_t -= delta
	if _step_t <= 0.0:
		var interval := clampf(2.1 / maxf(hspeed, 1.0), 0.26, 0.7)
		_step_t = interval
		var vol := -2.0
		if has_flag(F.CROUCH):
			vol -= 10.0
		if has_flag(F.HOLDING):
			vol -= 6.0 # careful steps while holding breath
		if anim == "Sprint":
			vol += 3.0
		Sfx.play_at("step_" + _surface(), global_position, vol)


func _breath_audio(delta: float) -> void:
	# Procedural breathing: filtered noise with an inhale/exhale envelope.
	# Quiet when calm, heavy after sprinting, silent while holding, loud gasp.
	var target_rate := 0.28
	var loud := -22.0
	if anim == "Sprint":
		target_rate = 0.9
		loud = -8.0
	elif anim == "Jog_Fwd":
		target_rate = 0.5
		loud = -14.0
	if has_flag(F.GASPING):
		target_rate = 1.6
		loud = 0.0
	_breath_rate = lerpf(_breath_rate, target_rate, delta * 0.8)
	if has_flag(F.HOLDING):
		loud = -80.0
	_breath_player.volume_db = lerpf(_breath_player.volume_db, loud, delta * 3.0)
	var pb: AudioStreamGeneratorPlayback = _breath_player.get_stream_playback()
	if pb == null:
		return
	var frames := pb.get_frames_available()
	var rate := _breath_gen.mix_rate
	var last := 0.0
	for i in frames:
		_breath_phase += _breath_rate / rate
		var env := pow(maxf(0.0, sin(_breath_phase * TAU)), 1.6)
		# cheap low-passed noise
		last = last * 0.92 + (randf() * 2.0 - 1.0) * 0.08
		var v := last * env * 2.5
		pb.push_frame(Vector2(v, v))
