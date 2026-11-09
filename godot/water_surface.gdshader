shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
#include "res://natural_light.gdshaderinc"
#include "res://replay_clock.gdshaderinc"
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

vec3 wave_sample(vec2 point) {
	vec2 first = vec2(cos(wave_direction),sin(wave_direction));
	vec2 second = vec2(cos(wave_direction + 1.2),sin(wave_direction + 1.2));
	float frequency = 6.283185 / max(wave_size,0.2);
	float a = dot(point,first) * frequency + visual_time() * wave_speed;
	float b = dot(point,second) * frequency * 1.37 - visual_time() * wave_speed * 0.83;
	float height = wave_height * (sin(a) * 0.65 + sin(b) * 0.35);
	vec2 slope = wave_height * frequency * (cos(a) * first * 0.65 + cos(b) * second * 0.35 * 1.37);
	return vec3(height,slope.x,slope.y);
}

void vertex() {
	vec3 point = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	VERTEX.y += wave_sample(point.xz).x;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 waves = wave_sample(world_position.xz);
	float time = visual_time() * wave_speed;
	vec2 flow = vec2(cos(wave_direction),sin(wave_direction));
	vec2 cross_flow = vec2(-flow.y,flow.x);
	vec2 point = vec2(dot(world_position.xz,flow),dot(world_position.xz,cross_flow));
	vec2 uv = point / max(wave_size * 2.0,0.4);
	// Three differently scaled/drifting samples break up straight wave bands.
	// Mipmapped normals avoid the high-frequency sparkle crawling at distance.
	vec2 broad = texture(ripple_normals,uv + vec2(time*0.012,-time*0.008)).xy * 2.0 - 1.0;
	vec2 crossed = texture(ripple_normals,mat2(vec2(0.8,0.6),vec2(-0.6,0.8))*uv*1.83 + vec2(-time*0.009,time*0.016)).xy * 2.0 - 1.0;
	vec2 fine = texture(ripple_normals,uv*4.17 + broad*0.09 + vec2(time*0.023,time*0.012)).xy * 2.0 - 1.0;
	float detail_fade = 1.0 - smoothstep(20.0,100.0,length(VERTEX));
	vec2 detail = broad*0.65 + crossed*0.45 + fine*0.22*detail_fade;
	detail = (flow*detail.x + cross_flow*detail.y) * clamp(wave_height/0.04,0.0,2.0);
	vec2 slope = waves.yz*0.25 + detail*0.65;
	vec3 normal = normalize(vec3(-slope.x,1.0,-slope.y));
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
