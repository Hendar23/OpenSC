extends "res://tests/test_scene_tree.gd"
class Population extends "res://wildlife_population.gd":
	var visibility_probes := 0
	var reject_after := -1
	func _random_home(_species: Dictionary, _random: RandomNumberGenerator) -> Vector3: return Vector3(0,0,80)
	func _visible_spawn(_point: Vector3, _observer: Vector3, _radius: float = 0.0) -> bool:
		visibility_probes += 1
		return reject_after >= 0 and visibility_probes > reject_after
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func state(id: String, count: int) -> Dictionary:
	return {"group":{"id":id,"species":"silver","position":[0,0,12],"count_min":count,"count_max":count,"radius":2.0},"seed":42,"members":[],"attempted":false}
func finish_spawn(pop: Node3D) -> void:
	for tick in range(100):
		if pop.pending_spawn.is_empty(): return
		pop._advance_spawn()
		await process_frame
	check(false,"Pending shoal preparation finishes within a bounded number of frames")
func run() -> void:
	var world := Node3D.new(); root.add_child(world)
	world.set_meta("bounds",AABB(Vector3(-100,-10,-100),Vector3(200,40,200)))
	world.set_meta("surface_height",25.0)
	var observer := Node3D.new(); world.add_child(observer)
	var camera := Camera3D.new(); observer.add_child(camera); camera.current = true
	var pop := Population.new(); world.add_child(pop); pop.world = world
	pop.streaming = true; pop.simulating = false; pop.set_physics_process(false)
	pop.player = observer; pop.view_camera = camera; pop.visibility_range = 30
	pop.definitions.silver = {"id":"silver","model":"SILVER","scale_min":100,"scale_max":100,"speed":1.0,"group_behaviour":"shoaling","response":"ignore","mobility":"swimming","health":6.0}
	pop.templates.silver = Node3D.new(); pop.model_bounds.silver = AABB(Vector3.ONE * -0.1,Vector3.ONE * 0.2)
	var overlapping := state("overlapping",1)
	overlapping.group.position = [0,0,0]; overlapping.group.radius = 0.0
	pop.random_groups.append(overlapping)
	pop._stream_update(true)
	check(overlapping.members.is_empty() and not overlapping.attempted,"Initial streaming retries later when a fish's placement overlaps the starting submarine")
	# The centre is outside the hull. A large fish's body still reaches it.
	overlapping.group.position = [0,0,2]
	pop.model_bounds.silver = AABB(Vector3.ONE * -1.0,Vector3.ONE * 2.0)
	pop._stream_update(true)
	check(overlapping.members.is_empty(),"Initial streaming accounts for the fish's full radius")
	pop.model_bounds.silver = AABB(Vector3.ONE * -0.1,Vector3.ONE * 0.2)
	pop.random_groups.clear()
	var approached := state("approached",2); pop.random_groups.append(approached)
	pop._stream_update(); pop._advance_spawn()
	check(not pop.pending_spawn.is_empty(),"An off-screen shoal prepares before its collision is enabled")
	if not pop.pending_spawn.is_empty():
		observer.position = pop.pending_spawn.placements[0].point
		await finish_spawn(pop)
	check(pop.pending_spawn.is_empty() and approached.members.is_empty() and not approached.attempted,"Swimming into a prepared spawn cancels it before the fish go live")
	observer.position = Vector3.ZERO
	pop.random_groups.clear()
	var shoal := state("twenty",20); pop.random_groups.append(shoal)
	pop._stream_update()
	check(not pop.pending_spawn.is_empty() and pop.active_count() == 0,"Streaming queues a whole shoal without creating all its actors in one frame")
	await process_frame; await process_frame
	pop._advance_spawn()
	check(pop.pending_spawn.members.size() == 1 and pop.active_count() == 0 and not shoal.attempted,"One prepared fish remains hidden and cannot activate an incomplete shoal")
	check(pop.spawn_staging.get_child(0).collision_layer == 0 and not pop.spawn_staging.get_child(0).is_physics_processing(),"Preparing wildlife has no live collision or simulation")
	check(not pop.spawn_staging.get_child(0).is_in_group("marine_life") and not pop.spawn_staging.get_child(0).is_in_group("attractable_fish"),"Fishing equipment and mission boats cannot select an unfinished shoal")
	await finish_spawn(pop)
	check(shoal.members.size() == 20 and shoal.attempted,"Streaming activates all twenty fish together without shrinking the editor count")
	check(shoal.members.all(func(fish: Node3D) -> bool: return fish.is_in_group("marine_life") and fish.is_in_group("attractable_fish")),"Activated fish become available to fishing equipment together")
	pop._stream_update()
	check(shoal.members.size() == 20 and pop.active_count() == 20,"A completed shoal is not duplicated on the following update")
	pop.set_active_limit(15)
	check(shoal.members.is_empty() and pop.active_count() == 0,"Lowering capacity retires a whole shoal instead of leaving fifteen fragments")
	pop._stream_update()
	check(shoal.members.is_empty() and not shoal.attempted,"Insufficient capacity postpones the group rather than spawning an undersized shoal")
	pop.set_active_limit(30)
	await finish_spawn(pop)
	check(shoal.members.size() == 20,"Increasing capacity admits the complete group")
	var casualty: Node3D = shoal.members[0]
	casualty.take_damage(casualty.max_health)
	pop._stream_update(); await finish_spawn(pop)
	check(shoal.members.size() == 19 and pop.active_count() == 19,"A casualty leaves the surviving members active without spawning replacements")
	for fish in shoal.members.duplicate():
		fish.take_damage(fish.max_health)
	pop._stream_update()
	check(shoal.members.is_empty() and pop.active_count() == 0,"Killed fish are removed from the active population")
	for turn in range(4):
		observer.rotate_y(PI / 2.0)
		pop._stream_update(); await finish_spawn(pop)
	check(shoal.members.is_empty(),"Turning in place after killing a shoal never spawns another at the same site")
	observer.position = Vector3(0,0,100)
	pop._stream_update(); await finish_spawn(pop)
	observer.position = Vector3.ZERO
	pop._stream_update(); await finish_spawn(pop)
	check(shoal.members.size() == 20,"Leaving the area and returning still allows a fresh shoal")
	for fish in pop.get_children(): fish.free()
	pop.random_groups.clear(); pop.max_active = 10; pop.stream_cursor = 0
	var blocked := state("blocked",20); pop.random_groups.append(blocked)
	for index in range(6): pop.random_groups.append(state("single_%d" % index,1))
	for tick in range(8):
		pop._stream_update(); await finish_spawn(pop)
	check(blocked.members.is_empty() and pop.active_count() == 6,"A blocked large group cannot starve later groups of spawning turns")
	for fish in pop.get_children(): fish.free()
	pop.random_groups.clear(); pop.stream_cursor = 0; pop.max_active = 80
	# All candidate positions touch the surface: the group must remain unspawned.
	var invalid := state("surface",20); invalid.group.position = [0,25.5,12]
	pop.random_groups.append(invalid); pop._stream_update()
	check(invalid.members.is_empty() and not invalid.attempted and not pop.spawned_groups.has("surface"),"Unplaceable groups are not marked complete")
	pop.random_groups.clear()
	var cancelled := state("cancelled",20); pop.random_groups.append(cancelled)
	pop._stream_update(); await process_frame; pop._advance_spawn()
	check(not pop.pending_spawn.is_empty(),"A new off-screen group starts preparing")
	pop.reject_after = 0; pop.visibility_probes = 0
	await process_frame; pop._advance_spawn()
	check(pop.pending_spawn.is_empty() and cancelled.members.is_empty() and pop.active_count() == 0,"Turning toward a preparing group cancels it without visible pop-in or leftover actors")
	pop.reject_after = -1
	# Nineteen valid placements must not build then discard nineteen actors.
	var additions := [0]
	pop.child_entered_tree.connect(func(_child: Node) -> void: additions[0] += 1)
	pop.reject_after = 19; pop.visibility_probes = 0
	var random := RandomNumberGenerator.new(); random.seed = 42
	pop.spawn_budget = 30
	var incomplete := pop._spawn_group(state("partial",20).group,random,true,true)
	check(incomplete.is_empty() and additions[0] == 0 and pop.spawn_budget == 30,"Under-minimum shoals allocate no actors or replay tracks and leave the spawn budget intact")
	pop.reject_after = -1
	# Independent test of authored group abundance and species scheduling.
	var species: Dictionary = pop.definitions.silver
	species.merge({"random_spawn":true,"groups_min":20,"groups_max":20,"count_min":20,"count_max":20,"spawn_chance":60.0,"roam_radius":2.0})
	var mutant := species.duplicate(true); mutant.id = "mutant"; mutant.groups_min = 3; mutant.groups_max = 3; mutant.count_min = 1; mutant.count_max = 1
	pop.document = {"groups":[],"species":[species,mutant]}
	pop.definitions.mutant = mutant; pop.templates.mutant = Node3D.new(); pop.model_bounds.mutant = pop.model_bounds.silver
	pop.session_seed = 1234; pop.reroll(false)
	check(pop.random_groups.filter(func(entry: Dictionary) -> bool: return entry.group.species == "silver").size() == 20 and pop.random_groups.filter(func(entry: Dictionary) -> bool: return entry.group.species == "mutant").size() == 3,"Editor group counts retain their authored twenty-to-three ratio")
	var first_mutant := -1
	for index in range(pop.random_groups.size()):
		if pop.random_groups[index].group.species == "mutant": first_mutant = index; break
	check(first_mutant >= 0 and first_mutant < 20,"Streaming schedule is not fixed in editor species order")
	world.free()
	print("Wildlife group limits: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
