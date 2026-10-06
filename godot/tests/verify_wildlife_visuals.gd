extends SceneTree
const Game = preload("res://game.gd")
const Document = preload("res://map_document.gd")
const Mods = preload("res://mod_registry.gd")
const Creatures = preload("res://creature_loader.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _run() -> void:
	Mods.initialize(false)
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	game.set_process(false); game.set_physics_process(false); game.pilot.freeze = true
	game.canvas.hide(); game.cockpit_hud.hide(); game.particles.hide()
	game.camera.cull_mask = 1; game.water_environment.fog_enabled = false; game.sun.shadow_enabled = false
	var pop: Node3D = game.wildlife; pop.streaming = false
	for species in pop.document.species: species.random_spawn = false
	var species: Dictionary = pop.document.species.filter(func(entry: Dictionary) -> bool: return entry.model == "CRAB")[0]
	var random := RandomNumberGenerator.new(); random.seed = 1234
	var home: Vector3 = pop._random_home(species,random)
	pop.document.groups = [{"id":"crab_visual_test","species":species.id,"position":Document.array(home),"chance":100.0,"count_min":1,"count_max":1,"radius":0.2}]
	pop.reroll(false)
	check(pop.get_child_count() == 1,"Piloting wildlife path creates the crab")
	if pop.get_child_count() == 0: game.queue_free(); await process_frame; quit(1); return
	var crab: Node3D = pop.get_child(0)
	crab.swim_speed = 0; crab.direction = Vector3.BACK; crab.goal = crab.position + Vector3.BACK * 10; crab.turn_timer = 100
	game.camera.position = crab.global_position + Vector3(0,1.0,1.0); game.camera.look_at(crab.global_position)
	var before: float = crab.animation_time
	for frame in range(30): await physics_frame
	check(crab.animation_time > before + 0.8 and crab.is_physics_processing() and crab.is_processing(),"Live piloting crab advances its walking animation")
	check(game.plant_current.plant_count > 0 and not game.plant_current.materials.is_empty(),"World plants receive sway materials")
	game.plant_controls.strength.value = 0.3; game.plant_controls.speed.value = 0.6; game.plant_controls.direction.value = 90; game.plant_controls.variation.value = 0.7
	check(game._view_settings().plants_strength == 0.3 and game._view_settings().plants_speed == 0.6 and game._view_settings().plants_direction == 90 and game._view_settings().plants_variation == 0.7,"Plant sliders are included in exported defaults")
	check(is_equal_approx(game.plant_current.materials[0].get_shader_parameter("sway_strength"),0.3),"Plant controls update world materials")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var first := root.get_texture().get_image()
		first.save_png("res://tests/piloting-crab-before.png")
		for frame in range(30): await physics_frame
		await RenderingServer.frame_post_draw
		var second := root.get_texture().get_image()
		second.save_png("res://tests/piloting-crab-after.png")
		var changed := 0
		var center := first.get_size() / 2
		for y in range(center.y - 100,center.y + 100):
			for x in range(center.x - 150,center.x + 150):
				if first.get_pixel(x,y) != second.get_pixel(x,y): changed += 1
		check(changed > 100,"Crab animation changes rendered pixels in the piloting world")
		print("Piloting crab changed pixels: ",changed)
		var plant := game.world_root.find_children("Plant_*","Node3D",true,false)[0] as Node3D
		var viewport := SubViewport.new(); viewport.size = Vector2i(400,400); viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
		var specimen := plant.duplicate() as Node3D; viewport.add_child(specimen); specimen.position = Vector3.ZERO
		var boxes: Array[AABB] = []; Creatures._collect_bounds(specimen,specimen.transform,boxes)
		var box := boxes[0]
		for next in boxes: box = box.merge(next)
		var camera := Camera3D.new(); viewport.add_child(camera); camera.position = box.get_center() + Vector3(0.8,0.3,1).normalized() * box.size.length() * 1.3; camera.look_at(box.get_center()); camera.current = true
		var light := DirectionalLight3D.new(); viewport.add_child(light); light.rotation_degrees = Vector3(-40,-20,0)
		for frame in range(6): await process_frame
		await RenderingServer.frame_post_draw
		first = viewport.get_texture().get_image(); first.save_png("res://tests/plant-sway-before.png")
		await create_timer(0.4).timeout; await RenderingServer.frame_post_draw
		second = viewport.get_texture().get_image(); second.save_png("res://tests/plant-sway-after.png")
		changed = 0
		for y in range(400):
			for x in range(400):
				if first.get_pixel(x,y) != second.get_pixel(x,y): changed += 1
		check(changed > 100,"Plant current visibly bends the rendered plant")
		print("Plant sway changed pixels: ",changed)
		game.plant_current.configure({"strength":0.0})
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		first = viewport.get_texture().get_image()
		var mesh := specimen.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
		var patch: Dictionary = game.plant_current.patches.filter(func(entry: Dictionary) -> bool: return entry.materials.has(mesh.get_active_material(0)))[0]
		var sources: Array[Dictionary] = [{"position":patch.point - Vector3.BACK * 0.5,"direction":Vector3.BACK,"power":1.0}]
		game.plant_current.update_sources(sources,0.3)
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		second = viewport.get_texture().get_image(); second.save_png("res://tests/plant-propeller-wash.png")
		changed = 0
		for y in range(400):
			for x in range(400):
				if first.get_pixel(x,y) != second.get_pixel(x,y): changed += 1
		check(changed > 100,"Propeller wash visibly bends the rendered foliage")
		print("Propeller wash changed pixels: ",changed)
		# Hold the wash bend constant and stop ordinary sway. Moving pixels now
		# come from the travelling wash ripples/torsion, not a changing lean.
		game.plant_current.configure({"speed":0.0,"ripple":0.5,"twist":1.0})
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		first = viewport.get_texture().get_image()
		await create_timer(0.5).timeout; await RenderingServer.frame_post_draw
		second = viewport.get_texture().get_image(); second.save_png("res://tests/plant-wash-twist.png")
		changed = 0
		for y in range(400):
			for x in range(400):
				if first.get_pixel(x,y) != second.get_pixel(x,y): changed += 1
		check(changed > 100,"Constant propeller wash produces travelling distortion with ordinary sway stopped")
		viewport.queue_free()
	game.queue_free(); await process_frame
	print("Wildlife visuals: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
