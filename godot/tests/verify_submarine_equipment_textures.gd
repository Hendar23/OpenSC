extends SceneTree
const Mods = preload("res://mod_registry.gd")
const Assets = preload("res://clump_loader.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)

func run() -> void:
	preload("res://asset_cache.gd").enabled = false
	Mods.initialize(false)
	var args := OS.get_cmdline_user_args()
	var folder := args[0] if not args.is_empty() else preload("res://asset_paths.gd").find_game_folder()
	var packs := Mods.packs.filter(func(pack: Dictionary) -> bool: return pack.id == "detailed-submarine-equipment-textures")
	check(not folder.is_empty() and packs.size() == 1,"Original game and one submarine/equipment pack available")
	if folder.is_empty() or packs.size() != 1: quit(1); return
	var pack: Dictionary = packs[0]
	check(pack.valid and pack.errors.is_empty() and pack.assets.size() == 66,"Valid 66-texture pack")
	check(Mods.active_ids().is_empty(),"Discovery does not enable mods or write real preferences")
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(pack.folder).path_join("sources.json")))
	check(provenance.factor == 8 and provenance.models.size() == 71 and provenance.textures.size() == 66,"Original model inventory and exact 8x scale")
	check(provenance.unavailable.has("sub2") and not pack.assets.has("texture.sub2"),"Missing original unused SUB2 recorded without invented replacement")
	var geometry_before := {}
	for model in provenance.models:
		var node := Assets.load_clump(folder.path_join("CLUMPS/" + str(model) + ".DFF"))
		check(node != null,"Original mechanical model loads: " + str(model))
		if node == null: continue
		geometry_before[model] = geometry(node)
		node.free()
	var ids: Array[String] = ["upscaled-map-textures","detailed-building-textures","detailed-plant-textures","detailed-submarine-equipment-textures"]
	Mods.apply(ids,ids,false)
	var shared_count := 0
	var masked_count := 0
	for name in provenance.textures:
		var entry: Dictionary = provenance.textures[name]
		var id := "texture." + str(name)
		check(pack.assets.has(id),"Original texture appears in manifest: " + id)
		if not pack.assets.has(id): continue
		var replacement: Dictionary = pack.assets[id]
		for relative in entry.source_files:
			check(FileAccess.get_sha256(folder.path_join(str(relative))) == str(entry.source_files[relative]),"Original colour/mask identity: " + str(relative))
		check(FileAccess.get_sha256(replacement.path) == str(entry.output_sha256),"Final PNG checksum: " + id)
		check(entry.generator == "built-in image_gen" and str(entry.get("prompt", "")).length() > 100 and str(entry.generated_sha256).length() == 64,"Exact prompt and generator provenance: " + id)
		var png := Image.load_from_file(replacement.path)
		check(png != null and png.get_width() == int(entry.original_size[0])*8 and png.get_height() == int(entry.original_size[1])*8,"Exact 8x atlas size/aspect: " + id)
		if png == null: continue
		if entry.has("reused_from"):
			shared_count += 1
			check(entry.reused_from == "detailed-building-textures" and entry.output_sha256 == entry.reused_output_sha256,"Approved shared atlas remains byte-identical: " + id)
		var masked := not str(entry.mask).is_empty()
		if masked:
			masked_count += 1
			check(png.get_format() == Image.FORMAT_RGBA8 and png.detect_alpha() != Image.ALPHA_NONE,"Mask-bearing equipment uses actual RGBA alpha: " + id)
			var opaque := 0
			var clear := 0
			for y in range(0,png.get_height(),8):
				for x in range(0,png.get_width(),8):
					if png.get_pixel(x,y).a > 0.5: opaque += 1
					if png.get_pixel(x,y).a < 0.1: clear += 1
			check(opaque > 100 and clear > 100,"Masked atlas retains foreground and transparent gaps: " + id)
		var texture := Assets._load_texture(folder,str(name),str(entry.mask),{})
		check(texture != null and texture.get_meta("asset_mod", "") == pack.name,"Runtime uses the new pack: " + id)
		if texture == null: continue
		var image := texture.get_image()
		check(image.has_mipmaps() and texture.get_meta("terrain_mipmaps",false),"Runtime filtered mipmaps: " + id)
		image.clear_mipmaps()
		check(image.get_data() == png.get_data(),"Runtime preserves PNG base colour and alpha: " + id)
		check(Mods.candidates(id)[0].name == pack.name,"New pack wins intended priority: " + id)
	check(shared_count == 12 and masked_count == 4,"Exact reused and alpha-bearing texture scope")
	for model in provenance.models:
		var node := Assets.load_clump(folder.path_join("CLUMPS/" + str(model) + ".DFF"))
		check(node != null,"Mechanical model loads with replacements: " + str(model))
		if node == null: continue
		check(geometry_before.get(model) == geometry(node),"Model frame transforms, positions, normals and UVs preserved: " + str(model))
		var updated := 0
		for mesh in node.find_children("*","MeshInstance3D",true,false):
			for surface in range(mesh.mesh.get_surface_count()):
				var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				if material == null or material.albedo_texture == null: continue
				check(material.albedo_texture.get_meta("asset_mod", "") == pack.name,"Rendered mechanical surface uses reconstructed texture: " + str(model))
				check(material.get_meta("terrain_mipmaps",false) and material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,"Mechanical surface retains opt-in filtering")
				updated += 1
		var natural := preload("res://natural_light.gd").new()
		natural.attach(node)
		var lit_count := 0
		for mesh in node.find_children("*","MeshInstance3D",true,false):
			for surface in range(mesh.mesh.get_surface_count()):
				var material := mesh.get_active_material(surface) as ShaderMaterial
				if material == null: continue
				var original := material.get_meta("natural_original") as StandardMaterial3D
				if original == null or original.albedo_texture == null: continue
				check(material.get_shader_parameter("terrain_mipmaps") == true and material.get_shader_parameter("terrain_albedo_texture") == original.albedo_texture,"Natural lighting retains reconstructed texture and sampler")
				lit_count += 1
		check(lit_count == updated,"Natural lighting preserves every textured surface: " + str(model))
		node.free()
	# Wildlife exclusion follows original material IDs, including fin/mask atlases.
	for model in ["ANGEL","ANGLER","BADJELLY","BADNASTY","BADTHING","BARACUDA","BIGEEL","BLOWFISH","CLAM","CRAB","DOGFISH","EEL","ELVER","JACKFISH","JELLYEGG","KIDJELLY","LIONFISH","MEEL","MJACK","MLION","MOMJELLY","MPIRANHA","MSILVER","MUTANT","PIRANHA","SEAHORSE","SILVER","SMALLEEL","STINGRAY","TURTLE","BABY"]:
		var data := FileAccess.get_file_as_bytes(folder.path_join("CLUMPS/" + model + ".DFF"))
		for ref in Assets._material_references(data,0,data.size()):
			if not str(ref.texture).is_empty(): check(not pack.assets.has("texture." + str(ref.texture).to_lower()),"Wildlife material left for its own pack: " + model)
	check(Mods.runtime_warnings.is_empty(),"No replacement fallback warnings")
	ids.erase("detailed-submarine-equipment-textures")
	Mods.apply(ids,ids,false)
	check(Assets._load_texture(folder,"SUB1","",{}).get_width() == 128,"Disabling pack restores original player hull")
	check(Assets._load_texture(folder,"TECHIE","",{}).get_meta("asset_mod", "") == "Detailed Building Textures (8x)","Shared building fallback retained")
	check(Assets._load_texture(folder,"CAVEY","",{}).get_meta("asset_mod", "") == "Detailed Map Textures (8x)","Terrain pack retained")
	check(Assets._load_texture(folder,"BUSH1","BUSH1M",{}).get_meta("asset_mod", "") == "Detailed Plant Textures (8x)","Plant pack retained")
	Mods.apply([],[],false)
	print("Submarine/equipment textures: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func geometry(node: Node3D) -> Array:
	var result := [node.transform]
	for child in node.get_children():
		if child is Node3D: result.append(geometry(child))
	if node is MeshInstance3D:
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			result.append([arrays[Mesh.ARRAY_VERTEX],arrays[Mesh.ARRAY_NORMAL],arrays[Mesh.ARRAY_TEX_UV]])
	return result
