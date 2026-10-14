extends Node
## Retail opening job: SC.EXE 0046ae40, MISSORD / MISSION1 / REWARD1.
const IDS := {1:"tradetrad",3:"tradetrad2",2:"tradetech",4:"tradetech2"}
var game: Node
var spawned: Array[Node] = []
var pirate: Node3D
var last_response := ""
var outcome: CanvasLayer

func setup(context: Node) -> void:
	game = context
	process_mode = Node.PROCESS_MODE_PAUSABLE
	game.events.city_docked.connect(docked)
	game.events.session_started.connect(_session_started)
	outcome = preload("res://mission_outcome.gd").new(); game.add_child(outcome)

func active() -> Dictionary:
	return game.player_progress.missions.active

func can_save() -> bool:
	return active().is_empty()

func text(id: String, response: int = 0) -> String:
	var raw := str(game.gameplay_catalogue.get("tables",{}).get("mission_text",{}).get("records",{}).get(id,{}).get("text",""))
	if response == 0: raw = raw.get_slice("#response",0)
	else:
		var marker := "#response %d" % response
		raw = raw.get_slice(marker,1).get_slice("#response",0)
	return raw.replace("<p>","").replace("@",",").strip_edges()

func board(city: int) -> Dictionary:
	var available := int(game.player_progress.campaign_stage) == 1 and IDS.has(city) and active().is_empty()
	var id := str(IDS.get(city,""))
	var shown_id := str(active().id) if not active().is_empty() else id
	var row: Dictionary = game.gameplay_catalogue.get("tables",{}).get("mission_availability",{}).get("records",{}).get(shown_id,{})
	return {"available":available,"id":shown_id,"title":text(shown_id).get_slice("\n",0),"briefing":text(shown_id),"picture":"MISSSCRE/" + str(row.get("picture","piccy100")).to_upper() + ".BMP","welcome":welcome(city),"active":not active().is_empty(),"objective":objective(),"response":last_response}

func welcome(city: int) -> String:
	var raw := str(game.gameplay_catalogue.get("tables",{}).get("source_texts",{}).get("records",{}).get("english.default.txt",{}).get("text",""))
	var faction := "procker" if city in [2,4] else "refinery" if city == 6 else "bohine"
	raw = raw.get_slice("#" + faction,1).get_slice("#default",1).get_slice("#noweapons",0)
	return raw.replace("<p>","").strip_edges()


func objective() -> String:
	if active().is_empty(): return "None"
	return "Return to a city with refined thorium." if active().get("refinery",false) else "Take raw thorium to the Refinery."

func accept(city: int) -> String:
	if game.docking.stage != game.Docking.Stage.DOCKED: return "Accept missions while docked."
	if not board(city).available: return "This mission is unavailable."
	if game.save_games.write(-1,game._save_snapshot("Before Prospectors Wanted!")) != OK: return game.save_games.error
	var id: String = IDS[city]
	game.player_progress.missions.active = {"id":id,"city":city,"refinery":false}
	game.player_progress.mission = "Prospectors Wanted!"
	last_response = ""
	_spawn_opening()
	if not game.equipment.vacuum.item_collected.is_connected(_collected): game.equipment.vacuum.item_collected.connect(_collected)
	for variant in IDS.values(): game.events.mission_available.emit(variant,false)
	return ""

func docked(city: int) -> void:
	if active().is_empty(): return
	if city == 6: active().refinery = true; return
	if not active().get("refinery",false) or not IDS.has(city): return
	# Completion is docking-driven, even with no refined cargo (response 5..8).
	var response: int = {1:1,3:2,2:3,4:4}[city]
	if int(game.player_progress.cargo.get("thorium",0)) == 0: response += 4
	active()["resolved_city"] = city
	last_response = text(str(active().id),response)
	finish(true)

func finish(success: bool) -> void:
	if active().is_empty(): return
	var id := str(active().id)
	var city := int(active().get("resolved_city",active().city))
	var rewards: Dictionary = game.gameplay_catalogue.tables.get("mission_rewards",{}).get("records",{}).get(id,{})
	game.player_progress.missions.active = {}
	game.player_progress.mission = "None"
	if success:
		game.player_progress.missions.completed[id] = {"success":true,"city":city}
		game.player_progress.campaign_stage = 2
		game.player_progress.campaign_jobs += 1
		game.player_progress.status.credits += int(rewards.get("credits",0))
		game.events.mission_completed.emit(id,1.0)
	else:
		last_response = "Mission failed. You can accept the prospecting job again at a city."
		game.events.mission_failed.emit(id)
	# Retain reward reputation deltas separately from the existing coarse standing labels.
	var reputation: Dictionary = game.player_progress.missions.get("reputation",{})
	var faction := "1" if city in [1,3] else "2"
	var delta := (float(rewards.get("success",0.3)) if success else -float(rewards.get("fail",0.1))) * 0.2
	reputation[faction] = float(reputation.get(faction,0)) + delta
	var enemy := "2" if faction == "1" else "1"
	if success: reputation[enemy] = float(reputation.get(enemy,0)) + delta * float(rewards.get("enemy",-0.5))
	game.player_progress.missions["reputation"] = reputation
	_cleanup()
	outcome.play(game.game_folder,success)
	if game.dock_interface_active: game.dock_interface.rebuild()

func _session_started(_restored: bool) -> void:
	_cleanup(); last_response = ""; outcome.dismiss()
	for id in IDS.values(): game.events.mission_available.emit(id,int(game.player_progress.campaign_stage) == 1 and can_save())

func _cleanup() -> void:
	if is_instance_valid(pirate):
		game.submarine_traffic.traders.erase(pirate)
		game.cockpit_hud.map_data.actor_markers.erase(pirate.body)
		if is_instance_valid(pirate.smoke): pirate.smoke.free(); pirate.smoke = null
	pirate = null
	game.bounty_radio_queue = game.bounty_radio_queue.filter(func(entry: Dictionary) -> bool: return not entry.has("mission"))
	if is_instance_valid(game.object_population):
		for body in game.object_population.get_children():
			if body.has_meta("mission_owner") and not spawned.has(body): body.queue_free()
	for node in spawned:
		if is_instance_valid(node): node.free()
	spawned.clear()

func _spawn_opening() -> void:
	var population: Node = game.object_population
	var definitions = preload("res://object_definitions.gd")
	var offset: Vector3 = game.world_root.get_meta("database_offset",Vector3.ZERO)
	var patrol: Array[Vector3] = []; patrol.resize(5)
	var pirate_pose := Transform3D.IDENTITY
	for row in game.gameplay_catalogue.tables.get("database.objects",{}).get("records",{}).values():
		# Retail mission string table maps tradetrad to 33 (not CSV row 5).
		if int(row.get("MissionID",0)) != 33: continue
		var pose := preload("res://scenery_loader.gd").placement(row,offset)
		var definition := {}
		if int(row.get("ObjectID",-1)) == 1: definition = definitions.inert_thorium(population.thorium_types.get("thorium",definitions.THORIUM))
		elif int(row.get("AutoCreate",0)) == 1 and int(row.get("ObjectType",0)) == 64: definition = population.thorium_types.get("thorium",definitions.THORIUM)
		elif int(row.get("AutoCreate",0)) == 1 and int(row.get("ObjectType",0)) == 86: definition = population.salvage_types.get("bottletop",definitions.SALVAGE)
		elif int(row.get("ObjectID",-1)) == 2: pirate_pose = pose
		elif int(row.get("ObjectID",-1)) == 4: patrol[clampi(int(row.get("param2",0)),0,4)] = pose.origin
		if not definition.is_empty():
			var body: Node = population._create_thorium(definition,0,pose)
			if body != null: body.set_meta("mission_owner",str(active().id)); spawned.append(body)
	var model := preload("res://map_document.gd").load_model("PIRATE",game.game_folder)
	if model == null: return
	game.world_root.add_child(model); model.global_transform = pirate_pose; spawned.append(model)
	pirate = preload("res://mission_pirate.gd").install_opening(model,{})
	pirate.mission_owner = str(active().id); pirate.patrol = patrol
	game.submarine_traffic.register_vessel(pirate,game.world_root,game.game_folder)
	pirate.engagement.connect(func() -> void: _radio("ag1" if active().get("refinery",false) else "ag2","PIR"))
	pirate.destroyed.connect(func(_id: String, _attacker: String) -> void: _radio("ag3","PIR"))


func _collected(item: String) -> void:
	if active().is_empty() or item != "ore": return
	active()["collected"] = int(active().get("collected",0)) + 1
	if int(active().collected) <= 2: _radio("ag4" if int(active().collected) == 1 else "ag5","SHIP")
func _radio(code: String, portrait: String) -> void:
	if active().is_empty(): return
	var row: Dictionary = game.gameplay_catalogue.tables.get("radio_messages",{}).get("records",{}).get(code,{})
	var face: Texture2D = preload("res://docking_radio.gd").speaker_portrait(game.game_folder,portrait)
	var stream: AudioStream = preload("res://legacy_audio.gd").load_file(game.game_folder.path_join("WAVES/ENGLISH/" + code.to_upper() + ".RAW"))
	var message := {"name":"","text":str(row.get("text","")),"portrait":face,"distorted_portrait":preload("res://docking_radio.gd").speaker_portrait(game.game_folder,portrait,true),"voice":stream,"mission":str(active().id)}
	game.bounty_radio_queue.append(message)
	if game.radio_feed != null: game.radio_feed.push_message(message,game.docking.radio_static)
