shader_type spatial;

render_mode depth_draw_opaque, specular_schlick_ggx;
stencil_mode write, compare_always, 32;

uniform sampler2D base_tex : source_color, hint_default_white;
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D mask_primary : source_color, hint_default_white;
uniform sampler2D mask_secondary : source_color, hint_default_white;

uniform vec4 primary_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 secondary_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float primary_strength = 1.0;
uniform float secondary_strength = 1.0;

uniform float metallic_scalar = 0.0;
uniform float roughness_scalar = 0.5;
uniform float specular_scalar = 0.5;

uniform sampler2D metallic_tex : hint_default_white;
uniform sampler2D roughness_tex : hint_default_white;
uniform sampler2D normal_tex : hint_normal;

uniform bool has_metallic_tex = false;
uniform bool has_roughness_tex = false;
uniform bool has_normal_tex = false;
uniform int metallic_tex_channel = 0;
uniform int roughness_tex_channel = 0;
uniform float normal_scale = 1.0;

uniform bool emission_enabled = false;
uniform sampler2D emission_tex : source_color, hint_default_white;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 1.0;

uniform float hue_target = 0.6;
uniform float saturation_threshold = 0.25;
uniform float saturation_softness = 0.2;
uniform float overlay_strength = 1.0;
uniform float saturation_exponent = 1.0;

vec3 _rgb_to_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 _hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(vec3(c.x) + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}


void fragment() {
	vec4 base = texture(base_tex, UV) * base_color;
	float mask_primary_value = texture(mask_primary, UV).r * primary_strength;
	float mask_secondary_value = texture(mask_secondary, UV).r * secondary_strength;
	float mask_weight = clamp(max(mask_primary_value, mask_secondary_value), 0.0, 1.0);

	vec3 tinted = base.rgb;
	float primary_mix = clamp(mask_primary_value * primary_color.a, 0.0, 1.0);
	float secondary_mix = clamp(mask_secondary_value * secondary_color.a, 0.0, 1.0);
	tinted = mix(tinted, primary_color.rgb, primary_mix);
	tinted = mix(tinted, secondary_color.rgb, secondary_mix);

	vec3 hsv = _rgb_to_hsv(tinted);
	float sat_min = saturation_threshold;
	float sat_max = max(saturation_threshold + saturation_softness, saturation_threshold + 0.001);
	float sat_weight = smoothstep(sat_min, sat_max, hsv.y);
	sat_weight = pow(clamp(sat_weight, 0.0, 1.0), max(saturation_exponent, 0.01));

	vec3 primary_hsv = _rgb_to_hsv(primary_color.rgb);
	vec3 secondary_hsv = _rgb_to_hsv(secondary_color.rgb);
	float target_hue = primary_hsv.x;
	if (mask_secondary_value > mask_primary_value) {
		target_hue = secondary_hsv.x;
	}

	float hue_blend = mix(hsv.x, target_hue, sat_weight);
	vec3 shifted = _hsv_to_rgb(vec3(hue_blend, hsv.y, hsv.z));
	float blend = clamp(overlay_strength * mask_weight * sat_weight, 0.0, 1.0);
	vec3 color_out = mix(tinted, shifted, blend);
	float metallic_value = metallic_scalar;
	if (has_metallic_tex) {
		int ch = clamp(metallic_tex_channel, 0, 3);
		vec4 mt = texture(metallic_tex, UV);
		if (ch == 0) metallic_value = mt.r;
		else if (ch == 1) metallic_value = mt.g;
		else if (ch == 2) metallic_value = mt.b;
		else if (ch == 3) metallic_value = mt.a;
	}
	float roughness_value = roughness_scalar;
	if (has_roughness_tex) {
		int ch_r = clamp(roughness_tex_channel, 0, 3);
		vec4 rt = texture(roughness_tex, UV);
		if (ch_r == 0) roughness_value = rt.r;
		else if (ch_r == 1) roughness_value = rt.g;
		else if (ch_r == 2) roughness_value = rt.b;
		else if (ch_r == 3) roughness_value = rt.a;
	}

	ALBEDO = color_out;
	METALLIC = clamp(metallic_value, 0.0, 1.0);
	ROUGHNESS = clamp(roughness_value, 0.0, 1.0);
	SPECULAR = clamp(specular_scalar, 0.0, 1.0);

	if (has_normal_tex) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	if (emission_enabled) {
		EMISSION = texture(emission_tex, UV).rgb * emission_color.rgb * emission_energy;
	}
}
