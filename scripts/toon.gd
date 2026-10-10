class_name Toon
extends RefCounted
## Factory for the cel-shaded look. Every material in the game comes
## through here so the style stays consistent and tweakable in one place.

const TOON_SHADER := preload("res://assets/shaders/toon.gdshader")
const OUTLINE_SHADER := preload("res://assets/shaders/outline.gdshader")
const TOON_CHARACTER_SHADER := preload("res://assets/shaders/toon_character.gdshader")

const DEFAULT_OUTLINE := Color(0.06, 0.05, 0.09)


static func outline(color: Color = DEFAULT_OUTLINE, width: float = 0.03) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = OUTLINE_SHADER
	m.set_shader_parameter("outline_color", color)
	m.set_shader_parameter("width", width)
	return m


## Flat-coloured or textured toon material.
static func material(color: Color, texture: Texture2D = null, uv_scale: Vector2 = Vector2.ONE,
		with_outline: bool = true, outline_color: Color = DEFAULT_OUTLINE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter("albedo_color", color)
	if texture:
		m.set_shader_parameter("albedo_texture", texture)
		m.set_shader_parameter("use_texture", true)
		m.set_shader_parameter("uv_scale", uv_scale)
	if with_outline:
		m.next_pass = outline(outline_color)
	return m


## Convert every StandardMaterial3D under `root` (an imported GLB, say) into
## toon materials, keeping their albedo colour and texture. Returns the list
## of created materials so callers can retint them later.
## Softer cel settings for characters: more steps, smoother bands, lighter
## shadow tint, so curved surfaces read as smooth like in Blender.
static func soften(m: ShaderMaterial) -> void:
	m.set_shader_parameter("steps", 5.0)
	m.set_shader_parameter("step_smoothness", 0.45)
	m.set_shader_parameter("shadow_tint_amount", 0.25)
	m.set_shader_parameter("shadow_tint", Color(0.45, 0.35, 0.5))
	m.set_shader_parameter("rim_blend", 0.2)


static func convert_scene(root: Node, outline_color: Color = DEFAULT_OUTLINE, outline_width: float = 0.03, with_outline: bool = true) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for mi in _meshes(root):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var src: Material = mi.get_active_material(s)
			var color := Color.WHITE
			var tex: Texture2D = null
			var sm: ShaderMaterial = null
			if src is StandardMaterial3D:
				color = src.albedo_color
				tex = src.albedo_texture
			elif src is ShaderMaterial and src.shader == TOON_SHADER:
				sm = src
			if sm == null:
				sm = material(color, tex, Vector2.ONE, with_outline, outline_color)
				sm.shader = TOON_CHARACTER_SHADER
				if with_outline:
					sm.next_pass.set_shader_parameter("width", outline_width)
				soften(sm)
				mi.set_surface_override_material(s, sm)
			out.append(sm)
	return out


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_meshes(c))
	return out
