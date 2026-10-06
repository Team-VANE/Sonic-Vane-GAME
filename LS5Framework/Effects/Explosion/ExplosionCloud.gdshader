shader_type spatial;
render_mode unshaded, blend_mix, depth_prepass_alpha, cull_disabled;

group_uniforms Timing;
instance uniform float age : hint_range(0.0, 1.0, 0.001) = 0.0;
uniform float fade_power : hint_range(0.1, 8.0, 0.1) = 1.4;

group_uniforms Cloud_Shape;
uniform sampler2D surface_noise_texture;
uniform sampler2D secondary_noise_texture;
uniform float surface_noise_scale : hint_range(0.1, 16.0, 0.1) = 3.0;
uniform float secondary_noise_scale : hint_range(0.1, 16.0, 0.1) = 7.0;
uniform float surface_distortion : hint_range(0.0, 2.0, 0.01) = 0.42;
uniform float surface_motion : hint_range(-4.0, 4.0, 0.01) = 0.65;

group_uniforms Fire_To_Smoke;
uniform sampler2D fire_ratio_texture;
uniform sampler2D smoke_ratio_texture;
uniform vec4 fire_start_color : source_color = vec4(1.0, 0.86, 0.15, 1.0);
uniform vec4 fire_end_color : source_color = vec4(1.0, 0.33, 0.04, 1.0);
uniform vec4 smoke_color : source_color = vec4(0.16, 0.15, 0.14, 1.0);
uniform float fire_emission_start : hint_range(0.0, 12.0, 0.1) = 6.0;
uniform float fire_emission_end : hint_range(0.0, 12.0, 0.1) = 2.4;
uniform float smoke_emission : hint_range(0.0, 2.0, 0.01) = 0.15;
uniform float smoke_takeover : hint_range(0.0, 1.0, 0.01) = 0.55;

group_uniforms Dissolve;
uniform sampler2D dissolve_texture;
uniform float alpha_multiplier : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float edge_softness : hint_range(0.01, 1.0, 0.01) = 0.28;
uniform float rim_strength : hint_range(0.0, 2.0, 0.01) = 0.35;

varying float v_surface_noise;
varying float v_secondary_noise;


vec2 sphere_uv(vec3 p, float scale, float offset) {
	vec3 n = normalize(p);
	return n.xz * scale + vec2(n.y * 0.25 + offset, offset);
}


void vertex() {
	vec2 surface_uv = sphere_uv(VERTEX, surface_noise_scale, TIME * surface_motion);
	vec2 secondary_uv = sphere_uv(VERTEX, secondary_noise_scale, -TIME * surface_motion * 0.7);
	v_surface_noise = texture(surface_noise_texture, surface_uv).r;
	v_secondary_noise = texture(secondary_noise_texture, secondary_uv).r;

	float pulse = sin(age * 3.14159);
	float displacement = ((v_surface_noise * 0.7 + v_secondary_noise * 0.3) - 0.5) * surface_distortion;
	VERTEX += NORMAL * displacement * pulse;
}


void fragment() {
	float noise_mix = clamp(v_surface_noise * 0.65 + v_secondary_noise * 0.35, 0.0, 1.0);
	float fire_mask = texture(fire_ratio_texture, vec2(age, noise_mix)).r;
	float smoke_mask = texture(smoke_ratio_texture, vec2(age, noise_mix)).r;
	float dissolve = texture(dissolve_texture, vec2(noise_mix, age)).r;

	float fire_to_smoke = smoothstep(smoke_takeover - edge_softness, smoke_takeover + edge_softness, age + smoke_mask * 0.35);
	float fire_visibility = clamp((1.0 - fire_to_smoke) * fire_mask, 0.0, 1.0);
	float smoke_visibility = clamp(fire_to_smoke * max(smoke_mask, 0.25), 0.0, 1.0);

	vec3 fire_color = mix(fire_start_color.rgb, fire_end_color.rgb, smoothstep(0.0, 1.0, age));
	float fire_emission = mix(fire_emission_start, fire_emission_end, smoothstep(0.0, 1.0, age));
	vec3 color = fire_color * fire_visibility * fire_emission;
	color += smoke_color.rgb * smoke_visibility * smoke_emission;

	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0) * rim_strength;
	float life_alpha = pow(clamp(1.0 - age, 0.0, 1.0), fade_power);
	float dissolve_alpha = smoothstep(age - edge_softness, age + edge_softness, dissolve);
	ALBEDO = color;
	EMISSION = color + fire_color * rim * fire_visibility;
	ALPHA = clamp((fire_visibility + smoke_visibility * 0.75 + rim) * life_alpha * dissolve_alpha * alpha_multiplier, 0.0, 1.0);
}
