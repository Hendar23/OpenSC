shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
uniform sampler2D surface_texture : source_color;
uniform bool has_texture = false;
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	vec3 tint = vec3(0.65, 0.88, 1.0);
	if (has_texture) tint = mix(tint, texture(surface_texture, UV).rgb, 0.12);
	ALBEDO = tint * COLOR.rgb;
	// Small wake bubbles need a broad visible edge, even without direct sun.
	ALPHA = (0.16 + 0.7 * rim) * COLOR.a;
	ROUGHNESS = 0.12;
	SPECULAR = 0.8;
	EMISSION = tint * COLOR.rgb * (0.08 + rim * 0.4);
}
