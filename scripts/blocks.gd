class_name Blocks
extends RefCounted
## Procedural map blocks. Every block is a simple shape inside a 2 m cell,
## coloured by one vertical gradient strip of the shared palette texture
## (assets/blocks/palette.png: 36 columns x 6 rows of strips). Exactly what
## the hand-exported block GLBs do, minus the 540 KB of embedded texture each.

const CELL := 2.0
const COLS := 36
const ROWS := 6
## How far inside a strip we sample (avoids bleeding into neighbours).
const U_INSET := 0.3
const V_INSET := 0.03

const PALETTE_PATH := "res://assets/blocks/palette.png"

enum Shape { CUBE, SLAB, PLATFORM, WALL, RAMP, STAIRS, CORNER, PILLAR, COLUMN }
const SHAPE_NAMES := ["Cube", "Slab", "Platform", "Wall", "Ramp", "Stairs", "Corner", "Pillar", "Column"]

## Named presets -> [column, row] in the palette grid. Measured from the
## blocks you exported; add your own here.
const TYPES := {
	"concrete": [4, 5],
	"asphalt": [8, 5],
	"metal": [16, 5],
	"dirt": [14, 2],
	"grass": [11, 4],
	"deepred": [14, 3],
	"black": [0, 5],
	"charcoal": [2, 5],
	"grey_dark": [7, 5],
	"grey": [14, 5],
	"grey_light": [13, 5],
	"white": [31, 5],
	"stone": [19, 4],
	"sand": [20, 5],
	"beige": [25, 5],
	"brick": [24, 5],
	"wood": [21, 5],
	"wood_dark": [26, 5],
	"rust": [21, 2],
	"mud": [13, 2],
	"water": [28, 0],
	"sky": [5, 0],
	"teal": [15, 1],
	"navy": [25, 3],
	"blueberry": [24, 3],
	"purple": [4, 2],
	"pink": [28, 4],
	"lime": [11, 0],
	"forest": [24, 2],
	"mint": [10, 4],
	"cucumber": [6, 4],
	"gold": [4, 3],
	"banana": [10, 1],
	"orange": [12, 4],
	"peach": [23, 0],
	"sunset": [8, 0],
	"cherry": [33, 1],
}

static var _palette: Texture2D = null
static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}


static func palette() -> Texture2D:
	if _palette == null:
		_palette = load(PALETTE_PATH)
	return _palette


## Toon material that samples one strip. Mesh UVs are expected in 0..1,
## with v = 0 at the top of the shape.
static func material(col: int, row: int) -> ShaderMaterial:
	col = clampi(col, 0, COLS - 1)
	row = clampi(row, 0, ROWS - 1)
	var key := col * 100 + row
	if _mat_cache.has(key):
		return _mat_cache[key]
	var pw := 1.0 / COLS
	var ph := 1.0 / ROWS
	var m := Toon.material(Color.WHITE, palette(), Vector2(pw * (1.0 - 2.0 * U_INSET), ph * (1.0 - 2.0 * V_INSET)))
	m.set_shader_parameter("uv_offset", Vector2(col * pw + pw * U_INSET, row * ph + ph * V_INSET))
	m.next_pass.set_shader_parameter("width", 0.02)
	_mat_cache[key] = m
	return m


static func material_named(type_name: String) -> ShaderMaterial:
	var cr: Array = TYPES.get(type_name, TYPES["concrete"])
	return material(cr[0], cr[1])


## Mesh for a shape, stretched over `cells` (only meaningful for box-like
## shapes; others ignore x/z stretch). Origin at the cell centre, so a
## 1x1x1 cube spans -1..1 on every axis like the exported blocks.
static func mesh(shape: Shape, cells: Vector3i = Vector3i.ONE) -> ArrayMesh:
	cells = Vector3i(maxi(cells.x, 1), maxi(cells.y, 1), maxi(cells.z, 1))
	var key := "%d_%d_%d_%d" % [shape, cells.x, cells.y, cells.z]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := CELL * cells.x / 2.0
	var hy := CELL * cells.y / 2.0
	var hz := CELL * cells.z / 2.0
	match shape:
		Shape.CUBE:
			_box(st, Vector3(-hx, -hy, -hz), Vector3(hx, hy, hz))
		Shape.SLAB:
			_box(st, Vector3(-hx, -hy, -hz), Vector3(hx, -hy + CELL * 0.5, hz))
		Shape.PLATFORM:
			_box(st, Vector3(-hx, -hy, -hz), Vector3(hx, -hy + CELL * 0.15, hz))
		Shape.WALL:
			_box(st, Vector3(-hx, -hy, -CELL * 0.15), Vector3(hx, hy, CELL * 0.15))
		Shape.RAMP:
			# rises towards -Z; walk up it from +Z
			_prism(st, [Vector3(0, -hy, hz), Vector3(0, -hy, -hz), Vector3(0, hy, -hz)], -hx, hx)
		Shape.STAIRS:
			var steps := 4
			for i in steps:
				var z0 := hz - (i + 1) * (2.0 * hz / steps)
				var y1 := -hy + (i + 1) * (2.0 * hy / steps)
				_box(st, Vector3(-hx, -hy, -hz), Vector3(hx, y1, z0 + (2.0 * hz / steps)))
		Shape.CORNER:
			# triangular prism filling the -X/-Z corner (an outside wedge)
			_prism_corner(st, hx, hy, hz)
		Shape.PILLAR:
			_cylinder(st, CELL * 0.3, -hy, hy, 20)
		Shape.COLUMN:
			_cylinder(st, hx, -hy, hy, 32)
	var am := st.commit()
	_mesh_cache[key] = am
	return am


static func make_custom(shape: Shape, col: int, row: int, cells: Vector3i = Vector3i.ONE) -> StaticBody3D:
	var body := make(shape, "concrete", cells)
	(body.get_child(0) as MeshInstance3D).material_override = material(col, row)
	return body


## Build a ready StaticBody3D (mesh + collision) for code-driven maps.
static func make(shape: Shape, type_name: String, cells: Vector3i = Vector3i.ONE) -> StaticBody3D:
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(shape, cells)
	mi.material_override = material_named(type_name)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_trimesh_shape()
	body.add_child(cs)
	body.set_meta("surface", surface_of(type_name))
	return body


## Footstep surface for a block colour.
static func surface_of(type_name: String) -> String:
	if type_name in ["grass", "lime", "forest", "mint", "cucumber"]:
		return "grass"
	if type_name in ["wood", "wood_dark", "brick"]:
		return "wood"
	if type_name in ["metal", "silver", "charcoal", "black"]:
		return "metal"
	if type_name in ["dirt", "mud", "sand", "beige", "rust"]:
		return "dirt"
	return "concrete"


# ---------------------------------------------------------------- geometry
# All helpers emit flat-shaded faces with v = 0 at the shape's top.
# Godot front faces are CLOCKWISE when seen from outside; every triangle
# below is written that way and the normal is derived to match.

static var _ymin := 0.0
static var _ymax := 1.0


static func _uv(p: Vector3) -> Vector2:
	var v := 1.0 - clampf((p.y - _ymin) / maxf(_ymax - _ymin, 0.001), 0.0, 1.0)
	return Vector2(0.5, v)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (c - a).cross(b - a).normalized()
	for p in [a, b, c]:
		st.set_normal(n)
		st.set_uv(_uv(p))
		st.add_vertex(p)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


static func _box(st: SurfaceTool, mn: Vector3, mx: Vector3) -> void:
	_ymin = mn.y
	_ymax = mx.y
	var p := [
		Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z),
		Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z),
	]
	_quad(st, p[4], p[5], p[6], p[7]) # top
	_quad(st, p[3], p[2], p[1], p[0]) # bottom
	_quad(st, p[0], p[1], p[5], p[4]) # -z
	_quad(st, p[2], p[3], p[7], p[6]) # +z
	_quad(st, p[3], p[0], p[4], p[7]) # -x
	_quad(st, p[1], p[2], p[6], p[5]) # +x


## Triangle profile (in the YZ plane) extruded along X from x0 to x1.
static func _prism(st: SurfaceTool, tri: Array, x0: float, x1: float) -> void:
	_ymin = minf(tri[0].y, minf(tri[1].y, tri[2].y))
	_ymax = maxf(tri[0].y, maxf(tri[1].y, tri[2].y))
	var a: Array[Vector3] = []
	var b: Array[Vector3] = []
	for t in tri:
		a.append(Vector3(x0, t.y, t.z))
		b.append(Vector3(x1, t.y, t.z))
	_tri(st, a[0], a[1], a[2]) # -x cap
	_tri(st, b[0], b[2], b[1]) # +x cap
	for i in 3:
		var j := (i + 1) % 3
		_quad(st, a[i], b[i], b[j], a[j])


static func _prism_corner(st: SurfaceTool, hx: float, hy: float, hz: float) -> void:
	_ymin = -hy
	_ymax = hy
	var a0 := Vector3(-hx, -hy, -hz)
	var a1 := Vector3(hx, -hy, -hz)
	var a2 := Vector3(-hx, -hy, hz)
	var b0 := a0 + Vector3(0, 2 * hy, 0)
	var b1 := a1 + Vector3(0, 2 * hy, 0)
	var b2 := a2 + Vector3(0, 2 * hy, 0)
	_tri(st, a0, a2, a1) # bottom
	_tri(st, b0, b1, b2) # top
	_quad(st, a0, a1, b1, b0) # -z side
	_quad(st, a2, a0, b0, b2) # -x side
	_quad(st, a1, a2, b2, b1) # diagonal


static func _cylinder(st: SurfaceTool, r: float, y0: float, y1: float, segs: int) -> void:
	_ymin = y0
	_ymax = y1
	var top := Vector3(0, y1, 0)
	var bot := Vector3(0, y0, 0)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := Vector3(cos(a0) * r, y0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, y0, sin(a1) * r)
		var q0 := p0 + Vector3(0, y1 - y0, 0)
		var q1 := p1 + Vector3(0, y1 - y0, 0)
		_tri(st, top, q0, q1)
		_tri(st, bot, p1, p0)
		# smooth side normals
		var n0 := Vector3(cos(a0), 0, sin(a0))
		var n1 := Vector3(cos(a1), 0, sin(a1))
		for v in [[p0, n0], [p1, n1], [q1, n1], [p0, n0], [q1, n1], [q0, n0]]:
			st.set_normal(v[1])
			st.set_uv(_uv(v[0]))
			st.add_vertex(v[0])
