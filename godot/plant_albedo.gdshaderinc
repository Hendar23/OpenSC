uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform sampler2D terrain_albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D clamped_albedo_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D clamped_terrain_albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool clamp_plant_texture = false;
uniform bool terrain_mipmaps = false;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool has_texture = false;

vec4 plant_albedo(vec2 uv) {
	if (!has_texture) return albedo_color;
	if (clamp_plant_texture) {
		return albedo_color * (terrain_mipmaps ? texture(clamped_terrain_albedo_texture, uv) : texture(clamped_albedo_texture, uv));
	}
	return albedo_color * (terrain_mipmaps ? texture(terrain_albedo_texture, uv) : texture(albedo_texture, uv));
}
