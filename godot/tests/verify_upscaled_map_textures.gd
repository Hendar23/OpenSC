extends SceneTree

const Mods = preload("res://mod_registry.gd")
const Assets = preload("res://clump_loader.gd")
const World = preload("res://world_loader.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	preload("res://asset_cache.gd").enabled = false
	Mods.initialize(false)
	var args := OS.get_cmdline_user_args()
	var folder := preload("res://asset_paths.gd").find_game_folder() if args.is_empty() else args[0]
	check(not folder.is_empty(), "Original game folder is configured or supplied after --")
	if folder.is_empty(): quit(1); return
	var packs := Mods.packs.filter(func(pack: Dictionary) -> bool: return pack.id == "upscaled-map-textures")
	check(packs.size() == 1, "Mod is discovered exactly once")
	if packs.size() != 1: quit(1); return
	var pack: Dictionary = packs[0]
	check(pack.valid and pack.errors.is_empty(), "Mod manifest and files are valid")
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(pack.folder).path_join("sources.json")))
	var factor := int(args[1]) if args.size() > 1 else int(provenance.get("factor", 0))
	check(factor in [4, 8] and int(provenance.get("factor", 0)) == factor, "Declared scale is supported and matches requested test scale")
	var enhanced := 0
	for name in provenance.textures:
		var entry: Dictionary = provenance.textures[name]
		var replacement: Dictionary = pack.assets.get("texture." + str(name), {})
		check(not replacement.is_empty(), "Provenance texture is present in manifest: " + str(name))
		if replacement.is_empty(): continue
		check(FileAccess.get_sha256(replacement.path) == str(entry.output_sha256), "Installed PNG matches provenance checksum: " + str(name))
		if entry.has("generated_sha256"):
			enhanced += 1
			check(entry.get("generator", "") == "built-in image_gen" and not str(entry.get("prompt", "")).is_empty(), "Reconstructed texture records its generator and prompt: " + str(name))
	check(enhanced == int(provenance.get("enhanced_texture_count", 0)), "Reconstructed texture count matches provenance")
	check(Mods.active_ids().is_empty(), "Discovery does not enable mods")
	Mods.apply(["upscaled-map-textures"], ["upscaled-map-textures"], false)
	var data := FileAccess.get_file_as_bytes(folder.path_join("DATA/SCEN1.BSP"))
	var end := -1
	for offset in range(60, data.size() - 16, 4):
		if Assets._has_tag(data, offset, "nalp") and Assets._has_tag(data, offset + 8, "trts"):
			end = offset; break
	check(end > 60, "Original world material table exists")
	if end < 0: quit(1); return
	var refs := Assets._material_references(data, 60, end)
	var expected := {}
	for ref in refs:
		if str(ref.texture).is_empty(): continue
		expected["texture." + str(ref.texture).to_lower()] = true
	check(pack.assets.size() == expected.size(), "Mod covers exactly the world's unique texture IDs")
	for id in pack.assets: check(expected.has(id), "No non-world replacement: " + str(id))
	for ref in refs:
		if str(ref.texture).is_empty(): continue
		var name := str(ref.texture)
		var original := preload("res://legacy_bmp.gd")._load_image(folder.path_join("GAMETEX/" + name.to_upper() + ".BMP"))
		if original == null: original = preload("res://legacy_bmp.gd")._load_image(folder.path_join("GAMETEX/" + name.to_upper() + ".RAS"))
		var material := World._terrain_material(ref, folder, {})
		var texture := material.albedo_texture
		check(texture != null and original != null, "Material texture loads: " + name)
		if texture == null or original == null: continue
		check(texture.get_size() == Vector2(original.get_size() * factor), "Exactly %dx source dimensions: %s" % [factor, name])
		check(texture.get_meta("asset_mod", "") == pack.name, "World material uses this mod: " + name)
		var enhanced_terrain: bool = pack.assets["texture." + name.to_lower()].get("terrain_mipmaps", false)
		var expected_filter := BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC if enhanced_terrain else BaseMaterial3D.TEXTURE_FILTER_NEAREST
		check(material.texture_repeat and material.texture_filter == expected_filter, "UV repeat retained and terrain filter selected correctly: " + name)
		var png := Image.load_from_file(pack.assets["texture." + name.to_lower()].path)
		var runtime_image := texture.get_image()
		check(runtime_image.has_mipmaps() == enhanced_terrain, "Mipmaps are opt-in: " + name)
		runtime_image.clear_mipmaps()
		check(png.get_data() == runtime_image.get_data(), "Runtime base pixels match supplied PNG: " + name)
	var world := await World.load_world(folder.path_join("DATA/SCEN1.BSP"), self, func(_message: String) -> void: pass)
	check(world != null, "Full original world loads with the texture mod")
	if world != null:
		var chunks := 0
		for child in world.get_children():
			if not child is MeshInstance3D: continue
			chunks += 1
			var material := child.mesh.surface_get_material(0) as StandardMaterial3D
			var ref: Dictionary = refs[int(child.get_meta("terrain_material"))]
			if str(ref.texture).is_empty():
				check(material != null and material.albedo_texture == null and material.albedo_color == ref.color, "Untextured world chunk retains original colour: " + str(child.name))
			else:
				check(material != null and material.albedo_texture != null and material.albedo_texture.get_meta("asset_mod", "") == pack.name, "Converted world chunk uses replacement: " + str(child.name))
		check(chunks > 0, "World contains rendered terrain chunks")
		var natural := preload("res://natural_light.gd").new()
		natural.attach(world)
		for child in world.get_children():
			if not child is MeshInstance3D: continue
			var lit := child.get_active_material(0) as ShaderMaterial
			if lit == null: continue
			var original := lit.get_meta("natural_original") as StandardMaterial3D
			var uses_mipmaps: bool = original.get_meta("terrain_mipmaps", false)
			check((lit.get_shader_parameter("terrain_mipmaps") == true) == uses_mipmaps, "Natural lighting retains opt-in terrain sampling: " + str(child.name))
			if uses_mipmaps: check(lit.get_shader_parameter("terrain_albedo_texture") == original.albedo_texture, "Natural lighting uses the same mipmapped texture: " + str(child.name))
		world.free()
	check(Mods.runtime_warnings.is_empty(), "No runtime fallback warnings")
	Mods.apply([], [], false)
	var restored := Assets._load_texture(folder, "CAVEY", "", {})
	check(restored != null and restored.get_width() == 128 and not restored.has_meta("asset_mod"), "Disabling mod restores original texture")
	print("Upscaled map textures: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
