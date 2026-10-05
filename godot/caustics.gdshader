shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, ambient_light_disabled, specular_disabled, fog_disabled;
#include "res://plant_bend.gdshaderinc"
#include "res://natural_light.gdshaderinc"
global uniform sampler2D osc_caustics_texture : filter_linear, repeat_enable;
global uniform float osc_caustics_strength;
global uniform float osc_caustics_size;
global uniform float osc_caustics_speed;
global uniform float osc_caustics_depth;
global uniform float osc_water_height;
global uniform vec3 osc_sun_direction;
global uniform float osc_wave_speed;
global uniform float osc_wave_direction;
global uniform float osc_caustics_visibility;
global uniform float osc_caustics_fog_start;
global uniform float osc_caustics_fog_curve;
uniform bool is_plant = false;
uniform bool alpha_cutout = false;
uniform sampler2D alpha_texture : filter_nearest, repeat_enable;
uniform float alpha_threshold = 0.5;
varying vec3 world_position;

void vertex() {
	if (is_plant) bend_plant(VERTEX,NORMAL,MODEL_MATRIX);
	world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	if (osc_caustics_strength <= 0.0 || osc_sun_direction.y <= 0.01 || world_position.y > osc_water_height) discard;
	if (alpha_cutout && texture(alpha_texture,UV).a < alpha_threshold) discard;
	float depth = max(0.0,osc_water_height - world_position.y);
	vec2 projected = world_position.xz + osc_sun_direction.xz * depth / max(osc_sun_direction.y,0.2);
	vec2 flow = vec2(cos(osc_wave_direction),sin(osc_wave_direction));
	vec2 uv = projected / max(osc_caustics_size * 12.0,0.1);
	float clock = TIME * osc_wave_speed * osc_caustics_speed;
	uv += vec2(sin(projected.y * 0.9 + clock),cos(projected.x * 0.8 - clock)) * 0.015;
	float first = texture(osc_caustics_texture,uv + flow * TIME * osc_caustics_speed * 0.014).r;
	float second = texture(osc_caustics_texture,uv * 1.13 - flow.yx * TIME * osc_caustics_speed * 0.01).r;
	float pattern = max(first,second * 0.65);
	float fade = exp(-depth / max(osc_caustics_depth,0.1)) * smoothstep(0.0,0.35,osc_sun_direction.y);
	fade *= natural_visibility(world_position);
	// Fade the extra light into fog without adding the blue fog colour twice.
	float fog = clamp((length(VERTEX) - osc_caustics_fog_start) / max(osc_caustics_visibility - osc_caustics_fog_start,0.1),0.0,1.0);
	fade *= 1.0 - pow(fog,osc_caustics_fog_curve);
	ALBEDO = vec3(0.88,1.0,0.93) * pattern * fade * osc_caustics_strength;
	SPECULAR = 0.0;
}
void light() {
	// Only sunlight creates caustics. ATTENUATION includes its shadow map.
	if (LIGHT_IS_DIRECTIONAL) DIFFUSE_LIGHT += abs(dot(NORMAL,LIGHT)) * ATTENUATION * LIGHT_COLOR / PI;
}
