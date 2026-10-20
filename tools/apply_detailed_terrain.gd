extends SceneTree
## Import approved/generated terrain PNGs into an existing upscaled texture pack.
## -- <generated-image-folder> <existing-pack-folder>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		fail("Expected generated image folder and existing texture pack folder."); return
	var input := args[0].replace("\\", "/").simplify_path()
	var output := args[1].replace("\\", "/").simplify_path()
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("mod.json")))
	var provenance: Variant = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("sources.json")))
	if not manifest is Dictionary or not provenance is Dictionary or manifest.get("id", "") != "upscaled-map-textures" or int(provenance.get("factor", 0)) != 8:
		fail("Expected the existing 8x map texture pack."); return
	var images := {}
	for file in DirAccess.get_files_at(input):
		if file.get_extension().to_lower() != "png": continue
		var name := file.get_basename()
		var id := "texture." + name
		if not provenance.textures.has(name) or not manifest.assets.has(id):
			fail("Generated texture has no original world asset: " + name); return
		var target := str(manifest.assets[id].file).replace("\\", "/")
		if target != "textures/" + name + ".png":
			fail("Unexpected target path: " + target); return
		var image := Image.load_from_file(input.path_join(file))
		if image == null or image.is_empty() or image.get_width() != image.get_height() or image.get_width() < 1024:
			fail("Expected square generated texture at least 1024px: " + name); return
		images[name] = image
	if images.is_empty(): fail("No generated terrain PNGs found."); return
	for name in provenance.textures:
		if not provenance.textures[name].has("method"):
			provenance.textures[name].method = "repeat-aware Lanczos interpolation"
	for name in images:
		manifest.assets["texture." + str(name)].terrain_mipmaps = true
		var source := input.path_join(str(name) + ".png")
		var generated_hash := FileAccess.get_sha256(source)
		var target := output.path_join("textures/" + str(name) + ".png")
		var entry: Dictionary = provenance.textures[name]
		if entry.get("generated_sha256", "") == generated_hash and entry.get("output_sha256", "") == FileAccess.get_sha256(target): continue
		var image: Image = images[name]
		entry.generated_size = [image.get_width(), image.get_height()]
		image.convert(Image.FORMAT_RGB8)
		# Normalize generated deliverables to the pack's exact 8x dimensions.
		image.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
		var temporary := target + ".tmp.png"
		if image.save_png(temporary) != OK or DirAccess.rename_absolute(temporary, target) != OK:
			fail("Could not install texture: " + str(name)); return
		entry.generated_sha256 = generated_hash
		entry.output_sha256 = FileAccess.get_sha256(target)
		entry.method = "AI detail reconstruction; normalized to 1024x1024"
		entry.generator = "built-in image_gen"
		var prompt := input.path_join(str(name) + ".prompt.txt")
		if FileAccess.file_exists(prompt): entry.prompt = FileAccess.get_file_as_string(prompt).strip_edges()
	var enhanced := 0
	for entry in provenance.textures.values():
		if entry.has("generated_sha256"): enhanced += 1
	provenance.method = "AI detail reconstruction for marked textures; repeat-aware Lanczos interpolation for remaining textures"
	provenance.enhanced_texture_count = enhanced
	provenance.terrain_sampling = "Opt-in linear mipmap anisotropic filtering for reconstructed terrain"
	manifest.name = "Detailed Map Textures (8x)"
	manifest.version = "2.0.0"
	manifest.description = "8x original world textures with reconstructed stone, sand and seabed detail. %d terrain textures enhanced with AI; remaining world textures use faithful interpolation." % enhanced
	if not write_json(output.path_join("sources.json"), provenance): return
	if not write_json(output.path_join("mod.json"), manifest): return
	print("Installed detail reconstruction: ", enhanced, " textures; original pack ID retained.")
	quit()

func write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: fail("Could not write " + path); return false
	file.store_string(JSON.stringify(value, "  ") + "\n")
	return true

func fail(message: String) -> void:
	push_error(message)
	quit(1)
