extends SceneTree
const Game = preload("res://game.gd")
const Document = preload("res://map_document.gd")
const Mods = preload("res://mod_registry.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)
func positions(pop: Node3D) -> Array:
	return pop.random_groups.map(func(state: Dictionary) -> Array: return state.group.position)
func _run() -> void:
	Mods.initialize(false)
	var data := Document.load_active()
	check(Document.valid(data) and data.groups.is_empty() and data.species.all(func(species: Dictionary) -> bool: return species.random_spawn),"Current map retains species and has no fixed wildlife spawns")
	var invalid := data.duplicate(true); invalid.species[0].groups_min = 30; invalid.species[0].groups_max = 2
	check(not Document.valid(invalid),"Invalid random group ranges are rejected")
	var game := Game.new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(1200):
		if game.startup_complete: break
		await physics_frame
	game.set_process(false); game.set_physics_process(false); game.pilot.active = false
	var pop: Node3D = game.wildlife; pop.set_simulating(false); pop.set_physics_process(false)
	check(pop.streaming and pop.random_groups.size() > 70,"Random groups are distributed throughout the map")
	check(pop.get_child_count() > 0 and pop.spawned_groups.size() < pop.random_groups.size(),"Only nearby groups are active in the game")
	var safe := true
	for fish in pop.get_children():
		safe = safe and fish.position.y + fish.radius < game.pilot.surface_height and fish.collision_layer == 8 and (fish.collision_mask & 8) == 0
	check(safe,"Creatures stay submerged and do not exclude other groups from their space")
	print("Initial random wildlife: %d groups, %d active groups, %d creatures" % [pop.random_groups.size(),pop.spawned_groups.size(),pop.get_child_count()])
	pop.session_seed = 444; pop.reroll(false)
	var visible_distance: float = pop.visibility_range
	var nearby_count: int = pop.get_child_count()
	check(pop.get_children().all(func(fish: Node3D) -> bool: return fish.global_position.distance_to(game.pilot.global_position) <= visible_distance + 4.01),"Only creatures within the small visible-range band are instantiated")
	pop.visibility_range = 66.0; pop.reroll(false)
	var wide_count: int = pop.get_child_count()
	pop.visibility_range = visible_distance; pop.reroll(false)
	check(nearby_count < wide_count * 0.5,"Visible-range spawning removes most of the previous 70-unit population")
	print("Streaming comparison with same population: %d near visibility versus %d at 70 units" % [nearby_count,wide_count])
	var signature := positions(pop)
	pop.reroll(false); check(positions(pop) == signature,"A session retains its population between streaming updates")
	pop.reroll(); check(positions(pop) != signature,"Docking generation reshuffles group locations")
	var state: Dictionary = pop.random_groups[0]
	for fish in state.members: fish.free()
	state.members = []; state.attempted = false
	pop.random_groups.clear(); pop.random_groups.append(state)
	pop.view_camera = null
	var home := Document.vector(state.group.position)
	game.pilot.global_position = home + Vector3(0,0,5)
	pop._stream_update()
	check(state.members.is_empty(),"Streaming does not insert a group inside the visible range")
	game.pilot.global_position = home + Vector3(60,0,0)
	pop._stream_update()
	check(state.members.is_empty(),"Groups at the old 60-unit distance remain uninstantiated")
	game.pilot.global_position = home + Vector3(pop.visibility_range + 3.0,0,0)
	pop._stream_update()
	check(not state.members.is_empty(),"Approaching an unseen group activates it outside the visible range")
	var retained_count: int = state.members.size()
	if retained_count > 1:
		var distant: Node3D = state.members[-1]
		distant.global_position = game.pilot.global_position + Vector3(pop.visibility_range + 10.0,0,0)
		pop.set_simulating(true)
		pop._stream_update()
		check(state.members.size() == retained_count and not distant.visible and not distant.is_physics_processing() and distant.collision_mask == 0,"A distant creature is retained with rendering, simulation and collision stopped")
		var sleeping_position := distant.global_position
		var sleeping_animation: float = distant.animation_time
		await physics_frame; await physics_frame
		check(distant.global_position == sleeping_position and distant.animation_time == sleeping_animation and distant.get_child(0).disabled,"Dormant creatures retain their position and animation without active collision shapes")
		pop.set_simulating(false)
		for fish in state.members:
			if fish.get_meta("wildlife_awake",true): fish._physics_process(1.0 / 60.0)
		check(state.members.all(func(fish: Node3D) -> bool: return fish.group_members.all(func(peer: Node3D) -> bool: return is_instance_valid(peer))),"Active shoal members can update safely alongside dormant neighbours")
	game.pilot.global_position = home + Vector3(1000,0,0); pop._stream_update()
	check(state.members.size() == retained_count and state.attempted and pop.active_count() == 0,"Far-away groups remain dormant and are excluded from the active population")
	var returning: Node3D = state.members[0]
	var retained_position := returning.global_position
	game.pilot.global_position = retained_position + Vector3(pop.visibility_range + 3.0,0,0)
	pop._stream_update()
	check(returning.visible and returning.collision_mask == 5 and returning.global_position == retained_position and state.members[0] == returning,"Returning to an unseen group wakes the same creature at its retained position")
	for species in pop.document.species: species.random_spawn = false
	var species: Dictionary = pop.document.species[0]
	species.random_spawn = true; species.groups_min = 8; species.groups_max = 8
	species.count_min = 2; species.count_max = 4; species.spawn_chance = 100.0
	pop.density = 1.0; pop.reroll(false)
	check(pop.random_groups.size() == 8,"Species minimum and maximum group counts are respected")
	game.wildlife_density_slider.value = 200
	check(pop.random_groups.size() == 16 and game._view_settings().wildlife_density == 2.0,"Density doubles random group counts and is included in exported settings")
	game.wildlife_density_slider.value = 0
	check(pop.random_groups.is_empty() and pop.get_child_count() == 0,"Zero density disables the random population")
	game.wildlife_density_slider.value = 100
	species.spawn_chance = 0; pop.reroll()
	check(pop.random_groups.is_empty(),"Zero species spawn chance prevents random groups")
	species.spawn_chance = 50
	var appeared := 0
	for cycle in range(12): pop.reroll(); appeared += pop.random_groups.size()
	check(appeared > 25 and appeared < 70,"Species chance creates varied populations across generations")
	species.random_spawn = false
	pop.document.groups = []
	for index in range(2): pop.document.groups.append({"id":"overlap_%d" % index,"species":species.id,"position":Document.array(home),"chance":100.0,"count_min":1,"count_max":1,"radius":10.0})
	pop.reroll()
	check(pop.spawned_groups.has("overlap_0") and pop.spawned_groups.has("overlap_1"),"Two fixed groups may occupy the same location")
	game.queue_free(); await process_frame
	print("Random wildlife: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
