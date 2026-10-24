#include "res://natural_light.gdshaderinc"
#ifdef EXTERIOR_CANOPY
#include "res://exterior_reflection.gdshaderinc"
#endif
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform sampler2D terrain_albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool terrain_mipmaps = false;
uniform bool cull_backfaces = false;
uniform sampler2D backface_texture : source_color, filter_nearest, repeat_enable;
uniform bool has_backface_texture = false;
uniform sampler2D emission_texture : source_color, filter_nearest, repeat_enable;
uniform sampler2D normal_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D metallic_texture : filter_linear_mipmap, repeat_enable;
uniform bool has_normal_texture = false;
uniform bool has_roughness_texture = false;
uniform bool has_metallic_texture = false;
uniform float normal_scale = 1.0;
uniform vec4 roughness_channel = vec4(1,0,0,0);
uniform vec4 metallic_channel = vec4(1,0,0,0);
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(0.0);
uniform bool has_texture = false;
uniform bool has_emission_texture = false;
uniform bool self_illuminated = false;
uniform float surface_emission_strength = 0.0;
uniform bool use_vertex_color = false;
uniform float roughness_value = 0.7;
uniform float metallic_value = 0.0;
uniform float specular_value = 0.5;
uniform float alpha_threshold = 0.0;
uniform float opacity = 1.0;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform bool billboard = false;
varying vec3 natural_position;
varying float natural_factor;
varying float natural_transmission;
varying float natural_specular;
void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz),MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
	natural_position = (INV_VIEW_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	if (cull_backfaces && !FRONT_FACING) discard;
	vec2 uv = UV * uv_scale.xy + uv_offset.xy;
	vec4 color = albedo_color;
#ifdef EXTERIOR_CANOPY
	if (!osc_exterior_enabled) color = canopy_original_color;
#endif
	if (has_texture) {
		if (terrain_mipmaps) color *= texture(terrain_albedo_texture,uv);
		else color *= texture(albedo_texture,uv);
	}
	if (use_vertex_color) color *= COLOR;
	if (has_backface_texture && !FRONT_FACING) color = texture(backface_texture,uv);
	if (color.a < alpha_threshold) discard;
	vec3 air_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL,0.0)).xyz);
	if (dot(NORMAL,VIEW) < 0.0) air_normal = -air_normal;
	vec3 air_position = natural_position + air_normal * 0.1;
	natural_factor = natural_visibility(air_position);
	float fog = natural_fog_amount(length(VERTEX));
	natural_transmission = 1.0 - fog;
	ALBEDO = color.rgb * (1.0 - fog);
	ROUGHNESS = roughness_value; METALLIC = metallic_value; SPECULAR = specular_value;
	natural_specular = specular_value;
	if (has_normal_texture) { NORMAL_MAP = texture(normal_texture,uv).rgb; NORMAL_MAP_DEPTH = normal_scale; }
	if (has_roughness_texture) ROUGHNESS *= dot(texture(roughness_texture,uv),roughness_channel);
	if (has_metallic_texture) METALLIC *= dot(texture(metallic_texture,uv),metallic_channel);
	#ifdef EXTERIOR_CANOPY
	if (!osc_exterior_enabled) { ROUGHNESS = 0.7; METALLIC = 0.1; SPECULAR = 0.5; natural_specular = 0.5; }
	#endif
	vec3 glow = emission_color.rgb;
	if (has_emission_texture) glow *= texture(emission_texture,uv).rgb;
	if (self_illuminated) glow = color.rgb * surface_emission_strength;
	EMISSION = (glow + color.rgb * natural_ambient(natural_factor)) * natural_transmission + natural_fog_colour(air_position,INV_VIEW_MATRIX[3].xyz) * fog;
#ifdef EXTERIOR_CANOPY
	if (osc_exterior_enabled && osc_exterior_ready) {
		vec3 reflected_ray = normalize(mat3(INV_VIEW_MATRIX) * reflect(-normalize(VIEW),normalize(NORMAL)));
		float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),5.0);
		float reflection_mix = mix(0.32,0.85,fresnel);
		ALBEDO *= 1.0 - reflection_mix;
		EMISSION += exterior_reflection(reflected_ray) * vec3(0.55,0.82,1.0) * reflection_mix * natural_transmission * mix(0.05,1.0,natural_factor);
	}
#endif
	#ifdef NATURAL_ALPHA
	ALPHA = color.a * opacity;
	#endif
}
void light() {
	if (!self_illuminated) {
		float source = LIGHT_IS_DIRECTIONAL ? natural_factor : 1.0;
		DIFFUSE_LIGHT += max(dot(NORMAL,LIGHT),0.0) * ATTENUATION * LIGHT_COLOR * source / PI;
		vec3 half_vector = normalize(LIGHT + VIEW);
		float shine = pow(max(dot(NORMAL,half_vector),0.0),mix(128.0,8.0,ROUGHNESS));
		// Godot's dielectric specular control maps to F0 = 0.16 * specular².
		// Treating it directly as reflectance made the default 0.5 shine 12.5x
		// brighter, even on rough fish and hull materials.
		vec3 reflectance = mix(vec3(0.16 * natural_specular * natural_specular),ALBEDO / max(natural_transmission,0.001),METALLIC);
		SPECULAR_LIGHT += shine * max(dot(NORMAL,LIGHT),0.0) * ATTENUATION * LIGHT_COLOR * source * reflectance * pow(1.0 - ROUGHNESS,2.0) * natural_transmission;
	}
}
