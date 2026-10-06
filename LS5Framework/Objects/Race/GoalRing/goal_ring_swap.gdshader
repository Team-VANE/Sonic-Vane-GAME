shader_type spatial;
render_mode unshaded, depth_draw_opaque;

uniform sampler2D tex_flat : source_color;
uniform sampler2D tex_glow : source_color;
uniform float swap_interval = 1.0;
uniform bool use_emission = true;
// Optional external time driver (seconds). Set to a negative value to use TIME.
uniform float swap_time = -1.0;

void fragment() {
	float interval = max(swap_interval, 0.01);
	float time_value = TIME;
	if (swap_time >= 0.0) {
		time_value = swap_time;
	}
	float phase = floor(time_value / interval);
	float use_b = mod(phase, 2.0);

	vec4 color_a = texture(tex_flat, UV);
	vec4 color_b = texture(tex_glow, UV);
	vec4 color = mix(color_a, color_b, use_b);

	ALBEDO = color.rgb;
	ALPHA = 1.0;
	if (use_emission) {
		EMISSION = color.rgb;
	}
}
