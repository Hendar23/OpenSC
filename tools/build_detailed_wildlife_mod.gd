extends SceneTree
## Build a NEW wildlife texture pack from the original colour/mask inventory.
## -- <original-game-folder> <inventory.json> <generated-folder> <new-pack-folder>
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4: fail("Expected original game, inventory, generated folder and NEW output folder."); return
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not plan is Dictionary or not plan.get("textures") is Dictionary or plan.textures.size() != 38 or not plan.get("models") is Array or plan.models.size() != 33:
		fail("Expected the original 38-texture / 33-creature-model inventory."); return
	var output := args[3].replace("\\", "/").simplify_path()
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): fail("Output already exists; choose a new directory."); return
	var images := {}
	var sources := {}
	for name in plan.textures:
		for character in str(name):
			if not character in "abcdefghijklmnopqrstuvwxyz0123456789-": fail("Invalid texture name."); return
		var entry: Dictionary = plan.textures[name].duplicate(true)
		if not entry.get("source_files") is Dictionary or entry.source_files.is_empty() or not entry.get("original_size") is Array or entry.original_size.size() != 2 or int(entry.original_size[0]) != 128 or int(entry.original_size[1]) != 128:
			fail("Incomplete original source identity: " + str(name)); return
		for relative in entry.source_files:
			if not str(relative).begins_with("GAMETEX/") or ".." in str(relative) or FileAccess.get_sha256(args[0].path_join(str(relative))) != str(entry.source_files[relative]):
				fail("Original colour/mask checksum mismatch: " + str(relative)); return
		var path := args[2].path_join(str(name)+".png")
		var image := Image.load_from_file(path)
		if image == null or image.is_empty() or image.get_width() < 1024 or image.get_width() != image.get_height():
			fail("Missing or incorrectly shaped generation: " + str(name)); return
		if not str(entry.get("mask", "")).is_empty():
			if image.detect_alpha() == Image.ALPHA_NONE: fail("Creature cutout lost alpha: " + str(name)); return
			var sample := image.duplicate() as Image; sample.resize(128,128,Image.INTERPOLATE_NEAREST)
			var clear := 0; var solid := 0
			for y in range(128):
				for x in range(128):
					if sample.get_pixel(x,y).a < 0.1: clear += 1
					if sample.get_pixel(x,y).a > 0.5: solid += 1
			if clear < 32 or solid < 100: fail("Creature cutout lost foreground or gaps: " + str(name)); return
		entry.generated_size = [image.get_width(),image.get_height()]
		entry.generated_sha256 = FileAccess.get_sha256(path)
		entry.prompt = FileAccess.get_file_as_string(args[2].path_join(str(name)+".prompt.txt")).strip_edges()
		if str(entry.prompt).is_empty(): fail("Missing exact prompt: " + str(name)); return
		entry.generator = "built-in image_gen"
		entry.method = "AI organic detail reconstruction, normalized to original atlas dimensions times eight"
		sources[name] = entry; images[name] = image
	if DirAccess.make_dir_recursive_absolute(output.path_join("textures")) != OK: fail("Could not create pack output."); return
	var manifest := {"schema_version":1,"id":"detailed-wildlife-textures","name":"Detailed Wildlife Textures (8x)","version":"1.0.0","description":"8x reconstructed original creature skins, fins, shells and wildlife scenery. Preserves original models and animation. Load after Detailed Map Textures (8x).","assets":{}}
	for name in images:
		var entry: Dictionary = sources[name]
		var image: Image = images[name]
		var masked := not str(entry.mask).is_empty()
		image.convert(Image.FORMAT_RGBA8 if masked else Image.FORMAT_RGB8)
		image.resize(1024,1024,Image.INTERPOLATE_LANCZOS)
		if masked: image.fix_alpha_edges()
		var relative := "textures/"+str(name)+".png"
		if image.save_png(output.path_join(relative)) != OK: fail("Could not save " + str(name)); return
		entry.output_size = [1024,1024]
		entry.output_sha256 = FileAccess.get_sha256(output.path_join(relative))
		manifest.assets["texture."+str(name)] = {"file":relative,"terrain_mipmaps":true}
	var provenance := {"factor":8,"models":plan.models,"unavailable":plan.get("unavailable",{}),"generator":"built-in image_gen","textures":sources}
	if not write_json(output.path_join("sources.json"),provenance): return
	if not write_json(output.path_join("mod.json"),manifest): return
	print("Built detailed wildlife pack: 38 1024x1024 creature/scenery atlases.")
	quit()

func write_json(path: String,data: Dictionary) -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: fail("Could not write "+path); return false
	file.store_string(JSON.stringify(data,"  ")+"\n"); return true
func fail(message: String) -> void:
	push_error(message); quit(1)
