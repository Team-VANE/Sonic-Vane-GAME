shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 trail_color : source_color = vec4(1.0, 0.08, 0.025, 0.9);
uniform float emission_energy : hint_range(0.0, 16.0) = 4.0;
uniform float activation_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float tail_fade_power : hint_range(0.1, 8.0) = 1.6;
uniform float head_fade_fraction : hint_range(0.0, 0.5) = 0.08;
uniform float edge_softness : hint_range(0.0, 0.5) = 0.16;

void fragment() {
	float trail_age = clamp(UV.x, 0.0, 1.0);
	float tail_fade = pow(max(1.0 - trail_age, 0.0), max(tail_fade_power, 0.1));
	float head_fade = 1.0;
	if (head_fade_fraction > 0.0) {
		head_fade = smoothstep(0.0, head_fade_fraction, trail_age);
	}
	float width_distance = abs(UV.y - 0.5) * 2.0;
	float width_fade_start = clamp(1.0 - edge_softness, 0.0, 1.0);
	float width_fade = 1.0 - smoothstep(width_fade_start, 1.0, width_distance);
	float alpha = trail_color.a * activation_alpha * tail_fade * head_fade * width_fade;

	ALBEDO = trail_color.rgb;
	EMISSION = trail_color.rgb * max(emission_energy - 1.0, 0.0);
	ALPHA = alpha;
}
