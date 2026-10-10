extends Node

var failures := 0

func check(cond: bool, what: String) -> void:
	if cond: print("  PASS  ", what)
	else:
		failures += 1
		printerr("  FAIL  ", what)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	var root := Node3D.new()
	get_tree().root.add_child(root)
	# banana (unrigged)
	var m := Node3D.new()
	m.set_script(load("res://scripts/player_model.gd"))
	root.add_child(m)
	m.load_skin("banana", Color.YELLOW)
	await get_tree().process_frame
	check(m.instance != null, "banana loaded")
	var aabb := _bounds(m)
	print("    banana bounds: ", aabb)
	check(absf(aabb.size.y - 1.8) < 0.05, "banana scaled to 1.8m (got %.2f)" % aabb.size.y)
	check(absf(aabb.position.y) < 0.05, "banana feet at y=0 (got %.2f)" % aabb.position.y)
	check(m.materials.size() >= 5, "banana materials converted to toon (%d)" % m.materials.size())
	check(m.is_animated(), "banana is rigged and animated")
	var ref := 0
	for n in m._all(m.instance):
		if n is MeshInstance3D and n.name.begins_with("Mannequin"): ref += 1
	check(ref == 0, "no reference mannequin left in banana.glb")
	# mannequin (rigged)
	var q := Node3D.new()
	q.set_script(load("res://scripts/player_model.gd"))
	root.add_child(q)
	q.load_skin("mannequin", Color.RED)
	await get_tree().process_frame
	check(q.is_animated(), "mannequin has animation player")
	check(q.anim_player != null and q.anim_player.has_animation("ual/Idle"), "UAL library attached")
	check(q.anim_player != null and q.anim_player.has_animation("ual/Sprint"), "Sprint present")
	var qa := _bounds(q)
	check(absf(qa.size.y - 1.8) < 0.1, "mannequin scaled to 1.8m (got %.2f)" % qa.size.y)
	var skel: Skeleton3D = q.skeleton
	var bi := skel.find_bone("upperarm_l")
	check(bi >= 0, "bone upperarm_l found")
	q.play("Jog_Fwd")
	var before := skel.get_bone_pose_rotation(bi)
	for i in 20: await get_tree().process_frame
	var after := skel.get_bone_pose_rotation(bi)
	check(before.angle_to(after) > 0.01, "bone moves while Jog_Fwd plays (delta %.3f rad)" % before.angle_to(after))
	check(q.anim_player.current_animation == "ual/Jog_Fwd", "current animation is Jog_Fwd")
	q.play_oneshot("Punch_Jab")
	check(q.anim_player.current_animation == "ual/Punch_Jab", "punch oneshot plays")
	print("\n%d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _bounds(m: Node3D) -> AABB:
	var aabb := AABB(); var first := true
	for n in m._all(m.instance):
		if n is MeshInstance3D and n.visible and n.mesh:
			var rel: Transform3D = m.global_transform.affine_inverse() * n.global_transform
			var box: AABB = rel * n.mesh.get_aabb()
			aabb = box if first else aabb.merge(box); first = false
	return aabb
