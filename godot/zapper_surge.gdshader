shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled;

uniform float arc_scale = 1.0;
uniform float arc_phase = 0.0;
uniform float arc_strength = 1.0;
varying vec3 hull_point;

void vertex() {
	// Use model-local coordinates so the pattern follows each articulated part.
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	hull_point = VERTEX * scale * arc_scale;
}

vec2 filament(vec3 p, float t) {
	float run = dot(p, vec3(5.0, 3.7, 1.3));
	float across = dot(p, vec3(1.9, -4.7, 4.1));
	float bend = 0.21 * sin(run * 9.0 - t) + 0.10 * sin(run * 21.0 + t * 1.8);
	across += bend + 0.045 * sin(run * 58.0 - t * 2.2);
	float strand = fract(across + 0.5) - 0.5;
	float width = clamp(fwidth(across), 0.003, 0.035);
	float core = 1.0 - smoothstep(0.012, 0.023 + width, abs(strand));
	float glow = 1.0 - smoothstep(0.017, 0.125, abs(strand));
	float gap = sin(run * 5.6 + floor(across + 0.5) * 2.8 - t * 2.1);
	float fork = strand - max(0.0, sin(run * 7.0 + t)) * 0.17;
	float branch = (1.0 - smoothstep(0.007, 0.016 + width, abs(fork))) * smoothstep(-0.1, 0.55, gap);
	float continuity = smoothstep(0.38 - arc_strength, 0.65, gap);
	return vec2(max(core, branch * 0.55), max(glow, branch * 0.4)) * continuity;
}

void fragment() {
	float t = arc_phase * 7.0;
	vec2 arcs = max(filament(hull_point, t), filament(hull_point.zyx * vec3(-1.05, 1.1, 0.8), -t * 0.8 + 3.1) * 0.78);
	ALBEDO = vec3(0.055, 0.32, 1.0) * (0.32 + arcs.y * 0.88) + vec3(0.63, 0.85, 1.0) * arcs.x;
	ALPHA = arc_strength * (0.10 * arc_strength + arcs.y * 0.44 + arcs.x * 0.44);
}
