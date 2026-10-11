extends SceneTree
const Game = preload("res://game.gd")
const Scenery = preload("res://scenery_loader.gd")
const Searchlight = preload("res://searchlight.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func snapshot(viewport: SubViewport) -> Image:
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func run() -> void:
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete, "Game starts with restored searchlights")
	if not game.startup_complete: quit(1); return
	var beams: Array[Node] = []
	for node in game.world_root.get_node("Scenery").get_children():
		if node is Searchlight: beams.append(node)
	check(beams.size() == 10, "Exactly ten startup building searchlights; mission beams remain dormant")
	var folder := preload("res://asset_paths.gd").find_game_folder()
	var tables := Scenery.read_database(folder.path_join("DATA/SCEN1.DDB"))
	for beam in beams:
		var index := int(str(beam.name).get_slice("_", 1))
		var expected := Scenery.placement(tables.Objects[index], game.world_root.get_meta("database_offset"))
		check(beam.transform.is_equal_approx(expected), "Searchlight retains authored placement and orientation")
		beam.set_process(false)
		beam.angle = 0; beam.direction = 1
		beam._process(3.0)
		check(is_equal_approx(beam.angle, 45), "Searchlight reaches its recovered sweep limit")
		beam._process(3.0)
		check(is_zero_approx(beam.angle) and beam.direction == -1, "Searchlight reverses smoothly")
		beam._process(500)
		check(absf(beam.angle) <= 45, "Long frames cannot overshoot the sweep")
		check(beam.can_process() != paused, "Searchlights inherit world pause")
	check(game.equipment.lamp.shadow_enabled, "Installed headlight enables shadow occlusion")
	if DisplayServer.get_name() != "headless":
		game.front_end.menu_layer.hide(); game.menu_backdrop.close(); game.set_process(false)
		game.day_night.hour = 0; game.day_night.enabled = false; game._update_daylight()
		var beam: Node3D = beams[0]
		beam.angle = 0; beam._process(0)
		game.camera.global_position = beam.to_global(Vector3(3, 1, 1))
		game.camera.look_at(beam.to_global(Vector3(0, 0, 1)))
		for frame in range(5): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/searchlight-world.png")
		await verify_beam_render()
		await verify_occlusion(game)
	game.queue_free(); await process_frame
	print("Searchlights and headlight: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func light_sum(image: Image) -> float:
	var total := 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()): total += image.get_pixel(x, y).v
	return total
func verify_beam_render() -> void:
	var viewport := SubViewport.new(); viewport.size = Vector2i(256, 256); viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color.BLACK; viewport.add_child(environment)
	var beam := Searchlight.new(); viewport.add_child(beam); beam.configure("", {}); beam.set_process(false); beam.set_daylight(0)
	var camera := Camera3D.new(); viewport.add_child(camera); camera.position = Vector3(3, 0, 1); camera.look_at(Vector3(0, 0, 1)); camera.current = true
	var night := await snapshot(viewport); night.save_png("res://tests/searchlight-soft-night.png")
	beam.set_daylight(1)
	var day := await snapshot(viewport); day.save_png("res://tests/searchlight-soft-day.png")
	check(light_sum(night) > 100 and light_sum(day) < light_sum(night) * 0.65, "Rendered searchlight visibly dims during daylight")
	beam.set_daylight(0)
	var wall := MeshInstance3D.new(); wall.mesh = QuadMesh.new(); wall.mesh.size = Vector2(4,4); wall.rotation.y = PI * 0.5; wall.position = Vector3(1,0,1)
	var black := StandardMaterial3D.new(); black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; black.albedo_color = Color.BLACK; wall.material_override = black; viewport.add_child(wall)
	var blocked := await snapshot(viewport)
	check(light_sum(blocked) < light_sum(night) * 0.05, "Soft beam is hidden behind solid scenery")
	viewport.queue_free(); await process_frame
func verify_occlusion(game: Node3D) -> void:
	paused = false
	var viewport := SubViewport.new(); viewport.size = Vector2i(512, 512); viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var world := Node3D.new(); viewport.add_child(world)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color.BLACK; environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_energy = 0; world.add_child(environment)
	var wall := MeshInstance3D.new(); wall.mesh = QuadMesh.new(); wall.mesh.size = Vector2(8, 8); wall.position.z = -2; world.add_child(wall)
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color.WHITE; wall.material_override = mat
	# Exercise the game's real receiver shader as well as the installed lamp.
	game.natural_light.attach(world)
	var blocker := MeshInstance3D.new(); blocker.mesh = BoxMesh.new(); blocker.mesh.size = Vector3(1.2, 1.2, 0.2); world.add_child(blocker)
	var lamp: SpotLight3D = game.equipment.lamp
	# Keep the real housing and hull around the lamp to catch self-occlusion.
	game.pilot.set_physics_process(false); game.pilot.freeze = true
	game.pilot.reparent(world)
	game.pilot.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0, 3)) * lamp.global_transform.affine_inverse() * game.pilot.global_transform
	lamp.visible = true
	var camera := Camera3D.new(); world.add_child(camera); camera.position = Vector3(3, 2, 3); camera.look_at(Vector3(0, 0, -2)); camera.current = true
	var pixel := Vector2i(camera.unproject_position(Vector3(0, 0, -2)))
	var shadowed := await snapshot(viewport); shadowed.save_png("res://tests/headlight-occluded.png")
	lamp.shadow_enabled = false
	var leaking := await snapshot(viewport); leaking.save_png("res://tests/headlight-unoccluded.png")
	print("Headlight receiver: shadowed=", shadowed.get_pixelv(pixel).v, " unoccluded=", leaking.get_pixelv(pixel).v)
	check(leaking.get_pixelv(pixel).v - shadowed.get_pixelv(pixel).v > 0.2, "A solid wall prevents headlight illumination behind it")
	blocker.hide(); lamp.shadow_enabled = true
	var open := await snapshot(viewport)
	check(open.get_pixelv(pixel).v - shadowed.get_pixelv(pixel).v > 0.2, "Removing the obstruction restores the beam")
	# A steep receiver must not shadow itself into stripes. Isolate the lamp
	# from the hull, and compare against the same surface without shadows.
	var lamp_parent := lamp.get_parent()
	lamp.reparent(world)
	# Legacy terrain can have lighting normals almost tangent to the faces.
	# Normal bias alone then barely separates a face from its own shadow map.
	var arrays := wall.mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index in normals.size(): normals[index] = Vector3(-1,0,0.01).normalized()
	arrays[Mesh.ARRAY_NORMAL] = normals
	var smooth_mesh := ArrayMesh.new(); smooth_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	wall.mesh = smooth_mesh
	camera.position = Vector3(0, 0, 6); camera.look_at(Vector3(0, 0, -2))
	# Player graphics uses 1024 for Low, 2048 for Medium and 4096 for High.
	for atlas in [1024,2048]:
		viewport.positional_shadow_atlas_size = atlas
		for distance in [5.0,10.0,16.0]:
			lamp.spot_range = 18; lamp.light_energy = 6; lamp.spot_angle = 45
			wall.position.z = lamp.global_position.z - distance
			camera.position = wall.position + Vector3(0,0,6); camera.look_at(wall.position)
			for angle in [60,80]:
				wall.rotation.y = deg_to_rad(angle)
				lamp.shadow_enabled = true
				var sloped := await snapshot(viewport)
				sloped.save_png("res://tests/headlight-steep-%d-%d-%d.png" % [atlas,distance,angle])
				lamp.shadow_enabled = false
				var reference := await snapshot(viewport)
				var lit_pixels := 0
				var acne_pixels := 0
				for y in range(512):
					for x in range(512):
						var expected := reference.get_pixel(x, y).v
						if expected > 0.15:
							lit_pixels += 1
							if expected - sloped.get_pixel(x, y).v > 0.06: acne_pixels += 1
				print("Headlight atlas=",atlas," distance=",distance," slope=",angle,": ",acne_pixels," / ",lit_pixels)
				check(lit_pixels > 200 and acne_pixels < lit_pixels * 0.01, "Steep receivers stay free of stripes at atlas %d distance %d slope %d" % [atlas,distance,angle])
	lamp.shadow_enabled = true
	lamp.reparent(lamp_parent)
	game.pilot.reparent(game)
	viewport.queue_free(); await process_frame
