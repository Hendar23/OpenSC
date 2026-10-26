extends SceneTree
const Fish = preload("res://fish_controller.gd")
const Population = preload("res://wildlife_population.gd")
var checks := 0
var failures := 0
class Observer extends Node3D:
	var dead := false
	var active := true
	var controls_enabled := true
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	var pop := Population.new(); world.add_child(pop); pop.world = world; pop.streaming = true; pop.set_physics_process(false)
	var player := Observer.new(); world.add_child(player); pop.player = player
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
	fish.position = Vector3(0,0,-28); pop.visibility_range = 30
	pop._update_activity(fish,Vector3.ZERO,camera.get_frustum())
	check(pop.detailed(fish) and fish.animation_interval == 0.0 and fish.is_physics_processing(),"Fish beyond the old 24-unit steering limit stay smooth throughout visible water")
	var activity := preload("res://actor_activity.gd").new(); world.add_child(activity); activity.set_physics_process(false)
	activity.cameras.append(camera); camera.far = 80; activity.refresh_views(); pop.activity = activity
	fish.position = Vector3(0,0,-70); pop._update_activity(fish,Vector3.ZERO,camera.get_frustum())
	check(pop.detailed(fish) and fish.animation_interval == 0.0 and fish.is_processing(),"Longer active camera visibility extends both steering and pose updates")
	pop.activity = null; activity.free(); pop.visibility_range = 10
	# Exercise ambient travel beyond the new smooth-range boundary.
	fish.position = Vector3(0,0,pop.smooth_range()+2); fish.attack_range = 3; fish.flee_range = 1.5; fish.visual_animation_enabled = false
	var time := fish.animation_time
	fish._physics_process(1.0/60.0)
	check(fish.animation_time > time and fish.ambient_clock > 0 and fish.offscreen_delta == 0,"Distant local scenery advances without the detailed AI path")
	fish.position = Vector3(0,0,1); fish._physics_process(1.0/60.0)
	check(fish.animation_time > time and fish.offscreen_delta == 0,"Nearby wildlife retains full-rate reactions")
	var members: Array[Node3D] = []
	for index in range(120):
		var extra := Fish.new()
		extra.setup(Node3D.new(),Vector3(0.1 * index,0,0),AABB(Vector3.ONE * -100,Vector3.ONE * 200),100,0.2,index)
		extra.population = pop; pop.add_child(extra); members.append(extra)
	pop.set_active_limit(40)
	check(pop.active_count() == 40,"Crowded wildlife is capped immediately")
	check(is_instance_valid(members[0]) and not is_instance_valid(members.back()),"Nearest wildlife has priority; excess individuals are discarded")
	check(pop.get_child_count() == 40,"The population cap retains no dormant world actors")
	await physics_frame
	check(pop.get_child_count() == 40,"Discarded actors cannot retain active collisions")
	pop.set_simulating(false); pop.set_simulating(true)
	check(pop.active_count() <= 40,"Docking or pause changes do not bypass the cap")
	pop.set_active_limit(60)
	check(pop.active_count() == 40,"Raising the cap does not resurrect discarded individuals without habitat spawns")
	pop.set_active_limit(0); pop._stream_update(true)
	check(pop.active_count() == 40,"Unlimited does not retain historical individual state")
	pop.streaming = false; pop.set_active_limit(40)
	check(pop.active_count() == 40,"Gameplay cap changes leave editor preview populations intact")
	world.queue_free(); await process_frame
	print("Wildlife activity: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
