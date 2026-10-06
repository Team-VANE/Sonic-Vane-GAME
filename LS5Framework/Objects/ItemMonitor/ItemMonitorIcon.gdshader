shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D background_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D item_texture : source_color, filter_linear, repeat_disable;

void fragment() {
	vec2 display_uv = UV;
	if (!FRONT_FACING) {
		display_uv.x = 1.0 - display_uv.x;
	}

	vec4 background = texture(background_texture, display_uv);
	vec4 item = texture(item_texture, display_uv);
	ALBEDO = mix(background.rgb, item.rgb, item.a);
	ALPHA = item.a + background.a * (1.0 - item.a);
}
