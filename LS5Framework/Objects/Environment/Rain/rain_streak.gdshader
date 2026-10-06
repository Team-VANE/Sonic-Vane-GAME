shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded, shadows_disabled, fog_disabled;

uniform vec4 rain_tint : source_color = vec4(0.72, 0.82, 0.92, 0.58);
uniform float drop_diameter : hint_range(0.001, 0.5, 0.001) = 0.02;
uniform float drop_length : hint_range(0.05, 8.0, 0.01) = 1.25;
uniform float edge_highlight_strength : hint_range(0.0, 2.0, 0.01) = 0.65;
uniform float emission_strength : hint_range(0.0, 2.0, 0.01) = 0.18;
uniform float lighting_multiplier : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float tip_softness : hint_range(0.01, 0.49, 0.01) = 0.16;
uniform float fade_in_start = 0.0;
uniform float fade_in_end = 0.01;
uniform float fade_out_start = 12.0;
uniform float fade_out_end = 23.0;

varying vec3 particle_view_position;
varying float length_gradient_position;

void vertex() {
	length_gradient_position = clamp(VERTEX.y + 0.5, 0.0, 1.0);
	VERTEX.xz *= max(drop_diameter, 0.001);
	VERTEX.y *= max(drop_length, 0.05);
	NORMAL = normalize(vec3(
		NORMAL.x / max(drop_diameter, 0.001),
		NORMAL.y / max(drop_length, 0.05),
		NORMAL.z / max(drop_diameter, 0.001)
	));
	particle_view_position = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float safe_fade_in_end = max(fade_in_end, fade_in_start + 0.001);
	float safe_fade_out_end = max(fade_out_end, fade_out_start + 0.001);
	float camera_distance = length(particle_view_position);
	float distance_fade = smoothstep(fade_in_start, safe_fade_in_end, camera_distance);
	distance_fade *= 1.0 - smoothstep(fade_out_start, safe_fade_out_end, camera_distance);
	float safe_tip_softness = clamp(tip_softness, 0.01, 0.49);
	float tip_gradient = smoothstep(0.0, safe_tip_softness, length_gradient_position);
	tip_gradient *= smoothstep(0.0, safe_tip_softness, 1.0 - length_gradient_position);
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	float center_brightness = mix(0.72, 1.0, pow(tip_gradient, 0.65));
	vec3 streak_color = rain_tint.rgb * center_brightness * lighting_multiplier;
	streak_color *= 1.0 + rim * edge_highlight_strength;
	ALBEDO = streak_color;
	EMISSION = streak_color * emission_strength;
	ALPHA = rain_tint.a * tip_gradient * distance_fade * mix(0.42, 1.0, rim);
}
