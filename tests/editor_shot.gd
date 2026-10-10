extends Node
func _ready() -> void:
	var r := Node.new()
	r.set_script(load("res://tests/editor_shot_runner.gd"))
	get_tree().root.add_child.call_deferred(r)
