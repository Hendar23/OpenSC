shader_type spatial;
render_mode ambient_light_disabled, fog_disabled, cull_disabled, depth_draw_never;
#include "res://natural_light.gdshaderinc"

uniform float cloud_radius = 12.0;
uniform float visibility = 0.45;
uniform float surface_height = 100000.0;
varying float camera_distance;
varying float world_height;
varying float speck_brightness;
varying vec3 natural_position;
varying float natural_factor;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	natural_position = center;
	camera_distance = length(center - CAMERA_POSITION_WORLD);
	world_height = center.y;
	speck_brightness = INSTANCE_CUSTOM.x;
	// Preserve each instance's size while facing the camera.
	float size = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size,
		INV_VIEW_MATRIX[1] * size, INV_VIEW_MATRIX[2] * size, MODEL_MATRIX[3]);
}

void fragment() {
	if (world_height >= surface_height) discard;
	float shape = 1.0 - smoothstep(0.08, 0.5, length(UV - vec2(0.5)));
	float near_fade = smoothstep(0.15, 0.65, camera_distance);
	float far_fade = 1.0 - smoothstep(cloud_radius * 0.75, cloud_radius, camera_distance);
	ALBEDO = vec3(0.65, 0.82, 0.8);
	natural_factor = natural_visibility(natural_position);
	EMISSION = ALBEDO * natural_ambient(natural_factor);
	ALPHA = shape * shape * near_fade * far_fade * visibility * speck_brightness;
}
void light() {
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * (LIGHT_IS_DIRECTIONAL ? natural_factor : 1.0) / PI;
}
