uniform bool sway_enabled = true;
uniform float sway_strength = 0.12;
uniform float sway_speed = 0.3;
uniform float sway_direction = 0.0;
uniform float sway_variation = 0.35;
uniform float sway_wavelength = 1.5;
uniform float sway_ripple = 0.08;
uniform float sway_twist = 0.3;
uniform float root_height = 0.0;
uniform float plant_height = 1.0;
uniform vec3 root_center = vec3(0.0);
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
	// A travelling wave changes phase along the stem, rather than moving the
	// whole leaf as a rigid sheet. Wash adds quicker eddies and stronger torsion.
	float k = 6.283185 / max(sway_wavelength,0.4);
	float ripple_phase = clock * 1.7 + TIME * wash * 3.0 + phase - fraction * k;
	float ripple = sin(ripple_phase);
	float amplitude = sway_ripple * (sway_strength + wash * 0.65);
	vec3 across = normalize(inverse(mat3(model)) * vec3(-sin(sway_direction),0.0,cos(sway_direction)));
	float angle = sway_twist * (sway_strength + wash) * fraction * ripple;
	mat2 torsion = mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)));
	vertex.xz = root_center.xz + torsion * (vertex.xz - root_center.xz);
	normal.xz = torsion * normal.xz;
	vertex += bend * height * fraction * fraction;
	vertex += across * amplitude * height * fraction * ripple;
	normal.y -= dot(normal, bend) * 2.0 * fraction + dot(normal,across) * amplitude * (ripple - fraction * k * cos(ripple_phase));
	normal = normalize(normal);
}
