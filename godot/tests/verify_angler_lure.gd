extends SceneTree
const Fish = preload("res://fish_controller.gd")
const Document = preload("res://map_document.gd")
const Paths = preload("res://asset_paths.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var visual := Document.load_model("ANGLER",Paths.find_game_folder(),true)
	var fish := Fish.new(); fish.setup(visual,Vector3.ZERO,AABB(Vector3.ONE * -10,Vector3.ONE * 20),10,1,12); world.add_child(fish); fish.set_physics_process(false); fish.rotation = Vector3.ZERO
	check(fish.lure_light != null and fish.lure_light.get_parent() == fish.lure_mesh,"Angler light attaches to its lure mesh")
	var bulb := fish.lure_mesh.get_surface_override_material(1) as StandardMaterial3D
	check(bulb != null and bulb.emission_enabled and bulb.emission_energy_multiplier > 1,"Original lure bulb has a glowing material")
	check(not fish.lure_light.shadow_enabled and fish.lure_light.distance_fade_enabled,"Lure uses a small light without expensive shadows")
	for time in [0.0,0.3,0.8,1.4]:
		fish.animation.apply(time); fish._update_lure()
		check(fish.lure_light.position.is_finite() and fish.lure_light.position.distance_to(fish.lure_centers[0]) < 1,"Light stays on the animated lure")
	if DisplayServer.get_name() != "headless":
		var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color(0.005,0.025,0.04)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color = Color(0.2,0.3,0.4); environment.environment.ambient_light_energy = 0.2; world.add_child(environment)
		var camera := Camera3D.new(); world.add_child(camera); camera.position = Vector3(2,0.7,2.5); camera.look_at(Vector3.ZERO); camera.fov = 35; camera.current = true
		await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/angler-lure-preview.png")
	fish.take_damage(fish.health)
	check(not fish.is_visible_in_tree() and not fish.lure_light.is_visible_in_tree(),"Lure light is hidden when the fish dies")
	world.queue_free(); await process_frame
	print("Angler lure: 8 checks, %d failures" % failures); quit(1 if failures else 0)
