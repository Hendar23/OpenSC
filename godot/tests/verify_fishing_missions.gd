extends "res://tests/verify_stage_two_missions.gd"

func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-fishing-fixtures"; storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var config := ConfigFile.new(); config.set_value("game","folder",ProjectSettings.globalize_path("res://../Original Sub Culture")); config.save(storage.preferences_path())
	call_deferred("run")

func accept_fishing(city: int) -> String:
	preload("res://mission_survivors.gd").clear(game.submarine_traffic)
	fresh(); port(city)
	game.player_progress.missions.completed["breakout" if city == 2 else "spytrad2"] = {"success":true,"city":city}
	return runtime.accept(city)

func collect_one(state: Dictionary, body: Node3D) -> void:
	body.global_position = state.agent.get_parent().to_global(Vector3(0,-1.5,0))
	body.set_physics_process(false)
	var fishing: RefCounted = jobs.fishing
	for step in range(12):
		fishing.capture_clock = 0; fishing.step(0.05)
		if body.dead: break
	check(body.dead,"Real fish enters the stun cone, is pulled aboard, and is counted once")

func fill(state: Dictionary) -> void:
	var fishing: RefCounted = jobs.fishing
	for body in fishing.fish.duplicate():
		if is_instance_valid(body) and not body.dead and not state.returning: collect_one(state,body)
	check(state.count == 12 and state.returning,"Twelve physical catches fill the hold and start the return route")

func return_herder(state: Dictionary, local: bool = false) -> void:
	var agent: Node3D = state.agent
	check(not is_finite(agent.travel_height),"Full herder releases its fishing height for normal navigation and docking")
	if local:
		agent.set_local_simulation(true); agent.set_physics_process(false)
		for frame in range(1800):
			agent.advance(0.1)
			if state.resolved:
				check(agent.stage == "berth","Local herder clears terrain and the dock's physical collision, opens the door and unloads")
				return
			await physics_frame
		check(false,"Local herder clears terrain and the dock's physical collision, opens the door and unloads")
		return
	agent.set_local_simulation(false)
	for step in range(1600):
		agent.advance_abstract(0.25)
		if state.resolved: break
	check(state.resolved and agent.stage == "berth","Returning herder follows the actual navigation route and docks without the player docking")

func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	while not game.startup_complete: await process_frame
	game._begin_new_game(); game.pilot.freeze = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false)
	game.set_process(false); game.set_physics_process(false); game.world_root.get_node("ActorActivity").set_physics_process(false)
	runtime = game.mission_runtime; jobs = runtime.side_jobs; jobs.set_physics_process(false)
	while not game.submarine_traffic.navigation_ready: game.submarine_traffic.build_graph(128); await process_frame
	var original_npcs: int = game.submarine_traffic.traders.size()
	fresh(); port(2)
	check(runtime.board(2).id == "breakout","Velcova fishing remains behind its prisoner rescue")
	game.player_progress.missions.completed["breakout2"] = {"success":true,"city":4}
	check(runtime.board(2).id == "fishing","Resolving the paired Tryton rescue also advances Velcova to fishing")
	for entry in [[2,3140,"fishing","breakout"],[3,2970,"bigherd","spytrad2"]]:
		fresh(); port(entry[0]); game.player_progress.missions.completed[entry[3]] = {"success":false}
		game.player_progress.status.credits = entry[1]-1
		check(not runtime.board(entry[0]).available,"Fishing requires the original owned-or-affordable Attractatron gate")
		game.player_progress.status.credits += 1
		check(runtime.board(entry[0]).available and runtime.board(entry[0]).id == entry[2],"Exact local equipment price reveals the correct fishing job")
		var offer: Dictionary = Shop.offer(game.gameplay_catalogue,str(entry[0]),2,"attract")
		check(offer.available and offer.price == entry[1] and offer.slot == 8,"Original Attractatron city price and mounting slot")
		check(Shop.buy(game.player_progress,offer).is_empty() and game.player_progress.hold.attract == 1,"Attractatron can be bought into the hold")
		check(runtime.board(entry[0]).available,"Owned Attractatron permits acceptance without extra credits")
		check(Shop.swap(game.player_progress,game.equipment,game.weapons,8,"attract").is_empty() and Shop.installed(game.equipment,game.weapons)[8] == "attract","Attractatron mounts in slot eight through normal equipment swapping")
		var snapshot: Dictionary = game._save_snapshot("Attractatron round trip")
		check(game.save_games.write(6,snapshot) == OK and game.save_games.read(6).equipment.any(func(item: Dictionary) -> bool: return item.id == "attract"),"Installed Attractatron round-trips through the published beta save format")
		check(not Shop.offer(game.gameplay_catalogue,"1",2,"attract").available and Shop.offer(game.gameplay_catalogue,"4",2,"attract").price == 2710,"Stage-two stock remains unavailable at Touka and uses Tryton's original price")
		game.dock_interface.open("equipment"); game.dock_interface.rebuild()
		check(game.dock_interface.slot_buttons[4].get_meta("slot") == 8 and game.dock_interface.slot_buttons[4].get_child_count() > 0,"Shop displays the installed Attractatron in the original-position grid")
		game.dock_interface.dismiss()
	fresh(); port(3); game.player_progress.missions.completed["spytrad"] = {"success":true,"city":1}
	check(runtime.board(3).id == "bigherd","Touka's completed covert variant advances the paired Beluga queue")
	check(accept_fishing(2).is_empty(),"Accept Defend Fishing Grounds at Velcova")
	if jobs.fishing == null: quit(1); return
	var fishing: RefCounted = jobs.fishing
	var state: Dictionary = fishing.herders[0]
	check(fishing.herders.size() == 1 and fishing.fish.size() == 20 and state.agent.get_parent().get_meta("editor_model") == "TECHHERD","Retail Velcova encounter has one Procha herder and twenty silverbacks, overriding the database's draft clump names")
	check(not runtime.can_save() and runtime.target_marker.target_body() == state.agent.body,"Fishing blocks saving and gives the herder its green HUD target")
	check(not game.submarine_traffic.route(state.agent.global_position,fishing.field).is_empty(),"Original outbound herding route is navigable")
	for agent in jobs.vessels: agent.set_physics_process(false)
	for body in fishing.fish: body.set_physics_process(false)
	var began: Vector3 = state.agent.global_position
	for frame in range(120): state.agent.advance(1.0/60.0); await physics_frame
	check(state.agent.global_position.distance_to(began) > 0.2,"Procha herder physically travels toward the ribs rather than standing still")
	check(absf(state.agent.global_position.y-began.y) < 0.01 and is_equal_approx(fishing.field.y,began.y),"Outbound fishing route stays at the ship's starting height")
	state.agent.motion.velocity = Vector3.DOWN
	var worst_height_error := 0.0
	for frame in range(120):
		game.pilot.global_position = state.agent.global_position+Vector3(0,0.4,1)
		state.agent.advance(0.05); await physics_frame
		worst_height_error = maxf(worst_height_error,absf(state.agent.global_position.y-began.y))
	check(worst_height_error < 0.01,"Close player avoidance and leftover downward momentum cannot make the herder dive")
	state.agent.set_local_simulation(false); state.agent.path.clear()
	for step in range(120): state.agent.advance_abstract(0.25)
	check(absf(state.agent.global_position.y-began.y) < 0.01,"Offscreen travel preserves the same fishing height")
	state.agent.set_local_simulation(true); state.agent.set_physics_process(false)
	# Exercise the attractor using real fish steering in open water, apart from
	# the capture cone, to distinguish attraction from forced collection.
	game.equipment.set_installed(["attract"]); game.equipment.selected = 0
	var attractor: Node3D = game.equipment.support_tools.attractatron
	var tool: Dictionary = game.equipment.current()
	var silver: Node3D = fishing.fish[0]
	silver.global_position = Vector3(10000,-10,10004.5); silver.home = silver.global_position
	silver.bounds = AABB(Vector3(9900,-100,9900),Vector3(200,200,200)); silver.surface_height = 50
	silver.direction = Vector3.RIGHT; silver.turn_speed = 360; silver.group_behaviour = "solitary"
	game.pilot.global_position = Vector3(10000,-10,10000); game.pilot.global_basis = Basis.IDENTITY
	game.docking.stage = game.Docking.Stage.IDLE; game.pilot.active = true; game.pilot.controls_enabled = true
	game.equipment.toggle_selected()
	check(attractor.enabled and tool.enabled and game.cockpit_hud.displays[1].equipment_icon_index(tool) == 0,"Normal input enables Attractatron and displays ATTRON")
	check(tool.icons.size() == 2 and tool.icons[0] != null and tool.icons[1] != null and attractor.audio.stream != null,"Original ATTRON/ATTROFF artwork, housing and sound load")
	var before: float = silver.global_position.distance_to(game.pilot.global_position)
	silver.set_physics_process(true)
	for frame in range(90):
		attractor.clock = 0; attractor._physics_process(1.0/60.0); await physics_frame
	check(silver.global_position.distance_to(game.pilot.global_position) < before-0.3,"Attractatron turns a real swimming silverback toward the player without teleporting it")
	check(attractor.affected.size() <= 7 and silver.attraction_remaining > 0,"Original field applies to at most seven nearby fish")
	game.equipment.toggle_selected()
	check(not attractor.enabled and silver.attraction_remaining == 0 and game.cockpit_hud.displays[1].equipment_icon_index(tool) == 1,"Switching off clears attraction and shows ATTROFF")
	var nearby: Array = fishing.fish.slice(0,10)
	for index in nearby.size():
		nearby[index].global_position = game.pilot.global_position + Vector3((index-4.5)*0.2,0,4.0)
		nearby[index].set_physics_process(true); nearby[index].attraction_remaining = 0
	game.equipment.toggle_selected(); attractor.clock = 0; attractor._physics_process(0.04)
	check(attractor.affected.size() == 7 and nearby.filter(func(body: Node3D) -> bool: return body.attraction_remaining > 0).size() == 7,"A ten-fish shoal respects the original seven-fish field limit")
	game.equipment.toggle_selected()
	for body in nearby: body.set_physics_process(false)
	silver.set_physics_process(false)
	game.pilot.global_position = state.agent.global_position + Vector3(20,0,0)
	jobs.age = 2; game.pilot.global_position = state.agent.global_position+Vector3(2,0,0); fishing.step(0)
	check(fishing.greeted,"Approaching the Procha herder schedules its guidance")
	fishing.step(19.99); check(not game.bounty_radio_queue.any(func(message: Dictionary) -> bool: return message.text == game.gameplay_catalogue.tables.radio_messages.records.u2.text),"Original herding instruction preserves its twenty-second delay")
	fishing.step(0.02); check(not game.bounty_radio_queue.is_empty() and game.bounty_radio_queue.back().text == game.gameplay_catalogue.tables.radio_messages.records.u2.text and runtime.speech.stream != null,"Original U2 speech and portrait are sent with the instruction")
	await capture("fishing",state.agent)
	var herder: Node3D = state.agent
	var fishing_route := PackedVector3Array([fishing.field])
	herder.path = fishing_route.duplicate(); herder.wait = 0.4
	var shields: float = herder.health.remaining
	herder.take_weapon_damage_from(1,herder.global_position + Vector3.DOWN,game.pilot)
	check(herder.health.remaining < shields and herder.path == fishing_route and herder.wait == 0.4 and herder.flee == 0,"A hit damages the fishing ship without clearing its route or starting evasive orders")
	herder.health.remaining = shields; herder.wait = 0; state.player_warning = false
	var fishing_pose: Transform3D = herder.get_parent().global_transform
	herder.path.clear(); herder.waypoint = herder.waypoints.size(); herder.motion.velocity = Vector3.ZERO
	herder.get_parent().global_basis = Basis(Vector3.RIGHT,deg_to_rad(65))
	var stopped_at: Vector3 = herder.global_position
	for step in range(120): herder._advance_motion(0.05)
	check(absf(herder.get_parent().global_basis.z.y) < 0.01 and herder.global_position.distance_to(stopped_at) < 0.01,"An idle herder levels out without diving or evading")
	herder.get_parent().global_transform = fishing_pose; herder.waypoint = 0; herder.path.clear()
	for index in range(6): collect_one(state,fishing.fish.filter(func(body: Node3D) -> bool: return is_instance_valid(body) and not body.dead)[0])
	check(state.count == 6 and fishing.first_wave and fishing.enemies.size() == 2,"Half-full Procha herder announces six fish and spawns two Bohine attackers")
	check(fishing.enemies[0].engage_player and fishing.enemies[1].combat_target == state.agent.body and fishing.enemies[1]._nearest_target() == state.agent.body,"One Bohine attacker targets the player and one targets the herder")
	var enemy: Node3D = fishing.enemies[1]; enemy.set_local_simulation(false)
	var enemy_before: Vector3 = enemy.global_position
	var target_shields: float = state.agent.health.remaining
	for step in range(720): enemy.advance_abstract(0.25)
	check(enemy.global_position.distance_to(enemy_before) > 1 and enemy.global_position.distance_to(state.agent.body.global_position) < 6.1,"Offscreen attackers complete the journey from their city to fighting distance, without oscillating at graph anchors")
	check(state.agent.health.remaining == target_shields,"Offscreen approach does not fire or apply hidden damage")
	enemy.set_local_simulation(true)
	enemy.set_physics_process(false)
	var herder_pose: Transform3D = state.agent.get_parent().global_transform
	var enemy_pose: Transform3D = enemy.get_parent().global_transform
	state.agent.get_parent().global_position = Vector3(10020,-10,10000)
	enemy.get_parent().global_transform = Transform3D(Basis(Vector3.UP,PI),Vector3(10020,-10,10005.5))
	enemy.victim = state.agent.body; enemy.cooldown = 0; enemy.motion.velocity = Vector3.ZERO
	await physics_frame; await physics_frame
	var health_before: float = state.agent.health.remaining
	enemy._advance_motion(0.02)
	for frame in range(120):
		await physics_frame
		if state.agent.health.remaining < health_before: break
	check(state.agent.health.remaining < health_before and state.under_attack,"A mission attacker's real missile hits the herder and triggers its under-attack radio call")
	state.agent.health.remaining = health_before; state.agent.get_parent().global_transform = herder_pose
	enemy.get_parent().global_transform = enemy_pose; enemy.motion.velocity = Vector3.ZERO
	fill(state)
	check(fishing.second_wave and fishing.enemies.size() == 4 and fishing.enemies[2].get_parent().get_meta("editor_model") == "TRAD-SUB","Full Procha hold triggers the second Bohine attack wave")
	check(state.agent.dock_destination == 2 and not state.cone.visible,"Full herder retracts its field and returns to Velcova")
	var attackers: Array[Node3D] = fishing.enemies.duplicate()
	await return_herder(state,true)
	check(runtime.can_save() and game.player_progress.missions.completed.fishing.success and game.player_progress.status.credits == 103000,"Herder docking completes fishing immediately and pays 3,000 credits")
	check(runtime.speech.stream != null and game.bounty_radio_queue.back().text == game.gameplay_catalogue.tables.radio_messages.records.u9.text,"Velcova's original completion speech plays without the player docking")
	check(attackers.all(func(agent: Node3D) -> bool: return is_instance_valid(agent) and not agent.dead and agent.running and game.submarine_traffic.traders.has(agent) and agent.mission_owner.is_empty() and not agent.get_parent().is_queued_for_deletion()),"Surviving Bohine attackers remain the same live world actors after completion")
	check(attackers.all(func(agent: Node3D) -> bool: return agent.engage_player and agent.combat_target == null and agent.has_meta("fishing_survivor")),"Remaining attackers can fight the player without retaining removed herder targets")
	for agent in attackers: agent.set_physics_process(false)
	attackers[0].health.remaining = 4.25
	port(2)
	var aftermath: Dictionary = game._save_snapshot("Fishing survivors")
	var identities: Array = attackers.map(func(agent: Node3D) -> String: return preload("res://entity_identity.gd").of(agent))
	check(game.save_games.write(5,aftermath) == OK and await game._load_saved_game(5),"Completed fishing encounter saves and loads through the real beta loader")
	var restored: Array = game.submarine_traffic.traders.filter(func(agent: Node3D) -> bool: return agent.has_meta("fishing_survivor"))
	check(restored.size() == 4 and restored.all(func(agent: Node3D) -> bool: return preload("res://entity_identity.gd").of(agent) in identities and agent.engage_player and not agent.dead),"Saved attackers are recreated with stable identities and hostility")
	check(restored.all(func(agent: Node3D) -> bool:
		var entry: Dictionary = aftermath.submarine_traffic[preload("res://entity_identity.gd").of(agent)]
		return is_equal_approx(agent.health.remaining,entry.health) and agent.get_parent().global_transform.is_equal_approx(preload("res://map_document.gd").decode(entry.pose)) and agent.get_parent().get_meta("editor_model") == entry.fishing_survivor),"Reload preserves each survivor's original model, damage and world pose")
	var invalid: Dictionary = aftermath.submarine_traffic.duplicate(true)
	invalid[identities[0]].fishing_survivor = "PIRATE3"
	check(not game.submarine_traffic.valid_snapshot(invalid),"Dynamic survivor restore only accepts the fishing encounter's allowed vessel models")
	var killed: Node3D = restored[0]
	killed.take_weapon_damage_from(10000,game.pilot.global_position,game.pilot)
	game.submarine_traffic.replenish_docked(1)
	check(killed.dead and not killed.get_parent().visible,"Destroyed mission survivors do not respawn as docked ambient traffic")
	check(game.player_progress.status.credits == 103000,"Faction attackers do not award roaming-pirate bounties")
	game._begin_new_game(); game.pilot.freeze = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false)
	check(game.submarine_traffic.traders.size() == original_npcs,"New game removes retained encounter ships instead of carrying them into a fresh world")
	await process_frame
	check(accept_fishing(3).is_empty(),"Accept Protect Beluga Trawlers at Beluga")
	fishing = jobs.fishing
	check(fishing.herders.size() == 3 and fishing.fish.size() == 50 and fishing.herders.all(func(ship: Dictionary) -> bool: return ship.agent.get_parent().get_meta("editor_model") == "TRADHERD"),"Beluga spawns three original Bohine herders and fifty silverbacks")
	check(fishing.herders.all(func(ship: Dictionary) -> bool: return ship.agent.propellers.size() == 2),"Both original Bohine herder propellers are registered for movement-driven animation and wakes")
	for ship in fishing.herders:
		var height: float = ship.agent.global_position.y
		ship.agent.motion.velocity = Vector3.DOWN; ship.agent._flow_move(0.05,Vector3.DOWN,1.2)
		check(is_equal_approx(ship.agent.travel_height,height) and absf(ship.agent.global_position.y-height) < 0.01,"Each Beluga herder holds its own starting height while fishing")
	for agent in jobs.vessels: agent.set_physics_process(false)
	for body in fishing.fish: body.set_physics_process(false)
	state = fishing.herders[0]
	jobs.age = 10; game.pilot.global_position = state.agent.global_position+Vector3(2,0,0); fishing.step(0)
	check(fishing.greeted and fishing.enemies.size() == 3 and fishing.herders.all(func(ship: Dictionary) -> bool: return ship.cone.visible),"Joining the Bohine fleet starts fishing and the first three-ship Procha attack")
	check(fishing.enemies.all(func(ship: Node3D) -> bool: return ship._valid_target(ship.combat_target) and not ship.engage_player),"Procha mission attackers target the herders instead of starting global faction combat")
	await capture("bigherd",state.agent)
	fill(state); return_herder(state)
	check(not runtime.can_save() and fishing.delivered == 1,"One unloaded Bohine herder does not finish while two remain at sea")
	var beluga_attackers: Array[Node3D] = fishing.enemies.duplicate()
	for other in fishing.herders:
		if not other.resolved: other.agent.take_weapon_damage_from(10000,game.pilot.global_position,game.pilot)
	check(runtime.can_save() and game.player_progress.missions.completed.bigherd.success and is_equal_approx(game.player_progress.missions.completed.bigherd.score,1.0/3.0) and game.player_progress.status.credits == 103500,"Beluga partial survival succeeds with its original one-third score and fixed 3,500-credit reward")
	check(beluga_attackers.all(func(agent: Node3D) -> bool: return is_instance_valid(agent) and not agent.dead and agent.has_meta("fishing_survivor") and game.submarine_traffic.traders.has(agent)),"Surviving Procha attackers also remain after the Beluga mission resolves")
	await process_frame
	check(accept_fishing(3).is_empty(),"Recreate complete Beluga success case")
	fishing = jobs.fishing
	for agent in jobs.vessels: agent.set_physics_process(false)
	for body in fishing.fish: body.set_physics_process(false)
	jobs.age = 10; game.pilot.global_position = fishing.herders[0].agent.global_position; fishing.step(0)
	for other in fishing.herders.duplicate(): fill(other)
	check(fishing.second_wave and fishing.enemies.size() == 6,"All surviving trawlers filling their holds triggers the second three-ship Procha wave")
	for other in fishing.herders.duplicate(): return_herder(other)
	check(runtime.can_save() and game.player_progress.missions.completed.bigherd.score == 1.0 and game.player_progress.status.credits == 103500,"All three Bohine returns finish with full score and the fixed reward")
	await process_frame
	check(accept_fishing(2).is_empty(),"Recreate Procha loss case")
	fishing = jobs.fishing; state = fishing.herders[0]
	for index in range(6): collect_one(state,fishing.fish.filter(func(body: Node3D) -> bool: return is_instance_valid(body) and not body.dead)[0])
	var failure_attackers: Array[Node3D] = fishing.enemies.duplicate()
	var wrecks_before: int = get_nodes_in_group("trader_wrecks").size()
	var effect_material: Material = state.cone.material_override
	state.agent.take_weapon_damage_from(10000,game.pilot.global_position,game.pilot)
	var wrecks := get_nodes_in_group("trader_wrecks")
	check(wrecks.size() == wrecks_before+1 and not wrecks.back().pieces.is_empty(),"Destroyed fishing ship still produces real hull debris")
	check(wrecks.back().pieces.all(func(piece: Dictionary) -> bool: return piece.material == null or not piece.material is StandardMaterial3D or piece.material.albedo_color != effect_material.albedo_color),"Blue vacuum field contributes no fragments to the destroyed ship")
	check(not runtime.can_save() and fishing.failed_clock == 6,"Procha loss speech starts before the separate six-second failure report")
	fishing.step(6)
	check(runtime.can_save() and not game.player_progress.missions.completed.fishing.success and game.player_progress.status.credits == 100000,"Destroyed Procha herder fails without paying a reward")
	check(failure_attackers.size() == 2 and failure_attackers.all(func(agent: Node3D) -> bool: return is_instance_valid(agent) and not agent.dead and agent.has_meta("fishing_survivor") and game.submarine_traffic.traders.has(agent)),"Live Bohine attackers remain after mission failure as well as success")
	await process_frame
	check(accept_fishing(3).is_empty(),"Recreate complete Beluga loss case")
	fishing = jobs.fishing
	for other in fishing.herders: other.agent.take_weapon_damage_from(10000,game.pilot.global_position,game.pilot)
	check(runtime.can_save() and not game.player_progress.missions.completed.bigherd.success and game.player_progress.status.credits == 100000,"Losing all three Bohine herders fails without reward")
	fresh(); await process_frame
	check(game.submarine_traffic.traders.filter(func(agent: Node3D) -> bool: return not agent.has_meta("fishing_survivor")).size() == original_npcs and root.get_tree().get_nodes_in_group("attractable_fish").all(func(body: Node3D) -> bool: return body.mission_owner.is_empty()),"Mission cleanup removes objective boats, fish, targets and reservations while preserving surviving attackers")
	game.queue_free(); await process_frame
	print("Fishing missions: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
