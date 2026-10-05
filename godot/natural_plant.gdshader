shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, fog_disabled;
#include "res://natural_light.gdshaderinc"
#include "res://plant_bend.gdshaderinc"
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool has_texture = false;
uniform float roughness_value = 0.7;
uniform float metallic_value = 0.0;
varying vec3 natural_position;
varying float natural_factor;
void vertex() {
	bend_plant(VERTEX,NORMAL,MODEL_MATRIX);
	natural_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	vec4 color = albedo_color;
	if (has_texture) color *= texture(albedo_texture,UV);
	if (color.a < 0.5) discard;
	vec3 air_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL,0.0)).xyz);
	if (dot(NORMAL,VIEW) < 0.0) air_normal = -air_normal;
	vec3 air_position = natural_position + air_normal * 0.1;
	natural_factor = natural_visibility(air_position);
	float fog = natural_fog_amount(length(VERTEX));
	ALBEDO = color.rgb * (1.0 - fog); ROUGHNESS = roughness_value; METALLIC = metallic_value;
	EMISSION = color.rgb * natural_ambient(natural_factor) * (1.0 - fog) + natural_fog_colour(air_position,INV_VIEW_MATRIX[3].xyz) * fog;
}
void light() {
	DIFFUSE_LIGHT += max(dot(NORMAL,LIGHT),0.0) * ATTENUATION * LIGHT_COLOR * (LIGHT_IS_DIRECTIONAL ? natural_factor : 1.0) / PI;
}
