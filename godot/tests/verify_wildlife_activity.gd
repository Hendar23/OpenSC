extends SceneTree
const Fish = preload("res://fish_controller.gd")
const Population = preload("res://wildlife_population.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var pop := Population.new(); world.add_child(pop); pop.world = world; pop.streaming = true; pop.set_physics_process(false)
	var player := Node3D.new(); world.add_child(player); pop.player = player
	var camera := Camera3D.new(); world.add_child(camera); pop.view_camera = camera; pop.visibility_range = 10
	var fish := Fish.new(); fish.setup(Node3D.new(),Vector3(0,0,-5),AABB(Vector3(-100,-100,-100),Vector3.ONE*200),100,0.2,42); fish.population = pop; pop.add_child(fish)
	pop._update_activity(fish,Vector3.ZERO,camera.get_frustum())
	check(fish.visual_animation_enabled and fish.is_processing() and fish.is_physics_processing(),"Visible wildlife retains full animation and AI")
	fish.position = Vector3(0,0,5); pop._update_activity(fish,Vector3.ZERO,camera.get_frustum())
	check(not fish.visual_animation_enabled and not fish.is_processing() and fish.is_physics_processing(),"Wildlife behind the camera roams without pose uploads")
	fish.position = Vector3(0,0,-12); pop._update_activity(fish,Vector3.ZERO,camera.get_frustum())
	check(not fish.is_processing() and not fish.is_physics_processing(),"The fog preparation band does not simulate")
	fish.position = Vector3(0,0,-5); pop._update_activity(fish,Vector3.ZERO,camera.get_frustum())
	check(fish.is_processing() and fish.is_physics_processing(),"Entering view restores animation and simulation")
	pop._set_awake(fish,false)
	check(fish.process_mode == Node.PROCESS_MODE_DISABLED and not fish.visible,"Dormancy disables the entire creature subtree")
	pop._set_awake(fish,true); pop.set_simulating(false)
	check(not fish.is_processing() and not fish.is_physics_processing(),"Pausing suppresses both callbacks")
	pop.set_simulating(true)
	check(fish.is_processing() and fish.is_physics_processing(),"Resuming restores visible wildlife")
	fish.position = Vector3(0,0,8); fish.detection_distance = 3; fish.visual_animation_enabled = false
	var time := fish.animation_time
	fish._physics_process(1.0/60.0)
	check(fish.animation_time == time and fish.offscreen_delta > 0,"Distant offscreen AI batches short physics ticks")
	fish.position = Vector3(0,0,1); fish._physics_process(1.0/60.0)
	check(fish.animation_time > time and fish.offscreen_delta == 0,"Nearby wildlife retains full-rate reactions")
	world.queue_free(); await process_frame
	print("Wildlife activity: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
