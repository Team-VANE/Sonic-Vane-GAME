shader_type spatial;

render_mode blend_mix, cull_back, depth_draw_never, diffuse_lambert, specular_disabled;

group_uniforms UekawaRim;
/** Overall opacity of the stylized lighting layer. */
uniform float effect_opacity : hint_range(0.0, 1.0, 0.01) = 0.82;
/** View-angle threshold where the inner shadow begins. */
uniform float shadow_start : hint_range(0.0, 1.0, 0.01) = 0.18;
/** View-angle threshold where the inner shadow reaches full strength. */
uniform float shadow_end : hint_range(0.0, 1.0, 0.01) = 0.62;
/** Amount of source brightness removed inside the rim. */
uniform float shadow_depth : hint_range(0.0, 1.0, 0.01) = 0.62;
/** View-angle threshold where the bright outer rim begins. */
uniform float rim_start : hint_range(0.0, 1.0, 0.01) = 0.68;
/** View-angle threshold where the bright outer rim reaches full strength. */
uniform float rim_end : hint_range(0.0, 1.0, 0.01) = 0.9;
/** Strength of the rim on the light-facing side. */
uniform float lit_rim_strength : hint_range(0.0, 3.0, 0.01) = 1.45;
/** Golden-yellow hue approached by chromatic light-facing rims. */
uniform float lit_rim_hue_target : hint_range(0.0, 1.0, 0.01) = 0.14;
/** Amount the source hue moves toward the highlight hue. */
uniform float lit_rim_hue_shift : hint_range(0.0, 1.0, 0.01) = 0.28;
/** Amount the light-facing rim is raised toward its source hue. */
uniform float lit_rim_brightness : hint_range(0.0, 1.0, 0.01) = 0.82;
/** Amount the light-facing rim is desaturated toward a pale source-colour highlight. */
uniform float lit_rim_bleach : hint_range(0.0, 1.0, 0.01) = 0.46;
/** Strength of the cyan rim opposite the dominant light angle. */
uniform float back_rim_strength : hint_range(0.0, 2.0, 0.01) = 0.34;
/** Cyan colour mixed into the back rim. */
uniform vec4 back_rim_color : source_color = vec4(0.12, 0.82, 1.0, 1.0);
/** Amount of cyan mixed into the source colour at the back rim. */
uniform float back_rim_tint : hint_range(0.0, 1.0, 0.01) = 0.58;
/** Minimum top-biased rim strength when direct lighting is weak. */
uniform float minimum_strength : hint_range(0.0, 0.5, 0.01) = 0.14;
/** Direct-light response applied to both rim sides. */
uniform float lighting_response : hint_range(0.0, 2.0, 0.01) = 1.0;
/** Alpha threshold used to preserve cutout surface boundaries. */
uniform float alpha_threshold : hint_range(0.0, 1.0, 0.01) = 0.1;

group_uniforms Surface;
/** Surface colour texture sampled by the stylized lighting layer. */
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

varying vec3 surface_color_data;
varying float view_rim_data;
varying float shadow_band_data;
varying float outer_rim_data;


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


vec3 raised_source_color(vec3 sampled_color) {
	vec3 source_hsv = rgb_to_hsv(sampled_color);
	float chroma_weight = smoothstep(0.08, 0.32, source_hsv.y);
	float hue_delta = fract(lit_rim_hue_target - source_hsv.x + 0.5) - 0.5;
	float shifted_hue = fract(source_hsv.x + hue_delta * lit_rim_hue_shift * chroma_weight);
	vec3 shifted_color = hsv_to_rgb(vec3(shifted_hue, source_hsv.y, source_hsv.z));
	float peak = max(max(shifted_color.r, shifted_color.g), max(shifted_color.b, 0.001));
	vec3 raised_hue = shifted_color / peak;
	vec3 brightened = mix(shifted_color, raised_hue, lit_rim_brightness);
	float highlight_peak = max(max(brightened.r, brightened.g), brightened.b);
	vec3 pale_highlight = vec3(highlight_peak);
	return mix(brightened, pale_highlight, lit_rim_bleach);
}


void fragment() {
	vec4 surface = texture(base_tex, UV) * base_color;
	if (surface.a < alpha_threshold) {
		discard;
	}

	vec3 surface_color = tint_enabled ? apply_character_tint(surface.rgb, UV) : surface.rgb;
	float view_rim = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float shadow_band = smoothstep(shadow_start, max(shadow_end, shadow_start + 0.001), view_rim);
	float outer_rim = smoothstep(rim_start, max(rim_end, rim_start + 0.001), view_rim);
	float shadow_visibility = shadow_band * (1.0 - outer_rim * 0.72);
	float layer_mask = max(outer_rim, shadow_visibility * 0.72);

	surface_color_data = surface_color;
	view_rim_data = view_rim;
	shadow_band_data = shadow_visibility;
	outer_rim_data = outer_rim;

	vec3 shaded_color = surface_color * (1.0 - shadow_depth * shadow_visibility);
	vec3 top_direction_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float top_facing = smoothstep(-0.15, 0.72, dot(normalize(NORMAL), top_direction_view));
	float bottom_facing = smoothstep(-0.15, 0.72, dot(normalize(NORMAL), -top_direction_view));
	vec3 lit_rim_color = raised_source_color(surface_color);
	vec3 back_rim_source = mix(surface_color, back_rim_color.rgb, back_rim_tint * back_rim_color.a);

	ALBEDO = shaded_color;
	EMISSION = outer_rim * minimum_strength * (
		lit_rim_color * top_facing
		+ back_rim_source * bottom_facing * back_rim_strength
	);
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = surface.a * effect_opacity * layer_mask;
}


void light() {
	float normal_light = dot(normalize(NORMAL), normalize(LIGHT));
	float lit_facing = smoothstep(-0.08, 0.72, normal_light);
	float back_facing = smoothstep(-0.08, 0.72, -normal_light);
	float lambert = max(normal_light, 0.0);
	vec3 lit_rim_color = raised_source_color(surface_color_data);
	vec3 back_rim_source = mix(
		surface_color_data,
		back_rim_color.rgb,
		back_rim_tint * back_rim_color.a
	);
	vec3 light_scale = ATTENUATION * LIGHT_COLOR / PI;

	DIFFUSE_LIGHT += ALBEDO * lambert * light_scale;
	DIFFUSE_LIGHT += lit_rim_color * outer_rim_data * lit_facing * lit_rim_strength * lighting_response * light_scale;
	DIFFUSE_LIGHT += back_rim_source * outer_rim_data * back_facing * back_rim_strength * lighting_response * light_scale;
}
