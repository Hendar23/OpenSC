extends SceneTree
const Mods = preload("res://mod_registry.gd")
const Assets = preload("res://clump_loader.gd")
const CreatureAnimation = preload("res://creature_animation.gd")
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
	var packs := Mods.packs.filter(func(pack: Dictionary) -> bool: return pack.id == "detailed-wildlife-textures")
	check(not folder.is_empty() and packs.size() == 1,"Original game and one wildlife pack available")
	if folder.is_empty() or packs.size() != 1: quit(1); return
	var pack: Dictionary = packs[0]
	check(pack.valid and pack.errors.is_empty() and pack.assets.size() == 38,"Valid pack of exactly 38 original wildlife textures")
	check(Mods.active_ids().is_empty(),"Discovery leaves real preferences unchanged")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(pack.folder).path_join("sources.json")))
	check(source.factor == 8 and source.models.size() == 33 and source.textures.size() == 38,"8x provenance and exact creature model scope")
	var geometry_before := {}
	var pose_before := {}
	for model in source.models:
		var node := Assets.load_clump(folder.path_join("CLUMPS/"+str(model)+".DFF"),PackedStringArray(),true)
		check(node != null,"Original animated creature loads: "+str(model))
		if node == null: continue
		geometry_before[model] = geometry(node)
		var animation := CreatureAnimation.new(node)
		animation.apply(0.35); var first := pose(node)
		animation.apply(0.9); pose_before[model] = [first,pose(node)]
		node.free()
	var ids: Array[String] = ["upscaled-map-textures","detailed-building-textures","detailed-plant-textures","detailed-submarine-equipment-textures","detailed-wildlife-textures"]
	Mods.apply(ids,ids,false)
	var masked := 0
	var scenery := 0
	for name in source.textures:
		var id := "texture."+str(name)
		var entry: Dictionary = source.textures[name]
		check(pack.assets.has(id),"Original wildlife asset binding: "+id)
		if not pack.assets.has(id): continue
		for relative in entry.source_files:
			check(FileAccess.get_sha256(folder.path_join(str(relative))) == str(entry.source_files[relative]),"Original colour/mask checksum: "+str(relative))
		var replacement: Dictionary = pack.assets[id]
		check(FileAccess.get_sha256(replacement.path) == str(entry.output_sha256),"Installed wildlife PNG checksum: "+id)
		check(entry.generator == "built-in image_gen" and str(entry.prompt).length() > 100 and str(entry.generated_sha256).length() == 64,"Generator/prompt provenance: "+id)
		var png := Image.load_from_file(replacement.path)
		check(png != null and png.get_size() == Vector2i(1024,1024),"Exactly 8x original atlas dimensions: "+id)
		if png == null: continue
		if not str(entry.mask).is_empty():
			masked += 1
			check(png.get_format() == Image.FORMAT_RGBA8 and png.detect_alpha() != Image.ALPHA_NONE,"Fin/spine cutout supplies actual alpha: "+id)
			var clear := 0; var solid := 0
			for y in range(0,1024,8):
				for x in range(0,1024,8):
					if png.get_pixel(x,y).a < 0.1: clear += 1
					if png.get_pixel(x,y).a > 0.5: solid += 1
			check(clear > 32 and solid > 100,"Cutout foreground and gaps retained: "+id)
		var texture := Assets._load_texture(folder,str(name),str(entry.mask),{})
		check(texture != null and texture.get_meta("asset_mod","") == pack.name,"Runtime uses wildlife replacement: "+id)
		if texture == null: continue
		var image := texture.get_image()
		check(image.has_mipmaps() and texture.get_meta("terrain_mipmaps",false),"Opt-in wildlife mipmaps generated: "+id)
		image.clear_mipmaps()
		check(image.get_data() == png.get_data(),"Runtime colour/alpha equal supplied base PNG: "+id)
		check(Mods.candidates(id)[0].name == pack.name,"Wildlife pack wins correct priority: "+id)
		if entry.get("world_material",false):
			scenery += 1
			var material := preload("res://world_loader.gd")._terrain_material({"texture":str(name),"mask":"","color":Color.WHITE},folder,{})
			check(material.albedo_texture.get_meta("asset_mod","") == pack.name and material.get_meta("terrain_mipmaps",false),"Wildlife scenery works through world-material loader")
	check(masked == 10 and scenery == 2,"Exactly ten masked atlases and two scenery textures")
	for model in source.models:
		var node := Assets.load_clump(folder.path_join("CLUMPS/"+str(model)+".DFF"),PackedStringArray(),true)
		check(node != null,"Detailed animated creature loads: "+str(model))
		if node == null: continue
		check(geometry_before.get(model) == geometry(node),"Original geometry, UVs, frames and morph arrays preserved: "+str(model))
		var animation := CreatureAnimation.new(node)
		animation.apply(0.35); var first := pose(node)
		animation.apply(0.9)
		check(pose_before.get(model) == [first,pose(node)],"Original swim/rigid animation poses unchanged: "+str(model))
		var textured := 0
		for mesh in node.find_children("*","MeshInstance3D",true,false):
			for surface in range(mesh.mesh.get_surface_count()):
				var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				if material == null or material.albedo_texture == null: continue
				check(material.albedo_texture.get_meta("asset_mod","") == pack.name,"Creature surface uses detailed skin: "+str(model))
				check(material.get_meta("terrain_mipmaps",false) and material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,"Creature material retains filtered sampling")
				textured += 1
		var natural := preload("res://natural_light.gd").new(); natural.attach(node)
		var lit_count := 0
		for mesh in node.find_children("*","MeshInstance3D",true,false):
			for surface in range(mesh.mesh.get_surface_count()):
				var material := mesh.get_active_material(surface) as ShaderMaterial
				if material == null: continue
				var original := material.get_meta("natural_original") as StandardMaterial3D
				if original == null or original.albedo_texture == null: continue
				check(material.get_shader_parameter("terrain_mipmaps") == true and material.get_shader_parameter("terrain_albedo_texture") == original.albedo_texture,"Natural lighting retains reconstructed skin/cutout")
				lit_count += 1
		check(lit_count == textured,"Natural light retains every textured creature surface")
		node.free()
	check(Mods.runtime_warnings.is_empty(),"No replacement fallback warnings")
	for other in ["detailed-building-textures","detailed-plant-textures","detailed-submarine-equipment-textures"]:
		for candidate in Mods.packs:
			if candidate.id != other: continue
			for id in pack.assets: check(not candidate.assets.has(id),"No unrelated building/plant/submarine override: "+str(id))
	ids.erase("detailed-wildlife-textures"); Mods.apply(ids,ids,false)
	check(Assets._load_texture(folder,"ANGEL","",{}).get_width() == 128,"Disabling pack restores original creature skin")
	check(Assets._load_texture(folder,"LIMPET","",{}).get_meta("asset_mod","") == "Detailed Map Textures (8x)","Scenery falls back to prior terrain pack")
	check(Assets._load_texture(folder,"SUB1","",{}).get_meta("asset_mod","") == "Detailed Submarine & Equipment Textures (8x)","Submarine pack remains enabled")
	check(Assets._load_texture(folder,"BUSH1","BUSH1M",{}).get_meta("asset_mod","") == "Detailed Plant Textures (8x)","Plant pack remains enabled")
	Mods.apply([],[],false)
	print("Detailed wildlife textures: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func geometry(node: Node3D) -> Array:
	var result := [node.transform]
	for child in node.get_children():
		if child is Node3D: result.append(geometry(child))
	if node is MeshInstance3D:
		for surface in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			result.append([arrays[Mesh.ARRAY_VERTEX],arrays[Mesh.ARRAY_NORMAL],arrays[Mesh.ARRAY_TEX_UV],node.mesh.surface_get_blend_shape_arrays(surface)])
	return result
func pose(node: Node3D) -> Array:
	var result := [node.transform]
	if node is MeshInstance3D:
		for index in range(node.mesh.get_blend_shape_count()): result.append(node.get_blend_shape_value(index))
	for child in node.get_children():
		if child is Node3D: result.append(pose(child))
	return result
