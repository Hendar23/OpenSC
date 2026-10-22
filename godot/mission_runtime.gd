extends Node
## Opening campaign jobs: SC.EXE callbacks, MISSORD / MISSION1 / REWARD1.
const IDS := {1:"tradetrad",3:"tradetrad2",2:"tradetech",4:"tradetech2"}
const Rules = preload("res://mission_rules.gd")
var game: Node
var spawned: Array[Node] = []
var pirate: Node3D
var last_response := ""
var last_response_id := ""
var last_response_city := 0
var outcome: CanvasLayer
var side_jobs: Node
var target_marker: Control
var speech: AudioStreamPlayer
var testing_all_missions := false

func testing_missions() -> Array:
	return Array(IDS.values()) + Rules.IMPLEMENTED

func testing_mission_city(id: String) -> int:
	for city in IDS:
		if IDS[city] == id: return int(city)
	return Rules.offering_city(id)

func set_testing_missions(enabled: bool, persist: bool = false) -> void:
	testing_all_missions = enabled
	if game.developer_tabs != null:
		var button: Button = game.developer_tabs.get_node_or_null("System/UnlockTestingMissions")
		if button != null:
			button.set_pressed_no_signal(enabled)
			button.text = "All missions for testing: " + ("On" if enabled else "Off")
	_publish_offers()
	if game.dock_interface != null and game.dock_interface.visible: game.dock_interface.rebuild()
	if persist: game._schedule_settings_save()

func setup(context: Node) -> void:
	game = context
	add_to_group("mission_runtime")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	speech = AudioStreamPlayer.new(); speech.name = "MissionSpeech"; add_child(speech)
	speech.volume_db = preload("res://docking_radio.gd").SPEECH_VOLUME_DB
	game.events.city_docked.connect(docked)
	game.events.session_started.connect(_session_started)
	outcome = preload("res://mission_outcome.gd").new(); game.add_child(outcome)
	side_jobs = preload("res://stage_two_missions.gd").new(); add_child(side_jobs); side_jobs.runtime = self; side_jobs.game = game
	var guidance := CanvasLayer.new(); guidance.layer = 1; add_child(guidance)
	target_marker = preload("res://mission_target.gd").new(); target_marker.game = game; target_marker.jobs = side_jobs; guidance.add_child(target_marker)

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
	for marker in ["#bulletin","#rem"]: raw = raw.get_slice(marker,0)
	return _flow_text(raw,response == 0)

static func _flow_text(raw: String, has_title: bool = false) -> String:
	raw = raw.replace("\r\n","\n").replace("\r","\n").strip_edges()
	if raw.is_empty(): return ""
	var title := ""
	if has_title:
		title = raw.get_slice("\n",0).strip_edges()
		raw = raw.substr(title.length()).strip_edges()
	# Source newlines are hard-wrapping for the old display width. Only <p>
	# carries an intentional break: one for a new line, two for a paragraph.
	raw = raw.replace("\n"," ").replace("@",",")
	var spaces := RegEx.new(); spaces.compile("[\\t ]+")
	raw = spaces.sub(raw," ",true).replace("<p>","\n")
	var lines := PackedStringArray()
	for line in raw.split("\n"): lines.append(line.strip_edges())
	raw = "\n".join(lines).strip_edges()
	while raw.contains("\n\n\n"): raw = raw.replace("\n\n\n","\n\n")
	return title + ("\n\n" + raw if not raw.is_empty() else "") if has_title else raw

func board(city: int) -> Dictionary:
	var id := str(IDS.get(city,"")) if int(game.player_progress.campaign_stage) == 1 else Rules.next_offer(game.player_progress,city)
	var offers: Array[Dictionary] = []
	if testing_all_missions:
		for candidate in testing_missions():
			if city == testing_mission_city(candidate): offers.append(_board_entry(candidate))
		id = str(offers[0].id) if not offers.is_empty() else ""
	var available := not id.is_empty() and active().is_empty() and (testing_all_missions or Rules.requirement_cost(game,id,city) <= int(game.player_progress.status.credits))
	if not testing_all_missions and available: offers.append(_board_entry(id))
	if not active().is_empty(): offers.clear()
	var shown_id := str(active().id) if not active().is_empty() else id
	return _board_entry(shown_id).merged({"available":available,"welcome":welcome(city),"active":not active().is_empty(),"report":false,"response":"","offers":offers,"information":refinery_information() if city == 6 else [],"information_only":city == 6})

func _board_entry(id: String) -> Dictionary:
	var row: Dictionary = game.gameplay_catalogue.get("tables",{}).get("mission_availability",{}).get("records",{}).get(id,{})
	return {"id":id,"title":text(id).get_slice("\n",0),"briefing":text(id),"picture":"MISSSCRE/"+str(row.get("picture","piccy100")).to_upper()+".BMP"}

func refinery_information() -> Array[Dictionary]:
	# MISSION1's factory entries use the no-op 004189f0 callback: guides,
	# not campaign offers. The retail refinery has no Accept control.
	var result: Array[Dictionary] = []
	for id in ["ore","metal","pearl"]:
		var row: Dictionary = game.gameplay_catalogue.get("tables",{}).get("mission_availability",{}).get("records",{}).get(id,{})
		result.append({"id":id,"title":text(id).get_slice("\n",0),"briefing":text(id),"picture":"MISSSCRE/"+str(row.get("picture","piccy100")).to_upper()+".BMP"})
	return result

func welcome(city: int) -> String:
	var raw := str(game.gameplay_catalogue.get("tables",{}).get("source_texts",{}).get("records",{}).get("english.default.txt",{}).get("text",""))
	var faction := "procker" if city in [2,4] else "refinery" if city == 6 else "bohine"
	raw = raw.get_slice("#" + faction,1).get_slice("#default",1).get_slice("#noweapons",0)
	return _flow_text(raw)


func accept(city: int, selected_id: String = "") -> String:
	if game.docking.stage != game.Docking.Stage.DOCKED: return "Accept missions while docked."
	var offer: Dictionary = board(city)
	if not offer.available: return "This mission is unavailable."
	var id: String = str(offer.id) if selected_id.is_empty() else selected_id
	if not offer.offers.any(func(entry: Dictionary) -> bool: return entry.id == id): return "This mission is unavailable at this station."
	if game.save_games.write(-1,game._save_snapshot("Before " + text(id).get_slice("\n",0))) != OK: return game.save_games.error
	game.player_progress.missions.active = {"id":id,"city":city,"refinery":false}
	game.player_progress.mission = text(id).get_slice("\n",0)
	last_response = ""
	last_response_id = ""
	outcome.dismiss()
	if Rules.IMPLEMENTED.has(id):
		if Rules.PAIRED.has(id):
			var unavailable: Array = game.player_progress.missions.get("unavailable",[])
			if not unavailable.has(Rules.PAIRED[id]): unavailable.append(Rules.PAIRED[id])
			game.player_progress.missions["unavailable"] = unavailable
		side_jobs.start(id)
	else:
		_spawn_opening()
		if not game.equipment.vacuum.item_collected.is_connected(_collected): game.equipment.vacuum.item_collected.connect(_collected)
	_publish_offers()
	return ""

func docked(city: int) -> void:
	if active().is_empty(): return
	if Rules.IMPLEMENTED.has(str(active().id)): side_jobs.docked(city); return
	if city == 6: active().refinery = true; return
	if not active().get("refinery",false) or not IDS.has(city): return
	# Completion is docking-driven, even with no refined cargo (response 5..8).
	var response: int = {1:1,3:2,2:3,4:4}[city]
	if int(game.player_progress.cargo.get("thorium",0)) == 0: response += 4
	active()["resolved_city"] = city
	last_response = text(str(active().id),response)
	finish(true)

func finish(success: bool, score: float = -1.0, response: int = 0) -> void:
	if active().is_empty(): return
	var id := str(active().id)
	last_response_id = id
	var city := int(active().get("resolved_city",active().city))
	last_response_city = city
	var side_job := Rules.IMPLEMENTED.has(id)
	var outcome_shown := bool(active().get("outcome_shown",false))
	if score < 0: score = 1.0 if success else 0.0
	if response > 0: last_response = text(id,response)
	var rewards: Dictionary = game.gameplay_catalogue.tables.get("mission_rewards",{}).get("records",{}).get(id,{})
	game.player_progress.missions.active = {}
	game.player_progress.mission = "None"
	if success or side_job:
		game.player_progress.missions.completed[id] = {"success":success,"city":city,"score":score}
	if side_job:
		game.player_progress.missions["stage2_resolved"] = int(game.player_progress.missions.get("stage2_resolved",0)) + 1
		if success: game.player_progress.missions["stage2_successes"] = int(game.player_progress.missions.get("stage2_successes",0)) + 1
	if success:
		if not side_job: game.player_progress.campaign_stage = 2
		game.player_progress.campaign_jobs += 1
		# 0041ec40 pays the fixed REWARD1 amount; score selects bulletins,
		# rather than scaling the credit reward.
		game.player_progress.status.credits += int(rewards.get("credits",0))
		game.events.mission_completed.emit(id,score)
	else:
		if response == 0: last_response = "Mission failed." if side_job else "Mission failed. You can accept the prospecting job again at a city."
		if side_job: preload("res://mailbox.gd").mission_completed(game.player_progress,id,score)
		game.events.mission_failed.emit(id)
	# Retain reward reputation deltas separately from the existing coarse standing labels.
	var reputation: Dictionary = game.player_progress.missions.get("reputation",{})
	var faction := "1" if city in [1,3] else "2"
	var delta := (float(rewards.get("success",0.3)) if success else -float(rewards.get("fail",0.1))) * 0.2
	reputation[faction] = float(reputation.get(faction,0)) + delta
	var enemy := "2" if faction == "1" else "1"
	if success: reputation[enemy] = float(reputation.get(enemy,0)) + delta * float(rewards.get("enemy",-0.5))
	game.player_progress.missions["reputation"] = reputation
	if side_jobs.fishing != null: preload("res://mission_survivors.gd").release(side_jobs,side_jobs.fishing.enemies)
	if side_jobs.remaining != null: preload("res://mission_survivors.gd").release(side_jobs,side_jobs.remaining.enemies)
	_cleanup(true)
	_publish_offers()
	if not outcome_shown or not success: outcome.play(game.game_folder,success)
	if game.dock_interface_active: game.dock_interface.rebuild()

func _session_started(_restored: bool) -> void:
	if speech != null: speech.stop()
	_cleanup(); last_response = ""; last_response_id = ""; outcome.dismiss()
	preload("res://campaign_resources.gd").restore_for_progress(game)
	_publish_offers()

func _publish_offers() -> void:
	for id in Array(IDS.values()) + Rules.IMPLEMENTED:
		var available: bool = can_save() and (testing_all_missions or (id in IDS.values() and int(game.player_progress.campaign_stage) == 1) or (id in Rules.IMPLEMENTED and Rules.next_offer(game.player_progress,Rules.offering_city(id)) == id))
		game.events.mission_available.emit(id,available)

func _cleanup(preserve_rover: bool = false) -> void:
	if side_jobs != null: side_jobs.clear(not preserve_rover)
	if is_instance_valid(pirate):
		game.submarine_traffic.traders.erase(pirate)
		game.cockpit_hud.map_data.actor_markers.erase(pirate.body)
		if is_instance_valid(pirate.smoke): pirate.smoke.free(); pirate.smoke = null
	pirate = null
	game.bounty_radio_queue = game.bounty_radio_queue.filter(func(entry: Dictionary) -> bool: return not entry.has("mission") or entry.get("terminal",false))
	if is_instance_valid(game.object_population):
		for body in game.object_population.get_children():
			if body.has_meta("mission_owner") and not spawned.has(body): body.queue_free()
	for node in spawned:
		if is_instance_valid(node): node.free()
	spawned.clear()

func _spawn_opening() -> void:
	preload("res://campaign_resources.gd").spawn_opening_bonus(game)
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
	if Rules.IMPLEMENTED.has(str(active().id)): return
	active()["collected"] = int(active().get("collected",0)) + 1
	if int(active().collected) <= 2: _radio("ag4" if int(active().collected) == 1 else "ag5","SHIP")
func _radio(code: String, portrait: String, terminal: bool = false) -> void:
	if active().is_empty(): return
	var row: Dictionary = game.gameplay_catalogue.tables.get("radio_messages",{}).get("records",{}).get(code,{})
	var face: Texture2D = preload("res://docking_radio.gd").speaker_portrait(game.game_folder,portrait)
	var stream: AudioStream = preload("res://legacy_audio.gd").load_file(game.game_folder.path_join("WAVES/ENGLISH/" + code.to_upper() + ".RAW"))
	var message := {"speaker":"ship" if portrait.to_upper() == "SHIP" else "mission/" + str(active().id) + "/" + portrait.to_lower(),"name":"","text":str(row.get("text","")),"portrait":face,"distorted_portrait":preload("res://docking_radio.gd").speaker_portrait(game.game_folder,portrait,true),"voice":stream,"mission":str(active().id)}
	# Mission text is displayed immediately, including beside a drop-off prompt.
	# Play its speech at the same time; completion cleanup removes queued mission
	# messages and must not discard the final voice before it has even started.
	if stream != null:
		speech.stop(); speech.stream = stream; speech.play(); message["voice_played"] = true
	game.bounty_radio_queue.append(message)
	if terminal: message["terminal"] = true
	if game.radio_feed != null: game.radio_feed.push_message(message,game.docking.radio_static)
