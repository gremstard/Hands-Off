extends Node
## Boots the main menu and the lobby (as host) to catch UI build errors.

func _ready() -> void:
	var r := Node.new()
	r.set_script(load("res://tests/ui_runner.gd"))
	get_tree().root.add_child.call_deferred(r)
