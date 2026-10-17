shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, ambient_light_disabled, fog_disabled;
#include "res://natural_light.gdshaderinc"

uniform vec3 glass_tint : source_color = vec3(0.82,0.94,0.96);
uniform float scratch_strength = 0.4;
uniform float scratch_count = 4.0;
uniform float scratch_length = 0.12;
uniform float scratch_width = 0.0008;
uniform float inner_reflection_mix = 0.75;
uniform float reflection_strength = 0.4;
uniform float grime_strength = 0.08;
uniform float roughness_value = 0.14;
varying vec3 world_position;
varying vec2 glass_uv;
uniform bool scene_reflections_ready = false;
uniform sampler2D reflection_face_0 : source_color, filter_linear, repeat_disable;
uniform sampler2D reflection_face_1 : source_color, filter_linear, repeat_disable;
uniform sampler2D reflection_face_2 : source_color, filter_linear, repeat_disable;
uniform sampler2D reflection_face_3 : source_color, filter_linear, repeat_disable;
uniform sampler2D reflection_face_4 : source_color, filter_linear, repeat_disable;
uniform sampler2D reflection_face_5 : source_color, filter_linear, repeat_disable;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453); }
vec3 scene_reflection(vec3 ray) {
	vec3 a = abs(ray);
	vec2 uv;
	if (a.x >= a.y && a.x >= a.z) {
		uv = vec2(ray.x > 0.0 ? ray.z : -ray.z,-ray.y) / a.x * 0.5 + 0.5;
		return ray.x > 0.0 ? texture(reflection_face_0,uv).rgb : texture(reflection_face_1,uv).rgb;
	}
	if (a.y >= a.z) {
		uv = vec2(ray.y > 0.0 ? ray.x : -ray.x,-ray.z) / a.y * 0.5 + 0.5;
		return ray.y > 0.0 ? texture(reflection_face_2,uv).rgb : texture(reflection_face_3,uv).rgb;
	}
	uv = vec2(ray.z > 0.0 ? -ray.x : ray.x,-ray.y) / a.z * 0.5 + 0.5;
	return ray.z > 0.0 ? texture(reflection_face_4,uv).rgb : texture(reflection_face_5,uv).rgb;
}
float noise(vec2 p) {
	vec2 cell = floor(p); vec2 q = fract(p); q = q*q*(3.0-2.0*q);
	return mix(mix(hash(cell),hash(cell+vec2(1,0)),q.x),mix(hash(cell+vec2(0,1)),hash(cell+vec2(1,1)),q.x),q.y);
}
float smudges(vec2 uv) {
	vec2 p = uv * vec2(19.0,29.0);
	float mottles = noise(p) * 0.6 + noise(p*3.2) * 0.4;
	float wiped = sin(length((uv-vec2(0.28,0.12))*vec2(1.0,0.7))*155.0 + noise(uv*35.0)*2.0)*0.5+0.5;
	return smoothstep(0.46,0.8,mottles)*mix(0.5,1.0,wiped)*grime_strength;
}
// Scratch coverage is evaluated per fragment; geometry only carries position.

float marks_at(vec2 uv) {
	float coverage = 0.0;
	for (int i = 0; i < 12; i++) {
		if (float(i) >= scratch_count) { break; }
		float seed = float(i);
		vec2 centre = vec2(0.24 + hash(vec2(seed,4.0))*0.52,0.28 + hash(vec2(seed,8.0))*0.44);
		float angle = hash(vec2(seed,12.0))*3.14;
		vec2 q = uv-centre;
		q = mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle))) * q;
		float distance_to_line = abs(q.x + q.y*q.y*0.3);
		float width = max(fwidth(distance_to_line)*0.75,scratch_width);
		float line = 1.0-smoothstep(width*0.35,width*1.5,distance_to_line);
		float ends = 1.0-smoothstep(scratch_length*0.35,scratch_length*0.5,abs(q.y));
		coverage = max(coverage,line*ends);
	}
	return coverage * scratch_strength;
}
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	glass_uv = UV;
}
void fragment() {
	float scratch = marks_at(UV);
	ALBEDO = vec3(1.0);
	ALPHA = 1.0;
	ROUGHNESS = roughness_value + scratch * 0.12 + grime_strength * 0.02;
	SPECULAR = 0.0;
	if (scene_reflections_ready) {
		vec3 normal = normalize(NORMAL);
		vec3 reflected_view = reflect(-normalize(VIEW),normal);
		vec3 ray = normalize(mat3(INV_VIEW_MATRIX) * reflected_view);
		// The inner surface also returns a weak ghost of the transmitted world.
		// Mirror its depth across the glass to approximate that second interface;
		// nearby forward objects then appear across the opposite curved edge.
		vec3 inner_ray = normalize(mat3(INV_VIEW_MATRIX) * (reflected_view * vec3(1.0,1.0,-1.0)));
		float fresnel = pow(1.0-abs(dot(normal,normalize(VIEW))),3.0);
		float dirt = smudges(UV);
		vec3 reflected = mix(scene_reflection(ray),scene_reflection(inner_ray),inner_reflection_mix);
		// Dirt scatters the captured image instead of painting an opaque grey blob.
		vec3 blurred = (scene_reflection(normalize(inner_ray+vec3(0.018,0,0))) + scene_reflection(normalize(inner_ray-vec3(0.018,0,0))) + scene_reflection(normalize(inner_ray+vec3(0,0.018,0))) + scene_reflection(normalize(inner_ray-vec3(0,0.018,0)))) * 0.25;
		EMISSION = mix(reflected,blurred,clamp(dirt*2.0,0.0,1.0)) * clamp(reflection_strength * (0.8 + fresnel * 1.4 + dirt * 0.35),0.0,0.7);
	}
}
void light() {
	float scratch = marks_at(glass_uv);

	vec3 normal = normalize(NORMAL);
	if (dot(normal,VIEW) < 0.0) normal = -normal;
	vec3 half_direction = normalize(LIGHT + VIEW);
	float facing = max(dot(normal,half_direction),0.0);
	float side = pow(1.0-abs(dot(normal,normalize(LIGHT))),2.0);
	float dirt = smudges(glass_uv);
	float scored = scratch * (side * 1.8 + pow(facing,22.0) * 0.9);
	float scattered = dirt * (side * 0.012 + pow(facing,45.0) * 0.025);
	float exposure = LIGHT_IS_DIRECTIONAL ? natural_visibility(world_position) : 1.0;
	// Only fine surface defects scatter direct light. Smooth glass reflects the
	// captured scene above, avoiding the old broad white spotlight patches.
	DIFFUSE_LIGHT += glass_tint * LIGHT_COLOR * ATTENUATION * exposure * (scored + scattered) * 0.32;
}
