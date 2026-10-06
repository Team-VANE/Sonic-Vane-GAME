shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;
stencil_mode write, compare_always, 32;

group_uniforms Appearance;
/** Pupil image composited over the sclera using its alpha channel. */
uniform sampler2D pupil_texture : source_color, filter_linear_mipmap, repeat_disable;
/** Opaque base color outside the projected pupils. */
uniform vec4 sclera_color : source_color = vec4(1.0);
/** Surface metallic response. */
uniform float metallic : hint_range(0.0, 1.0) = 0.186;
/** Surface roughness. */
uniform float roughness : hint_range(0.0, 1.0) = 0.273;
/** Dielectric specular response. */
uniform float specular : hint_range(0.0, 1.0) = 0.5;

group_uniforms Projection;
/** Projector-local axis mapped to the image's horizontal coordinate. */
uniform vec3 horizontal_axis = vec3(1.0, 0.0, 0.0);
/** Projector-local axis mapped to the image's vertical coordinate. */
uniform vec3 vertical_axis = vec3(0.0, 1.0, 0.0);
/** Left image mapping scale; negative components mirror the projection. */
uniform vec2 left_scale = vec2(1.0);
/** Right image mapping scale; negative components mirror the projection. */
uniform vec2 right_scale = vec2(1.0);
/** Left image origin in texture coordinates. */
uniform vec2 left_offset = vec2(0.5);
/** Right image origin in texture coordinates. */
uniform vec2 right_offset = vec2(0.5);
/** Converts bottom-origin image coordinates to Godot texture coordinates. */
uniform bool flip_vertical = true;

group_uniforms Runtime;
/** World-to-projector transform supplied by CharacterEyeProjection. */
uniform mat4 world_to_left = mat4(1.0);
/** World-to-projector transform supplied by CharacterEyeProjection. */
uniform mat4 world_to_right = mat4(1.0);
/** Enables each pupil only while its projector transform is available. */
uniform vec2 projector_enabled = vec2(0.0);

vec4 sample_pupil(vec3 position, vec2 mapping_scale, vec2 offset) {
	vec2 coordinates = vec2(dot(position, horizontal_axis), dot(position, vertical_axis));
	vec2 pupil_uv = coordinates * mapping_scale + offset;
	if (flip_vertical) {
		pupil_uv.y = 1.0 - pupil_uv.y;
	}
	vec4 pupil = texture(pupil_texture, pupil_uv);
	vec2 inside = step(vec2(0.0), pupil_uv) * step(pupil_uv, vec2(1.0));
	pupil.a *= inside.x * inside.y;
	return pupil;
}

void fragment() {
	vec4 world_position = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 left_pupil = sample_pupil((world_to_left * world_position).xyz, left_scale, left_offset);
	vec4 right_pupil = sample_pupil((world_to_right * world_position).xyz, right_scale, right_offset);
	vec3 color = mix(sclera_color.rgb, right_pupil.rgb, right_pupil.a * projector_enabled.y);
	ALBEDO = mix(color, left_pupil.rgb, left_pupil.a * projector_enabled.x);
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
