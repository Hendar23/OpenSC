shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec3 sunlight_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 sunlight_color : source_color = vec3(1.0);
uniform float sunlight_energy = 0.0;
uniform float reflection_strength = 0.25;

void fragment() {
	// A broad reflection on the convex CRT glass. Add it over the picture
	// so a matching light angle can visibly wash out even the black areas.
	vec2 curve = (UV - vec2(0.5)) * vec2(0.85, -0.85);
	vec3 glass_normal = normalize(NORMAL + vec3(curve, 0.0));
	vec3 light_direction = normalize(mat3(VIEW_MATRIX) * sunlight_direction);
	vec3 half_direction = normalize(light_direction + normalize(-VERTEX));
	float reflection = pow(max(dot(glass_normal, half_direction), 0.0), 10.0);
	ALBEDO = sunlight_color * sunlight_energy * reflection * 3.0 * reflection_strength;
	ALPHA = 1.0;
}
