shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D color_ramp : source_color;
uniform float scroll_speed = 18.00;
instance uniform float phase = 0.0;

void fragment() {
	float length_t = clamp(UV.y * 2.0, 0.0, 1.0);
	float progress = fract(1.0 - length_t + TIME * scroll_speed + phase);
	float activity = fract(length_t - TIME * scroll_speed + phase);
	float active = smoothstep(0.04, 0.12, activity) * (1.0 - smoothstep(0.52, 0.62, activity));
	float outer_fade = smoothstep(0.0, 0.35, length_t);
	float center_fade = pow(1.0 - smoothstep(0.30, 0.82, length_t), 2.0);
	ALBEDO = texture(color_ramp, vec2(progress, 0.5)).rgb;
	ALPHA = active * outer_fade * center_fade;
}
