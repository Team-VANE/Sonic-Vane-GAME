shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

group_uniforms appearance;
uniform sampler2D checkered_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(0.72, 0.9, 1.0, 1.0);
uniform float base_opacity : hint_range(0.0, 1.0, 0.01) = 0.01;
uniform float interaction_opacity : hint_range(0.0, 1.0, 0.01) = 0.82;
uniform float emission_strength : hint_range(0.0, 4.0, 0.01) = 0.35;

group_uniforms mapping;
uniform float texture_scale : hint_range(0.01, 8.0, 0.01) = 0.55;
uniform float triplanar_sharpness : hint_range(1.0, 16.0, 0.1) = 8.0;
uniform vec2 scroll_direction = vec2(0.035, 0.0);
uniform float update_rate : hint_range(1.0, 240.0, 1.0) = 60.0;

group_uniforms interaction;
uniform float proximity_distance : hint_range(0.01, 200.0, 0.01) = 1.8;
uniform float proximity_falloff : hint_range(0.01, 200.0, 0.01) = 2.5;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying vec3 world_position;
varying vec3 world_normal;


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}


vec4 sample_triplanar(vec3 position, vec3 normal, vec2 offset) {
	vec3 weights = pow(abs(normal), vec3(max(triplanar_sharpness, 0.001)));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);

	vec4 x_projection = texture(checkered_texture, position.zy * texture_scale + offset);
	vec4 y_projection = texture(checkered_texture, position.xz * texture_scale + offset);
	vec4 z_projection = texture(checkered_texture, position.xy * texture_scale + offset);
	return x_projection * weights.x + y_projection * weights.y + z_projection * weights.z;
}


float get_scene_view_depth(float depth, vec2 screen_uv, mat4 inv_projection) {
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth);
	vec4 view_position = inv_projection * vec4(ndc, 1.0);
	return view_position.z / max(abs(view_position.w), 0.0001);
}


void fragment() {
	float tick_rate = max(update_rate, 1.0);
	float stepped_time = floor(TIME * tick_rate) / tick_rate;
	vec4 pattern = sample_triplanar(world_position, world_normal, scroll_direction * stepped_time);

	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	float scene_view_depth = get_scene_view_depth(scene_depth, SCREEN_UV, INV_PROJECTION_MATRIX);
	float surface_distance = abs(scene_view_depth - VERTEX.z);
	float proximity = 1.0 - smoothstep(0.0, max(proximity_distance, 0.001), surface_distance);
	proximity = pow(clamp(proximity, 0.0, 1.0), max(proximity_falloff, 0.001));

	vec3 color = pattern.rgb * tint.rgb;
	float alpha = mix(base_opacity, interaction_opacity, proximity) * pattern.a * tint.a;
	ALBEDO = color;
	EMISSION = color * emission_strength;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
