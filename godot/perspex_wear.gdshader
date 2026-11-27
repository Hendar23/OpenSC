shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 key_direction = vec3(-0.48, 0.73, -0.49);
uniform float key_energy = 1.0;
uniform float wear : hint_range(0.0, 8.0) = 1.0;
uniform sampler2D wear_mask : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform bool reflection_ready = false;
uniform float reflection_blend = 0.0;
uniform float reflection_projection_scale = 0.5;
uniform sampler2D reflection_px : source_color, filter_linear, repeat_disable;
uniform sampler2D reflection_nx : source_color, filter_linear, repeat_disable;
uniform sampler2D reflection_py : source_color, filter_linear, repeat_disable;
uniform sampler2D reflection_ny : source_color, filter_linear, repeat_disable;
uniform sampler2D reflection_pz : source_color, filter_linear, repeat_disable;
uniform sampler2D reflection_nz : source_color, filter_linear, repeat_disable;
uniform sampler2D next_reflection_px : source_color, filter_linear, repeat_disable;
uniform sampler2D next_reflection_nx : source_color, filter_linear, repeat_disable;
uniform sampler2D next_reflection_py : source_color, filter_linear, repeat_disable;
uniform sampler2D next_reflection_ny : source_color, filter_linear, repeat_disable;
uniform sampler2D next_reflection_pz : source_color, filter_linear, repeat_disable;
uniform sampler2D next_reflection_nz : source_color, filter_linear, repeat_disable;

varying vec3 surface_normal;

vec3 soft_sample(sampler2D face_texture, vec2 uv, float radius) {
	vec2 step_uv = radius / vec2(textureSize(face_texture, 0));
	return (
		textureLod(face_texture, uv + vec2(step_uv.x, 0.0), 0.0).rgb +
		textureLod(face_texture, uv - vec2(step_uv.x, 0.0), 0.0).rgb +
		textureLod(face_texture, uv + vec2(0.0, step_uv.y), 0.0).rgb +
		textureLod(face_texture, uv - vec2(0.0, step_uv.y), 0.0).rgb
	) * 0.25;
}

vec3 blend_captures(sampler2D current_face, sampler2D next_face, vec2 uv, float radius) {
	vec3 current = soft_sample(current_face, uv, radius);
	if (reflection_blend <= 0.0) {
		return current;
	}
	return mix(current, soft_sample(next_face, uv, radius), reflection_blend);
}

vec3 scene_reflection(vec3 ray, float radius) {
	vec3 axis = abs(ray);
	float dominant = max(axis.x, max(axis.y, axis.z));
	// Neighbouring faces overlap beyond 90 degrees, so the join can be filtered.
	vec3 weight = smoothstep(vec3(0.92), vec3(1.0), axis / dominant);
	vec3 color = vec3(0.0);
	if (weight.x > 0.0) {
		vec2 uv = vec2(ray.x > 0.0 ? ray.z : -ray.z, -ray.y) / axis.x * reflection_projection_scale + 0.5;
		color += weight.x * (ray.x > 0.0
			? blend_captures(reflection_px, next_reflection_px, uv, radius)
			: blend_captures(reflection_nx, next_reflection_nx, uv, radius));
	}
	if (weight.y > 0.0) {
		vec2 uv = vec2(ray.y > 0.0 ? ray.x : -ray.x, -ray.z) / axis.y * reflection_projection_scale + 0.5;
		color += weight.y * (ray.y > 0.0
			? blend_captures(reflection_py, next_reflection_py, uv, radius)
			: blend_captures(reflection_ny, next_reflection_ny, uv, radius));
	}
	if (weight.z > 0.0) {
		vec2 uv = vec2(ray.z > 0.0 ? -ray.x : ray.x, -ray.y) / axis.z * reflection_projection_scale + 0.5;
		color += weight.z * (ray.z > 0.0
			? blend_captures(reflection_pz, next_reflection_pz, uv, radius)
			: blend_captures(reflection_nz, next_reflection_nz, uv, radius));
	}
	return color / (weight.x + weight.y + weight.z);
}

void vertex() {
	surface_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 outward = normalize(surface_normal);
	vec3 toward_eye = normalize(mat3(INV_VIEW_MATRIX) * VIEW);
	float incidence = clamp(dot(outward, -toward_eye), 0.0, 1.0);
	float grazing = 1.0 - incidence;
	vec3 key = normalize(key_direction);

	// The broad lobe represents forward scatter from light outside the acrylic.
	float facing_key = max(dot(outward, key), 0.0);
	float alignment = max(dot(-toward_eye, key), 0.0);
	float scatter = pow(alignment, 12.0) * mix(0.33, 1.0, facing_key) * clamp(key_energy, 0.0, 1.5);
	// Stay inside the circular outline baked into the source image.
	vec2 wear_uv = vec2(0.5) + (UV - vec2(0.5)) * 0.88;
	float wear_pattern = pow(texture(wear_mask, wear_uv).r, 1.35);
	float wear_level = wear_pattern * wear;
	float roughness = clamp(wear_level, 0.0, 1.0);
	float wear_light = wear_level * (0.025 * grazing + 0.30 * scatter);
	wear_light += wear_pattern * max(wear - 2.0, 0.0) * 0.020;
	float fresnel = 0.039 + 0.961 * pow(grazing, 5.0);
	vec3 reflected = vec3(0.0);
	if (reflection_ready) {
		reflected = scene_reflection(reflect(-toward_eye, outward), mix(1.35, 4.5, roughness)) * fresnel;
	}
	ALBEDO = reflected + vec3(0.73, 0.88, 0.91) * wear_light;
	ALPHA = 1.0;
}
