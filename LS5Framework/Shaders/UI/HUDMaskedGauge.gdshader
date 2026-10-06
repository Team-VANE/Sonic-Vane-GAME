shader_type canvas_item;

uniform vec4 background_color : source_color = vec4(0.02, 0.06, 0.15, 1.0);
uniform vec4 fill_color : source_color = vec4(0.1, 0.5, 1.0, 1.0);
uniform vec4 feedback_color : source_color = vec4(1.0);
uniform float feedback_strength : hint_range(0.0, 1.0) = 0.0;
uniform float feedback_glow : hint_range(0.0, 1.0) = 0.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform int gauge_type = 0;

void fragment() {
	float mask = texture(TEXTURE, UV).a;
	float speed_position = clamp((UV.x - 0.037) / 0.77, 0.0, 1.0);
	float barrier_position = clamp((0.95 - UV.y) / 0.59, 0.0, 1.0);
	vec3 ramp = mix(vec3(0.06, 0.43, 1.0), vec3(0.05, 0.9, 0.2), smoothstep(0.0, 0.38, speed_position));
	ramp = mix(ramp, vec3(1.0, 0.88, 0.05), smoothstep(0.38, 0.72, speed_position));
	ramp = mix(ramp, vec3(1.0, 0.12, 0.06), smoothstep(0.72, 1.0, speed_position));
	float filled = 0.0;
	vec3 colour = ramp;
	if (gauge_type == 0) {
		filled = step(speed_position, progress) * step(0.001, progress);
		colour = mix(colour, feedback_color.rgb, feedback_strength);
		colour += feedback_color.rgb * feedback_glow * feedback_strength;
	} else if (gauge_type == 1) {
		filled = step(barrier_position, progress) * step(0.001, progress);
		colour = fill_color.rgb;
	}
	COLOR = vec4(mix(background_color.rgb, colour, filled), mask);
}
