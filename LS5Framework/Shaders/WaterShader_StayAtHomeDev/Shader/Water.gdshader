shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// Godot 4.5: use `hint_screen_texture` / `hint_depth_texture` uniforms.
// Avoid naming them `SCREEN_TEXTURE` / `DEPTH_TEXTURE` (legacy built-ins removed).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

// Global graphics options (set via SettingsManager -> Graphics).
// These keep all water materials in sync without per-material edits.
global uniform bool water_displacement_enabled = true;
global uniform bool water_refraction_enabled = true;
global uniform bool water_normal_maps_enabled = true;
global uniform bool water_depth_effects_enabled = true;
// Water SSR is tied to the global SSR toggle to avoid mismatched reflection settings.
global uniform bool water_ssr_enabled = true;

uniform vec3 albedo : source_color = vec3(0.05, 0.20, 0.28);
uniform vec3 albedo2 : source_color = vec3(0.02, 0.10, 0.14);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.04;
uniform float alpha : hint_range(0.0, 1.0) = 0.85;

uniform sampler2D wave : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D texture_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D texture_normal2 : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;

// UV scaling for displacement and normals (tiling).
instance uniform float height_scale = 0.15;
instance uniform float clipmap_lod_scale = 0.0;
instance uniform float clipmap_inner_radius = 0.0;
instance uniform float clipmap_outer_radius = 0.0;
instance uniform float clipmap_displacement_fade_start = 0.0;
uniform float wave_uv_scale = 1.0;
uniform float normal_uv_scale = 1.0;
uniform float normal2_uv_scale = 1.0;

uniform vec2 wave_direction = vec2(2.0, 0.0);
uniform vec2 wave_direction2 = vec2(0.0, 1.0);
uniform float time_scale : hint_range(0.0, 0.2, 0.005) = 0.025;
uniform float noise_scale = 10.0;
uniform float height_offset = 0.0;

uniform float normal_detail_fade_start = 500.0;
uniform float normal_detail_fade_end = 4000.0;
uniform float distant_normal_strength : hint_range(0.0, 1.0) = 0.2;
uniform float specular_aa_strength : hint_range(0.0, 2.0) = 0.35;
uniform float distant_roughness : hint_range(0.0, 1.0) = 0.3;
uniform float ssr_camera_fade_start = 750.0;
uniform float ssr_camera_fade_end = 3000.0;
uniform float water_scatter_strength : hint_range(0.0, 0.5) = 0.06;
uniform float gi_fallback_fade_start = 650.0;
uniform float gi_fallback_fade_end = 1300.0;
uniform float gi_fallback_irradiance : hint_range(0.0, 2.0) = 0.45;
uniform float gi_fallback_near_blend : hint_range(0.0, 1.0) = 0.35;

uniform vec4 color_deep : source_color = vec4(0.02, 0.06, 0.10, 1.0);
uniform vec4 color_shallow : source_color = vec4(0.10, 0.35, 0.40, 1.0);

// Depth shading controls (in world units along the view direction).
uniform float shallow_depth : hint_range(0.0, 20.0, 0.05) = 0.5;
uniform float deep_depth : hint_range(0.0, 200.0, 0.1) = 6.0;
uniform float depth_offset : hint_range(-10.0, 10.0, 0.01) = 0.0;

// Beer-Lambert absorption (how quickly water absorbs the refracted scene).
uniform float beers_law : hint_range(0.0, 10.0, 0.05) = 2.0;

// Edge/shore foam (also based on thickness).
uniform vec3 edge_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float edge_start : hint_range(0.0, 5.0, 0.01) = 0.02;
uniform float edge_width : hint_range(0.0, 5.0, 0.01) = 0.20;
uniform float edge_strength : hint_range(0.0, 2.0, 0.01) = 1.0;

// Screen refraction (offset screen sampling by normal).
uniform float refraction_strength : hint_range(0.0, 0.2, 0.001) = 0.03;
uniform float refraction_mip_scale : hint_range(0.0, 8.0, 0.05) = 2.5;

// Screen-space reflections (SSR) for water surface (custom ray march).
uniform float ssr_strength : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float ssr_max_distance : hint_range(0.0, 300.0, 0.1) = 80.0;
uniform int ssr_max_steps : hint_range(4, 128, 1) = 48;
uniform float ssr_stride : hint_range(0.1, 5.0, 0.05) = 1.0;
uniform float ssr_thickness : hint_range(0.01, 5.0, 0.01) = 0.35;
uniform float ssr_start_offset : hint_range(0.0, 2.0, 0.01) = 0.1;
uniform float ssr_fade_start : hint_range(0.0, 1.0, 0.01) = 0.6;
uniform float ssr_fade_end : hint_range(0.0, 1.0, 0.01) = 0.95;
uniform float ssr_edge_fade : hint_range(0.0, 0.25, 0.005) = 0.05;
uniform float ssr_roughness_mip : hint_range(0.0, 8.0, 0.05) = 4.0;

varying vec3 world_pos;
varying vec3 flat_world_pos;
varying float texture_lod;


float fresnel_term(float amount, vec3 normal, vec3 view_dir) {
	return pow(1.0 - clamp(dot(normalize(normal), normalize(view_dir)), 0.0, 1.0), amount);
}


vec3 unpack_normal(vec3 c) {
	return normalize(c * 2.0 - 1.0);
}


vec3 pack_normal(vec3 n) {
	return n * 0.5 + 0.5;
}

float linearize_depth(float raw_depth, vec2 screen_uv, mat4 inv_proj) {
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, raw_depth);
	vec4 view = inv_proj * vec4(ndc, 1.0);
	if (abs(view.w) > 0.000001) {
		view.xyz /= view.w;
	}
	return max(-view.z, 0.0);
}


vec2 view_to_uv(vec3 view_pos, mat4 proj) {
	vec4 clip = proj * vec4(view_pos, 1.0);
	vec3 ndc = clip.xyz / clip.w;
	return ndc.xy * 0.5 + 0.5;
}


bool ssr_trace(vec3 view_pos, vec3 refl_dir, mat4 proj, mat4 inv_proj, out vec2 hit_uv, out float hit_t) {
	hit_uv = vec2(0.0);
	hit_t = 0.0;

	float max_distance = max(ssr_max_distance, 0.0);
	if (max_distance <= 0.0) {
		return false;
	}

	float stride = max(ssr_stride, 0.001);
	float thickness = max(ssr_thickness, 0.0001);
	float t = max(ssr_start_offset, 0.0);

	for (int i = 0; i < ssr_max_steps; i++) {
		t += stride;
		if (t > max_distance) {
			break;
		}

		vec3 ray_view = view_pos + refl_dir * t;
		vec2 uv = view_to_uv(ray_view, proj);
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			break;
		}

		float raw_depth = texture(depth_tex, uv).r;
		if (raw_depth <= 0.000001 || raw_depth >= 0.999999) {
			continue;
		}

		float scene_depth = linearize_depth(raw_depth, uv, inv_proj);
		float ray_depth = -ray_view.z;
		float depth_delta = ray_depth - scene_depth;
		if (depth_delta > 0.0 && depth_delta < thickness) {
			hit_uv = uv;
			hit_t = t;
			return true;
		}
	}

	return false;
}


void vertex() {
	// Sample waves in world-space XZ for stable tiling.
	vec3 base_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 sample_pos = base_world_pos.xz;
	texture_lod = 0.0;
	float displacement_weight = 1.0;
	if (clipmap_lod_scale > 0.0) {
		float camera_distance = distance(base_world_pos.xz, CAMERA_POSITION_WORLD.xz);
		float fade_start = max(clipmap_displacement_fade_start, clipmap_inner_radius);
		if (camera_distance > fade_start) {
			displacement_weight = fade_start / max(camera_distance, 0.001);
			texture_lod = clamp(log2(camera_distance / max(fade_start, 0.001)), 0.0, clipmap_lod_scale);
		}
		float horizon_start = clipmap_outer_radius * 0.75;
		float horizon_end = max(clipmap_outer_radius, horizon_start + 0.001);
		displacement_weight *= 1.0 - smoothstep(horizon_start, horizon_end, camera_distance);
	}
	VERTEX.y += height_offset;
	flat_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_pos = flat_world_pos;
	
	if (water_displacement_enabled) {
		float h = textureLod(wave, (sample_pos / max(noise_scale, 0.0001)) * wave_uv_scale + TIME * time_scale, texture_lod).r;
		float h_mean = textureLod(wave, vec2(0.5), 10.0).r;
		VERTEX.y += (h - h_mean) * height_scale * displacement_weight;
		
		// Update world position after displacement for accurate depth computations.
		world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}
}


void fragment() {
	// Pass the projection matrix into helper functions to keep 4.6 shader parsing happy.
	mat4 proj = PROJECTION_MATRIX;
	mat4 inv_proj = INV_PROJECTION_MATRIX;
	vec3 view_pos = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
	float view_distance = length(view_pos);
	float detail_fade_end = max(normal_detail_fade_end, normal_detail_fade_start + 0.001);
	float detail_fade = smoothstep(normal_detail_fade_start, detail_fade_end, view_distance);
	float water_depth = linearize_depth(FRAGCOORD.z, SCREEN_UV, inv_proj);

	bool no_scene_hit = true;
	float thickness = 0.0;
	float scene_depth = 0.0;
	float depth_blend = 1.0;
	float edge_factor = 0.0;
	float absorption = 0.0;
	if (water_depth_effects_enabled) {
		// Scene depth at this pixel.
		float raw_depth = texture(depth_tex, SCREEN_UV).r;

		// If depth is ~1.0, there is no geometry behind (sky). Treat as "deep water".
		no_scene_hit = raw_depth <= 0.000001 || raw_depth >= 0.999999;

		if (!no_scene_hit) {
			// Convert non-linear depth texture to view-space distance using projection matrix.
			// Godot's depth texture is already in projection space (0..1),
			// matching the reconstruction used by the other water shaders.
			scene_depth = linearize_depth(raw_depth, SCREEN_UV, inv_proj);
		} else {
			scene_depth = water_depth + max(max(shallow_depth, deep_depth), 0.0) + max(depth_offset, 0.0) + 1.0;
		}
		thickness = max((scene_depth - water_depth) + depth_offset, 0.0);

		// Depth blend (0 = shallow, 1 = deep).
		float d0 = min(shallow_depth, deep_depth);
		float d1 = max(shallow_depth, deep_depth + 0.0001);
		depth_blend = smoothstep(d0, d1, thickness);

		// Edge/foam factor:
		// Use absolute depth gap so foam appears when objects touch/intersect the water surface,
		// regardless of whether the object is slightly in front of or behind the water plane.
		if (!no_scene_hit) {
			float depth_gap = abs(scene_depth - water_depth) + max(depth_offset, 0.0);
			float a = max(edge_start, 0.0);
			float b = max(edge_start + edge_width, a + 0.0001);
			edge_factor = (1.0 - smoothstep(a, b, depth_gap)) * clamp(edge_strength, 0.0, 2.0);
			edge_factor = clamp(edge_factor, 0.0, 1.0);
		}

		// Absorption: more thickness = less of the background scene shows through.
		if (water_refraction_enabled) {
			absorption = exp(-beers_law * thickness);
			absorption = clamp(absorption, 0.0, 1.0);
		}
	}

	// Normal maps (world-space UVs, mixed and normalized).
	vec3 n_mix = vec3(0.0, 0.0, 1.0);
	if (water_normal_maps_enabled) {
		vec2 sample_pos = flat_world_pos.xz;
		vec2 t1 = (TIME * wave_direction) * time_scale;
		vec2 t2 = (TIME * wave_direction2) * time_scale;
		vec2 uv1 = sample_pos * normal_uv_scale + t1;
		vec2 uv2 = sample_pos * normal2_uv_scale + t2;
		float gradient_scale = exp2(max(texture_lod, 0.0));

		vec3 n1 = unpack_normal(textureGrad(texture_normal, uv1, dFdx(uv1) * gradient_scale, dFdy(uv1) * gradient_scale).rgb);
		vec3 n2 = unpack_normal(textureGrad(texture_normal2, uv2, dFdx(uv2) * gradient_scale, dFdy(uv2) * gradient_scale).rgb);
		n_mix = normalize(mix(n1, n2, 0.5));
		float normal_strength = mix(1.0, clamp(distant_normal_strength, 0.0, 1.0), detail_fade);
		n_mix = normalize(mix(vec3(0.0, 0.0, 1.0), n_mix, normal_strength));
		
		// Two-sided water: flip tangent-space XY on backfaces so normals don't look inverted underwater.
		if (!FRONT_FACING) {
			n_mix.xy = -n_mix.xy;
		}
	}
	NORMAL_MAP = pack_normal(n_mix);

	// View-space normal (tangent-space normal map -> view space).
	vec3 view_normal = normalize(NORMAL);
	if (water_normal_maps_enabled) {
		vec3 t = normalize(TANGENT);
		vec3 b = normalize(BINORMAL);
		vec3 n = normalize(NORMAL);
		mat3 tbn = mat3(t, b, n);
		view_normal = normalize(tbn * n_mix);
	}

	vec3 view_dir = normalize(VIEW);
	vec3 normal_dx = dFdx(n_mix);
	vec3 normal_dy = dFdy(n_mix);
	float normal_variance = max(dot(normal_dx, normal_dx), dot(normal_dy, normal_dy));
	float filtered_roughness = sqrt(roughness * roughness + normal_variance * max(specular_aa_strength, 0.0));
	filtered_roughness = max(filtered_roughness, mix(roughness, distant_roughness, detail_fade));
	filtered_roughness = clamp(filtered_roughness, 0.0, 1.0);

	// Refraction: distort screen UV by the mixed normal.
	vec3 scene_col = vec3(1.0);
	// Skip screen sampling when depth effects are off to avoid unnecessary texture fetches.
	if (water_refraction_enabled && water_depth_effects_enabled && !no_scene_hit) {
		vec2 refr_uv = SCREEN_UV + n_mix.xy * refraction_strength;
		scene_col = textureLod(screen_tex, refr_uv, depth_blend * refraction_mip_scale).rgb;
	}
	vec3 water_tint = mix(color_shallow.rgb, color_deep.rgb, depth_blend);

	// Combine scene refraction + tint.
	vec3 base_col = mix(water_tint, scene_col * water_tint, absorption);

	// Add a simple fresnel-based surface tint.
	float f = fresnel_term(5.0, view_normal, view_dir);
	vec3 surface_col = mix(albedo, albedo2, f);
	vec3 col = mix(base_col, surface_col, f * 0.35);
	vec3 scatter_col = mix(color_shallow.rgb, color_deep.rgb, clamp(depth_blend * 0.65, 0.0, 1.0));

	// Screen-space reflections (custom SSR, based on depth buffer).
	if (water_ssr_enabled && ssr_strength > 0.0 && !no_scene_hit) {
		vec2 hit_uv = vec2(0.0);
		float hit_t = 0.0;
		vec3 refl_dir = normalize(reflect(-view_dir, view_normal));
		if (refl_dir.z < -0.0001) {
			bool hit = ssr_trace(view_pos, refl_dir, proj, inv_proj, hit_uv, hit_t);
			if (hit) {
				float min_edge = min(min(hit_uv.x, 1.0 - hit_uv.x), min(hit_uv.y, 1.0 - hit_uv.y));
				float edge_fade = smoothstep(0.0, max(ssr_edge_fade, 0.0001), min_edge);

				float max_distance = max(ssr_max_distance, 0.0001);
				float dist_ratio = clamp(hit_t / max_distance, 0.0, 1.0);
				float fade_start = clamp(ssr_fade_start, 0.0, 1.0);
				float fade_end = clamp(ssr_fade_end, fade_start + 0.0001, 1.0);
				float dist_fade = 1.0 - smoothstep(fade_start, fade_end, dist_ratio);

				float lod = clamp(filtered_roughness * ssr_roughness_mip, 0.0, ssr_roughness_mip);
				vec3 ssr_col = textureLod(screen_tex, hit_uv, lod).rgb;
				float ssr_camera_end = max(ssr_camera_fade_end, ssr_camera_fade_start + 0.001);
				float camera_fade = 1.0 - smoothstep(ssr_camera_fade_start, ssr_camera_end, view_distance);
				float ssr_mix = clamp(ssr_strength * edge_fade * dist_fade * camera_fade * f, 0.0, 1.0);
				col = mix(col, ssr_col, ssr_mix);
			}
		}
	}

	// Foam/edge override.
	col = mix(col, edge_color, edge_factor);

	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	EMISSION = scatter_col * max(water_scatter_strength, 0.0);
	float gi_fade_end = max(gi_fallback_fade_end, gi_fallback_fade_start + 0.001);
	float gi_distance_blend = smoothstep(gi_fallback_fade_start, gi_fade_end, view_distance);
	float gi_fallback_blend = mix(clamp(gi_fallback_near_blend, 0.0, 1.0), 1.0, gi_distance_blend);
	IRRADIANCE = vec4(vec3(max(gi_fallback_irradiance, 0.0)), gi_fallback_blend);
	METALLIC = metallic;
	ROUGHNESS = filtered_roughness;
	ALPHA = alpha;
}
