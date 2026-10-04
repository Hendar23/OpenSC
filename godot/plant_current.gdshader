shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool has_texture = false;
uniform float roughness_value = 0.7;
uniform float metallic_value = 0.0;
uniform bool sway_enabled = true;
uniform float sway_strength = 0.12;
uniform float sway_speed = 0.3;
uniform float sway_direction = 0.0;
uniform float sway_variation = 0.35;
uniform float root_height = 0.0;
uniform float plant_height = 1.0;
uniform vec3 propeller_bend = vec3(0.0);

void vertex() {
	if (sway_enabled) {
		float height = max(plant_height, 0.001);
		float fraction = clamp((VERTEX.y - root_height) / height, 0.0, 1.0);
		vec2 location = MODEL_MATRIX[3].xz;
		float phase = dot(location, vec2(0.17, 0.11));
		float clock = TIME * sway_speed * 6.283185;
		float wave = sin(clock + phase) + sway_variation * 0.35 * sin(clock * 1.73 + phase * 2.31);
		vec3 world_direction = vec3(cos(sway_direction), 0.0, sin(sway_direction));
		vec3 local_direction = inverse(mat3(MODEL_MATRIX)) * world_direction;
		local_direction = normalize(local_direction);
		vec3 bend = local_direction * sway_strength * wave;
		float wash = length(propeller_bend);
		if (wash > 0.0001) bend += normalize(inverse(mat3(MODEL_MATRIX)) * propeller_bend) * wash;
		// Downward pod wash compresses foliage without folding it into the floor.
		bend.y = max(bend.y,-0.35);
		VERTEX += bend * height * fraction * fraction;
		// The root stays fixed; tilt the normal with the bending blade.
		NORMAL.y -= dot(NORMAL, bend) * 2.0 * fraction;
		NORMAL = normalize(NORMAL);
	}
}
void fragment() {
	vec4 color = albedo_color;
	if (has_texture) color *= texture(albedo_texture, UV);
	if (color.a < 0.5) discard;
	ALBEDO = color.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
}
