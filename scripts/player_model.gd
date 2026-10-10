extends Node3D
## Loads a character GLB, scales it to player height, applies the toon look,
## and drives animations from the Universal Animation Library when the
## model has a skeleton. Unrigged models simply stand still.

const TARGET_HEIGHT := 1.8
# Godot's glTF importer strips the "_Loop" suffix and marks those clips looping.
const ANIM_IDLE := "Idle"
const ANIM_WALK := "Walk"
const ANIM_JOG := "Jog_Fwd"
const ANIM_SPRINT := "Sprint"
const ANIM_JUMP := "Jump"
const ANIM_PUNCH := "Interact" # reach out a hand to tag
const ANIM_HIT := "Hit_Chest"
const ANIM_DANCE := "Dance"

static var _library: AnimationLibrary = null

var skin := ""
var instance: Node3D = null
var skeleton: Skeleton3D = null
var anim_player: AnimationPlayer = null
var materials: Array[ShaderMaterial] = []
var current_anim := ""
var _oneshot_until := 0.0


func load_skin(new_skin: String, team_color: Color) -> void:
	skin = new_skin
	for c in get_children():
		c.queue_free()
	instance = null
	skeleton = null
	anim_player = null
	materials.clear()
	current_anim = ""

	var scene: PackedScene = load(Skins.path(skin))
	if scene == null and skin != Skins.MANNEQUIN:
		push_warning("Skin '%s' missing, falling back to mannequin" % skin)
		skin = Skins.MANNEQUIN
		scene = load(Skins.path(skin))
	if scene == null:
		_build_capsule(team_color)
		return

	instance = scene.instantiate()
	add_child(instance)
	if skin != Skins.MANNEQUIN:
		_hide_reference_meshes(instance)
	_fit_to_height()
	# No hull outline on characters: their arm/torso blocks overlap inside, and the
	# inverted hull of those interior faces pokes through. Team colour comes from
	# the ring and name tag instead.
	materials = Toon.convert_scene(instance, team_color, 0.0, false)
	if skin == Skins.MANNEQUIN:
		_tint_mannequin(team_color)
	skeleton = _find(instance, "Skeleton3D") as Skeleton3D
	if skeleton:
		_setup_animation()
		play(ANIM_IDLE)


func set_team_color(color: Color) -> void:
	for m in materials:
		if m.next_pass:
			m.next_pass.set_shader_parameter("outline_color", color)
	if skin == Skins.MANNEQUIN:
		_tint_mannequin(color)


## First person: collapse the Head bone so the head and face vanish while
## the body and arms stay visible. (Scale tracks are stripped from the clips,
## so the pose scale sticks.)
func set_head_hidden(hidden: bool) -> void:
	if skeleton == null:
		return
	var hi := skeleton.find_bone("Head")
	if hi < 0:
		return
	skeleton.set_bone_pose_scale(hi, Vector3.ONE * (0.001 if hidden else 1.0))


func is_animated() -> bool:
	return anim_player != null


## Pick a locomotion clip from movement state. Called every frame by Player.
func locomotion(horizontal_speed: float, on_floor: bool, sprinting: bool) -> String:
	if not on_floor:
		return ANIM_JUMP
	if horizontal_speed < 0.3:
		return ANIM_IDLE
	if sprinting and horizontal_speed > 7.0:
		return ANIM_SPRINT
	if horizontal_speed > 4.0:
		return ANIM_JOG
	return ANIM_WALK


func play(anim: String) -> void:
	if anim_player == null or anim == current_anim:
		return
	if Time.get_ticks_msec() / 1000.0 < _oneshot_until:
		return
	var key := "ual/" + anim
	if anim_player.has_animation(key):
		anim_player.play(key, 0.15)
		current_anim = anim


func play_oneshot(anim: String) -> void:
	if anim_player == null:
		return
	var key := "ual/" + anim
	if not anim_player.has_animation(key):
		return
	anim_player.play(key, 0.08)
	current_anim = anim
	_oneshot_until = Time.get_ticks_msec() / 1000.0 + anim_player.get_animation(key).length * 0.8


# ---------------------------------------------------------------- internals

func _hide_reference_meshes(root: Node) -> void:
	# The exported character files still contain the Quaternius mannequin
	# used as a size reference in Blender. Hide it.
	for n in _all(root):
		if n is MeshInstance3D and n.name.begins_with("Mannequin"):
			n.visible = false


func _fit_to_height() -> void:
	var aabb := AABB()
	var first := true
	for n in _all(instance):
		if n is MeshInstance3D and n.visible and n.mesh:
			var rel: Transform3D = global_transform.affine_inverse() * n.global_transform
			var box: AABB = rel * n.mesh.get_aabb()
			aabb = box if first else aabb.merge(box)
			first = false
	if first or aabb.size.y <= 0.001:
		return
	var s := TARGET_HEIGHT / aabb.size.y
	instance.scale = Vector3.ONE * s
	instance.position = Vector3(-aabb.get_center().x * s, -aabb.position.y * s, -aabb.get_center().z * s)


func _tint_mannequin(color: Color) -> void:
	for i in materials.size():
		var c := color if i % 2 == 0 else color.darkened(0.45)
		materials[i].set_shader_parameter("albedo_color", c)


func _setup_animation() -> void:
	var lib := _get_library()
	if lib == null:
		return
	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	instance.add_child(anim_player)
	anim_player.root_node = NodePath("..")
	# Retarget track paths to wherever this model's skeleton lives.
	var skel_path := str(instance.get_path_to(skeleton))
	var needs_remap := false
	for anim_name in lib.get_animation_list():
		var a := lib.get_animation(anim_name)
		if a.get_track_count() > 0 and str(a.track_get_path(0)).get_slice(":", 0) != skel_path:
			needs_remap = true
		break
	if needs_remap:
		lib = lib.duplicate(true)
		for anim_name in lib.get_animation_list():
			var a := lib.get_animation(anim_name)
			for t in a.get_track_count():
				var p := str(a.track_get_path(t))
				var bone := p.get_slice(":", 1)
				a.track_set_path(t, NodePath(skel_path + ":" + bone))
	anim_player.add_animation_library("ual", lib)


static func _get_library() -> AnimationLibrary:
	if _library:
		return _library
	var scene: PackedScene = load(Skins.ANIM_LIBRARY_PATH)
	if scene == null:
		push_warning("Animation library not found at " + Skins.ANIM_LIBRARY_PATH)
		return null
	var tmp := scene.instantiate()
	var ap := tmp.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		tmp.free()
		return null
	var names := ap.get_animation_library_list()
	if names.is_empty():
		tmp.free()
		return null
	_library = ap.get_animation_library(names[0]).duplicate(true)
	# The clips bake a position track on every bone in the mannequin's
	# proportions. Keep only root/pelvis motion so other rigs keep their own
	# bone lengths; rotation does the rest.
	for anim_name in _library.get_animation_list():
		var a := _library.get_animation(anim_name)
		for t in range(a.get_track_count() - 1, -1, -1):
			var ty := a.track_get_type(t)
			if ty == Animation.TYPE_SCALE_3D:
				a.remove_track(t)
			elif ty == Animation.TYPE_POSITION_3D:
				var bone := str(a.track_get_path(t)).get_slice(":", 1)
				if bone != "pelvis" and bone != "root":
					a.remove_track(t)
	# Hany is a stiff blocky fellow: damp the spine and neck bends the
	# mannequin clips carry so he stands upright instead of slouching.
	const DAMP := {"spine_01": 0.4, "spine_02": 0.4, "spine_03": 0.5, "neck_01": 0.35, "Head": 0.6}
	for anim_name in _library.get_animation_list():
		var a := _library.get_animation(anim_name)
		for t in a.get_track_count():
			if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
				continue
			var bone := str(a.track_get_path(t)).get_slice(":", 1)
			if not DAMP.has(bone):
				continue
			var f: float = DAMP[bone]
			for k in a.track_get_key_count(t):
				var q: Quaternion = a.track_get_key_value(t, k)
				a.track_set_key_value(t, k, Quaternion.IDENTITY.slerp(q, f))
	for anim_name in [ANIM_IDLE, ANIM_WALK, ANIM_JOG, ANIM_SPRINT, ANIM_JUMP, ANIM_DANCE, "A_TPose"]:
		if _library.has_animation(anim_name):
			_library.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	tmp.free()
	return _library


func _build_capsule(color: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = TARGET_HEIGHT
	mi.mesh = cm
	mi.position.y = TARGET_HEIGHT / 2
	var m := Toon.material(color)
	mi.material_override = m
	materials.append(m)
	add_child(mi)
	instance = mi


static func _find(root: Node, cls: String) -> Node:
	if root.is_class(cls):
		return root
	for c in root.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null


static func _all(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	for c in root.get_children():
		out.append_array(_all(c))
	return out
