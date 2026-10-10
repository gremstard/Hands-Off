extends SceneTree
## Writes the built-in map to assets/maps/blockyard.hom (so it's a real file
## people can copy and remix).
func _init() -> void:
	var m := MapData.default_map()
	var err := m.save_file("res://assets/maps/blockyard.hom")
	print("blockyard.hom: ", error_string(err), " blocks=", m.blocks.size())
	quit(0 if err == OK else 1)
