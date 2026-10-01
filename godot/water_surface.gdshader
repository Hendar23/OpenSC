shader_type spatial;
render_mode unshaded, cull_disabled;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float ripple = sin(world_position.x * 1.7 + TIME * 0.65)
		* sin(world_position.z * 1.3 - TIME * 0.45);
	ALBEDO = mix(vec3(0.08, 0.25, 0.28), vec3(0.2, 0.45, 0.43), ripple * 0.5 + 0.5);
}
