extends SceneTree
const Mods = preload("res://mod_registry.gd")
const Assets = preload("res://clump_loader.gd")
const Movement = preload("res://movement_model.gd")
const Paths = preload("res://asset_paths.gd")
const Game = preload("res://game.gd")
const Modern = preload("res://modern_model.gd")
var checks := 0
var failures := 0
var temporary_files: Array[String] = []
var fixture_root := "res://tests/mod-fixtures"

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error("FAIL: " + message)
func write(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
	temporary_files.append(path)
func pack(id: String, manifest: Dictionary) -> void:
	manifest.schema_version = manifest.get("schema_version", 1)
	manifest.id = id
	manifest.name = id
	write(fixture_root.path_join(id).path_join("mod.json"), JSON.stringify(manifest))
func bound_textures(model: Node3D) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		for surface in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(surface)
			if material is BaseMaterial3D and material.albedo_texture != null and material.albedo_texture.has_meta("asset_mod"):
				result.append(material.albedo_texture)
	return result
func _run() -> void:
	var folder := Paths.find_game_folder()
	pack("first", {"movement": {"mass": 150.0}, "assets": {"texture.sub1": "skin.png"}})
	pack("second", {"movement": {"mass": 180.0, "forward_speed": 8.0}, "assets": {"texture.sub1": "skin.png", "model.sub": {"file": "submarine.glb", "forward_axis": "+Z", "scale": 0.5, "material_textures": {"2": "texture.sub1", "4": "texture.sub1", "5": "texture.sub1"}}}})
	pack("broken-model", {"assets": {"submarine.player": "broken.glb"}})
	write(fixture_root.path_join("broken-model/broken.glb"), "not a GLB")
	pack("invalid", {"schema_version": 999, "movement": {"mass": -1}, "assets": {"texture.sub1": "../../outside.png"}})
	write(fixture_root.path_join("unreadable/mod.json"), "not json")
	for item in [["first", Color.RED], ["second", Color.BLUE]]:
		var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(item[1])
		var path := fixture_root.path_join(item[0]).path_join("skin.png")
		image.save_png(ProjectSettings.globalize_path(path))
		temporary_files.append(path)
	var glb_path := fixture_root.path_join("second/submarine.glb")
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://../Mods/example-glb-submarine/models/submarine.glb"), ProjectSettings.globalize_path(glb_path))
	temporary_files.append(glb_path)
	var preference := "res://tests/mod-preferences-test.cfg"
	Mods.initialize(false, fixture_root, preference)
	check(Mods.packs.size() == 5 and Mods.active_ids().is_empty(), "Mods are discovered and disabled by default")
	check(Mods.packs.filter(func(p: Dictionary) -> bool: return not p.valid).size() == 2, "Bad JSON and unsupported schema are reported without loading")
	check(Mods.packs.filter(func(p: Dictionary) -> bool: return p.id == "invalid")[0].assets.is_empty(), "Paths outside a mod folder are rejected")
	var base := Movement.new()
	base.load_settings(false)
	var base_settings: Dictionary = base.settings.duplicate()
	var base_path: String = base.persistence_path
	Mods.apply(["first", "second"], ["first", "second", "broken-model", "invalid", "unreadable"], true)
	temporary_files.append(preference)
	check(Mods.movement.mass == 180 and Mods.movement.forward_speed == 8, "Later partial presets win conflicts")
	check(Mods.conflicts.size() == 2, "Movement and asset conflicts are reported")
	check(Mods.candidates("submarine.player").size() == 1 and Mods.candidates("model.sub").size() == 1, "Stable submarine ID and legacy alias resolve the same asset")
	var texture := Assets._load_texture(folder, "SUB1", "", {})
	check(texture.get_image().get_pixel(0, 0).is_equal_approx(Color.BLUE), "PNG replacement wins over original BMP")
	var modern := Assets.load_submarine(folder.path_join("CLUMPS/SUB.DFF"))
	check(modern != null and modern.get_meta("modern_model", false) and modern.scale.is_equal_approx(Vector3.ONE * 0.5), "GLB replacement loads with configured model scale")
	if modern != null:
		var bound := bound_textures(modern)
		check(bound.size() == 3 and bound.all(func(t: Texture2D) -> bool: return t.get_image().get_pixel(0, 0).is_equal_approx(Color.BLUE)), "GLB material bindings use the highest-priority PNG on all hull parts")
	if modern != null: modern.free()
	var edited := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	edited.fill(Color.GREEN)
	edited.save_png(ProjectSettings.globalize_path(fixture_root.path_join("second/skin.png")))
	Mods.apply(Mods.enabled, Mods.order, false)
	modern = Assets.load_submarine(folder.path_join("CLUMPS/SUB.DFF"))
	check(modern != null and bound_textures(modern).all(func(t: Texture2D) -> bool: return t.get_image().get_pixel(0, 0).is_equal_approx(Color.GREEN)), "Reapplying after a PNG edit reloads current pixels into GLB materials")
	if modern != null: modern.free()
	var modded := Movement.new()
	modded.load_settings(false)
	check(modded.settings.mass == 180 and modded.settings.forward_speed == 8, "Movement model uses enabled partial presets")
	check(is_equal_approx(modded.settings.turn_drag, base_settings.turn_drag), "Unspecified movement values inherit base tuning")
	check(modded.persistence_path != base_path and modded.persistence_path.begins_with("user://movement-mod-"), "Modded tuning has a separate saved profile")
	var base_bytes := FileAccess.get_file_as_bytes(base_path) if FileAccess.file_exists(base_path) else PackedByteArray()
	var export_path := "res://tests/mod-movement-test.cfg"
	modded.save_settings(export_path)
	temporary_files.append(export_path)
	var saved := ConfigFile.new()
	saved.load(export_path)
	check(saved.get_value("movement", "mass") == 180 and saved.get_value("movement", "physics_version") == 2, "Modded movement exports effective settings in the current format")
	var current_base := FileAccess.get_file_as_bytes(base_path) if FileAccess.file_exists(base_path) else PackedByteArray()
	check(current_base == base_bytes, "Exporting modded tuning leaves base saved tuning untouched")
	Mods.initialize(true, fixture_root, preference)
	check(Mods.active_ids() == ["first", "second"], "Enabled mods and priority persist across reload")
	Mods.apply(["first", "second", "broken-model"], ["first", "second", "broken-model", "invalid", "unreadable"], false)
	modern = Assets.load_submarine(folder.path_join("CLUMPS/SUB.DFF"))
	check(modern != null and modern.get_meta("asset_mod") == "second" and not Mods.runtime_warnings.is_empty(), "Broken highest-priority model falls back to the next valid replacement")
	if modern != null: modern.free()
	Mods.apply(["first"], ["second", "first", "broken-model", "invalid", "unreadable"], false)
	texture = Assets._load_texture(folder, "SUB1", "", {})
	check(texture.get_image().get_pixel(0, 0).is_equal_approx(Color.RED), "Changing enabled packs changes texture priority")
	Mods.apply([], Mods.order, false)
	modern = Modern.load_model(ProjectSettings.globalize_path(glb_path), {"forward_axis": "+Z", "material_textures": {"2": "texture.sub1"}})
	check(modern != null and bound_textures(modern).is_empty(), "Disabling PNG overrides preserves embedded GLB textures")
	if modern != null: modern.free()
	var restored := Movement.new()
	restored.load_settings(false)
	check(restored.settings == base_settings and restored.persistence_path == base_path, "Disabling mods restores base movement and its original save profile")
	var original := Assets.load_submarine(folder.path_join("CLUMPS/SUB.DFF"))
	check(original != null and not original.get_meta("modern_model", false), "Disabling mods restores original model")
	if original != null: original.free()
	Mods.initialize(false)
	Mods.apply(["example.glb-submarine", "example.png-texture", "example.heavier-movement"], Mods.order, false)
	var game := Game.new()
	game.remember_preferences = false
	root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete and game.pilot != null, "Game launches with GLB, PNG and movement examples enabled")
	if game.pilot != null:
		check(game.pilot.visual.get_meta("modern_model", false) and game.pilot.visual.get_meta("submarine_parts", {}).size() == 5, "Modern submarine supplies all moving-part attachments")
		var current_png := Image.load_from_file(ProjectSettings.globalize_path("res://../Mods/example-png-texture/textures/sub1.png"))
		current_png.convert(Image.FORMAT_RGBA8)
		var current_textures := bound_textures(game.pilot.visual)
		check(current_textures.size() == 3 and current_textures.all(func(t: Texture2D) -> bool:
			var image := t.get_image()
			image.convert(Image.FORMAT_RGBA8)
			return image.get_data() == current_png.get_data()
		), "Actual game hull uses the user's current PNG with both example mods enabled")
		check(game.pilot.movement.settings.mass == 125 and game.docking.ports.size() == 6, "Movement preset and docking remain functional with modern model")
		var parts: Dictionary = game.pilot.visual.get_meta("submarine_parts")
		var pod: Node3D = game.pilot.visual.get_node(parts.left_pod)
		var rest := pod.basis
		game.pilot.movement.tilt = PI / 4
		game.pilot._update_animation(0.1)
		check(not pod.basis.is_equal_approx(rest), "GLB side pods animate through mapped attachment points")
		game.front_end.buttons.mods.pressed.emit()
		check(game.mod_panel.visible and not game.mod_panel.embedded and game.mod_panel.choices.has("example.glb-submarine") and game.mod_panel.choices.has("test.remastered-submarine"), "Main-menu Mods lists installed examples and remastered submarine")
		for checkbox in game.mod_panel.choices.values(): checkbox.button_pressed = false
		game.mod_panel._apply()
		for frame in range(1200):
			if not game.world_loading: break
			await physics_frame
		check(not game.pilot.visual.get_meta("modern_model", false) and game.pilot.movement.settings.mass == base_settings.mass, "Applying no mods reloads the original ship and base tuning")
	game.queue_free()
	await process_frame
	Mods.initialize(false)
	for path in temporary_files: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for child in ["first", "second", "broken-model", "invalid", "unreadable"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_root.path_join(child)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_root))
	print("Mod verification: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
