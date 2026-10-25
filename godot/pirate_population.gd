extends Node3D
signal transmission(message: Dictionary)
## Two persistent slots; replacements are relocated into unseen open water.
const MAX_PIRATES := 2
const Pirate = preload("res://pirate_submarine.gd")
const TAUNTS := [
	"You're in the wrong waters, mate!",
	"You've got something we want!",
	"You're going down!",
	"Say goodbye to your sub!",
	"You should've stayed at home!",
	"We're taking everything you've got!",
	"You're easy pickings!",
	"That sub's scrap!",
	"You won't get away!",
	"Prepare to be sunk!",
	"Your cargo belongs to us!",
	"Let's see how tough you are!",
	"You're about to spring a leak!",
	"Nothing personal, just business!",
	"We've been waiting for you!",
	"You're not getting out of this one!",
	"Time to feed the fishes!",
	"Nice sub. Shame about the owner!",
	"Should've brought some backup!",
	"Let's see what you've got!",
	"You're swimming home!",
	"Dump the cargo and we might let you swim!",
	"That salvage belongs to us!",
	"Fresh meat!",
	"Wrong part of the ocean, pal!",
	"You’re in our water now!",
	"Another sucker!",
]
var traffic: Node
var ships: Array[Node3D] = []
var retry := 0.0
var random := RandomNumberGenerator.new()
var portrait: Texture2D
var distorted_portrait: Texture2D

func setup(manager: Node, folder: String, document: Dictionary) -> void:
	traffic = manager; random.randomize()
	portrait = preload("res://docking_radio.gd").speaker_portrait(folder,"pir")
	distorted_portrait = preload("res://docking_radio.gd").speaker_portrait(folder,"pir",true)
	for index in range(MAX_PIRATES):
		var id := "PIRATE" # Yellow hull for random encounters.
		var values := Pirate.PIRATE_DEFAULTS.duplicate()
		for type in document.get("npc_types",[]):
			if type.get("family") == "pirate" and type.get("model") == id:
				values.merge(type,true); break
		values.npc_respawn = false
		var model := preload("res://map_document.gd").load_model(id,folder)
		if model == null: continue
		model.name = "Pirate_%d" % (index + 1); add_child(model)
		preload("res://entity_identity.gd").assign_id(model,"population/pirates/%d" % index)
		var agent := Pirate.install_pirate(model,values); agent.roaming = true
		traffic.register_vessel(agent,get_parent(),folder)
		agent.player_attack_started.connect(_taunt.bind(agent))
		ships.append(agent)
		# Hidden until a safe first placement is found.
		agent.dead = true; model.hide(); agent.body.collision_layer = 0
	reset_population()

func _taunt(agent: Node3D) -> void:
	if attacks_suppressed(): return
	var line: String = TAUNTS[random.randi_range(0,TAUNTS.size()-1)]
	transmission.emit({"speaker":preload("res://entity_identity.gd").of(agent),"text":"PIRATE : "+line,"portrait":portrait,"distorted_portrait":distorted_portrait})

func attacks_suppressed() -> bool:
	# Derive this from the active encounter so completion, failure and session
	# reset resume ambient attacks without leaving a saved/global toggle behind.
	var mission := get_tree().get_first_node_in_group("mission_runtime")
	return mission != null and str(mission.active().get("id","")) == "minefield"

func reset_population() -> void:
	for agent in ships:
		agent.dead = true; agent.get_parent().hide(); agent.body.collision_layer = 0
	for agent in ships: replace(agent)

func replenish_docked(delta: float) -> void:
	# Called by the game only while the docked UI hides the world.
	if not traffic.navigation_ready: return
	retry = maxf(0,retry - delta)
	if retry > 0: return
	for agent in ships:
		if agent.dead and agent.mission_owner.is_empty() and not replace(agent): retry = 1.0

func replace(agent: Node3D) -> bool:
	var ids: PackedInt64Array = traffic.graph.get_point_ids()
	if ids.is_empty(): return false
	var camera := get_viewport().get_camera_3d()
	for attempt in range(256):
		var point: Vector3 = traffic.graph.get_point_position(ids[random.randi_range(0,ids.size()-1)])
		if is_instance_valid(traffic.player) and point.distance_squared_to(traffic.player.global_position) < 6400: continue
		if camera != null and camera.is_position_in_frustum(point): continue
		var crowded := false
		for other in traffic.traders:
			if other != agent and not other.dead and point.distance_squared_to(other.global_position) < 25: crowded = true; break
		if crowded or not traffic.water_clear(point): continue
		agent.home.origin = point; agent.home.basis = Basis(Vector3.UP,random.randf_range(-PI,PI))
		agent.reset(); agent.running = traffic.simulating
		return true
	return false
