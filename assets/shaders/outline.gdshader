// Inverted-hull outline, used as next_pass on toon materials.
shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.08, 1.0);
uniform float width = 0.03;
uniform bool screen_space = true;

void vertex() {
	float w = width;
	if (screen_space) {
		// keep roughly constant thickness on screen
		vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		w = width * clamp(clip.w, 0.5, 40.0) * 0.12;
	}
	VERTEX += normalize(NORMAL) * w;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
