extends Node
## Headless smoke test: hosts a server, injects fake peers, plays each mode
## through to a result. Run with:
##   godot --headless --path . res://tests/smoke.tscn

var failures := 0


func _ready() -> void:
	var runner := Node.new()
	runner.name = "SmokeRunner"
	runner.set_script(load("res://tests/smoke_runner.gd"))
	get_tree().root.add_child.call_deferred(runner)
