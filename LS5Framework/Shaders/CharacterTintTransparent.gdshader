shader_type spatial;

render_mode blend_mix, depth_prepass_alpha, specular_schlick_ggx;

uniform sampler2D base_tex : source_color, hint_default_white;
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D mask_primary : source_color, hint_default_white;
uniform sampler2D mask_secondary : source_color, hint_default_white;

uniform vec4 primary_color : source_color = vec4(1.0);
uniform vec4 secondary_color : source_color = vec4(1.0);
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
uniform bool alpha_scissor_enabled = false;
uniform float alpha_scissor_threshold = 0.5;
uniform float afterimage_alpha = 1.0;

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

float _channel(vec4 value, int channel) {
	if (channel == 1) return value.g;
	if (channel == 2) return value.b;
	if (channel == 3) return value.a;
	return value.r;
}

void fragment() {
	vec4 base = texture(base_tex, UV) * base_color;
	float primary_mask = texture(mask_primary, UV).r * primary_strength;
	float secondary_mask = texture(mask_secondary, UV).r * secondary_strength;
	float mask_weight = clamp(max(primary_mask, secondary_mask), 0.0, 1.0);
	vec3 tinted = mix(base.rgb, primary_color.rgb, clamp(primary_mask * primary_color.a, 0.0, 1.0));
	tinted = mix(tinted, secondary_color.rgb, clamp(secondary_mask * secondary_color.a, 0.0, 1.0));
	vec3 hsv = _rgb_to_hsv(tinted);
	float sat_max = max(saturation_threshold + saturation_softness, saturation_threshold + 0.001);
	float sat_weight = pow(clamp(smoothstep(saturation_threshold, sat_max, hsv.y), 0.0, 1.0), max(saturation_exponent, 0.01));
	vec3 primary_hsv = _rgb_to_hsv(primary_color.rgb);
	vec3 secondary_hsv = _rgb_to_hsv(secondary_color.rgb);
	float target_hue = secondary_mask > primary_mask ? secondary_hsv.x : primary_hsv.x;
	vec3 shifted = _hsv_to_rgb(vec3(mix(hsv.x, target_hue, sat_weight), hsv.y, hsv.z));
	ALBEDO = mix(tinted, shifted, clamp(overlay_strength * mask_weight * sat_weight, 0.0, 1.0));
	METALLIC = has_metallic_tex ? _channel(texture(metallic_tex, UV), clamp(metallic_tex_channel, 0, 3)) : metallic_scalar;
	ROUGHNESS = has_roughness_tex ? _channel(texture(roughness_tex, UV), clamp(roughness_tex_channel, 0, 3)) : roughness_scalar;
	SPECULAR = specular_scalar;
	if (has_normal_tex) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	if (emission_enabled) {
		vec3 source_emission = texture(emission_tex, UV).rgb * emission_color.rgb;
		float emission_value = max(source_emission.r, max(source_emission.g, source_emission.b));
		vec3 tinted_emission = primary_color.rgb * emission_value;
		EMISSION = mix(source_emission, tinted_emission, clamp(primary_mask * primary_color.a, 0.0, 1.0)) * emission_energy;
	}
	ALPHA = base.a * afterimage_alpha;
	if (alpha_scissor_enabled) {
		if (ALPHA < alpha_scissor_threshold) {
			discard;
		}
		ALPHA = 1.0;
	}
}
