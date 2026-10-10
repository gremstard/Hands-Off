extends Node3D
## Greybox arena built in code. Replace with your modelled map later - keep
## the same public API (spawn_players, get_player_node, remove_player,
## jail_position) and swap the geometry.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
## Block-built map (scenes/maps/main.tscn). If it's missing the code greybox is used.
const MAP_SCENE := "res://scenes/maps/main.tscn"
const HUD_SCENE := preload("res://scripts/hud.gd")

const HALF := 35.0 # arena half-size
const WALL_H := 5.0
const JAIL_CENTER := Vector3(-27, 0, 27)
const JAIL_SIZE := 8.0
const SEEKER_SPAWN := Vector3(27, 0, -27)

const PALETTE: Array[Color] = [
	Color(0.85, 0.8, 0.75), Color(0.9, 0.75, 0.65), Color(0.75, 0.9, 0.8),
	Color(0.95, 0.9, 0.7), Color(0.8, 0.75, 0.95),
]

## How much of the photo texture shows through the flat cel colour.
const TEXTURE_MIX := 0.45
const TEX := "res://assets/textures/"
const SKYBOX := "res://assets/skyboxes/skybox-day.png"
const FIRE_SCENE := "res://assets/BinbunVFX_Vol2/FlameFX/effects/fire/vfx_basic_fire_01.tscn"

var tex_floor: Texture2D = load(TEX + "Grass/Grass_03.png")
var tex_wall: Texture2D = load(TEX + "Bricks/Bricks_04.png")
var tex_ring: Texture2D = load(TEX + "Stone/Stone_04.png")
var tex_wood: Texture2D = load(TEX + "Wood/Wood_06.png")
var tex_metal: Texture2D = load(TEX + "Metal/Metal_03.png")
var tex_tile: Texture2D = load(TEX + "Tile/Tile_05.png")
var tex_plaster: Texture2D = load(TEX + "Plaster/Plaster_04.png")

@onready var players_root: Node3D = $Players
var _color_i := 0
var _map: Node3D = null
var _hider_spawns: Array[Vector3] = []
var _seeker_pos: Vector3 = SEEKER_SPAWN
var _jail: Vector3 = JAIL_CENTER


func _ready() -> void:
	_build_environment()
	var data: MapData = Game.current_map()
	if data:
		_build_map(data)
	else:
		_build_geometry()
	add_child(HUD_SCENE.new())
	Game.arena_ready(self)


func _build_map(data: MapData) -> void:
	_map = Node3D.new()
	_map.name = "Map"
	add_child(_map)
	var info := data.build(_map)
	_jail = info.jail
	_seeker_pos = info.hander
	for r in info.runners:
		_hider_spawns.append(r)
	for t in info.torches:
		_fire(t)
	var jail_label := Label3D.new()
	jail_label.text = "JAIL"
	jail_label.position = _jail + Vector3(0, 4, 0)
	jail_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	jail_label.font_size = 96
	jail_label.pixel_size = 0.01
	jail_label.modulate = Color(1, 0.4, 0.4)
	add_child(jail_label)


func _load_map() -> void:
	var scene: PackedScene = load(MAP_SCENE)
	_map = scene.instantiate()
	add_child(_map)
	var markers := _map.get_node_or_null("Markers")
	if markers:
		for m in markers.get_children():
			if not (m is Node3D):
				continue
			var n: String = m.name
			if n.begins_with("HiderSpawn"):
				_hider_spawns.append(m.global_position)
			elif n == "SeekerSpawn":
				_seeker_pos = m.global_position
			elif n == "JailCenter":
				_jail = m.global_position
			elif n.begins_with("Torch"):
				_fire(m.global_position)
	var jail_label := Label3D.new()
	jail_label.text = "JAIL"
	jail_label.position = _jail + Vector3(0, 4, 0)
	jail_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	jail_label.font_size = 96
	jail_label.pixel_size = 0.01
	jail_label.modulate = Color(1, 0.4, 0.4)
	add_child(jail_label)


# ---------------------------------------------------------------- public

func spawn_players(players: Dictionary) -> void:
	var ids := players.keys()
	ids.sort()
	var hider_i := 0
	var seeker_i := 0
	var hider_total := 0
	for id in ids:
		if players[id].team != Game.Team.SEEKER:
			hider_total += 1
	for id in ids:
		if get_player_node(id):
			continue
		var p := PLAYER_SCENE.instantiate()
		p.name = str(id)
		var pos: Vector3
		if players[id].team == Game.Team.SEEKER:
			pos = _seeker_spawn(seeker_i)
			seeker_i += 1
		else:
			pos = _hider_spawn(hider_i, maxi(hider_total, 1))
			hider_i += 1
		p.position = pos
		players_root.add_child(p)
		p.look_at(Vector3(0, pos.y, 0), Vector3.UP, true)


func get_player_node(id: int) -> Node3D:
	return players_root.get_node_or_null(str(id)) as Node3D


func remove_player(id: int) -> void:
	var n := get_player_node(id)
	if n:
		n.queue_free()


func jail_position() -> Vector3:
	return _jail + Vector3(0, 0.5, 0)


# ---------------------------------------------------------------- spawns

func _hider_spawn(i: int, total: int) -> Vector3:
	if not _hider_spawns.is_empty():
		return _hider_spawns[i % _hider_spawns.size()] + Vector3(0, 0, 0.6 * float(i / _hider_spawns.size()))
	var ang := TAU * float(i) / float(total)
	return Vector3(cos(ang) * 20.0, 0.5, sin(ang) * 20.0)


func _seeker_spawn(i: int) -> Vector3:
	# Handers start locked in the jail for the head start.
	var ox := float(i % 3) * 1.5 - 1.5
	var oz := float(i / 3) * 1.5 - 1.5
	return _jail + Vector3(ox, 0.5, oz)


# ---------------------------------------------------------------- building

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	add_child(sun)

	var sky := Sky.new()
	var pano: Texture2D = load(SKYBOX)
	if pano:
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = pano
		pm.filter = true
		sky.sky_material = pm
	else:
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(0.35, 0.55, 0.9)
		sky_mat.sky_horizon_color = Color(0.75, 0.82, 0.9)
		sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.0012
	env.fog_light_color = Color(0.8, 0.85, 0.95)
	env.ssao_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_geometry() -> void:
	var floor_c := Color(0.62, 0.85, 0.5)
	var wall_c := Color(0.9, 0.85, 0.8)
	# Floor + perimeter
	_box(Vector3(0, -0.5, 0), Vector3(HALF * 2, 1, HALF * 2), floor_c, tex_floor, 0.15)
	_box(Vector3(0, WALL_H / 2, -HALF), Vector3(HALF * 2 + 1, WALL_H, 1), wall_c, tex_wall, 0.4)
	_box(Vector3(0, WALL_H / 2, HALF), Vector3(HALF * 2 + 1, WALL_H, 1), wall_c, tex_wall, 0.4)
	_box(Vector3(-HALF, WALL_H / 2, 0), Vector3(1, WALL_H, HALF * 2 + 1), wall_c, tex_wall, 0.4)
	_box(Vector3(HALF, WALL_H / 2, 0), Vector3(1, WALL_H, HALF * 2 + 1), wall_c, tex_wall, 0.4)

	# Central block and ring walls with corner gaps
	_box(Vector3(0, 1.5, 0), Vector3(6, 3, 6), Color(0.95, 0.9, 0.85), tex_plaster, 0.5)
	_box(Vector3(12, 1.5, 0), Vector3(1, 3, 14), Color.WHITE, tex_ring, 0.5)
	_box(Vector3(-12, 1.5, 0), Vector3(1, 3, 14), Color.WHITE, tex_ring, 0.5)
	_box(Vector3(0, 1.5, 12), Vector3(14, 3, 1), Color.WHITE, tex_ring, 0.5)
	_box(Vector3(0, 1.5, -12), Vector3(14, 3, 1), Color.WHITE, tex_ring, 0.5)

	# Crates and cover scattered around
	var crates := [
		[Vector3(20, 0, 20), Vector3(3, 2, 3)], [Vector3(23, 0, 17), Vector3(2, 1, 2)],
		[Vector3(-20, 0, 18), Vector3(4, 2, 2)], [Vector3(20, 0, -18), Vector3(2, 4, 2)],
		[Vector3(-20, 0, -20), Vector3(3, 1.5, 3)], [Vector3(-24, 0, 5), Vector3(2, 2, 6)],
		[Vector3(24, 0, -5), Vector3(2, 2, 6)], [Vector3(5, 0, 24), Vector3(6, 2, 2)],
		[Vector3(-5, 0, -24), Vector3(6, 2, 2)], [Vector3(28, 0, 10), Vector3(3, 3, 3)],
		[Vector3(-28, 0, -10), Vector3(3, 3, 3)], [Vector3(10, 0, -28), Vector3(3, 3, 3)],
		[Vector3(-10, 0, 28), Vector3(3, 3, 3)], [Vector3(6, 0, -6), Vector3(1, 5, 1)],
		[Vector3(-6, 0, 6), Vector3(1, 5, 1)], [Vector3(30, 0, 30), Vector3(2, 2.5, 2)],
		[Vector3(-30, 0, -30), Vector3(2, 2.5, 2)], [Vector3(16, 0, 8), Vector3(2, 1, 4)],
		[Vector3(-16, 0, -8), Vector3(2, 1, 4)],
	]
	var ci := 0
	for c in crates:
		var size: Vector3 = c[1]
		var t := tex_wood if ci % 3 != 2 else tex_metal
		_box(c[0] + Vector3(0, size.y / 2, 0), size, PALETTE[ci % PALETTE.size()], t, 0.6)
		ci += 1

	# Staircase up to a small platform
	for i in 3:
		var h := 1.0 * (i + 1)
		_box(Vector3(15 + i * 2, h / 2, -8), Vector3(2, h, 2), Color.WHITE, tex_ring, 0.5)
	_box(Vector3(21.5, 1.5, -8), Vector3(5, 3, 2), Color.WHITE, tex_ring, 0.5)

	# Jail: three solid walls, one wall with a doorway, dark floor
	var jail_c := Color(0.85, 0.78, 0.8)
	var hs := JAIL_SIZE / 2
	_box(JAIL_CENTER + Vector3(0, 0.05, 0), Vector3(JAIL_SIZE, 0.1, JAIL_SIZE), Color(0.55, 0.3, 0.3), tex_tile, 0.5)
	_box(JAIL_CENTER + Vector3(-hs, 1.5, 0), Vector3(0.5, 3, JAIL_SIZE), jail_c, tex_metal, 0.5)
	_box(JAIL_CENTER + Vector3(0, 1.5, hs), Vector3(JAIL_SIZE, 3, 0.5), jail_c, tex_metal, 0.5)
	_box(JAIL_CENTER + Vector3(0, 1.5, -hs), Vector3(JAIL_SIZE, 3, 0.5), jail_c, tex_metal, 0.5)
	# doorway on the +X side facing the arena centre
	_box(JAIL_CENTER + Vector3(hs, 1.5, -hs / 2 - 0.5), Vector3(0.5, 3, hs - 1), jail_c, tex_metal, 0.5)
	_box(JAIL_CENTER + Vector3(hs, 1.5, hs / 2 + 0.5), Vector3(0.5, 3, hs - 1), jail_c, tex_metal, 0.5)
	# torches either side of the jail door
	_fire(JAIL_CENTER + Vector3(hs + 0.8, 1.7, -1.6))
	_fire(JAIL_CENTER + Vector3(hs + 0.8, 1.7, 1.6))
	var jail_label := Label3D.new()
	jail_label.text = "JAIL"
	jail_label.position = JAIL_CENTER + Vector3(0, 4, 0)
	jail_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	jail_label.font_size = 96
	jail_label.pixel_size = 0.01
	jail_label.modulate = Color(1, 0.4, 0.4)
	add_child(jail_label)

	# Seeker start pad
	_box(SEEKER_SPAWN + Vector3(0, 0.05, 0), Vector3(8, 0.1, 8), Color(0.9, 0.5, 0.4), tex_tile, 0.5)


func _fire(pos: Vector3) -> void:
	var scene: PackedScene = load(FIRE_SCENE)
	if scene == null:
		return
	var f := scene.instantiate()
	f.position = pos
	f.scale = Vector3.ONE * 0.9
	add_child(f)
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.1
	cm.height = 1.6
	pole.mesh = cm
	pole.position = pos + Vector3(0, -0.9, 0)
	pole.material_override = Toon.material(Color(0.35, 0.25, 0.2))
	add_child(pole)


func _box(pos: Vector3, size: Vector3, color: Color = Color.TRANSPARENT, tex: Texture2D = null, tex_scale: float = 0.5) -> StaticBody3D:
	if color == Color.TRANSPARENT:
		color = PALETTE[_color_i % PALETTE.size()]
		_color_i += 1
	var body := StaticBody3D.new()
	body.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := Toon.material(color, tex)
	if tex:
		mat.set_shader_parameter("use_triplanar", true)
		mat.set_shader_parameter("triplanar_scale", tex_scale)
		mat.set_shader_parameter("texture_mix", TEXTURE_MIX)
	mat.next_pass.set_shader_parameter("width", 0.02)
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	add_child(body)
	return body
