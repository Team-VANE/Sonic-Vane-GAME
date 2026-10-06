shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_prepass_alpha;

uniform vec4 boom_color : source_color = vec4(0.7, 0.9, 1.0, 1.0);
uniform float boom_alpha = 1.0;
uniform float boom_progress = 0.0;
uniform float boom_max_alpha = 1.0;

uniform float edge_radius = 0.95;
uniform float edge_softness = 0.06;
uniform float fray_strength = 0.55;
uniform float fray_scale = 14.0;
uniform float fray_speed = 6.0;

uniform float edge_line_count = 48.0;
uniform float edge_line_strength = 0.45;
uniform float edge_line_sharpness = 8.0;
uniform float edge_line_speed = 6.0;

uniform float inner_start = 0.2;
uniform float inner_softness = 0.08;
uniform float inner_fray_strength = 0.25;

uniform float intersection_softness = 0.2;
uniform float intersection_strength = 1.0;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

float _hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float _noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = _hash(i);
	float b = _hash(i + vec2(1.0, 0.0));
	float c = _hash(i + vec2(0.0, 1.0));
	float d = _hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float _fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(12.5, 8.3);
	for (int i = 0; i < 4; i++) {
		v += a * _noise(p);
		p = p * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

float _linearize_depth(float depth, vec2 uv, mat4 inv_proj) {
	vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
	vec4 view = inv_proj * clip;
	return -view.z / max(view.w, 0.0001);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float ang = atan(uv.y, uv.x);

	float edge_noise = _fbm(vec2(ang * fray_scale, TIME * fray_speed));
	edge_noise = pow(edge_noise, 2.2);
	float line_wave = abs(sin(ang * edge_line_count + TIME * edge_line_speed));
	float line_mask = pow(line_wave, edge_line_sharpness) * edge_line_strength;
	float edge_fray = edge_noise * fray_strength + line_mask;
	float edge = 1.0 - smoothstep(edge_radius - edge_softness - edge_fray,
		edge_radius + edge_softness,
		r);

	float fray_noise = _fbm(uv * fray_scale + vec2(TIME * 0.8, -TIME * 0.6));
	float fray_mask = mix(1.0, smoothstep(0.35, 0.85, fray_noise), fray_strength);

	float inner_t = clamp((boom_progress - inner_start) / max(1.0 - inner_start, 0.001), 0.0, 1.0);
	float inner_radius = inner_t;
	float inner_noise = _fbm(uv * (fray_scale * 1.4) + vec2(-TIME * 1.7, TIME * 1.3));
	float inner_edge = inner_radius + inner_noise * inner_fray_strength;
	float inner_mask = smoothstep(inner_edge - inner_softness, inner_edge + inner_softness, r);

	float alpha = boom_alpha * boom_max_alpha * edge * fray_mask * inner_mask;
	alpha *= clamp(boom_color.a, 0.0, 1.0);
	float softness = max(intersection_softness, 0.0001);
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	mat4 inv_proj = inverse(PROJECTION_MATRIX);
	float scene_z = _linearize_depth(scene_depth, SCREEN_UV, inv_proj);
	float depth_fade = 1.0;
	alpha *= mix(1.0, depth_fade, clamp(intersection_strength, 0.0, 1.0));
	if (alpha <= 0.001) {
		discard;
	}

	ALBEDO = boom_color.rgb;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
