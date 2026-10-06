shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D color_ramp : source_color;
uniform float scroll_speed = 20.5;
uniform float alpha = 0.80;

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * scale.x, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * scale.y, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * scale.z, 0.0),
		MODEL_MATRIX[3]
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float radius = length(UV - vec2(0.5)) * 2.0;
	float color_position = fract(radius - TIME * scroll_speed);
	ALBEDO = texture(color_ramp, vec2(color_position, 0.5)).rgb;
	ALPHA = alpha * (1.0 - smoothstep(0.82, 1.0, radius));
}
