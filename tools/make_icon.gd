extends SceneTree
## Rasterise assets/icon/icon.svg to PNG (1024 and 256) for the exports.
func _init() -> void:
	var svg := FileAccess.get_file_as_string("res://assets/icon/icon.svg")
	for size in [1024, 256, 64]:
		var img := Image.new()
		var err := img.load_svg_from_string(svg, size / 1024.0)
		if err != OK:
			print("svg load failed: ", error_string(err))
			quit(1)
			return
		img.save_png("res://assets/icon/icon%d.png" % size)
	DirAccess.copy_absolute("res://assets/icon/icon1024.png", "res://icon.png")
	print("icon ok")
	quit(0)
