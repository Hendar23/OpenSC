shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
#include "res://natural_light.gdshaderinc"
uniform float daylight = 1.0;
uniform float night_brightness = 0.18;
uniform float wave_height = 0.04;
uniform float wave_size = 4.0;
uniform float wave_speed = 0.8;
uniform float wave_direction = 0.436;
uniform float surface_shine = 0.35;
uniform vec3 sun_direction = vec3(0.0,1.0,0.0);

varying vec3 world_position;

vec3 wave_sample(vec2 point) {
	vec2 first = vec2(cos(wave_direction),sin(wave_direction));
	vec2 second = vec2(cos(wave_direction + 1.2),sin(wave_direction + 1.2));
	float frequency = 6.283185 / max(wave_size,0.2);
	float a = dot(point,first) * frequency + TIME * wave_speed;
	float b = dot(point,second) * frequency * 1.37 - TIME * wave_speed * 0.83;
	float height = wave_height * (sin(a) * 0.65 + sin(b) * 0.35);
	vec2 slope = wave_height * frequency * (cos(a) * first * 0.65 + cos(b) * second * 0.35 * 1.37);
	// Fine ripples contribute normals without needing a dense geometry grid.
	float detail = dot(point,second) * frequency * 6.0 + TIME * wave_speed * 1.7;
	slope += second * cos(detail) * wave_height * frequency * 0.3;
	return vec3(height,slope.x,slope.y);
}

void vertex() {
	vec3 point = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	VERTEX.y += wave_sample(point.xz).x;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 waves = wave_sample(world_position.xz);
	vec3 normal = normalize(vec3(-waves.y,1.0,-waves.z));
	vec3 view = normalize((INV_VIEW_MATRIX * vec4(VIEW,0.0)).xyz);
	float grazing = pow(1.0 - abs(dot(normal,view)),4.0);
	float ripple = clamp(waves.x / max(wave_height,0.001) * 0.5 + 0.5,0.0,1.0);
	vec3 daytime = mix(vec3(0.04,0.35,0.43),vec3(0.16,0.52,0.6),ripple);
	daytime = mix(daytime,vec3(0.025,0.16,0.2),grazing * 0.65);
	vec3 nighttime = vec3(0.008,0.022,0.048) * (night_brightness / 0.18);
	vec3 through_surface = normalize(-view + vec3(waves.y,0.0,waves.z) * 1.8);
	float glint = pow(max(dot(through_surface,sun_direction),0.0),90.0) * max(sun_direction.y,0.0);
	ALBEDO = mix(nighttime,daytime,daylight) + vec3(1.0,0.96,0.82) * glint * surface_shine * daylight * 1.8;
	// The sunlit surface uses outdoor water fog even when the camera is in
	// a cave. Its distance fade still blends the far plane into open water.
	ALBEDO = mix(ALBEDO,osc_natural_fog_color.rgb,natural_fog_amount(length(VERTEX)));
}
