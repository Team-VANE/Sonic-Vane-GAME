shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D frame_01 : source_color, filter_linear, repeat_disable;
uniform sampler2D frame_02 : source_color, filter_linear, repeat_disable;
uniform sampler2D frame_03 : source_color, filter_linear, repeat_disable;
uniform float brightness : hint_range(0.0, 4.0) = 1.3;
varying float particle_age;

void vertex() {
	particle_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
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
	vec4 flame;
	if (particle_age < 1.0 / 3.0) {
		flame = texture(frame_01, UV);
	} else if (particle_age < 2.0 / 3.0) {
		flame = texture(frame_02, UV);
	} else {
		flame = texture(frame_03, UV);
	}
	ALBEDO = flame.rgb * COLOR.rgb * brightness;
	ALPHA = flame.a * COLOR.a * (1.0 - smoothstep(0.8, 1.0, particle_age));
}
