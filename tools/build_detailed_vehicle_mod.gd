extends SceneTree
## Build a NEW submarine/equipment pack from its original material inventory.
## -- <original-game> <inventory.json> <generated-folder> <building-pack> <new-output>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 5: fail("Expected original game, inventory, generated folder, shared building pack and NEW output folder."); return
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var shared: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[3].path_join("mod.json")))
	var shared_sources: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[3].path_join("sources.json")))
	if not plan is Dictionary or not plan.get("textures") is Dictionary or not plan.get("models") is Array or plan.textures.size() != 66 or plan.models.size() != 71:
		fail("Expected the original 66-texture / 71-model submarine/equipment inventory."); return
	if not shared is Dictionary or shared.get("id", "") != "detailed-building-textures" or not shared_sources is Dictionary:
		fail("Expected the approved detailed building pack for shared materials."); return
	var output := args[4].replace("\\", "/").simplify_path()
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): fail("Output exists; choose a new directory."); return
	var images := {}
	var sources := {}
	for name in plan.textures:
		var entry: Dictionary = plan.textures[name].duplicate(true)
		for character in str(name):
			if not character in "abcdefghijklmnopqrstuvwxyz0123456789-": fail("Invalid texture name."); return
		if not entry.get("source_files") is Dictionary or entry.source_files.is_empty() or not entry.get("original_size") is Array or entry.original_size.size() != 2:
			fail("Incomplete original source identity: " + str(name)); return
		for relative in entry.source_files:
			if not str(relative).begins_with("GAMETEX/") or ".." in str(relative) or FileAccess.get_sha256(args[0].path_join(str(relative))) != str(entry.source_files[relative]):
				fail("Original source checksum mismatch: " + str(relative)); return
		var id := "texture." + str(name)
		var image: Image
		if shared.assets.has(id):
			var previous: Dictionary = shared_sources.textures.get(name,{})
			var path: String = args[3].path_join(str(shared.assets[id].file))
			if not entry.source_files.values().has(previous.get("source_sha256", "")) or FileAccess.get_sha256(path) != previous.get("output_sha256", ""):
				fail("Shared building texture provenance mismatch: " + str(name)); return
			image = Image.load_from_file(path)
			entry.method = "Reused approved building reconstruction of the identical original texture"
			entry.reused_from = "detailed-building-textures"
			entry.reused_output_sha256 = previous.output_sha256
			entry.generated_sha256 = previous.generated_sha256
			entry.generated_size = previous.generated_size
			entry.prompt = previous.prompt
		else:
			var path: String = args[2].path_join(str(name) + ".png")
			image = Image.load_from_file(path)
			if image == null or image.is_empty() or mini(image.get_width(),image.get_height()) < 1024:
				fail("Missing/undersized generated atlas: " + str(name)); return
			entry.generated_sha256 = FileAccess.get_sha256(path)
			entry.generated_size = [image.get_width(),image.get_height()]
			entry.prompt = FileAccess.get_file_as_string(args[2].path_join(str(name) + ".prompt.txt")).strip_edges()
			if str(entry.prompt).is_empty(): fail("Missing prompt: " + str(name)); return
			entry.method = "AI detail reconstruction; normalized to original atlas dimensions times eight"
		if image == null or image.is_empty() or absf(float(image.get_width()) / image.get_height() - float(entry.original_size[0]) / entry.original_size[1]) > 0.025:
			fail("Atlas aspect ratio changed: " + str(name)); return
		if not str(entry.get("mask", "")).is_empty() and image.detect_alpha() == Image.ALPHA_NONE:
			fail("Masked equipment atlas lost alpha: " + str(name)); return
		if not str(entry.get("mask", "")).is_empty():
			var sample := image.duplicate() as Image
			sample.resize(128,128,Image.INTERPOLATE_NEAREST)
			var clear := 0
			var solid := 0
			for y in range(128):
				for x in range(128):
					if sample.get_pixel(x,y).a < 0.1: clear += 1
					if sample.get_pixel(x,y).a > 0.5: solid += 1
			if clear < 100 or solid < 100: fail("Masked atlas lost its actual cutout: " + str(name)); return
		entry.generator = "built-in image_gen"
		sources[name] = entry
		images[name] = image
	if DirAccess.make_dir_recursive_absolute(output.path_join("textures")) != OK: fail("Could not create output."); return
	var manifest := {"schema_version":1,"id":"detailed-submarine-equipment-textures","name":"Detailed Submarine & Equipment Textures (8x)","version":"1.0.0","description":"8x reconstructed original submarine, tool, weapon and mechanical equipment textures. Load after the map and building texture packs. Wildlife is unchanged.","assets":{}}
	for name in images:
		var image: Image = images[name]
		var entry: Dictionary = sources[name]
		var width := int(entry.original_size[0]) * 8
		var height := int(entry.original_size[1]) * 8
		# Keep approved shared pixels byte-identical. Only new generations need
		# normalization; masked atlases retain their generated RGBA cutouts.
		if not entry.has("reused_from"):
			image.convert(Image.FORMAT_RGBA8 if not str(entry.mask).is_empty() else Image.FORMAT_RGB8)
			image.resize(width,height,Image.INTERPOLATE_LANCZOS)
			if not str(entry.mask).is_empty(): image.fix_alpha_edges()
		if image.get_size() != Vector2i(width,height): fail("Shared atlas has wrong output dimensions."); return
		var relative: String = "textures/" + str(name) + ".png"
		if image.save_png(output.path_join(relative)) != OK: fail("Could not save " + str(name)); return
		entry.output_size = [width,height]
		entry.output_sha256 = FileAccess.get_sha256(output.path_join(relative))
		manifest.assets["texture." + str(name)] = {"file":relative,"terrain_mipmaps":true}
	var provenance := {"factor":8,"models":plan.models,"unavailable":plan.get("unavailable",{}),"textures":sources,"generator":"built-in image_gen","new_reconstructions":54,"shared_reconstructions":12}
	if not write_json(output.path_join("sources.json"),provenance): return
	if not write_json(output.path_join("mod.json"),manifest): return
	print("Built submarine/equipment pack: 66 textures, 54 new and 12 shared reconstructions.")
	quit()

func write_json(path: String,data: Dictionary) -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: fail("Could not write " + path); return false
	file.store_string(JSON.stringify(data,"  ") + "\n")
	return true

func fail(message: String) -> void:
	push_error(message)
	quit(1)
