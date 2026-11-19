shader_type canvas_item;
render_mode unshaded;
uniform sampler2D window_mask : filter_linear, repeat_disable;
uniform bool backdrop = false;
uniform vec2 layout_origin;
uniform vec2 layout_size;
uniform vec2 viewport_size;
void fragment() {
	vec2 uv = backdrop ? (SCREEN_UV * viewport_size - layout_origin) / layout_size : UV;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	float hole = texture(window_mask, clamp(uv, vec2(0.0), vec2(1.0))).a * inside;
	vec4 art = backdrop ? vec4(0.0, 0.0, 0.0, 1.0) : texture(TEXTURE, UV);
	COLOR = vec4(art.rgb, art.a * (1.0 - hole));
}
