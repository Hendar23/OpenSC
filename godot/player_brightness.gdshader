shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float brightness = 1.0;
uniform float contrast = 1.0;
uniform bool night_vision = false;
uniform float night_vision_daylight = 0.0;

float luminance(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float sensor_grain(vec2 cell) {
	vec2 seed = cell + floor(TIME * 24.0) * vec2(13.0, 41.0);
	vec3 hash = fract(seed.xyx * 0.1031);
	hash += dot(hash, hash.yzx + 33.33);
	return fract((hash.x + hash.y) * hash.z) - 0.5;
}

vec3 intensify(vec3 scene, vec2 uv, vec2 pixel_size) {
	float light = max(0.0, luminance(scene));
	vec2 spread = pixel_size / pixel_size.y * 0.009;
	// Average the surroundings so a point highlight cannot create four offset copies.
	float nearby = 0.25 * (
		clamp(luminance(texture(screen_texture, uv + vec2(spread.x, 0.0)).rgb), 0.0, 1.0) +
		clamp(luminance(texture(screen_texture, uv - vec2(spread.x, 0.0)).rgb), 0.0, 1.0) +
		clamp(luminance(texture(screen_texture, uv + vec2(0.0, spread.y)).rgb), 0.0, 1.0) +
		clamp(luminance(texture(screen_texture, uv - vec2(0.0, spread.y)).rgb), 0.0, 1.0)
	);
	float glare = max(smoothstep(0.23, 0.55, light), 0.65 * smoothstep(0.40, 0.80, nearby));
	float gain = pow(1.0 - exp(-5.5 * light), 0.72);
	float grain_scale = max(1.0, 1.0 / (720.0 * pixel_size.y));
	float grain = sensor_grain(floor(uv / (pixel_size * grain_scale)));
	float vignette = 1.0 - 0.26 * smoothstep(0.35, 0.70, length(uv - 0.5));
	vec3 phosphor = vec3(0.19, 1.0, 0.31) * max(0.0, gain + 0.025 + grain * 0.14) * vignette;
	vec3 intensified = mix(phosphor, vec3(0.88, 1.0, 0.89), glare);
	float daylight_washout = night_vision_daylight * (0.05 + 0.39 * smoothstep(0.10, 0.45, light));
	return mix(intensified, vec3(1.0), daylight_washout);
}

void fragment() {
	vec4 scene = texture(screen_texture, SCREEN_UV);
	if (night_vision) {
		scene.rgb = intensify(scene.rgb, SCREEN_UV, SCREEN_PIXEL_SIZE);
	}
	vec3 adjusted = pow(max(scene.rgb, vec3(0.0)), vec3(1.0 / brightness));
	COLOR = vec4(max(mix(vec3(0.5), adjusted, contrast), vec3(0.0)), scene.a);
}
