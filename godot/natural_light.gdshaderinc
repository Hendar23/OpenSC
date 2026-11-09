global uniform bool osc_natural_enabled;
global uniform sampler2D osc_overhead : filter_linear, repeat_disable;
global uniform vec4 osc_overhead_bounds;
global uniform vec2 osc_overhead_pixel;
global uniform float osc_natural_surface;
global uniform float osc_cave_ambient;
global uniform vec4 osc_ambient_source;
global uniform float osc_sun_depth;
global uniform float osc_sun_falloff;
global uniform vec4 osc_natural_ambient;
global uniform vec4 osc_natural_fog_color;
global uniform vec3 osc_natural_fog;
global uniform sampler3D osc_sky_volume : filter_linear, repeat_disable;
global uniform vec3 osc_volume_min;
global uniform vec3 osc_volume_size;
global uniform sampler2D osc_cave_sections : filter_linear, repeat_disable;
global uniform sampler2D osc_other_cave_sections : filter_nearest, repeat_disable;
global uniform vec3 osc_cave_min;
global uniform vec3 osc_cave_size;
global uniform bool osc_cave_active;
global uniform vec3 osc_cave_mouth;
global uniform vec3 osc_cave_inward;
global uniform vec3 osc_cave_span;
global uniform float osc_cave_view_radius;

// Global vectors/constants are authored in display colour space. Forward+
// shades in linear space; Compatibility writes display values directly.
vec3 natural_colour(vec3 colour) {
	if (OUTPUT_IS_SRGB) return colour;
	return mix(colour / 12.92,pow((colour + vec3(0.055)) / 1.055,vec3(2.4)),greaterThan(colour,vec3(0.04045)));
}
float cave_wall_coverage(vec3 point) {
	if (!osc_cave_active) return 0.0;
	vec3 local = point - osc_cave_min;
	if (any(lessThan(local,vec3(0.0))) || any(greaterThan(local,osc_cave_size))) return 0.0;
	float x = clamp((point.x - osc_cave_span.x) / osc_cave_span.y,0.0,osc_cave_span.z - 1.0);
	vec4 section = texture(osc_cave_sections,vec2((x + 0.5) / osc_cave_span.z,0.5));
	float wall = max(max(section.x - point.y,point.y - section.y),max(section.z - point.z,point.z - section.w));
	return 1.0 - smoothstep(0.85,1.5,wall);
}

bool near_other_caves(vec3 p, float pad) {
	return (p.y >= 125.0-pad && p.y <= 158.0+pad &&
		p.x >= 118.0-pad && p.x <= 174.0+pad && p.z >= 114.0-pad && p.z <= 175.0+pad) ||
		(p.y >= 155.0-pad && p.y <= 162.0+pad &&
		((p.x >= 174.0-pad && p.x <= 187.0+pad && p.z >= 207.0-pad && p.z <= 213.0+pad) ||
		(p.x >= 252.0-pad && p.x <= 258.0+pad && p.z >= 288.0-pad && p.z <= 304.0+pad)));
}

vec3 passage_local(vec3 point, vec4 mouth, vec4 rim) {
	vec3 offset = point - mouth.xyz;
	return vec3(dot(offset.xz,rim.xy),offset.y,dot(offset.xz,vec2(-rim.y,rim.x)));
}

float passage_walls(vec3 p, float length_inward, int row) {
	if (p.x < -0.35 || p.x > length_inward + 0.65 || abs(p.z) > 39.0 || abs(p.y) > 30.0) return 0.0;
	int last = textureSize(osc_other_cave_sections,0).x - 3;
	float index = clamp(p.x / length_inward,0.0,1.0) * float(last);
	int lo = int(index);
	vec4 section = mix(texelFetch(osc_other_cave_sections,ivec2(lo+2,row),0),
		texelFetch(osc_other_cave_sections,ivec2(min(lo+1,last)+2,row),0),fract(index));
	float wall = max(max(section.x-p.y,p.y-section.y),max(section.z-p.z,p.z-section.w));
	return (1.0-smoothstep(0.35,0.85,wall)) * (1.0-smoothstep(length_inward-0.35,length_inward+0.65,p.x));
}

float tryton_west_rim(vec3 point, int row) {
	if (row != 0) return 1.0;
	// Open water above the descending west branch.
	return smoothstep(139.0,142.0,point.x);
}

float tryton_cover(vec3 point, int row) {
	if (row != 0 || point.x >= 158.0) return 1.0;
	// The far chambers have branches. The fitted span includes the rock
	// between them; reject open water above or beside that rock.
	vec2 uv = (point.xz-osc_overhead_bounds.xy)/osc_overhead_bounds.zw;
	ivec2 size = textureSize(osc_overhead,0);
	float overhead = texelFetch(osc_overhead,clamp(ivec2(uv*vec2(size)),ivec2(0),size-1),0).r;
	return mix(smoothstep(0.35,0.95,overhead-point.y),1.0,smoothstep(154.0,158.0,point.x));
}

float cave_shelter_for(vec3 point, bool tryton_rock) {
	float shelter = cave_wall_coverage(point) * smoothstep(-0.35,4.0,dot(point - osc_cave_mouth,osc_cave_inward));
	if (!osc_cave_active || !near_other_caves(point,1.0)) return shelter;
	for (int row = 0; row < textureSize(osc_other_cave_sections,0).y; row++) {
		vec4 mouth = texelFetch(osc_other_cave_sections,ivec2(0,row),0);
		vec4 rim = texelFetch(osc_other_cave_sections,ivec2(1,row),0);
		vec3 p = passage_local(point,mouth,rim);
		float cover = tryton_rock ? 1.0 : tryton_cover(point,row);
		shelter = max(shelter,passage_walls(p,mouth.w,row)*smoothstep(-0.35,3.0,p.x)*cover*tryton_west_rim(point,row));
	}
	return shelter;
}
float cave_shelter(vec3 point) { return cave_shelter_for(point,false); }

float distance_fog_amount(float distance_to_camera, vec3 settings) {
	float progress = pow(clamp((distance_to_camera - settings.y) / max(settings.x - settings.y,0.1),0.0,1.0),settings.z);
	// Ease both ends so distant contrast has no hard visibility boundary.
	return clamp(progress * progress * progress * (progress * (progress * 6.0 - 15.0) + 10.0),0.0,1.0);
}
float natural_fog_amount(float distance_to_camera) {
	return distance_fog_amount(distance_to_camera,osc_natural_fog);
}

// The aperture is fitted to the boundary loop of the original cave mesh.
// Rock still occludes the view normally. Only rays through the opening can
// change between the outdoor and cave water colours. X is shelter along
// the view; Y is how much open water is visible through the exit.
vec2 touka_ray_shelter(vec3 eye, vec3 direction, float distance_limit) {
	if (!osc_cave_active) return vec2(0.0);
	// The water behind the mouth darkens as soon as the camera is inside.
	// Keep the longer daylight blend on rock so the rim doesn't pop.
	float shelter = cave_wall_coverage(eye) * smoothstep(-0.35,0.45,dot(eye - osc_cave_mouth,osc_cave_inward));
	if (shelter == 0.0 && distance(eye,osc_cave_mouth) >= osc_cave_view_radius) return vec2(0.0);
	float alignment = dot(direction,osc_cave_inward);
	if (abs(alignment) < 0.0001) return vec2(shelter,0.0);
	float crossing = dot(osc_cave_mouth - eye,osc_cave_inward) / alignment;
	if (crossing < 0.0 || crossing >= distance_limit) return vec2(shelter,0.0);
	vec2 aperture = (eye + direction * crossing - osc_cave_mouth).yz;
	aperture.y -= aperture.x * 0.27;
	float opening = 1.0 - smoothstep(0.96,1.16,length(aperture / vec2(2.65,3.35)));
	float travel = distance_limit - crossing;
	float blend = opening * smoothstep(0.0,alignment > 0.0 ? 9.0 : 5.0,travel);
	if (alignment > 0.0) {
		// An opening viewed through outdoor water loses contrast with distance.
		// Otherwise the aperture projects a dark disc onto the distant fog.
		blend *= (1.0 - natural_fog_amount(crossing)) * (1.0 - smoothstep(9.0,osc_cave_view_radius,crossing));
		shelter = max(shelter,blend);
		return vec2(shelter,0.0);
	}
	return vec2(shelter,shelter * blend);
}

vec2 passage_crossing(vec3 eye, vec3 direction, vec2 rim, float limit, float shelter, float range_to_mouth) {
	if (abs(direction.x) < 0.0001) return vec2(0.0);
	float crossing = -eye.x / direction.x;
	if (crossing < 0.0 || crossing >= limit) return vec2(0.0);
	float opening = 1.0-smoothstep(0.94,1.12,length((eye+direction*crossing).yz/rim.yx));
	float blend = opening * smoothstep(0.0,4.0,limit-crossing);
	if (direction.x > 0.0) {
		// Open-ended sheds need no projected dark cap beyond their far opening.
		return vec2(blend*(1.0-natural_fog_amount(crossing))*(1.0-smoothstep(7.0,osc_cave_view_radius,range_to_mouth)),0.0);
	}
	return vec2(0.0,shelter*blend);
}

vec2 cave_ray_shelter(vec3 eye, vec3 direction, float distance_limit) {
	vec2 result = touka_ray_shelter(eye,direction,distance_limit);
	if (!osc_cave_active || !near_other_caves(eye,osc_cave_view_radius)) return result;
	for (int row = 0; row < textureSize(osc_other_cave_sections,0).y; row++) {
		vec4 mouth = texelFetch(osc_other_cave_sections,ivec2(0,row),0);
		float range_to_mouth = distance(eye,mouth.xyz);
		vec4 rim = texelFetch(osc_other_cave_sections,ivec2(1,row),0);
		vec3 p = passage_local(eye,mouth,rim);
		float shelter = passage_walls(p,mouth.w,row)*smoothstep(-0.35,0.45,p.x)*tryton_cover(eye,row)*tryton_west_rim(eye,row);
		if (range_to_mouth >= osc_cave_view_radius && shelter <= 0.0) continue;
		vec3 ray = passage_local(eye+direction,mouth,rim)-p;
		vec2 crossed = passage_crossing(p,ray,rim.zw,distance_limit,shelter,range_to_mouth);
		result = max(result,max(vec2(shelter,0.0),crossed));
	}
	return result;
}

float natural_depth_light(vec3 point) {
	float depth = max(0.0,osc_natural_surface - point.y);
	return 1.0 - smoothstep(osc_sun_depth,osc_sun_depth + max(osc_sun_falloff,0.01),depth);
}

float natural_exposure_for(vec3 point, vec2 thresholds, bool tryton_rock) {
	if (!osc_natural_enabled) return 1.0;
	float light = natural_depth_light(point);
	vec3 uv = (point - osc_volume_min) / osc_volume_size;
	if (any(lessThan(uv,vec3(0.0))) || any(greaterThan(uv,vec3(1.0)))) return light;
	float shelter = cave_shelter_for(point,tryton_rock);
	if (shelter >= 1.0) return 0.0;
	float outdoor = smoothstep(thresholds.x,thresholds.y,texture(osc_sky_volume,uv).r);
	return light * outdoor * (1.0 - shelter);
}
float natural_exposure(vec3 point, vec2 thresholds) { return natural_exposure_for(point,thresholds,false); }

float natural_visibility(vec3 point) {
	return natural_exposure(point,vec2(0.05,0.4));
}
float cave_background_visibility(vec3 camera, vec2 cave) {
	float viewer = natural_exposure(camera,vec2(0.35,0.95));
	return mix(viewer * (1.0 - cave.x),natural_depth_light(camera),cave.y);
}
float natural_background_visibility(vec3 camera, vec3 direction) {
	return cave_background_visibility(camera,cave_ray_shelter(camera,direction,osc_natural_fog.x));
}

float natural_fog_visibility(vec3 point, vec3 camera) {
	if (!osc_natural_enabled) return 1.0;
	vec3 offset = point - camera;
	float distance_to_camera = max(length(offset),0.001);
	vec2 cave = cave_ray_shelter(camera,offset / distance_to_camera,distance_to_camera);
	float endpoint = cave_shelter(point);
	float viewer = natural_exposure(camera,vec2(0.35,0.95));
	if (cave.x > 0.0 || endpoint > 0.0) {
		// Terrain inside the cave must also fade into the intervening exterior
		// water; the end point by itself cannot darken that water.
		float entry = 1.0 - natural_fog_amount(distance_to_camera);
		return mix(viewer * (1.0 - max(cave.x,endpoint * entry)),natural_depth_light(camera),cave.y);
	}
	if (viewer <= 0.0) return 0.0;
	float water = 0.0;
	for (int i = 0; i < 4; i++) {
		water += natural_exposure(mix(camera,point,(float(i) + 0.5) / 4.0),vec2(0.35,0.95));
	}
	water *= 0.25;
	return min(viewer,water * water);
}

vec3 natural_water_colour(float exposure) {
	float cave = osc_ambient_source.w > 0.0 ? 0.0 : min(osc_cave_ambient,osc_natural_ambient.a);
	return natural_colour(osc_natural_fog_color.rgb * exposure + vec3(0.75,0.8,0.88) * cave * (1.0 - exposure));
}

vec3 natural_fog_colour(vec3 point, vec3 camera) {
	float exposure = natural_fog_visibility(point,camera);
	// Fully opaque fog must converge to the viewer's water/background colour.
	// Otherwise coarse shelter samples reveal distant triangles as dark shards,
	// even though their surface lighting has already faded out completely.
	vec3 offset = point - camera;
	float distance_fade = natural_fog_amount(length(offset));
	if (distance_fade > 0.65) {
		float background = natural_background_visibility(camera,normalize(offset));
		exposure = mix(exposure,background,smoothstep(0.65,1.0,distance_fade));
	}
	return natural_water_colour(exposure);
}

vec3 natural_ambient(float exposure, vec3 point) {
	// Shelter must not become brighter than the surrounding night water.
	float cave = min(osc_cave_ambient,osc_natural_ambient.a);
	if (osc_ambient_source.w > 0.0 && exposure < 1.0) {
		vec3 offset = point - osc_ambient_source.xyz;
		cave *= 1.0 - smoothstep(4.0,100.0,dot(offset,offset));
	}
	return osc_natural_ambient.rgb * osc_natural_ambient.a * exposure + vec3(0.75,0.8,0.88) * cave * (1.0 - exposure);
}
