extends "res://tests/test_scene_tree.gd"
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	preload("res://mod_registry.gd").initialize(false)
	call_deferred("run")
func run() -> void:
	var loader := preload("res://clump_loader.gd")
	var natural := preload("res://natural_light.gd").new()
	var water := preload("res://water_visuals.gd").new()
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	for id in ["SUB","PIRATE","PRISON","TECH2SUB","TECHHERD","TECHNEW","TECHSHUT","TECHTRUK","TRAD-SUB","TRAD2","FREIGHT","TRADSHUT","ELECTRO","TIN"]:
		var path := folder.path_join("CLUMPS/"+id+".DFF")
		if not FileAccess.file_exists(path): continue
		var model: Node3D = loader.load_clump(path); root.add_child(model)
		var glass := 0
		var painted: Array[Dictionary] = []
		for node in model.find_children("*","MeshInstance3D",true,false):
			for index in range(node.mesh.get_surface_count()):
				var original: StandardMaterial3D = node.get_active_material(index)
				if original.get_meta("exterior_canopy",false):
					glass += 1
					check(node.layers == 1 << 17,"Glass stays out of reflection capture: "+id)
				else: painted.append({"node":node,"index":index,"texture":original.albedo_texture,"color":original.albedo_color})
		check(glass > 0 if id not in ["FREIGHT","TRADSHUT","ELECTRO","TIN"] else glass == 0,"Only actual blue glazing is classified: "+id)
		water.attach(model); natural.attach(model)
		for node in model.find_children("*","MeshInstance3D",true,false):
			for index in range(node.mesh.get_surface_count()):
				var material: ShaderMaterial = node.get_active_material(index)
				if material.get_meta("natural_original").get_meta("exterior_canopy",false):
					check(material.shader == preload("res://exterior_canopy.gdshader") and material.get_shader_parameter("roughness_value") < 0.2,"Glossy canopy survives lighting/caustic wrappers: "+id)
		for entry in painted:
			var material: ShaderMaterial = entry.node.get_active_material(entry.index)
			check(material.get_shader_parameter("albedo_texture") == entry.texture and material.get_shader_parameter("albedo_color") == entry.color,"Hull texture/colour preserved: "+id)
		model.free()
	var world := Node3D.new(); root.add_child(world)
	var capture := preload("res://exterior_reflections.gd").new(); world.add_child(capture); capture.setup(world.get_world_3d())
	check(capture.views.is_empty(),"Headless checks do not allocate GPU capture viewports")
	world.free()
	print("Exterior canopies: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
