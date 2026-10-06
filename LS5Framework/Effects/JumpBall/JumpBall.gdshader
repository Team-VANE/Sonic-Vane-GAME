shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_prepass_alpha;

uniform vec4 jump_ball_color : source_color = vec4(0.2, 0.8, 1.0, 0.72);
uniform float jump_ball_alpha = 1.0;
uniform float tail_fade_strength = 0.0;
uniform vec3 tail_fade_axis = vec3(0.0, 0.0, -1.0);
uniform float tail_fade_start = 0.18;
uniform float tail_fade_length = 1.35;
uniform float tail_min_alpha = 0.08;
uniform float rim_strength = 0.22;

varying float local_tail;

void vertex() {
	vec3 axis = normalize(tail_fade_axis);
	local_tail = clamp((dot(VERTEX, axis) - tail_fade_start) / max(tail_fade_length, 0.001), 0.0, 1.0);
}

void fragment() {
	float tail_alpha = mix(1.0, tail_min_alpha, local_tail * tail_fade_strength);
	float rim = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.0);
	float alpha = jump_ball_color.a * jump_ball_alpha * tail_alpha;
	alpha += rim * rim_strength * jump_ball_alpha * jump_ball_color.a * tail_alpha;
	if (alpha <= 0.001) {
		discard;
	}
	ALBEDO = jump_ball_color.rgb;
	EMISSION = jump_ball_color.rgb * 0.35;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
