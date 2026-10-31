shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

/** Collection trail tint and base opacity. */
uniform vec4 trail_tint : source_color = vec4(0.14, 0.78, 1.0, 0.85);
/** Opacity remaining after collection completes. */
uniform float trail_fade = 1.0;
/** Maps the occupied ribbon sections onto the full trail length. */
uniform float progress_scale = 1.0;
/** Fraction of the oldest trail that fades in. */
uniform float tail_fade_fraction = 0.12;
/** Fraction of the newest trail that fades out. */
uniform float head_fade_fraction = 0.08;
/** Minimum opacity at the newest point. */
uniform float head_min_opacity = 0.2;

void fragment() {
	float progress = clamp(UV.y * progress_scale, 0.0, 1.0);
	float opacity = 1.0;
	if (tail_fade_fraction > 0.001) {
		opacity *= clamp(progress / tail_fade_fraction, 0.0, 1.0);
	}
	if (head_fade_fraction > 0.001) {
		opacity *= clamp((1.0 - progress) / head_fade_fraction, head_min_opacity, 1.0);
	}
	ALBEDO = trail_tint.rgb;
	ALPHA = trail_tint.a * trail_fade * opacity;
}
