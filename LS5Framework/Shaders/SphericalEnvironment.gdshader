shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

group_uniforms Environment;
/** Spherical environment or matcap image. */
uniform sampler2D environment_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_disable;
/** Reflection color multiplier. */
uniform vec4 reflection_tint : source_color = vec4(1.0);
/** Reflection coverage before masking and Fresnel falloff. */
uniform float reflection_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
/** Reflection brightness in exposure stops. */
uniform float reflection_exposure : hint_range(-8.0, 8.0, 0.05) = 0.0;
/** Compositing operation applied over the base surface. */
uniform int blend_mode : hint_enum("Mix", "Add", "Multiply") = 0;
/** Additional self-lit reflection intensity. */
uniform float reflection_emission : hint_range(0.0, 4.0, 0.01) = 0.0;
/** Reflection mip level; requires mipmaps on the environment texture. */
uniform float reflection_blur : hint_range(0.0, 6.0, 0.1) = 0.0;

group_uniforms Mapping;
/** Reflection uses the view direction; matcap uses the view-space normal. */
uniform int mapping_mode : hint_enum("Spherical Reflection", "Matcap") = 0;
/** Environment image scale around its center. Negative values mirror an axis. */
uniform vec2 environment_scale = vec2(1.0);
/** Environment image offset after scaling and rotation. */
uniform vec2 environment_offset = vec2(0.0);
/** Environment image rotation in degrees. */
uniform float environment_rotation : hint_range(-180.0, 180.0, 0.1) = 0.0;
/** Environment image scrolling speed in UV units per second. */
uniform vec2 environment_scroll = vec2(0.0);
/** Reverses the image vertically for top-origin reflection textures. */
uniform bool flip_vertical = true;

group_uniforms Surface;
/** Faces removed from rendering: Back, Front, or Disabled for both sides. */
uniform int cull_mode : hint_enum("Back", "Front", "Disabled") = 0;
/** Surface transparency. Zero is opaque; one is fully transparent. */
uniform float transparency : hint_range(0.0, 1.0, 0.01) = 0.0;
/** Base surface texture, sampled using the mesh UVs. */
uniform sampler2D base_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
/** Base surface color before reflection compositing. */
uniform vec4 base_color : source_color = vec4(1.0);
/** Scale for the base, mask, and normal texture UVs. */
uniform vec2 surface_uv_scale = vec2(1.0);
/** Offset for the base, mask, and normal texture UVs. */
uniform vec2 surface_uv_offset = vec2(0.0);
/** Scene lighting response. Zero preserves the unlit environment-map appearance. */
uniform float lighting_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
/** Metallic response when scene lighting is enabled. */
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.0;
/** Surface roughness for scene lighting, independent of reflection blur. */
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.5;
/** Specular response for scene lighting. */
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.0;

group_uniforms Mask;
/** Enables a mesh-UV texture mask for the reflection. */
uniform bool mask_enabled = false;
/** Mask texture; white allows reflection and black preserves the base. */
uniform sampler2D reflection_mask : hint_default_white, filter_linear_mipmap, repeat_enable;
/** Mask channel sampled for reflection coverage. */
uniform int mask_channel : hint_enum("Red", "Green", "Blue", "Alpha") = 0;
/** Reverses the sampled reflection mask. */
uniform bool mask_invert = false;

group_uniforms Fresnel;
/** Amount of edge-weighted reflection falloff. Zero gives uniform coverage. */
uniform float fresnel_amount : hint_range(0.0, 1.0, 0.01) = 0.0;
/** Falloff exponent for edge-weighted reflection. */
uniform float fresnel_power : hint_range(0.1, 8.0, 0.1) = 3.0;
/** Minimum reflection coverage on front-facing surfaces at full Fresnel strength. */
uniform float fresnel_minimum : hint_range(0.0, 1.0, 0.01) = 0.0;

group_uniforms Normal;
/** Enables a tangent-space normal texture for lighting and environment mapping. */
uniform bool normal_enabled = false;
/** OpenGL tangent-space normal texture. Requires mesh tangents. */
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
/** Tangent-space normal intensity. */
uniform float normal_strength : hint_range(0.0, 2.0, 0.01) = 1.0;
group_uniforms;

void fragment() {
	if ((cull_mode == 0 && !FRONT_FACING) || (cull_mode == 1 && FRONT_FACING)) {
		discard;
	}
	vec2 surface_uv = UV * surface_uv_scale + surface_uv_offset;
	vec3 surface_normal = normalize(NORMAL);
	if (normal_enabled) {
		vec3 detail_normal = texture(normal_texture, surface_uv).xyz * 2.0 - 1.0;
		detail_normal.xy *= normal_strength;
		detail_normal = normalize(detail_normal);
		surface_normal = normalize(mat3(normalize(TANGENT), normalize(BINORMAL), surface_normal) * detail_normal);
	}
	NORMAL = surface_normal;
	vec2 sphere_uv;
	if (mapping_mode == 1) {
		sphere_uv = surface_normal.xy * 0.5 + vec2(0.5);
	} else {
		vec3 reflected = reflect(-VIEW, surface_normal);
		float diameter = max(2.0 * length(vec3(reflected.xy, reflected.z + 1.0)), 0.0001);
		sphere_uv = reflected.xy / diameter + vec2(0.5);
	}
	if (flip_vertical) {
		sphere_uv.y = 1.0 - sphere_uv.y;
	}
	vec2 centered_uv = (sphere_uv - vec2(0.5)) * environment_scale;
	float angle = radians(environment_rotation);
	centered_uv = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * centered_uv;
	sphere_uv = centered_uv + vec2(0.5) + environment_offset + environment_scroll * TIME;
	vec3 reflection = textureLod(environment_texture, sphere_uv, reflection_blur).rgb * reflection_tint.rgb * exp2(reflection_exposure);
	float coverage = reflection_strength;
	if (mask_enabled) {
		vec4 mask_sample = texture(reflection_mask, surface_uv);
		float mask_value = mask_sample[mask_channel];
		coverage *= mask_invert ? 1.0 - mask_value : mask_value;
	}
	float edge = pow(1.0 - clamp(dot(surface_normal, VIEW), 0.0, 1.0), fresnel_power);
	coverage *= mix(1.0, mix(fresnel_minimum, 1.0, edge), fresnel_amount);
	vec3 base = texture(base_texture, surface_uv).rgb * base_color.rgb;
	vec3 surface_color = mix(base, reflection, coverage);
	if (blend_mode == 1) {
		surface_color = base + reflection * coverage;
	} else if (blend_mode == 2) {
		surface_color = base * mix(vec3(1.0), reflection, coverage);
	}
	ALBEDO = surface_color * lighting_amount;
	EMISSION = surface_color * (1.0 - lighting_amount) + reflection * coverage * reflection_emission;
	ALPHA = 1.0 - clamp(transparency, 0.0, 1.0);
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular * lighting_amount;
}
