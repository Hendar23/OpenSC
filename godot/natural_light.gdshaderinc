global uniform bool osc_natural_enabled;
global uniform sampler2D osc_overhead : filter_linear, repeat_disable;
global uniform vec4 osc_overhead_bounds;
global uniform vec2 osc_overhead_pixel;
global uniform float osc_natural_surface;
global uniform float osc_cave_ambient;
global uniform float osc_sun_depth;
global uniform float osc_sun_falloff;
global uniform vec4 osc_natural_ambient;
global uniform vec4 osc_natural_fog_color;
global uniform vec3 osc_natural_fog;
global uniform sampler3D osc_sky_volume : filter_linear, repeat_disable;
global uniform vec3 osc_volume_min;
global uniform vec3 osc_volume_size;
float natural_exposure(vec3 point, vec2 thresholds) {
	if (!osc_natural_enabled) return 1.0;
	float depth = max(0.0,osc_natural_surface - point.y);
	float light = 1.0 - smoothstep(osc_sun_depth,osc_sun_depth + max(osc_sun_falloff,0.01),depth);
	vec3 uv = (point - osc_volume_min) / osc_volume_size;
	if (any(lessThan(uv,vec3(0.0))) || any(greaterThan(uv,vec3(1.0)))) return light;
	return light * smoothstep(thresholds.x,thresholds.y,texture(osc_sky_volume,uv).r);
}
float natural_visibility(vec3 point) {
	return natural_exposure(point,vec2(0.05,0.4));
}
float distance_fog_amount(float distance_to_camera, vec3 settings) {
	float progress = pow(clamp((distance_to_camera - settings.y) / max(settings.x - settings.y,0.1),0.0,1.0),settings.z);
	// Ease both ends: distant contrast emerges gradually rather than reaching
	// the visibility boundary with a nonzero slope and suddenly appearing.
	return clamp(progress * progress * progress * (progress * (progress * 6.0 - 15.0) + 10.0),0.0,1.0);
}
float natural_fog_amount(float distance_to_camera) {
	return distance_fog_amount(distance_to_camera,osc_natural_fog);
}
float natural_fog_visibility(vec3 point, vec3 camera) {
	if (!osc_natural_enabled) return 1.0;
	// Fog needs illuminated water along the view, not just an outdoor camera.
	// Use stricter shelter thresholds than surface light at a mixed roof edge.
	// Interior views remain dark even when looking towards an exposed exit.
	float viewer = natural_exposure(camera,vec2(0.35,0.95));
	if (viewer <= 0.0) return 0.0;
	float water = 0.0;
	for (int i = 0; i < 4; i++) {
		water += natural_exposure(mix(camera,point,(float(i) + 0.5) / 4.0),vec2(0.35,0.95));
	}
	water *= 0.25;
	return min(viewer,water * water);
}

vec3 natural_fog_colour(vec3 point, vec3 camera) {
	float exposure = natural_fog_visibility(point,camera);
	// Fully opaque fog must converge to the viewer's water/background colour.
	// Otherwise coarse shelter samples reveal distant triangles as dark shards,
	// even though their surface lighting has already faded out completely.
	float distance_fade = natural_fog_amount(length(point - camera));
	exposure = mix(exposure,natural_exposure(camera,vec2(0.35,0.95)),smoothstep(0.65,1.0,distance_fade));
	return osc_natural_fog_color.rgb * exposure + vec3(0.75,0.8,0.88) * osc_cave_ambient * (1.0 - exposure);
}

vec3 natural_ambient(float exposure) {
	return osc_natural_ambient.rgb * osc_natural_ambient.a * exposure + vec3(0.75,0.8,0.88) * osc_cave_ambient * (1.0 - exposure);
}
