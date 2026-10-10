extends Node
## Player profile saved on disk: name, skin, later hats and costumes.
## Edited from the main menu's skin editor; the lobby just reads it.

const PATH := "user://profile.cfg"

var player_name := "Hany"
var skin := Skins.DEFAULT
var hat := ""
var costume := ""


func _ready() -> void:
	var icon: Texture2D = load("res://icon.png")
	if icon:
		DisplayServer.set_icon(icon.get_image())
	load_profile()
	Net.player_name = player_name
	Net.skin = skin


func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	player_name = str(cfg.get_value("hany", "name", player_name))
	skin = Skins.valid(str(cfg.get_value("hany", "skin", skin)))
	hat = str(cfg.get_value("hany", "hat", ""))
	costume = str(cfg.get_value("hany", "costume", ""))


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("hany", "name", player_name)
	cfg.set_value("hany", "skin", skin)
	cfg.set_value("hany", "hat", hat)
	cfg.set_value("hany", "costume", costume)
	cfg.save(PATH)
	Net.player_name = player_name
	Net.skin = skin
