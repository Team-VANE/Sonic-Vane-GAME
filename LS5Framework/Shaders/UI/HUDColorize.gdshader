shader_type canvas_item;

uniform vec4 tint_color : source_color = vec4(1.0);

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float intensity = max(source.r, max(source.g, source.b));
	COLOR = vec4(tint_color.rgb * intensity, source.a * tint_color.a);
}
