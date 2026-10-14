shader_type canvas_item;
uniform float age = 0.0;
void fragment() {
	vec2 uv = UV;
	float amplitude = 0.035 * exp(-age * 2.5);
	uv.x += sin(uv.y * 35.0 + age * 14.0) * amplitude;
	uv.y += sin(uv.x * 24.0 - age * 11.0) * amplitude;
	COLOR *= texture(TEXTURE,uv);
}
