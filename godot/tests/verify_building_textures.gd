extends SceneTree

const Mods = preload("res://mod_registry.gd")
const Assets = preload("res://clump_loader.gd")
const World = preload("res://world_loader.gd")
const Builder = preload("res://../tools/build_detailed_building_mod.gd")
var checks := 0
var failures := 0

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
	var folder := args[0] if not args.is_empty() else preload("res://asset_paths.gd").find_game_folder()
	if folder.is_empty(): check(false, "Original game folder required"); quit(1); return
	var packs := Mods.packs.filter(func(pack: Dictionary) -> bool: return pack.id == "detailed-building-textures")
	check(packs.size() == 1, "Building pack discovered exactly once")
	if packs.size() != 1: quit(1); return
	var pack: Dictionary = packs[0]
	check(pack.valid and pack.errors.is_empty(), "Building manifest and PNG paths valid")
	check(Mods.active_ids().is_empty(), "Discovery does not enable mods or write player preferences")
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(pack.folder).path_join("sources.json")))
	var names := Builder.NAMES.split(" ")
	check(pack.assets.size() == 52 and provenance.textures.size() == 52, "Exactly 52 selected building atlases")
	check(provenance.factor == 8 and provenance.generator == "built-in image_gen", "Scale and generation method recorded")
	Mods.apply(["upscaled-map-textures", "detailed-building-textures"], ["upscaled-map-textures", "detailed-building-textures"], false)
	var shared := 0
	for name in names:
		var id := "texture." + name
		check(pack.assets.has(id) and provenance.textures.has(name), "Expected building binding: " + name)
		if not pack.assets.has(id) or not provenance.textures.has(name): continue
		var entry: Dictionary = provenance.textures[name]
		var replacement: Dictionary = pack.assets[id]
		var original := preload("res://legacy_bmp.gd")._load_image(folder.path_join(str(entry.source_file)))
		var png := Image.load_from_file(replacement.path)
		check(original != null and png != null, "Original and replacement decode: " + name)
		if original == null or png == null: continue
		check(FileAccess.get_sha256(folder.path_join(str(entry.source_file))) == str(entry.source_sha256), "Original asset identity recorded: " + name)
		check(FileAccess.get_sha256(replacement.path) == str(entry.output_sha256), "Replacement checksum: " + name)
		check(str(entry.get("prompt", "")).length() > 100 and str(entry.get("generated_sha256", "")).length() == 64, "Generation provenance: " + name)
		check(png.get_size() == original.get_size() * 8, "8x size and original UV atlas aspect: " + name)
		check(replacement.get("terrain_mipmaps", false), "Building opts into filtered mipmaps: " + name)
		var candidates := Mods.candidates(id)
		check(not candidates.is_empty() and str(candidates[0].name) == str(pack.name), "Building wins mod priority: " + name)
		if candidates.size() > 1: shared += 1
		var texture := Assets._load_texture(folder, name.to_upper(), "", {})
		check(texture != null and texture.get_meta("asset_mod", "") == pack.name, "Runtime uses building texture: " + name)
		if texture == null: continue
		var runtime := texture.get_image()
		check(runtime.has_mipmaps() and texture.get_meta("terrain_mipmaps", false), "Runtime mipmaps generated: " + name)
		runtime.clear_mipmaps()
		check(runtime.get_data() == png.get_data(), "Runtime retains exact supplied base pixels: " + name)
	check(shared == 50, "Building pack overrides 50 shared world IDs and adds two model IDs")
	var cave := Assets._load_texture(folder, "CAVEY", "", {})
	check(cave.get_meta("asset_mod", "") == "Detailed Map Textures (8x)", "Natural terrain remains supplied by terrain pack")
	var world := await World.load_world(folder.path_join("DATA/SCEN1.BSP"), self, func(_message: String) -> void: pass)
	check(world != null, "Original world loads with both packs")
	if world != null:
		verify_materials(world, str(pack.name))
		world.free()
	for model in provenance.models:
		var node := Assets.load_clump(folder.path_join("CLUMPS/" + str(model) + ".DFF"))
		check(node != null, "Static building model loads: " + str(model))
		if node != null:
			verify_materials(node, str(pack.name))
			node.free()
	check(Mods.runtime_warnings.is_empty(), "No texture fallback warnings")
	Mods.apply(["upscaled-map-textures"], ["upscaled-map-textures"], false)
	var fallback := Assets._load_texture(folder, "TRAD5", "", {})
	check(fallback != null and fallback.get_width() == 1024 and fallback.get_meta("asset_mod", "") == "Detailed Map Textures (8x)", "Disabling buildings restores underlying terrain pack's shared texture")
	Mods.apply([], [], false)
	var restored := Assets._load_texture(folder, "TRAD5", "", {})
	check(restored != null and restored.get_width() == 128 and not restored.has_meta("asset_mod"), "Disabling both restores original 128px atlas")
	var original_model := Assets.load_clump(folder.path_join("CLUMPS/DOCKING.DFF"))
	check(original_model != null, "Original model still loads with mods disabled")
	if original_model != null:
		for mesh in original_model.find_children("*", "MeshInstance3D", true, false):
			for surface in range(mesh.mesh.get_surface_count()):
				var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				check(material != null and material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST and not material.get_meta("terrain_mipmaps", false), "Original model keeps legacy nearest sampling")
		original_model.free()
	print("Detailed building textures: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func verify_materials(node: Node3D, pack_name: String) -> void:
	var building_surfaces := 0
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null or material.albedo_texture == null or material.albedo_texture.get_meta("asset_mod", "") != pack_name: continue
			building_surfaces += 1
			check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC and material.get_meta("terrain_mipmaps", false), "Building material retains opt-in sampling")
	check(building_surfaces > 0, "Building has replaced rendered surfaces: " + str(node.name))
	var natural := preload("res://natural_light.gd").new()
	natural.attach(node)
	var lit_surfaces := 0
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh.mesh.get_surface_count()):
			var lit := mesh.get_active_material(surface) as ShaderMaterial
			if lit == null: continue
			var original := lit.get_meta("natural_original") as StandardMaterial3D
			if original == null or original.albedo_texture == null or original.albedo_texture.get_meta("asset_mod", "") != pack_name: continue
			lit_surfaces += 1
			check(lit.get_shader_parameter("terrain_mipmaps") == true and lit.get_shader_parameter("terrain_albedo_texture") == original.albedo_texture, "Natural lighting retains filtered building texture")
	check(lit_surfaces == building_surfaces, "All building surfaces retain replacements through natural lighting")
