extends SceneTree
## Build a new 8x building pack from a source inventory and generated images.
## -- <inventory.json> <generated-folder> <new-pack-folder>

const NAMES := "beam boost boot bucketa bucketc can cantop chevron crete facpad factory factory1 groutc2 honey honey2 interboo lightpo lights metall metall1 metall2 metall3 metally metallyh metalblk metrid outpost pad1 padtech padtrad pipe podscape pointy prong rivet1 rivet2 shell side1 siding speckirn techie techieb techoutp techtop teeth trad5 tradout tradpowr traz traztop vent wood2"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		fail("Expected inventory JSON, generated image folder and new output folder."); return
	var inventory: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not inventory is Dictionary or not inventory.get("textures") is Dictionary:
		fail("Invalid source inventory."); return
	var names := NAMES.split(" ")
	if inventory.textures.size() != names.size():
		fail("Inventory must contain exactly the 52 building texture IDs."); return
	var output := args[2].replace("\\", "/").simplify_path()
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output):
		fail("Output already exists; choose a new directory."); return
	var images := {}
	for name in names:
		if not inventory.textures.has(name): fail("Missing inventory asset: " + name); return
		var entry: Dictionary = inventory.textures[name]
		var size: Variant = entry.get("original_size", [])
		if not size is Array or size.size() != 2 or int(size[0]) != 128 or int(size[1]) != (150 if name == "tradout" else 128):
			fail("Unexpected original dimensions: " + name); return
		var source := str(entry.get("source_file", ""))
		if not source in ["GAMETEX/" + name.to_upper() + ".BMP", "GAMETEX/" + name.to_upper() + ".RAS"] or str(entry.get("source_sha256", "")).length() != 64:
			fail("Invalid original source identity: " + name); return
		var path := args[1].path_join(name + ".png")
		var image := Image.load_from_file(path)
		if image == null or image.is_empty() or image.get_width() < 1024 or image.get_height() < 1024:
			fail("Missing/undersized generated image: " + name); return
		var aspect := float(image.get_width()) / image.get_height()
		if absf(aspect - float(size[0]) / size[1]) > 0.025:
			fail("Generated image changed atlas aspect ratio: " + name); return
		var prompt := args[1].path_join(name + ".prompt.txt")
		if not FileAccess.file_exists(prompt) or FileAccess.get_file_as_string(prompt).strip_edges().is_empty():
			fail("Missing generation prompt: " + name); return
		images[name] = image
	# No manifest is published until every image has passed validation and saved.
	if DirAccess.make_dir_recursive_absolute(output.path_join("textures")) != OK:
		fail("Could not create pack output."); return
	var manifest := {"schema_version": 1, "id": "detailed-building-textures", "name": "Detailed Building Textures (8x)", "version": "1.0.0", "description": "52 original building, docking and structural textures with reconstructed fine surface detail at 8x resolution. Load after Detailed Map Textures (8x).", "assets": {}}
	var provenance := {"factor": 8, "method": "AI detail reconstruction, normalized to original atlas dimensions times eight", "generator": "built-in image_gen", "models": inventory.get("models", []), "textures": {}}
	for name in names:
		var image: Image = images[name]
		var entry: Dictionary = inventory.textures[name].duplicate(true)
		entry.generated_size = [image.get_width(), image.get_height()]
		entry.generated_sha256 = FileAccess.get_sha256(args[1].path_join(name + ".png"))
		entry.prompt = FileAccess.get_file_as_string(args[1].path_join(name + ".prompt.txt")).strip_edges()
		image.convert(Image.FORMAT_RGB8)
		image.resize(int(entry.original_size[0]) * 8, int(entry.original_size[1]) * 8, Image.INTERPOLATE_LANCZOS)
		var relative := "textures/" + name + ".png"
		if image.save_png(output.path_join(relative)) != OK:
			fail("Could not save " + name); return
		entry.output_size = [image.get_width(), image.get_height()]
		entry.output_sha256 = FileAccess.get_sha256(output.path_join(relative))
		provenance.textures[name] = entry
		manifest.assets["texture." + name] = {"file": relative, "terrain_mipmaps": true}
	if not write_json(output.path_join("sources.json"), provenance): return
	if not write_json(output.path_join("mod.json"), manifest): return
	print("Built detailed building texture pack: ", names.size(), " original atlas replacements at 8x.")
	quit()

func write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: fail("Could not write " + path); return false
	file.store_string(JSON.stringify(data, "  ") + "\n")
	return true

func fail(message: String) -> void:
	push_error(message)
	quit(1)
