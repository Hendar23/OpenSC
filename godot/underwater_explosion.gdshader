shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled, blend_premul_alpha;

uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler3D blast_noise : repeat_enable, filter_linear;
uniform float blast_age = 0.0;
uniform float blast_unit = 1.0;
uniform bool spill_over = false;
global uniform vec3 osc_natural_fog;

varying flat vec3 blast_center;

const vec3 CENTER = vec3(0.0);
const float RUPTURE = 1.17;
const vec3 RUPTURE_CENTER = CENTER + vec3(-0.14, 0.095, -0.025);

float pulse(float time, float peak, float width) {
	float offset = (time - peak) / width;
	return exp(-offset * offset);
}

float hash3(vec3 p) {
	p = fract(p * 0.3199 + vec3(0.17, 0.39, 0.23)) * 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	// The texture contains hash3 at lattice points [-64, 63] on each axis.
	// Hardware filtering performs the same trilinear blend after easing.
	return textureLod(blast_noise, (cell + f + vec3(64.5)) / 128.0, 0.0).r;
}

vec2 sphere_hits(vec3 origin, vec3 ray, float radius) {
	float b = dot(origin, ray);
	float disc = b * b - dot(origin, origin) + radius * radius;
	if (disc < 0.0) {
		return vec2(-1.0);
	}
	float half_chord = sqrt(disc);
	return vec2(-b - half_chord, -b + half_chord);
}

float shell_distance(vec3 local, float collapse, float time) {
	vec3 p = local * vec3(1.0, 1.055, 1.0);
	vec3 direction = normalize(p + vec3(0.0001));
	float coarse = noise3(direction * 3.6 + time * vec3(0.12, -0.27, 0.15));
	float ridges = noise3(direction * 11.0 - vec3(0.0, time * 0.6, 0.0));
	float fold = smoothstep(0.05, 0.90, dot(direction, normalize(vec3(0.75, 0.25, 0.33))));
	return length(p) - (0.97 + (coarse - 0.5) * 0.072 + (ridges - 0.5) * 0.026
		- collapse * fold * 0.21);
}

vec3 shell_normal(vec3 local, float collapse, float time) {
	const float d = 0.013;
	float base = shell_distance(local, collapse, time);
	return normalize(vec3(
		shell_distance(local + vec3(d, 0, 0), collapse, time) - base,
		shell_distance(local + vec3(0, d, 0), collapse, time) - base,
		shell_distance(local + vec3(0, 0, d), collapse, time) - base
	));
}

vec4 blast(vec3 origin, vec3 ray, float ray_limit, vec2 uv, mat3 view_basis, float time) {
	float swell = 1.0 - pow(1.0 - clamp(time / 0.79, 0.0, 1.0), 1.48);
	float close = pow(smoothstep(0.81, 1.20, time), 1.05);
	float radius = mix(0.19, 1.21, swell) * mix(1.0, 0.39, close);
	float breakup = smoothstep(RUPTURE, RUPTURE + 0.10, time);
	float life = smoothstep(0.035, 0.13, time) * (1.0 - breakup);
	if (life <= 0.0) {
		return vec4(0.0);
	}

	vec3 center = mix(CENTER, RUPTURE_CENTER, close);
	if (spill_over) { center.y += 0.56 * sin(time * 3.8); }
	vec3 local_origin = (origin - center) / radius;
	vec2 hits = sphere_hits(local_origin, ray, 1.17);
	hits.x = max(0.0, hits.x);
	hits.y = min(hits.y, ray_limit / radius);
	if (hits.y <= hits.x) {
		return vec4(0.0);
	}

	float step_size = (hits.y - hits.x) / 45.0;
	vec3 light = vec3(0.0);
	float transmission = 1.0;
	float first_fire = smoothstep(0.045, 0.13, time) * (1.0 - smoothstep(0.23, 0.46, time));
	float reignition = smoothstep(0.93, 1.095, time) * (1.0 - smoothstep(1.16, 1.24, time));
	float heat = max(first_fire, reignition);
	float sooty = smoothstep(0.13, 0.60, time);
	float shell_t = -1.0;
	float refraction = 0.0;
	vec3 refracted = vec3(0.0);
	for (int i = 0; i < 45; i++) {
		float distance = hits.x + (float(i) + 0.5) * step_size;
		vec3 p = local_origin + distance * ray;
		float shell_radius = length(p * vec3(1.0, 1.055, 1.0));
		if (shell_radius >= 1.019) {
			continue;
		}
		// Below the minimum shell radius, the density mask is already fully open.
		float sdf = -0.24;
		if (shell_t < 0.0 || shell_radius > 0.681 - close * 0.21) {
			sdf = shell_distance(p, close, time);
		}
		if (sdf >= 0.0) {
			continue;
		}
		if (shell_t < 0.0) {
			shell_t = distance + sdf * 0.5;
		}

		vec3 flow = p * vec3(4.1, 5.3, 4.5) + vec3(time * 1.3, -time * 2.15, 0.0);
		flow += 1.9 * vec3(noise3(p * 3.7 + vec3(2.0, time, 1.4)),
			noise3(p * 4.1 + vec3(5.0, 1.2, -time)), noise3(p * 3.2 - vec3(time, 4.8, 0.7)));
		float billow = 0.62 * noise3(flow) + 0.25 * noise3(flow * 2.18)
			+ 0.13 * noise3(flow * 4.65);
		float inside = smoothstep(0.10, 0.24, -sdf);
		float fire = 0.0;
		vec3 emission = vec3(0.0);
		if (heat > 0.0) {
			float wrinkle = 1.0 - abs(noise3(flow * 1.45 + vec3(0.5, 3.6, 0.7)) * 2.0 - 1.0);
			float turbulent = smoothstep(0.38, 0.72, billow * 0.88 + wrinkle * 0.12);
			float pockets = smoothstep(0.39, 0.73, billow);
			vec3 core_position = p * vec3(1.0, 1.24, 1.0) + vec3(close * 0.23, 0.0, 0.0);
			float core = exp(-dot(core_position, core_position) * 3.2);
			fire = (first_fire * pockets * (0.32 + 0.68 * turbulent) * core
				+ reignition * core * (0.11 + 0.89 * pockets) * (0.48 + 0.52 * wrinkle)) * inside;
			vec3 ember = mix(vec3(1.47, 0.14, 0.019), vec3(2.7, 1.11, 0.38),
				clamp(turbulent * 0.71 + core * 0.43, 0.0, 1.0));
			emission = ember * fire * 9.0;
		}
		float smoke = inside * mix(0.19, 1.0, sooty) * (0.42 + 1.32 * smoothstep(0.26, 0.71, billow));
		vec3 smoke_color = mix(vec3(0.044, 0.078, 0.097), vec3(0.29, 0.40, 0.44),
			smoothstep(0.32, 0.75, billow + p.y * 0.14));
		float density = smoke * (1.24 + 0.52 * close);
		light += transmission * step_size * life * (emission + density * smoke_color);
		transmission *= exp(-step_size * life * (density + fire));
	}

	if (shell_t >= 0.0) {
		vec3 hit = local_origin + shell_t * ray;
		vec3 normal = shell_normal(hit, close, time);
		float facing = clamp(dot(normal, -ray), 0.0, 1.0);
		float fresnel = pow(1.0 - facing, 2.6);
		float film = noise3(hit * 15.0 + vec3(0.0, time * 1.4, 0.0));
		float tear = noise3(hit * 5.8 + vec3(2.2, -3.0, 1.3));
		float membrane = life * smoothstep(breakup, breakup + 0.19, tear);
		vec2 bend = (view_basis * normal).xy;
		vec2 offset = bend * (0.006 + 0.017 * fresnel) * membrane
			* min(1.0, radius / max(0.16, length(origin)));
		// Keep foreground geometry from bleeding into the warped samples.
		float packed_depth = texture(scene_depth, uv + offset).r;
		float here = texture(scene_depth, uv).r;
		refraction = membrane * (0.12 + 0.28 * fresnel);
		refracted = texture(scene_color, uv + offset * (packed_depth <= here + 0.005 ? 1.0 : 0.0)).rgb;
		vec3 flecks = hit * 18.0 + vec3(0.0, time * 0.65, 0.0);
		vec3 cell = floor(flecks);
		vec3 seed = vec3(hash3(cell), hash3(cell + 4.2), hash3(cell + 9.1));
		vec3 fleck_offset = fract(flecks) - mix(vec3(0.28), vec3(0.72), seed);
		float spot = length(fleck_offset) / mix(0.14, 0.40, seed.x);
		float fleck = 1.0 - smoothstep(0.54, 1.02, spot);
		float lip = smoothstep(0.35, 0.64, spot) * (1.0 - smoothstep(0.67, 1.0, spot));
		light *= 1.0 - fleck * 0.49 * membrane * swell;
		float upper_glint = smoothstep(0.20, 0.97, dot(normal, normalize(vec3(-0.38, 0.85, 0.31))));
		light += membrane * (fresnel * (vec3(0.19, 0.36, 0.43) * (0.41 + 0.47 * film)
			+ upper_glint * vec3(0.09, 0.14, 0.17) + heat * vec3(0.14, 0.044, 0.017))
			+ lip * swell * vec3(0.07, 0.10, 0.12));
	}
	return vec4(light + refracted * refraction * transmission, 1.0 - transmission * (1.0 - refraction));
}

vec4 aftermath(vec3 origin, vec3 ray, float ray_limit, vec4 color, float time) {
	float birth_cloud = smoothstep(RUPTURE, RUPTURE + 0.085, time);
	float smoke_fade = birth_cloud * (1.0 - smoothstep(2.20, 5.70, time));
	if (smoke_fade <= 0.0) {
		return color;
	}
	float drift = time - RUPTURE;
	float roll = 1.0 - exp(-drift * 2.8);
	vec3 cloud_origin = origin - RUPTURE_CENTER - vec3(-0.075 * drift, 0.20 * drift, 0.065 * drift);
	float cloud_size = 0.43 + (1.0 - exp(-drift * 4.2)) * 0.48 + drift * 0.12;
	vec2 cloud = sphere_hits(cloud_origin, ray, cloud_size * 1.62);
	float transmission = 1.0;
	vec3 mist = vec3(0.0);
	cloud.x = max(cloud.x, 0.0);
	cloud.y = min(cloud.y, ray_limit);
	if (cloud.y > cloud.x) {
		float stride = (cloud.y - cloud.x) / 33.0;
		for (int i = 0; i < 33; i++) {
			vec3 p = (cloud_origin + (cloud.x + (float(i) + 0.5) * stride) * ray) / cloud_size;
			vec3 warped = p + roll * (vec3(
				noise3(p * 2.0 + vec3(3.4, drift * 0.21, 1.2)),
				noise3(p * 2.3 - vec3(1.1, drift * 0.35, 3.9)),
				noise3(p * 2.5 + vec3(-1.8, 0.9, drift * 0.19))) - 0.5) * 0.71;
			vec3 stretched = warped * vec3(0.85, 1.22, 0.91) + vec3(p.y * 0.23, -p.x * 0.19, 0.0) * roll;
			float lumps = noise3(warped * 2.8 + vec3(2.8, -drift * 0.32, 0.0));
			float billows = 0.56 * lumps + 0.30 * noise3(warped * 6.5)
				+ 0.14 * noise3(warped * 17.0);
			float contour = length(stretched) + (0.47 - billows) * mix(0.55, 1.12, roll);
			float edge = 1.0 - smoothstep(0.32, 1.13, contour);
			float density = edge * smoothstep(0.25, 0.78, billows) * (0.36 + 0.64 * lumps);
			float opacity = 1.0 - exp(-stride * 7.5 * density * smoke_fade);
			vec3 tint = mix(vec3(0.029, 0.059, 0.081), vec3(0.33, 0.45, 0.52),
				smoothstep(0.32, 0.79, billows + p.y * 0.15));
			mist += transmission * opacity * tint;
			transmission *= 1.0 - opacity;
		}
	}

	return vec4(color.rgb * transmission + mist, 1.0 - transmission * (1.0 - color.a));
}


vec4 crater_fire(vec3 origin, vec3 ray, float ray_limit, float time) {
	vec4 fire = vec4(0.0);
	for (int i = 0; i < 2; i++) {
		float phase = time - float(i) * 0.13;
		float strength = smoothstep(0.0, 0.13, phase) * (1.0 - smoothstep(0.31, 0.60, phase));
		vec3 center = vec3(0.0, 4.0 * max(phase, 0.0), 0.0);
		float distance_along = dot(center - origin, ray);
		if (strength <= 0.0 || distance_along < 0.0 || distance_along >= ray_limit) {
			continue;
		}
		vec3 offset = (origin + distance_along * ray - center) * vec3(2.8, 1.2, 2.8);
		float density = exp(-3.0 * dot(offset, offset)) * strength;
		float flicker = 0.5 + 0.5 * noise3(offset * 8.0 + vec3(0.0, -phase * 14.0, 0.0));
		fire += vec4(vec3(1.8, 0.54, 0.12) * flicker, 0.28) * density;
	}
	return fire;
}

void vertex() {
	// The quad covers the projected volume, including when the camera is inside it.
	blast_center = MODEL_MATRIX[3].xyz;
	vec3 center_view = (VIEW_MATRIX * vec4(blast_center, 1.0)).xyz;
	float envelope = blast_age < 0.16 ? 2.6 : 1.65;
	if (spill_over && blast_age < 0.73) { envelope = 3.8; }
	if (blast_age >= RUPTURE) {
		float drift = blast_age - RUPTURE;
		float cloud_size = 0.43 + (1.0 - exp(-drift * 4.2)) * 0.48 + drift * 0.12;
		vec3 cloud_offset = RUPTURE_CENTER + vec3(-0.075 * drift, 0.20 * drift, 0.065 * drift);
		envelope = max(envelope, length(cloud_offset) + cloud_size * 1.62);
	}
	float radius = envelope * blast_unit;
	if (center_view.z - radius >= 0.0) {
		POSITION = vec4(2.0, 2.0, 0.5, 1.0);
	} else if (-center_view.z <= radius + 0.1) {
		POSITION = vec4(VERTEX.xy, 0.5, 1.0);
	} else {
		// Project the enclosing box. The projection can flip the vertical axis,
		// so a signed projection scale is not a safe screen-space radius.
		vec2 low = vec2(1e20);
		vec2 high = vec2(-1e20);
		for (int i = 0; i < 8; i++) {
			vec3 corner = vec3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1));
			vec4 clip = PROJECTION_MATRIX * vec4(center_view + (2.0 * corner - 1.0) * radius, 1.0);
			vec2 point = clip.xy / clip.w;
			low = min(low, point);
			high = max(high, point);
		}
		POSITION = vec4(mix(low, high, VERTEX.xy * 0.5 + 0.5), 0.5, 1.0);
	}
}

void fragment() {
	vec2 xy = SCREEN_UV * 2.0 - 1.0;
	float depth = texture(scene_depth, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	depth = depth * 2.0 - 1.0;
#endif
	vec4 surface_view = INV_PROJECTION_MATRIX * vec4(xy, depth, 1.0);
	vec3 ray = mat3(INV_VIEW_MATRIX) * normalize(surface_view.xyz);
	vec3 origin = (INV_VIEW_MATRIX[3].xyz - blast_center) / blast_unit;
	// Stop at opaque hulls or terrain instead of marching through them.
	float ray_limit = length(surface_view.xyz) / max(abs(surface_view.w), 0.000001) / blast_unit;
	float time = blast_age;
	vec4 color = blast(origin, ray, ray_limit, SCREEN_UV, mat3(VIEW_MATRIX), time);
	if (spill_over) {
		vec4 plume = crater_fire(origin, ray, ray_limit, time);
		color = color * (1.0 - plume.a) + plume;
	}
	color = aftermath(origin, ray, ray_limit, color, time);
	float flash = smoothstep(0.0, 0.026, time) * (1.0 - smoothstep(0.055, 0.16, time));
	float distance_along = dot(-origin, ray);
	if (flash > 0.0 && distance_along > 0.0 && distance_along < ray_limit + 0.18) {
		vec3 offset = origin + ray * distance_along;
		float glare_distance2 = dot(offset, offset);
		float glare = flash * (10.7 * exp(-glare_distance2 * 7.8) + 1.90 * exp(-glare_distance2 * 1.58));
		color.rgb += vec3(1.0, 0.82, 0.63) * glare;
		color.a = mix(color.a, 1.0, 1.0 - exp(-glare * 0.33));
	}
	float camera_depth = length(origin) * blast_unit;
	float fog = pow(smoothstep(osc_natural_fog.y, max(osc_natural_fog.y + 0.001, osc_natural_fog.x), camera_depth), max(0.01, osc_natural_fog.z));
	color *= 1.0 - fog;
	if (color.a < 0.001 && max(color.r, max(color.g, color.b)) < 0.003) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = clamp(color.a, 0.0, 1.0);
}
