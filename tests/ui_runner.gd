extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	for i in 5: await get_tree().process_frame
	var menu := get_tree().current_scene
	print("menu scene: ", menu.name, " children: ", menu.get_child_count())
	Net.player_name = "UI"
	Net.host(7799)
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
	for i in 5: await get_tree().process_frame
	var lobby := get_tree().current_scene
	print("lobby scene: ", lobby.name, " mode: ", lobby.mode_option.get_item_text(lobby.mode_option.selected))
	Game.set_mode(Game.Mode.COPS_ROBBERS)
	for i in 3: await get_tree().process_frame
	print("lobby after mode change: ", lobby.mode_desc.text)
	get_tree().change_scene_to_file("res://scenes/settings.tscn")
	for i in 5: await get_tree().process_frame
	print("settings: ", get_tree().current_scene.name, " crouch=", Settings.key_name("crouch"), " roll=", Settings.key_name("roll"), " talk=", Settings.key_name("talk"), " breath=", Settings.key_name("hold_breath"))
	# skin editor
	get_tree().change_scene_to_file("res://scenes/skin_editor.tscn")
	for i in 8: await get_tree().process_frame
	var se := get_tree().current_scene
	print("skin editor: ", se.name, " skins: ", se._skins.size(), " animated preview: ", se.preview_model.is_animated())
	# map editor: place a block, a zone, save, reload
	get_tree().change_scene_to_file("res://scenes/map_editor.tscn")
	for i in 8: await get_tree().process_frame
	var ed := get_tree().current_scene
	var before: int = ed.map.blocks.size()
	ed._cursor_valid = true
	ed._cursor_pos = Vector3(4, 1, 4)
	ed._act()
	ed._set_tool(3) # hander spawn
	ed._cursor_pos = Vector3(6, 0.5, 6)
	ed._act()
	ed.name_edit.text = "uitest"
	ed._save()
	var back := MapData.load_file(MapData.user_path("uitest"))
	print("map editor: blocks %d -> %d, saved+loaded blocks=%d markers=%d hander=%s" % [before, ed.map.blocks.size(), back.blocks.size(), back.markers.size(), str(back.markers.filter(func(m): return m.k == "hander")[0].p)])
	if back.blocks.size() != before + 1:
		printerr("FAIL map roundtrip")
		get_tree().quit(1)
	get_tree().change_scene_to_file("res://scenes/kit_builder.tscn")
	for i in 10: await get_tree().process_frame
	var kb = get_tree().current_scene
	var nb: int = kb.map.props.size()
	kb._cursor_valid = true
	kb._cursor_pos = Vector3(8, 0, 8)
	kb._act()
	print("kit builder: cats=%d thumbs=%d props %d -> %d piece=%s" % [kb._cats.size(), kb._thumb_grid.get_child_count(), nb, kb.map.props.size(), kb.prop_path.get_file()])
	if kb.map.props.size() != nb + 1:
		printerr("FAIL kit builder place")
		get_tree().quit(1)
	print("UI OK")
	get_tree().quit(0)
