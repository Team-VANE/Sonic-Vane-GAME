shader_type sky;
render_mode use_half_res_pass;

uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);
uniform vec3 zenith_color : source_color = vec3(0.12, 0.38, 0.9);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.78, 1.0);
uniform vec3 ground_color : source_color = vec3(0.035, 0.028, 0.025);
uniform float ground_visibility : hint_range(0.0, 1.0) = 1.0;
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.78);
uniform vec3 moon_color : source_color = vec3(0.72, 0.82, 1.0);
uniform vec3 cloud_light_color : source_color = vec3(1.0, 0.98, 0.94);
uniform vec3 cloud_shadow_color : source_color = vec3(0.35, 0.42, 0.52);

uniform float rayleigh_strength : hint_range(0.0, 8.0) = 2.0;
uniform float mie_strength : hint_range(0.0, 2.0) = 0.08;
uniform float mie_eccentricity : hint_range(-0.99, 0.99) = 0.8;
uniform float turbidity : hint_range(0.1, 20.0) = 4.0;
uniform float sun_angular_radius = 0.004625;
uniform float sun_disk_intensity = 18.0;
uniform float moon_angular_radius = 0.00454;
uniform float moon_disk_intensity = 1.2;
uniform float moon_phase : hint_range(0.0, 1.0) = 0.5;
uniform float star_visibility : hint_range(0.0, 1.0) = 0.0;
uniform float star_intensity = 1.4;
uniform float star_scale = 720.0;
uniform float star_density : hint_range(0.0, 1.0) = 0.28;
uniform float star_lower_hemisphere_visibility : hint_range(0.0, 1.0) = 0.0;
uniform vec3 star_cool_color : source_color = vec3(0.62, 0.72, 1.0);
uniform vec3 star_warm_color : source_color = vec3(1.0, 0.88, 0.68);

uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.35;
uniform float cloud_density : hint_range(0.0, 1.0) = 0.82;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.12;
uniform float cloud_scale = 3.2;
uniform float cloud_detail = 0.72;
uniform float cloud_light_absorption : hint_range(0.0, 1.0) = 0.42;
uniform float cloud_volume_depth : hint_range(0.0, 4.0) = 0.0;
uniform int cloud_volume_steps : hint_range(1, 4) = 1;
uniform float cloud_optical_density : hint_range(0.1, 4.0) = 1.0;
uniform float cloud_core_shadow_strength : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_edge_light_strength : hint_range(0.0, 2.0) = 1.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform float lower_layer_height : hint_range(0.001, 0.25) = 0.022;
uniform float upper_layer_amount : hint_range(0.0, 1.0) = 0.12;
uniform float upper_layer_height : hint_range(0.002, 0.5) = 0.07;
uniform float upper_layer_scale : hint_range(0.1, 4.0) = 0.62;
uniform float upper_layer_wind_multiplier : hint_range(0.0, 5.0) = 1.45;
uniform float distance_fade_start : hint_range(0.0, 0.99) = 0.82;
uniform float distance_fade_end : hint_range(0.01, 1.0) = 0.995;
uniform float distance_haze_strength : hint_range(0.0, 1.0) = 0.78;
uniform bool above_horizon_clouds_enabled = true;
uniform bool below_horizon_clouds_enabled = true;
uniform float below_horizon_visibility : hint_range(0.0, 1.0) = 0.0;
uniform float below_horizon_fade_depth : hint_range(0.01, 1.0) = 0.35;
uniform float below_horizon_scale : hint_range(0.25, 8.0) = 1.0;
uniform float below_horizon_detail : hint_range(0.0, 2.0) = 1.0;
uniform float below_horizon_curvature : hint_range(0.1, 4.0) = 1.0;
uniform float below_horizon_haze_strength : hint_range(0.0, 1.0) = 0.72;

float hash13(vec3 value) {
	value = fract(value * 0.1031);
	value += dot(value, value.yzx + 33.33);
	return fract((value.x + value.y) * value.z);
}


float value_noise(vec3 position) {
	vec3 cell = floor(position);
	vec3 local = fract(position);
	local = local * local * (3.0 - 2.0 * local);

	float n000 = hash13(cell + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(cell + vec3(1.0, 1.0, 1.0));

	float x00 = mix(n000, n100, local.x);
	float x10 = mix(n010, n110, local.x);
	float x01 = mix(n001, n101, local.x);
	float x11 = mix(n011, n111, local.x);
	return mix(mix(x00, x10, local.y), mix(x01, x11, local.y), local.z);
}


float cloud_fbm(vec3 position) {
	float sum = 0.0;
	float weight = 0.55;
	mat3 rotation = mat3(
		vec3(0.00, 0.80, 0.60),
		vec3(-0.80, 0.36, -0.48),
		vec3(-0.60, -0.48, 0.64)
	);
	for (int octave = 0; octave < 4; octave++) {
		sum += value_noise(position) * weight;
		position = rotation * position * 2.03 + vec3(7.1, 3.8, 5.4);
		weight *= 0.5;
	}
	return sum;
}


vec4 cloud_shell_sample(vec3 direction, float layer_height, float layer_scale, float wind_multiplier) {
	float safe_height = max(layer_height, 0.001);
	float shell_radius = 1.0 + safe_height;
	vec3 ray_origin = vec3(0.0, 1.0, 0.0);
	float origin_projection = dot(ray_origin, direction);
	float intersection_term = origin_projection * origin_projection - dot(ray_origin, ray_origin) + shell_radius * shell_radius;
	float travel_distance = -origin_projection + sqrt(max(intersection_term, 0.0));
	vec3 shell_normal = (ray_origin + direction * max(travel_distance, 0.0)) / shell_radius;
	float horizon_distance = sqrt(max(2.0 * safe_height + safe_height * safe_height, 0.0001));
	float footprint_scale = 1.0 / horizon_distance;
	vec3 tangent_coordinates = vec3(shell_normal.x, shell_normal.y - 1.0, shell_normal.z) * footprint_scale;
	vec3 coordinates = tangent_coordinates * cloud_scale * layer_scale + vec3(cloud_offset.x, 0.0, cloud_offset.y) * wind_multiplier;
	float distance_ratio = clamp(travel_distance / horizon_distance, 0.0, 1.0);
	return vec4(coordinates, distance_ratio);
}


vec4 cloud_deck_sample(vec3 direction, float layer_height, float layer_scale, float wind_multiplier) {
	vec3 mirrored_direction = vec3(direction.x, abs(direction.y), direction.z);
	float curved_layer_height = max(layer_height * below_horizon_curvature, 0.001);
	return cloud_shell_sample(mirrored_direction, curved_layer_height, layer_scale * below_horizon_scale, wind_multiplier);
}


float rayleigh_phase(float cosine) {
	return 0.0596831 * (1.0 + cosine * cosine);
}


float mie_phase(float cosine, float eccentricity) {
	float g2 = eccentricity * eccentricity;
	float denominator = pow(max(1.0 + g2 - 2.0 * eccentricity * cosine, 0.001), 1.5);
	return 0.1193662 * (1.0 - g2) * (1.0 + cosine * cosine) / ((2.0 + g2) * denominator);
}


vec3 atmosphere_color(vec3 direction) {
	float above_horizon = clamp(direction.y, 0.0, 1.0);
	float horizon_blend = pow(above_horizon, 0.32);
	vec3 base_sky = mix(horizon_color, zenith_color, horizon_blend);
	float view_air_mass = 1.0 / max(0.08, above_horizon + 0.12);
	float sun_cosine = clamp(dot(direction, sun_direction), -1.0, 1.0);
	float sun_height = smoothstep(-0.16, 0.08, sun_direction.y);
	float haze = mie_phase(sun_cosine, mie_eccentricity) * mie_strength * turbidity;
	float molecular = rayleigh_phase(sun_cosine) * rayleigh_strength;
	vec3 extinction = exp(-vec3(0.12, 0.07, 0.035) * view_air_mass * turbidity * 0.12);
	vec3 scattered = base_sky * extinction;
	scattered += zenith_color * molecular * 0.15 * sun_height;
	scattered += sun_color * haze * 0.18 * sun_height;
	return max(scattered, vec3(0.0));
}


float star_field(vec3 direction) {
	vec3 cell = floor(direction * star_scale);
	float star = hash13(cell);
	float threshold = mix(1.0, 0.975, star_density);
	float brightness = pow(max(star - threshold, 0.0) / max(1.0 - threshold, 0.0001), 6.0);
	float twinkle = 0.72 + hash13(cell + 19.7) * 0.55;
	return brightness * twinkle;
}


vec3 celestial_color(vec3 direction, vec3 sky_color) {
	float sun_cosine = dot(direction, sun_direction);
	float sun_inner = cos(sun_angular_radius);
	float sun_outer = cos(sun_angular_radius * 1.35);
	float sun_disk = smoothstep(sun_outer, sun_inner, sun_cosine);
	float sun_glow = pow(max(sun_cosine, 0.0), 512.0) * smoothstep(-0.12, 0.02, sun_direction.y);
	vec3 result = sky_color + sun_color * (sun_disk * sun_disk_intensity + sun_glow * 0.75 * min(sun_disk_intensity, 1.0));

	float moon_cosine = dot(direction, moon_direction);
	float moon_inner = cos(moon_angular_radius);
	float moon_outer = cos(moon_angular_radius * 1.18);
	float moon_disk = smoothstep(moon_outer, moon_inner, moon_cosine);
	vec3 tangent = normalize(cross(abs(moon_direction.y) > 0.95 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0), moon_direction));
	vec3 bitangent = cross(moon_direction, tangent);
	vec2 moon_local = vec2(dot(direction, tangent), dot(direction, bitangent)) / max(sin(moon_angular_radius), 0.0001);
	float phase_angle = moon_phase * TAU;
	float phase_facing = -cos(phase_angle);
	float phase_side = sin(phase_angle) < 0.0 ? -1.0 : 1.0;
	float terminator = phase_facing + moon_local.x * phase_side * sqrt(max(1.0 - moon_local.y * moon_local.y, 0.0));
	float lit_face = smoothstep(-0.035, 0.035, terminator);
	float lunar_detail = 0.78 + value_noise(direction * 180.0) * 0.22;
	result += moon_color * moon_disk * moon_disk_intensity * mix(0.035, lunar_detail, lit_face);

	float hemisphere_mask = mix(smoothstep(-0.08, 0.12, direction.y), 1.0, star_lower_hemisphere_visibility);
	float stars = star_field(direction) * star_visibility * hemisphere_mask;
	result += mix(star_cool_color, star_warm_color, hash13(floor(direction * star_scale) + 3.1)) * stars * star_intensity;
	return result;
}


vec4 cloud_volume_sample(
	vec3 coordinates,
	float threshold,
	float softness,
	float layer_density,
	float detail_influence,
	vec3 broad_offset,
	vec3 fine_offset,
	vec3 light_direction
) {
	int sample_count = clamp(cloud_volume_steps, 1, 4);
	float sample_count_float = float(sample_count);
	float accumulated_opacity = 0.0;
	float accumulated_density = 0.0;
	float accumulated_shape = 0.0;
	float accumulated_lit_density = 0.0;
	float density_weight = 0.0;
	float light_transmittance = 1.0;
	vec3 volume_axis = normalize(light_direction + vec3(0.0001));
	for (int sample_index = 0; sample_index < 4; sample_index++) {
		if (sample_index >= sample_count) {
			break;
		}
		float slice_position = sample_count > 1 ? 0.5 - float(sample_index) / float(sample_count - 1) : 0.0;
		vec3 sample_coordinates = coordinates + volume_axis * slice_position * cloud_volume_depth;
		float broad_shape = cloud_fbm(sample_coordinates + broad_offset);
		float fine_shape = broad_shape;
		if (detail_influence > 0.001) {
			fine_shape = value_noise(sample_coordinates * 4.7 + fine_offset);
		}
		float shape = mix(broad_shape, broad_shape * 0.78 + fine_shape * 0.32, detail_influence);
		float density = smoothstep(threshold - softness, threshold + softness, shape);
		float base_opacity = clamp(density * layer_density, 0.0, 0.9999);
		float sample_opacity = 1.0 - pow(1.0 - base_opacity, cloud_optical_density / sample_count_float);
		accumulated_opacity += (1.0 - accumulated_opacity) * sample_opacity;
		accumulated_density += density / sample_count_float;
		accumulated_shape += shape / sample_count_float;
		accumulated_lit_density += density * light_transmittance;
		density_weight += density;
		light_transmittance *= 1.0 - sample_opacity;
	}
	float light_visibility = density_weight > 0.0001 ? accumulated_lit_density / density_weight : 1.0;
	return vec4(accumulated_opacity, accumulated_density, accumulated_shape, clamp(light_visibility, 0.0, 1.0));
}


vec4 cloud_layer(vec3 direction) {
	float standard_horizon_mask = smoothstep(-0.015, 0.025, direction.y);
	float upper_horizon_mask = smoothstep(0.0, 0.025, direction.y);
	float lower_hemisphere_depth = max(-direction.y, 0.0);
	float lower_visibility = below_horizon_clouds_enabled ? below_horizon_visibility : 0.0;
	float lower_layer_enabled = smoothstep(0.0, 0.001, lower_visibility);
	float above_mask = mix(standard_horizon_mask, upper_horizon_mask, lower_layer_enabled);
	above_mask *= above_horizon_clouds_enabled ? 1.0 : 0.0;
	float below_mask = smoothstep(0.0, max(below_horizon_fade_depth, 0.01), lower_hemisphere_depth) * lower_visibility;
	if (max(above_mask, below_mask) <= 0.0 || cloud_coverage <= 0.001 || cloud_density <= 0.001) {
		return vec4(0.0);
	}

	float sun_height = smoothstep(-0.18, 0.1, sun_direction.y);
	float moon_height = smoothstep(-0.12, 0.08, moon_direction.y);
	float moon_light_weight = moon_height * (1.0 - sun_height);
	float celestial_light_weight = sun_height + moon_light_weight;
	vec3 volume_light_vector = sun_direction * sun_height + moon_direction * moon_light_weight;
	vec3 volume_light_direction = length(volume_light_vector) > 0.0001 ? normalize(volume_light_vector) : vec3(0.0, 1.0, 0.0);
	vec3 volume_light_color = (sun_color * sun_height + moon_color * moon_light_weight) / max(celestial_light_weight, 0.0001);
	float celestial_light_amount = clamp(celestial_light_weight, 0.0, 1.0);
	float threshold = mix(0.88, 0.27, cloud_coverage);
	float upper_threshold = mix(0.94, 0.5, cloud_coverage);
	float sun_forward_light = pow(max(dot(direction, sun_direction), 0.0), 8.0) * sun_height;
	float moon_forward_light = pow(max(dot(direction, moon_direction), 0.0), 8.0) * moon_light_weight;
	float forward_light = max(sun_forward_light, moon_forward_light);
	float diffuse_light = 0.32 + 0.68 * max(sun_direction.y, 0.0) * sun_height;
	vec3 day_cloud = mix(cloud_shadow_color, cloud_light_color, diffuse_light);
	day_cloud += sun_color * sun_forward_light * (1.0 - cloud_light_absorption) * 0.55;
	vec3 night_cloud = mix(cloud_shadow_color * 0.24, moon_color * 0.42, moon_height);

	vec4 above_cloud = vec4(0.0);
	if (above_mask > 0.0) {
		float safe_fade_end = max(distance_fade_end, distance_fade_start + 0.001);
		vec4 lower_sample = cloud_shell_sample(direction, lower_layer_height, 1.0, 1.0);
		vec4 lower_volume = cloud_volume_sample(
			lower_sample.xyz,
			threshold,
			cloud_softness,
			cloud_density,
			clamp(cloud_detail, 0.0, 2.0) * 0.5,
			vec3(0.0),
			vec3(12.7, 4.3, 8.9),
			volume_light_direction
		);
		float lower_opacity = lower_volume.x * (1.0 - smoothstep(distance_fade_start, safe_fade_end, lower_sample.w));
		vec4 upper_sample = cloud_shell_sample(direction, upper_layer_height, upper_layer_scale, upper_layer_wind_multiplier);
		vec4 upper_volume = cloud_volume_sample(
			upper_sample.xyz,
			upper_threshold,
			cloud_softness * 1.35,
			cloud_density * upper_layer_amount,
			0.0,
			vec3(19.3, 7.1, 31.7),
			vec3(4.8, 23.1, 15.7),
			volume_light_direction
		);
		float upper_opacity = upper_volume.x * (1.0 - smoothstep(distance_fade_start, safe_fade_end, upper_sample.w));
		vec3 lower_color = mix(night_cloud, day_cloud, sun_height);
		vec3 upper_color = mix(night_cloud * 1.08, day_cloud * 1.06, sun_height);
		float lower_depth = smoothstep(threshold, threshold + cloud_softness * 3.0, lower_volume.z);
		float upper_depth = smoothstep(upper_threshold, upper_threshold + cloud_softness * 3.0, upper_volume.z);
		lower_color *= mix(1.0, 0.58, lower_depth * cloud_light_absorption);
		upper_color *= mix(1.0, 0.72, upper_depth * cloud_light_absorption);
		lower_color *= 1.0 - (1.0 - lower_volume.w) * cloud_core_shadow_strength * celestial_light_amount * 0.55;
		upper_color *= 1.0 - (1.0 - upper_volume.w) * cloud_core_shadow_strength * celestial_light_amount * 0.4;
		float edge_illumination = celestial_light_amount * 0.14 + forward_light * 0.66;
		float visible_upper = upper_opacity * (1.0 - lower_opacity);
		float layer_opacity = lower_opacity + visible_upper;
		vec3 layer_color = (lower_color * lower_opacity + upper_color * visible_upper) / max(layer_opacity, 0.0001);
		float combined_edge = sqrt(max(layer_opacity * (1.0 - layer_opacity), 0.0));
		layer_color += volume_light_color * combined_edge * edge_illumination * (1.0 - cloud_light_absorption) * 0.82 * cloud_edge_light_strength;
		float distance_haze = (lower_sample.w * lower_opacity + upper_sample.w * visible_upper) / max(layer_opacity, 0.0001);
		layer_color = mix(layer_color, horizon_color, clamp(distance_haze * distance_haze_strength, 0.0, 1.0));
		above_cloud = vec4(max(layer_color, vec3(0.0)), layer_opacity * above_mask);
	}

	vec4 below_cloud = vec4(0.0);
	if (below_mask > 0.0) {
		vec4 lower_sample = cloud_deck_sample(direction, lower_layer_height, 1.0, 1.0);
		vec4 lower_volume = cloud_volume_sample(
			lower_sample.xyz,
			threshold,
			cloud_softness,
			cloud_density,
			clamp(cloud_detail * below_horizon_detail, 0.0, 2.0) * 0.5,
			vec3(0.0),
			vec3(12.7, 4.3, 8.9),
			volume_light_direction
		);
		vec4 upper_sample = cloud_deck_sample(direction, upper_layer_height, upper_layer_scale, upper_layer_wind_multiplier);
		vec4 upper_volume = cloud_volume_sample(
			upper_sample.xyz,
			upper_threshold,
			cloud_softness * 1.35,
			cloud_density * upper_layer_amount,
			0.0,
			vec3(19.3, 7.1, 31.7),
			vec3(4.8, 23.1, 15.7),
			volume_light_direction
		);
		float lower_opacity = lower_volume.x;
		float upper_opacity = upper_volume.x;
		float top_surface_light = max(volume_light_direction.y, 0.0) * celestial_light_amount;
		vec3 lower_color = mix(night_cloud, day_cloud, sun_height);
		vec3 upper_color = mix(night_cloud * 1.08, day_cloud * 1.06, sun_height);
		lower_color += volume_light_color * top_surface_light * (1.0 - cloud_light_absorption) * 0.28;
		upper_color += volume_light_color * top_surface_light * (1.0 - cloud_light_absorption) * 0.36;
		float lower_depth = smoothstep(threshold, threshold + cloud_softness * 3.0, lower_volume.z);
		float upper_depth = smoothstep(upper_threshold, upper_threshold + cloud_softness * 3.0, upper_volume.z);
		lower_color *= mix(1.0, 0.68, lower_depth * cloud_light_absorption);
		upper_color *= mix(1.0, 0.76, upper_depth * cloud_light_absorption);
		lower_color *= 1.0 - (1.0 - lower_volume.w) * cloud_core_shadow_strength * celestial_light_amount * 0.42;
		upper_color *= 1.0 - (1.0 - upper_volume.w) * cloud_core_shadow_strength * celestial_light_amount * 0.34;
		float edge_illumination = celestial_light_amount * 0.1 + top_surface_light * 0.56;
		float visible_lower = lower_opacity * (1.0 - upper_opacity);
		float layer_opacity = upper_opacity + visible_lower;
		vec3 layer_color = (upper_color * upper_opacity + lower_color * visible_lower) / max(layer_opacity, 0.0001);
		float combined_edge = sqrt(max(layer_opacity * (1.0 - layer_opacity), 0.0));
		layer_color += volume_light_color * combined_edge * edge_illumination * (1.0 - cloud_light_absorption) * 0.9 * cloud_edge_light_strength;
		float deck_distance = (upper_sample.w * upper_opacity + lower_sample.w * visible_lower) / max(layer_opacity, 0.0001);
		float deck_haze = smoothstep(0.45, 1.0, deck_distance) * below_horizon_haze_strength;
		layer_color = mix(layer_color, horizon_color, deck_haze);
		below_cloud = vec4(max(layer_color, vec3(0.0)), layer_opacity * below_mask);
	}

	float opacity = above_cloud.a + below_cloud.a * (1.0 - above_cloud.a);
	vec3 cloud_color = (above_cloud.rgb * above_cloud.a + below_cloud.rgb * below_cloud.a * (1.0 - above_cloud.a)) / max(opacity, 0.0001);
	return vec4(max(cloud_color, vec3(0.0)), opacity);
}


void sky() {
	vec3 direction = normalize(EYEDIR);
	if (AT_HALF_RES_PASS) {
		vec4 clouds = cloud_layer(direction);
		COLOR = clouds.rgb;
		ALPHA = clouds.a;
	} else {
		float ground_mask = smoothstep(-0.08, 0.02, direction.y);
		vec3 sky_color = atmosphere_color(direction);
		vec3 grounded_color = mix(ground_color, sky_color, ground_mask);
		vec3 color = mix(sky_color, grounded_color, ground_visibility);
		color = celestial_color(direction, color);
		color = mix(color, HALF_RES_COLOR.rgb, HALF_RES_COLOR.a);
		COLOR = color;
	}
}
