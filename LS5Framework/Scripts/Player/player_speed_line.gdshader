shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

instance uniform vec4 line_color : source_color = vec4(1.0);
instance uniform float lifecycle_alpha : hint_range(0.0, 1.0) = 0.0;
instance uniform float surface_end_fade : hint_range(0.01, 0.49) = 0.24;
instance uniform float surface_fade_power : hint_range(0.1, 4.0) = 0.85;

varying float line_axis;

void vertex() {
	line_axis = clamp(VERTEX.z + 0.5, 0.0, 1.0);
}

void fragment() {
	float fade_distance = clamp(surface_end_fade, 0.01, 0.49);
	float front_fade = smoothstep(0.0, fade_distance, line_axis);
	float back_fade = 1.0 - smoothstep(1.0 - fade_distance, 1.0, line_axis);
	float surface_alpha = pow(max(front_fade * back_fade, 0.0), max(surface_fade_power, 0.1));

	ALBEDO = line_color.rgb;
	ALPHA = line_color.a * lifecycle_alpha * surface_alpha;
}
