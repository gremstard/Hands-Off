extends Node
## Key bindings and options, saved to user://settings.cfg. Defaults keep the
## keys around WASD: Shift sprint, C crouch, V roll, F wall stick, X talk,
## R hold breath, E tag.

const PATH := "user://settings.cfg"

## action -> [display name, default physical keycode]
const ACTIONS := {
	"move_forward": ["Move forward", KEY_W],
	"move_back": ["Move back", KEY_S],
	"move_left": ["Move left", KEY_A],
	"move_right": ["Move right", KEY_D],
	"jump": ["Jump", KEY_SPACE],
	"sprint": ["Sprint", KEY_SHIFT],
	"crouch": ["Crouch", KEY_C],
	"roll": ["Roll", KEY_V],
	"wall_stick": ["Wall stick", KEY_F],
	"talk": ["Talk (voice)", KEY_X],
	"hold_breath": ["Hold breath", KEY_R],
	"tag": ["Tag", KEY_E],
	"orbit": ["Orbit camera", KEY_ALT],
	"mouse_free": ["Free / lock mouse", KEY_ESCAPE],
	"menu": ["Menu", KEY_TAB],
}

var keys: Dictionary = {}   # action -> keycode
var talk_toggle := false
var mouse_sens := 1.0


func _ready() -> void:
	for a in ACTIONS:
		keys[a] = ACTIONS[a][1]
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for a in ACTIONS:
		keys[a] = int(cfg.get_value("keys", a, keys[a]))
	# older saves had the menu on Escape; Escape is the mouse key now
	if keys["menu"] == KEY_ESCAPE:
		keys["menu"] = KEY_TAB
	talk_toggle = bool(cfg.get_value("options", "talk_toggle", false))
	mouse_sens = float(cfg.get_value("options", "mouse_sens", 1.0))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for a in keys:
		cfg.set_value("keys", a, keys[a])
	cfg.set_value("options", "talk_toggle", talk_toggle)
	cfg.set_value("options", "mouse_sens", mouse_sens)
	cfg.save(PATH)
	apply()


func rebind(action: String, keycode: int) -> void:
	keys[action] = keycode
	save_settings()


## Push the bindings into the InputMap. Tag keeps left click as well.
func apply() -> void:
	for a in ACTIONS:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		InputMap.action_erase_events(a)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[a]
		InputMap.action_add_event(a, ev)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("tag", mb)
	var orb := InputEventMouseButton.new()
	orb.button_index = MOUSE_BUTTON_MIDDLE
	InputMap.action_add_event("orbit", orb)
	# Tab must reach the game, not hop between UI controls
	if InputMap.has_action("ui_focus_next"):
		InputMap.action_erase_events("ui_focus_next")
	if InputMap.has_action("ui_focus_prev"):
		InputMap.action_erase_events("ui_focus_prev")


func key_name(action: String) -> String:
	return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(keys[action]))
