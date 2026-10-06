shader_type canvas_item;

uniform bool generate_panel = false;
uniform vec2 panel_size = vec2(280.0, 80.0);
uniform vec4 panel_color : source_color = vec4(0.01, 0.025, 0.065, 0.9);
uniform vec4 frame_color : source_color = vec4(0.18, 0.52, 1.0, 1.0);
uniform vec4 frame_highlight_color : source_color = vec4(0.48, 0.78, 1.0, 1.0);
uniform vec4 scanline_color : source_color = vec4(0.3, 0.7, 1.0, 1.0);
uniform float corner_radius_px : hint_range(0.0, 64.0) = 14.0;
uniform float frame_width_px : hint_range(0.0, 24.0) = 6.0;
uniform float edge_feather_px : hint_range(0.0, 32.0) = 10.0;
uniform float scanline_spacing_px : hint_range(1.0, 16.0) = 4.0;
uniform float scanline_width_px : hint_range(0.25, 8.0) = 1.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.14;
uniform float scanline_lift : hint_range(0.0, 0.25) = 0.025;
uniform float scanline_scroll_speed_px : hint_range(-32.0, 32.0) = 10.45;
uniform float scanline_flicker_subtle_strength : hint_range(0.0, 2.0) = 0.005;
uniform float scanline_flicker_peak_strength : hint_range(0.0, 2.0) = 0.07;
uniform float scanline_flicker_bias : hint_range(1.0, 32.0) = 12.0;
uniform float scanline_flicker_speed : hint_range(0.0, 90.0) = 75.0;
uniform float foreground_luma_start : hint_range(0.0, 1.0) = 0.5;
uniform float foreground_luma_end : hint_range(0.0, 1.0) = 0.86;
uniform int text_clearance_count = 0;
uniform vec4 text_clearance_rects[32];
uniform float text_clearance_padding_px : hint_range(0.0, 32.0) = 3.0;
uniform float text_clearance_feather_px : hint_range(0.0, 32.0) = 7.0;
varying vec2 effect_position;


void vertex() {
	effect_position = VERTEX;
}


float rounded_box_sdf(vec2 point, vec2 half_size, float radius) {
	vec2 corner = abs(point) - max(half_size - vec2(radius), vec2(0.0));
	return length(max(corner, vec2(0.0))) + min(max(corner.x, corner.y), 0.0) - radius;
}


float scanline_mask(float screen_y, float time) {
	float spacing = max(scanline_spacing_px, 1.0);
	float width = clamp(scanline_width_px, 0.0, spacing);
	if (width >= spacing - 0.001) {
		return 1.0;
	}
	float phase = screen_y - time * scanline_scroll_speed_px;
	float centered_phase = mod(phase + spacing * 0.5, spacing) - spacing * 0.5;
	float distance_to_center = abs(centered_phase);
	float half_width = width * 0.5;
	float available_feather = max(spacing * 0.5 - half_width, 0.001);
	float feather = min(max(fwidth(screen_y), 0.5), available_feather);
	return 1.0 - smoothstep(half_width, half_width + feather, distance_to_center);
}


float scanline_flicker(float time) {
	float subtle_strength = min(scanline_flicker_subtle_strength, scanline_flicker_peak_strength);
	float peak_strength = max(scanline_flicker_subtle_strength, scanline_flicker_peak_strength);
	if (scanline_flicker_speed <= 0.0 || peak_strength <= 0.0) {
		return 1.0;
	}
	float flicker_tick = floor(time * max(scanline_flicker_speed, 0.0));
	float intensity_sample = fract(sin((flicker_tick + 1.0) * 12.9898) * 43758.5453);
	float direction_sample = fract(sin((flicker_tick + 41.73) * 78.233) * 23421.631);
	float peak_weight = pow(intensity_sample, max(scanline_flicker_bias, 1.0));
	float subtle_variation = (direction_sample * 2.0 - 1.0) * subtle_strength;
	float variation = mix(subtle_variation, peak_strength, peak_weight);
	return max(1.0 + variation, 0.0);
}


float rectangle_sdf(vec2 point, vec4 rectangle) {
	vec2 half_size = rectangle.zw * 0.5;
	vec2 center = rectangle.xy + half_size;
	vec2 delta = abs(point - center) - half_size;
	return length(max(delta, vec2(0.0))) + min(max(delta.x, delta.y), 0.0);
}


float text_clearance_mask(vec2 point) {
	float clearance = 1.0;
	float feather_end = text_clearance_padding_px + max(text_clearance_feather_px, 0.001);
	for (int index = 0; index < 32; index++) {
		if (index >= text_clearance_count) {
			break;
		}
		float distance_to_text = rectangle_sdf(point, text_clearance_rects[index]);
		clearance *= smoothstep(text_clearance_padding_px, feather_end, distance_to_text);
	}
	return clearance;
}


void fragment() {
	float scanline = scanline_mask(FRAGCOORD.y, TIME);
	float animated_scanline_strength = scanline_strength * scanline_flicker(TIME);
	if (generate_panel) {
		vec2 safe_size = max(panel_size, vec2(1.0));
		vec2 half_size = safe_size * 0.5;
		float radius = min(corner_radius_px, min(half_size.x, half_size.y));
		float sdf = rounded_box_sdf(UV * safe_size - half_size, half_size, radius);
		float antialias_width = max(fwidth(sdf), 0.75);
		float inside = 1.0 - smoothstep(-antialias_width, antialias_width, sdf);
		float interior = 1.0 - smoothstep(
			-frame_width_px - antialias_width,
			-frame_width_px + antialias_width,
			sdf
		);
		float border = max(inside - interior, 0.0);
		float border_highlight = smoothstep(-max(frame_width_px * 0.45, 0.001), 0.0, sdf);
		vec3 border_rgb = mix(frame_color.rgb, frame_highlight_color.rgb, border_highlight);
		float inward_distance = max(-sdf - frame_width_px, 0.0);
		float edge_feather = smoothstep(0.0, max(edge_feather_px, 0.001), inward_distance);
		float inner_shadow = mix(0.72, 1.0, edge_feather);
		float line_mix = scanline * animated_scanline_strength * edge_feather;
		vec3 interior_rgb = mix(panel_color.rgb * inner_shadow, scanline_color.rgb, line_mix);
		float border_ratio = border / max(inside, 0.001);
		float border_alpha = mix(frame_color.a, frame_highlight_color.a, border_highlight);
		vec3 output_rgb = mix(interior_rgb, border_rgb, border_ratio);
		float output_alpha = panel_color.a * interior + border_alpha * border;
		COLOR = vec4(output_rgb, output_alpha);
	} else {
		vec4 source = COLOR;
		float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
		float foreground_mask = 1.0 - smoothstep(foreground_luma_start, foreground_luma_end, luminance);
		float shadow_mask = smoothstep(0.22, 0.82, source.a);
		float flat_primitive_mask = step(0.5, max(TEXTURE_PIXEL_SIZE.x, TEXTURE_PIXEL_SIZE.y));
		float uv_edge_distance = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
		float edge_mask = smoothstep(0.0, 0.055, uv_edge_distance);
		float text_mask = text_clearance_mask(effect_position);
		float background_mask = foreground_mask * shadow_mask * edge_mask * flat_primitive_mask * text_mask;
		float line_mix = scanline * animated_scanline_strength * background_mask;
		vec3 tinted_line = min(scanline_color.rgb + vec3(scanline_lift), vec3(1.0));
		COLOR = vec4(mix(source.rgb, tinted_line, line_mix), source.a);
	}
}
