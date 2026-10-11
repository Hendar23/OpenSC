extends SceneTree
const Game = preload("res://game.gd")
const Defence = preload("res://dock_defence.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	preload("res://mod_registry.gd").initialize(false)
	var fresh_defence := Defence.new()
	check(is_equal_approx(fresh_defence.damage_per_tick,3.0 * preload("res://submarine_weapons.gd").DEFAULTS.damage_per_tick),"Fresh dock damage defaults to three times the standard zapper")
	fresh_defence.free()
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(1800):
		if game.startup_complete: break
		await physics_frame
	check(game.startup_complete,"Actual world starts with dock defence")
	if not game.startup_complete: quit(1); return
	game._begin_new_game(); game.front_end.hide_menu(); game.set_process(false); game.set_physics_process(false)
	game.pilot.freeze = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false)
	var defence: Node3D = game.world_root.get_node("DockDefence")
	check(game.dock_zapper_damage_slider.get_parent().name == "System" and not game.dock_zapper_damage_slider.scrollable,"Damage slider appears in System and ignores mouse-wheel changes")
	check(is_equal_approx(defence.damage_per_tick,game.dock_zapper_damage_slider.value),"Live dock damage follows the loaded development settings")
	game.dock_zapper_damage_slider.value = 12.0
	check(defence.damage_per_tick == 12.0 and game._view_settings().dock_zapper_damage_per_tick == 12.0,"Damage slider changes live docks and is included in saved settings")
	var config := ConfigFile.new(); config.set_value("view","dock_zapper_damage_per_tick",9.0)
	var fixture := "res://tests/dock-damage-settings-test.cfg"; config.save(fixture)
	game._load_preferences(fixture)
	check(defence.damage_per_tick == 9.0 and game.dock_zapper_damage_slider.value == 9.0,"Saved dock damage restores to the slider and live docks")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	game.dock_zapper_damage_slider.value = Defence.DAMAGE
	check(defence.ports.size() == game.docking.ports.size() and defence.ports.size() >= 6,"All actual city docks receive defence")
	var population: Node3D = game.wildlife; population.set_physics_process(false)
	for fish in population.get_children(): fish.set_physics_process(false)
	var state: Dictionary = defence.ports.filter(func(entry: Dictionary) -> bool: return int(entry.node.get_meta("city_id")) == 1)[0]
	var port: Node3D = state.node
	var points := PackedVector3Array()
	preload("res://model_hitbox.gd")._collect_vertices(port,Transform3D.IDENTITY,points)
	for emitter in Defence.EMITTERS:
		var distance := INF
		for point in points: distance = minf(distance,point.distance_to(emitter))
		check(distance < 0.05,"Recovered emitter lies at an actual dock spike tip")
	var species: String = population.templates.keys()[0]
	var fish := preload("res://fish_controller.gd").new()
	fish.setup(population.templates[species].duplicate(),port.to_global(Defence.SEARCH_CENTER),AABB(Vector3.ONE * -1000,Vector3.ONE * 2000),1000,0.3,1)
	fish.population = population; fish.swim_speed = 0; fish.configure_health(1000); population.add_child(fish)
	game.camera.global_position = port.to_global(Vector3(6,5.5,7))
	game.camera.look_at(port.to_global(Vector3(0,1.6,0)),Vector3.UP)
	defence._physics_process(0.04)
	check(fish.health < 1000 and state.arcs.size() == 3,"Live port attacks approaching wildlife with three arcs")
	check(state.sound.stream == population.zapper_sound,"Dock defence shares the original electricity sound")
	check(state.sound.bus == "Effects","Dock zapper obeys global effects volume")
	for frame in range(3): await process_frame
	check(state.arcs.all(func(arc: Node3D) -> bool: return arc.beam.visible and arc.beam.mesh.get_surface_count() > 0),"All three arcs render in the actual world")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/dock-defence-preview.png")
	game._show_main_menu()
	check(paused and not defence.can_process(),"Dock defence suspends with the paused outside world")
	paused = false; game.queue_free(); await process_frame
	print("Actual-world dock defence: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
