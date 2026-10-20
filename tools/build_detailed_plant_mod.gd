extends SceneTree
## Build a NEW plant pack; preserve original assets and generated RGBA cutouts.
## -- <original-game-folder> <generated-folder> <new-pack-folder>
const Assets = preload("res://clump_loader.gd")
const NAMES := ["bush1", "bush2", "bush3", "bush4", "reed"]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3: fail("Expected original game folder, generated folder and NEW output folder."); return
	var output := args[2].replace("\\", "/").simplify_path()
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output):
		fail("Output already exists; choose a new directory."); return
	preload("res://asset_cache.gd").enabled = false
	preload("res://mod_registry.gd").initialize(false)
	var images := {}
	var provenance := {"factor": 8, "generator": "built-in image_gen", "method": "AI organic detail reconstruction; RGBA cutouts normalized to eight times original dimensions; transparent edge colours padded for filtering", "textures": {}}
	for name in NAMES:
		var model: String = str(name).to_upper()
		var path := args[0].path_join("CLUMPS/" + model + ".DFF")
		var data := FileAccess.get_file_as_bytes(path)
		var refs := Assets._material_references(data, 0, data.size())
		if refs.size() != 1 or str(refs[0].texture).to_lower() != name or str(refs[0].mask) != model + "M":
			fail("Unexpected original plant material binding: " + model); return
		var original := Assets._load_texture(args[0], str(refs[0].texture), str(refs[0].mask), {})
		if original == null or original.get_size() != Vector2(128, 128):
			fail("Missing or unexpected original plant atlas: " + model); return
		var source_files := {}
		for source in [model, model + "M"]:
			var relative: String = "GAMETEX/" + str(source) + ".BMP"
			if not FileAccess.file_exists(args[0].path_join(relative)): relative = "GAMETEX/" + str(source) + ".RAS"
			var hash := FileAccess.get_sha256(args[0].path_join(relative))
			if hash.length() != 64: fail("Missing original source: " + relative); return
			source_files[relative] = hash
		var image := Image.load_from_file(args[1].path_join(str(name) + ".png"))
		if image == null or image.is_empty() or image.get_width() < 1024 or image.get_width() != image.get_height() or image.detect_alpha() == Image.ALPHA_NONE:
			fail("Expected square transparent RGBA generation, at least 1024px: " + str(name)); return
		var sample := image.duplicate() as Image
		sample.resize(128, 128, Image.INTERPOLATE_NEAREST)
		var solid := 0
		var clear := 0
		for y in range(128):
			for x in range(128):
				var alpha := sample.get_pixel(x, y).a
				if alpha > 0.5: solid += 1
				if alpha < 0.01: clear += 1
		if solid < 512 or clear < 1024:
			fail("Plant cutout lost foreground or transparent gaps: " + str(name)); return
		var prompt := FileAccess.get_file_as_string(args[1].path_join(str(name) + ".prompt.txt")).strip_edges()
		if prompt.is_empty(): fail("Missing generation prompt: " + str(name)); return
		var entry := {"model": model, "mask": str(refs[0].mask), "source_files": source_files, "original_size": [128, 128], "generated_size": [image.get_width(), image.get_height()], "generated_sha256": FileAccess.get_sha256(args[1].path_join(str(name) + ".png")), "prompt": prompt}
		provenance.textures[name] = entry
		images[name] = image
	if DirAccess.make_dir_recursive_absolute(output.path_join("textures")) != OK:
		fail("Could not create output directory."); return
	var manifest := {"schema_version": 1, "id": "detailed-plant-textures", "name": "Detailed Plant Textures (8x)", "version": "1.0.0", "description": "8x detailed cutout textures for all four original aquatic bushes and the reed. Preserves original models and plant animation.", "assets": {}}
	for name in NAMES:
		var image: Image = images[name]
		image.convert(Image.FORMAT_RGBA8)
		image.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
		# Fill hidden RGB from neighbouring plant pixels to avoid coloured/black
		# fringes under linear filtering; alpha and visible cutout are retained.
		image.fix_alpha_edges()
		var relative: String = "textures/" + str(name) + ".png"
		if image.save_png(output.path_join(relative)) != OK: fail("Could not save " + str(name)); return
		provenance.textures[name].output_size = [1024, 1024]
		provenance.textures[name].output_sha256 = FileAccess.get_sha256(output.path_join(relative))
		manifest.assets["texture." + str(name)] = {"file": relative, "terrain_mipmaps": true}
	if not write_json(output.path_join("sources.json"), provenance): return
	if not write_json(output.path_join("mod.json"), manifest): return
	print("Built detailed plant texture pack: five 1024x1024 RGBA cutouts.")
	quit()

func write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: fail("Could not write " + path); return false
	file.store_string(JSON.stringify(data, "  ") + "\n")
	return true

func fail(message: String) -> void:
	push_error(message)
	quit(1)
