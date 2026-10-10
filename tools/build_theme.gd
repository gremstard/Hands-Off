extends SceneTree
## Generates assets/ui/theme.tres from the Kenney UI pack + fonts.
## Run: godot --headless --path . -s res://tools/build_theme.gd

const K := "res://assets/ui/kenney/"


func _init() -> void:
	var t := Theme.new()
	var font: FontFile = load("res://assets/ui/fonts/KenneyFutureNarrow.ttf")
	var font_bold: FontFile = load("res://assets/ui/fonts/KenneyFuture.ttf")
	# Kenney Future tracks letters so wide that word spaces disappear; keep it
	# for titles (type variation "Title") and use Godot's default UI font for text.
	t.default_font_size = 17
	t.add_type("Title")
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", font_bold)
	t.set_font_size("font_size", "Title", 32)

	# Buttons
	t.set_stylebox("normal", "Button", _nine(K + "grey/button_rectangle_depth_gradient.png", 14, 14, 14, 18))
	t.set_stylebox("hover", "Button", _nine(K + "blue/button_rectangle_depth_gradient.png", 14, 14, 14, 18))
	t.set_stylebox("pressed", "Button", _nine(K + "blue/button_rectangle_gradient.png", 14, 14, 14, 14))
	t.set_stylebox("disabled", "Button", _nine(K + "grey/button_rectangle_flat.png", 14, 14, 14, 14, Color(1, 1, 1, 0.5)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color(0.15, 0.15, 0.2))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.3, 0.3, 0.35, 0.7))
	t.set_font_size("font_size", "Button", 17)
	t.set_constant("h_separation", "Button", 8)

	# OptionButton inherits Button look
	for prop in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(prop, "OptionButton", t.get_stylebox(prop, "Button"))
	t.set_color("font_color", "OptionButton", Color(0.15, 0.15, 0.2))
	t.set_color("font_hover_color", "OptionButton", Color.WHITE)
	t.set_color("font_pressed_color", "OptionButton", Color.WHITE)


	# Panels
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.1, 0.11, 0.16, 0.92)
	panel.set_corner_radius_all(14)
	panel.border_color = Color(0.95, 0.85, 0.3)
	panel.set_border_width_all(3)
	panel.content_margin_left = 8
	panel.content_margin_right = 8
	panel.content_margin_top = 8
	panel.content_margin_bottom = 8
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "PopupMenu", panel)

	# LineEdit / ItemList
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0.92, 0.93, 0.96)
	field.set_corner_radius_all(8)
	field.content_margin_left = 10
	field.content_margin_right = 10
	field.content_margin_top = 6
	field.content_margin_bottom = 6
	t.set_stylebox("normal", "LineEdit", field)
	var field_focus := field.duplicate()
	field_focus.border_color = Color(0.3, 0.55, 0.95)
	field_focus.set_border_width_all(2)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", Color(0.1, 0.1, 0.15))
	t.set_color("font_placeholder_color", "LineEdit", Color(0.45, 0.45, 0.5))
	t.set_color("caret_color", "LineEdit", Color(0.1, 0.1, 0.15))
	t.set_stylebox("panel", "ItemList", field)
	t.set_color("font_color", "ItemList", Color(0.1, 0.1, 0.15))
	t.set_color("font_hovered_color", "ItemList", Color(0.1, 0.1, 0.15))
	t.set_color("font_selected_color", "ItemList", Color.WHITE)

	# Labels
	t.set_color("font_color", "Label", Color(0.96, 0.96, 0.98))

	var err := ResourceSaver.save(t, "res://assets/ui/theme.tres")
	print("theme saved: ", error_string(err))
	quit(0 if err == OK else 1)


func _nine(path: String, l: int, t: int, r: int, b: int, modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(path)
	sb.texture_margin_left = l
	sb.texture_margin_top = t
	sb.texture_margin_right = r
	sb.texture_margin_bottom = b
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	sb.modulate_color = modulate
	return sb
