shader_type spatial;
render_mode cull_disabled;
#include "res://plant_albedo.gdshaderinc"
uniform float roughness_value = 0.7;
uniform float metallic_value = 0.0;
#include "res://plant_bend.gdshaderinc"

void vertex() {
	bend_plant(VERTEX,NORMAL,MODEL_MATRIX);
}
void fragment() {
	vec4 color = plant_albedo(UV);
	if (color.a < 0.5) discard;
	ALBEDO = color.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
}
