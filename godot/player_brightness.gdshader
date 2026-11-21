shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float brightness = 1.0;
uniform float contrast = 1.0;
void fragment() {
	vec4 scene = texture(screen_texture, SCREEN_UV);
	vec3 adjusted = pow(max(scene.rgb, vec3(0.0)), vec3(1.0 / brightness));
	COLOR = vec4(max(mix(vec3(0.5), adjusted, contrast), vec3(0.0)), scene.a);
}
