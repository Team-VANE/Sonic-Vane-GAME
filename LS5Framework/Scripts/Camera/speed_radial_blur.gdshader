shader_type canvas_item;
render_mode unshaded;

uniform float intensity : hint_range(0.0, 2.0) = 0.0;
uniform float max_blur_radius : hint_range(0.0, 0.2) = 0.06;
uniform float vignette_inner_radius : hint_range(0.0, 1.5) = 0.24;
uniform float vignette_outer_radius : hint_range(0.0, 1.5) = 0.58;
uniform float max_opacity : hint_range(0.0, 1.0) = 0.9;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.12;
uniform float pulse_frequency : hint_range(0.0, 10.0) = 1.6;
uniform float chromatic_separation : hint_range(0.0, 0.02) = 0.00025;
uniform int speed_line_lanes_per_side : hint_range(2, 16) = 10;
uniform float speed_line_opacity : hint_range(0.0, 1.0) = 0.14;
uniform float speed_line_spawn_rate : hint_range(0.1, 20.0) = 8.0;
uniform float speed_line_lifetime_fraction : hint_range(0.05, 0.95) = 0.75;
uniform float speed_line_width : hint_range(0.005, 0.25) = 0.012;
uniform float speed_line_length : hint_range(0.05, 0.9) = 0.5;
uniform float viewport_aspect = 1.7777778;
uniform float time_offset = 0.0;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;

const int SAMPLE_COUNT = 12;

float random_lane_value(float value) {
	return fract(sin(value * 127.1 + 311.7) * 43758.5453);
}

float get_speed_line_mask(vec2 radial_uv, float time_value) {
	float abs_x = max(abs(radial_uv.x), 0.00001);
	float abs_y = max(abs(radial_uv.y), 0.00001);
	float scale_to_vertical_edge = 0.5 / abs_x;
	float scale_to_horizontal_edge = 0.5 / abs_y;
	float boundary_scale;
	float side_index;
	float edge_coordinate;

	if (scale_to_vertical_edge < scale_to_horizontal_edge) {
		boundary_scale = scale_to_vertical_edge;
		side_index = radial_uv.x >= 0.0 ? 0.0 : 1.0;
		edge_coordinate = radial_uv.y * boundary_scale + 0.5;
	} else {
		boundary_scale = scale_to_horizontal_edge;
		side_index = radial_uv.y >= 0.0 ? 2.0 : 3.0;
		edge_coordinate = radial_uv.x * boundary_scale + 0.5;
	}

	float lane_count = max(float(speed_line_lanes_per_side), 1.0);
	edge_coordinate = clamp(edge_coordinate, 0.0, 0.99999);
	float lane_index = min(floor(edge_coordinate * lane_count), lane_count - 1.0);
	float global_lane_index = side_index * lane_count + lane_index;
	float timing_jitter = mix(0.15, 0.85, random_lane_value(global_lane_index + 71.6));
	float timing_phase = (lane_index + timing_jitter) / lane_count + side_index * 0.173;
	float spawn_time = time_value * speed_line_spawn_rate + timing_phase;
	float spawn_cycle = floor(spawn_time);
	float spawn_age = fract(spawn_time);
	float event_seed = global_lane_index * 97.3 + spawn_cycle * 53.7;
	float lifetime_variation = mix(0.9, 1.08, random_lane_value(event_seed + 5.4));
	float lifetime = clamp(speed_line_lifetime_fraction * lifetime_variation, 0.05, 0.95);
	float lifetime_fade = min(0.06, lifetime * 0.22);
	float spawn_envelope = smoothstep(0.0, lifetime_fade, spawn_age);
	spawn_envelope *= 1.0 - smoothstep(lifetime - lifetime_fade, lifetime, spawn_age);

	float lane_jitter = mix(0.12, 0.88, random_lane_value(event_seed + 3.1));
	float lane_center = (lane_index + lane_jitter) / lane_count;
	float lane_distance = abs(edge_coordinate - lane_center) * lane_count;
	float lane_width_variation = mix(0.35, 2.15, random_lane_value(event_seed + 11.7));
	float lane_width = speed_line_width * lane_width_variation;
	float lane_feather = max(lane_width * 0.65, 0.002);
	float lane_mask = 1.0 - smoothstep(
		lane_width,
		lane_width + lane_feather,
		lane_distance
	);

	float distance_to_edge = clamp(1.0 / max(boundary_scale, 0.00001), 0.0, 1.0);
	float length_variation = mix(0.55, 1.35, random_lane_value(event_seed + 17.9));
	float streak_length = clamp(speed_line_length * length_variation, 0.08, 0.88);
	float streak_tip = 1.0 - streak_length;
	float tip_feather = mix(0.008, 0.04, random_lane_value(event_seed + 29.5));
	float streak_mask = smoothstep(streak_tip, streak_tip + tip_feather, distance_to_edge);
	float streak_progress = clamp((distance_to_edge - streak_tip) / max(streak_length, 0.001), 0.0, 1.0);
	float life_progress = clamp(spawn_age / max(lifetime, 0.001), 0.0, 1.0);
	float rapid_growth = mix(0.82, 1.0, smoothstep(0.0, 0.18, life_progress));
	float outward_weight = mix(0.22, 1.0, streak_progress) * rapid_growth;
	float brightness_variation = mix(0.58, 1.0, random_lane_value(event_seed + 41.3));
	return lane_mask * streak_mask * outward_weight * brightness_variation * spawn_envelope;
}

void fragment() {
	vec2 radial_uv = SCREEN_UV - vec2(0.5);
	vec2 aspect_position = radial_uv * vec2(viewport_aspect, 1.0);
	float radial_distance = length(aspect_position);

	float pulse_phase = time_offset * pulse_frequency * TAU;
	float pulse_wave = sin(pulse_phase) * 0.68 + sin(pulse_phase * 0.47 + 1.7) * 0.32;
	float pulse = 1.0 + pulse_wave * pulse_amount;
	float mask_radius_shift = pulse_wave * pulse_amount * 0.035;
	float edge_mask = smoothstep(
		vignette_inner_radius + mask_radius_shift,
		max(vignette_outer_radius + mask_radius_shift, vignette_inner_radius + 0.001),
		radial_distance
	);

	float active_intensity = max(intensity, 0.0);
	float blur_distance = max_blur_radius * active_intensity * pulse;
	vec2 half_pixel = SCREEN_PIXEL_SIZE * 0.5;
	vec2 blur_step = radial_uv * blur_distance / float(SAMPLE_COUNT - 1);
	vec2 sample_uv = SCREEN_UV;
	vec3 blurred_color = vec3(0.0);
	float total_weight = 0.0;

	for (int sample_index = 0; sample_index < SAMPLE_COUNT; sample_index++) {
		float sample_t = float(sample_index) / float(SAMPLE_COUNT - 1);
		float sample_weight = mix(1.0, 0.85, sample_t);
		vec2 clamped_uv = clamp(sample_uv, half_pixel, vec2(1.0) - half_pixel);
		blurred_color += texture(SCREEN_TEXTURE, clamped_uv).rgb * sample_weight;
		total_weight += sample_weight;
		sample_uv -= blur_step;
	}

	blurred_color /= total_weight;
	float color_split = chromatic_separation * active_intensity * edge_mask * pulse;
	if (color_split > 0.000001) {
		vec2 streak_mid_uv = SCREEN_UV - radial_uv * blur_distance * 0.5;
		vec2 far_uv = clamp(
			streak_mid_uv - radial_uv * color_split,
			half_pixel,
			vec2(1.0) - half_pixel
		);
		vec2 near_uv = clamp(
			streak_mid_uv + radial_uv * color_split,
			half_pixel,
			vec2(1.0) - half_pixel
		);
		vec3 chromatic_color = blurred_color;
		chromatic_color.r = texture(SCREEN_TEXTURE, far_uv).r;
		chromatic_color.b = texture(SCREEN_TEXTURE, near_uv).b;
		float chromatic_mix = clamp(active_intensity * edge_mask * 0.04, 0.0, 0.06);
		blurred_color = mix(blurred_color, chromatic_color, chromatic_mix);
	}

	float speed_line_mask = get_speed_line_mask(radial_uv, time_offset);
	float speed_line_strength = clamp(
		speed_line_mask * speed_line_opacity * active_intensity,
		0.0,
		0.4
	);
	blurred_color = mix(blurred_color, vec3(1.0), speed_line_strength);

	float mask_alpha = clamp(edge_mask * active_intensity * max_opacity * pulse, 0.0, 1.0);
	float speed_line_alpha = clamp(
		speed_line_mask * active_intensity * clamp(speed_line_opacity * 4.0, 0.0, 1.0) * 0.65,
		0.0,
		0.85
	);
	mask_alpha = max(mask_alpha, speed_line_alpha);
	COLOR = vec4(blurred_color, mask_alpha);
}
