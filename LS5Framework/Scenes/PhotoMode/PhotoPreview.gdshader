shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D scanlines : repeat_enable, filter_nearest;
// Photo color treatment.
uniform int filter_mode : hint_enum("Original", "Sepiatone", "CRT") = 0;
// Normalized screenshot bounds.
uniform vec4 crop_bounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform float scanline_scale = 1.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 output_bounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool green_screen = false;
uniform sampler2D player_matte : repeat_disable, filter_linear;

void fragment() {
	vec4 scene = textureLod(scene_color, SCREEN_UV, 0.0);
	if (green_screen) {
		float player_alpha = texture(player_matte, SCREEN_UV).a;
		scene = vec4(mix(vec3(0.0, 1.0, 0.0), scene.rgb, player_alpha), 1.0);
	}
	if (filter_mode == 1) {
		float luminance = dot(scene.rgb, vec3(0.2126, 0.7152, 0.0722));
		scene.rgb = luminance * vec3(1.15, 0.88, 0.57);
	} else if (filter_mode == 2) {
		float scanline = texture(scanlines, vec2(0.0, FRAGCOORD.y * scanline_scale / 1024.0)).a;
		vec2 edge = SCREEN_UV * 2.0 - 1.0;
		float vignette = 1.0 - 0.16 * smoothstep(0.25, 1.7, dot(edge, edge));
		scene.rgb *= (1.0 - 0.32 * scanline) * vignette;
	}
	vec2 photo_uv = (SCREEN_UV - output_bounds.xy) / (output_bounds.zw - output_bounds.xy);
	vec2 photo_edge = photo_uv * 2.0 - 1.0;
	scene.rgb *= 1.0 - vignette_strength * smoothstep(0.15, 1.65, dot(photo_edge, photo_edge));
	if (any(lessThan(SCREEN_UV, crop_bounds.xy)) || any(greaterThanEqual(SCREEN_UV, crop_bounds.zw))) {
		scene.rgb *= 0.32;
	}
	COLOR = scene;
}
