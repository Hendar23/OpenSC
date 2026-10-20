extends SceneTree
## Run with --headless --path godot --script ../tools/build_upscaled_map_textures.gd
## -- <original-game-folder> <new-output-folder> [4|8]. Requires the original game.

const Assets = preload("res://clump_loader.gd")
const BMP = preload("res://legacy_bmp.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 3:
		fail("Expected original game folder, a new mod output folder, and optional scale (4 or 8)."); return
	if args.size() == 3 and args[2] not in ["4", "8"]:
		fail("Scale must be 4 or 8."); return
	var factor := int(args[2]) if args.size() == 3 else 4
	var source := args[0].replace("\\", "/")
	var output := args[1].replace("\\", "/")
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output):
		fail("Output already exists; choose a new folder to preserve existing work."); return
	var world := source.path_join("DATA/SCEN1.BSP")
	var data := FileAccess.get_file_as_bytes(world)
	if not Assets._has_tag(data, 0, "dlrw"):
		fail("Cannot read the original SCEN1.BSP world."); return
	var material_end := -1
	for offset in range(60, data.size() - 16, 4):
		if Assets._has_tag(data, offset, "nalp") and Assets._has_tag(data, offset + 8, "trts"):
			material_end = offset; break
	if material_end < 0:
		fail("World material table not found."); return
	var references := Assets._material_references(data, 60, material_end)
	if references.size() != int(data.decode_u32(68)):
		fail("World material count mismatch."); return
	var images := {}
	var sources := {}
	for ref in references:
		var name := str(ref.texture).to_lower()
		if name.is_empty() or images.has(name): continue
		if not name.is_valid_filename() or not str(ref.mask).is_empty():
			fail("Unsupported texture name or masked world material: " + name); return
		var path := source.path_join("GAMETEX/" + name.to_upper() + ".BMP")
		var image := BMP._load_image(path)
		if image == null:
			path = source.path_join("GAMETEX/" + name.to_upper() + ".RAS")
			image = BMP._load_image(path)
		if image == null or image.is_empty():
			fail("Cannot decode original texture: " + name); return
		images[name] = image
		sources[name] = {"file": "GAMETEX/" + path.get_file(), "sha256": FileAccess.get_sha256(path), "original_size": [image.get_width(), image.get_height()]}
	if images.is_empty():
		fail("No world textures found."); return
	if DirAccess.make_dir_recursive_absolute(output.path_join("textures")) != OK:
		fail("Cannot create mod folder."); return
	var assets := {}
	var names := images.keys(); names.sort()
	for name in names:
		var image: Image = images[name]
		var width := image.get_width()
		var height := image.get_height()
		# Sample across repeat boundaries instead of clamping Lanczos at the edge.
		# Crop the middle tile after resizing so no padding enters the actual UVs.
		image.convert(Image.FORMAT_RGB8)
		var tiled := Image.create(width * 3, height * 3, false, image.get_format())
		for y in range(3):
			for x in range(3): tiled.blit_rect(image, Rect2i(0, 0, width, height), Vector2i(x * width, y * height))
		tiled.resize(width * 3 * factor, height * 3 * factor, Image.INTERPOLATE_LANCZOS)
		var upscaled := tiled.get_region(Rect2i(width * factor, height * factor, width * factor, height * factor))
		var relative := "textures/" + str(name) + ".png"
		if upscaled.save_png(output.path_join(relative)) != OK:
			fail("Cannot save " + relative); return
		assets["texture." + str(name)] = {"file": relative}
		sources[name]["output_sha256"] = FileAccess.get_sha256(output.path_join(relative))
	var manifest := {"schema_version": 1, "id": "upscaled-map-textures", "name": "Upscaled Map Textures (%dx)" % factor, "version": "1.1.0" if factor == 8 else "1.0.0", "description": "%dx upscales of the original world textures: seabed, rocks, caves and static map structures. Preserves original artwork using repeat-aware Lanczos resampling." % factor, "assets": assets}
	if not write_json(output.path_join("sources.json"), {"world_sha256": FileAccess.get_sha256(world), "factor": factor, "method": "3x3 periodic padding, Lanczos resize, center crop; no generated detail", "textures": sources}): return
	# Write the manifest last, so incomplete builds are not discovered as mods.
	if not write_json(output.path_join("mod.json"), manifest): return
	print("Built ", assets.size(), " original world texture replacements at ", factor, "x: ", output)
	quit()

func write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		fail("Cannot write " + path); return false
	file.store_string(JSON.stringify(value, "  ") + "\n")
	return true

func fail(message: String) -> void:
	push_error(message)
	quit(1)
