uniform sampler2D mask_rgb : hint_default_black;
uniform bool rgb_mask_enabled = false;
uniform vec4 tertiary_color : source_color = vec4(1.0);

vec3 character_rgb_mask_weights(vec2 uv) {
	vec3 weights = texture(mask_rgb, uv).rgb * vec3(primary_color.a, secondary_color.a, tertiary_color.a);
	return weights / max(dot(weights, vec3(1.0)), 1.0);
}

vec3 character_rgb_tint(vec3 source, vec3 weights) {
	float value = max(source.r, max(source.g, source.b));
	vec3 palette = primary_color.rgb * weights.r + secondary_color.rgb * weights.g + tertiary_color.rgb * weights.b;
	return source * (1.0 - dot(weights, vec3(1.0))) + palette * value;
}
