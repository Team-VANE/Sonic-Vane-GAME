shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

group_uniforms Timing;
instance uniform float age : hint_range(0.0, 1.0, 0.001) = 0.0;
uniform float fade_power : hint_range(0.1, 8.0, 0.1) = 2.2;

group_uniforms Streak_Shape;
uniform sampler2D streak_texture;
uniform sampler2D breakup_texture;
uniform float streak_tiling : hint_range(0.1, 16.0, 0.1) = 2.0;
uniform float streak_sharpness : hint_range(0.5, 12.0, 0.1) = 5.5;
uniform float streak_floor : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float center_opacity : hint_range(0.0, 1.0, 0.01) = 0.85;
uniform float edge_cutout : hint_range(0.0, 1.0, 0.01) = 0.82;
uniform float alpha_multiplier : hint_range(0.0, 4.0, 0.01) = 1.45;

group_uniforms Color;
uniform vec4 core_color : source_color = vec4(1.0, 0.92, 0.22, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.28, 0.04, 1.0);
uniform float emission_strength : hint_range(0.0, 16.0, 0.1) = 7.0;


void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	float radial = length(centered_uv);
	float outward = clamp(radial / max(edge_cutout, 0.001), 0.0, 1.0);

	float streak = texture(streak_texture, vec2(UV.x * streak_tiling, UV.y)).r;
	float breakup = texture(breakup_texture, vec2(UV.x * 2.0 + age, UV.y * 3.0 - age)).r;
	float streak_mask = max(streak, streak_floor) * mix(0.65, 1.0, breakup);
	float mask = pow(clamp(streak_mask, 0.0, 1.0), streak_sharpness);
	mask *= mix(center_opacity, 1.0, smoothstep(0.0, edge_cutout, radial));
	mask *= 1.0 - smoothstep(edge_cutout, 1.0, radial);

	float life = pow(clamp(1.0 - age, 0.0, 1.0), fade_power);
	vec3 color = mix(core_color.rgb, edge_color.rgb, outward) * emission_strength;
	ALBEDO = color;
	EMISSION = color;
	ALPHA = clamp(mask * life * alpha_multiplier, 0.0, 1.0);
}
