extends "res://tests/test_scene_tree.gd"
const Progress = preload("res://player_progress.gd")
const Rules = preload("res://mission_rules.gd")
const Volcano = preload("res://volcanic_disaster.gd")
const Charge = preload("res://depth_charge.gd")
const Burst = preload("res://mine_explosion.gd")
var game: Node
var runtime: Node
var jobs: Node
var checks := 0
var failures := 0

func _init() -> void:
	super._init()
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-volcano-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var config := ConfigFile.new(); config.set_value("game","folder",OS.get_environment("OPENSC_TEST_GAME_FOLDER")); config.save(storage.preferences_path())
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func heard(code: String) -> bool:
	var text: String = game.gameplay_catalogue.tables.radio_messages.records[code].text
	return game.bounty_radio_queue.any(func(entry: Dictionary) -> bool: return entry.text == text)

func fresh(id: String) -> StaticBody3D:
	runtime._cleanup(); await physics_frame; await physics_frame
	game.radio_feed.clear(); game.bounty_radio_queue.clear(); runtime.outcome.dismiss()
	game.player_progress = Progress.restore({"campaign_stage":3}); game.player_progress.status.credits = 10000
	if id == "fumehole": game.player_progress.missions.completed["disperse"] = {"success":true,"city":2}
	game.pilot.restore_health(); game.pilot.active = true; game.pilot.controls_enabled = true
	game.pilot.global_position = Vector3(10000,100,10000); game.pilot.linear_velocity = Vector3.ZERO
	game.weapons.set_installed(["zapper","depthl"]); game.weapons.select_id("depthl")
	game.player_progress.hold.depth = 8
	runtime.set_testing_missions(false)
	var city := Rules.offering_city(id)
	game.docking.current = game.submarine_traffic.port_by_id(city); game.docking.stage = game.Docking.Stage.DOCKED
	var result: String = runtime.accept(city,id)
	check(result.is_empty(),"Accept original city variant "+id+": "+result)
	game.docking.stage = game.Docking.Stage.IDLE; game.dock_interface.dismiss(); jobs.set_physics_process(false)
	await physics_frame; await physics_frame
	return jobs.volcano

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"Original world loads")
	if not game.startup_complete: quit(1); return
	await game._begin_new_game()
	game.pilot.freeze = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false); game.set_process(false)
	game.world_root.get_node("ActorActivity").set_physics_process(false)
	game.wildlife.set_simulating(false); game.photo_mode.replay.set_process(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs
	var progress := Progress.restore({"campaign_stage":3})
	check(Rules.next_offer(progress,2) == "disperse" and Rules.next_offer(progress,4) == "fumehole2","Source city queue order")
	progress.missions.completed["disperse"] = {"success":true,"city":2}
	check(Rules.next_offer(progress,2) == "fumehole","Volcano follows Velcova's mutant attack")
	progress.missions.completed["fumehole2"] = {"success":true,"city":4}
	check(Rules.next_offer(progress,2).is_empty(),"Paired history excludes duplicate offer in published saves")
	progress = Progress.restore(JSON.parse_string(JSON.stringify(progress)))
	check(progress.missions.completed.has("fumehole2"),"New completion survives existing save restoration")
	game.player_progress = Progress.restore({"campaign_stage":3}); game.weapons.set_installed(["zapper"])
	check(Rules.requirement_cost(game,"fumehole",2) == 4570 and Rules.requirement_cost(game,"fumehole2",4) == 4460,"Original launcher and four-charge affordability")
	runtime.set_testing_missions(true)
	check(runtime.testing_mission_city("fumehole") == 2 and runtime.testing_mission_city("fumehole2") == 4,"Both variants available in dev tools at original cities")

	var core: StaticBody3D = await fresh("fumehole")
	var position: Vector3 = core.global_position
	check(position.distance_to(Vector3(310.5941,156.5066,179.522)) < 0.01,"Exact original crater placement")
	check(game.player_progress.missions.unavailable.has("fumehole2"),"Accepting Velcova excludes Tryton counterpart")
	check(runtime.target_marker.target_body() == core,"Existing HUD guidance points to invisible core")
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(position,position+Vector3.DOWN*8,1))
	check(not hit.is_empty() and position.y-hit.position.y > 2,"Core is accessible above crater floor")
	core.take_weapon_damage(10000,position)
	check(core.health == 10 and not core.dead,"Ordinary weapons cannot shut down the volcano")
	for i in range(3): core.depth_charge_from(10000,position+Vector3.RIGHT*4,Vector3.ZERO)
	check(core.hits == 0 and core.health == 10 and heard("n14"),"Three misses give precise-aim warning without damage")
	core.depth_charge_from(10000,position+Vector3.UP*3,Vector3.ZERO)
	check(heard("n22") and core.hits == 0,"Aligned but high charge reports original warning")
	core.depth_charge_from(10000,position+Vector3.DOWN*3,Vector3.ZERO)
	check(core.hits == 0,"Below-target out-of-range charge is not a direct hit")
	core.step(10.0)
	check(heard("n8"),"Original ten-second seismic warning")
	check(Volcano.heat_at(66) == 0.05 and Volcano.heat_at(67) == 0.18 and Volcano.heat_at(250) == 0.3 and Volcano.heat_at(450) == 0.18,"Original quiet, rising, peak and settling heat phases")
	core.cycle_tick = 500; core.tick_credit = 0; core.step(0.04)
	check(core.cycle_tick == 0,"Original 501-tick eruption cycle wraps")
	game.pilot.global_position = position+Vector3.UP*2
	var before: float = game.pilot.health
	core.cycle_tick = 300; core._heat_tick()
	check(is_equal_approx(before-game.pilot.health,0.525) and heard("n21"),"Peak heat applies original radial damage and hull protection once")
	var queued: int = game.bounty_radio_queue.size(); core._heat_tick()
	check(game.bounty_radio_queue.size() == queued,"Heat warning is throttled")
	game.pilot.hull_rating = 150; before = game.pilot.health; core._heat_tick()
	check(is_equal_approx(before-game.pilot.health,0.15),"Upgraded hull reduces heat normally")
	game.pilot.hull_rating = 100; game.pilot.global_position = position+Vector3.UP*5
	before = game.pilot.health; core._heat_tick()
	check(game.pilot.health == before,"Heat ends outside the original radius")
	game.pilot.global_position = position+Vector3.UP*3.2
	before = game.pilot.health; core._heat_tick()
	check(game.pilot.health < before,"Heat catches a hull touching the hazard even with its centre outside the three-unit radius")
	game.pilot.global_position = position+Vector3.UP*10
	var camera_pose: Transform3D = game.camera.global_transform
	game.camera.global_position = position+Vector3(5,5,5)
	core.bubbles.clear(); core.cycle_tick = 249; core.tick_credit = 0
	core.step(0.08)
	check(core.bubbles.credits.size() == 3 and core.bubbles.particles.size() >= 3,"Peak eruption fills three separate bubble columns")
	check(core.smoke.tuning.emission_rate == 16.0 and core.smoke.tuning.opacity >= 0.9 and core.smoke.tuning.end_size >= 3.0,"Peak smoke is dense, substantially larger and more opaque")
	core.cycle_tick = 0; core.tick_credit = 0; core.step(0.04)
	check(core.smoke.tuning.emission_rate == 2.0,"Smoke falls back to a quieter plume between periodic eruptions")
	game.camera.global_transform = camera_pose
	if not core.rocks.is_empty(): core.rocks.front().free()
	var expired := AudioStreamPlayer3D.new(); core.add_child(expired); core.audio.append(expired); expired.free()
	core._erupt(false,true); core._erupt(true,true)
	core.step(0.04)
	check(core.rocks.all(func(rock: Variant) -> bool: return is_instance_valid(rock)) and core.audio.all(func(sound: Variant) -> bool: return is_instance_valid(sound)),"Freed debris and finished audio cannot interrupt later eruption cycles")
	check(core.rocks.size() >= 2 and core.smoke.puffs.size() >= 2,"Eruption produces real rock bodies and original smoke")
	var bursts := core.get_children().filter(func(node: Node) -> bool: return node is Burst)
	check(not bursts.is_empty() and bursts.all(func(effect: Node3D) -> bool: return effect.spill_over and is_equal_approx(effect.global_position.y,position.y+2.0)),"Volcano flashes clear the highest crater lip above the lower smoke and bubbles")
	if not bursts.is_empty():
		var flash: Node3D = bursts.back(); flash._process(0.55)
		check(flash.lobes.any(func(lobe: Dictionary) -> bool: return not lobe.upward and lobe.node.visible and lobe.node.position.y < flash.size*0.15 and lobe.node.global_position.y > position.y+1.9 and Vector2(lobe.node.position.x,lobe.node.position.z).length() > flash.size),"Spilling fire stays near the mouth instead of sinking through the volcano sides")
		check(flash.lobes.filter(func(lobe: Dictionary) -> bool: return lobe.upward).size() == 2 and flash.lobes.any(func(lobe: Dictionary) -> bool: return lobe.upward and lobe.node.visible and lobe.node.position.y > flash.size and Vector2(lobe.node.position.x,lobe.node.position.z).is_zero_approx()),"Two staggered fire bursts rise straight up from the crater")
	var small: Node3D = core.rocks[-2]; var large: Node3D = core.rocks[-1]
	check(small.get_child(0).get_meta("asset_source","").contains("SMALROCK") and large.get_child(0).get_meta("asset_source","").contains("ROCK"),"Both original eruption rock models are used")
	check(small.mass == 10 and small.linear_velocity.y > 0 and not small.get_meta("grapple_tow_target"),"Rocks launch upwards with original mass and no collectible salvage")
	check(core.sounds.values().all(func(stream: AudioStream) -> bool: return stream != null),"Original eruption and blast sounds load")
	for i in range(50): core._erupt(false,false)
	check(core.rocks.size() <= core.ROCK_LIMIT and core.audio.size() <= 12 and core.smoke.puffs.size() <= core.smoke.CAPACITY,"Effects and physical debris have fixed budgets")
	for rock in core.rocks: rock.queue_free()
	await physics_frame; await physics_frame
	core.rocks.clear()

	# Exercise the actual launcher, inherited momentum, ordinary fuse/collider
	# and the real world crater, rather than calling only the mission callback.
	game.pilot.global_transform = Transform3D(Basis.IDENTITY,position+Vector3.UP*3)
	game.pilot.reset_physics_interpolation(); game.pilot.pending_reset = false
	var tools: Node3D = game.equipment.support_tools
	tools.depth_cooldown = 0; tools.fire_depth(true)
	check(tools.projectiles.size() == 1 and game.player_progress.hold.depth == 7,"Actual equipped launcher drops one normal charge")
	var charge: Node3D = tools.projectiles[0]
	check(charge is Charge and charge.entered_vent == null,"Open crater does not bypass terrain or extend fuse")
	for frame in range(150):
		if not is_instance_valid(charge): break
		await physics_frame
	check(core.hits == 1 and core.health < 10,"Normal falling charge reaches and damages the core in the real crater")
	game.pilot.global_position = position+Vector3.UP*10
	# Complete remaining hits at a normal core-surface blast distance.
	while core.hits < 6: core.depth_charge_from(0,position+Vector3.UP,Vector3.ZERO)
	core.step(0.12)
	check(core.dead and core.health < 0 and heard("n15") and heard("n20") and heard("n11"),"Six valid hits shut down with original progress and hit lines")
	check(runtime.target_marker.target_body() == null and not core.smoke.enabled,"Inactive volcano stops guidance and emissions")
	check(not runtime.active().is_empty() and game.player_progress.status.credits == 10000,"No premature completion at final hit")
	core.step(0.28)
	check(heard("n9") and not runtime.active().is_empty(),"Seismic confirmation after 0.4 seconds")
	core.step(6.39)
	check(not runtime.active().is_empty(),"Original confirmation delay remains before payout")
	core.step(0.01)
	check(runtime.active().is_empty() and heard("n10") and game.player_progress.status.credits == 14000,"Completes at volcano after 6.8 seconds and pays exactly 4000")
	check(game.player_progress.missions.completed.fumehole.success and game.player_progress.missions.stage3_successes == 1,"Original stage-three progress recorded")
	core.step(10)
	check(game.player_progress.status.credits == 14000,"Repeated callbacks cannot pay twice")
	await physics_frame; await physics_frame
	check(get_nodes_in_group("depth_charge_vents").is_empty(),"Mission completion removes core, heat and effects")

	core = await fresh("fumehole2")
	check(core.global_position.is_equal_approx(position),"Tryton variant uses the same original volcano")
	core.depth_charge_from(0,position,Vector3.ZERO)
	for i in range(2): core.depth_charge_from(0,position+Vector3.UP,Vector3.ZERO)
	core.step(0.12)
	check(core.progress == 2 and heard("n12"),"Health-based almost-there report uses original threshold")
	while not core.dead: core.depth_charge_from(0,position+Vector3.UP,Vector3.ZERO)
	core.step(6.8)
	check(game.player_progress.missions.completed.fumehole2.success and game.player_progress.status.credits == 14000,"Tryton variant also completes through standard reward flow")
	core = await fresh("fumehole2")
	core._erupt(true,true)
	runtime.finish(false)
	await physics_frame; await physics_frame
	check(get_nodes_in_group("depth_charge_vents").is_empty() and jobs.volcano == null,"Failure/cancellation cleans all volcano-owned actors")
	core = await fresh("fumehole")
	jobs.docked(2)
	check(not runtime.active().is_empty(),"Returning to a dock cannot complete an active volcano")
	core.depth_charge_from(0,core.global_position,Vector3.ZERO)
	core.depth_charge_from(0,core.global_position,Vector3.ZERO)
	check(core.dead and core.hits == 2,"Sufficient blast damage can stop the core before the six-hit cap, as in retail")
	runtime._cleanup(); await physics_frame; await physics_frame
	core = await fresh("fumehole2")
	game.pilot.global_position = core.global_position+Vector3.UP
	game.pilot.health = 0.01
	core.step(0.04)
	check(game.pilot.dead and runtime.active().is_empty() and jobs.volcano == null,"Fatal heat uses standard player death and safely cleans mission during its tick")
	await physics_frame; await physics_frame
	check(get_nodes_in_group("depth_charge_vents").is_empty(),"No lingering hazard after player death")
	game.free(); await process_frame
	print("Volcanic Disaster: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
