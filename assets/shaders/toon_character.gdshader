// Hands Off cel shader. Derived from Binbun's "stylized" shader (kept as
// stylized.gdshader for reference) with: uv_scale, pattern off by default,
// and a safe default when no texture is bound.
shader_type spatial;
render_mode cull_disabled; // characters: no holes from stray back faces

group_uniforms Albedo;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform float texture_mix : hint_range(0.0, 1.0, 0.05) = 1.0; // 0 = flat colour, 1 = full texture
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform bool use_triplanar = false;   // world-space mapping, ignores mesh UVs
uniform float triplanar_scale = 0.25; // texture repeats per metre
uniform float triplanar_sharpness = 8.0;

group_uniforms Light;
uniform float steps = 3.0;
uniform float step_smoothness : hint_range(0.0, 1.0, 0.05) = 0.15;
uniform vec4 shadow_tint : source_color = vec4(0.25, 0.2, 0.4, 1.0);
uniform float shadow_tint_amount : hint_range(0.0, 1.0, 0.1) = 0.5;
uniform float specular : hint_range(0.0, 1.0, 0.05) = 0.0;

group_uniforms Rim;
uniform bool use_rim = true;
uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim_amount = 2.5;
uniform float rim_smoothness = 0.2;
uniform float rim_blend : hint_range(0.0, 1.0, 0.05) = 0.35;

varying vec3 world_pos;
varying vec3 world_nrm;

vec4 triplanar(sampler2D tex, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(triplanar_sharpness));
	w /= (w.x + w.y + w.z);
	vec4 x = texture(tex, p.zy * triplanar_scale);
	vec4 y = texture(tex, p.xz * triplanar_scale);
	vec4 z = texture(tex, p.xy * triplanar_scale);
	return x * w.x + y * w.y + z * w.z;
}

float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 albedo = albedo_color;
	if (use_texture) {
		vec4 t;
		if (use_triplanar) {
			t = triplanar(albedo_texture, world_pos, world_nrm);
		} else {
			t = texture(albedo_texture, UV * uv_scale + uv_offset);
		}
		albedo *= mix(vec4(1.0), t, texture_mix);
	}
	ALBEDO = albedo.rgb;
	SPECULAR = specular;
}

void light() {
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float light_mult = ndotl * steps;
	float step_base = floor(light_mult);
	float light_factor = smoothstep(0.5 - step_smoothness, 0.5 + step_smoothness, light_mult - step_base);
	float lit = (step_base + light_factor) / steps;

	vec3 diffuse = vec3(lit) * (LIGHT_COLOR / PI);
	diffuse = (shadow_tint.rgb * (1.0 - lit) * shadow_tint_amount) + diffuse * lit;

	if (use_rim) {
		float rim_value = fresnel(rim_amount, NORMAL, VIEW);
		rim_value = smoothstep(0.5 - (rim_smoothness / 2.0), 0.5 + (rim_smoothness / 2.0), rim_value);
		rim_value *= lit;
		diffuse += rim_color.rgb * rim_value * rim_blend;
	}

	DIFFUSE_LIGHT += ALBEDO * diffuse;
	SPECULAR_LIGHT += vec3(pow(lit, 50.0)) * specular;
}
