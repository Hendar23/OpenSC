extends SceneTree
const Game = preload("res://game.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/" + name + ".png")
func run() -> void:
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(2400):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete,"Actual game loads")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.day_night.enabled = false
	game.pilot.set_physics_process(false)
	game.natural_light.configure(Game.NaturalLight.DEFAULTS)
	for frame in range(2400):
		if game.cockpit_hud.map_data.scenery_baked or DisplayServer.get_name() == "headless": break
		await process_frame
	var key := InputEventKey.new(); key.keycode = KEY_M; key.pressed = true
	game._input(key)
	check(game.map_open and game.expanded_map.full_world,"M opens whole-world map")
	check(game.expanded_map.map_data == game.cockpit_hud.map_data,"Expanded map shares exploration and map imagery")
	game._process(0)
	check(not game.pilot.controls_enabled,"Map prevents accidental piloting/fire")
	if DisplayServer.get_name() != "headless": await capture("expanded-map")
	game._input(key); check(not game.map_open,"M closes map")
	game._update_daylight()
	if DisplayServer.get_name() != "headless": await capture("outdoors-fixed")
	var original := InputMap.action_get_events("map_toggle")
	InputMap.action_erase_events("map_toggle")
	var replacement := InputEventKey.new(); replacement.keycode = KEY_J
	InputMap.action_add_event("map_toggle",replacement)
	preload("res://input_bindings.gd").install()
	game._input(key); check(not game.map_open,"Old key stops working after rebinding")
	replacement.pressed = true; game._input(replacement)
	check(game.map_open,"Rebound key opens map and defaults are not overwritten")
	game._set_map_open(false)
	InputMap.action_erase_events("map_toggle")
	for event in original: InputMap.action_add_event("map_toggle",event)
	var space := game.world_root.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.new(); ray.collision_mask = 16; ray.hit_back_faces = false
	var box: AABB = game.natural_light.bounds
	var open_samples := 0; var darkest := 1.0
	for z in range(int(box.position.z) + 5,int(box.end.z) - 5,5):
		for x in range(int(box.position.x) + 5,int(box.end.x) - 5,5):
			ray.from = Vector3(x,game.natural_light.surface + 1,z); ray.to = Vector3(x,box.position.y,z)
			var floor_hit := space.intersect_ray(ray)
			if floor_hit.is_empty(): continue
			var point: Vector3 = floor_hit.position + floor_hit.normal
			if game.natural_light.surface - point.y > 20: continue
			var open := true
			for offset in [Vector3.ZERO,Vector3.LEFT * 4,Vector3.RIGHT * 4,Vector3.FORWARD * 4,Vector3.BACK * 4]:
				ray.from = point + offset; ray.to = Vector3(ray.from.x,game.natural_light.surface + 1,ray.from.z)
				if not space.intersect_ray(ray).is_empty(): open = false; break
			if open:
				open_samples += 1
				var exposure := game.natural_light.visibility(point)
				if exposure < darkest:
					darkest = exposure
					if exposure < 0.1: print('Dark open point ',point,' normal ',floor_hit.normal)
	check(open_samples > 100 and darkest > 0.98,"Open original terrain remains illuminated across ridge and cliff samples")
	print("Open terrain samples ",open_samples," minimum exposure ",darkest)
	var cave := Vector3.ZERO; var best := 0.0
	# Find a real air cavity, with an underside above and a floor below.
	for z in range(int(box.position.z) + 4,int(box.end.z) - 4,2):
		for x in range(int(box.position.x) + 4,int(box.end.x) - 4,2):
			for y in range(142,158,3):
				var point := Vector3(x,y,z)
				ray.from = point; ray.to = point + Vector3.UP * 24
				var up := space.intersect_ray(ray)
				if up.is_empty() or up.normal.y > -0.2: continue
				ray.to = point + Vector3.DOWN * 15
				var down := space.intersect_ray(ray)
				if down.is_empty() or down.normal.y < 0.2: continue
				var room := minf(point.distance_to(up.position),point.distance_to(down.position))
				if x >= 180 and room > best and game.natural_light.visibility(point) == 0:
					best = room; cave = point
	check(best > 1.0,"Found an enclosed air volume in original terrain")
	print("Cave point ",cave," clearance ",best)
	if best > 1:
		game.pilot.global_position = cave; game.pilot.reset_physics_interpolation()
		var wall := Vector3.ZERO; var wall_distance := INF
		for direction in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
			ray.from = cave; ray.to = cave + direction * 30
			var hit := space.intersect_ray(ray)
			if not hit.is_empty() and cave.distance_to(hit.position) < wall_distance:
				wall_distance = cave.distance_to(hit.position); wall = hit.position
		if wall_distance < INF: game.pilot.global_basis = Basis.looking_at(wall - cave)
		game._set_camera_mode(true); game._update_follow_camera(0,true)
		game._update_daylight()
		check(game.water_environment.background_color.b < 0.1,"Sheltered background uses dark cave water instead of blue sky glow")
		check("fog_disabled" in game.surface_material.shader.code,"Actual water surface stays independent of the sheltered background")
		if DisplayServer.get_name() != "headless":
			await capture("cave-fixed-dark")
			var interior := root.get_texture().get_image()
			check(interior.get_pixel(interior.get_width() / 2,interior.get_height() - 20).b < 0.1,"Rendered distant cave water does not receive blue engine sky fog")
			game.natural_light_controls.cave_ambient.value = 0.15
			game._update_daylight(); await capture("cave-fixed-ambient")
			game.equipment.mounted[0].enabled = true; game.equipment.apply_settings()
			await capture("cave-fixed-headlight")
	game.queue_free(); await process_frame
	print("Caves and expanded map: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
