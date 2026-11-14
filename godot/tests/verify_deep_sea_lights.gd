extends "res://tests/test_scene_tree.gd"
const Equipment = preload("res://submarine_equipment.gd")
const Pilot = preload("res://submarine_controller.gd")
const Assets = preload("res://clump_loader.gd")
const NaturalLight = preload("res://natural_light.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	preload("res://player_storage.gd").root_override = "res://tests/cache-deep-lights-fixtures"
	preload("res://mod_registry.gd").initialize(false,"res://tests/cache-deep-lights-fixtures/Mods")
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func snapshot(viewport: SubViewport) -> Image:
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func brightness(image: Image) -> float:
	var total := 0.0
	for y in image.get_height():
		for x in image.get_width(): total += image.get_pixel(x,y).v
	return total
func run() -> void:
	var folder := OS.get_environment("OPENSC_TEST_GAME_FOLDER")
	var viewport := SubViewport.new(); viewport.size = Vector2i(640,480); viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = 0.0; viewport.add_child(environment)
	var pilot := Pilot.new(); viewport.add_child(pilot); pilot.set_physics_process(false)
	pilot.visual = Assets.load_submarine(folder.path_join("CLUMPS/SUB.DFF"))
	pilot.visual.rotation.y = PI; pilot.add_child(pilot.visual)
	var equipment := Equipment.new(); pilot.add_child(equipment); equipment.setup(pilot,folder)
	equipment.settings.light_range = 12.0; equipment.settings.light_angle = 22.0; equipment.settings.light_down_angle = 19.0
	# Match gameplay's material pass order, including the water/caustics pass.
	var water := preload("res://water_visuals.gd").new(); water.attach(pilot)
	var natural := NaturalLight.new(); natural.attach(pilot)
	check(not equipment.bulb_materials.is_empty(),"Original lamp has a separate bulb material")
	check(not equipment.lamp.visible and not equipment.bulb_materials[0].emission_enabled,"Bulb and beam start switched off")
	equipment.toggle_selected()
	check(equipment.lamp.visible and equipment.light_shaft.is_visible_in_tree(),"Switching on reveals the shaft with the spotlight")
	check(equipment.bulb_materials[0].emission_enabled,"Bulb lights up after cave-light receivers are attached")
	check(equipment.bulb_lenses.size() == 1 and equipment.bulb_lenses[0].is_visible_in_tree(),"Powered lamp fills its recessed face with a luminous lens")
	var active_bulb := false
	for mesh in pilot.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			if mesh.get_active_material(surface) == equipment.bulb_materials[0]: active_bulb = true
	check(active_bulb,"The glowing material is the rendered bulb, not a discarded receiver material")
	check(equipment.light_shaft.to_global(Vector3(0,0,-6)).is_equal_approx(equipment.lamp.global_position),"Shaft starts at the light rather than behind the submarine")
	check(equipment.light_shaft.to_global(Vector3(0,0,6)).is_equal_approx(equipment.lamp.to_global(Vector3(0,0,-12))),"Shaft follows the real beam direction and range")
	if DisplayServer.get_name() != "headless":
		var camera := Camera3D.new(); viewport.add_child(camera); camera.current = true
		camera.global_position = equipment.lamp.to_global(Vector3(5,2,-1))
		camera.look_at(equipment.lamp.to_global(Vector3(0,0,-5)))
		var lit := await snapshot(viewport); lit.save_png("res://tests/deep-sea-shaft.png")
		equipment.light_shaft.hide()
		var without := await snapshot(viewport)
		check(brightness(lit) > brightness(without) + 100.0,"The shaft is visible in dark water")
		equipment.light_shaft.show()
		camera.global_position = equipment.lamp.to_global(Vector3(0.3,0.12,-0.5))
		camera.look_at(equipment.lamp.global_position)
		var bulb := await snapshot(viewport); bulb.save_png("res://tests/deep-sea-bulb.png")
		var lens: MeshInstance3D = equipment.bulb_lenses[0]
		var centre := lens.to_global(lens.mesh.get_aabb().get_center())
		var pixel := Vector2i(camera.unproject_position(centre))
		var colour := bulb.get_pixelv(pixel)
		check(minf(colour.r,minf(colour.g,colour.b)) > 0.98,"Actual rendered lens centre is pure white after all gameplay material passes")
	equipment.toggle_selected()
	check(not equipment.light_shaft.is_visible_in_tree() and not equipment.bulb_materials[0].emission_enabled,"Switching off removes both glow and shaft")
	check(not equipment.bulb_lenses[0].visible,"Switching off restores the original recessed reflector")
	equipment.toggle_selected(); equipment.set_installed(["suckomat"])
	check(not equipment.light_shaft.is_visible_in_tree(),"Uninstalling the lights hides the shaft")
	viewport.queue_free(); await process_frame
	print("Deep-sea lights: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
