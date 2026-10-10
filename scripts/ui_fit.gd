class_name UiFit
extends RefCounted
## Size a ScrollContainer to its content, capped to the screen, so panels
## are as tall as they need to be and scroll only when they must.

static func fit(scroll: ScrollContainer, content: Control, margin: float = 48.0) -> void:
	var want := content.get_combined_minimum_size().y
	var cap := scroll.get_viewport().get_visible_rect().size.y - margin
	scroll.custom_minimum_size.y = minf(want, maxf(cap, 100.0))
