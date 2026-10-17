shader_type canvas_item;
render_mode unshaded;
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear;
uniform float refraction_strength = 0.6;
uniform float edge_tint = 0.025;

void fragment() {
	vec2 radial = SCREEN_UV * 2.0 - 1.0;
	float radius = length(radial) / sqrt(2.0);
	// A clear sightline in the centre, increasing curvature toward the sides.
	float curvature = smoothstep(0.2,1.0,radius);
	vec2 offset = radial * curvature * curvature * refraction_strength * 0.028;
	vec2 safe_uv = clamp(SCREEN_UV - offset,SCREEN_PIXEL_SIZE * 0.5,vec2(1.0) - SCREEN_PIXEL_SIZE * 0.5);
	vec3 transmitted = textureLod(scene_color,safe_uv,0.0).rgb;
	transmitted *= mix(vec3(1.0),vec3(0.82,0.96,1.0),curvature * edge_tint);
	COLOR = vec4(transmitted,1.0);
}
