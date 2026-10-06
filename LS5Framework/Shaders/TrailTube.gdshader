shader_type spatial;
render_mode unshaded, cull_disabled;

varying vec3 world_pos;

float _hash12(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float a = COLOR.a;
	float h = _hash12(world_pos.xy);
	if (a < h) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ALPHA = 1.0;
}
