shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool has_texture = false;
uniform float roughness_value = 0.7;
uniform float metallic_value = 0.0;
#include "res://plant_bend.gdshaderinc"

void vertex() {
	bend_plant(VERTEX,NORMAL,MODEL_MATRIX);
}
void fragment() {
	vec4 color = albedo_color;
	if (has_texture) color *= texture(albedo_texture, UV);
	if (color.a < 0.5) discard;
	ALBEDO = color.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
}
