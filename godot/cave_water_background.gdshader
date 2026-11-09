shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, depth_draw_never, cull_disabled;
#include "res://natural_light.gdshaderinc"

void vertex() {
	POSITION = vec4(VERTEX.xy,mix(CLIP_SPACE_FAR,1.0,0.000001),1.0);
}

void fragment() {
	vec4 view_ray = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0,1.0,1.0);
	vec3 direction = normalize(mat3(INV_VIEW_MATRIX) * view_ray.xyz);
	vec2 cave = cave_ray_shelter(CAMERA_POSITION_WORLD,direction,osc_natural_fog.x);
	if (cave.x <= 0.0) discard;
	ALBEDO = natural_water_colour(cave_background_visibility(CAMERA_POSITION_WORLD,cave));
}
