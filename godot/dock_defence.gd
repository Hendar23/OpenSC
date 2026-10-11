extends Node3D

# DOCKINGSPHERE callback 0x44c610, targeting predicate 0x44e920.
const TICK_RATE := 25.0
const RANGE := 3.0
const DAMAGE := 3.0 * preload("res://submarine_weapons.gd").DEFAULTS.damage_per_tick
const SEARCH_CENTER := Vector3(0,3.1,0)
const EMITTERS := [Vector3(0,1.68,1.93),Vector3(1.93,1.68,0),Vector3(-1.93,1.68,0)]
var population: Node3D
var ports: Array[Dictionary] = []
var clock := 0.0
var damage_per_tick := DAMAGE

func setup(world: Node3D, wildlife: Node3D) -> void:
	population = wildlife
	for node in world.find_children("*","Node3D",true,false):
		if not node.has_meta("city_id"): continue
		ports.append({"node":node,"target":null,"arcs":[],"sound":null})

static func eligible(fish: Node3D) -> bool:
	return is_instance_valid(fish) and not fish.is_queued_for_deletion() and not fish.dead and fish.is_physics_processing() and fish.get_meta("wildlife_awake",true) and not fish.get_meta("dock_zapper_immune",false) and int(fish.get_meta("original_object_id",0)) != 73 and str(fish.get_meta("species","")).to_lower() != "taggedfish"

func _target(port: Node3D) -> Node3D:
	var center := port.to_global(SEARCH_CENTER)
	var nearest := INF
	var selected: Node3D
	# The original sphere query includes each target's body radius. This small
	# capped population scan avoids querying colliders belonging to the dock.
	for fish in population.get_children():
		if not eligible(fish): continue
		var distance := center.distance_squared_to(fish.global_position)
		if distance >= pow(RANGE + fish.radius,2) or distance >= nearest: continue
		nearest = distance; selected = fish
	return selected

func _physics_process(delta: float) -> void:
	if not is_instance_valid(population): return
	if not population.simulating:
		clock = 0.0
		for state in ports: _stop(state)
		return
	clock += maxf(0.0,delta) * TICK_RATE
	while clock >= 1.0 - 0.000001:
		clock = maxf(0.0,clock - 1.0)
		for state in ports:
			if not is_instance_valid(state.node): continue
			state.target = _target(state.node)
			if eligible(state.target): preload("res://original_damage.gd").weapon(state.target,damage_per_tick,state.node.global_position)
	for state in ports:
		if not is_instance_valid(state.node) or not eligible(state.target): _stop(state)
		else: _show(state)

func _show(state: Dictionary) -> void:
	# Aquatraz (city 5) applies damage but has no ordinary dock spike arcs.
	if int(state.node.get_meta("city_id")) == 5: return
	if state.arcs.is_empty():
		for point in EMITTERS:
			var arc := preload("res://submarine_weapons.gd").create_arc(state.node,population.zapper_frames)
			add_child(arc); arc.set_physics_process(false); state.arcs.append(arc)
		var sound := AudioStreamPlayer3D.new(); sound.stream = population.zapper_sound
		sound.unit_size = 3; sound.max_distance = 30; add_child(sound); state.sound = sound
	for index in range(state.arcs.size()):
		var arc: Node3D = state.arcs[index]
		arc.camera = get_viewport().get_camera_3d()
		arc.firing = arc.camera != null and not arc.frames.is_empty()
		arc.beam.visible = arc.firing
		arc.beam_start = state.node.to_global(EMITTERS[index]); arc.beam_end = state.target.global_position
	var sound: AudioStreamPlayer3D = state.sound
	sound.global_position = state.node.to_global(SEARCH_CENTER)
	preload("res://explosion_audio.gd").apply(sound,0.0,"wildlife_zapper_volume")
	if sound.stream != null and not sound.playing: sound.play()

func _stop(state: Dictionary) -> void:
	state.target = null
	for arc in state.arcs: arc.firing = false; arc.beam.hide()
	if state.sound != null: state.sound.stop()
