shader_type spatial;

render_mode blend_mix, cull_disabled, depth_draw_never, diffuse_lambert, specular_disabled;
stencil_mode read, compare_not_equal, 32;

group_uniforms Outline;
/** Distance the outline shell expands along the surface normal. */
uniform float outline_width : hint_range(0.0, 0.1, 0.001) = 0.035;
/** Proportion of source brightness removed from the outline. */
uniform float darkness : hint_range(0.0, 1.0, 0.01) = 0.72;
/** Alpha threshold used to preserve cutout surface boundaries. */
uniform float alpha_threshold : hint_range(0.0, 1.0, 0.01) = 0.1;

group_uniforms Surface;
/** Surface colour texture sampled by the outline. */
uniform sampler2D base_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic;
/** Surface colour multiplier applied to the sampled texture. */
uniform vec4 base_color : source_color = vec4(1.0);

group_uniforms CharacterTint;
/** Enables character colour processing for runtime-tinted surfaces. */
uniform bool tint_enabled = false;
/** Primary character colour mask. */
uniform sampler2D mask_primary : source_color, hint_default_white;
/** Secondary character colour mask. */
uniform sampler2D mask_secondary : source_color, hint_default_black;
/** Primary character colour. */
uniform vec4 primary_color : source_color = vec4(1.0);
/** Secondary character colour. */
uniform vec4 secondary_color : source_color = vec4(1.0);
/** Primary mask intensity. */
uniform float primary_strength = 1.0;
/** Secondary mask intensity. */
uniform float secondary_strength = 0.0;
/** Minimum saturation affected by hue tinting. */
uniform float saturation_threshold : hint_range(0.0, 1.0) = 0.25;
/** Saturation transition width for hue tinting. */
uniform float saturation_softness : hint_range(0.0, 1.0) = 0.2;
/** Saturation response exponent for hue tinting. */
uniform float saturation_exponent : hint_range(0.01, 8.0) = 1.0;
/** Final hue tint blend strength. */
uniform float overlay_strength : hint_range(0.0, 1.0) = 1.0;


vec3 rgb_to_hsv(vec3 color) {
	vec4 constants = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(color.bg, constants.wz), vec4(color.gb, constants.xy), step(color.b, color.g));
	vec4 q = mix(vec4(p.xyw, color.r), vec4(color.r, p.yzx), step(p.x, color.r));
	float delta = q.x - min(q.w, q.y);
	float epsilon = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * delta + epsilon)), delta / (q.x + epsilon), q.x);
}


vec3 hsv_to_rgb(vec3 color) {
	vec3 p = abs(fract(vec3(color.x) + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return color.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), color.y);
}


vec3 apply_character_tint(vec3 sampled_color, vec2 uv) {
	float primary_mask = texture(mask_primary, uv).r * primary_strength;
	float secondary_mask = texture(mask_secondary, uv).r * secondary_strength;
	float mask_weight = clamp(max(primary_mask, secondary_mask), 0.0, 1.0);

	vec3 tinted = mix(sampled_color, primary_color.rgb, clamp(primary_mask * primary_color.a, 0.0, 1.0));
	tinted = mix(tinted, secondary_color.rgb, clamp(secondary_mask * secondary_color.a, 0.0, 1.0));

	vec3 hsv = rgb_to_hsv(tinted);
	float saturation_max = max(saturation_threshold + saturation_softness, saturation_threshold + 0.001);
	float saturation_weight = smoothstep(saturation_threshold, saturation_max, hsv.y);
	saturation_weight = pow(clamp(saturation_weight, 0.0, 1.0), max(saturation_exponent, 0.01));

	vec3 primary_hsv = rgb_to_hsv(primary_color.rgb);
	vec3 secondary_hsv = rgb_to_hsv(secondary_color.rgb);
	float target_hue = secondary_mask > primary_mask ? secondary_hsv.x : primary_hsv.x;
	vec3 shifted = hsv_to_rgb(vec3(mix(hsv.x, target_hue, saturation_weight), hsv.y, hsv.z));
	return mix(tinted, shifted, clamp(overlay_strength * mask_weight * saturation_weight, 0.0, 1.0));
}


void vertex() {
	VERTEX += NORMAL * outline_width;
}


void fragment() {
	vec4 surface = texture(base_tex, UV) * base_color;
	if (surface.a < alpha_threshold) {
		discard;
	}

	vec3 surface_color = tint_enabled ? apply_character_tint(surface.rgb, UV) : surface.rgb;
	ALBEDO = surface_color * (1.0 - darkness);
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = 1.0;
}
