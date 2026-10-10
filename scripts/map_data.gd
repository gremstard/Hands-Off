class_name MapData
extends RefCounted
## A Hands Off map (.hom): blocks + zones, as JSON. Shipped maps live in
## res://assets/maps, player maps in user://maps. The host sends the map to
## every client when a round starts, so any .hom works online.

const VERSION := 1
const USER_DIR := "user://maps"
const BUILTIN_DIR := "res://assets/maps"
const EXT := ".hom"

## Marker kinds
const JAIL := "jail"
const HANDER := "hander"
const RUNNER := "runner"
const TORCH := "torch"

var name := "Untitled"
## [{s: shape(int), b: block name, c: col, r: row, p: [x,y,z], ry: radians, n: [cx,cy,cz]}]
var blocks: Array = []
## [{k: kind, p: [x,y,z]}]
var markers: Array = []


static func from_json(text: String) -> MapData:
	var d = JSON.parse_string(text)
	var m := MapData.new()
	if d is Dictionary:
		m.name = str(d.get("name", "Untitled"))
		m.blocks = d.get("blocks", [])
		m.markers = d.get("markers", [])
	return m


func to_json() -> String:
	return JSON.stringify({"format": "hom", "version": VERSION, "name": name, "blocks": blocks, "markers": markers}, "\t")


static func load_file(path: String) -> MapData:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	return from_json(f.get_as_text())


func save_file(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json())
	return OK


## All maps the player can pick: built-in first, then user://maps.
static func list_maps() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dir in [BUILTIN_DIR, USER_DIR]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(EXT):
				out.append({"name": f.trim_suffix(EXT), "path": dir + "/" + f, "builtin": dir == BUILTIN_DIR})
	return out


static func user_path(map_name: String) -> String:
	return USER_DIR + "/" + map_name.validate_filename() + EXT


# ---------------------------------------------------------------- editing

func add_block(shape: int, block: String, pos: Vector3, ry: float = 0.0, cells: Vector3i = Vector3i.ONE, col: int = -1, row: int = -1) -> Dictionary:
	var e := {"s": shape, "b": block, "p": [pos.x, pos.y, pos.z], "ry": ry, "n": [cells.x, cells.y, cells.z]}
	if block == "custom":
		e["c"] = col
		e["r"] = row
	blocks.append(e)
	return e


func add_marker(kind: String, pos: Vector3) -> void:
	# single-instance kinds replace
	if kind == JAIL or kind == HANDER:
		markers = markers.filter(func(m): return m.k != kind)
	markers.append({"k": kind, "p": [pos.x, pos.y, pos.z]})


static func vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Build the map into `parent`. Returns {jail, hander, runners: [], torches: []}.
func build(parent: Node3D) -> Dictionary:
	var info := {"jail": Vector3(-27, 0.5, 27), "hander": Vector3(27, 0.5, -27), "runners": [], "torches": []}
	for b in blocks:
		var cells := Vector3i.ONE
		if b.has("n"):
			cells = Vector3i(int(b.n[0]), int(b.n[1]), int(b.n[2]))
		var body: StaticBody3D
		if str(b.get("b", "")) == "custom":
			body = Blocks.make_custom(int(b.s), int(b.get("c", 0)), int(b.get("r", 0)), cells)
		else:
			body = Blocks.make(int(b.s) as Blocks.Shape, str(b.get("b", "concrete")), cells)
		body.position = vec(b.p)
		body.rotation.y = float(b.get("ry", 0.0))
		parent.add_child(body)
	for m in markers:
		var p := vec(m.p)
		match str(m.k):
			JAIL:
				info.jail = p
			HANDER:
				info.hander = p
			RUNNER:
				info.runners.append(p)
			TORCH:
				info.torches.append(p)
	return info


## The arena you've been playing on, as data.
static func default_map() -> MapData:
	var m := MapData.new()
	m.name = "Blockyard"
	var S := Blocks.Shape
	m.add_block(S.CUBE, "grass", Vector3(0, -1, 0), 0, Vector3i(36, 1, 36))
	m.add_block(S.CUBE, "concrete", Vector3(0, 2, -37), 0, Vector3i(38, 2, 1))
	m.add_block(S.CUBE, "concrete", Vector3(0, 2, 37), 0, Vector3i(38, 2, 1))
	m.add_block(S.CUBE, "concrete", Vector3(-37, 2, 0), 0, Vector3i(1, 2, 36))
	m.add_block(S.CUBE, "concrete", Vector3(37, 2, 0), 0, Vector3i(1, 2, 36))
	m.add_block(S.COLUMN, "grey_light", Vector3(0, 1, 0), 0, Vector3i(3, 1, 3))
	m.add_block(S.SLAB, "deepred", Vector3(0, 2.5, 0), 0, Vector3i(2, 1, 2))
	m.add_block(S.RAMP, "asphalt", Vector3(0, 1, -6), 0, Vector3i(2, 1, 2))
	m.add_block(S.RAMP, "asphalt", Vector3(0, 1, 6), PI, Vector3i(2, 1, 2))
	m.add_block(S.WALL, "brick", Vector3(12, 1, 0), PI / 2, Vector3i(7, 1, 1))
	m.add_block(S.WALL, "brick", Vector3(-12, 1, 0), PI / 2, Vector3i(7, 1, 1))
	m.add_block(S.WALL, "brick", Vector3(0, 1, -12), 0, Vector3i(7, 1, 1))
	m.add_block(S.WALL, "brick", Vector3(0, 1, 12), 0, Vector3i(7, 1, 1))
	for c in [Vector2(20, 20), Vector2(-20, 20), Vector2(20, -20), Vector2(-20, -20)]:
		m.add_block(S.CUBE, "wood", Vector3(c.x, 1, c.y))
		m.add_block(S.SLAB, "wood", Vector3(c.x + 2, 1, c.y))
		m.add_block(S.STAIRS, "grey_light", Vector3(c.x, 1, c.y - 4), 0.0 if c.y > 0 else PI)
	for c in [Vector2(8, -8), Vector2(-8, 8), Vector2(26, 0), Vector2(-26, 0), Vector2(0, 26), Vector2(0, -26)]:
		m.add_block(S.PILLAR, "metal", Vector3(c.x, 1, c.y))
	m.add_block(S.SLAB, "dirt", Vector3(-16, 0, -8), 0, Vector3i(3, 1, 2))
	m.add_block(S.SLAB, "dirt", Vector3(16, 0, 8), 0, Vector3i(3, 1, 2))
	m.add_block(S.PLATFORM, "sand", Vector3(24, 0, -12), 0, Vector3i(3, 1, 3))
	m.add_block(S.PLATFORM, "sand", Vector3(-24, 0, 12), 0, Vector3i(3, 1, 3))
	m.add_block(S.CORNER, "charcoal", Vector3(30, 1, 30), 0, Vector3i(2, 1, 2))
	m.add_block(S.CORNER, "charcoal", Vector3(-30, 1, -30), PI, Vector3i(2, 1, 2))
	var jx := -28.0
	var jz := 28.0
	m.add_block(S.PLATFORM, "deepred", Vector3(jx, 0, jz), 0, Vector3i(4, 1, 4))
	m.add_block(S.CUBE, "metal", Vector3(jx - 4, 1.5, jz), 0, Vector3i(1, 2, 4))
	m.add_block(S.CUBE, "metal", Vector3(jx, 1.5, jz - 4), 0, Vector3i(4, 2, 1))
	m.add_block(S.CUBE, "metal", Vector3(jx, 1.5, jz + 4), 0, Vector3i(4, 2, 1))
	m.add_block(S.CUBE, "metal", Vector3(jx + 4, 1.5, jz - 3), 0, Vector3i(1, 2, 1))
	m.add_block(S.CUBE, "metal", Vector3(jx + 4, 1.5, jz + 3), 0, Vector3i(1, 2, 1))
	m.add_block(S.PLATFORM, "sunset", Vector3(28, 0, -28), 0, Vector3i(4, 1, 4))
	m.add_marker(JAIL, Vector3(jx, 0.5, jz))
	m.add_marker(HANDER, Vector3(28, 0.6, -28))
	m.add_marker(TORCH, Vector3(-23, 1.7, 26))
	m.add_marker(TORCH, Vector3(-23, 1.7, 30))
	for i in 8:
		var a := TAU * i / 8
		m.add_marker(RUNNER, Vector3(cos(a) * 20, 0.5, sin(a) * 20))
	return m
