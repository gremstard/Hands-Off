@tool
class_name Block
extends StaticBody3D
## A map block you place in the editor. Pick a shape and a colour, stretch
## with `cells`, snap to the 2 m grid (Transform snap: 2). Rebuilds itself
## live in the editor and at runtime.

@export var shape: Blocks.Shape = Blocks.Shape.CUBE:
	set(v):
		shape = v
		_rebuild()
@export_enum("concrete", "asphalt", "metal", "dirt", "grass", "deepred", "black", "charcoal", "grey_dark", "grey", "grey_light", "white", "stone", "sand", "beige", "brick", "wood", "wood_dark", "rust", "mud", "water", "sky", "teal", "navy", "blueberry", "purple", "pink", "lime", "forest", "mint", "cucumber", "gold", "banana", "orange", "peach", "sunset", "cherry", "custom")
var block: String = "concrete":
	set(v):
		block = v
		_rebuild()
## Used when block == "custom": any strip of the palette (0..35, 0..5).
@export var palette_col: int = 4:
	set(v):
		palette_col = v
		_rebuild()
@export var palette_row: int = 5:
	set(v):
		palette_row = v
		_rebuild()
## Stretch box-like shapes over several cells (x, y, z).
@export var cells: Vector3i = Vector3i.ONE:
	set(v):
		cells = v
		_rebuild()

var _mesh: MeshInstance3D
var _col: CollisionShape3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.name = "Mesh"
		add_child(_mesh)
		_col = CollisionShape3D.new()
		_col.name = "Collision"
		add_child(_col)
	_mesh.mesh = Blocks.mesh(shape, cells)
	if block == "custom":
		_mesh.material_override = Blocks.material(palette_col, palette_row)
	else:
		_mesh.material_override = Blocks.material_named(block)
	_col.shape = _mesh.mesh.create_trimesh_shape()
