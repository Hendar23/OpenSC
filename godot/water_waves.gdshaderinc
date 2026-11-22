#include "res://replay_clock.gdshaderinc"

vec3 wave_sample(vec2 point, vec4 wave) {
	vec2 first = vec2(cos(wave.w),sin(wave.w));
	vec2 second = vec2(cos(wave.w + 1.2),sin(wave.w + 1.2));
	float frequency = 6.283185 / max(wave.y,0.2);
	float a = dot(point,first) * frequency + visual_time() * wave.z;
	float b = dot(point,second) * frequency * 1.37 - visual_time() * wave.z * 0.83;
	float height = wave.x * (sin(a) * 0.65 + sin(b) * 0.35);
	vec2 slope = wave.x * frequency * (cos(a) * first * 0.65 + cos(b) * second * 0.35 * 1.37);
	return vec3(height,slope.x,slope.y);
}

vec2 ripple_detail(sampler2D normals, vec2 point, float distance_to_eye, vec4 wave) {
	float time = visual_time() * wave.z;
	vec2 flow = vec2(cos(wave.w),sin(wave.w));
	vec2 cross_flow = vec2(-flow.y,flow.x);
	vec2 uv = vec2(dot(point,flow),dot(point,cross_flow)) / max(wave.y * 2.0,0.4);
	// Three differently scaled, drifting samples break up straight wave bands.
	vec2 broad = texture(normals,uv + vec2(time*0.012,-time*0.008)).xy * 2.0 - 1.0;
	vec2 crossed = texture(normals,mat2(vec2(0.8,0.6),vec2(-0.6,0.8))*uv*1.83 + vec2(-time*0.009,time*0.016)).xy * 2.0 - 1.0;
	vec2 fine = texture(normals,uv*4.17 + broad*0.09 + vec2(time*0.023,time*0.012)).xy * 2.0 - 1.0;
	float detail_fade = 1.0 - smoothstep(20.0,100.0,distance_to_eye);
	vec2 detail = broad*0.65 + crossed*0.45 + fine*0.22*detail_fade;
	return (flow*detail.x + cross_flow*detail.y) * clamp(wave.x/0.04,0.0,2.0);
}

vec3 water_normal(vec2 wave_slope, vec2 detail) {
	vec2 slope = wave_slope*0.25 + detail*0.65;
	return normalize(vec3(-slope.x,1.0,-slope.y));
}
