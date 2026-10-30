extends "res://tests/test_scene_tree.gd"
const Document = preload("res://map_document.gd")
const Damage = preload("res://original_damage.gd")
const Motion = preload("res://npc_sub_motion.gd")
var game: Node
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var storage = preload("res://player_storage.gd")
	storage.root_override = "res://tests/cache-original-fidelity-fixtures"
	storage.ensure_parent(storage.preferences_path())
	var ignore := FileAccess.open(storage.root_override.path_join(".gdignore"),FileAccess.WRITE); ignore.store_string("")
	var config := ConfigFile.new(); config.set_value("game","folder",OS.get_environment("OPENSC_TEST_GAME_FOLDER")); config.save(storage.preferences_path())
	call_deferred("run")
func run() -> void:
	game = preload("res://game.gd").new(); game.remember_preferences = false; root.add_child(game)
	for frame in range(4000):
		if game.startup_complete: break
		await process_frame
	check(game.startup_complete,"World starts for original fidelity checks")
	if not game.startup_complete: quit(1); return
	game.set_process(false)
	var audio: Node = game.world_root.get_node("AmbientSounds"); audio.set_physics_process(false)
	check(not audio.allowed() and audio.voices.is_empty(),"Outdoor sounds remain silent before a session starts")
	check(audio.streams.size() == 7 and audio.streams.values().all(func(stream: AudioStream) -> bool: return stream != null),"Recovered ambient and engine samples decode before gameplay")
	check(audio.vessel_sample("TECHSHUT",2) == "INSUB2" and audio.vessel_sample("TRADSHUT",1) == "INSUB2" and audio.vessel_sample("CARAVAN",1) == "TECHENG" and audio.vessel_sample("PIRATE",3) == "PIRATENG","Recovered per-model engine sounds override generic faction fallback")
	game._begin_new_game(); game.front_end.menu_layer.hide(); game.loading_canvas.hide()
	game.pilot.freeze = true; game.pilot.set_physics_process(false); game.docking.set_physics_process(false)
	var stats: Dictionary = game.gameplay_catalogue.tables.creature_stats.records
	for row in [["angel",10,2.5,0.05],["silver",10,2.5,0.05],["crab",1,0.1,0.1],["mutant",10,0.25,1],["thorium",1,0.05,0.0006],["pirate",30,0.3,0.5],["technew",15,0.3,0.5],["trad-sub",10,0.3,0.5]]:
		check(is_equal_approx(stats[row[0]].health,row[1]) and is_equal_approx(stats[row[0]].sustain,row[2]) and is_equal_approx(stats[row[0]].inflict,row[3]),"Imported retail health / sustain / inflict: "+row[0])
	check(Document.creature_health({"model":"silver"},game.gameplay_catalogue) == 10,"Unmodified wildlife health has no hidden multiplier")
	var document := Document.load_path(Document.DEFAULT_PATH)
	for species in document.species:
		if not stats.has(str(species.model).to_lower()): continue
		check(is_equal_approx(species.health,stats[str(species.model).to_lower()].health),"Authored map uses original health: "+str(species.id))
	for object in document.object_types:
		if object.id in ["thorium","inert_thorium"]: check(object.health == 1,"Map crystal durability restored: "+str(object.id))
	check(preload("res://player_projectile.gd").TORPEDO_DAMAGE_MULTIPLIER == 1,"Player torpedo raw impact strength has no extra balance multiplier")
	var motion := Motion.new(); motion.turn_rate = Motion.COMBAT_TURN_RATE; motion.turn_response = Motion.COMBAT_TURN_RESPONSE
	var pose := Basis.IDENTITY; motion.velocity = Vector3.BACK*2
	for tick in range(30): pose = motion.step(1.0/60,Vector3.RIGHT,2,2,pose)
	check(pose.z.angle_to(Vector3.RIGHT) < deg_to_rad(20) and motion.velocity.length() > 1,"Combat hull turns briskly while retaining forward motion")
	for hull in ["PIRATE","TRAD2","TECH2SUB","FREIGHT"]:
		var model: Node3D = Document.load_model(hull,game.game_folder); game.world_root.add_child(model)
		var agent: Node3D = preload("res://trader_submarine.gd").install(model,{})
		check((agent.motion.turn_rate == Motion.COMBAT_TURN_RATE) == (hull != "FREIGHT"),"Combat turning is applied to the actual hull, retaining freighter handling: "+hull)
		model.free()
	var pirate := preload("res://pirate_submarine.gd").new()
	check(pirate.health_multiplier() == 1,"Pirates have no doubled health multiplier"); pirate.free()
	# Recovered fish contact applies inflict, speed, hull and sustain once.
	var fish := preload("res://fish_controller.gd").new()
	fish.setup(Node3D.new(),Vector3.ZERO,AABB(Vector3(-100,-100,-100),Vector3.ONE*200),100,0.2,42)
	game.world_root.add_child(fish)
	fish.population = game.wildlife; fish.configure_combat({"model":"piranha"}); fish.set_physics_process(false)
	fish.global_position = game.pilot.global_position+Vector3.RIGHT; fish.velocity = Vector3.LEFT*2
	check(is_equal_approx(fish.submarine_contact_damage(Vector3.ZERO,Vector3.LEFT),Damage.object_contact(2,0.5)),"Wildlife contact uses recovered relative-closing formula")
	fish.velocity = Vector3.RIGHT*2
	check(fish.submarine_contact_damage(Vector3.ZERO,Vector3.LEFT) == 0,"Separating fish cannot damage the player"); fish.free()
	# Real sources and voice selection, independent of the authored scenery.
	var point := Vector3(10000,25,10000); game.pilot.global_position = point; game.camera.global_position = point
	game.pilot.active = true; game.pilot.controls_enabled = true; game.docking.stage = game.Docking.Stage.IDLE
	check(audio.allowed(),"Outdoor sound resumes during play")
	var bubbles := preload("res://bubble_stream.gd").new(); game.world_root.add_child(bubbles); bubbles.add_to_group("ambient_bubbles"); bubbles.global_position = point+Vector3.RIGHT
	audio.refresh()
	check(audio.voices.has(bubbles.get_instance_id()) and audio.voices[bubbles.get_instance_id()].stream == audio.streams.BUBBLES,"Nearby bubble stream plays its original source sound")
	var voice: Node = audio.voices.get(bubbles.get_instance_id()); audio.refresh()
	check(audio.voices.get(bubbles.get_instance_id()) == voice,"Ambient updates reuse the current audio voice")
	bubbles.global_position += Vector3.RIGHT*8; audio.refresh()
	check(not audio.voices.has(bubbles.get_instance_id()),"Bubble sound ends outside the recovered 7.5-unit hearing range")
	var npc_model: Node3D = Document.load_model("CARAVAN",game.game_folder); game.world_root.add_child(npc_model); npc_model.global_position = point
	var npc: Node3D = preload("res://trader_submarine.gd").install(npc_model,{"npc_faction":2})
	npc.system = game.submarine_traffic; npc.reset(); npc.running = true; npc.set_physics_process(false); game.submarine_traffic.traders.append(npc)
	audio.refresh()
	var engine: AudioStreamPlayer3D = audio.voices[npc.get_instance_id()]
	check(engine.stream == audio.streams.TECHENG and is_equal_approx(db_to_linear(engine.volume_db),0.1875),"Prototype retains its quieter engine gain beneath the halved ambient level")
	game.camera.global_position = point+Vector3.LEFT*20; audio.refresh()
	check(audio.voices.get(npc.get_instance_id()) == engine and is_equal_approx(db_to_linear(engine.volume_db),0.1875),"Third-person camera offset cannot silence an engine beside the player's hull")
	npc_model.global_position = point+Vector3.RIGHT*3.75; audio.clock = 0.1; audio._physics_process(1.0/60.0)
	check(is_equal_approx(db_to_linear(engine.volume_db),0.09375) and audio.clock > 0,"NPC engine position and smooth distance gain update between source scans")
	npc_model.global_position = point+Vector3.RIGHT*7.49; audio.refresh()
	check(audio.voices[npc.get_instance_id()] == engine and engine.volume_db < -70,"NPC engine fades to inaudible before its hearing boundary without restarting the loop")
	npc_model.global_position = point+Vector3.RIGHT*8; audio.refresh()
	check(not audio.voices.has(npc.get_instance_id()),"Inaudible engines release their voice outside the hearing range")
	npc_model.global_position = point+Vector3.RIGHT*7.49; audio.refresh()
	check(audio.voices[npc.get_instance_id()].volume_db < -70,"Approaching NPC engines begin quietly at the distance boundary")
	game.camera.global_position = npc_model.global_position; game.pilot.global_position = point+Vector3.LEFT*20; audio.refresh()
	check(not audio.voices.has(npc.get_instance_id()),"A camera near the prototype cannot keep its engine audible when the player's hull is distant")
	game.camera.global_position = point; game.pilot.global_position = point
	game.submarine_traffic.traders.erase(npc); npc_model.free(); audio.refresh()
	var factory := preload("res://drop_off_point.gd").new(); game.world_root.add_child(factory); factory.configure(0.5,6); factory.global_position = point+Vector3.RIGHT*20
	audio.refresh()
	check(audio.voices.has(factory.get_instance_id()),"Refinery hum plays at its original longer range")
	var hum: AudioStreamPlayer3D = audio.voices[factory.get_instance_id()]
	var middle_volume := hum.volume_db
	factory.global_position = point; audio.refresh()
	check(is_equal_approx(db_to_linear(hum.volume_db),0.375*db_to_linear(-0.01)),"Factory ambience is half its previous seventy-five-percent level")
	check(middle_volume < hum.volume_db,"Factory hum fades with distance instead of remaining at full volume until cutoff")
	factory.global_position = point+Vector3.RIGHT*5; audio.refresh(); var close_volume := hum.volume_db
	factory.global_position = point+Vector3.RIGHT*10; audio.refresh()
	check(close_volume < -8.529 and hum.volume_db < close_volume,"Refinery hum has no constant-volume inner plateau near the Defection rendezvous")
	game.pilot.global_position = point-Vector3.RIGHT*19
	audio.clock = 0.1; audio._physics_process(1.0/60.0)
	check(hum.volume_db < middle_volume and audio.clock > 0,"Factory fade follows the moving player between source-selection scans")
	game.pilot.global_position = point
	factory.global_position = point+Vector3.RIGHT*(audio.FACTORY_RANGE-0.1); audio.refresh()
	check(audio.voices[factory.get_instance_id()] == hum and hum.volume_db < -70,"Existing factory loop becomes inaudible before reaching its distance boundary")
	factory.global_position = point+Vector3.RIGHT*40; audio.refresh()
	check(not audio.voices.has(factory.get_instance_id()),"Refinery hum stops beyond its original range")
	game.loading_save = true; audio._physics_process(0.1)
	check(audio.voices.is_empty() and not audio.allowed(),"Loading silences ambient audio"); game.loading_save = false
	game.docking.stage = game.Docking.Stage.DOCKED
	check(not audio.allowed(),"Dock interiors silence outdoor ambience")
	factory.free(); bubbles.free()
	# Accept docking through the real controller; do not settle the rescue yet.
	var runtime: Node = game.mission_runtime; var jobs: Node = runtime.side_jobs
	runtime._cleanup(); game.player_progress.missions.active = {"id":"breakout","city":2,"refinery":false}
	jobs.id = "breakout"; jobs.phase = "return"; jobs.passengers = true
	game.equipment.support_tools.passengers = true
	var credits: int = game.player_progress.status.credits
	var port: Dictionary = game.submarine_traffic.port_by_id(2)
	game.docking.stage = game.Docking.Stage.IDLE; game.pilot.global_position = port.entry; game.pilot.global_basis = Basis.IDENTITY
	game.pilot.velocity = Vector3.ZERO; game.pilot.angular_velocity = Vector3.ZERO
	game.pilot.active = true; game.pilot.controls_enabled = true
	var cargo := RigidBody3D.new(); cargo.freeze = true; game.world_root.add_child(cargo)
	var starts: Array[int] = []
	game.docking.docking_started.connect(func() -> void: starts.append(1))
	for tool: Node3D in [game.equipment.magnet,game.equipment.grapple]:
		tool.target = cargo
		game.docking.update_approach()
		check(game.docking.nearby.is_empty() and not game.docking.message.contains("Do you want to dock?"),"Attached cargo suppresses docking prompt: "+tool.tool_id)
		check(not game.docking.request_docking() and game.docking.stage == game.Docking.Stage.IDLE,"Direct docking request refuses attached cargo: "+tool.tool_id)
		check(game.pilot.active and game.pilot.controls_enabled and game.pilot.collision_mask != 0 and preload("res://dock_access.gd").owner(port) != game.docking,"Refusal leaves flight controls, collision and berth reservation untouched: "+tool.tool_id)
		check(starts.is_empty() and not runtime.outcome.visible and not runtime.active().get("outcome_shown",false) and game.player_progress.status.credits == credits,"Blocked docking cannot trigger mission success or rewards: "+tool.tool_id)
		tool.target = null
		game.docking.update_approach()
		check(not game.docking.nearby.is_empty() and game.docking.message.contains("Do you want to dock?"),"Releasing cargo restores the docking prompt: "+tool.tool_id)
	game.equipment.magnet.target = cargo; cargo.queue_free()
	check(not game.docking.towing_cargo(),"Deleted cargo cannot leave a stale docking restriction")
	game.equipment.magnet.target = null
	check(game.docking.request_docking(),"Empty towing tools allow the real rescue return to dock")
	check(runtime.outcome.visible and runtime.active().get("outcome_shown",false),"Mission complete animation starts with accepted docking")
	check(not runtime.active().is_empty() and jobs.passengers and game.equipment.support_tools.passengers and game.player_progress.status.credits == credits,"Docking announcement leaves passengers and rewards unsettled until berth")
	runtime.outcome.age = 2.0; runtime.docking_started(2)
	check(runtime.outcome.age == 2.0,"Docking success is announced once")
	runtime.docked(2)
	check(runtime.active().is_empty() and game.player_progress.status.credits > credits and runtime.outcome.age == 2.0,"Berth settles the mission without restarting the animation")
	for path in ["res://ambient_sounds.gd","res://tests/verify_original_fidelity.gd"]:
		if not FileAccess.file_exists(path+".uid"):
			var file := FileAccess.open(path+".uid",FileAccess.WRITE); file.store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	game.queue_free(); await process_frame
	print("Original fidelity: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
