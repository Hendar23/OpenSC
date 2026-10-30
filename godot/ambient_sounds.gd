extends Node
## Recovered outdoor sound sources. Selection is bounded and distance-based;
## no ambient timer invents playback for samples without a recovered trigger.
const Audio = preload("res://legacy_audio.gd")
const Loop = preload("res://audio_loop.gd")
const RANGE := 7.5 # 00409d60, camera-to-source distance.
const FACTORY_RANGE := sqrt(1000.0) # 00451790, refinery drop point.
const MAX_VOICES := 12
const VOLUME_SCALE := 0.375
const ENGINE_VOLUME_SCALE := 0.5
const SAMPLES := ["FACTAMB1","BUBBLES","SCREEN1","TRADENG","TECHENG","PIRATENG","INSUB2"]
const SWIMMERS := ["jackfish","lionfish","dogfish","angler","baracuda","piranha","seahorse","stingray","smalleel","meel","bigeel","blowfish","elver","badnasty","baby","mutant","mjack","badjelly","kidjelly","momjelly"]
var game: Node3D
var streams := {}
var voices := {}
var clock := 0.0

func setup(context: Node3D, folder: String) -> void:
	game = context
	for sample in SAMPLES:
		streams[sample] = Loop.prepare(Audio.load_file(folder.path_join("WAVES/"+sample+".RAW")),sample in ["FACTAMB1","TRADENG","TECHENG","INSUB2"])

func allowed() -> bool:
	return is_instance_valid(game) and not get_tree().paused and not game.front_end.menu_layer.visible and game.has_started_game and game.pilot_mode and not game.world_loading and not game.loading_save and not game.loading_canvas.visible and not game.pilot.dead and game.docking.stage != game.Docking.Stage.DOCKED and (game.photo_mode == null or not game.photo_mode.active)

func _physics_process(delta: float) -> void:
	if not allowed():
		silence(); return
	# Follow moving engines and fade between the ten-Hz source scans.
	for voice: AudioStreamPlayer3D in voices.values():
		_update_voice(voice)
	clock -= delta
	if clock > 0: return
	clock = 0.1
	refresh()

func silence() -> void:
	for voice: AudioStreamPlayer3D in voices.values(): voice.free()
	voices.clear(); clock = 0.0

static func level(distance: float) -> float:
	# DirectSound hundredths of a dB: min(-1, 5000 - distance*1000).
	return minf(-0.01,50.0-distance*10.0)

static func factory_level(distance: float) -> float:
	# Fade throughout the range: the refinery beside the defector otherwise
	# masks the ship's engine with a steady hum across its broad inner plateau.
	var gain := 1.0-smoothstep(0.0,FACTORY_RANGE,distance)
	return level(0.0)+linear_to_db(maxf(0.0001,gain))

static func engine_level(distance: float) -> float:
	var gain := ENGINE_VOLUME_SCALE*(1.0-smoothstep(0.0,RANGE,distance))
	return linear_to_db(maxf(0.0001,gain))

func _update_voice(voice: AudioStreamPlayer3D) -> void:
	var source: Node3D = voice.get_meta("source").get_ref()
	if not is_instance_valid(source): return
	voice.global_position = source.global_position
	var factory: bool = voice.stream == streams.get("FACTAMB1")
	var listener: Vector3 = game.pilot.global_position if factory or voice.get_meta("npc_engine",false) else game.camera.global_position
	var distance := listener.distance_to(voice.global_position)
	var volume := factory_level(distance) if factory else engine_level(distance) if voice.get_meta("npc_engine",false) else level(distance)
	voice.volume_db = volume+linear_to_db(VOLUME_SCALE)

func refresh() -> void:
	var camera: Camera3D = game.camera
	var candidates: Array[Dictionary] = []
	for source: Node3D in get_tree().get_nodes_in_group("ambient_factories"):
		var distance := source.global_position.distance_to(game.pilot.global_position)
		if distance < FACTORY_RANGE:
			candidates.append({"node":source,"sample":"FACTAMB1","distance":distance,"priority":0})
	for source: Node3D in get_tree().get_nodes_in_group("ambient_bubbles"):
		if source.enabled: _candidate(candidates,source,"BUBBLES",camera.global_position,1)
	for agent: Node3D in game.submarine_traffic.traders:
		if not is_instance_valid(agent) or agent.dead or not agent.running or not agent.get_parent().is_visible_in_tree() or agent.stage == "berth": continue
		var model := preload("res://trader_submarine.gd").model_id(agent.get_parent())
		_candidate(candidates,agent,vessel_sample(model,int(agent.tuning.npc_faction)),game.pilot.global_position,1,true)
	for vehicle: Node3D in game.ground_traffic.vehicles:
		if is_instance_valid(vehicle) and not vehicle.dead and vehicle.running:
			_candidate(candidates,vehicle,"TECHENG" if int(vehicle.tuning.npc_faction) == 2 else "TRADENG",game.pilot.global_position,1,true)
	for group in ["player_projectiles","turret_missiles"]:
		for shot: Node3D in get_tree().get_nodes_in_group(group):
			if group == "player_projectiles" and (shot.kind == "electro" or shot.out_of_fuel or shot.spent): continue
			_candidate(candidates,shot,"INSUB2",camera.global_position,1)
	if is_instance_valid(game.wildlife):
		for fish: Node3D in game.wildlife.nearby_creatures(camera.global_position,RANGE):
			if fish.dead or not fish.get_meta("wildlife_awake",true) or not fish.is_visible_in_tree() or str(fish.get_meta("sound_model","")) not in SWIMMERS: continue
			_candidate(candidates,fish,"SCREEN1",camera.global_position,2)
	for actor: Node in game.mission_runtime.side_jobs.actors:
		if not is_instance_valid(actor) or not actor.is_in_group("marine_life") or actor.dead or not actor.is_visible_in_tree(): continue
		if str(actor.get_meta("sound_model","")) in SWIMMERS: _candidate(candidates,actor,"SCREEN1",camera.global_position,2)
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.priority < b.priority or (a.priority == b.priority and a.distance < b.distance))
	var retained := {}; var counts := {}
	for entry in candidates:
		if retained.size() >= MAX_VOICES: break
		# A shoal can contain hundreds of fish. Reuse a few nearest voices,
		# rather than allocating one audio node per member of the population.
		if entry.sample == "SCREEN1" and int(counts.get(entry.sample,0)) >= 4: continue
		if streams.get(entry.sample) == null: continue
		var key: int = entry.node.get_instance_id()
		retained[key] = true; counts[entry.sample] = int(counts.get(entry.sample,0))+1
		var voice: AudioStreamPlayer3D = voices.get(key)
		if voice == null:
			voice = AudioStreamPlayer3D.new(); voice.name = str(entry.sample)
			voice.stream = streams[entry.sample]; voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
			voice.max_distance = 0; voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
			add_child(voice); voices[key] = voice
		voice.set_meta("source",weakref(entry.node)); voice.set_meta("npc_engine",entry.get("npc_engine",false))
		_update_voice(voice)
		if not voice.playing: voice.play()
	for key in voices.keys():
		if not retained.has(key): voices[key].free(); voices.erase(key)

static func vessel_sample(model: String, faction: int) -> String:
	if model in ["TRADSHUT","TECHSHUT","TRADHERD","TECHHERD","STARSHIP"]: return "INSUB2"
	if model == "CARAVAN": return "TECHENG"
	if model == "FREIGHT": return "TRADENG"
	return "PIRATENG" if faction == 3 else "TECHENG" if faction == 2 else "TRADENG"

func _candidate(list: Array[Dictionary], source: Node3D, sample: String, listener: Vector3, priority: int, npc_engine: bool = false) -> void:
	var distance := listener.distance_to(source.global_position)
	if distance < RANGE: list.append({"node":source,"sample":sample,"distance":distance,"priority":priority,"npc_engine":npc_engine})
