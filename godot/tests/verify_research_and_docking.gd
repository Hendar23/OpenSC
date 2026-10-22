extends "res://tests/verify_remaining_stage_two.gd"
const Fish = preload("res://fish_controller.gd")
const Thorium = preload("res://thorium_body.gd")
const Explosion = preload("res://mine_explosion.gd")
const Bindings = preload("res://input_bindings.gd")

func key(code: int, handled: bool = false) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = true
	if handled: game._input(event)
	else: game._unhandled_input(event)

func interaction_fish(pop: Node3D, point: Vector3, role: String) -> Node3D:
	var fish := Fish.new(); fish.setup(Node3D.new(),point,AABB(Vector3(-100,-100,-100),Vector3.ONE*200),100,0.2,42)
	pop.add_child(fish); fish.population = pop; fish.configure_combat({"food_role":role,"attack_range":8,"flee_range":8}); fish.set_physics_process(true)
	return fish

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"World loads for research/docking checks")
	if not game.startup_complete: quit(1); return
	await game._begin_new_game(); game.pilot.freeze = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false); game.set_process(false); game.set_physics_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	game.object_population.set_physics_process(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	var before: Array = game.object_population.get_children()
	await fresh("tagtech")
	var mission: RefCounted = jobs.remaining
	var extra_fish: Array = jobs.actors.filter(func(body: Node) -> bool: return body is Fish and body != mission.creature)
	check(extra_fish.size() == 9 and extra_fish.all(func(body: Node) -> bool: return not body.has_meta("mission_marker") and body not in game.cockpit_hud.map_data.actor_markers),"Extra mission wildlife have no minimap dots")
	check(mission.creature in game.cockpit_hud.map_data.actor_markers,"Tagged specimen retains its designated map marker")
	check(mission.creature.ignore_wildlife,"Tagged specimen ignores other wildlife")
	check(mission.creature.collision_mask & 8 == 0,"Specimen retains collision-free passage through fish")
	var pop := preload("res://wildlife_population.gd").new(); root.add_child(pop)
	var predator := interaction_fish(pop,Vector3(0,60,0),"predator")
	var prey := interaction_fish(pop,Vector3(0,60,0.5),"prey")
	predator.combat.perceive(1); prey.combat.perceive(1)
	check(predator.combat.target == prey and prey.combat.threat == predator,"Ordinary wildlife still hunt and flee normally")
	predator.ignore_wildlife = true; predator.combat.perceive(1); prey.combat.perceive(1)
	check(predator.combat.target == null and prey.combat.threat == null,"Ignoring wildlife suppresses hunting and reciprocal fleeing")
	predator.ignore_wildlife = false; prey.ignore_wildlife = true; predator.combat.perceive(1); prey.combat.perceive(1)
	check(predator.combat.target == null and prey.combat.threat == null,"Predators cannot select an ignored specimen either")
	predator.combat.target = prey; predator.combat.attack(0.1)
	check(predator.combat.target == null,"Stale wildlife attack targets are discarded")
	pop.free()
	var crystals: Array = game.object_population.get_children().filter(func(body: Node) -> bool: return body is Thorium and body not in before)
	check(crystals.size() == 4 and crystals.all(func(body: Node) -> bool: return not body.has_meta("mission_owner")),"Four cave crystals are independent world resources")
	var barrel: RigidBody3D = mission.cargo
	var point: Vector3 = barrel.global_position+Vector3(12,2,0)
	barrel.global_position = point; game.pilot.global_position = point+Vector3.UP*2
	game.pilot.active = true; game.pilot.controls_enabled = true; game.pilot.hull_rating = 100; game.pilot.radiation_rating = 0; game.pilot.restore_health()
	var magnet: Node3D = game.equipment.magnet; magnet.set_enabled(true); magnet._attach(barrel)
	check(magnet.target == barrel,"Canister attaches to the real magnet")
	check(is_equal_approx(float(barrel.stats.radiation_strength),4.375),"Canister uses the recovered callback's 0.05 inflict strength")
	game.object_population._update_radiation(1)
	check(is_equal_approx(game.pilot.health,100-4.375/2) and game.pilot.radiation_exposed,"Towed canister damages the unprotected player and raises the radiation warning")
	game.pilot.restore_health(); game.pilot.radiation_rating = 100; game.object_population._update_radiation(1)
	check(is_equal_approx(game.pilot.health,100-4.375/2*0.2),"Existing radiation shielding reduces canister damage")
	game.pilot.restore_health(); game.pilot.global_position = point+Vector3.UP*4; game.object_population._update_radiation(1)
	check(game.pilot.health == 100 and not game.pilot.radiation_exposed,"Canister radiation ends at its four-unit range")
	game.pilot.global_position = point+Vector3.UP*2; barrel.delivered = true; game.object_population._update_radiation(1)
	check(game.pilot.health == 100 and not game.pilot.radiation_exposed,"Delivered canister no longer irradiates the player")
	barrel.delivered = false; magnet.release()
	var crystal: Node3D = crystals.pop_back(); game.object_population._shatter(crystal)
	await process_frame
	var shards: Array = game.object_population.get_children().filter(func(body: Node) -> bool: return body is Thorium and body.shard > 0 and body not in before)
	check(shards.size() == 3,"Cave crystal shatters into collectible world shards")
	var effects_before: Array = game.world_root.get_children()
	barrel.take_weapon_damage(1000)
	await process_frame
	var effects: Array = game.world_root.get_children().filter(func(body: Node) -> bool: return body is Explosion and body not in effects_before)
	check(runtime.active().is_empty() and not game.player_progress.missions.completed.tagtech.success,"Destroying the canister still fails the mission")
	check(effects.size() == 1 and not effects[0].frames.is_empty() and effects[0].audio.stream != null,"Destroyed canister produces a visible, audible explosion beyond mission cleanup")
	check(crystals.all(func(body: Node) -> bool: return is_instance_valid(body) and not body.is_queued_for_deletion()) and shards.all(func(body: Node) -> bool: return is_instance_valid(body) and not body.is_queued_for_deletion()),"Cave crystals and existing shards persist after mission failure")
	var retained: Array = crystals+shards
	var ids: Array = retained.map(func(body: Node) -> String: return preload("res://entity_identity.gd").of(body))
	var snapshot: Array = game.object_population.snapshot()
	check(ids.all(func(id: String) -> bool: return snapshot.any(func(entry: Dictionary) -> bool: return entry.entity_id == id)),"Retained resources enter the normal beta-compatible world snapshot")
	game.object_population.restore_snapshot(snapshot)
	check(ids.all(func(id: String) -> bool: return game.object_population.get_children().any(func(body: Node) -> bool: return preload("res://entity_identity.gd").of(body) == id)),"Retained crystals and shards restore from their normal snapshot")
	before = game.object_population.get_children()
	await fresh("tagtech"); mission = jobs.remaining
	crystals = game.object_population.get_children().filter(func(body: Node) -> bool: return body is Thorium and body not in before)
	check(jobs.delivery(mission.cargo,4),"Canister can still be delivered to Procha")
	await process_frame
	check(crystals.size() == 4 and crystals.all(func(body: Node) -> bool: return is_instance_valid(body) and not body.is_queued_for_deletion()),"Cave resources also survive successful delivery")
	game.equipment.set_installed(["magnet","bigears","deep_sea_lights"]); game.weapons.set_installed(["zapper","missile","electro"])
	game.pilot.active = true; game.pilot.controls_enabled = false; game.dock_interface.dismiss(); paused = false
	for stage in [game.Docking.Stage.APPROACH,game.Docking.Stage.SETTLE,game.Docking.Stage.ALIGN,game.Docking.Stage.OPEN,game.Docking.Stage.DESCEND,game.Docking.Stage.CLOSE,game.Docking.Stage.EXIT_OPEN,game.Docking.Stage.ASCEND,game.Docking.Stage.EXIT_CLOSE]:
		game.docking.stage = stage; game.equipment.selected = 0; game.weapons.selected = 0
		key(KEY_PAGEDOWN); key(KEY_BRACKETRIGHT)
		check(game.weapons.selected == 1 and game.equipment.selected == 1,"Selection works during automatic docking stage " + str(stage))
		key(KEY_PAGEUP); key(KEY_BRACKETLEFT)
		check(game.weapons.selected == 0 and game.equipment.selected == 0,"Reverse selection works during automatic docking stage " + str(stage))
		key(KEY_M,true)
		check(game.map_open and not game.pilot.controls_enabled and game.docking.stage == stage,"Full map opens without steering or interrupting transit stage " + str(stage))
		key(KEY_M,true); check(not game.map_open,"Map toggles closed during transit stage " + str(stage))
	game.docking.stage = game.Docking.Stage.CLOSE; game._set_map_open(true); game._reset_docked_wildlife()
	check(not game.map_open,"Dock arrival clears the map before showing the city interface")
	game.docking.stage = game.Docking.Stage.DOCKED; key(KEY_M,true)
	check(not game.map_open,"Full dock menu does not reopen the transit map")
	game.free(); await process_frame
	print("Research/docking verification: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
