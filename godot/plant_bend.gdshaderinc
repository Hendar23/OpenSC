uniform bool sway_enabled = true;
uniform float sway_strength = 0.12;
uniform float sway_speed = 0.3;
uniform float sway_direction = 0.0;
uniform float sway_variation = 0.35;
uniform float root_height = 0.0;
uniform float plant_height = 1.0;
uniform vec3 propeller_bend = vec3(0.0);

void bend_plant(inout vec3 vertex, inout vec3 normal, mat4 model) {
	if (!sway_enabled) return;
	float height = max(plant_height, 0.001);
	float fraction = clamp((vertex.y - root_height) / height, 0.0, 1.0);
	float phase = dot(model[3].xz, vec2(0.17, 0.11));
	float clock = TIME * sway_speed * 6.283185;
	float wave = sin(clock + phase) + sway_variation * 0.35 * sin(clock * 1.73 + phase * 2.31);
	vec3 local_direction = normalize(inverse(mat3(model)) * vec3(cos(sway_direction), 0.0, sin(sway_direction)));
	vec3 bend = local_direction * sway_strength * wave;
	float wash = length(propeller_bend);
	if (wash > 0.0001) bend += normalize(inverse(mat3(model)) * propeller_bend) * wash;
	bend.y = max(bend.y,-0.35);
	vertex += bend * height * fraction * fraction;
	normal.y -= dot(normal, bend) * 2.0 * fraction;
	normal = normalize(normal);
}
