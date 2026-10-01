extends SceneTree
const Assets = preload("res://clump_loader.gd")
const Paths = preload("res://asset_paths.gd")
const BMP = preload("res://legacy_bmp.gd")
const Modern = preload("res://modern_model.gd")
func _initialize() -> void:
	var folder := Paths.find_game_folder()
	var png_path := ProjectSettings.globalize_path("res://../Mods/example-png-texture/textures")
	var glb_folder := ProjectSettings.globalize_path("res://../Mods/example-glb-submarine/models")
	DirAccess.make_dir_recursive_absolute(png_path)
	DirAccess.make_dir_recursive_absolute(glb_folder)
	var image := BMP.load_image(folder.path_join("GAMETEX/SUB1.BMP"))
	if image == null or image.save_png(png_path.path_join("sub1.png")) != OK: quit(1); return
	var model := Assets._load_legacy(folder.path_join("CLUMPS/SUB.DFF"), PackedStringArray(["Hull", "RearPropeller", "LeftPod", "RightPod", "RightPropeller", "LeftPropeller"]))
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var path := glb_folder.path_join("submarine.glb")
	if document.append_from_scene(model, state) != OK or document.write_to_filesystem(state, path) != OK:
		model.free(); quit(1); return
	model.free()
	var imported := Modern.load_model(path, {"forward_axis": "+Z"})
	if imported == null: quit(1); return
	var parts := {}
	for entry in [["left_pod", "RightPod"], ["right_pod", "LeftPod"], ["main_propeller", "RearPropeller"], ["left_propeller", "RightPropeller"], ["right_propeller", "LeftPropeller"]]:
		var node := imported.find_child(entry[1], true, false)
		if node == null: imported.free(); quit(1); return
		parts[entry[0]] = str(imported.get_path_to(node))
	imported.free()
	var manifest := {"schema_version": 1, "id": "example.glb-submarine", "name": "Example: GLB submarine", "version": "1.0", "description": "All six original submarine parts converted into a self-contained GLB. Same appearance, modern model format, working propellers. Disabled until enabled.", "assets": {"submarine.player": {"file": "models/submarine.glb", "scale": 1.0, "forward_axis": "+Z", "parts": parts, "material_textures": {"2": "texture.sub1", "4": "texture.sub1", "5": "texture.sub1"}}}}
	var file := FileAccess.open(glb_folder.get_base_dir().path_join("mod.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	print("Example mod assets built. GLB attachment paths: ", parts)
	quit()
