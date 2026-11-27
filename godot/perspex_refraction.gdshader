shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D scene_color : filter_linear, repeat_disable;
uniform float overscan = 1.65;
uniform float bend : hint_range(0.0, 0.85) = 0.40;
uniform float spread : hint_range(0.0, 1.0) = 0.85;
uniform float thickness : hint_range(0.02, 0.40) = 0.045;
uniform vec3 dome_radii;

varying vec3 shell_point;

void vertex() {
	shell_point = VERTEX;
}

vec2 project_ray(vec3 direction, mat4 projection) {
	vec4 clip = projection * vec4(direction, 0.0);
	return clip.xy / clip.w * 0.5 + 0.5;
}

void fragment() {
	const float acrylic_index = 1.49;
	const float water_index = 1.33;
	mat3 dome_to_view = mat3(VIEW_MATRIX * MODEL_MATRIX);
	vec3 incident = normalize(transpose(dome_to_view) * -VIEW);
	vec3 inner_normal = normalize(shell_point / (dome_radii * dome_radii));
	vec3 in_acrylic = refract(incident, -inner_normal, 1.0 / acrylic_index);

	// Intersect the outer ellipsoid in unit sphere coordinates.
	vec3 outer_radii = dome_radii + vec3(thickness);
	vec3 origin = shell_point / outer_radii;
	vec3 direction = in_acrylic / outer_radii;
	float a = dot(direction, direction);
	float b = dot(origin, direction);
	float c = dot(origin, origin) - 1.0;
	float travel = (-b + sqrt(max(0.0, b * b - a * c))) / a;
	vec3 outer_hit = shell_point + in_acrylic * travel;
	vec3 outer_normal = normalize(outer_hit / (outer_radii * outer_radii));
	vec3 in_water = refract(in_acrylic, -outer_normal, acrylic_index / water_index);

	float grazing = 1.0 - clamp(dot(inner_normal, incident), 0.0, 1.0);
	float bend_weight = bend * mix(sqrt(grazing), 1.0, spread);
	vec3 preview_ray = dome_to_view * mix(incident, in_water, bend_weight);
	vec2 shift = project_ray(preview_ray, PROJECTION_MATRIX) - project_ray(-VIEW, PROJECTION_MATRIX);
	vec2 source_uv = (SCREEN_UV + shift - vec2(0.5)) / overscan + vec2(0.5);
	ALBEDO = textureLod(scene_color, source_uv, 0.0).rgb;
	ALPHA = 1.0;
}
