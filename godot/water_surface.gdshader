shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
#include "res://natural_light.gdshaderinc"
#include "res://water_waves.gdshaderinc"
uniform float daylight = 1.0;
uniform float night_brightness = 0.18;
uniform float wave_height = 0.04;
uniform float wave_size = 4.0;
uniform float wave_speed = 0.8;
uniform float wave_direction = 0.436;
uniform float surface_shine = 0.35;
uniform vec3 sun_direction = vec3(0.0,1.0,0.0);
uniform sampler2D ripple_normals : hint_normal, repeat_enable, filter_linear_mipmap;

varying vec3 world_position;

void vertex() {
	vec3 point = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	VERTEX.y += wave_sample(point.xz,vec4(wave_height,wave_size,wave_speed,wave_direction)).x;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 wave = vec4(wave_height,wave_size,wave_speed,wave_direction);
	vec3 waves = wave_sample(world_position.xz,wave);
	vec2 detail = ripple_detail(ripple_normals,world_position.xz,length(VERTEX),wave);
	vec3 normal = water_normal(waves.yz,detail);
	vec3 view = normalize((INV_VIEW_MATRIX * vec4(VIEW,0.0)).xyz);
	float cosine = abs(dot(normal,view));
	// Looking up through water: the sky is visible inside the critical angle;
	// beyond it the underside reflects the water. Ripples distort that boundary.
	// Snell-window reference: https://godotshaders.com/shader/snells-window/
	float sky_window = smoothstep(0.56,0.65,cosine);
	// Slightly wider artistic sky window, as requested, including its refraction.
	vec3 sky_ray = refract(-view,-normal,1.25);
	float sky_up = clamp(sky_ray.y,0.0,1.0);
	// The reflected environment is sunlit water, not an almost black sky.
	vec3 water_colour = osc_natural_fog_color.rgb;
	vec3 reflection = mix(water_colour*0.82,vec3(0.10,0.48,0.56),sqrt(cosine));
	float ripple_light = clamp(0.5 + detail.x*0.9 + detail.y*0.6,0.0,1.0);
	reflection *= mix(0.94,1.08,ripple_light);
	vec3 sky = mix(vec3(0.20,0.57,0.69),vec3(0.52,0.82,0.88),sqrt(sky_up));
	float sun_above = smoothstep(0.0,0.25,sun_direction.y);
	float sun_alignment = max(dot(sky_ray,sun_direction),0.0);
	float glow = pow(sun_alignment,4.0) * sun_above;
	float glint = pow(sun_alignment,96.0) * sun_above;
	sky += vec3(0.38,0.36,0.28)*glow*surface_shine;
	sky += vec3(1.0,0.96,0.82)*glint*surface_shine*1.8;
	float fresnel = 0.02 + 0.98*pow(1.0-cosine,5.0);
	vec3 daytime = mix(reflection,sky,sky_window*(1.0-fresnel));
	vec3 nighttime = vec3(0.008,0.022,0.048) * (night_brightness / 0.18);
	ALBEDO = mix(nighttime,daytime,daylight);
	// Beer-Lambert water extinction, using the same visibility and fog colour
	// as the rest of the scene (Triton underwater rendering guidance). Reach
	// the exact background colour before camera clipping, without a hard rim.
	// https://www.sundog-soft.com/docs/triton/underwater.html
	float distance_to_camera = length(world_position-CAMERA_POSITION_WORLD);
	float extinction = 1.0-exp(-3.912*distance_to_camera/max(osc_natural_fog.x,0.1));
	float far_fade = smoothstep(osc_natural_fog.x*0.65,osc_natural_fog.x*0.95,distance_to_camera);
	float fog = max(natural_fog_amount(distance_to_camera),max(extinction,far_fade));
	vec3 ray = (world_position - CAMERA_POSITION_WORLD) / max(distance_to_camera,0.001);
	if (osc_natural_enabled) {
		float exposure = natural_background_visibility(CAMERA_POSITION_WORLD,ray);
		// Deep water absorbs the distant sky even with optional distance fog off.
		fog = max(fog,(1.0 - exposure) * smoothstep(10.0,22.0,distance_to_camera));
		ALBEDO = mix(natural_colour(ALBEDO),natural_water_colour(exposure),fog);
	} else {
		ALBEDO = natural_colour(mix(ALBEDO,water_colour,fog));
	}
}
