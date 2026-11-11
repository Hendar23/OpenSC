shader_type canvas_item;
render_mode unshaded;

uniform float strength : hint_range(0.0, 1.0);
uniform bool clear_recording_indicator = false;
uniform vec4 recording_bounds;

void fragment() {
	vec2 cell = floor(UV * vec2(192.0, 120.0));
	float frame = mod(floor(TIME * 25.0), 256.0);
	float grain = fract(sin(dot(cell, vec2(12.9898, 78.233)) + frame * 17.0) * 43758.5453);
	float band = fract(sin(cell.y * 16.21 + frame * 3.7) * 24317.31);
	float opacity = strength * mix(0.38, 0.94, step(0.76, band));
	if (clear_recording_indicator && all(greaterThanEqual(UV, recording_bounds.xy)) && all(lessThan(UV, recording_bounds.zw))) {
		opacity = 0.0;
	}
	COLOR = vec4(vec3(smoothstep(0.18, 0.88, grain)), opacity);
}
