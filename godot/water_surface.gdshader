shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float daylight = 1.0;
uniform float night_brightness = 0.18;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float ripple = sin(world_position.x * 1.7 + TIME * 0.65)
		* sin(world_position.z * 1.3 - TIME * 0.45);
	vec3 daytime = mix(vec3(0.08, 0.25, 0.28), vec3(0.2, 0.45, 0.43), ripple * 0.5 + 0.5);
	vec3 nighttime = mix(vec3(0.008, 0.02, 0.045), vec3(0.018, 0.05, 0.09), ripple * 0.5 + 0.5) * (night_brightness / 0.18);
	ALBEDO = mix(nighttime, daytime, daylight);
}
