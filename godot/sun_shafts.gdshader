shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, depth_test_disabled, fog_disabled;
#include "res://replay_clock.gdshaderinc"
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform float beam_length = 30.0;
uniform float beam_width = 3.0;
uniform float strength = 0.0;
uniform float seed = 0.0;
uniform float surface_height;
uniform float depth_start = 25.0;
uniform float depth_end = 45.0;
uniform float view_range = 60.0;
uniform vec3 light_color : source_color = vec3(1.0);
varying vec3 local_position;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 cell = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell),hash(cell+vec2(1,0)),f.x),mix(hash(cell+vec2(0,1)),hash(cell+vec2(1,1)),f.x),f.y);
}
void vertex() {
    VERTEX *= vec3(beam_width,beam_width,beam_length);
    local_position = VERTEX;
}
void fragment() {
	vec3 camera = (inverse(MODEL_MATRIX) * INV_VIEW_MATRIX[3]).xyz;
	vec3 ray = normalize(local_position-camera);
	vec3 safe_ray = mix(vec3(0.00001),ray,greaterThan(abs(ray),vec3(0.00001)));
	vec3 extent = vec3(beam_width,beam_width,beam_length)*0.5;
	vec3 first = (-extent-camera)/safe_ray, last = (extent-camera)/safe_ray;
	vec3 low = min(first,last), high = max(first,last);
	float start = max(0.0,max(low.x,max(low.y,low.z)));
	float finish = min(high.x,min(high.y,high.z));
	float depth = texture(depth_texture,SCREEN_UV).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV,depth) * 2.0 - 1.0;
	#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0,depth);
	#endif
	vec4 hit = INV_PROJECTION_MATRIX*vec4(ndc,1.0);
	vec4 world_hit = INV_VIEW_MATRIX*vec4(hit.xyz/hit.w,1.0);
	finish = min(finish,length((inverse(MODEL_MATRIX)*world_hit).xyz-camera));
	float step_size = max(0.0,finish-start)/16.0;
	float density = 0.0;
	for (int i=0;i<16;i++) {
		vec3 p = camera+ray*(start+(float(i)+0.5)*step_size);
		float edge = 1.0-smoothstep(0.2,0.5,length(p.xy)/beam_width);
		float streak = smoothstep(0.38,0.78,noise(p.xy*2.0+vec2(seed+visual_time()*0.035,seed)));
		vec3 world = (MODEL_MATRIX*vec4(p,1.0)).xyz;
		float attenuation = 1.0-smoothstep(depth_start,depth_end,surface_height-world.y);
		float along = p.z/beam_length+0.5;
		attenuation *= smoothstep(0.0,0.04,along)*(1.0-smoothstep(0.8,1.0,along));
		float distance_fade = 1.0-smoothstep(view_range*0.5,view_range,start+(float(i)+0.5)*step_size);
		density += edge*streak*attenuation*distance_fade*step_size;
	}
	ALBEDO = mix(light_color,vec3(0.4,0.8,0.85),0.35);
	float opacity = min(0.22,density*0.035)*strength;
	// Scattering opacity is linear in either renderer. Gamma-correcting alpha
	// made the already faint rays almost disappear in Forward+.
	ALPHA = opacity;
}
