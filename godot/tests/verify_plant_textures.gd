extends SceneTree

const Mods = preload("res://mod_registry.gd")
const Assets = preload("res://clump_loader.gd")
const Current = preload("res://plant_current.gd")
const Natural = preload("res://natural_light.gd")
const NAMES := ["BUSH1", "BUSH2", "BUSH3", "BUSH4", "REED"]
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

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
	if folder.is_empty(): check(false, "Original folder required"); quit(1); return
	var packs := Mods.packs.filter(func(pack: Dictionary) -> bool: return pack.id == "detailed-plant-textures")
	check(packs.size() == 1, "Plant pack discovered exactly once")
	if packs.size() != 1: quit(1); return
	var pack: Dictionary = packs[0]
	check(pack.valid and pack.errors.is_empty() and pack.assets.size() == 5, "Exactly five valid original plant replacements")
	check(Mods.active_ids().is_empty(), "Discovery leaves real player preferences untouched")
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(pack.folder).path_join("sources.json")))
	check(provenance.factor == 8 and provenance.generator == "built-in image_gen" and provenance.textures.size() == 5, "Scale and generator provenance")
	var original_geometry := {}
	for name in NAMES:
		var node := Assets.load_clump(folder.path_join("CLUMPS/" + str(name) + ".DFF"))
		check(node != null, "Original model loads: " + str(name))
		if node == null: continue
		var current := Current.new()
		current.attach(node)
		check(current.plant_count == 1 and not current.materials.is_empty(), "Original plant animation still attaches: " + str(name))
		for material in current.materials:
			check(material.get_shader_parameter("terrain_mipmaps") != true, "Original plants retain default nearest sampler")
		original_geometry[name] = geometry(node)
		var natural := Natural.new()
		natural.attach(node)
		for material in current.materials:
			check(material.shader == preload("res://natural_plant.gdshader") and material.get_shader_parameter("terrain_mipmaps") != true, "Original natural plant retains default sampler")
		node.free()
	var enabled: Array[String] = ["upscaled-map-textures", "detailed-building-textures", "detailed-plant-textures"]
	Mods.apply(enabled, enabled, false)
	for name in NAMES:
		var lower: String = str(name).to_lower()
		var id := "texture." + lower
		check(pack.assets.has(id) and provenance.textures.has(lower), "Original plant binding: " + id)
		if not pack.assets.has(id) or not provenance.textures.has(lower): continue
		var entry: Dictionary = provenance.textures[lower]
		var replacement: Dictionary = pack.assets[id]
		check(Mods.candidates(id).size() == 1, "No overlap with terrain/building packs: " + id)
		check(entry.model == name and entry.mask == str(name) + "M", "Original model/mask identity: " + id)
		for source in entry.source_files:
			check(FileAccess.get_sha256(folder.path_join(str(source))) == str(entry.source_files[source]), "Original colour/mask checksum: " + str(source))
		check(FileAccess.get_sha256(replacement.path) == str(entry.output_sha256), "Installed plant checksum: " + id)
		check(str(entry.get("prompt", "")).length() > 100 and str(entry.get("generated_sha256", "")).length() == 64, "Prompt and generation checksum recorded: " + id)
		var png := Image.load_from_file(replacement.path)
		check(png != null and png.get_size() == Vector2i(1024, 1024) and png.get_format() == Image.FORMAT_RGBA8, "Exactly 8x RGBA dimensions: " + id)
		if png == null: continue
		var solid := 0
		var clear := 0
		for y in range(0,1024,8):
			for x in range(0,1024,8):
				var alpha := png.get_pixel(x,y).a
				if alpha > 0.5: solid += 1
				if alpha < 0.01: clear += 1
		check(solid > 512 and clear > 1024, "Foreground and genuinely transparent cutout gaps retained: " + id)
		if name == "REED":
			var opaque_x := []
			for x in range(1024):
				if png.get_pixel(x,512).a > 0.5: opaque_x.append(x)
			check(not opaque_x.is_empty() and int(opaque_x.front()) > 350 and int(opaque_x.back()) < 675, "Reed remains a narrow centred UV strip")
			check(png.get_pixel(512,0).a > 0.5 and png.get_pixel(512,1023).a > 0.5, "Reed strip reaches both vertical repeat boundaries")
		var texture := Assets._load_texture(folder, str(name), str(name) + "M", {})
		check(texture != null and texture.get_meta("asset_mod", "") == pack.name and texture.get_meta("terrain_mipmaps", false), "Runtime uses plant pack: " + id)
		if texture == null: continue
		var image := texture.get_image()
		check(image.has_mipmaps(), "Plant mipmaps generated: " + id)
		image.clear_mipmaps()
		check(image.get_data() == png.get_data(), "Generated RGBA used directly instead of mismatched legacy mask: " + id)
		var node := Assets.load_clump(folder.path_join("CLUMPS/" + str(name) + ".DFF"))
		check(node != null, "Detailed original plant model loads: " + str(name))
		if node == null: continue
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			for surface in range(mesh.mesh.get_surface_count()):
				var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				check(material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and material.alpha_scissor_threshold == 0.5, "Original cutout rendering threshold retained")
		var current := Current.new()
		current.attach(node)
		check(current.plant_count == 1 and not current.materials.is_empty(), "Detailed plant animation attaches")
		check(original_geometry.get(name) == geometry(node), "Original subdivided vertices, normals and UVs unchanged: " + str(name))
		var settings := current.settings.duplicate(true)
		for material in current.materials:
			check(material.shader == preload("res://plant_current.gdshader") and material.get_shader_parameter("terrain_mipmaps") == true, "Sway shader opts into filtered HD sampling")
			var albedo := material.get_shader_parameter("terrain_albedo_texture") as Texture2D
			check(albedo != null and albedo.get_meta("asset_mod", "") == pack.name and albedo.get_width() == 1024, "Sway shader retains HD cutout")
			material.set_shader_parameter("propeller_bend", Vector3(0.1,0.2,0.3))
		var natural := Natural.new()
		natural.attach(node)
		check(current.settings == settings, "Mod does not change sway/wash settings")
		for material in current.materials:
			check(material.shader == preload("res://natural_plant.gdshader") and material.get_shader_parameter("terrain_mipmaps") == true, "Natural plant conversion retains HD sampling")
			check(material.get_shader_parameter("terrain_albedo_texture") == material.get_shader_parameter("albedo_texture"), "Natural plant uses the same cutout texture")
			check(material.get_shader_parameter("propeller_bend") == Vector3(0.1,0.2,0.3), "Natural conversion preserves wash animation state")
		node.free()
	check(Mods.runtime_warnings.is_empty(), "No plant texture fallback warnings")
	Mods.apply(["upscaled-map-textures", "detailed-building-textures"], ["upscaled-map-textures", "detailed-building-textures"], false)
	var restored := Assets._load_texture(folder,"BUSH1","BUSH1M",{})
	check(restored != null and restored.get_width() == 128 and not restored.has_meta("asset_mod"), "Disabling plant pack alone restores original masked texture")
	check(Assets._load_texture(folder,"CAVEY","",{}).get_meta("asset_mod","") == "Detailed Map Textures (8x)", "Terrain pack remains active")
	check(Assets._load_texture(folder,"TRAD5","",{}).get_meta("asset_mod","") == "Detailed Building Textures (8x)", "Building pack remains active")
	Mods.apply([],[],false)
	print("Detailed plant textures: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func geometry(node: Node3D) -> Array:
	var result := []
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			result.append([arrays[Mesh.ARRAY_VERTEX],arrays[Mesh.ARRAY_NORMAL],arrays[Mesh.ARRAY_TEX_UV]])
	return result
