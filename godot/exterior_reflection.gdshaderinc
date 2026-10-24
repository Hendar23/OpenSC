global uniform bool osc_exterior_enabled;
global uniform bool osc_exterior_ready;
uniform vec4 canopy_original_color : source_color = vec4(0.28,0.34,0.40,1.0);
global uniform sampler2D osc_exterior_face_0 : source_color, filter_linear, repeat_disable;
global uniform sampler2D osc_exterior_face_1 : source_color, filter_linear, repeat_disable;
global uniform sampler2D osc_exterior_face_2 : source_color, filter_linear, repeat_disable;
global uniform sampler2D osc_exterior_face_3 : source_color, filter_linear, repeat_disable;
global uniform sampler2D osc_exterior_face_4 : source_color, filter_linear, repeat_disable;
global uniform sampler2D osc_exterior_face_5 : source_color, filter_linear, repeat_disable;
vec3 exterior_reflection(vec3 ray) {
	vec3 a = abs(ray);
	vec2 uv;
	if (a.x >= a.y && a.x >= a.z) {
		uv = vec2(ray.x > 0.0 ? ray.z : -ray.z,-ray.y) / a.x * 0.5 + 0.5;
		return ray.x > 0.0 ? texture(osc_exterior_face_0,uv).rgb : texture(osc_exterior_face_1,uv).rgb;
	}
	if (a.y >= a.z) {
		uv = vec2(ray.y > 0.0 ? ray.x : -ray.x,-ray.z) / a.y * 0.5 + 0.5;
		return ray.y > 0.0 ? texture(osc_exterior_face_2,uv).rgb : texture(osc_exterior_face_3,uv).rgb;
	}
	uv = vec2(ray.z > 0.0 ? -ray.x : ray.x,-ray.y) / a.z * 0.5 + 0.5;
	return ray.z > 0.0 ? texture(osc_exterior_face_4,uv).rgb : texture(osc_exterior_face_5,uv).rgb;
}
