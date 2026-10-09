shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, depth_test_disabled;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform float beam_length = 2.4336;
uniform float beam_radius = 0.45;
uniform float beam_brightness = 0.55;
uniform float beam_softness = 0.65;
uniform float brightness_factor = 1.0;
varying vec3 beam_position;

void vertex() {
	beam_position = VERTEX + vec3(0.0, 0.0, beam_length * 0.5);
}

void fragment() {
	vec3 offset = vec3(0.0, 0.0, beam_length * 0.5);
	vec3 camera = (inverse(MODEL_MATRIX) * INV_VIEW_MATRIX[3]).xyz + offset;
	vec3 ray = normalize(beam_position - camera);
	vec3 safe_ray = mix(vec3(0.00001), ray, greaterThan(abs(ray), vec3(0.00001)));
	vec3 first = (vec3(-beam_radius, -beam_radius, 0.0) - camera) / safe_ray;
	vec3 last = (vec3(beam_radius, beam_radius, beam_length) - camera) / safe_ray;
	vec3 low = min(first, last);
	vec3 high = max(first, last);
	float start = max(0.0, max(low.x, max(low.y, low.z)));
	float finish = min(high.x, min(high.y, high.z));
	// Clip the volume at actual scene geometry, including an object inside it.
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	if (CLIP_SPACE_FAR < 0.0) { ndc.z = depth * 2.0 - 1.0; }
	vec4 view_hit = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec4 world_hit = INV_VIEW_MATRIX * vec4(view_hit.xyz / view_hit.w, 1.0);
	vec3 local_hit = (inverse(MODEL_MATRIX) * world_hit).xyz + offset;
	finish = min(finish, length(local_hit - camera));
	float step_size = max(0.0, finish - start) / 24.0;
	float density = 0.0;
	for (int sample_index = 0; sample_index < 24; sample_index++) {
		vec3 point = camera + ray * (start + (float(sample_index) + 0.5) * step_size);
		float along = clamp(point.z / beam_length, 0.0, 1.0);
		float radius = max(0.008, beam_radius * along);
		float radial = length(point.xy) / radius;
		float edge = 1.0 - smoothstep(1.0 - beam_softness, 1.0, radial);
		density += edge * pow(1.0 - along, 1.2) * smoothstep(0.0, 0.04, along) * step_size / beam_radius;
	}
	ALBEDO = vec3(0.8, 0.92, 1.0);
	ALPHA = clamp(density * beam_brightness * brightness_factor, 0.0, 0.85);
}
